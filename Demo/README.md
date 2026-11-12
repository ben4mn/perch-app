# The demo notebook

`Demo/notebook` is a Perch notebook you can open to try the app, and the notebook the website's clips are made from. It is plain files in the same layout and formats as any Perch notebook, and it passes `swift run perch verify Demo/notebook` (so does every dated copy; `swift test --filter DemoNotebookTests` checks both).

Every name, place, business and detail in it is invented. Nell Ashby runs a two-person studio with Tomas Reyes that designs and builds garden rooms and small cabins. The notebook is hers: client work in **Studio**, the house, allotment and family in **Home**, and an evening timber-frame course, the fiddle and drawing in **Learning**. Any resemblance to a real person, firm or place is by accident.

## Making a dated copy

The files are written as if today were 12 November 2026. A copy made on another day would be full of stale dates, so make one with today's dates instead:

```sh
scripts/demo-notebook.sh ~/Perch-Demo                 # dates moved so that "today" is today
scripts/demo-notebook.sh ~/Perch-Demo --date 2027-03-01
scripts/demo-notebook.sh ~/Perch-Demo --owner sam     # for a build whose PERCH_OWNER_ID is sam
```

Every `YYYY-MM-DD` in the notebook, in file names and inside files, moves by the same number of days, so what was due today is due today, what was three days overdue still is, and links to dated notes such as `2026-11-10 Okafor site visit` still find them. File modification times are set from `Demo/edited.tsv` (notes) and from each task's own dates, so folders sort the way a lived-in notebook would. The words were written for late autumn, so a copy made in June will still talk about frost and garlic.

Nell's own tasks are `owner: me` and her comments `@me:`, because `me` is the owner of a build with nothing configured (`PERCH_OWNER_ID` in `Config/Perch.xcconfig`), so they show as yours. A build with another owner shows them as someone else's; make its copy with `--owner <that id>` and they are yours again. `scripts/site-media.sh` does this with the Debug app's own owner.

In a build with no GitHub App (the default), choose **Open a notebook folder** on Perch's first run, or **Open a different notebook…** later (Command-O), and pick the copy. It opens without sync; run `git init` in it first if you want Perch to commit as you go. A build with a GitHub App asks for **Use a Git repo on this Mac**, so run `git init` first there. The areas are the notebook's own three folders, and nothing else. In Settings, Notch, set the notepad folder to `Daily` to see the day's notepad in the notch.

## What is in it

- **49 tasks** across the three areas: six overdue, eight due today (one at a set time with a reminder), more in the coming days and weeks, some with no date, five that repeat (daily, weekly, monthly), and nine done over the last week. Labels group the client jobs (`okafor`, `lindqvist`, `pell`). Some have details with checklists, comments under Activity, a deadline, or subtasks (the Lindqvist planning drawings). Nell owns 45 of them, Tomas two and Claude two, and Claude has proposed three as done, one of them as no longer needed, so they wait in Ready to tick.
- **28 notes** in folders, with a board, a whiteboard and a picture. Between them they use what the reader draws:
  - headings, lists, checklists, callouts, highlights and a footnote: `Studio/Clients/Okafor garden room.md`, `Learning/Timber frame course/Module 3 - joints.md`, `Studio/Process/Handover checklist.md`
  - tables: the payment and glazing tables in the Okafor note, `Studio/Suppliers.md`, `Home/Garden/Allotment plan.md`, `Learning/Fiddle/Practice log.md`
  - a picture (an SVG elevation in `Studio/Clients/.attachments`): `Studio/Clients/Okafor garden room.md`
  - a code block: `Studio/Process/Cladding calculator.md`
  - formulas: `Learning/Timber frame course/Rafter sizing.md`, `Studio/Process/Pricing a garden room.md`, `Home/Recipes/Sourdough.md`
  - diagrams: a flowchart in `Studio/Process/Build sequence.md`, a Gantt chart in `Studio/Clients/Lindqvist cabin.md`
  - music: a tune in ABC in `Learning/Fiddle/Tunes to learn.md`
  - links between notes: 29 wiki links, all of which resolve
  - a NotesHub board: `Studio/Studio board.kanban.md`; a whiteboard: `Studio/Lindqvist floor plan.excalidraw`
  - a day's notepad in `Daily/`

## For the clips

Two files outside the notebook hold what a notebook doesn't: `Demo/agents.json` is who the notch shows as working in the notebook, Claude and an assistant called Wren (the Relay tells the app this in real use), and `Demo/clips.json` is the words of the stand-in clips in the Clips pane. Both are read only by the Debug build's snapshot runner. `scripts/site-media.sh` makes the clips; see TESTING.md, "Clips for the website".
