#!/usr/bin/env node
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { gzipSync } from "node:zlib";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { fileURLToPath } from "node:url";
import { readOrigin } from "./origin.js";
import { ownerConfig, ownerNotice, type OwnerConfig } from "./owner.js";
import { publicBase, setupGuide } from "./setup.js";
import { Presence } from "./presence.js";
import { buildServer, Workspace, type Agent } from "./tools.js";
import { Vault } from "./vault.js";

/** relay.config.json. The owner keys (owner, ownerId, areas, areasNote, pronouns) are all optional. */
interface Config extends OwnerConfig {
  vault: string;
  host: string;
  port: number;
  push: boolean;
  agents: { name: string; email?: string; tokenSHA256: string }[];
}

/** The notebook's clone and what agents are told about it, from the config. */
function openWorkspace(config: Config): Workspace {
  // On standard error, which the stdio transport leaves free.
  const notice = ownerNotice(config);
  if (notice) console.error(notice);
  const vault = new Vault(config.vault, { push: config.push, owner: config.owner });
  return new Workspace(vault, new Presence(), ownerConfig(config));
}

const configPath = process.env.PERCH_RELAY_CONFIG ?? "relay.config.json";

function loadConfig(): Config {
  if (!existsSync(configPath)) throw new Error(`No config at ${configPath}. Run: perch-relay init <vault-folder>`);
  return { host: "127.0.0.1", port: 8787, push: true, agents: [], ...JSON.parse(readFileSync(configPath, "utf8")) };
}

// Relay/bridge/bridge.mjs, from dist/src/index.js.
const bridgePath = fileURLToPath(new URL("../../bridge/bridge.mjs", import.meta.url));

const sha = (text: string) => createHash("sha256").update(text).digest("hex");

function agentFor(config: Config, header: string | undefined): Agent | null {
  const token = header?.match(/^Bearer (.+)$/)?.[1];
  if (!token) return null;
  const digest = Buffer.from(sha(token), "hex");
  for (const agent of config.agents) {
    const expected = Buffer.from(agent.tokenSHA256, "hex");
    if (expected.length === digest.length && timingSafeEqual(expected, digest)) {
      return { name: agent.name, email: agent.email ?? `${agent.name}@perch.local` };
    }
  }
  return null;
}

async function serve() {
  const config = loadConfig();
  const workspace = openWorkspace(config);
  const { vault } = workspace;
  await vault.pull(true).catch((e) => console.error("Initial pull failed:", e.message));

  const send = (res: ServerResponse, status: number, body: unknown) => {
    res.writeHead(status, { "content-type": "application/json" });
    res.end(JSON.stringify(body));
  };

  const readBody = (req: IncomingMessage) =>
    new Promise<unknown>((resolve, reject) => {
      const chunks: Buffer[] = [];
      let size = 0;
      req.on("data", (chunk) => {
        size += chunk.length;
        if (size > 4 * 1024 * 1024) reject(new Error("Request too large"));
        chunks.push(chunk);
      });
      req.on("end", () => {
        try {
          resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : undefined);
        } catch (error) {
          reject(error);
        }
      });
    });

  const server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url ?? "/", "http://relay");
      if (url.pathname === "/health") return send(res, 200, { ok: true });
      const base = publicBase(req.headers);
      const help = `${base}/setup`;
      // Public help for agents given only the address, and the bridge they may need. No secrets in either.
      if (["/", "/setup", "/llms.txt"].includes(url.pathname) && (req.method === "GET" || req.method === "HEAD")) {
        res.writeHead(200, { "content-type": "text/markdown; charset=utf-8", "cache-control": "no-cache" });
        return res.end(req.method === "HEAD" ? undefined : setupGuide(base, workspace.owner));
      }
      if (url.pathname === "/bridge.mjs" && (req.method === "GET" || req.method === "HEAD")) {
        if (!existsSync(bridgePath)) return send(res, 404, { error: "The bridge isn't installed with this Relay.", help });
        res.writeHead(200, { "content-type": "text/javascript; charset=utf-8", "content-disposition": 'attachment; filename="bridge.mjs"' });
        return res.end(req.method === "HEAD" ? undefined : readFileSync(bridgePath));
      }
      // No OAuth here: say so plainly, so clients don't read a 401 as "sign in first".
      if (url.pathname.startsWith("/.well-known/")) {
        return send(res, 404, { error: "This Relay doesn't offer OAuth. Connect with a Bearer token instead.", help });
      }
      const agent = agentFor(config, req.headers.authorization);
      if (!agent) {
        const error = req.headers.authorization ? "Unknown token." : "Missing token. Send Authorization: Bearer <token>.";
        return send(res, 401, { error, help });
      }

      if (url.pathname === "/api/presence" && req.method === "GET") {
        return send(res, 200, { ...workspace.presence.snapshot(), recent: workspace.presence.recent(30) });
      }
      if (url.pathname === "/api/history" && req.method === "GET") {
        // Each file's history, for the iPhone's created and last edited dates. It has no Git of its own.
        await vault.exclusive(() => vault.pull()).catch(() => undefined);
        const head = await vault.exclusive(() => vault.head());
        const etag = `"${head}"`;
        if (req.headers["if-none-match"] === etag) {
          res.writeHead(304, { etag });
          return res.end();
        }
        const log = Buffer.from(await vault.exclusive(() => vault.history(head)), "utf8");
        const gzip = /\bgzip\b/.test(String(req.headers["accept-encoding"] ?? ""));
        res.writeHead(200, {
          "content-type": "text/plain; charset=utf-8",
          etag,
          ...(gzip ? { "content-encoding": "gzip" } : {}),
        });
        return res.end(gzip ? gzipSync(log) : log);
      }
      if (url.pathname === "/mcp") {
        if (req.method !== "POST") return send(res, 405, { error: "This server runs without sessions; use POST." });
        // A fresh server per request keeps each agent's identity separate.
        const origin = readOrigin(req.headers["x-perch-session"]);
        workspace.presence.noteOrigin(agent.name, origin);
        const mcp = buildServer(workspace, agent, origin);
        const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
        res.on("close", () => {
          transport.close();
          mcp.close();
        });
        await mcp.connect(transport);
        await transport.handleRequest(req, res, await readBody(req));
        return;
      }
      send(res, 404, { error: "Not found" });
    } catch (error: any) {
      if (!res.headersSent) send(res, 500, { error: error?.message ?? "Server error" });
    }
  });
  server.listen(config.port, config.host, () => console.log(`Perch Relay on http://${config.host}:${config.port} for ${config.vault}`));
}

async function stdio(agentName: string) {
  const server = buildServer(openWorkspace(loadConfig()), { name: agentName, email: `${agentName}@perch.local` });
  await server.connect(new StdioServerTransport());
}

function save(config: Config) {
  writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
}

const [command, ...rest] = process.argv.slice(2);
switch (command) {
  case "serve":
    await serve();
    break;
  case "stdio":
    await stdio(rest[0] ?? "local-agent");
    break;
  case "init":
    if (!rest[0]) throw new Error("Usage: perch-relay init <vault-folder>");
    if (existsSync(configPath)) throw new Error(`${configPath} already exists.`);
    save({ vault: rest[0], host: "127.0.0.1", port: 8787, push: true, agents: [] });
    console.log(`Created ${configPath}. Add agents with: perch-relay add-agent <name>`);
    break;
  case "add-agent": {
    const name = rest[0];
    if (!name || !/^[a-z][a-z0-9-]{1,30}$/.test(name)) throw new Error("Agent names are lowercase letters, digits and dashes, like robin or claude-code.");
    const config = loadConfig();
    if (config.agents.some((a) => a.name === name)) throw new Error(`${name} already exists. Remove it first to issue a new token.`);
    const token = "perch_" + randomBytes(24).toString("base64url");
    config.agents.push({ name, tokenSHA256: sha(token) });
    save(config);
    console.log(`Token for ${name}. It's shown once; only its hash is stored:\n${token}`);
    break;
  }
  case "remove-agent": {
    const config = loadConfig();
    config.agents = config.agents.filter((a) => a.name !== rest[0]);
    save(config);
    console.log(`Removed ${rest[0]}. Its token no longer works.`);
    break;
  }
  default:
    console.log("Commands: init <vault>, add-agent <name>, remove-agent <name>, serve, stdio <agent-name>");
}
