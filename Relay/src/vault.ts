import { execFile } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import { blobID } from "./format.js";
import { voice } from "./owner.js";

const run = promisify(execFile);

/**
 * Must match `FileHistory.logArguments` in Sources/PerchKit/Vault/FileHistory.swift: the iPhone parses
 * this output with the same code the Mac uses on its own clone.
 */
export const HISTORY_LOG_ARGS = ["-c", "core.quotepath=off", "log", "-M", "--no-merges", "--format=%x1e%at", "--name-status"];

export class VaultError extends Error {
  constructor(message: string, public detail?: Record<string, unknown>) {
    super(message);
  }
}

/** A Git clone of the notebook. All Git work runs one step at a time. */
export class Vault {
  private queue: Promise<unknown> = Promise.resolve();
  private lastPull = 0;

  constructor(
    public root: string,
    private options: { push: boolean; pullEverySeconds?: number; owner?: string } = { push: true },
  ) {}

  /** Runs work after everything already queued, so Git never runs twice at once. */
  exclusive<T>(work: () => Promise<T>): Promise<T> {
    const next = this.queue.then(work, work);
    this.queue = next.catch(() => undefined);
    return next;
  }

  resolve(relative: string): string {
    const cleaned = relative.replace(/^\/+/, "");
    const full = path.resolve(this.root, cleaned);
    if (!full.startsWith(path.resolve(this.root) + path.sep) || cleaned.split("/").includes(".git")) {
      throw new VaultError(`"${relative}" is outside the notebook.`);
    }
    return full;
  }

  async git(...args: string[]): Promise<string> {
    const { stdout } = await run("git", ["-C", this.root, ...args], {
      maxBuffer: 64 * 1024 * 1024,
      env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
    });
    return stdout;
  }

  private async hasRemote() {
    return (await this.git("remote")).trim().length > 0;
  }

  /** Brings in other devices' changes, at most every few seconds. */
  async pull(force = false) {
    const wait = (this.options.pullEverySeconds ?? 5) * 1000;
    if (!force && Date.now() - this.lastPull < wait) return;
    this.lastPull = Date.now();
    if (!(await this.hasRemote())) return;
    await this.git("fetch", "--quiet", "origin");
    const branch = (await this.git("symbolic-ref", "--short", "HEAD")).trim();
    try {
      await this.git("merge", "--ff-only", "--quiet", `origin/${branch}`);
    } catch {
      // Local commits that never reached GitHub: replay them on top.
      try {
        await this.git("rebase", "--quiet", `origin/${branch}`);
      } catch {
        await this.git("rebase", "--abort").catch(() => undefined);
        throw new VaultError(`The notebook couldn't merge changes from GitHub. Ask ${voice({ owner: this.options.owner }).name} to check the Relay.`);
      }
    }
  }

  /** The commit the clone is at. */
  async head(): Promise<string> {
    return (await this.git("rev-parse", "HEAD")).trim();
  }

  private historyCache?: { head: string; log: string };

  /**
   * The whole history as `git log` prints it with HISTORY_LOG_ARGS, for the apps to read each file's
   * created and last edited dates from. Kept until the next commit.
   */
  async history(head: string): Promise<string> {
    if (this.historyCache?.head === head) return this.historyCache.log;
    const log = await this.git(...HISTORY_LOG_ARGS, head);
    this.historyCache = { head, log };
    return log;
  }

  async read(relative: string): Promise<{ text: string; version: string } | null> {
    try {
      const data = await fs.readFile(this.resolve(relative));
      return { text: data.toString("utf8"), version: blobID(data) };
    } catch (error: any) {
      if (error?.code === "ENOENT") return null;
      throw error;
    }
  }

  async list(): Promise<string[]> {
    const out = await this.git("-c", "core.quotepath=off", "ls-files", "-z", "--cached", "--others", "--exclude-standard");
    return [...new Set(out.split("\0").filter(Boolean))].filter((p) => !p.endsWith(".DS_Store") && !p.endsWith(".gitkeep")).sort();
  }

  /**
   * Writes files and commits them under the agent's name.
   * `expect` maps paths to the version the agent last read; null means "must not exist yet".
   */
  async commit(
    changes: { path: string; text: string | null }[],
    expect: Record<string, string | null | undefined>,
    author: { name: string; email: string },
    message: string,
  ) {
    for (const change of changes) {
      const expected = expect[change.path];
      if (expected === undefined) continue;
      const current = await this.read(change.path);
      const currentVersion = current?.version ?? null;
      if (currentVersion !== expected) {
        throw new VaultError(
          current
            ? `${change.path} changed since you read it. Read it again, then reapply your edit.`
            : `${change.path} no longer exists.`,
          { path: change.path, currentVersion, currentText: current?.text },
        );
      }
    }
    for (const change of changes) {
      const full = this.resolve(change.path);
      if (change.text === null) await fs.rm(full, { force: true });
      else {
        await fs.mkdir(path.dirname(full), { recursive: true });
        const temp = `${full}.perch-${process.pid}-${Date.now()}`;
        await fs.writeFile(temp, change.text, "utf8");
        await fs.rename(temp, full);
      }
    }
    await this.git("add", "-A", "--", ...changes.map((c) => c.path));
    if (!(await this.git("diff", "--cached", "--name-only")).trim()) return;
    await this.git(
      "-c", `user.name=${author.name}`, "-c", `user.email=${author.email}`,
      "commit", "--quiet", "-m", message,
    );
    await this.push();
  }

  private async push() {
    if (!this.options.push || !(await this.hasRemote())) return;
    const branch = (await this.git("symbolic-ref", "--short", "HEAD")).trim();
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        await this.git("push", "--quiet", "origin", branch);
        return;
      } catch {
        await this.pull(true);
      }
    }
    throw new VaultError("Saved here, but GitHub didn't accept the change yet. It will retry on the next write.");
  }

  async log(limit: number, since?: string): Promise<{ hash: string; author: string; date: string; subject: string; files: string[] }[]> {
    const args = ["-c", "core.quotepath=off", "log", `-n${limit}`, "--date=iso-strict", "--name-only", "--format=\u001e%H\u001f%an\u001f%ad\u001f%s"];
    if (since) args.push(`--since=${since}`);
    const out = await this.git(...args).catch(() => "");
    return out.split("\u001e").filter(Boolean).map((block) => {
      const [header, ...rest] = block.split("\n");
      const [hash, author, date, subject] = header.split("\u001f");
      return { hash, author, date, subject, files: rest.filter(Boolean) };
    });
  }
}
