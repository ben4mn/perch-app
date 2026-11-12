# Testing Perch

Test on a copy first. Nothing here touches your real notebook or Todoist until you choose to.

## Part 1: the Mac app and Todoist import

1. Make a safe copy of your notes. Its sync target is a local folder, so nothing reaches GitHub:
   ```sh
   scripts/make-test-vault.sh <your notebook's Git address or folder>
   ```
   This creates `~/Perch-Test/vault`.
2. Build and open Perch:
   ```sh
   scripts/build-mac.sh
   ```
3. A build without a GitHub App (the default, see `Config/Perch.xcconfig`) opens on **Open a notebook folder**: choose `~/Perch-Test/vault`. A folder that isn't a Git repository opens too, without sync. A build with a GitHub App asks you to **Sign in with GitHub** first. Perch shows a code: **Copy Code and Open GitHub**, enter it, and approve. Perch then asks for a notebook. Under **Use a Git repo on this Mac**, choose `~/Perch-Test/vault`. (**Clone from GitHub** clones a repository the Perch GitHub App can reach into `~/Documents/Perch` and syncs it as your GitHub account, with your GitHub noreply address on its commits. Don't pick your real notebook there until you mean to.)
4. Get your Todoist API token without a password: in the signed-in Todoist app, open **Settings → Integrations → Developer** and copy the token.
5. In Perch, open **Import from Todoist**, paste the token and choose **Preview import**. Check the counts against Todoist, then **Create task files**. A project goes to the area with the same name; any other project goes to Personal, with the project's name as a label.

### What to check

- **Notes:** notes open in Read. Choose Edit (Command-E) to change one; in a wide window the preview sits beside the editor, on the side set under Settings → Reading. Open notes with Mermaid diagrams, ABC music, tables and wiki links, and try the Aa panel for font, size and width.
- **Sections:** the sidebar starts with **Tasks | Notes** and shows one section at a time. Command-1 is Tasks and Command-2 is Notes; each comes back where you left it (the view and area, or the folder or note), and that is remembered across launches.
- **Tasks and areas:** in Tasks the sidebar lists the views (Today, Upcoming, List, Calendar, Board, and Ready to tick while something waits) and, under Areas, All and the notebook's areas (the folders with tasks in them, and any you add). Clicking an area scopes every view to it and leaves the view alone, so a view and an area are both highlighted; the same areas are chips across the top of the main pane, beside the view switcher. Check that counts, the calendar's trays, empty states and the header ("Personal · Upcoming") follow the area, that quick add inside an area files the task there, and that List inside an area nests subtasks under their tasks and has Completed. Option-Command-1 to 6 choose the view (5 is Ready to tick, 6 is Board; they were Command-1 to 4), and Option-Command-[ and ] step through the areas.
- **Adding an area:** click **+** at the end of the area chips (or Edit areas… in the sidebar, the … menu, or Settings → Notebook). Add Consulting from "Add with one tap", then reorder, hide and show areas. Check that nothing appears in the notebook folder until the first task is added in Consulting, and that the area can be removed again while it has no tasks.
- **Notes and folders:** in Notes the sidebar is All notes and the folder tree. The main pane has a chip for each top-level folder and, inside one, a second row for the folders around you: a top-level folder's sub-folders, or deeper down the current folder among its siblings with a chip leading back up. The "All kinds" chip narrows the listing to Notes, Boards or Whiteboards. Folders still show as a grid or a list.
- **Between the two:** in Tasks › Personal the Notes button jumps to the Personal folder; in that folder the Tasks button (and the "Tasks in Personal" card) jumps back to Personal's tasks in the view you left. A wiki link, a search result or a board card opens once, in Notes.
- **Sidebar keyboard:** click a row, then use the arrow keys, type a name to jump to it, and Left/Right/Return/Space on folders. In Tasks the arrows move through the views and then the areas.
- **Wiki links:** type `[[` in a note. Option-click an underlined name in the preview to save it as a link. Rename a note and check that links to it update.
- **Tasks:** Today, Upcoming (grouped by day), List, Calendar (month and week; drag a task to another day, or use Move to) and Board (columns by due date; drag a card to another column to reschedule), each for All and for one area. Tick a task to complete it. Open a task: details, subtasks, comments, priority, owner.
- **Themes:** Settings → Appearance. Pick a preset, change the accent or any single color, and check that every screen follows.
- **Quick add:** `Call the vet tomorrow 5pm #Personal !p2`.
- **Boards and whiteboards:** open a `.kanban.md` board and an `.excalidraw.svg` whiteboard.
- **The notch:** hover over it or press Option-N. Try the notepad (Command-Return makes a task), Week, Clips (off until you turn it on) and Insights. Drag a card by the bar at its top to reorder the cards, or right-click the bar for Move Left and Move Right. Escape, a click anywhere else, or moving the pointer away closes it.
- **Clips:** turn it on in the notch's Clips pane. Copy some text, a web address, an image (in Preview, Edit › Copy) and a file in the Finder; take a screenshot to a file (Shift-Command-4) and one to the clipboard (Control-Shift-Command-4); drop a PDF on the notch. Each shows as its own kind, newest first, under Last hour: the address as a link card, both screenshots as pictures (the saved one called "Screenshot"), the PDF with its first page. Copy the same text again: it moves to the front, not in twice. The chips filter by kind; when the last of a kind goes, All comes back. A click copies and says Copied; hovering shows a remove button; right-click has Copy, Open Link or Show in Finder, and Remove. Drag a card into another app: text arrives as text, a link as an address, a file or saved screenshot as the file. Clear forgets everything and leaves your files alone. Clips older than 24 hours are gone, also after the Mac wakes from sleep; nothing about them is saved, so quitting Perch forgets them too.
- **Notch prompts:** give a task a due date of today and a time a minute from now. A tab drops out of the notch with **5 min** and **Done**; it never takes the keyboard from the app in front. Left alone it goes after 30 seconds and comes back five minutes later, twice. **5 min** brings it back in five minutes and writes nothing to the task. Move the task to tomorrow while its reminder is snoozed and it doesn't come back.
- **The focus timer** is hidden until you turn off Settings → Notch → **Hide the focus timer**. Shown, the workspace has a Focus card, task rows in Today have a play button, a running timer rides beside the notch (or in a tab under it when menus reach the notch), and a finished one asks from the notch. Turning the setting on again ends a session under way and logs it.
- **Notch settings:** Settings → Notch. "Notch animations" Full, Subtle (no bounce, stagger or flourishes) and Off (every change is instant); Reduce Motion in System Settings turns all of it into short fades. "Show the notch" off removes it at once and stops reminders being checked.
- **NotesHub compatibility:** in NotesHub, add `~/Perch-Test/vault` as a File System notebook and check the same notes, boards and the imported task files.
- **Sync:** Perch commits to the test copy about once a minute. `git -C ~/Perch-Test/vault log` shows each change.
- **Updates:** a build with no update source (`PERCH_UPDATE_REPOSITORY` empty, the default) shows its version and changelog under Settings → Updates and never checks. A build with one shows Check Now and the launch check too. About four seconds after Perch opens it asks GitHub for the latest release of that repository and offers Install and Restart when it's newer. That needs the GitHub App installed on that repository as well as on the notebook; until then Updates says so and links to GitHub.
- **New task:** every New menu (the sidebar, a folder's New chip, right-click) starts with New task, and File → New Task is Shift-Command-N. From a folder inside an area it opens quick add in that area.
- **Agents card:** with nobody active, the notch's Agents card lists what each agent did last, newest first: Claude with a spark, an agent the build names in `PERCH_AGENT_MARKS` with its mark (a dot or a house), anyone else by initial. Commits come from the notebook's history; status lines and messages come from the Relay when Perch is connected to it.
- **Mission Control:** with the notch running, a four-finger swipe up tiles every app, and the notch steps aside until Mission Control closes.
- **Account:** Settings → Notebook shows who is signed in and what the notebook syncs with. Sign Out stops sync and returns to the sign-in screen; signing in again reopens the same notebook. **Open a different notebook…** (Command-O) shows the chooser over the open notebook, with Cancel.

### iPhone

The iPhone needs a fine-grained GitHub token limited to your notebook repository, with **Contents: Read and write**. A build without a GitHub App connects with that token alone; a build with one can also sign in with GitHub.

### iPhone (development)

The iPhone app syncs with GitHub directly. Test it against a copy of the repository, not your real notebook. Open `Perch.xcodeproj` in Xcode, choose the **PerchPhone** scheme and your iPhone, and run it. TestFlight upload comes after this test.

What to check on iPhone:

- **Tabs:** Tasks, Notes, Agents, Search. Boards has gone: boards and whiteboards are files in Notes, and the "All kinds" chip there shows only one kind.
- **Tasks:** the area chips (All, then each area, then +) are pinned under the navigation bar and scroll sideways; under them is the view switcher (Today, Upcoming, List, Calendar, and Ready while something waits). The old "Today ⌄" title menu is gone. The title says where you are ("Personal · Calendar"). Try every view in All, in an area, and in an area added with +.
- **Notes:** top-level folder chips, then a row of sub-folders, then the browser. Choosing a folder changes the browser in place; opening a note pushes it, and Back returns to the same folder.
- **Jumps:** the folder button at the end of the area chips, and the checklist button at the end of the folder chips. A link in a task opens the note in the Notes tab; from Search and Agents a result opens in place.
- **Sizes:** on a narrow screen every bar scrolls rather than wrapping, at the largest interface size too. The view switcher shows icons and names where they fit, names alone where those fit, and otherwise scrolls; a name is never cut short. Rotate both screens.
- **Long press:** press and hold an area chip for quick jumps: that area's Today, Upcoming, List or Calendar, and its notes.
- **The focus timer** is hidden until you turn off Settings → Features → **Hide the focus timer** (the same setting as the Mac's). Hidden, there is no timer button in the Tasks toolbar, nothing starts a session or a Live Activity, and Insights leaves out focus minutes. Turning it on while a session runs ends the session.
- **Relaunch:** the app reopens on the section, area, view and folder you left.

### iPhone Duo (the folding phone)

The app picks its layout from two measurements, never from the device: the whole screen, and the room it is given inside the safe area. On the cover screen iOS keeps a column about 86 points wide for its status strip, toolbar buttons and tab bar (measured in the simulator: 382 of 466 points upright, 594 of 678 on its side). Nobody has measured the inner screen yet, so the layout is chosen to come out the same whether or not iOS keeps such a column there:

| Screen | Whole screen | Room for the app | Layout |
| --- | --- | --- | --- |
| Closed, upright | 466×678 | 382 wide | Tabs, area chips and the view switcher, as on any phone. |
| Closed, on its side | 678×466 | 594 wide | Tabs still, with the Board offered in the view switcher. iOS already draws the tab bar in its own column here, so a rail would only be a second column beside it. |
| Open, upright | 669×951 | 669, or about 583 beside a column | A rail of icons on the leading edge (Tasks, Notes, Agents, Search, sync, Settings) in place of the tab bar. The sidebar opens over the content as a drawer. One pane of content, with its chip bars and the Board. |
| Open, on its side | 951×669 | 951, or about 865 beside a column | The sidebar stays open beside two panes of content. |

The rules: 640 points of room is wide. A screen that is 640 wide and 600 tall is wide even when the room is less, as long as the rail leaves 440 points of content; that is the open phone upright beside a system column. The keyboard never changes the answer. The sidebar is 232 points and stays open wherever two panes of 310 fit beside it (853 points of room at the default interface size); otherwise it is a drawer over the 68-point rail. Content of 620 points or more is two panes, 500 or more is offered the Board, and 860 or more draws the week as seven columns.

What to check on the Duo, opened:

- **Sidebar:** Tasks | Notes at the top. In Tasks: Today, Upcoming, List, Calendar, Board and (while something waits) Ready to tick, then All and each area with its count and overdue dot, then Edit areas…; one view and one area are highlighted together. In Notes: a Show row (All, Notes, Boards, Whiteboards), All notes and the folder tree; chevrons open folders, a folder shows in the browser, a file opens in the pane. Then Agents and Search, and at the foot the sync status and Settings. While the sidebar is open the content has no chip bars.
- **Rail and drawer:** the button at the top of the sidebar folds it to the rail; the same button on the rail brings it back. So does a swipe on the rail or the sidebar itself: away from the leading edge to open, toward it to close. Esc on a keyboard closes the drawer. On its side the choice is remembered across launches. Upright the sidebar is a drawer: it closes when you pick a view, a file, Agents or Search, tap outside it, or swipe it away, and stays open while you pick an area or open folders.
- **Tasks, on its side:** picking a task shows it in the pane on the right instead of a sheet; its ✕ closes it. Drag the line between the panes to resize (it remembers). Beside Today, with nothing picked, the pane shows the week, Up next and any Ready to tick proposals. Beside Upcoming, List and Ready it says to choose a task. Calendar and Board take the whole width until a task is picked.
- **Board:** columns Overdue (only while something is overdue), Today, Tomorrow, This week (only while the week has days left after tomorrow), Later and No date. Drag a card to another column: Today and Tomorrow set that day, This week the day after tomorrow, Later the first day of next week, No date clears the date; a card already in the column keeps its own day, and nothing can be dropped on Overdue. Only `due:` changes in the task's file. On the closed phone upright a saved Board shows Upcoming and comes back when the phone opens.
- **Calendar:** Month is the grid of dots with the chosen day's list beside it. Week is seven columns with the sidebar folded to the rail when the app has the whole 951 points, and tiles of day lists with the sidebar open or when iOS keeps a column of the screen.
- **Notes, on its side:** the folder browser and the open note side by side, the open note highlighted in the browser and in the tree. The note's toolbar gains two buttons: hide or show the folder list (the note then has the whole width, and Edit puts its preview beside the editor), and ✕ to close the note (a back arrow after following a link inside it).
- **Search, on its side:** the field and results on the left, the picked note or task on the right.
- **Opening and closing mid-use:** open a task on the closed phone (a sheet), then open the phone: the sheet goes and the same task is in the pane. Close it again: the sheet comes back. Do the same with a note pushed in Notes (it becomes the note in the pane, and Back still works when closed), with a note being edited (it should still be in Edit, near the same line, with everything typed up to the moment the phone moved and no conflict markers), with Settings open (it stays open) and with the Board showing. Rename a note from its … menu while it is in the pane: it stays open under the new name. The section, area, view and folder never change. Scroll position in lists is not kept: the lists are drawn afresh.
- **Display settings:** Settings → Display. Interface size Extra Large widens the sidebar to 290 points. On its side there is still room for two panes beside it if the app has the whole 951 points; if iOS keeps a column, the sidebar becomes a drawer over the rail so the two panes stay. "Use wide layouts on large screens" off brings the tabs back on every screen.
- **Keyboard,** with one attached: ⌘1 Tasks, ⌘2 Notes, ⌘3 Agents, ⌥⌘F Search as on the Mac (the field takes the keyboard; plain ⌘F is left alone so it can't pull you out of a note you are typing in); ⌥⌘1 to ⌥⌘6 Today, Upcoming, List, Calendar, Ready to tick, Board; ⌥⌘[ and ⌥⌘] previous and next area; ⌘N a new note in Notes, otherwise the keyboard goes to Add a task; ⌘E edits the open note; ⌃⌘S shows or hides the sidebar and Esc closes the drawer; ⇧⌘S syncs. Hold ⌘ to see the list where iOS shows one. With a trackpad or mouse, rows and buttons highlight under the pointer.
- **VoiceOver:** every rail button, sidebar row (name, count, "some overdue", selected, expanded or collapsed), board column and the pane divider (adjustable) should be announced.

Things only the real device can show, so look closely: where iOS puts its own bars on the inner screen (on the closed screen the status strip, toolbar buttons and tab bar sit in a column, on the trailing edge upright and on the leading edge with the phone turned left; whether the inner screen keeps such a column decides only how wide the panes are, not which layout you get), where Back shows for a note pushed in the upright layout (in the simulator it is in the note's own bar beside the rail, or in the system's column on the cover screen; the scaled `-perchForceLayoutSize` pictures leave it out, which is the scaling and not the app), and how the change of layout looks while the hinge is moving.

### Tabs and split view (experimental)

Off by default. Turn it on in Settings › Experimental on the Mac, or Settings › Features on the iPhone. Nothing in the notebook changes either way, and turning it off puts everything back.

**On the Mac**

- A slim strip of tabs appears above the main pane. ⌘T opens a tab (Today in Tasks, the top folder in Notes), ⌘W closes it (with one tab left, ⌘W closes the window as before), ⇧⌘T brings the last closed tab back, ⇧⌘] and ⇧⌘[ (or ⌃Tab and ⌃⇧Tab) step through them, ⌘[ and ⌘] go back and forward inside a tab.
- ⌘-click anything that opens (a sidebar row, a note in a folder, a link inside a note, a search result) to open it in a new tab; ⌥⌘-click opens it in the other pane. The same two choices are in the right-click menu of sidebar rows, folders, files and tasks.
- ⌃⌘\ splits right, ⇧⌃⌘\ splits down, ⌥⌘\ moves the focus to the other pane, ⌃⌘W closes the split and keeps every tab. Drag the line between the panes; drag a tab along the strip to reorder it, onto the other pane to move it, or to the left, right or bottom edge of the content to split.
- Click in a pane and the sidebar follows it: the pane with the underlined tab is the one the sidebar and the Go menu talk to. The area chosen in the sidebar filters the task views in both panes.
- Open the same note in both panes and type in one: the other shows it at once, and there is one save. A tab's dot means typing that isn't on disk yet.
- The ⌄ menu at the end of the strip lists every tab, and under Workspaces saves the layout by name ("Planning": Today beside the Calendar) and brings it back.
- Things to try to break: close the last tab; rename or delete a note that is open in a tab that isn't in front; make the window as small as it goes while split; quit and reopen.

**On an open folding phone, or a phone on its side**

- The same strip sits above the content. Touch and hold a note, folder, task or sidebar row and choose Open in New Tab or Open to the Side. On its side the two panes sit side by side; upright they sit one above the other. Tap a pane to give it the focus; the sidebar follows.
- Fold the phone: the ordinary tab bar layout shows whatever the focused tab was showing. Unfold it: the tabs and panes are back, and if you went somewhere while it was folded, the focused tab went with you.
- On the cover screen there are no tabs at all, with the setting on or off.

**Without opening the app.** Snapshot steps build a workspace: `set:experimentalTabs=true` first, then `tabs:open:<place>`, `tabs:split:<place>`, `tabs:select:<n>`, `tabs:focus:left|right`, `tabs:fill:<n>`, `tabs:down`, `tabs:window:<w>x<h>` (the list is beside `case "tabs"` in `SnapshotRunner.swift`), where a place is `today`, `list`, `calendar`, `folder:<path>` or `file:<path>`. Put the `set:` step before a `duo:` step to draw the iPhone's wide layout with tabs. On the simulator, `-perchTabs "list|calendar" -perchSplit "file:Studio/Clients/Okafor garden room.md"` does the same, with `-perchForceLayoutSize 951x669` for the inner screen and `-perchForceLayoutUntil 4` to fold part-way through. Since the note reader's rework, a note's own text is not in the window's PNG; look at the `NN-web0.png` beside it.

**Removing it.** Delete `Sources/PerchKit/Navigation/Workspace.swift`, `Sources/PerchUI/WorkspaceStore.swift`, `Sources/PerchUI/WorkspaceViews.swift`, `Tests/PerchKitTests/WorkspaceTests.swift` and `Tests/PerchKitTests/WorkspaceStoreTests.swift`, then follow the compiler: every hook in the other files is a line or two marked `Tabs:`.

## Part 2: MCP and agents

1. Start a Relay on the test copy:
   ```sh
   cd Relay && npm ci && npm run build
   export PERCH_RELAY_CONFIG=~/Perch-Test/relay.config.json
   node dist/src/index.js init ~/Perch-Test/vault
   node dist/src/index.js add-agent claude-code
   node dist/src/index.js add-agent robin
   node dist/src/index.js add-agent perch-app
   node dist/src/index.js serve
   ```
   Each `add-agent` prints a token once. Keep them somewhere safe.
2. Connect Claude Code:
   ```sh
   claude mcp add --transport http perch http://127.0.0.1:8787/mcp --header "Authorization: Bearer <claude-code token>"
   ```
3. In Perch's Settings, under **Agents**, enter `http://127.0.0.1:8787` and the `perch-app` token. Agents then appear in the notch and the app.
4. Watch a scripted demo: `node Relay/scripts/demo.mjs ~/Perch-Test/relay-tokens.txt` runs Robin and Claude Code side by side, with a claim, a blocked write, a proposed completion and a message.
5. Ask two agents to work at once. For example, ask one to claim a note and summarize it while the other adds a task, and watch presence, claims, Ready to tick and the activity history.
6. Check what agents are told. Ask a connected agent "What did the Perch server tell you, and what does its guide tool say?" It should describe the notebook's areas, the task format, the order to work in and the rules without being told any of it in the chat. The text lives in `Relay/src/tools.ts` (`INSTRUCTIONS` and `GUIDE`); see `Relay/README.md`.

To see agent edits in the app as they happen, open the test copy itself in Perch (**Open a different notebook…**, then **Use a Git repo on this Mac**, then `~/Perch-Test/vault`). A test copy made from a notebook already on this Mac needs no GitHub sign-in: `scripts/make-test-vault.sh <its folder>`.


## Formatting notes

Color, highlight, underline and text size are saved in the note itself, as Markdown or small HTML tags that NotesHub and GitHub also read. Nothing is kept anywhere else.

| Format | In the file |
| --- | --- |
| Bold, italic, strikethrough | `**x**`, `*x*`, `~~x~~` |
| Highlight (yellow) | `==x==` |
| Highlight (a color) | `<mark style="background-color: #3B82D9">x</mark>` |
| Text color | `<span style="color: #D94F3D">x</span>` |
| Underline | `<u>x</u>` |
| Text size | `<span style="font-size: 1.15em">x</span>` (0.85em, 1.15em, 1.3em or 1.6em) |
| Subscript, superscript | `~x~`, `^x^` (each word gets its own: they can't hold a space) |
| Centered or right-aligned | `<div align="center">`, a blank line, the text, a blank line, `</div>` |

**On the Mac**, edit a note (⌘E) and use the format bar above the text, the Format menu, or right-click a selection. With nothing selected a format applies to the word under the caret. Things to check:

1. Select a few words and pick a color from the **A** button. Pick a second color over part of them: the file has side-by-side spans, never one inside another. Choose Automatic: the span is gone and the text is exactly as it was.
2. Select across two list items and make them bold or colored: each item gets its own marks, and the `- ` and `[ ]` stay outside them.
3. Move the caret onto a line with a color: its `<span …>` tags appear, small and dim. Move off: they hide. After a click they appear a moment later, once the mouse is up, so the words don't move under a double-click or a drag. Only tags whose effect the editor draws are hidden (color, highlight, underline, size and the like); `<br>`, `<kbd>`, `<details>`, `<img>` and `<div align>` always show. Settings › Editing › Hide formatting tags while editing turns this off.
4. With tags hidden, press Backspace at the start of colored text, or Delete at its end: the whole pair of tags goes and the words stay, as one step to undo. Half a tag is never left behind. With the setting off, tags are plain text and each key deletes one character.
5. The bar's buttons light up for what is at the caret (bold, heading level, list kind, color).
6. Press Tab in a table to go to the next cell; Tab in the last cell adds a row.
7. Each command is one step to undo (⌘Z).
8. Select `(bar)` in the middle of `foo(bar)baz` and press ⌘B: the file gets `foo(**bar**)baz`, because Markdown doesn't read `foo**(bar)**baz` as bold. ⌘B again takes it off.
9. Put the caret in inline code, a code block, an indented code block, frontmatter, a link's address or a block of raw HTML (`<details>` … `</details>` with no blank lines inside) and try any format: nothing happens. Quote and callout work on a whole code block, never on part of one.
10. In a narrow editor (split view) the bar folds its less-used commands into the ••• menu. Settings › Editing › Show format bar above the editor hides it; the shortcuts and the menu still work.

| Shortcut | Does |
| --- | --- |
| ⌘B, ⌘I, ⌘U | Bold, italic, underline |
| ⇧⌘X, ⇧⌘H | Strikethrough, highlight |
| ⇧⌘C | Show the color palette |
| ⇧⌘. and ⇧⌘, | Larger and smaller text |
| ⌃⌘1, ⌃⌘2, ⌃⌘3 | Heading 1 to 3 (again for body text). ⌥⌘1 to ⌥⌘6 are the task views. |
| ⇧⌘7, ⇧⌘8, ⇧⌘9 | Numbered, bulleted and task list |
| ⌘K, ⇧⌘K | Link, link to a note |
| ⌘\ | Clear formatting (keeps links and code) |

**On the iPhone**, the bar above the keyboard has the common formats. **Aa** swaps the row for headings, text size, alignment and blocks; the **A** with a colored bar swaps it for the palette (text or highlight, the ten colors, recent colors, and a custom color). The arrow at the left goes back. Nothing opens a sheet except the custom color picker, so the keyboard and selection stay put. With the phone unfolded (640 points or wider) headings and text size are in the main row. Selecting text and opening the edit menu shows a Format group. With a keyboard attached, the Mac shortcuts above work.

A format is only written where it will read back as that format. Where it wouldn't (bold ending against a lone `*`, a color across half of `x^2^`), the command does nothing rather than leave marks showing in the text.

`swift test --filter FormattingFuzzTests` checks all of this on made-up notes: a fifth of them on an ordinary `swift test` (about half a minute), all of them with `PERCH_FUZZ=full`, and ten times as many with `PERCH_FUZZ=10`. A failure prints its seed, selection and note.

Typing `/` at the start of a line also offers callouts by type, a table, centered and right-aligned text, highlight, underline, text size and `Colored text: Red` (and the other nine colors).

## Checking visuals without opening the app

The debug build can draw screens offscreen to PNG files. It reads the notebook you name, never syncs it, and leaves the app's saved settings alone. The examples use a dated copy of the demo notebook, so they work on any Mac; any test copy works the same way:

```sh
scripts/demo-notebook.sh /tmp/perch-demo
xcodegen generate --quiet
xcodebuild -project Perch.xcodeproj -scheme PerchMac -configuration Debug -derivedDataPath .build/debug build
.build/debug/Build/Products/Debug/Perch.app/Contents/MacOS/Perch \
  -perchSnapshotDir /tmp/perch-shots -perchSnapshotVault /tmp/perch-demo \
  -perchSnapshotScript "today;upcoming;list;calendar:month;calendar:week;folder:Studio"
```

The notch is drawn on a stand-in desktop, in any state or moment of its opening, without ever showing its real window:

```sh
.build/debug/Build/Products/Debug/Perch.app/Contents/MacOS/Perch \
  -perchSnapshotDir /tmp/perch-notch -perchSnapshotVault /tmp/perch-demo \
  -perchSnapshotScript "notchscreen:1470;notchclosed;notchpeek;notchframe:0.5;notchframe:1.08;notchmode:workspace;notchmode:week;notchmode:insights;notchmode:clips;notchlive:reminder;notchlive:agent;notchlive:event;notchopen:prompt;notchcomplete:0.4;set:focusHidden=false;notchmode:workspace;notchlive:focus;notchlive:noroom;notchlive:focusdone;notchfocus:running;notchdrag:focus"
```

- `notchscreen:<width>[:nonotch][:dark]` picks the desktop for the steps after it (1470 wide, notched and light until then). Try 1147 for the narrowest panel, 1920 for the widest, and `nonotch` for an external display.
- `notchclosed`, `notchclosed:bare`, `notchpeek`: the notch at rest with and without today's counts, and swollen under the pointer.
- `notchframe:<progress>`: the opening held part-way, 0 to 1. `notchframe:-0.05` and `notchframe:1.08` show a spring's overshoot at each end.
- `notchmode:workspace|week|insights|clips`: the open panel. Clips is drawn with stand-in clips of every kind across Last hour, Earlier today and Yesterday; the pictures are drawn in code and nothing is read from the pasteboard or the disk. `notchmode:clips:text|links|images|files` picks a filter, `notchmode:clips:hover` shows the first card under the pointer, `notchmode:clips:prompt` adds a prompt at the foot (the cards shorten), and `notchmode:clips:empty` and `notchmode:clips:off` show those states.
- `notchlive:reminder|agent|event|focus|noroom|paused|focusdone`: the closed notch asking something, or carrying the timer (`noroom` is the timer in a tab under the notch because menus reach it).
- `notchopen:prompt`: the open panel with a prompt in its own row at the foot. `notchcomplete:<0–1>`: the first task mid-tick. `notchdrag:<today|focus|notepad|agents>[:<points>]`: a card held mid-reorder. `notchfocus:running|paused`: the Focus card with a session under way.
- The focus timer is hidden, as in the app, until a `set:focusHidden=false` step. The steps that are about the timer show it for that one step anyway.
- `theme:<id>` before a notch step changes the card tints, and `settingswindow:notch` draws the Notch settings pane.
- Moments of a movement, each where the app's own curve (`Motion`) would have it, for the frames of a clip: `notchpeek:<0–1>` is the swell under the pointer held part-way; `notchmove:open:<seconds>` is the pointer resting on the notch (the swell, then the panel opening after `NotchHover.openDelay`, its content arriving item by item); `notchmove:close:<seconds>` the panel going back with the counts returning; `notchmove:prompt|promptaway:<seconds>[:reminder|agent|event|focusdone]` a prompt dropping out of the closed notch or going back; `notchmove:live|liveaway:<seconds>[:<elapsed>]` the focus timer widening the notch, that many seconds into a session; `notchtick:<seconds>[:<done>]` the first of today's tasks ticked in the open panel that long after the click (negative while the pointer is still arriving), with `<done>` tasks before it already ticked, in memory only.
- `notchscreen:<width>:tall` draws every step at the open panel's size, so closed and open frames are one picture size, and `notchscreen:<width>:still` holds every open panel fully arrived, with nothing repeating. `-perchSnapshotAgents <file.json>` and `-perchSnapshotClips <file.json>` replace the built-in stand-in agents and the words of the stand-in clips (`Demo/agents.json` and `Demo/clips.json` show the form).

The first-run screens are drawn with stand-in GitHub replies: `onboarding:signin`, `onboarding:code`, `onboarding:choose`, `onboarding:empty` (no repositories yet), `onboarding:cloning` and `onboarding:failed`. `onboarding:local` is the first run of a build with no GitHub App, which offers a folder on this Mac.

Add `-perchSnapshotLight` for light mode. A `wait:<seconds>` step sets how long the steps after it wait before their picture (3 seconds until then, 6 for a whiteboard); it draws nothing itself. `-perchSnapshotComposite` draws each note page and whiteboard into the window's PNG (the web view's own drawing never reaches it), and `-perchSnapshotFlatSidebar` draws the main window's sidebar as a plain column beside the same main pane, because the system's glass sidebar draws nothing in an off-screen window. `hideareas:Personal` and `areaorder:Studio,Home` hide and order areas for the run, as Edit areas would, and save nothing. Other steps include `theme:<id>`, `task:<id>`, `file:<path>`, `notemode:read|edit|split`, `size:<width>x<height>`, `duo:<width>x<height>[:expanded|rail|drawer]` (the iPhone's wide-screen shell: sidebar or rail, and panes; `tab:agents|search` then picks those destinations, and `view:board` shows the Board), `themesettings` and `sidebar` (it replaces the window's content, so put it after the main-pane steps).

Every run starts on Tasks › All › Today. Widths under 700 also fold a task view's filter controls behind the button at the end of its counts line, as a phone does. Steps for sections and scope: `section:tasks|notes` switches section, back where that section was left; `scope:<area>` scopes the task views (`scope:work` finds "✈️ Work"; a bare `scope:` is All); `view:today|upcoming|list|calendar|board|ready` changes the view and keeps the scope, as `today`, `upcoming`, `list` and `calendar` do; `areas:Consulting,Other` adds areas by name for that run; `noteskind:all|notes|boards|whiteboards` filters Notes; `areaeditor[:<width>x<height>]` draws the Edit areas sheet. `area:<name>` still works: it scopes Tasks to that area and shows its List. `sidebar:tasks` or `sidebar:notes` draws the sidebar for one section, and section, scope, view and folder steps after it redraw the sidebar, so `...;sidebar:tasks;scope:personal;section:notes` gives three sidebar pictures. After `size:`, widths under 700 draw as a phone does and widths of 800 or more put the sub-sections in a column, as the iPhone does:

```sh
  -perchSnapshotScript "size:380x640;scope:studio;upcoming;calendar:month;areas:Consulting;scope:consulting;list;section:notes;folder:Studio/Clients"
```

Settings can be changed for one run, and are never saved: `set:<key>=<value>` for text and on/off settings (`set:displayInterfaceSize=extraLarge`, `set:displayDensity=compact`, `set:editorHighlightLine=true`, `set:editorIndent=2`) and `reading:<key>=<value>` where a number is wanted (`reading:readingTextSize=2`). A screen already showing picks the change up, so `file:<path>;reading:readingHeadingFont=serif` shows the reader restyling an open note. `settingspane:display|reading|editing[:<width>x<height>]` draws one settings screen on its own, and `settingswindow[:<pane>]` draws the Mac's Settings window. The keys are listed in `DisplaySettings.Key`, `ReadingSettings.Key` and `EditingSettings.Key`.

The note editor's format controls can be drawn on their own, with a made-up selection: `format:bar[:<width>x<height>]` is the Mac's bar (try `format:bar:520x110` for the folded one), `format:palette` and `format:highlightPalette` its color popover, and `format:keyboard`, `format:keyboardStyle` and `format:keyboardColor` the iPhone's keyboard bar and its two strips (`format:keyboard:380x110` for a closed folding phone, `format:keyboard:669x110` for an open one). In a note, `notemode:edit;file:<path>` shows the bar above the editor, and `set:editorHideFormatTags=false` shows every formatting tag.

The iPhone app's debug build takes similar launch arguments in the simulator, alongside `-perchLocalVault`: `-perchSection tasks|notes`, `-perchScope <area name>` (`work` finds "✈️ Work"), `-perchView today|upcoming|list|calendar|ready`, `-perchCalendarMode month|week`, `-perchFolder <path>`, `-perchNotesKind all|notes|boards|whiteboards`, `-perchExtraAreas "Consulting,Other"` (areas added for that launch only), `-perchTab agents|search`, `-perchOpen <path>`, `-perchTask <id>`, `-perchSearch <text>`, `-perchSettings root|areas|theme|display|reading|editing` and `-perchTheme <id>`. `-perchView` also takes `board`. For the wide layouts: `-perchSidebar expanded|rail|drawer`, `-perchNotesBrowser shown|hidden`, `-perchNoteMode read|edit|split`, and `-perchForceLayoutSize <width>x<height>`, which lays the app out as if it had that much room and scales the result to fit the screen, so the Duo's inner screen (`951x669`, `669x951`) can be looked at on a simulator that only lights the cover screen. `-perchForceLayoutAfter <seconds>` starts at the real size and switches to the forced one after that long, and `-perchForceLayoutUntil <seconds>` does the reverse: either stands in for opening or closing the phone mid-use. `-perchForceLayoutColumn 86` takes a system column off the forced width (`669x951` then lays out in 583), `-perchPretendScene 678x951` tells the layout the screen is that big while drawing unscaled in the real room (with the simulator turned on its side it shows the rail at full size beside the real system column), and `-perchLayoutReadout` prints the measured screen, the room and the layout chosen along the bottom edge. Any saved setting can be given the same way, for that launch only (`-displayInterfaceSize extraLarge -displayMatchSystemTextSize NO`, `-focusHidden NO`). A launch that names a section, scope, view, folder or extra areas reads what was saved but doesn't save where it ends up.

### Clips for the website

`scripts/site-media.sh` makes the website's looping clips from these snapshots, on a dated copy of the demo notebook (`Demo/README.md`) made for the Debug app's own owner (`PERCH_OWNER_ID`, read from the built app), so the notebook's tasks are the user's own in it. It builds the Debug app when anything under `Apps`, `Sources` or `Config`, or `project.yml`, is newer, runs the snapshot runner once per scene, and joins the pictures with ffmpeg into `site/media/`: an H.264 `.mp4`, a VP9 `.webm`, a poster `.jpg` per scene, a `.gif` for the three README scenes, and `manifest.json` listing each scene's files, size and length. `site/media/` is not kept in Git.

```sh
scripts/site-media.sh                                     # every scene, about a quarter of an hour
scripts/site-media.sh --scenes notch-open,tasks --contact-sheet /tmp/sheet.png
scripts/site-media.sh --scenes agents --out /tmp/clips    # one scene, somewhere other than site/media
```

The frames go in a new temporary folder each run, or in `--work <folder>`, which must be new, empty, or one the script made before (it leaves a `.perch-site-media` file there and deletes only inside such a folder). Each scene's poster, the still a reader with reduced motion sees, is the frame at the `poster` time in the scene's definition, chosen to show what the scene is about.

Where the runner can hold a moment (the notch opening and closing, a prompt dropping, a tick, a note scrolling), every frame at 60 fps is its own picture, so the motion is the app's. Changes of view, mode or theme are stills joined by short eased crossfades. Each clip ends on its first picture. The settings a run would otherwise read from the Mac's own Perch settings are pinned at the top of `scripts/site-media/site_media.py`, so the clips come out the same on any Mac. The scenes are defined there too, each a few lines.

## Stress-testing navigation

The debug build can drive Perch's main view in a window of its own: it moves between places, opens task panels and closes them every way a person does (the X, Esc, Cmd+W, with the sidebar toggled or the place changed while a panel is open), and counts each time the window closed, a panel stayed open, a panel closed by itself, or a panel was selected but not on screen. It runs on a copy of a notebook with sync off, never reads the Keychain or the Relay, never saves window positions, and makes its window off screen, so it can run while you work:

```sh
rsync -a --exclude .git ~/Perch-Test/vault/ /tmp/perch-stress-vault/
open -n -g -W -a "$PWD/.build/debug/Build/Products/Debug/Perch.app" --args \
  -perchNavStress /tmp/perch-stress-vault /tmp/perch-stress.json -perchNavStressSteps 150 -perchNavStressSeed 46
```

Start it with `open -n -g` as shown. The result lists a tally for each way of closing and every failure with its place. The last line of the log is a control: with no panel open, Cmd+W must still close the window. Add `-perchNavStressHold <seconds> <file>` (and `-perchNavStressHoldPanel` for a panel) to finish on the List, write the window's number to the file and wait, so `screencapture -l <number>` can take a picture of the window, title bar included, while it is parked. `-perchNavStressWidth <points>` sets the window's width.

Add `-perchNavStressNotes` for the note editing test instead. For three small, three medium and three large notes (or one, with `-perchNavStressNote <part of its path>`) it times the preview after opening, the editor after Cmd+E, the preview catching up while it types a line at twelve characters a second, the preview after it is turned back on, and the reader after Done, and how long each keystroke held the main thread. While a run types, `sample <pid> 3` shows where the time goes.

To find notes that draw wrongly in a real notebook, the opt-in survey draws every note in a copy through the reader and lists tables left as text, error boxes and Markdown marks left showing:

```sh
PERCH_RENDER_SURVEY=/tmp/perch-stress-vault PERCH_RENDER_SURVEY_OUT=/tmp/survey.json swift test --filter RenderSurveyTests
```

## Checking how notes are drawn

Notes are drawn by a web page built from `Web/src/render.js` into `Apps/Shared/Web`. The page has its own tests,
which run the built page in an offscreen WebKit view (the same engine both apps use) and look at what it drew.

```sh
scripts/render-tests.sh                 # rebuild the page, then run every rendering test (about 25 seconds)
scripts/render-tests.sh --bench         # timings: page load, first text, everything drawn, an edit
scripts/render-tests.sh --stills out/   # pictures of fixtures; add notes, themes and a width to choose
swift test --filter PerchRenderTests    # the same tests without rebuilding; `swift test` runs them too
```

The notes they draw are in `Tests/Fixtures/Rendering`: hand-written ones for code in some forty language tags,
tables, lists, callouts, maths, Mermaid, ABC music, wiki links, raw HTML, pictures, frontmatter, Windows line
endings, colour formatting, content wider than a phone, and two hostile notes (`xss.md`, and `xss-more.md`
for forged controls, odd link schemes, and Mermaid, KaTeX and CSS tricks). The stress notes
(`stress-5000-lines.md`, `stress-200-code-blocks.md`) and the `bench-*.md` notes are written by
`node scripts/make-render-fixtures.mjs`; run it again after changing it.

What the tests hold the page to:

- Every fixture draws completely, with an error box only where the fixture has a deliberate mistake.
- The text inside a code block is the note's text exactly: nothing lost, nothing interpreted, tabs and trailing
  spaces kept. Known language tags and their aliases (`sh`, `c++`, `tsx`, `yml`…) are coloured; unknown tags and
  untagged blocks stay plain and are never guessed at; the label is the tag as written.
- Nothing is wider than the page at 380, 669 and 951 points, with long code lines wrapping or scrolling; wide
  code, tables and formulas scroll inside their own box.
- Scripts and event handlers in a note never run, inline styles are cut down to a short allowlist, and nothing
  is fetched from outside the app. Re-run these after any change to how HTML reaches the page.
- Syntax colours, author-chosen text colours and highlights have at least 4.5:1 contrast on every built-in theme
  (3:1 for comments).
- An edit rebuilds only the block that changed; a theme or reading-setting change rebuilds nothing; a page reached
  by a series of edits is identical to one drawn fresh.
- A note with only text fetches none of the heavy libraries. Each is fetched the first time a note needs it.
- The page allows no `eval`, and its own libraries never trip its content policy.
- A note replaced while its libraries are still loading leaves nothing behind; 300 notes through one page leave
  the page as it began; any run of random edits (`PERCH_RENDER_EDIT_STEPS=400` for a longer one) ends on the page
  a fresh render gives, source lines included.
- A library that can't be loaded leaves the block readable as written. While the page is hidden nothing is drawn
  in the background; `settle()` (a PDF, a snapshot) still finishes everything and loads every picture.
- Picked text colours and highlights are drawn exactly as the editor draws them. Both sides are held to
  `Tests/Fixtures/Rendering/legible-colours.json`: `SharedColourTableTests` checks `FormatPalette`, the page tests
  check `Perch.color`. After changing the rule on purpose, write the table again with
  `PERCH_WRITE_COLOUR_TABLE=1 swift test --filter SharedColourTableTests` and change the JavaScript to match.

Two tests are skipped unless asked for: `RenderBenchTests` (`--bench`) and `RenderStillTests` (`--stills`).

The tests share a few web views between them (`RenderPage` hands a closed page's web view to the next page and
loads the reader in it afresh). This is needed: the 64th web view put in an offscreen window in one test run
never loads. A test that needs a clean page calls `startOver()`, or closes its page and makes another. The bench
makes a new web view for every measurement, so run it by itself, as the script does.

`PERCH_WEB_ROOT=<folder>` points the tests at another build of the page, which is how before-and-after timings
and pictures are made (`git archive <commit> Apps/Shared/Web | tar -x -C <folder>`).

In a snapshot run, each `NN-web0.json` also reports `timing` (milliseconds for parsing, building, first text,
colouring code, maths, diagrams, and `settled` for everything), `openToTextMs` (from the note's view being made
to its text being on screen), counts of code blocks and how many were coloured, `pending` (should be 0), and
`overflowX` (should be 0). `webscroll:0.5` scrolls the note on screen halfway down for the next picture.

After changing anything under `Web/`, run `npm run build` there and commit `Apps/Shared/Web` with it: the apps
ship that folder as it is, and `git status` should be clean after a build. The build also writes
`Apps/Shared/Web/THIRD-PARTY-NOTICES.txt`, the licences of everything bundled into the pages, from what was
actually bundled; it changes when a dependency does.

## Releasing

Releases are made by the maintainer from the private working copy. The steps, and the TestFlight
setup, are in TESTING-PRIVATE.md there. A build from source has no update source by default
(`PERCH_UPDATE_REPOSITORY` in `Config/Perch.xcconfig`), so it never looks for releases.
