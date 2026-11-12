import { build } from "esbuild";
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const out = "../Apps/Shared/Web";
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

const minify = process.env.PERCH_DEBUG !== "1";
const shared = {
  bundle: true,
  minify,
  target: "safari17",
  outdir: out,
  define: {
    "process.env.NODE_ENV": '"production"',
    "process.env.IS_PREACT": '"false"',
    global: "window",
  },
  loader: { ".woff2": "file", ".woff": "file", ".ttf": "file", ".eot": "file", ".svg": "dataurl", ".png": "dataurl" },
  assetNames: "assets/[name]-[hash]",
  logLevel: "warning",
};

writeLanguageTable();

// The reader: a small core that draws text at once, and everything heavy (the highlighter's languages,
// KaTeX, Mermaid, abcjs) in chunks under chunks/ that are fetched only when a note needs them.
const reader = await build({
  ...shared,
  metafile: true,
  entryPoints: { render: "src/render.js", "render-katex": "katex/dist/katex.min.css" },
  format: "esm",
  splitting: true,
  chunkNames: "chunks/[name]-[hash]",
  // Licence notices stay inside each file, so a chunk never ships without its own.
  legalComments: "inline",
});

// The whiteboard: one file, as before.
const whiteboard = await build({
  ...shared,
  metafile: true,
  entryPoints: { whiteboard: "src/whiteboard.jsx" },
  format: "iife",
  legalComments: "linked",
});

// Excalidraw loads its own fonts from this folder at runtime. Only the families font-notices.txt lists
// ("Family (fonts/<folder>)") are copied, so no font ships without its licence. The public copy's notices
// leave out Liberation Sans (see Open/exclude.txt there), so a rebuild there leaves its folder out too.
const fontsFrom = "node_modules/@excalidraw/excalidraw/dist/prod/fonts";
const noticed = new Set([...readFileSync("font-notices.txt", "utf8").matchAll(/fonts\/([A-Za-z0-9_-]+)\)/g)].map((match) => match[1]));
const unnoticed = readdirSync(fontsFrom).filter((name) => statSync(`${fontsFrom}/${name}`).isDirectory() && !noticed.has(name));
cpSync(fontsFrom, `${out}/fonts`, { recursive: true, filter: (source) => !unnoticed.some((name) => source === `${fontsFrom}/${name}` || source.startsWith(`${fontsFrom}/${name}/`)) });
if (unnoticed.length) console.log(`fonts/: left out ${unnoticed.join(", ")}, which font-notices.txt doesn't list`);

// The reader runs no code but its own files: no eval, nothing from outside the app, and a note can't
// re-point relative addresses (base-uri) or post a form. The whiteboard's libraries need eval.
const policy = (script) => `default-src 'self' perch-app: perch-vault: data: blob:; script-src ${script}; style-src 'unsafe-inline' perch-app:; img-src perch-app: perch-vault: https: data: blob:; media-src perch-vault: blob: data:; frame-src https://www.youtube-nocookie.com; connect-src perch-app: perch-vault: data: blob:; font-src perch-app: data:; object-src 'none'; base-uri 'none'; form-action 'none'`;
const page = (name, title, module, csp) => `<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta http-equiv="Content-Security-Policy" content="${csp}">
<title>${title}</title>
<link rel="stylesheet" href="${name}.css">
</head><body><div id="root"></div><script${module ? ' type="module"' : ""} src="${name}.js"></script></body></html>`;
writeFileSync(`${out}/render.html`, page("render", "Note", true, policy("perch-app:")));
writeFileSync(`${out}/whiteboard.html`, page("whiteboard", "Whiteboard", false, policy("perch-app: 'unsafe-eval'")));

writeNotices([reader.metafile, whiteboard.metafile]);

const size = (path) => statSync(path).size;
const chunks = readdirSync(`${out}/chunks`).filter((name) => name.endsWith(".js"));
const kb = (bytes) => (bytes / 1e3).toFixed(0) + " kB";
console.log("render.js (loaded by every note)", kb(size(`${out}/render.js`)));
console.log("render.css", kb(size(`${out}/render.css`)), "· render-katex.css (on demand)", kb(size(`${out}/render-katex.css`)));
console.log(`chunks (on demand): ${chunks.length} files,`, kb(chunks.reduce((sum, name) => sum + size(`${out}/chunks/${name}`), 0)));
for (const file of ["whiteboard.js", "whiteboard.css"]) console.log(file, (size(`${out}/${file}`) / 1e6).toFixed(1) + " MB");

/**
 * Writes THIRD-PARTY-NOTICES.txt beside the pages: every package whose code or fonts ended up in them,
 * with its version, licence and the licence text it ships. The list comes from what was actually bundled,
 * so it can't fall behind package.json. Both apps carry the file inside their Web folder.
 */
function writeNotices(metafiles) {
  const folders = new Set();
  for (const meta of metafiles) {
    for (const input of Object.keys(meta.inputs)) {
      const match = /^(?:.*\/)?(node_modules\/(?:.*\/node_modules\/)?(?:@[^/]+\/)?[^/]+)\//.exec(input.replace(/^[a-z-]+:/, ""));
      if (match) folders.add(match[1]);
    }
  }
  // Copied whole rather than bundled.
  folders.add("node_modules/@excalidraw/excalidraw");
  // Packages that publish without a licence file. Their licence is the one their repository states.
  const mit = (holder) => `MIT License\n\nCopyright (c) ${holder}\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\nof this software and associated documentation files (the "Software"), to deal\nin the Software without restriction, including without limitation the rights\nto use, copy, modify, merge, publish, distribute, sublicense, and/or sell\ncopies of the Software, and to permit persons to whom the Software is\nfurnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all\ncopies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\nIMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\nFITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\nAUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\nLIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\nOUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\nSOFTWARE.`;
  const unfiled = { "@excalidraw/excalidraw": mit("2020 Excalidraw") };
  const packages = new Map();
  for (const folder of folders) {
    if (!existsSync(`${folder}/package.json`)) continue;
    const info = JSON.parse(readFileSync(`${folder}/package.json`, "utf8"));
    if (!info.name || !info.version) continue;
    const file = readdirSync(folder).filter((name) => /^(licen[sc]e|copying|notice)(\.|-|$)/i.test(name)).sort()[0];
    const licence = typeof info.license === "string" ? info.license : info.license?.type ?? (info.licenses ?? []).map((each) => each.type).join(" OR ") ?? "";
    packages.set(`${info.name}@${info.version}`, {
      name: info.name, version: info.version, licence: licence || "see text",
      home: typeof info.repository === "string" ? info.repository : info.repository?.url ?? info.homepage ?? "",
      text: file ? readFileSync(`${folder}/${file}`, "utf8").replace(/\r\n/g, "\n").trim() : unfiled[info.name] ?? "",
    });
  }
  const list = [...packages.values()].sort((a, b) => (a.name + "@" + a.version < b.name + "@" + b.version ? -1 : 1));
  // Many packages ship the same licence word for word; each distinct text is printed once.
  const texts = new Map();
  for (const each of list) {
    const key = each.text || `(no licence file in the package; licensed as ${each.licence})`;
    if (!texts.has(key)) texts.set(key, []);
    texts.get(key).push(`${each.name} ${each.version}`);
  }
  const lines = [
    "Third-party software in Perch's pages",
    "",
    "The note reader (render.js and chunks/) and the whiteboard (whiteboard.js, fonts/) are built from the",
    "open-source packages below. The fonts under assets/ and fonts/ are listed one family at a time, with",
    "their licences, in the last sections. Written by Web/build.mjs; do not edit.",
    "",
    ...list.map((each) => `${each.name} ${each.version} — ${each.licence}${each.home ? ` — ${each.home.replace(/^git\+/, "").replace(/\.git$/, "")}` : ""}`),
    "",
  ];
  for (const [text, names] of texts) {
    lines.push("=".repeat(78), names.join(", "), "=".repeat(78), "", text, "");
  }
  // The fonts' own licences, by family. Font files don't come with package metadata, so this part is
  // written by hand in font-notices.txt from what each font file says.
  lines.push(readFileSync("font-notices.txt", "utf8").trimEnd(), "");
  writeFileSync(`${out}/THIRD-PARTY-NOTICES.txt`, lines.join("\n"));
  const required = ["highlight.js", "katex", "mermaid", "abcjs", "markdown-it", "dompurify", "@excalidraw/excalidraw", "react"];
  const missing = required.filter((name) => !list.some((each) => each.name === name && each.text));
  if (missing.length) throw new Error(`No licence text found for: ${missing.join(", ")}`);
  const bare = list.filter((each) => !each.text).map((each) => `${each.name} (${each.licence})`);
  console.log(`THIRD-PARTY-NOTICES.txt: ${list.length} packages, ${texts.size} licence texts` + (bare.length ? `; named without a text of their own: ${bare.join(", ")}` : ""));
}

/**
 * Writes src/render/languages.generated.js: every highlight.js language as its own lazy import, the names
 * and aliases that lead to each, and which other languages a language embeds (HTML embeds CSS and JavaScript).
 */
function writeLanguageTable() {
  const core = require("highlight.js/lib/core");
  const directory = "node_modules/highlight.js/lib/languages";
  const modules = readdirSync(directory).filter((name) => name.endsWith(".js") && !name.endsWith(".js.js")).map((name) => name.slice(0, -3)).sort();
  const aliases = {}, embeds = {};
  for (const name of modules) {
    const definition = require(`highlight.js/lib/languages/${name}`)(core);
    aliases[name] = name;
    for (const alias of definition.aliases ?? []) aliases[alias.toLowerCase()] ??= name;
    const found = new Set(), seen = new Set();
    const walk = (value) => {
      if (!value || typeof value !== "object" || seen.has(value) || value instanceof RegExp) return;
      seen.add(value);
      if (typeof value.subLanguage === "string") found.add(value.subLanguage);
      if (Array.isArray(value.subLanguage)) value.subLanguage.forEach((language) => found.add(language));
      for (const child of Array.isArray(value) ? value : Object.values(value)) walk(child);
    };
    walk(definition);
    found.delete(name);
    if (found.size) embeds[name] = [...found].sort();
  }
  // Tags people write that highlight.js doesn't know under that name.
  const extra = {
    jsonc: "json", json5: "json", html5: "xml", htm: "xml", vue: "xml", svelte: "xml", shellscript: "bash", fish: "bash",
    "objective-c": "objectivec", "obj-c": "objectivec", dotenv: "ini", env: "ini", conf: "ini", cfg: "ini",
    "c#": "csharp", "f#": "fsharp", el: "lisp", elisp: "lisp", emacs: "lisp", make: "makefile", mk: "makefile",
    yaml: "yaml", docker: "dockerfile", tf: "ini", hcl: "ini", proto: "protobuf", ps1: "powershell", bat: "dos", cmd: "dos",
    txt: "plaintext", text: "plaintext", plain: "plaintext", none: "plaintext", output: "plaintext", log: "plaintext",
  };
  for (const [alias, name] of Object.entries(extra)) if (modules.includes(name)) aliases[alias] ??= name;
  for (const [name, list] of Object.entries(embeds)) embeds[name] = list.map((language) => aliases[language]).filter((language) => language && language !== name);
  const lines = [
    "// Written by build.mjs from the installed highlight.js. Do not edit.",
    `export const aliases = ${JSON.stringify(Object.fromEntries(Object.entries(aliases).sort(([a], [b]) => (a < b ? -1 : 1))))};`,
    `export const embeds = ${JSON.stringify(embeds)};`,
    "export const loaders = {",
    ...modules.map((name) => `  ${JSON.stringify(name)}: () => import("highlight.js/lib/languages/${name}"),`),
    "};",
    "",
  ];
  writeFileSync("src/render/languages.generated.js", lines.join("\n"));
}
