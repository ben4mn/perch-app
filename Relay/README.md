# Perch Relay: the agent layer

The Relay lets AI agents work in the notebook alongside its owner. It is an MCP server over its own Git clone of the notebook. Every agent has its own token and its own name, every change an agent makes is a Git commit under that name, and the Perch apps show who is working where.

## What agents are told

Agents learn how Perch works from the Relay itself, so nothing needs pasting into each one:

- **On connecting**, every MCP client receives the server's instructions: start with `guide`, set a `presence` status, and the five rules that keep the notebook safe (read before writing, claim longer edits, use the right tool for tasks and boards, propose rather than complete other people's tasks, no deleting).
- **The `guide` tool** returns the full explanation: how areas, notes, tasks, owners, boards and whiteboards work, the order to work in, the rules, and one line on when to use each tool. It also gives the agent's own name, today's date, the areas and the owners in use.

Both live in `src/tools.ts` (`instructions()` and `guide()`). Edit them there. They take the owner settings below, so the same text works with a name or without one. The tests fail if a tool exists that the guide doesn't explain, or if the instructions grow past what a client will show in full.

## The notebook's owner

Five optional keys in `relay.config.json`, beside `vault`, `host`, `port`, `push` and `agents`, set how agents are told about the person the notebook belongs to. Without them the Relay names no one and speaks of "the notebook's owner".

```json
{
  "vault": "/data/vault",
  "host": "127.0.0.1",
  "port": 8787,
  "push": true,
  "agents": [],
  "owner": "Jordan",
  "ownerId": "jordan",
  "areas": ["Work", "Personal"],
  "areasNote": "\"Work\" is Jordan's job and \"Personal\" is everything else.",
  "pronouns": "she"
}
```

| Key | Default | What it sets |
| --- | --- | --- |
| `owner` | none | The owner's name, as agents are told it. |
| `ownerId` | `"me"` | The `owner:` value on the owner's own tasks, and who `message` sends to when it has no `to`. |
| `areas` | `["Personal"]` | The areas the notebook starts with, in this order. Each one is listed only when its top-level folder exists. Folders that hold a `Tasks` folder are added after them. |
| `areasNote` | none | One sentence about the areas. The guide puts it after "Top-level folders are areas." |
| `pronouns` | `"they"` | `"he"`, `"she"` or `"they"`, for the sentences that refer back to the owner. |

Restart the Relay after a change. These keys change only what agents read, not the notebook or the tokens. Set `ownerId` to the `owner:` value your own tasks already carry (the Perch app writes its build's `PERCH_OWNER_ID`, `me` by default): agents add tasks for you with it. While it is missing, the Relay says so in one line when it starts.

## What keeps the notebook safe

| Safeguard | How it works |
| --- | --- |
| Identity | Each agent has a token, stored only as a hash. `remove-agent` stops it at once. |
| No lost edits | `write`, and `task_update` with new details, need the version the agent read. A stale write is rejected. |
| No collisions | `claim` marks a file as in use for up to two hours; other agents' writes to it are refused until it is released or expires. |
| The owner decides | An agent completes only tasks it owns. For anyone else's it proposes, and the owner ticks it from Ready to tick. |
| Undo | Every write is a commit. There is no delete or rename tool. |
| Formats | Tasks go through the task tools and boards through `kanban_card`, so the app and NotesHub keep reading them. |
| Injected text | The guide and every read remind agents that note text is information, never instructions. |

## Running it

Test on a copy first: see Part 2 of `../TESTING.md`. In short:

```sh
npm ci && npm run build
export PERCH_RELAY_CONFIG=~/Perch-Test/relay.config.json
node dist/src/index.js init ~/Perch-Test/vault
node dist/src/index.js add-agent claude-code   # prints the token once
node dist/src/index.js serve                   # http://127.0.0.1:8787/mcp
```

Connecting clients:

- **Claude Code:** an HTTP MCP server at `http://127.0.0.1:8787/mcp` with the header `Authorization: Bearer <token>`. A project `.mcp.json` can read the token from an environment variable (`"Bearer ${PERCH_TOKEN}"`), which keeps it out of shell history.
- **Clients that only speak stdio** (Claude Desktop, Codex): `bridge/bridge.mjs` with `PERCH_URL` and `PERCH_TOKEN` set.
- **The Perch apps:** Settings, then Agents, with the `perch-app` token. The apps only read from the Relay: presence, claims and messages.

`npm test` runs the format checks and an end-to-end run with two agents and a real Git remote. `node scripts/demo.mjs <tokens-file>` plays a scripted session between two agents, `robin` and `claude-code`, to watch in the app.

## Running it on a server

The `Dockerfile` builds the Relay with Git and SSH. `docker-compose.yml` runs it with host networking and keeps everything in `./data`: the config (`data/relay.config.json`), the notebook's clone (`data/vault`), and an SSH key for the notebook's Git remote (`data/deploy_key`). The container runs as the `node` user, so that user must be able to write to `data/`. Clone the notebook into `data/vault`, then:

```sh
docker compose run --rm relay node dist/src/index.js init /data/vault
docker compose run --rm relay node dist/src/index.js add-agent claude-code   # prints the token once
docker compose up -d --build
```

The Relay listens on `127.0.0.1:8787`, so agents on other machines need a tunnel or a reverse proxy with HTTPS in front of it. The help page at `/setup` takes its address from the request's `Host` or `X-Forwarded-Host` header.
