// Two agents working in a TEST notebook at once, so you can watch presence, claims and proposals.
// Usage: node scripts/demo.mjs <tokens-file> [relay-url]
// The tokens file has one "<agent> <token>" line each for robin and claude-code.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { readFileSync } from "node:fs";

const [tokensFile, base = "http://127.0.0.1:8787"] = process.argv.slice(2);
if (!tokensFile) throw new Error("Usage: node scripts/demo.mjs <tokens-file> [relay-url]");
const tokens = Object.fromEntries(readFileSync(tokensFile, "utf8").trim().split("\n").map((l) => l.split(" ")));
const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));

async function agent(name) {
  const client = new Client({ name, version: "demo" });
  await client.connect(new StreamableHTTPClientTransport(new URL(`${base}/mcp`), {
    requestInit: { headers: { Authorization: `Bearer ${tokens[name]}` } },
  }));
  return async (tool, args = {}) => {
    const result = await client.callTool({ name: tool, arguments: args });
    const data = JSON.parse(result.content[0].text);
    if (result.isError) console.log(`  ${name} ✗ ${data.error}`);
    return data;
  };
}

const say = (who, text) => console.log(`${new Date().toLocaleTimeString()}  ${who.padEnd(12)} ${text}`);
const robin = await agent("robin");
const claude = await agent("claude-code");

// The demo works in the notebook's first area, whatever it is called.
const { areas } = await robin("guide");
const area = areas[0];

say("robin", `is here: reviewing today's tasks in ${area}`);
await robin("presence", { status: `Reviewing today's tasks in ${area}` });
await sleep(4);
say("claude-code", "is here: drafting a weekly summary");
await claude("presence", { status: "Drafting a weekly summary" });
await sleep(4);

const today = await robin("tasks_list", { view: "today", area, limit: 200 });
say("robin", `found ${today.total} tasks in ${area} due or overdue`);

// A task whose own triage notes say it can be ticked.
let candidate;
for (const task of today.tasks) {
  const full = await robin("task_read", { id: task.id });
  const last = full.activity?.at(-1)?.text ?? "";
  if (/can be ticked|is done|already (done|answered)|answered\./i.test(last) && !task.proposed_done_by) {
    candidate = { ...task, evidence: last };
    break;
  }
}
await sleep(3);
if (candidate) {
  say("robin", `proposes done: “${candidate.title.slice(0, 60)}”`);
  await robin("task_propose_done", { id: candidate.id, reason: `The latest triage note says: ${candidate.evidence.slice(0, 300)}` });
}

const note = "Personal/Perch agent demo.md";
await sleep(4);
say("claude-code", `claims ${note}`);
await claude("claim", { path: note, note: "Writing the weekly summary", minutes: 10 });
await claude("append", {
  path: note,
  heading: `Weekly summary (${new Date().toDateString()})`,
  text: `- ${today.total} tasks in ${area} are due or overdue.\n- Robin ${candidate ? "proposed one task as done for you to confirm" : "found nothing ready to tick"}.\n- Written by claude-code through Perch's MCP server.`,
});
await sleep(4);
say("robin", `tries to write ${note} while it's claimed`);
await robin("append", { path: note, text: "Robin's addition" });
await sleep(4);
say("claude-code", "releases the note, tells you, and adds a follow-up task for you");
await claude("release", { path: note });
// A message with no recipient goes to the notebook's owner, and the reply says who that is.
const { to: owner } = await claude("message", { text: "The weekly summary is in Perch agent demo. A task to read it is on your list." });
await claude("task_add", {
  title: "Read the agent demo summary",
  area: "personal",
  owner,
  due: new Date().toISOString().slice(0, 10),
  priority: 2,
  labels: ["demo"],
  details: "Claude Code wrote a summary in [[Perch agent demo]]. Robin proposed a task as done; check Ready to tick.",
});
await sleep(3);
say("robin", "leaves you a message");
await robin("message", { text: "Demo done. One task is waiting in Ready to tick." });

console.log("\nBoth agents stay present for two minutes. Open the notch or the app to see them.");
for (let i = 0; i < 6; i++) {
  await sleep(20);
  await robin("presence", { status: i % 2 ? `Watching for new tasks in ${area}` : `Reviewing today's tasks in ${area}` });
  await claude("presence", { status: "Idle after the weekly summary" });
}
console.log("Demo finished.");
