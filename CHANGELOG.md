# Changelog

What changed in each release of Perch, newest first. Perch shows this in Settings, Updates, and each release's notes on GitHub come from its section here.

## 0.2.7 (2026-11-11)

- Rename a note from the sidebar or a folder: right-click it and choose Rename. Links to it update, the same as before.
- While editing a note, its title in the title bar is a text field. Click it, type the new name and press Return (or click away). Esc puts the old name back.
- Renaming a note that is open keeps anything typed in the last moment, and the note stays in the editor under its new name.

## 0.2.6 (2026-11-11)

- Tabs and split view, to try out. Turn on Tabs and split view in Settings, Experimental on the Mac (Settings, Features on the iPhone). The main pane gets a strip of tabs, each with its own back and forward, and can show two places side by side or one above the other. Command-T opens a tab, Command-click opens something in a new tab and Option-Command-click opens it in the other pane. With the setting off, Perch works as before.
- On an open folding iPhone the same tabs and panes sit above the content; folding it shows the tab you were in.
- A note you close no longer stays in memory, and a note's page that has been out of sight for half a minute lets go of what it drew and draws it again when you come back.
- A picture that can't be loaded and stands as a block of its own (an HTML image, or a picture with a caption) keeps its "Missing image" note while you edit elsewhere in the note. Before, the next keystroke turned it back into a broken picture.

## 0.2.5 (2026-11-11)

- Tidy Table, in the editor's table menu and Format, Table (Control-Command-T): pads every cell so a table's columns line up in the editor, keeping each column's alignment. Short rows get empty cells, nothing is dropped, and the caret stays in its cell.
- A task's panel scrolls with the pointer anywhere over it. Over the details it didn't, so the subtasks and activity below were out of reach.
- Perch updates itself on the Mac: it looks every few hours as well as at launch, downloads a new version in the background, and moves to it when you haven't used it for a minute or when you quit it. Settings, Updates turns this off. (From this version on; 0.2.4 and earlier still ask once.)
- Releases can go to TestFlight for the iPhone by themselves, with a GitHub workflow and an App Store Connect key (see TESTING.md, Releasing).

## 0.2.4 (2026-11-11)

- A task's panel on the Mac no longer closes by itself. It is now Perch's own column beside the list or note, shown exactly while a task is selected; drag its left edge to change its width.
- The preview keeps up while you type: it redraws about eight times a second instead of waiting for you to stop, and less often in a very long note so it never falls behind.
- Typing in a long note no longer stutters. Each keystroke used to compare the whole note three times and count its lines one character at a time; in a 490 KB transcript a keystroke went from about 120 ms to under 30.
- Bold, strike-through and highlight that end in punctuation right before a word now show as intended, as in `**Label:**Text`, including in tables. Underscores keep the strict rule, so `snake_case_names` stay as they are.

## 0.2.3 (2026-11-11)

- Esc, or the X, on a task's panel closes only the panel. Before, it could close the whole main window.
- Cmd+W closes an open task panel first. With no panel open it closes the window, as before.
- The top of the window and the edges around the sidebar take the theme's background instead of the system's grey (macOS 15 and later).
- Notes show when each was created and last edited, from the notebook's Git history, and folders sort and filter by those dates.
- The iPhone no longer hangs on Notes, the task filters or Ready to tick on iOS 27.1: those screens always use their stacked layout there.

## 0.2.2 (2026-11-10)

- Settings, Agents shows whether Perch is connected to the Relay: Connected with how many agents are working, or why not (token refused, Relay not answering, or an error code). The button says Reconnect once connected.
- A pasted app token loses the line break copied from its file. The Relay refused a token with one, and Connect seemed to do nothing.

## 0.2.1 (2026-11-10)

- A calmer Notes bar: folder chips without grey fills, a count only on the folder you're in, and the folders inside it as plain tabs with a line under the current one.
- A bar with more folders than fit fades at its edge instead of cutting a name in half.
- A top-level folder no longer repeats its name in a path above the title.
- Ready to tick says who asked and how long ago, whether they think the task is done or no longer needed, and why. The buttons say what they do: Mark done or Close task, and Keep open.
- The notch explains Ready to tick in one line (agents ask you before closing a task) and shows one proposal at a time, with a link to the rest.
- Click the agent on a proposal, or an agent working in the notch, to open the Claude or Codex session it was in. A task's page also says what the agent was doing when it asked.
- The Relay records when each proposal was made, from which session, and the agent's status at the time. Proposals made before this release have no link.

## 0.2.0 (2026-11-10)

- Sign in with GitHub on the Mac, then clone a notebook from GitHub or open a Git repository already on the Mac.
- A notebook cloned in Perch syncs as your GitHub account and commits with your GitHub noreply address.
- The notch's Agents card shows what Dot, Claude and another agent did last when nobody is working, each with its own mark.
- Hovering the notch is steadier: the same target over every app, the panel closes when you move away, clicks beside it reach the app underneath, and it doesn't reopen right after you close it.
- Mission Control works again. The notch steps aside while Mission Control is showing, instead of leaving an empty desktop.
- Clicking Perch in the Dock brings back one window, never two.
- Editing with the preview beside: lines sit level on both sides, and scrolling either side moves the other.
- New task in every New menu, and File, New Task (Shift-Command-N), adds to the area of the folder you're in.
- Settings, Updates: Perch checks GitHub for a newer release when it opens, installs it for you, and shows this changelog.
- Agents learn how Perch works from the Relay's guide tool, and the Relay's bridge can read its token from a private file.

## 0.1.0 (2026-11-09)

- The first build: notes and tasks over a private notebook repository in NotesHub's formats, with a Todoist import.
- The Mac app with the notch (today's tasks, notepad, week, focus timer, clips, reminders and agents) and themes.
- The iPhone app with GitHub sync, widgets, a Live Activity, share capture and the wide layout for the Duo.
- The Perch Relay, an MCP server that lets AI agents work in the notebook beside you.
