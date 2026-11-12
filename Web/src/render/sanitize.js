// The one place note HTML is cleaned before it reaches the page.
import DOMPurify from "dompurify";
import { cleanStyle } from "./color.js";

const CONFIG = {
  ADD_ATTR: ["data-line", "data-wiki", "data-conflict", "target", "open"],
  FORBID_TAGS: ["style", "form", "button", "select", "textarea", "option", "dialog"],
  ALLOW_DATA_ATTR: true,
};

// A cleaner of the page's own. Mermaid cleans its drawings with the shared one, and the rules for
// notes (no inline styles beyond a short list) would strip the styles a diagram is laid out with.
const notePurify = DOMPurify(window);

notePurify.addHook("uponSanitizeElement", (node, data) => {
  // The only input a note may show is a task's checkbox.
  if (data.tagName === "input" && node.getAttribute?.("type")?.toLowerCase() !== "checkbox") node.remove();
});

notePurify.addHook("uponSanitizeAttribute", (node, data) => {
  if (data.attrName !== "style") return;
  // Inline styles are rebuilt from a short list of harmless declarations; see cleanStyle.
  const clean = cleanStyle(data.attrValue);
  if (clean) data.attrValue = clean;
  else data.keepAttr = false;
});

/** Cleans note HTML and returns it as nodes ready to put on the page. */
export function sanitizeToFragment(html) {
  return notePurify.sanitize(html, { ...CONFIG, RETURN_DOM_FRAGMENT: true });
}

/** Output of KaTeX: its own spans, MathML and inline sizes, which the note-style rules would strip. */
const mathPurify = DOMPurify(window);
export function sanitizeMath(html) {
  return mathPurify.sanitize(html, { USE_PROFILES: { html: true, mathMl: true, svg: true }, FORBID_TAGS: ["style", "form", "input", "button", "a", "img", "iframe"], FORBID_ATTR: ["href", "xlink:href", "src"] });
}

/** Output of the code highlighter: spans with classes and nothing else. */
export function sanitizeHighlight(html) {
  return mathPurify.sanitize(html, { ALLOWED_TAGS: ["span"], ALLOWED_ATTR: ["class"] });
}
