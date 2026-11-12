# Perch

Perch is a notes and tasks app for the Mac, with an iPhone app beside it. It works on plain Markdown
files in a folder, usually a Git repository, so your notes stay yours and open in any editor. On a Mac
with a notch, Perch lives in the notch too. And the Perch Relay, a small MCP server, lets AI agents such
as Claude work in the same notebook while you watch.

See it moving at [ben4mn.github.io/perch-app](https://ben4mn.github.io/perch-app/).

<!-- Previews: three short animations, published with the project site. -->
![Opening Perch from the notch](https://ben4mn.github.io/perch-app/media/notch-open.gif)
![Tasks in Perch](https://ben4mn.github.io/perch-app/media/tasks.gif)
![Notes in Perch](https://ben4mn.github.io/perch-app/media/notes.gif)
<!-- End of previews. -->

## What it does

- Notes are Markdown files. Perch reads them with tables, code, math, Mermaid diagrams and ABC music,
  and edits them with a format bar that writes plain Markdown. `[[Title]]` links one note to another.
- Each task is a Markdown file of its own, in an area's `Tasks` folder (`Personal/Tasks/`, say). Perch
  shows them as Today, Upcoming, List, Calendar and Board, with quick add (`Call the vet tomorrow 5pm #Personal`).
- The notch opens to today's tasks, a notepad, the week, recent clips and what agents are doing.
- Boards (`.kanban.md`) and whiteboards (`.excalidraw.svg`) use NotesHub's formats, so NotesHub can open
  the same notebook.
- In a Git repository, Perch commits, pulls and pushes about once a minute, with the Git login that
  folder already uses. Any other folder works too, without sync.

## What you need

- A Mac with Apple silicon and macOS 14 or later.
- Xcode 27.
- XcodeGen, which makes the Xcode project from `project.yml`: `brew install xcodegen`.
- Node.js 22.5 or later, only for the Relay and for rebuilding the page that draws notes.

You don't need an Apple developer account. The Mac app is signed to run on the Mac that built it.

## Build and run

```sh
git clone https://github.com/ben4mn/perch-app.git perch
cd perch
scripts/build-mac.sh
```

That builds Perch, puts it in `~/Applications/Perch.app` and opens it. The first build takes a few
minutes. If that folder already has another build of Perch (one with a different bundle identifier),
the script stops and changes nothing; run `scripts/build-mac.sh --replace` to put this build there
instead. [AGENTS.md](AGENTS.md) has the commands for a debug build and for the tests.

On its first run Perch asks for a notebook folder. Pick a folder of Markdown notes, or a new empty
folder to start one. Perch remembers it, and Settings, Notebook can open a different one later.

## Try it with the demo notebook

The repository has a small demo notebook in `Demo/notebook/`, with invented people, tasks and notes.
This writes a copy of it with its dates moved so that its "today" is today, ready to open:

```sh
scripts/demo-notebook.sh ~/Perch-Demo
```

Then choose **Open a notebook folder** when Perch first opens (or **Open a different notebook…** later)
and pick `~/Perch-Demo`. It opens without sync; run `git init` in it first if you want Perch to commit as
you go. Its tasks are yours (`owner: me`, the default owner); a build with another `PERCH_OWNER_ID`
takes `--owner <id>`. [Demo/README.md](Demo/README.md) says what is in it.

## Use it with Claude Code

Clone the repository, open the folder in Claude Code, and ask it to build and run Perch. Claude Code
reads [CLAUDE.md](CLAUDE.md) and [AGENTS.md](AGENTS.md), which carry the build and test commands, a
map of the code, and the rules the project follows. Ask it for a change the same way: it writes the
failing test first, then the code.

## Sign in with your own GitHub App (optional)

A build from source has no GitHub sign-in. It opens a folder on your Mac, and syncs it with Git if it is
a repository. To clone notebooks from GitHub inside Perch and sign in once for sync, make a GitHub App of
your own:

1. On GitHub, open Settings, Developer settings, GitHub Apps, and choose New GitHub App.
2. Give it a name and a homepage address, turn on Enable Device Flow, and turn off the webhook.
3. Under Repository permissions, give Contents read and write access.
4. Create it, then install it on the repository that holds your notes.
5. Make a file `Config/Private.xcconfig` with the App's client ID and your own bundle identifier prefix:

   ```
   PERCH_BUNDLE_ID_PREFIX = com.yourname
   PERCH_GITHUB_CLIENT_ID = <the App's client ID>
   ```

6. Build again. Perch now asks you to sign in with GitHub first, and offers Clone from GitHub.

`Config/Perch.xcconfig` lists every value a build can set, including signing with your own Apple team
and an update source for the Mac app. `Config/Private.xcconfig` is in `.gitignore`, so it stays on your
Mac.

## The iPhone app

The iPhone app builds and runs in the simulator (see AGENTS.md). It syncs with a GitHub repository
directly, with a fine-grained token that can read and write that repository's contents. To install it on
a phone you need your own Apple team in `Config/Private.xcconfig`. It is less finished than the Mac app.

## The Relay

The Perch Relay is an MCP server for the notebook, written in Node and TypeScript. It keeps its own Git
clone of the notebook. Each agent gets its own token and name, every change an agent makes is a Git
commit under that name, and agents can claim a file while they edit it. The apps show who is working
where, in the window and the notch. Agents learn the notebook's layout and rules from the Relay itself.

To try it, see [Relay/README.md](Relay/README.md) and Part 2 of [TESTING.md](TESTING.md). Connect Perch
to it in Settings, Agents.

## Status

- This is a personal project. It was made for one person's notebook and is shared as it is.
- There are no ready-made downloads, and nothing is notarized. Build it from source.
- The Mac app comes first. The iPhone app works, with fewer features and less polish.
- Changes are made in a private working copy and brought across to this repository by the maintainer.
  [CONTRIBUTING.md](CONTRIBUTING.md) says how to propose one.
- Perch is under the MIT license ([LICENSE](LICENSE)). The code and fonts it bundles from others are
  listed in [THIRD-PARTY.md](THIRD-PARTY.md).
