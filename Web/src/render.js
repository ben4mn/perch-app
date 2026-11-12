// The reader page. Swift calls window.Perch; the page answers with messages (ready, rendered, settled,
// height, scroll, copy, toggleTask, openWiki, …). Display only: nothing here can change a note's text.
const scriptStart = performance.now();

import "abcjs/abcjs-audio.css";
import "./render/render.css";
import { parseSegments, renderFragment } from "./render/markdown.js";
import { sanitizeToFragment } from "./render/sanitize.js";
import * as color from "./render/color.js";
import * as enhance from "./render/enhance.js";

const post = (message) => {
  window.webkit?.messageHandlers?.perch?.postMessage(message);
  window.__perchMessages?.push(message);
};

const root = document.getElementById("root");
// Marks the placeholders this page makes for sync conflicts, so a note can't write its own.
const nonce = Math.random().toString(36).slice(2, 10);

/** Turns NotesHub conflict blocks into marked placeholders before Markdown runs. */
function extractConflicts(source) {
  const blocks = [];
  if (!source.includes(":::conflict{")) return { replaced: source, blocks };
  const replaced = source.replace(/^:::conflict\{variant=(\w+)\}\r?\n([\s\S]*?)\r?\n?^:::[ \t]*$/gm, (match, variant, body) => {
    blocks.push({ variant, body });
    // Keeps the same number of lines, so everything below still knows which source line it came from.
    return `<div data-conflict="${nonce}-${blocks.length - 1}"></div>` + "\n".repeat(match.split("\n").length - 1);
  });
  return { replaced, blocks };
}

function stripFrontmatter(source) {
  const match = /^---\r?\n([\s\S]*?)\r?\n?---[ \t]*(?:\r?\n|$)/.exec(source);
  if (!match) return { body: source, lines: 0, yaml: null };
  return { body: source.slice(match[0].length), lines: match[0].split("\n").length - 1, yaml: match[1] };
}

const unquote = (value) => value.replace(/^(["'])(.*)\1$/, "$2");

/** Reads the simple YAML notes use: `key: value`, inline lists and dash lists. Returns null for anything richer. */
function parseProperties(yaml) {
  const entries = [];
  let current = null;
  for (const raw of yaml.split(/\r?\n/)) {
    if (!raw.trim() || /^\s*#/.test(raw)) continue;
    // A list under a key, with its dashes indented or (as many tools write them) at the left margin.
    const item = /^\s+-\s*(.*)$/.exec(raw) ?? (current && !current.inline && (!current.values.length || current.dashes) ? /^-\s+(.*)$/.exec(raw) : null);
    if (item && current) { current.values.push(unquote(item[1].trim())); current.dashes = true; continue; }
    const pair = /^([^\s:#][^:]*):(?:\s+(.*)|\s*)$/.exec(raw);
    if (!pair) return null;
    const value = (pair[2] ?? "").trim();
    // A block of text (`|`, `>`) is more than a list of chips can show.
    if (/^[|>][+-]?$/.test(value)) return null;
    current = { key: pair[1].trim(), values: [], inline: value !== "" };
    const list = /^\[(.*)\]$/.exec(value);
    if (list) current.values = list[1].split(",").map((part) => unquote(part.trim())).filter(Boolean), current.list = true;
    else if (value) current.values = [unquote(value)];
    else current.list = true;
    entries.push(current);
  }
  return entries;
}

// The reader's own choice for this page, until the setting changes.
let propertiesOpen;
/** Open or closed, from the Properties reading setting: "expanded", "collapsed", or by size when unset. */
function propertiesShouldOpen(box) {
  if (propertiesOpen !== undefined) return propertiesOpen;
  const mode = document.documentElement.dataset.properties;
  if (mode === "expanded") return true;
  if (mode === "collapsed") return false;
  // Frontmatter too rich to list stays closed, as it always has.
  return box.dataset.entries !== undefined && Number(box.dataset.entries) <= 4;
}

/** Frontmatter as a tidy block of properties. Display only: the note's text is untouched. */
function buildProperties(yaml) {
  const entries = parseProperties(yaml);
  const box = document.createElement("details");
  box.className = "properties";
  const summary = document.createElement("summary");
  summary.append("Properties");
  box.append(summary);
  if (!entries) {
    const pre = document.createElement("pre");
    pre.textContent = yaml;
    box.append(pre);
  } else {
    const count = document.createElement("span");
    count.className = "count";
    count.textContent = String(entries.length);
    summary.append(count);
    const list = document.createElement("dl");
    for (const entry of entries) {
      const term = document.createElement("dt");
      term.textContent = entry.key;
      const detail = document.createElement("dd");
      if (!entry.values.length) {
        detail.className = "empty";
        detail.textContent = "–";
      } else if (entry.list || entry.values.length > 1) {
        for (const value of entry.values) {
          const chip = document.createElement("span");
          chip.className = "chip";
          chip.textContent = value;
          detail.append(chip);
        }
      } else {
        detail.textContent = entry.values[0];
      }
      list.append(term, detail);
    }
    box.append(list);
    box.dataset.entries = String(entries.length);
  }
  box.open = propertiesShouldOpen(box);
  // Only a click counts as the reader's own choice; opening it from a setting doesn't.
  summary.addEventListener("click", () => { setTimeout(() => { propertiesOpen = box.open; }, 0); });
  return box;
}

// Code blocks this page built. A note can write markup that looks like one; only these answer to Copy.
const ownBlocks = new WeakSet();

/** Wraps tables so they scroll sideways, gives code blocks a label and a copy button, and frames diagrams. */
function decorateBlocks(scope) {
  for (const table of scope.querySelectorAll("table")) {
    if (table.parentElement?.classList.contains("table-wrap")) continue;
    const wrap = document.createElement("div");
    wrap.className = "table-wrap";
    table.replaceWith(wrap);
    wrap.append(table);
  }
  for (const pre of scope.querySelectorAll("pre")) {
    if (pre.parentElement?.classList.contains("code-block")) continue;
    const line = pre.dataset.line;
    if (pre.classList.contains("diagram-source")) {
      const kind = pre.dataset.kind === "abc" ? "abc" : "mermaid";
      const frame = document.createElement("div");
      frame.className = "diagram";
      frame.dataset.kind = kind;
      frame.dataset.state = "pending";
      if (line !== undefined) frame.dataset.line = line;
      frame.__source = pre.textContent;
      pre.replaceWith(frame);
      continue;
    }
    const tag = pre.dataset.lang ?? "";
    const wrap = document.createElement("div");
    wrap.className = tag ? "code-block" : "code-block plain";
    if (tag) wrap.dataset.lang = tag;
    if (line !== undefined) wrap.dataset.line = line;
    const head = document.createElement("div");
    head.className = "code-head";
    const label = document.createElement("span");
    label.className = "code-lang";
    // The tag as the note wrote it, whether or not there is a highlighter for it.
    label.textContent = tag;
    const copy = document.createElement("button");
    copy.type = "button";
    copy.className = "code-copy";
    copy.textContent = "Copy";
    head.append(label, copy);
    pre.replaceWith(wrap);
    pre.removeAttribute("data-line");
    pre.removeAttribute("data-lang");
    wrap.append(head, pre);
    ownBlocks.add(wrap);
  }
  for (const item of scope.querySelectorAll("li.task-list-item")) {
    const box = item.querySelector(":scope > input[type=checkbox], :scope > p > input[type=checkbox]");
    item.classList.toggle("checked", !!box?.checked);
  }
  for (const box of scope.querySelectorAll("input[type=checkbox]")) box.disabled = !!box.dataset.inert;
}

const vaultURL = (path) =>
  "perch-vault://vault/" + path.split("/").map(encodeURIComponent).join("/");

function resolveRelative(basePath, target) {
  let decoded = target;
  try { decoded = decodeURI(target); } catch {}
  const parts = basePath.split("/").slice(0, -1);
  if (decoded.startsWith("/")) parts.length = 0;
  for (const part of decoded.split("/")) {
    if (part === "" || part === ".") continue;
    if (part === "..") parts.pop();
    else parts.push(part);
  }
  return parts.join("/");
}

const isExternal = (value) => /^[a-z][a-z0-9+.-]*:/i.test(value);
const AUDIO = /\.(m4a|mp3|flac|opus|ogg|wav|aac)$/i;
const VIDEO = /\.(mp4|m4v|mov|webm)$/i;

function youtubeID(url) {
  const match = /^https?:\/\/(?:www\.|m\.)?(?:youtube\.com\/watch\?(?:.*&)?v=|youtu\.be\/|youtube\.com\/shorts\/)([\w-]{6,})/.exec(url);
  return match ? match[1] : null;
}

/** A picture that can't be loaded becomes a quiet note of what was meant to be there. */
function imageFailed(event) {
  const image = event.target;
  if (!image.isConnected) return;
  const note = document.createElement("span");
  note.className = "image-missing";
  note.textContent = image.alt ? `Missing image: ${image.alt}` : "Missing image";
  note.title = image.dataset.source ?? "";
  const gone = image.parentElement?.tagName === "FIGURE" ? image.parentElement : image;
  gone.replaceWith(note);
  // A picture that is a block of its own (raw HTML, or a figure with a caption) is one of the nodes the
  // page keeps for its block. The note takes its place there too, or the next edit, which keeps the block,
  // puts the broken picture back, and no second error comes to swap it out.
  for (const piece of pieces) {
    const at = piece.nodes.indexOf(gone);
    if (at !== -1) { piece.nodes[at] = note; break; }
  }
}

function fixMedia(scope, basePath) {
  for (const image of scope.querySelectorAll("img[src]")) {
    const source = image.getAttribute("src");
    image.dataset.source = source;
    if (!isExternal(source)) image.setAttribute("src", vaultURL(resolveRelative(basePath, source)));
    image.loading = "lazy";
    image.addEventListener("error", imageFailed, { once: true });
    const title = image.getAttribute("title");
    // A caption needs the picture to stand alone; one in the middle of a sentence keeps its place in the line.
    const parent = image.parentElement;
    const alone = parent?.tagName === "P" && [...parent.childNodes].every((node) => node === image || (node.nodeType === Node.TEXT_NODE && !node.textContent.trim()));
    if (title && alone) {
      const figure = document.createElement("figure");
      const caption = document.createElement("figcaption");
      caption.textContent = title;
      parent.replaceWith(figure);
      figure.append(image, caption);
      if (parent.dataset.line !== undefined) figure.dataset.line = parent.dataset.line;
    }
  }
  for (const link of scope.querySelectorAll("a[href]")) {
    const href = link.getAttribute("href");
    if (link.classList.contains("wikilink") || href.startsWith("#")) continue;
    if (!isExternal(href)) {
      const path = resolveRelative(basePath, href.split("#")[0]);
      if (AUDIO.test(path) || VIDEO.test(path)) {
        const media = document.createElement(AUDIO.test(path) ? "audio" : "video");
        media.controls = true;
        media.preload = "metadata";
        media.src = vaultURL(path);
        link.replaceWith(media);
      } else {
        link.dataset.note = path;
        link.setAttribute("href", "#");
      }
      continue;
    }
    // A link alone in its paragraph becomes an embed or a preview card.
    const parent = link.parentElement;
    const alone = parent?.tagName === "P" && parent.childNodes.length === 1 && link.textContent === href;
    if (!alone) continue;
    const id = youtubeID(href);
    if (id) {
      const wrap = document.createElement("div");
      wrap.className = "embed";
      const frame = document.createElement("iframe");
      frame.src = `https://www.youtube-nocookie.com/embed/${id}`;
      frame.loading = "lazy";
      frame.setAttribute("allowfullscreen", "");
      frame.setAttribute("sandbox", "allow-scripts allow-same-origin allow-presentation");
      wrap.append(frame);
      parent.replaceWith(wrap);
    } else {
      link.classList.add("link-card");
      let host = "";
      try { host = new URL(href).hostname.replace(/^www\./, ""); } catch {}
      link.dataset.host = host;
    }
  }
}

function fixCallouts(scope) {
  for (const quote of scope.querySelectorAll("blockquote")) {
    const first = quote.firstElementChild;
    if (first?.tagName !== "P") continue;
    // The marker is the first text of the quote, even when the whole title was coloured or underlined
    // and so sits inside a span of its own.
    let node = first.firstChild;
    while (node?.nodeType === Node.ELEMENT_NODE && /^(SPAN|MARK|U|STRONG|EM|B|I)$/.test(node.tagName)) node = node.firstChild;
    if (node?.nodeType !== Node.TEXT_NODE) continue;
    const match = /^\[!([\w-]+)\]([+-])?[ \t]*([^\n]*)/.exec(node.textContent);
    if (!match) continue;
    const [whole, type, fold] = match;
    const callout = document.createElement(fold ? "details" : "div");
    callout.className = `callout callout-${type.toLowerCase()}`;
    if (quote.dataset.line !== undefined) callout.dataset.line = quote.dataset.line;
    if (fold === "+") callout.open = true;
    const heading = document.createElement(fold ? "summary" : "div");
    heading.className = "callout-title";
    // The title is the rest of the first line, with whatever formatting it has.
    node.textContent = node.textContent.slice(whole.length - match[3].length);
    const text = document.createElement("span");
    while (first.firstChild && first.firstChild.nodeName !== "BR") text.append(first.firstChild);
    if (first.firstChild?.nodeName === "BR") first.firstChild.remove();
    if (first.firstChild?.nodeType === Node.TEXT_NODE) first.firstChild.textContent = first.firstChild.textContent.replace(/^\n/, "");
    // No title written: the kind of callout is its title. (Formatting wrapped round the marker alone leaves nothing to show.)
    if (!text.textContent.trim() && !text.querySelector("img, .math")) text.textContent = type[0].toUpperCase() + type.slice(1).toLowerCase();
    heading.append(text);
    const body = document.createElement("div");
    body.className = "callout-body";
    body.append(...quote.childNodes);
    if (!first.textContent.trim() && !first.children.length) first.remove();
    callout.append(heading, body);
    quote.replaceWith(callout);
  }
}

let mentionPattern = null, mentionsByKey = new Map(), mentionsKey = "[]";
function setMentions(mentions) {
  const key = JSON.stringify(mentions ?? []);
  if (key === mentionsKey) return false;
  mentionsKey = key;
  if (!mentions?.length) { mentionPattern = null; return true; }
  const sorted = [...mentions].sort((a, b) => b.key.length - a.key.length);
  const escapeRegex = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  mentionPattern = new RegExp(`(?<![\\p{L}\\p{N}_-])(${sorted.map((m) => escapeRegex(m.key)).join("|")})(?![\\p{L}\\p{N}_-])`, "giu");
  mentionsByKey = new Map(sorted.map((m) => [m.key.toLowerCase(), m]));
  return true;
}

function removeMentions(scope) {
  for (const anchor of scope.querySelectorAll("a.mention")) {
    const parent = anchor.parentNode;
    anchor.replaceWith(anchor.textContent);
    parent?.normalize();
  }
}

function applyMentions(scope) {
  if (!mentionPattern) return;
  const pattern = mentionPattern;
  const walker = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      return node.parentElement?.closest("a,code,pre,h1,h2,h3,.math,.diagram,svg,summary,.callout-title")
        ? NodeFilter.FILTER_REJECT
        : NodeFilter.FILTER_ACCEPT;
    },
  });
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const node of nodes) {
    const text = node.textContent;
    pattern.lastIndex = 0;
    if (!pattern.test(text)) continue;
    pattern.lastIndex = 0;
    const fragment = document.createDocumentFragment();
    let last = 0;
    for (const match of text.matchAll(pattern)) {
      fragment.append(text.slice(last, match.index));
      const mention = mentionsByKey.get(match[0].toLowerCase());
      const anchor = document.createElement("a");
      anchor.className = "mention";
      anchor.href = "#";
      anchor.dataset.mentionPath = mention.path;
      anchor.dataset.mentionText = match[0];
      anchor.title = `Open ${mention.title}. Option-click saves this as a [[link]].`;
      anchor.textContent = match[0];
      fragment.append(anchor);
      last = match.index + match[0].length;
    }
    fragment.append(text.slice(last));
    node.replaceWith(fragment);
  }
}

// MARK: Theme

// Light or dark: what Swift last said, or the system's setting until it does.
const systemDark = matchMedia("(prefers-color-scheme: dark)");
let explicitScheme = null;
const isDark = () => (explicitScheme ?? (systemDark.matches ? "dark" : "light")) === "dark";
const applyScheme = () => { document.documentElement.dataset.scheme = isDark() ? "dark" : "light"; };
systemDark.addEventListener("change", () => { applyScheme(); themeChanged(); });
applyScheme();

const themeHex = (style, name) => {
  const value = style.getPropertyValue(name).trim();
  return /^#[0-9a-f]{6}$/i.test(value) ? value : null;
};

/** Mermaid's settings in the theme's colors, when the theme gave plain hex colors; its stock look otherwise. */
function mermaidTheme() {
  const style = getComputedStyle(document.documentElement);
  const text = themeHex(style, "--perch-text"), surface = themeHex(style, "--perch-surface"), frame = themeHex(style, "--perch-code-bg");
  const line = themeHex(style, "--perch-text-secondary") ?? themeHex(style, "--perch-muted"), border = themeHex(style, "--perch-border");
  if (!text || !surface || !frame || !line || !border) return { theme: isDark() ? "dark" : "default" };
  // Charts with several series (a pie's slices) take the theme's own signal colours, softened toward
  // the frame so the theme's text still reads on them.
  const tones = ["--perch-info", "--perch-success", "--perch-warning", "--perch-danger", "--perch-accent", "--perch-muted"]
    .map((name) => themeHex(style, name)).filter(Boolean).map((tone) => color.mix(tone, frame, 0.45));
  const series = {};
  tones.forEach((tone, index) => { series[`pie${index + 1}`] = tone; series[`cScale${index}`] = tone; });
  return {
    theme: "base",
    themeVariables: {
      ...series,
      pieStrokeColor: border, pieOuterStrokeColor: border, pieStrokeWidth: "1px", pieOuterStrokeWidth: "1px",
      pieSectionTextColor: text, pieLegendTextColor: text, pieTitleTextColor: text,
      darkMode: isDark(),
      background: frame,
      primaryColor: surface, primaryTextColor: text, primaryBorderColor: line,
      secondaryColor: frame, secondaryTextColor: text, secondaryBorderColor: border,
      tertiaryColor: frame, tertiaryTextColor: text, tertiaryBorderColor: border,
      mainBkg: surface, nodeBorder: line, lineColor: line, textColor: text, titleColor: text,
      clusterBkg: frame, clusterBorder: border, edgeLabelBackground: frame,
      noteBkgColor: surface, noteTextColor: text, noteBorderColor: border,
    },
  };
}
enhance.setMermaidTheme(mermaidTheme);

/** What author-chosen colours have to be readable against: the theme's page, card and code backgrounds. */
function colorContext() {
  const style = getComputedStyle(document.documentElement);
  const grounds = ["--perch-bg", "--perch-surface", "--perch-code-bg"].map((name) => themeHex(style, name)).filter(Boolean);
  return {
    backgrounds: grounds.length ? grounds : [isDark() ? "#1c1d22" : "#ffffff"],
    text: themeHex(style, "--perch-text") ?? (isDark() ? "#e4e6ec" : "#1c1e24"),
    dark: isDark(),
  };
}

const insideDrawing = (element) => {
  for (let node = element.parentElement; node && node !== root; node = node.parentElement) if (enhance.isDrawn(node)) return true;
  return false;
};

/**
 * Draws author-chosen colours so they read on this theme. The note's own colour is kept in
 * data-ink / data-tint; what is drawn is worked out from it, and worked out again when the theme changes.
 */
function applyColors(scope, context = colorContext()) {
  const elements = scope.querySelectorAll ? [...scope.querySelectorAll("[style], [data-ink], [data-tint]")] : [];
  const page = context.backgrounds[0];
  const washed = [];
  for (const element of elements) {
    // Typeset formulas and drawn music carry styles of their own. Only what this page drew is left
    // alone: a note can't opt out by writing class="math" on its own markup.
    if (insideDrawing(element)) continue;
    const ink = element.dataset.ink ?? element.style.color;
    if (ink && color.parseColor(ink)) {
      element.dataset.ink = ink;
      // The editor's rule, against the page's own background, so both show the same colour.
      element.style.color = color.legible(ink, page);
    }
    const tint = element.dataset.tint ?? element.style.backgroundColor;
    if (tint && color.parseColor(tint)) {
      element.dataset.tint = tint;
      // As the editor draws it: the colour washed over the page, at one strength for light themes and one for dark.
      element.style.backgroundColor = color.washCss(tint, context.dark);
      element.classList.add("tinted");
      washed.push(element);
    }
  }
  // Text on a highlight is read against the highlight, not the page: the theme's text, and any picked
  // colour inside it, moves lighter or darker until it can be.
  for (const element of washed) {
    const behind = color.wash(element.dataset.tint, page, context.dark);
    if (!element.dataset.ink) element.style.color = color.textOnWash(null, context.text, page, behind);
    for (const inked of [element, ...element.querySelectorAll("[data-ink]")]) {
      // Each piece of coloured text answers to the highlight nearest around it.
      if (!inked.dataset.ink || inked.closest("[data-tint]") !== element || insideDrawing(inked)) continue;
      inked.style.color = color.textOnWash(inked.dataset.ink, context.text, page, behind);
    }
  }
}

let themeKey = "";
/** After the theme's colours change: nothing is rendered again, only recoloured. */
function themeChanged() {
  const context = colorContext();
  const style = getComputedStyle(document.documentElement);
  const code = {
    codeBackground: themeHex(style, "--perch-code-bg"), dark: isDark(), muted: themeHex(style, "--perch-muted"),
    success: themeHex(style, "--perch-success"), danger: themeHex(style, "--perch-danger"),
  };
  const key = JSON.stringify([context, code]);
  if (key === themeKey) return;
  themeKey = key;
  // Syntax colours are tuned to this theme's code background, whatever theme it is.
  const tokens = color.codeTokenColors(code);
  for (const name of ["keyword", "string", "number", "title", "type", "comment", "added", "removed"]) {
    const variable = `--perch-code-${name}`;
    if (tokens[variable]) document.documentElement.style.setProperty(variable, tokens[variable]);
    else document.documentElement.style.removeProperty(variable);
  }
  applyColors(root, context);
  enhance.redrawDiagramsForTheme(root);
}

function renderConflicts(scope, blocks) {
  for (const placeholder of scope.querySelectorAll("[data-conflict]")) {
    const [mark, number] = (placeholder.dataset.conflict ?? "").split("-");
    const index = Number(number);
    const block = mark === nonce ? blocks[index] : undefined;
    // A note can hold its own `data-conflict` markup; only the placeholders made above have a block.
    if (!block) continue;
    const wrap = document.createElement("section");
    wrap.className = "conflict";
    const header = document.createElement("div");
    header.className = "conflict-head";
    const label = document.createElement("span");
    label.textContent = block.variant === "a" ? "Version A" : block.variant === "d" ? "Version B" : `Version ${block.variant}`;
    const button = document.createElement("button");
    button.textContent = "Keep this version";
    button.addEventListener("click", () => post({ type: "resolveConflict", index, variant: block.variant }));
    header.append(label, button);
    const body = document.createElement("div");
    body.append(sanitizeToFragment(renderFragment(block.body)));
    // Lines in here are counted from the top of the block, not the note, so its boxes can't be ticked
    // and nothing in it stands for a line of the note.
    for (const box of body.querySelectorAll("input[type=checkbox]")) box.dataset.inert = "1";
    for (const element of body.querySelectorAll("[data-line]")) element.removeAttribute("data-line");
    wrap.append(header, body);
    placeholder.replaceWith(wrap);
  }
}

// MARK: Rendering

let currentLineOffset = 0;
// What is on the page: one entry per independent piece of the note, with the nodes drawn for it.
let pieces = [];
let pageBase = null;
let propertiesBox = null, propertiesYaml = null;
let lastAppearance = "";
let lastTiming = null;
let renderStart = 0;

const shiftLines = (nodes, delta) => {
  if (!delta) return;
  const move = (element) => { if (element.dataset.line !== undefined && element.dataset.line !== "") element.dataset.line = String(Number(element.dataset.line) + delta); };
  for (const node of nodes) {
    if (node.nodeType !== Node.ELEMENT_NODE) continue;
    move(node);
    for (const element of node.querySelectorAll("[data-line]")) move(element);
  }
};

/** Builds the nodes for one piece of the note: cleaned, decorated, and queued for colouring and drawing. */
function buildPiece(piece, context) {
  const holder = document.createElement("div");
  holder.append(sanitizeToFragment(piece.html));
  if (context.conflicts.length) renderConflicts(holder, context.conflicts);
  fixCallouts(holder);
  fixMedia(holder, context.basePath);
  decorateBlocks(holder);
  applyMentions(holder);
  applyColors(holder, context.colors);
  for (const block of holder.querySelectorAll(".code-block[data-lang]")) enhance.enhanceCode(block);
  for (const element of holder.querySelectorAll('.math[data-math="pending"]')) enhance.enhanceMath(element);
  for (const element of holder.querySelectorAll(".diagram")) (element.dataset.kind === "abc" ? enhance.enhanceABC : enhance.enhanceMermaid)(element);
  const nodes = [...holder.childNodes];
  shiftLines(nodes, piece.start);
  return nodes;
}

/**
 * Makes the page match the new pieces, touching as little as it can. A piece whose HTML is unchanged
 * keeps the nodes it already has, with their coloured code, typeset formulas and drawn diagrams.
 */
function reconcile(next, context) {
  const old = pieces;
  let head = 0;
  while (head < old.length && head < next.length && old[head].key === next[head].key) head++;
  let oldTail = old.length, newTail = next.length;
  while (oldTail > head && newTail > head && old[oldTail - 1].key === next[newTail - 1].key) { oldTail--; newTail--; }
  const spare = new Map();
  for (let i = head; i < oldTail; i++) {
    const list = spare.get(old[i].key);
    if (list) list.push(old[i]); else spare.set(old[i].key, [old[i]]);
  }
  let reused = 0, built = 0;
  const result = next.map((piece, index) => {
    const kept = index < head ? old[index] : index >= newTail ? old[oldTail + index - newTail] : spare.get(piece.key)?.shift();
    if (kept) {
      reused++;
      shiftLines(kept.nodes, piece.start - kept.start);
      if (context.mentionsChanged) for (const node of kept.nodes) if (node.nodeType === Node.ELEMENT_NODE) { removeMentions(node); applyMentions(node); }
      return { key: piece.key, start: piece.start, nodes: kept.nodes };
    }
    built++;
    return { key: piece.key, start: piece.start, nodes: buildPiece(piece, context) };
  });
  for (const list of spare.values()) for (const piece of list) for (const node of piece.nodes) node.remove();
  let cursor = propertiesBox ? propertiesBox.nextSibling : root.firstChild;
  for (const piece of result) {
    for (const node of piece.nodes) {
      if (node === cursor) cursor = cursor.nextSibling;
      else root.insertBefore(node, cursor);
    }
  }
  while (cursor) { const after = cursor.nextSibling; cursor.remove(); cursor = after; }
  pieces = result;
  return { reused, built };
}

function setProperties(yaml, compact) {
  const wanted = compact || yaml === null || !yaml.trim() ? null : yaml;
  if (wanted === propertiesYaml && (wanted === null) === (propertiesBox === null)) return;
  propertiesBox?.remove();
  propertiesBox = null;
  propertiesYaml = wanted;
  if (wanted === null) return;
  propertiesBox = buildProperties(wanted);
  root.prepend(propertiesBox);
}

let lastHeight = -1;
const reportHeight = () => {
  const height = document.documentElement.scrollHeight;
  if (height === lastHeight) return;
  lastHeight = height;
  post({ type: "height", height });
};

const round = (value) => Math.round(value * 10) / 10;
enhance.setIdleCallback(() => {
  if (!lastTiming) return;
  lineIndex = null;
  const { spent } = enhance;
  lastTiming.highlight = round(spent.highlight);
  lastTiming.math = round(spent.math);
  lastTiming.mermaid = round(spent.mermaid);
  lastTiming.abc = round(spent.abc);
  lastTiming.load = { ...spent.load };
  lastTiming.jobs = spent.jobs;
  lastTiming.slices = spent.slices;
  lastTiming.longestSlice = round(spent.longest);
  lastTiming.settled = round(performance.now() - renderStart);
  post({ type: "settled", timing: lastTiming, height: document.documentElement.scrollHeight });
});

const boot = { scriptStart: round(scriptStart), ready: 0 };

const Perch = {
  /**
   * Draws a note. The text is on the page when this returns and `rendered` is posted; code colours,
   * formulas and diagrams follow in the background, and `settled` is posted when they are all in.
   * Calling it again with nearly the same text only touches the blocks that changed.
   */
  render({ markdown = "", basePath = "", mentions = [], resolved = {}, scrollFraction, scrollLine, compact = false, appearance } = {}) {
    renderStart = performance.now();
    enhance.resetSpent();
    document.body.classList.toggle("compact", !!compact);
    if (appearance) Perch.setAppearance(appearance);
    const { body, lines, yaml } = stripFrontmatter(String(markdown));
    currentLineOffset = lines;
    const { replaced, blocks } = extractConflicts(body);
    const scroller = document.scrollingElement;
    const scrollTop = scroller.scrollTop;

    const parseStart = performance.now();
    const next = parseSegments(replaced);
    for (const piece of next) piece.key = blocks.length && piece.html.includes("data-conflict") ? piece.html + "\n" + JSON.stringify(blocks) : piece.html;
    const parsed = performance.now();

    // Pictures and links are resolved against the note's own folder, so another note starts from nothing.
    if (basePath !== pageBase) {
      pieces = [];
      pageBase = basePath;
      root.replaceChildren();
      propertiesBox = null;
      propertiesYaml = null;
    }
    setProperties(yaml, compact);
    const mentionsChanged = setMentions(mentions);
    const { reused, built } = reconcile(next, { basePath, conflicts: blocks, colors: colorContext(), mentionsChanged });
    for (const link of root.querySelectorAll("a.wikilink")) link.classList.toggle("missing", resolved?.[link.dataset.wiki] === false);
    const drawn = performance.now();

    lineIndex = null;
    if (scrollFraction !== undefined) scroller.scrollTop = scrollFraction * (scroller.scrollHeight - innerHeight);
    else if (scroller.scrollTop !== scrollTop) scroller.scrollTop = scrollTop;
    if (typeof scrollLine === "number") Perch.scrollToSourceLine({ line: scrollLine });
    const toc = [...root.querySelectorAll("h1,h2,h3,h4")].map((heading) => ({
      level: Number(heading.tagName[1]),
      text: heading.textContent,
      line: Number(heading.dataset.line ?? 0) + currentLineOffset,
    }));
    const timing = {
      parse: round(parsed - parseStart), build: round(drawn - parsed), text: round(performance.now() - renderStart),
      pieces: next.length, reused, built, boot,
    };
    lastTiming = timing;
    lastHeight = document.documentElement.scrollHeight;
    post({ type: "rendered", toc, height: lastHeight, timing });
    const began = renderStart;
    requestAnimationFrame(() => { if (began === renderStart) timing.paint = round(performance.now() - began); });
    if (enhance.isIdle()) {
      // Nothing left to draw: the page is already in its final state.
      timing.settled = timing.text;
      post({ type: "settled", timing, height: lastHeight });
    } else {
      enhance.start();
    }
    return true;
  },
  /**
   * Resolves once every code block, formula and diagram on the page has been drawn and every picture
   * has loaded, wherever on the page it is. Pictures far below what is showing are normally left until
   * the reader gets near them; a PDF or a snapshot takes in the whole page, so they are fetched now.
   */
  async settle() {
    const waiting = [];
    for (const image of root.querySelectorAll("img")) {
      if (image.loading === "lazy") image.loading = "eager";
      if (image.complete) continue;
      waiting.push(new Promise((resolve) => {
        image.addEventListener("load", resolve, { once: true });
        image.addEventListener("error", resolve, { once: true });
      }));
    }
    const done = await enhance.settle();
    // A picture that never answers doesn't hold a PDF up for ever.
    if (waiting.length) await Promise.race([Promise.all(waiting), new Promise((resolve) => setTimeout(resolve, 4000))]);
    return done;
  },
  /** Timings of the last render, in milliseconds. */
  get timing() { return lastTiming; },
  boot,
  /** Colour arithmetic for author-chosen colours, shared with tests. */
  color,
  /** Scrolls to a fraction of the page, 0 to 1. Takes the number or { fraction }. */
  scrollTo(where) {
    const fraction = Number(typeof where === "object" && where ? where.fraction : where);
    if (!Number.isFinite(fraction)) return false;
    document.scrollingElement.scrollTop = fraction * (document.scrollingElement.scrollHeight - innerHeight);
    return true;
  },
  /** Brings the block written on a source line to the top, for the outline. Takes the number or { line }. */
  scrollToLine(where) {
    const line = Number(typeof where === "object" && where ? where.line : where);
    if (!Number.isFinite(line)) return false;
    const target = [...document.querySelectorAll("#root [data-line]")].find((el) => Number(el.dataset.line) + currentLineOffset >= line);
    target?.scrollIntoView({ block: "start" });
    return !!target;
  },
  /**
   * Changes how the page looks without rendering again. Every key is optional; null puts the default back.
   * { fontBody, fontHeading, fontMono, fontSize (px), lineHeight, measure ("68ch" or "none"), justify,
   *   colorScheme ("light" or "dark"), variables: { "--perch-accent": "#…" },
   *   style: { "--perch-paragraph-gap": "1.4em" } (reading settings; same rules as variables, "" clears one),
   *   attributes: { properties: "hidden" | "collapsed" | "expanded" | "", images: "full" | "" } }
   * Anything that isn't the kind of value expected is ignored. Diagrams and author-chosen colours follow a
   * new theme on their own: the note is not rendered again.
   */
  setAppearance(appearance) {
    if (!appearance || typeof appearance !== "object") return false;
    // The same settings arrive with every render; applying them again would restyle the whole page for nothing.
    let signature = "";
    try { signature = JSON.stringify(appearance); } catch {}
    if (signature && signature === lastAppearance) return true;
    lastAppearance = signature;
    const style = document.documentElement.style;
    // Values come from Swift, but check them anyway: short text or a number, and nothing that could load a file.
    const usable = (value) => (typeof value === "number" && Number.isFinite(value)) || (typeof value === "string" && value.length <= 300 && !/url\(|[;{}<>]/i.test(value));
    const set = (name, value) => {
      if (value === null || value === undefined || value === "") style.removeProperty(name);
      else if (usable(value)) style.setProperty(name, String(value));
    };
    const has = (key) => Object.prototype.hasOwnProperty.call(appearance, key);
    if (has("fontBody")) set("--perch-font-body", appearance.fontBody);
    if (has("fontHeading")) set("--perch-font-heading", appearance.fontHeading);
    if (has("fontMono")) set("--perch-font-mono", appearance.fontMono);
    if (has("fontSize")) {
      const size = Number(appearance.fontSize);
      set("--perch-font-size", appearance.fontSize && Number.isFinite(size) ? `${Math.min(Math.max(size, 8), 64)}px` : null);
    }
    if (has("lineHeight")) set("--perch-line-height", appearance.lineHeight);
    if (has("measure")) set("--perch-measure", appearance.measure);
    if (has("justify")) {
      set("--perch-text-align", appearance.justify ? "justify" : null);
      set("--perch-hyphens", appearance.justify ? "auto" : null);
    }
    if (has("colorScheme")) {
      explicitScheme = appearance.colorScheme === "dark" || appearance.colorScheme === "light" ? appearance.colorScheme : null;
      applyScheme();
    }
    const variables = appearance.variables && typeof appearance.variables === "object" ? appearance.variables : {};
    // Reading settings go last, so they win over the older keys above that set the same variable.
    const readerStyle = appearance.style && typeof appearance.style === "object" ? appearance.style : {};
    for (const [name, value] of [...Object.entries(variables), ...Object.entries(readerStyle)]) {
      if (/^--perch-[a-z0-9-]+$/.test(name)) set(name, value);
    }
    const attributes = appearance.attributes && typeof appearance.attributes === "object" ? appearance.attributes : {};
    const allowed = { properties: ["hidden", "collapsed", "expanded"], images: ["full"] };
    for (const [name, value] of Object.entries(attributes)) {
      if (!Object.prototype.hasOwnProperty.call(allowed, name)) continue;
      const before = document.documentElement.dataset[name];
      if (allowed[name].includes(value)) document.documentElement.dataset[name] = value;
      else delete document.documentElement.dataset[name];
      if (name === "properties" && before !== document.documentElement.dataset[name]) {
        // A changed setting replaces whatever was clicked open or shut, on the page that is showing too.
        propertiesOpen = undefined;
        for (const box of document.querySelectorAll("details.properties")) box.open = propertiesShouldOpen(box);
      }
    }
    // CSS can't ask what a variable holds, so whether long code lines wrap is also put where it can see it.
    if (style.getPropertyValue("--perch-code-white-space").trim()) document.documentElement.dataset.codeWrap = "1";
    else delete document.documentElement.dataset.codeWrap;
    lineIndex = null;
    themeChanged();
    return true;
  },
  /** Puts a source line (fractions allowed) at the top of the page: keeps the reader beside the editor. */
  scrollToSourceLine({ line = 0, quiet = true } = {}) {
    if (typeof line !== "number" || !Number.isFinite(line)) return false;
    const top = offsetForLine(line);
    if (top === null) return false;
    if (quiet) quietUntil = performance.now() + 250;
    document.scrollingElement.scrollTop = Math.max(0, top - topInset());
    return true;
  },
};

// Blocks that know which source line they came from, in page order.
let lineIndex = null;
let quietUntil = 0;
const topInset = () => parseFloat(getComputedStyle(root).paddingTop) || 0;

function sourceBlocks() {
  if (lineIndex) return lineIndex;
  const scroll = document.scrollingElement.scrollTop;
  const blocks = [];
  let lastLine = -1, lastTop = -1;
  for (const element of document.querySelectorAll("#root [data-line]")) {
    const line = Number(element.dataset.line) + currentLineOffset;
    const top = element.getBoundingClientRect().top + scroll;
    if (!(line > lastLine) || !(top > lastTop) || !element.getClientRects().length) continue;
    blocks.push({ line, top });
    lastLine = line;
    lastTop = top;
  }
  if (blocks.length) blocks.push({ line: blocks[blocks.length - 1].line + 40, top: Math.max(document.scrollingElement.scrollHeight, lastTop + 1) });
  lineIndex = blocks;
  return blocks;
}

function offsetForLine(line) {
  const blocks = sourceBlocks();
  if (!blocks.length) return null;
  if (line <= blocks[0].line) return line <= 0 ? 0 : blocks[0].top * (line / Math.max(blocks[0].line, 1));
  let index = blocks.findIndex((block) => block.line > line);
  if (index < 0) return blocks[blocks.length - 1].top;
  const before = blocks[index - 1], after = blocks[index];
  return before.top + ((line - before.line) / (after.line - before.line)) * (after.top - before.top);
}

function lineAtTop() {
  const blocks = sourceBlocks();
  const y = document.scrollingElement.scrollTop + topInset();
  if (!blocks.length || y <= blocks[0].top) return 0;
  let index = blocks.findIndex((block) => block.top > y);
  if (index < 0) return blocks[blocks.length - 1].line;
  const before = blocks[index - 1], after = blocks[index];
  return before.line + ((y - before.top) / (after.top - before.top)) * (after.line - before.line);
}

let scrollQueued = false;
addEventListener("scroll", () => {
  if (scrollQueued) return;
  scrollQueued = true;
  requestAnimationFrame(() => {
    scrollQueued = false;
    if (document.body.classList.contains("compact")) return;
    post({ type: "scroll", line: lineAtTop(), byUser: performance.now() > quietUntil });
  });
}, { passive: true });
addEventListener("resize", () => { lineIndex = null; });
window.Perch = Perch;

/** A picture or diagram, enlarged over the page. Any click puts it away. */
function showLightbox(content) {
  const overlay = document.createElement("div");
  overlay.className = "perch-lightbox";
  overlay.append(content);
  overlay.addEventListener("click", () => overlay.remove());
  document.body.append(overlay);
}

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") document.querySelector("body > .perch-lightbox")?.remove();
});

document.addEventListener("click", (event) => {
  if (event.target.closest?.("body > .perch-lightbox")) return;
  const copy = event.target.closest?.(".code-copy");
  if (copy) {
    const block = copy.closest(".code-block");
    if (!block || !ownBlocks.has(block)) return;
    // The block's text is the note's own, character for character; only the newline that ends it is left off.
    const text = (block.querySelector("pre")?.textContent ?? "").replace(/\n$/, "");
    // Swift puts it on the clipboard; the page itself never touches it.
    post({ type: "copy", text });
    copy.textContent = "Copied";
    copy.classList.add("copied");
    setTimeout(() => { copy.textContent = "Copy"; copy.classList.remove("copied"); }, 1400);
    return;
  }
  const compact = document.body.classList.contains("compact");
  const image = event.target.closest?.("#root img");
  if (image && !image.closest("a") && !compact) {
    const large = document.createElement("img");
    large.src = image.currentSrc || image.src;
    large.alt = image.alt;
    showLightbox(large);
    return;
  }
  const diagram = event.target.closest?.('#root .diagram[data-state="done"]');
  if (diagram && !compact && !event.target.closest(".abc-audio")) {
    const drawing = (diagram.shadowRoot ?? diagram).querySelector("svg");
    if (drawing) {
      const large = drawing.cloneNode(true);
      // Fill the screen whatever size it was drawn at; the viewBox keeps its shape.
      large.removeAttribute("width");
      large.removeAttribute("height");
      large.style.cssText = "";
      const sheet = document.createElement("div");
      sheet.className = "sheet";
      sheet.append(large);
      showLightbox(sheet);
      return;
    }
  }
  const box = event.target.closest?.("input[type=checkbox]");
  if (box) {
    // Only a task item's own box changes the note, and only when the item knows its own source line.
    const item = box.closest("li");
    const line = item?.classList.contains("task-list-item") && !box.dataset.inert ? item.dataset.line : undefined;
    if (line === undefined || line === "") { event.preventDefault(); return; }
    post({ type: "toggleTask", line: Number(line) + currentLineOffset, checked: box.checked });
    item.classList.toggle("checked", box.checked);
    return;
  }
  const anchor = event.target.closest?.("a");
  if (!anchor) return;
  if (anchor.dataset.mentionPath) {
    event.preventDefault();
    post(event.altKey
      ? { type: "saveMention", text: anchor.dataset.mentionText, path: anchor.dataset.mentionPath }
      : { type: "openNote", path: anchor.dataset.mentionPath });
  } else if (anchor.dataset.wiki) {
    event.preventDefault();
    post({ type: "openWiki", target: anchor.dataset.wiki });
  } else if (anchor.dataset.note) {
    event.preventDefault();
    post({ type: "openNote", path: anchor.dataset.note });
  } else if (/^https?:|^mailto:/i.test(anchor.getAttribute("href") ?? "")) {
    event.preventDefault();
    post({ type: "openExternal", url: anchor.href });
  } else if ((anchor.getAttribute("href") ?? "").startsWith("#")) {
    // Footnotes and links to headings move within the page; nothing is loaded.
    event.preventDefault();
    const id = decodeURIComponent(anchor.getAttribute("href").slice(1));
    const target = id ? document.getElementById(id) ?? document.getElementById("user-content-" + id) : null;
    target?.scrollIntoView({ block: "start" });
  } else {
    // Any other address (tel:, a scheme of some app, one of this page's own files) goes nowhere:
    // a note can't take the reader's page somewhere else.
    event.preventDefault();
  }
});

// Lets Swift size the page to its content, for task details shown inline, and keeps line positions fresh.
new ResizeObserver(() => { lineIndex = null; reportHeight(); }).observe(root);

boot.ready = round(performance.now());
post({ type: "ready", boot });
