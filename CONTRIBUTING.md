# Contributing to Perch

Thank you for looking. Perch is a personal project, so changes arrive in a particular way.

This repository is produced from a private working copy by a script. Nothing is committed here
directly. The maintainer reads each proposal, makes the change in the working copy, and the next
public copy carries it. Your pull request is closed when that happens, with a note saying where the
change landed.

To propose a change:

1. Open an issue first for anything bigger than a small fix, so we can agree on the shape of it.
2. Make the change on a branch, test first: write the failing test, see it fail, then make it pass.
   Most logic lives in `Sources/PerchKit` and is tested in `Tests/PerchKitTests`.
3. Run `swift test`, and the Mac Debug build in AGENTS.md. For a change to the Relay, run its
   tests too. For a change you can see, draw it with the off-screen snapshot runner on a copy of
   the demo notebook (`scripts/demo-notebook.sh`, then TESTING.md, "Checking visuals without
   opening the app") and add the pictures. Say in the pull request what you ran and what you
   could not check.
4. Keep to the rules in AGENTS.md: no emojis in the UI, test runs never read the Keychain or sync,
   and never use a real notebook in a test.

A coding agent such as Claude Code can do all of this from AGENTS.md.
