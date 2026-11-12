// Markdown to HTML strings. Nothing slow happens here: code is left as plain text, formulas and
// diagrams as their source, and enhance.js colours, typesets and draws them after the text is on screen.
import MarkdownIt from "markdown-it";
import footnote from "markdown-it-footnote";
import mark from "markdown-it-mark";
import sub from "markdown-it-sub";
import sup from "markdown-it-sup";
import taskLists from "markdown-it-task-lists";
import { full as emoji } from "markdown-it-emoji";

function mathPlugin(md) {
  const escape = md.utils.escapeHtml;
  md.inline.ruler.after("escape", "math_inline", (state, silent) => {
    const { src, pos, posMax } = state;
    if (src[pos] !== "$") return false;
    const isDisplay = src[pos + 1] === "$";
    const open = isDisplay ? 2 : 1;
    if (!isDisplay) {
      // Prices are not formulas: "$5 and $10", "US$5", "5$ or 10$" all stay text.
      if (pos + 1 >= posMax || /\s/.test(src[pos + 1])) return false;
      if (pos > 0 && /[\p{L}\p{N}$]/u.test(src[pos - 1])) return false;
    }
    let end = pos + open;
    while (end < posMax) {
      if (src[end] === "\\") { end += 2; continue; }
      if (src[end] === "$" && (!isDisplay || src[end + 1] === "$")) break;
      end++;
    }
    if (end >= posMax || end === pos + open) return false;
    if (!isDisplay) {
      if (/\s/.test(src[end - 1])) return false;
      if (/[\p{L}\p{N}]/u.test(src[end + 1] || "")) return false;
    }
    if (!silent) {
      const token = state.push("math_inline", "math", 0);
      token.content = src.slice(pos + open, end);
      token.meta = { display: isDisplay };
    }
    state.pos = end + open;
    return true;
  });
  md.block.ruler.after("blockquote", "math_block", (state, start, end, silent) => {
    if (state.sCount[start] - state.blkIndent >= 4) return false;
    const first = state.src.slice(state.bMarks[start] + state.tShift[start], state.eMarks[start]).trim();
    if (!first.startsWith("$$")) return false;
    if (first.length >= 5 && first.endsWith("$$")) {
      if (silent) return true;
      const token = state.push("math_block", "math", 0);
      token.content = first.slice(2, -2);
      token.map = [start, start + 1];
      state.line = start + 1;
      return true;
    }
    if (first !== "$$" && first.includes("$$")) return false;
    let next = start + 1;
    while (next < end) {
      // A formula never runs past the block it is in: the end of a quote or list item stops the search.
      const line = state.src.slice(state.bMarks[next] + state.tShift[next], state.eMarks[next]).trim();
      if (line && state.sCount[next] < state.blkIndent) return false;
      if (line.endsWith("$$")) break;
      next++;
    }
    if (next >= end) return false;
    if (silent) return true;
    const token = state.push("math_block", "math", 0);
    const last = state.src.slice(state.bMarks[next] + state.tShift[next], state.eMarks[next]).trim().slice(0, -2);
    token.content = [first.slice(2), state.getLines(start + 1, next, state.blkIndent, false).replace(/\n$/, ""), last].filter((part) => part.trim()).join("\n");
    token.map = [start, next + 1];
    state.line = next + 1;
    return true;
  }, { alt: ["paragraph", "reference", "blockquote", "list"] });
  // The TeX itself is the placeholder: readable if the formula can't be typeset, and replaced when it is.
  md.renderer.rules.math_inline = (tokens, i) =>
    `<span class="math ${tokens[i].meta.display ? "math-display" : "math-inline"}" data-math="pending">${escape(tokens[i].content)}</span>`;
  md.renderer.rules.math_block = (tokens, i) =>
    `<div class="math-block"${tokens[i].attrGet("data-line") !== null ? ` data-line="${tokens[i].attrGet("data-line")}"` : ""}><div class="math math-display" data-math="pending">${escape(tokens[i].content)}</div></div>\n`;
}

function wikiPlugin(md) {
  md.inline.ruler.before("link", "wikilink", (state, silent) => {
    const { src, pos } = state;
    if (src[pos] !== "[" || src[pos + 1] !== "[") return false;
    const end = src.indexOf("]]", pos + 2);
    if (end < 0) return false;
    const inner = src.slice(pos + 2, end);
    if (!inner.trim() || /[\[\]\n]/.test(inner)) return false;
    if (!silent) {
      // In a table the bar between target and label is written `\|`, so it doesn't end the cell.
      const bar = inner.search(/\\?\|/);
      const target = bar < 0 ? inner : inner.slice(0, bar);
      const label = bar < 0 ? inner : inner.slice(bar).replace(/^\\?\|/, "");
      const token = state.push("wikilink", "a", 0);
      token.meta = { target: target.trim(), label: (label.trim() || target).trim() };
    }
    state.pos = end + 2;
    return true;
  });
  md.renderer.rules.wikilink = (tokens, i) => {
    const { target, label } = tokens[i].meta;
    const escape = md.utils.escapeHtml;
    return `<a class="wikilink" href="#" data-wiki="${escape(target)}">${escape(label)}</a>`;
  };
}

// Bold, strike-through and highlight that close right after punctuation and right before a word, as in
// `**IBM, Salesforce:**Emphasize` or a redline's `~~Customer.~~Supplier`. CommonMark won't let that closing mark
// close (GitHub shows the marks), but the meaning is plain and notes written by AI tools do it often; the same
// goes for an opening mark after a word and before punctuation, `See**"the brief"**`. Only `*`, `~` and `=`
// are eased: underscores keep the strict rule, so `snake_case_names` stay as they are, and a mark with a space
// on the side it would face (`2 * 3`, `** not bold **`) is still just a character.
function easedFlanking(md) {
  const { isWhiteSpace, isPunctChar, isMdAsciiPunct } = md.utils;
  const punctuation = (code) => isMdAsciiPunct(code) || isPunctChar(String.fromCharCode(code));
  const space = (code) => isWhiteSpace(code);
  const scan = md.inline.State.prototype.scanDelims;
  md.inline.State.prototype.scanDelims = function (start, canSplitWord) {
    const result = scan.call(this, start, canSplitWord);
    const marker = this.src.charCodeAt(start);
    if (marker !== 0x2a && marker !== 0x7e && marker !== 0x3d) return result;
    const before = start > 0 ? this.src.charCodeAt(start - 1) : 0x20;
    const after = start + result.length < this.posMax ? this.src.charCodeAt(start + result.length) : 0x20;
    if (!result.can_close && punctuation(before) && !space(after) && !punctuation(after)) result.can_close = true;
    if (!result.can_open && punctuation(after) && !space(before) && !punctuation(before)) result.can_open = true;
    return result;
  };
}

export const md = new MarkdownIt({ html: true, linkify: true, breaks: true, typographer: false })
  .use(easedFlanking)
  .use(footnote)
  .use(mark)
  .use(sub)
  .use(sup)
  .use(emoji)
  .use(taskLists, { enabled: true, label: false })
  .use(mathPlugin)
  .use(wikiPlugin);

// "www.example.com" and "example.org" become links without a scheme, but only for endings that are
// plainly web addresses. The two-letter country endings are left out: `README.md`, `build.sh`, `main.rs`
// and `setup.py` are file names in a notebook, not Moldova, Saint Helena, Serbia and Paraguay.
md.linkify.set({ fuzzyLink: true, fuzzyEmail: true, fuzzyIP: false });
md.linkify.tlds("com org net edu gov mil int io dev app ai co me tv fm us uk ca au de fr es it nl se no fi dk ch at be ie nz jp cn in br ru eu info biz xyz tech blog page site online cloud wiki news design".split(" "), false);

const escapeHtml = md.utils.escapeHtml;
const lineAttribute = (token) => (token.attrGet("data-line") !== null ? ` data-line="${token.attrGet("data-line")}"` : "");

// Code keeps the tag exactly as the note wrote it; which highlighter that means is decided later.
md.renderer.rules.fence = (tokens, i) => {
  const token = tokens[i];
  const tag = md.utils.unescapeAll(token.info).trim().split(/\s+/)[0] ?? "";
  const kind = tag.toLowerCase();
  if (kind === "mermaid" || kind === "abc") {
    return `<pre class="diagram-source" data-kind="${kind}"${lineAttribute(token)}><code>${escapeHtml(token.content)}</code></pre>\n`;
  }
  return `<pre${tag ? ` data-lang="${escapeHtml(tag)}"` : ""}${lineAttribute(token)}><code>${escapeHtml(token.content)}</code></pre>\n`;
};
md.renderer.rules.code_block = (tokens, i) =>
  `<pre${lineAttribute(tokens[i])}><code>${escapeHtml(tokens[i].content)}</code></pre>\n`;

const VOID = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]);

/** How many more tags a piece of raw HTML opens than it closes. */
function tagBalance(html) {
  let balance = 0;
  const text = html.replace(/<!--[\s\S]*?-->/g, "");
  for (const match of text.matchAll(/<(\/?)([a-zA-Z][\w:-]*)(?:"[^"]*"|'[^']*'|[^'">])*?(\/?)>/g)) {
    if (VOID.has(match[2].toLowerCase()) || match[3]) continue;
    balance += match[1] ? -1 : 1;
  }
  return balance;
}

/**
 * Parses a note into independent pieces: runs of top-level blocks, each with its HTML and first line.
 * Lines inside a piece are numbered from the piece's own start, so the same text gives the same HTML
 * wherever it sits in the note. That HTML is what tells an unchanged block from a changed one.
 * Raw HTML left open (`<details>`, `<div align="center">`) keeps the blocks up to its closing tag in one piece.
 */
export function parseSegments(source) {
  const env = {};
  const tokens = md.parse(source, env);
  const segments = [];
  let from = 0, depth = 0, open = 0;
  const flush = (to) => {
    const slice = tokens.slice(from, to);
    from = to;
    if (!slice.length) return;
    const first = slice.find((token) => token.map);
    const start = first ? first.map[0] : segments.length ? segments[segments.length - 1].end : 0;
    let end = start;
    for (const token of slice) {
      if (!token.map) continue;
      end = Math.max(end, token.map[1]);
      if (token.nesting >= 0 && token.level <= 12) token.attrSet("data-line", String(token.map[0] - start));
    }
    segments.push({ start, end, html: md.renderer.render(slice, md.options, env) });
  };
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    depth += token.nesting;
    if (token.level === 0 && token.type === "html_block") open = Math.max(0, open + tagBalance(token.content));
    if (depth === 0 && open === 0) flush(i + 1);
  }
  flush(tokens.length);
  return segments;
}

/** Renders a short piece of Markdown on its own, for the two versions inside a sync conflict. */
export const renderFragment = (source) => md.render(source);
