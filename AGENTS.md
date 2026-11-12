# Working on Perch

Perch is a notes and tasks app: a native Mac and iPhone app (SwiftUI) over plain Markdown files in a folder, usually a Git repository, with a Mac notch interface and the Perch Relay, an MCP server that lets AI agents work in the same notebook.

## Where things are

- `Sources/PerchKit`: the model and logic, with no UI (tasks, notes, sync, editing, updates, the build's configuration). Most tests are here.
- `Sources/PerchUI`: the SwiftUI views shared by both apps.
- `Apps/Mac`, `Apps/iOS`: each app's shell. On the Mac that is the window, the notch, Settings, first run, updates, and the debug test harnesses `NavStress` and `NoteStress`.
- `Web/src`: the page that draws notes, built into `Apps/Shared/Web` (markdown-it and its plugins).
- `Relay`: the Perch Relay (Node and TypeScript). It has its own README.
- `project.yml`: the XcodeGen project. `Perch.xcodeproj` is generated from it with `xcodegen generate`.
- `Config/Perch.xcconfig`: the values that differ between builds (bundle identifiers, signing, GitHub App, update source, the owner and agent names, which agents get a mark of their own). An optional `Config/Private.xcconfig` overrides them and stays out of Git.
- `Demo/notebook`: a small notebook to try Perch with, all invented (`Demo/README.md`). `scripts/demo-notebook.sh <folder> [--owner <id>]` writes a copy with fresh dates; `DemoNotebookTests` hold it to the public build's areas and owners.
- `site/`: the project website. `scripts/site-media.sh [--scenes a,b] [--out <folder>]` makes its clips into `site/media/` (not in Git) from the off-screen snapshot runner on the demo notebook, and `scripts/site-build.sh <folder> --owner <o> --repo <r>` builds the site to publish.
- `CHANGELOG.md`: user-facing changes. Settings, Updates shows it.
- `TESTING.md`: how to test everything, including the off-screen snapshots, the stress tests and the render survey.

## Build and test

```sh
swift test                                  # PerchKit and PerchUI tests, plus the render tests (about 2 minutes)
(cd Relay && npm ci && npm test)            # the Relay
scripts/render-tests.sh                     # rebuild the note page from Web/src, then its WebKit tests
xcodegen generate --quiet
xcodebuild -project Perch.xcodeproj -scheme PerchMac -configuration Debug -destination "platform=macOS,arch=arm64" \
  -derivedDataPath .build/debug-app build
xcodebuild -project Perch.xcodeproj -scheme PerchPhone -configuration Debug -destination "generic/platform=iOS Simulator" \
  -derivedDataPath .build/ios-check CODE_SIGNING_ALLOWED=NO build
scripts/build-mac.sh                        # a Release build, installed to ~/Applications and opened
```

Perch needs Xcode 27 and an Apple silicon Mac. With no `Config/Private.xcconfig` the Mac app is signed ad hoc, so it runs on the Mac that built it with no Apple account.

## Two kinds of build

The values that differ between builds live in `Config/Perch.xcconfig` and reach the code through each app's Info.plist and `PerchConfiguration` (in `Sources/PerchKit/Settings`). Nothing in the Swift package names a person, an account or a server.

- With no GitHub App client ID (the default), the Mac app never asks anyone to sign in. First run offers a folder on this Mac: a Git repository syncs with its own Git login, any other folder opens without sync. Settings shows no GitHub account.
- With no update repository (the default), the Mac app never checks for updates, and Settings, Updates shows only the version and the changelog.
- The decisions are in `FirstRun` and tested in `BuildConfigurationTests`. Keep new build-dependent behaviour there, with a test, rather than reading Info.plist in a view.

## How work is done here

- Test first, every time: write the failing test, see it fail, then make it pass. Don't call something done until it builds and its tests pass, and say plainly what wasn't verified.
- Measure before you fix. The debug harnesses (TESTING.md) drive the real window off screen, on a copy of a notebook, with sync off. Use them rather than taking over the screen, and run before-and-after numbers.
- No emojis in the UI or in pages. Use SF Symbols or inline SVG.
- Test on a copy of a notebook, never on your real one: `rsync -a --exclude .git <notebook>/ <scratch>/`, or `scripts/make-test-vault.sh`.
- Never print a token or put one on a command line. Pass it through standard input or a file only you can read.
- Test runs (snapshots and the stress harnesses) never read the Keychain or the Relay, never sync, and never save settings or window positions. Keep it that way when you add to them.

## Things that were learned the hard way

- The notch panel's `collectionBehavior` must stay `.transient`. `.stationary` broke Mission Control for every app on the Mac.
- Don't use SwiftUI's `.inspector` for the Mac's task panel. It sends a late "closed" when a panel opens soon after another closes, which closed the new panel, so `TaskPanelColumn` is Perch's own column.
- Don't call `dismiss()` from the task panel. Close it by clearing `selectedTaskID`, which every host is bound to.
- `ViewThatFits` can spin forever on iOS 27.1 and hang the app. On the iPhone, use a fixed stacked layout (see the comment in `FolderScreen`'s header).
- Compare a note's text with `TextIdentity.same`, not `==`. Swift's `==` normalizes Unicode as it goes, and on a long note it was most of what a keystroke cost.
- An embedded web view, such as a task's details, keeps scroll-wheel events on the Mac. Pass `embedded: true` to `WebHostView` (see `WebScroll`).
- A background launch (`open -g`) never makes a SwiftUI app's first window, so the stress harness makes its own window.
- Settings in `project.yml` win over `Config/Perch.xcconfig`. Put a value that differs between builds in the xcconfig only.
