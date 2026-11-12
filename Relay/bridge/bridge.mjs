#!/usr/bin/env node
// A stdio MCP server that forwards every message to a Perch Relay over HTTP(S).
// No dependencies. Set PERCH_URL (e.g. https://relay.example.com/mcp) and either PERCH_TOKEN, or
// PERCH_TOKEN_FILE naming a file only you can read, so the token stays out of app configs.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const url = process.env.PERCH_URL;
let token = process.env.PERCH_TOKEN;
const tokenFile = process.env.PERCH_TOKEN_FILE;
if (!token && tokenFile) {
  try {
    if (statSync(tokenFile).mode & 0o077) {
      process.stderr.write(`${tokenFile} can be read by other users. Run: chmod 600 "${tokenFile}"\n`);
      process.exit(2);
    }
    token = readFileSync(tokenFile, "utf8").trim();
  } catch (error) {
    process.stderr.write(`Couldn't read the token file: ${error.message}\n`);
    process.exit(2);
  }
}
if (!url || !token) {
  process.stderr.write("Set PERCH_URL, and PERCH_TOKEN or PERCH_TOKEN_FILE.\n");
  process.exit(2);
}

// Which app and session this agent is in, so Perch can link its work back to the conversation. Only
// these fields go to the Relay: never the account's email or anything else in the environment.
function sessionOrigin() {
  const env = process.env;
  if (env.CLAUDECODE === "1" || env.CLAUDE_CODE_SESSION_ID) {
    return {
      app: env.CLAUDE_CODE_ENTRYPOINT === "claude-desktop" ? "claude-desktop" : "claude-code",
      session: env.CLAUDE_CODE_HOST_SESSION_ID || undefined,
      conversation: env.CLAUDE_CODE_SESSION_ID || undefined,
      folder: env.CLAUDE_PROJECT_DIR || process.cwd(),
    };
  }
  // Codex runs each thread in its own folder and records it in the thread's file: find ours.
  const folder = process.cwd();
  if (folder === "/") return undefined;
  const root = join(env.CODEX_HOME || join(homedir(), ".codex"), "sessions");
  const days = [0, 1, 2].map((back) => {
    const d = new Date(Date.now() - back * 86400000);
    return join(root, String(d.getFullYear()), String(d.getMonth() + 1).padStart(2, "0"), String(d.getDate()).padStart(2, "0"));
  });
  for (const day of days) {
    let files = [];
    try { files = readdirSync(day).filter((f) => f.endsWith(".jsonl")).sort().reverse(); } catch { continue; }
    for (const file of files) {
      try {
        const first = readFileSync(join(day, file), "utf8").split("\n", 1)[0];
        const meta = JSON.parse(first)?.payload;
        if (meta?.cwd === folder && typeof meta.id === "string") return { app: "codex", thread: meta.id, folder };
      } catch {}
    }
  }
  return undefined;
}

const origin = sessionOrigin();
const originHeader = origin ? Buffer.from(JSON.stringify(origin)).toString("base64url") : undefined;

const write = (message) => process.stdout.write(JSON.stringify(message) + "\n");
let pending = Promise.resolve();

async function forward(line) {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        Accept: "application/json, text/event-stream",
        ...(originHeader ? { "X-Perch-Session": originHeader } : {}),
      },
      body: JSON.stringify(message),
    });
    const text = await response.text();
    if (!text) return;
    // The Relay answers with JSON; tolerate an event stream too.
    const bodies = text.startsWith("event:") || text.startsWith("data:")
      ? text.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim())
      : [text];
    for (const body of bodies) {
      const parsed = JSON.parse(body);
      for (const item of Array.isArray(parsed) ? parsed : [parsed]) {
        if (item?.jsonrpc) write(item);
        else if (message.id !== undefined) write({ jsonrpc: "2.0", id: message.id, error: { code: -32000, message: item?.error ?? `Relay returned HTTP ${response.status}` } });
      }
    }
  } catch (error) {
    if (message.id !== undefined) write({ jsonrpc: "2.0", id: message.id, error: { code: -32000, message: `Couldn't reach Perch: ${error.message}` } });
  }
}

// Requests run in order, so replies keep the order clients expect.
createInterface({ input: process.stdin }).on("line", (line) => {
  pending = pending.then(() => forward(line));
});
