# Third-party code and fonts in Perch

Perch's own code is under the MIT licence in [LICENSE](LICENSE). This file lists what it carries from
others, and where each licence text is.

## In the apps

Both apps ship the folder `Apps/Shared/Web`: the page that draws notes and the whiteboard. It is built
from open-source JavaScript packages by `Web/build.mjs`, which also writes
[Apps/Shared/Web/THIRD-PARTY-NOTICES.txt](Apps/Shared/Web/THIRD-PARTY-NOTICES.txt). That file lists every
package that ended up in the pages, with its version, its licence and the licence text it ships. The
main ones are markdown-it and its plugins (MIT), highlight.js (BSD-3-Clause), KaTeX (MIT), Mermaid
(MIT), abcjs (MIT), DOMPurify (MPL-2.0 or Apache-2.0), React (MIT) and Excalidraw (MIT). Some of
Mermaid's dependencies are under Apache-2.0 (chevrotain), EPL-2.0 (elkjs), BSD, ISC and CC0-1.0.

The same file's last sections list the fonts, one family at a time, with the copyright lines from
each font's own files, any Reserved Font Name, and the licence texts:

| Font | Where | Licence |
| --- | --- | --- |
| KaTeX fonts | `assets/` | SIL Open Font License 1.1 |
| Assistant | `assets/`, `fonts/Assistant` | SIL Open Font License 1.1 |
| Cascadia Code | `fonts/Cascadia` | SIL Open Font License 1.1 |
| Comic Shanns | `fonts/ComicShanns` | MIT |
| Excalifont | `fonts/Excalifont` | SIL Open Font License 1.1 |
| Lilita One | `fonts/Lilita` | SIL Open Font License 1.1 |
| Nunito | `fonts/Nunito` | SIL Open Font License 1.1 |
| Virgil | `fonts/Virgil` | SIL Open Font License 1.1 |
| Xiaolai SC | `fonts/Xiaolai` | SIL Open Font License 1.1 |

The fonts under `fonts/` are copied as they are from Excalidraw's npm package, which loads them for the
whiteboard. None of them is renamed or modified. Excalidraw's package also has Liberation Sans 1.05,
which is under the GNU GPL version 2 with a font exception rather than the OFL. This copy leaves it
out. Excalidraw marks it as a font for drawing on a server, and its font picker never offers it; its
Helvetica style uses the system's Helvetica. Text that a drawing made elsewhere has already set in
Liberation Sans shows in a system font instead. `Web/build.mjs` copies only the font families that
`Web/font-notices.txt` lists, so rebuilding the page leaves it out too.

The apps use no Swift packages from others. The app icon and the notch artwork are drawn by code in
this repository (`Design/render-icon.swift`).

## In the Relay

The Relay is not bundled into the apps. It installs its packages with npm (see `Relay/package.json`
and `Relay/package-lock.json`): the MCP TypeScript SDK and zod, both MIT, and their dependencies, which
are MIT, ISC, BSD-2-Clause and BSD-3-Clause. Building it uses TypeScript (Apache-2.0) and the Node type
definitions (MIT).

## In the tests

`Tests/PerchKitTests/Fixtures/Home Renovation.kanban.md` and `Brainstorming.excalidraw.svg` come from
NotesHub's noteshub-skills (MIT). `Sources/PerchKit/Formats/KanbanBoard.swift` mirrors the board
parser in the same repository. See
[Tests/PerchKitTests/Fixtures/NOTICE.md](Tests/PerchKitTests/Fixtures/NOTICE.md).
