// Mirrors PerchKit's Swift task format byte for byte, so the app and the Relay agree.
import { createHash, randomInt } from "node:crypto";

export const jsTrim = (text: string) => text.trim();

export function blobID(data: Buffer | string): string {
  const bytes = typeof data === "string" ? Buffer.from(data, "utf8") : data;
  return createHash("sha1").update(`blob ${bytes.length}\0`).update(bytes).digest("hex");
}

const PLAIN = /^[A-Za-z0-9][A-Za-z0-9 _./+-]*$/;

export function quoteIfNeeded(value: string): string {
  if (PLAIN.test(value) && value === value.trim()) return value;
  return JSON.stringify(value);
}

export function unquote(value: string): string {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    try {
      return JSON.parse(value);
    } catch {
      return value.slice(1, -1);
    }
  }
  if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) return value.slice(1, -1).replaceAll("''", "'");
  return value;
}

/** Splits `---` frontmatter from the body without changing any bytes. */
export function splitDocument(text: string): { raw: string; body: string } {
  const lines = text.split("\n");
  const clean = (line: string) => line.replace(/\r$/, "");
  if (lines.length < 2 || clean(lines[0]) !== "---") return { raw: "", body: text };
  let offset = lines[0].length + 1;
  for (let index = 1; index < lines.length; index++) {
    const end = offset + lines[index].length + (index < lines.length - 1 ? 1 : 0);
    if (clean(lines[index]) === "---") return { raw: text.slice(0, end), body: text.slice(end) };
    offset = end;
  }
  return { raw: "", body: text };
}

type Entry = { key: string | null; raw: string };

export class Fields {
  entries: Entry[] = [];

  static parse(raw: string): Fields {
    const fields = new Fields();
    if (!raw) return fields;
    const lines = raw.split("\n");
    if (lines[lines.length - 1] === "") lines.pop();
    for (const line of lines.slice(1, -1)) {
      const cleaned = line.replace(/\r$/, "");
      fields.entries.push({ key: Fields.keyOf(cleaned), raw: cleaned });
    }
    return fields;
  }

  private static keyOf(line: string): string | null {
    if (!line || " \t#-".includes(line[0])) return null;
    const colon = line.indexOf(":");
    if (colon < 0) return null;
    if (colon + 1 < line.length && line[colon + 1] !== " ") return null;
    return line.slice(0, colon);
  }

  get(key: string): string | undefined {
    const entry = this.entries.find((e) => e.key === key);
    if (!entry) return undefined;
    const value = entry.raw.slice(key.length + 1).trim();
    return value ? unquote(value) : undefined;
  }

  list(key: string): string[] {
    const index = this.entries.findIndex((e) => e.key === key);
    if (index < 0) return [];
    const value = this.entries[index].raw.slice(key.length + 1).trim();
    if (value.startsWith("[") && value.endsWith("]")) {
      return value.slice(1, -1).split(",").map((v) => unquote(v.trim())).filter(Boolean);
    }
    if (value) return [unquote(value)];
    const items: string[] = [];
    for (const entry of this.entries.slice(index + 1)) {
      const trimmed = entry.raw.trim();
      if (entry.key !== null || !trimmed.startsWith("- ")) break;
      items.push(unquote(trimmed.slice(2).trim()));
    }
    return items;
  }

  set(key: string, value: string | undefined | null) {
    const index = this.entries.findIndex((e) => e.key === key);
    const replacement = value === undefined || value === null ? null : `${key}: ${quoteIfNeeded(value)}`;
    if (index >= 0) {
      if (replacement) this.entries[index] = { key, raw: replacement };
      else {
        this.entries.splice(index, 1);
        while (index < this.entries.length && this.entries[index].key === null && this.entries[index].raw.trim().startsWith("- ")) {
          this.entries.splice(index, 1);
        }
      }
    } else if (replacement) {
      this.entries.push({ key, raw: replacement });
    }
  }

  setList(key: string, values: string[]) {
    this.set(key, null);
    if (values.length) this.entries.push({ key, raw: `${key}: [${values.map(quoteIfNeeded).join(", ")}]` });
  }

  get raw(): string {
    return ["---", ...this.entries.map((e) => e.raw), "---"].join("\n") + "\n";
  }
}

export interface Activity {
  date: string;
  author: string;
  text: string;
}

export interface Task {
  id: string;
  path: string;
  title: string;
  status: "open" | "done" | "cancelled";
  owner?: string;
  due?: string;
  time?: string;
  deadline?: string;
  repeat?: string;
  remind: string[];
  priority: number;
  labels: string[];
  parent?: string;
  duration?: number;
  created?: string;
  completed?: string;
  source?: string;
  proposed_done_by?: string;
  proposed_done_reason?: string;
  /** When the agent proposed it, local time with offset. */
  proposed_done_at?: string;
  /** A link back to the session the proposal came from. */
  proposed_done_from?: string;
  /** What the agent said it was doing at the time. */
  proposed_done_while?: string;
  details: string;
  activity: Activity[];
  extra: Fields;
}

const MANAGED = [
  "id", "title", "status", "owner", "due", "time", "deadline", "repeat", "remind", "priority",
  "labels", "parent", "duration", "created", "completed", "source", "proposed_done_by", "proposed_done_reason",
  "proposed_done_at", "proposed_done_from", "proposed_done_while",
];

export function taskArea(path: string): string {
  const parts = path.split("/");
  const index = parts.lastIndexOf("Tasks");
  return index > 0 ? parts.slice(0, index).join("/") : parts[0];
}

export function isTaskPath(path: string): boolean {
  const parts = path.split("/");
  return path.toLowerCase().endsWith(".md") && !path.toLowerCase().endsWith(".kanban.md") && parts.length >= 2 && parts[parts.length - 2] === "Tasks";
}

export function decodeTask(path: string, text: string): Task | null {
  const { raw, body } = splitDocument(text);
  const fields = Fields.parse(raw);
  const id = fields.get("id");
  const status = fields.get("status");
  if (!id || !status || !["open", "done", "cancelled"].includes(status)) return null;
  const lines = body.split("\n");
  let heading = -1;
  for (let i = lines.length - 1; i >= 0; i--) if (lines[i].trim() === "## Activity") { heading = i; break; }
  const trimEnd = (s: string) => s.replace(/[\r\n]+$/, "");
  let details = trimEnd(body);
  const activity: Activity[] = [];
  if (heading >= 0) {
    details = trimEnd(lines.slice(0, heading).join("\n"));
    const pattern = /^- (\d{4}-\d{2}-\d{2}[^ ]*) @([^:\s]+): (.*)$/;
    for (const line of lines.slice(heading + 1)) {
      const match = pattern.exec(line);
      if (match) activity.push({ date: match[1], author: match[2], text: match[3] });
      else if (line.startsWith("  ") && activity.length) activity[activity.length - 1].text += "\n" + line.slice(2);
      else if (line.trim()) activity.push({ date: "", author: "note", text: line });
    }
  }
  const number = (value?: string) => (value && /^-?\d+$/.test(value) ? Number(value) : undefined);
  return {
    id, path, title: fields.get("title") ?? path.split("/").pop()!.replace(/\.md$/i, ""),
    status: status as Task["status"], owner: fields.get("owner"), due: fields.get("due"), time: fields.get("time"),
    deadline: fields.get("deadline"), repeat: fields.get("repeat"), remind: fields.list("remind"),
    priority: number(fields.get("priority")) ?? 4, labels: fields.list("labels"), parent: fields.get("parent"),
    duration: number(fields.get("duration")), created: fields.get("created"), completed: fields.get("completed"),
    source: fields.get("source"), proposed_done_by: fields.get("proposed_done_by"),
    proposed_done_reason: fields.get("proposed_done_reason"), proposed_done_at: fields.get("proposed_done_at"),
    proposed_done_from: fields.get("proposed_done_from"), proposed_done_while: fields.get("proposed_done_while"),
    details, activity, extra: fields,
  };
}

export function encodeTask(task: Task): string {
  const fields = Fields.parse(task.extra.raw === "---\n---\n" ? "" : task.extra.raw);
  for (const key of MANAGED) fields.set(key, null);
  fields.set("id", task.id);
  fields.set("title", task.title);
  fields.set("status", task.status);
  fields.set("owner", task.owner);
  fields.set("due", task.due);
  fields.set("time", task.time);
  fields.set("deadline", task.deadline);
  fields.set("repeat", task.repeat);
  fields.setList("remind", task.remind);
  fields.set("priority", task.priority === 4 ? null : String(task.priority));
  fields.setList("labels", task.labels);
  fields.set("parent", task.parent);
  fields.set("duration", task.duration === undefined ? null : String(task.duration));
  fields.set("created", task.created);
  fields.set("completed", task.completed);
  fields.set("source", task.source);
  fields.set("proposed_done_by", task.proposed_done_by);
  fields.set("proposed_done_reason", task.proposed_done_reason);
  fields.set("proposed_done_at", task.proposed_done_at);
  fields.set("proposed_done_from", task.proposed_done_from);
  fields.set("proposed_done_while", task.proposed_done_while);
  let body = task.details;
  if (task.activity.length) {
    if (body) body += "\n\n";
    body += "## Activity\n\n";
    body += task.activity
      .map((a) => {
        const [first, ...rest] = a.text.split("\n");
        return [`- ${a.date} @${a.author}: ${first}`, ...rest.map((l) => `  ${l}`)].join("\n");
      })
      .join("\n");
  }
  if (body && !body.endsWith("\n")) body += "\n";
  return fields.raw + body;
}

export function newTask(path: string, id: string, title: string): Task {
  return { id, path, title, status: "open", remind: [], priority: 4, labels: [], details: "", activity: [], extra: new Fields() };
}

const ALPHABET = "23456789abcdefghjkmnpqrstuvwxyz";
export const makeTaskID = () => "t" + Array.from({ length: 7 }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");

export function taskFileName(title: string, id: string): string {
  let cleaned = title.replace(/[/\\:*?"<>|#%[\]^\n\r\t]/g, " ").split(" ").filter(Boolean).join(" ");
  cleaned = cleaned.replace(/^\.+/, "");
  const graphemes = [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(cleaned)].map((s) => s.segment);
  if (graphemes.length > 80) cleaned = graphemes.slice(0, 80).join("").trim();
  cleaned = cleaned.replace(/\.+$/, "");
  return `${cleaned || "Task"} ${id}.md`;
}

export const today = (date = new Date()) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
