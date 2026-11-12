/**
 * Where an agent is working: the app and the session it's in, as the stdio bridge sees them. Perch uses
 * it to link a proposal (or an agent in the notch) back to the conversation it came from.
 *
 * The bridge sends it as an `X-Perch-Session` header, base64url-encoded JSON. Only these fields are kept,
 * each a short string; anything else the header carries is dropped.
 */
export interface AgentOrigin {
  /** "claude-desktop", "claude-code" (a terminal), or "codex". */
  app?: string;
  /** The Claude desktop session: local_<id>. */
  session?: string;
  /** The Claude Code conversation id. */
  conversation?: string;
  /** The Codex thread id. */
  thread?: string;
  /** The folder the agent is working in. */
  folder?: string;
}

const FIELDS = ["app", "session", "conversation", "thread", "folder"] as const;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOCAL_SESSION = /^local_[A-Za-z0-9-]{1,64}$/;

export function readOrigin(header: string | string[] | undefined): AgentOrigin | undefined {
  if (typeof header !== "string" || !header || header.length > 2000) return undefined;
  let value: unknown;
  try {
    value = JSON.parse(Buffer.from(header, "base64url").toString("utf8"));
  } catch {
    return undefined;
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const origin: AgentOrigin = {};
  for (const key of FIELDS) {
    const field = (value as Record<string, unknown>)[key];
    if (field === undefined) continue;
    if (typeof field !== "string" || field.length > 300 || /[\u0000-\u001f]/.test(field)) return undefined;
    origin[key] = field;
  }
  return Object.keys(origin).length ? origin : undefined;
}

/**
 * A link that opens the session in its app, for the apps that have one: a Claude desktop session
 * (Claude's app opens `claude://code/continue?session=local_...`) and a Codex thread. Claude Code in a
 * terminal has none, so its proposals carry no link.
 */
export function sessionLink(origin: AgentOrigin | undefined): string | undefined {
  if (!origin) return undefined;
  if (origin.app === "claude-desktop" && origin.session && LOCAL_SESSION.test(origin.session)) {
    return `claude://code/continue?session=${origin.session}`;
  }
  if (origin.app === "codex" && origin.thread && UUID.test(origin.thread)) {
    return `codex://threads/${origin.thread}`;
  }
  return undefined;
}

/** Now, as a local time with its offset (2026-11-10T12:14:05-06:00), for task files people read. */
export function localTimestamp(date = new Date()): string {
  const pad = (n: number) => String(Math.trunc(Math.abs(n))).padStart(2, "0");
  const offset = -date.getTimezoneOffset();
  const sign = offset >= 0 ? "+" : "-";
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}` +
    `${sign}${pad(offset / 60)}:${pad(offset % 60)}`;
}
