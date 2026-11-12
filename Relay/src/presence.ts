import { sessionLink, type AgentOrigin } from "./origin.js";

/** Who's here, what they're working on, and messages between them. Kept in memory. */
export interface Claim {
  path: string;
  agent: string;
  note: string;
  expires: number;
}

export interface Event {
  at: string;
  agent: string;
  kind: "message" | "claim" | "release" | "write" | "task" | "status";
  text: string;
  path?: string;
  to?: string;
}

export class Presence {
  private seen = new Map<string, { status: string; at: number; path?: string; statusAt?: number }>();
  /** The app and session each agent last called from. */
  private origins = new Map<string, AgentOrigin>();
  private claims = new Map<string, Claim>();
  private events: Event[] = [];
  static activeMinutes = 5;

  touch(agent: string, path?: string, origin?: AgentOrigin) {
    const current = this.seen.get(agent);
    this.seen.set(agent, { status: current?.status ?? "Connected", at: Date.now(), path: path ?? current?.path, statusAt: current?.statusAt });
    if (origin) this.origins.set(agent, origin);
  }

  setStatus(agent: string, status: string, path?: string) {
    this.seen.set(agent, { status, at: Date.now(), path, statusAt: Date.now() });
    this.record({ agent, kind: "status", text: status, path });
  }

  /** What the agent said it was doing, if it said so in the last two hours. */
  currentStatus(agent: string): string | undefined {
    const seen = this.seen.get(agent);
    return seen?.statusAt && Date.now() - seen.statusAt < 2 * 3600_000 ? seen.status : undefined;
  }

  origin(agent: string): AgentOrigin | undefined { return this.origins.get(agent); }

  /** Remembers where an agent is calling from, without counting it as working. */
  noteOrigin(agent: string, origin: AgentOrigin | undefined) { if (origin) this.origins.set(agent, origin); }

  record(event: Omit<Event, "at">) {
    this.events.push({ ...event, at: new Date().toISOString() });
    if (this.events.length > 500) this.events.splice(0, this.events.length - 500);
  }

  private prune() {
    const now = Date.now();
    for (const [key, claim] of this.claims) if (claim.expires <= now) this.claims.delete(key);
  }

  claim(agent: string, path: string, note: string, minutes: number): Claim {
    this.prune();
    const existing = this.claims.get(path);
    if (existing && existing.agent !== agent) {
      throw new Error(`${existing.agent} is working on ${path} (${existing.note}) for about ${Math.ceil((existing.expires - Date.now()) / 60000)} more minutes.`);
    }
    const claim = { path, agent, note, expires: Date.now() + Math.min(Math.max(minutes, 1), 120) * 60000 };
    this.claims.set(path, claim);
    this.record({ agent, kind: "claim", text: note, path });
    return claim;
  }

  release(agent: string, path: string) {
    if (this.claims.get(path)?.agent === agent) {
      this.claims.delete(path);
      this.record({ agent, kind: "release", text: "Finished", path });
    }
  }

  /** Throws when someone else holds the path. */
  check(agent: string, path: string) {
    this.prune();
    const claim = this.claims.get(path);
    if (claim && claim.agent !== agent) {
      throw new Error(`${claim.agent} is working on ${path} right now (${claim.note}). Wait, or message them.`);
    }
  }

  snapshot() {
    this.prune();
    const now = Date.now();
    return {
      agents: [...this.seen.entries()]
        .map(([name, s]) => ({
          name,
          status: s.status,
          path: s.path,
          isActive: now - s.at < Presence.activeMinutes * 60000,
          updated: new Date(s.at).toISOString(),
          link: sessionLink(this.origins.get(name)),
        }))
        .sort((a, b) => Number(b.isActive) - Number(a.isActive) || b.updated.localeCompare(a.updated)),
      claims: [...this.claims.values()].map((c) => ({ ...c, expires: new Date(c.expires).toISOString() })),
    };
  }

  recent(limit: number, forAgent?: string) {
    const list = forAgent ? this.events.filter((e) => !e.to || e.to === forAgent || e.agent === forAgent) : this.events;
    return list.slice(-limit).reverse();
  }
}
