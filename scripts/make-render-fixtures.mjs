#!/usr/bin/env node
// Writes the generated notes in Tests/Fixtures/Rendering: the stress notes and the ones the timing run uses.
// Deterministic: running it again gives the same files. The hand-written fixtures beside them are not touched.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const out = join(dirname(fileURLToPath(import.meta.url)), "../Tests/Fixtures/Rendering");
const words = "the coast road runs past harbor lighthouse quarry and ridge camp before it turns inland toward the old ferry landing where timetable changes arrive each october".split(" ");
let seed = 7;
const next = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff);
const sentence = (count) => {
  const picked = Array.from({ length: count }, () => words[next() % words.length]);
  picked[0] = picked[0][0].toUpperCase() + picked[0].slice(1);
  return picked.join(" ") + ".";
};
const paragraph = () => Array.from({ length: 2 + (next() % 3) }, () => sentence(8 + (next() % 10))).join(" ");

const code = {
  swift: (n) => `struct Stop${n}: Codable {\n    let name: String\n    var minutes = ${n}\n    func label() -> String { "\\(name): \\(minutes) min" } // ${n}\n}`,
  python: (n) => `def total_${n}(stops):\n    """Sum of minutes."""\n    return sum(s.minutes for s in stops) + ${n}  # ${n}`,
  js: (n) => `export function total${n}(list) {\n  return list.reduce((sum, stop) => sum + stop.minutes, ${n}); // ${n}\n}`,
  ts: (n) => `export const total${n} = (list: Stop[]): number =>\n  list.reduce((sum, stop) => sum + (stop.minutes ?? ${n}), 0);`,
  json: (n) => `{\n  "name": "Stop ${n}",\n  "minutes": ${n},\n  "open": true\n}`,
  yaml: (n) => `stop:\n  name: Stop ${n}\n  minutes: ${n}\n  open: true # ${n}`,
  bash: (n) => `for f in *.md; do\n  echo "note ${n}: $f" >> "$HOME/log.txt"\ndone`,
  sql: (n) => `SELECT name, SUM(minutes) AS total\nFROM stops WHERE id > ${n} -- ${n}\nGROUP BY name;`,
  go: (n) => `func total${n}(stops []Stop) int {\n\tsum := ${n}\n\tfor _, s := range stops {\n\t\tsum += s.Minutes\n\t}\n\treturn sum\n}`,
  rust: (n) => `fn total_${n}(stops: &[Stop]) -> u32 {\n    stops.iter().map(|s| s.minutes).sum::<u32>() + ${n}\n}`,
  "": (n) => `plain block ${n}\n  no language tag`,
};
const languages = Object.keys(code);
const fence = (n) => {
  const language = languages[n % languages.length];
  return "```" + language + "\n" + code[language](n) + "\n```";
};
const table = (n) => `| Stop | Minutes | Open |\n| --- | ---: | :---: |\n| Harbor ${n} | ${n} | yes |\n| Quarry ${n} | ${n * 2} | no |\n| \`code ${n}\` | ${n * 3} | **yes** |`;
const tasks = (n) => `- [ ] Pack the tent ${n}\n- [x] Check the timetable ${n}\n  - [ ] Evening sailing\n- Plain item with [[Wiki Target]] and \`code\``;
const callout = (n) => `> [!${["note", "tip", "warning", "danger"][n % 4]}] Section ${n}\n> ${sentence(12)}`;
const mermaid = (n) => "```mermaid\nflowchart LR\n  A" + n + "[Start " + n + "] --> B" + n + "{Choice}\n  B" + n + " -->|yes| C" + n + "[Do it]\n  B" + n + " -->|no| D" + n + "[Skip]\n```";
const mermaidKinds = (n) => [
  mermaid(n),
  "```mermaid\nsequenceDiagram\n  participant A as App " + n + "\n  participant W as Web view\n  A->>W: render\n  W-->>A: rendered\n```",
  "```mermaid\npie title Time " + n + "\n  \"Parse\" : 10\n  \"Draw\" : 30\n```",
  "```mermaid\nstateDiagram-v2\n  [*] --> Idle" + n + "\n  Idle" + n + " --> Busy: render\n  Busy --> Idle" + n + ": done\n```",
  "```mermaid\nclassDiagram\n  class Note" + n + " { +String path +render() }\n  Note" + n + " <|-- Board" + n + "\n```",
][n % 5];
const math = (n) => `Inline $a_${n}^2 + b^2 = c^2$ and a display:\n\n$$\n\\sum_{i=1}^{${n}} i = \\frac{${n}(${n}+1)}{2}\n$$`;

function write(name, text) {
  writeFileSync(join(out, name), text.endsWith("\n") ? text : text + "\n");
  console.log(name, text.split("\n").length, "lines");
}

// A short note: what most notes are.
write("bench-small.md", ["# Weekend plan", paragraph(), "- Pack the tent\n- Both lamps\n- [ ] Check the ferry", paragraph()].join("\n\n"));

// A typical technical note: about ten code blocks, a table, tasks, a callout and some maths.
{
  const parts = ["---\ntitle: Typical\ntags: [bench, code]\n---", "# A typical note"];
  for (let i = 1; i <= 10; i++) {
    parts.push(`## Section ${i}`, paragraph(), fence(i), paragraph());
    if (i === 3) parts.push(table(i));
    if (i === 5) parts.push(tasks(i), callout(i));
    if (i === 7) parts.push(math(i));
  }
  write("bench-typical.md", parts.join("\n\n"));
}

// Five Mermaid diagrams of different kinds between ordinary text.
{
  const parts = ["# Five diagrams"];
  for (let i = 1; i <= 5; i++) parts.push(`## Diagram ${i}`, paragraph(), mermaidKinds(i), paragraph());
  write("bench-5-mermaid.md", parts.join("\n\n"));
}

// 200 code blocks.
{
  const parts = ["# Two hundred code blocks"];
  for (let i = 1; i <= 200; i++) parts.push(`Block ${i}: ${sentence(9)}`, fence(i));
  write("stress-200-code-blocks.md", parts.join("\n\n"));
}

// At least 5,000 lines mixing everything.
{
  const parts = ["---\ntitle: Stress\ntags: [stress, long]\n---", "# Five thousand lines"];
  let lines = 0, section = 0;
  const push = (...blocks) => { for (const block of blocks) { parts.push(block); lines += block.split("\n").length + 1; } };
  while (lines < 5000) {
    section++;
    push(`## Section ${section} with \`code\` and *emphasis*`, paragraph(), fence(section), paragraph());
    push(tasks(section), table(section), callout(section));
    push(`### Notes ${section}`, paragraph() + ` See [[Wiki Target]] and [a link](https://example.com/${section}), ==marked==, H~2~O, x^2^ :tada:[^n${section}]`);
    push(`[^n${section}]: Footnote ${section}.`);
    if (section % 4 === 0) push(math(section));
    if (section % 25 === 0) push(mermaidKinds(section / 25));
    if (section % 40 === 0) push("```abc\nX:" + section + "\nT:Tune " + section + "\nM:4/4\nL:1/4\nK:C\nC D E F | G A B c |]\n```");
    if (section % 10 === 0) push(`1. First\n2. Second\n   - nested bullet\n     1. deep\n3. Third`, `> A quote.\n> > Nested quote ${section}.`, "---");
    if (section % 15 === 0) push(`![picture ${section}](pixel.png "Caption ${section}")`, `<details>\n<summary>More ${section}</summary>\n\nHidden **Markdown** ${section}.\n\n</details>`);
    if (section % 6 === 0) push(`<span style="color: #3B82D9">Blue ${section}</span> and <mark style="background-color: #3F9B5B">green ${section}</mark>, <u>underlined</u>.`);
  }
  write("stress-5000-lines.md", parts.join("\n\n"));
}
