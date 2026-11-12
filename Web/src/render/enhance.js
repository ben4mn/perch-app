// Everything slow, done after the text is on screen: colouring code, typesetting formulas, drawing
// diagrams and music. Each library is fetched the first time a note needs it. Work runs in short
// slices, nearest the reader first, so scrolling and typing are never held up.
import { aliases, embeds, loaders } from "./languages.generated.js";
import { sanitizeHighlight, sanitizeMath } from "./sanitize.js";

/** Milliseconds spent since the last render began, by kind of work. Reported to Swift when the page settles. */
export const spent = { highlight: 0, math: 0, mermaid: 0, abc: 0, load: {}, jobs: 0, slices: 0, longest: 0 };
export function resetSpent() {
  spent.highlight = spent.math = spent.mermaid = spent.abc = spent.jobs = spent.slices = spent.longest = 0;
  spent.load = {};
}

const remember = (cache, key, value, limit) => {
  if (cache.size >= limit) cache.delete(cache.keys().next().value);
  cache.set(key, value);
};

// MARK: Libraries, fetched on demand

const once = (name, load) => {
  let promise;
  return () => (promise ??= (async () => {
    const start = performance.now();
    try {
      return await load();
    } catch (error) {
      // A library that couldn't be fetched is asked for again the next time something needs it.
      promise = undefined;
      throw error;
    } finally {
      spent.load[name] = Math.round(performance.now() - start);
    }
  })());
};

const stylesheet = (href) => new Promise((resolve) => {
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = href;
  link.onload = link.onerror = () => resolve();
  document.head.append(link);
});

const loadHighlighter = once("highlighter", async () => (await import("highlight.js/lib/core")).default);
const loadKatex = once("katex", async () => {
  const [module] = await Promise.all([import("katex"), stylesheet("render-katex.css")]);
  return module.default;
});
const loadMermaid = once("mermaid", async () => (await import("mermaid")).default);
const loadABC = once("abcjs", async () => (await import("abcjs")).default);

let hljs = null;
const moduleLoads = new Map(), languageLoads = new Map();
const loadModule = (name) => {
  if (!moduleLoads.has(name)) moduleLoads.set(name, loaders[name]().then((module) => module.default));
  return moduleLoads.get(name);
};
/** Fetches one language and every language it can embed (HTML holds CSS and JavaScript, which holds HTML…). Resolves to false if it can't be had. */
function loadLanguage(name) {
  let promise = languageLoads.get(name);
  if (!promise) {
    const names = [name];
    for (const next of names) for (const other of embeds[next] ?? []) if (loaders[other] && !names.includes(other)) names.push(other);
    promise = (async () => {
      try {
        hljs ??= await loadHighlighter();
        const definitions = await Promise.all(names.map(loadModule));
        names.forEach((each, index) => { if (!hljs.getLanguage(each)) hljs.registerLanguage(each, definitions[index]); });
        return true;
      } catch {
        languageLoads.delete(name);
        return false;
      }
    })();
    languageLoads.set(name, promise);
  }
  return promise;
}

/** The highlighter for a tag as written in a note ("py", "C++", "zsh"), or null for plain text and unknown tags. */
export function languageFor(tag) {
  const name = aliases[String(tag ?? "").toLowerCase()];
  return name && name !== "plaintext" ? name : null;
}

// MARK: The queue

const jobs = new Map(); // element → job
let background = [], urgent = [];
let pumping = false, draining = false, startTimer = null;
let wake = null;
const idleWaiters = [];
let onIdle = () => {};
export function setIdleCallback(callback) { onIdle = callback; }

const watcher = "IntersectionObserver" in window
  ? new IntersectionObserver((entries) => {
      let found = false;
      for (const entry of entries) {
        const job = jobs.get(entry.target);
        if (!job || !entry.isIntersecting || job.urgent) continue;
        job.urgent = found = true;
        urgent.push(job);
      }
      if (found) start();
    }, { rootMargin: "700px 0px 900px 0px" })
  : null;

/** Work drawn by this file, which no markup in a note can claim to be. */
const drawn = new WeakSet();
export const isDrawn = (element) => drawn.has(element);

function add(element, run) {
  const existing = jobs.get(element);
  if (existing) existing.cancelled = true;
  const job = { element, run, urgent: false, cancelled: false };
  jobs.set(element, job);
  background.push(job);
  watcher?.observe(element);
  // While the page is out of sight nothing is drawn, and notes may come and go: work for blocks that
  // have left the page is dropped rather than kept until someone looks.
  if (background.length > 3000 && background.length % 500 === 0) forget();
}

function forget() {
  const gone = (job) => job.cancelled || job.done || !job.element.isConnected;
  for (const job of background) if (gone(job)) finish(job);
  background = background.filter((job) => !gone(job));
  urgent = urgent.filter((job) => !gone(job));
}

function finish(job) {
  if (jobs.get(job.element) === job) {
    jobs.delete(job.element);
    watcher?.unobserve(job.element);
  }
}

// A slice is checked after each block, so it runs over by part of one block: 8 keeps a slice of
// ordinary blocks under about 12 ms, inside one frame with room for scrolling.
const SLICE = 8;
const pause = () => new Promise((resolve) => {
  wake = resolve;
  setTimeout(resolve, 0);
});
/** Resolves when the page can be seen again, or when someone asks for everything to be finished (a PDF). */
const whenShown = () => new Promise((resolve) => {
  const done = () => { document.removeEventListener("visibilitychange", check); resolve(); };
  const check = () => { if (!document.hidden) done(); };
  document.addEventListener("visibilitychange", check);
  wake = done;
});

async function pump() {
  if (pumping) return;
  pumping = true;
  let sliceStart = performance.now();
  const endSlice = () => {
    const length = performance.now() - sliceStart;
    spent.slices++;
    if (length > spent.longest) spent.longest = length;
  };
  for (;;) {
    // Nobody is looking: wait until they are. The text is already there; only the colouring waits.
    if (!draining && document.hidden && jobs.size) {
      await whenShown();
      sliceStart = performance.now();
    }
    let job = null;
    while (urgent.length && !job) { const next = urgent.shift(); if (!next.cancelled && !next.done) job = next; }
    while (background.length && !job) { const next = background.shift(); if (!next.cancelled && !next.done) job = next; }
    if (!job) break;
    job.done = true;
    finish(job);
    if (!job.element.isConnected) continue;
    try { await job.run(); } catch (error) { console.error(error); }
    spent.jobs++;
    if (!draining && performance.now() - sliceStart > SLICE) {
      endSlice();
      await pause();
      sliceStart = performance.now();
    }
  }
  endSlice();
  pumping = false;
  draining = false;
  for (const resolve of idleWaiters.splice(0)) resolve(true);
  onIdle();
}

/** Begins work after the text has had a chance to paint. */
export function start() {
  if (pumping || startTimer !== null) return;
  const go = () => {
    if (startTimer === null) return;
    clearTimeout(startTimer);
    startTimer = null;
    pump();
  };
  // A frame first, so the plain text is painted; the timer covers a page that isn't being shown.
  startTimer = setTimeout(go, 60);
  requestAnimationFrame(() => setTimeout(go, 0));
}

export const isIdle = () => !pumping && startTimer === null && !jobs.size;

/** Resolves when everything queued has been drawn. Finishes the work without pausing between slices. */
export function settle() {
  if (isIdle()) return Promise.resolve(true);
  draining = true;
  const done = new Promise((resolve) => idleWaiters.push(resolve));
  if (startTimer !== null) { clearTimeout(startTimer); startTimer = null; }
  wake?.();
  pump();
  return done;
}

// Where the page is scrolled to, as last heard from a scroll event. Asking the page itself would make
// it lay everything out again after every change.
let scrolledTo = 0;
addEventListener("scroll", () => { scrolledTo = document.scrollingElement?.scrollTop ?? 0; }, { passive: true });

/** Runs `change` on a block and, if the block is above what's being read, keeps the reader's place. */
function keepingPlace(element, change) {
  const scroller = document.scrollingElement;
  if (!scroller || scrolledTo <= 0) return change();
  const before = element.getBoundingClientRect();
  change();
  if (before.bottom > 0) return;
  const delta = element.getBoundingClientRect().height - before.height;
  if (delta) scroller.scrollTop += delta;
}

// MARK: Code

const highlightCache = new Map();
const HIGHLIGHT_LIMIT = 200_000;

function paintCode(block, code, html) {
  code.innerHTML = html;
  code.classList.add("hljs");
  block.dataset.highlighted = "1";
}

/** Colours one code block: at once if this exact code was coloured before, otherwise in the queue. */
export function enhanceCode(block) {
  const code = block.querySelector("pre > code");
  const language = languageFor(block.dataset.lang);
  if (!code || !language) return;
  const text = code.textContent;
  if (!text.trim() || text.length > HIGHLIGHT_LIMIT) return;
  const key = language + "\n" + text;
  const cached = highlightCache.get(key);
  if (cached !== undefined) return paintCode(block, code, cached);
  add(block, async () => {
    if (!(await loadLanguage(language))) return;
    const begin = performance.now();
    let html;
    try {
      html = sanitizeHighlight(hljs.highlight(text, { language, ignoreIllegals: true }).value);
    } catch {
      return;
    }
    remember(highlightCache, key, html, 600);
    if (code.isConnected && code.textContent === text) paintCode(block, code, html);
    spent.highlight += performance.now() - begin;
  });
}

// MARK: Maths

const mathCache = new Map();

function paintMath(element, result) {
  const tex = element.textContent;
  keepingPlace(element.closest(".math-block") ?? element, () => {
    if (result.error) {
      element.dataset.math = "error";
      element.title = result.error;
      if (element.classList.contains("math-display") && element.parentElement?.classList.contains("math-block")) {
        const note = document.createElement("div");
        note.className = "render-error";
        note.textContent = `This formula couldn't be typeset: ${result.error}`;
        const source = document.createElement("pre");
        source.className = "source";
        source.textContent = tex;
        element.replaceChildren(note, source);
      }
    } else {
      element.innerHTML = result.html;
      element.dataset.math = "done";
      drawn.add(element);
    }
    element.dataset.tex = tex;
  });
}

export function enhanceMath(element) {
  const display = element.classList.contains("math-display");
  const tex = element.textContent;
  const key = (display ? "D" : "I") + tex;
  const cached = mathCache.get(key);
  if (cached) return paintMath(element, cached);
  add(element, async () => {
    let katex;
    // Without the library the formula stays as its TeX, which is what the note says anyway.
    try { katex = await loadKatex(); } catch { return; }
    const begin = performance.now();
    let result;
    try {
      result = { html: sanitizeMath(katex.renderToString(tex, { displayMode: display, throwOnError: true, output: "htmlAndMathml", strict: "ignore", trust: false, maxExpand: 1000 })) };
    } catch (error) {
      // KaTeX's message ends with where it stopped, underlined character by character; the reason is enough.
      result = { error: String(error?.message ?? error).replace(/^KaTeX parse error:\s*/, "").replace(/\u0332/g, "").replace(/ at position \d+:.*$/s, "").trim() };
    }
    remember(mathCache, key, result, 2000);
    if (element.isConnected) paintMath(element, result);
    spent.math += performance.now() - begin;
  });
}

// MARK: Diagrams

const mermaidCache = new Map(); // theme + source → svg
const heights = new Map(); // source → last drawn height, so the space is held before the next draw
// Heights are noted as the browser reports them, never asked for: asking forces a layout of the whole note.
const sizeWatcher = "ResizeObserver" in window
  ? new ResizeObserver((entries) => {
      for (const entry of entries) {
        const element = entry.target;
        if (element.dataset.state !== "done" || !element.isConnected) continue;
        const height = entry.borderBoxSize?.[0]?.blockSize ?? entry.contentRect.height;
        if (height > 0) remember(heights, element.dataset.kind + "\n" + (element.__source ?? ""), Math.round(height), 200);
      }
    })
  : null;
const heldHeight = (element) => heights.get(element.dataset.kind + "\n" + (element.__source ?? ""));
let mermaidCount = 0;
let mermaidThemeKey = null;
let currentTheme = () => ({ theme: "default" });
/** How diagrams should be coloured right now. Set by the page, which knows the theme. */
export function setMermaidTheme(provider) { currentTheme = provider; }

function showError(element, message, source) {
  const note = document.createElement("div");
  note.className = "render-error";
  note.textContent = message;
  const pre = document.createElement("pre");
  pre.className = "source";
  pre.textContent = source;
  if (element.shadowRoot) element.shadowRoot.innerHTML = "<slot></slot>";
  element.replaceChildren(note, pre);
  element.dataset.state = "error";
  element.style.minHeight = "";
}

/**
 * A drawn diagram lives in a shadow tree of its own. Mermaid's SVG carries a stylesheet, and a
 * stylesheet added to the page itself makes the browser restyle every element of a long note.
 */
function paintMermaid(element, svg, themeKey) {
  keepingPlace(element, () => {
    element.replaceChildren();
    const tree = element.shadowRoot ?? element.attachShadow({ mode: "open" });
    tree.innerHTML = `<style>:host{display:block;overflow-x:auto;overflow-y:hidden}svg{display:block;margin:0 auto;max-width:100%;height:auto}</style>${svg}`;
    // A wide diagram on a narrow screen shrinks to fit, but only so far: below about three fifths of
    // its drawn size the labels can't be read, so from there it keeps that size and scrolls sideways.
    const drawing = tree.querySelector("svg");
    const natural = drawing?.viewBox?.baseVal?.width ?? 0;
    if (natural > 0) drawing.style.minWidth = `${Math.round(natural * 0.6)}px`;
    element.dataset.state = "done";
    element.style.minHeight = "";
  });
  element.__themeKey = themeKey;
}

export function enhanceMermaid(element) {
  const source = element.__source ?? "";
  const themeKey = JSON.stringify(currentTheme());
  const cached = mermaidCache.get(themeKey + "\n" + source);
  if (cached) return paintMermaid(element, cached, themeKey);
  if (element.dataset.state !== "done" && heldHeight(element)) element.style.minHeight = heldHeight(element) + "px";
  sizeWatcher?.observe(element);
  add(element, async () => {
    let mermaid;
    try {
      mermaid = await loadMermaid();
    } catch {
      if (element.isConnected) keepingPlace(element, () => showError(element, "The diagram library couldn't be loaded, so this is the diagram as written.", source));
      return;
    }
    const begin = performance.now();
    const theme = currentTheme(), key = JSON.stringify(theme);
    if (key !== mermaidThemeKey) {
      mermaid.initialize({ startOnLoad: false, securityLevel: "strict", fontFamily: "inherit", suppressErrorRendering: true, ...theme });
      mermaidThemeKey = key;
    }
    const id = `mermaid-${++mermaidCount}`;
    try {
      if (!source.trim()) throw new Error("The diagram is empty.");
      const { svg } = await mermaid.render(id, source);
      remember(mermaidCache, key + "\n" + source, svg, 60);
      if (element.isConnected) {
        paintMermaid(element, svg, key);
      }
    } catch (error) {
      // The parser's first lines say where it stopped; its list of every token it would have accepted helps nobody.
      const message = String(error?.message ?? error).split("\n").filter((line) => line.trim() && !/^Expecting /.test(line)).slice(0, 3).join("\n");
      if (element.isConnected) keepingPlace(element, () => showError(element, `Mermaid couldn't draw this diagram.\n${message}`, source));
    } finally {
      // Mermaid can leave its scratch elements behind when a diagram fails.
      document.getElementById(id)?.remove();
      document.getElementById("d" + id)?.remove();
      spent.mermaid += performance.now() - begin;
    }
  });
}

/** After a theme change: diagrams drawn in other colours are drawn again, in place, without a re-render. */
export function redrawDiagramsForTheme(root) {
  const key = JSON.stringify(currentTheme());
  let any = false;
  for (const element of root.querySelectorAll('.diagram[data-kind="mermaid"][data-state="done"]')) {
    if (element.__themeKey === key) continue;
    enhanceMermaid(element);
    any = true;
  }
  if (any) start();
}

export function enhanceABC(element) {
  const source = element.__source ?? "";
  if (heldHeight(element)) element.style.minHeight = heldHeight(element) + "px";
  sizeWatcher?.observe(element);
  add(element, async () => {
    let abcjs;
    try {
      abcjs = await loadABC();
    } catch {
      if (element.isConnected) keepingPlace(element, () => showError(element, "The music library couldn't be loaded, so this is the tune as written.", source));
      return;
    }
    if (!element.isConnected) return;
    const begin = performance.now();
    try {
      const paper = document.createElement("div");
      paper.className = "abc-paper";
      const controls = document.createElement("div");
      controls.className = "abc-audio";
      keepingPlace(element, () => {
        element.replaceChildren(paper, controls);
        drawn.add(element);
        const [visual] = abcjs.renderAbc(paper, source, { responsive: "resize", add_classes: true });
        element.dataset.state = "done";
        element.style.minHeight = "";
        if (visual && abcjs.synth.supportsAudio()) {
          const synth = new abcjs.synth.SynthController();
          synth.load(controls, null, { displayRestart: true, displayPlay: true, displayProgress: true });
          synth.setTune(visual, false).catch(() => {});
        }
      });
    } catch (error) {
      showError(element, `The music notation couldn't be drawn.\n${error?.message ?? error}`, source);
    } finally {
      spent.abc += performance.now() - begin;
    }
  });
}
