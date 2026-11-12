// The public page at /, /setup and /llms.txt. An agent that is only given the Relay's address
// reads this to learn how to connect, and to walk the person through anything that goes wrong.
// It holds no secrets: every request that touches the notebook still needs a token.

import { voice, type OwnerConfig } from "./owner.js";

/**
 * The address agents should use, from the request's own host. Only safe host characters are kept.
 * A request without a usable host gets the Relay's default local address.
 */
export function publicBase(headers: Record<string, string | string[] | undefined>): string {
  const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)?.split(",")[0]?.trim();
  const host = (first(headers["x-forwarded-host"]) ?? first(headers.host) ?? "").replace(/[^A-Za-z0-9.:-]/g, "") || "127.0.0.1:8787";
  const proto = first(headers["x-forwarded-proto"]) === "http" || /^(127\.|localhost|192\.168\.)/.test(host) ? "http" : "https";
  return `${proto}://${host}`;
}

export function setupGuide(base: string, config: OwnerConfig = {}): string {
  const mcp = `${base}/mcp`;
  const o = voice(config);
  return `# Perch Relay: connecting an agent

You are reading the public help page of a **Perch Relay**, an MCP server for ${o.notebook} (Markdown
notes, tasks and boards kept in a Git repository). This page is for AI agents and the people helping
them. Follow it to connect, then use the troubleshooting section to guide the person through any error.

- MCP endpoint: \`${mcp}\` (Streamable HTTP, **POST only**, no sessions, no SSE)
- Health check: \`${base}/health\` returns \`{"ok":true}\` without a token
- Authentication: \`Authorization: Bearer <token>\`. **Each agent has its own token.** There is no OAuth.

## 1. Get a token

Only ${o.name} can issue tokens. Ask the person for theirs. If they don't have one for this agent, they create it
on the machine running the Relay (it is shown once; only its hash is kept):

\`\`\`sh
node dist/src/index.js add-agent <name>     # or: docker compose run --rm relay node dist/src/index.js add-agent <name>
\`\`\`

Names are lowercase letters, digits and dashes (for example \`claude-work\`). Commits made through the token
are signed with that name.

Keep the token out of chat logs and config files where you can. Store it in a file only the person can read:

\`\`\`sh
mkdir -p ~/.config/perch/tokens && chmod 700 ~/.config/perch ~/.config/perch/tokens
pbpaste > ~/.config/perch/tokens/<name>     # macOS, after the person copies the token; or create the file in an editor
chmod 600 ~/.config/perch/tokens/<name>
\`\`\`

## 2. Connect: pick the client you are running in

### Claude Code (CLI, desktop app Code tab, IDE extensions)

\`\`\`sh
claude mcp add --scope user --transport http perch ${mcp} --header "Authorization: Bearer $(cat ~/.config/perch/tokens/<name>)"
\`\`\`

Then start a new session (or run \`/mcp\`). \`claude mcp get perch\` should say **Connected**.

### Claude Desktop (chat), Codex, or any client that only speaks stdio

Use the bridge, a single file with no dependencies (needs Node 18 or later):

\`\`\`sh
curl -fsSL ${base}/bridge.mjs -o ~/.config/perch/bridge.mjs
\`\`\`

Claude Desktop, in \`claude_desktop_config.json\` (Settings → Developer → Edit Config), then quit and reopen:

\`\`\`json
{
  "mcpServers": {
    "perch": {
      "command": "node",
      "args": ["<home>/.config/perch/bridge.mjs"],
      "env": { "PERCH_URL": "${mcp}", "PERCH_TOKEN_FILE": "<home>/.config/perch/tokens/<name>" }
    }
  }
}
\`\`\`

Use absolute paths (no \`~\`): \`<home>\` is the person's home folder, which \`echo $HOME\` prints. If \`node\` isn't found, give its full path from \`which node\`.

Codex, in \`~/.codex/config.toml\`:

\`\`\`toml
[mcp_servers.perch]
command = "node"
args = ["<home>/.config/perch/bridge.mjs"]
[mcp_servers.perch.env]
PERCH_URL = "${mcp}"
PERCH_TOKEN_FILE = "<home>/.config/perch/tokens/<name>"
\`\`\`

### claude.ai on the web or phone ("custom connectors")

**Not supported.** Custom connectors sign in with OAuth and can't send a fixed Bearer token, and this Relay
only accepts tokens. Adding \`${mcp}\` there fails during sign-in (often shown as an authorization,
registration or connection error). Use Claude Code or Claude Desktop with the steps above instead.

## 3. Check it works

1. \`curl -sS ${base}/health\` prints \`{"ok":true}\`.
2. Call the \`guide\` tool. It answers with **your agent name**, today's date and how the notebook is laid out.
   Read it before writing anything, then call \`presence\` with a status line.

Test the token by itself, without printing it:

\`\`\`sh
curl -sS -X POST ${mcp} -H "Authorization: Bearer $(cat ~/.config/perch/tokens/<name>)" \\
  -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' \\
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"check","version":"0"}}}'
\`\`\`

A reply containing \`"serverInfo":{"name":"perch"\` means the token and the Relay both work.

## 4. Troubleshooting

Work through these with the person. Quote the exact status code or message you see.

| What you see | What it means | What to do |
| --- | --- | --- |
| A **Cloudflare error page**: 502 Bad gateway, 530, error 1033 "Argo Tunnel error", 1016, "the web server is not responding" | Cloudflare is up, but the machine running the Relay (or its \`cloudflared\` tunnel) is off, asleep or disconnected. Nothing on the agent's side can fix it. | Tell the person the Relay's host is offline. They need to wake it or restart the Relay and \`cloudflared\` there. Meanwhile, use a local Perch MCP if this machine has one. Re-check \`/health\` afterwards. |
| 524 or a timeout | The Relay is up but slow, usually a Git pull or push to GitHub. | Retry once after a minute. If it keeps happening, the host's network or GitHub is the problem. |
| \`/health\` works but **401** \`Missing or unknown token\` | The token is missing, malformed, or was removed. | Check the header is exactly \`Authorization: Bearer perch_…\` with no quotes, spaces or newline (\`cat -e\` the file: it should end in a single \`$\`). If it's still refused, ask ${o.name} for a new token (\`remove-agent\`, then \`add-agent\`). |
| **405** \`use POST\` | The client tried GET or SSE. | Use the Streamable HTTP transport (\`--transport http\`), not \`sse\`. |
| An OAuth, "authorization", "client registration" or "couldn't connect" error in claude.ai | Custom connectors need OAuth, which this Relay doesn't offer. | Use Claude Code or Claude Desktop (section 2). |
| **403**, a Cloudflare "Just a moment…" check, or a Cloudflare Access login page | A Cloudflare security setting (Bot Fight Mode, WAF, Access) is stopping non-browser clients. | Ask ${o.name} to allow \`/mcp\`, \`/health\`, \`/setup\` and \`/bridge.mjs\` through for API clients. |
| \`Could not resolve host\`, TLS or certificate errors, or a corporate block page | The network in between (a work proxy or firewall) is in the way. | Try \`curl -v ${base}/health\` to see where it stops. Try another network, or ask the network admins to allow the host. |
| The bridge exits at once: \`Set PERCH_URL…\`, \`Couldn't read the token file\`, \`can be read by other users\` | The bridge's settings are missing or the token file is too open. | Fix the env paths (absolute), and run \`chmod 600\` on the token file. |
| A write is rejected because the file changed | Someone else edited it. | Read it again and redo the edit on the new text. Never resend the old copy. |
| \`guide\` answers with a different agent name | The client is using someone else's token. | Give this agent its own token (section 1). |

If none of these fit, ask the person for the full error text, the client they're using, and the output of
\`curl -sS -o /dev/null -w '%{http_code}\\n' ${base}/health\`.
`;
}
