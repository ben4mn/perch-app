// Colour arithmetic for author-chosen colours. Pure functions: no DOM, no theme lookups.
// The note keeps the colour its author picked; these work out what to draw so it stays readable
// on whichever theme is showing.

/** The ten colours the editor offers, in its order. */
export const PALETTE = {
  red: "#D94F3D", orange: "#E8843C", amber: "#C99A1B", green: "#3F9B5B", teal: "#1F9E96",
  blue: "#3B82D9", indigo: "#6B5BD2", purple: "#A855C7", pink: "#D4588F", gray: "#7A7F87",
};

const NAMED = {
  aliceblue: "f0f8ff", antiquewhite: "faebd7", aqua: "00ffff", aquamarine: "7fffd4", azure: "f0ffff", beige: "f5f5dc",
  bisque: "ffe4c4", black: "000000", blanchedalmond: "ffebcd", blue: "0000ff", blueviolet: "8a2be2", brown: "a52a2a",
  burlywood: "deb887", cadetblue: "5f9ea0", chartreuse: "7fff00", chocolate: "d2691e", coral: "ff7f50",
  cornflowerblue: "6495ed", cornsilk: "fff8dc", crimson: "dc143c", cyan: "00ffff", darkblue: "00008b", darkcyan: "008b8b",
  darkgoldenrod: "b8860b", darkgray: "a9a9a9", darkgreen: "006400", darkgrey: "a9a9a9", darkkhaki: "bdb76b",
  darkmagenta: "8b008b", darkolivegreen: "556b2f", darkorange: "ff8c00", darkorchid: "9932cc", darkred: "8b0000",
  darksalmon: "e9967a", darkseagreen: "8fbc8f", darkslateblue: "483d8b", darkslategray: "2f4f4f", darkslategrey: "2f4f4f",
  darkturquoise: "00ced1", darkviolet: "9400d3", deeppink: "ff1493", deepskyblue: "00bfff", dimgray: "696969",
  dimgrey: "696969", dodgerblue: "1e90ff", firebrick: "b22222", floralwhite: "fffaf0", forestgreen: "228b22",
  fuchsia: "ff00ff", gainsboro: "dcdcdc", ghostwhite: "f8f8ff", gold: "ffd700", goldenrod: "daa520", gray: "808080",
  green: "008000", greenyellow: "adff2f", grey: "808080", honeydew: "f0fff0", hotpink: "ff69b4", indianred: "cd5c5c",
  indigo: "4b0082", ivory: "fffff0", khaki: "f0e68c", lavender: "e6e6fa", lavenderblush: "fff0f5", lawngreen: "7cfc00",
  lemonchiffon: "fffacd", lightblue: "add8e6", lightcoral: "f08080", lightcyan: "e0ffff", lightgoldenrodyellow: "fafad2",
  lightgray: "d3d3d3", lightgreen: "90ee90", lightgrey: "d3d3d3", lightpink: "ffb6c1", lightsalmon: "ffa07a",
  lightseagreen: "20b2aa", lightskyblue: "87cefa", lightslategray: "778899", lightslategrey: "778899",
  lightsteelblue: "b0c4de", lightyellow: "ffffe0", lime: "00ff00", limegreen: "32cd32", linen: "faf0e6", magenta: "ff00ff",
  maroon: "800000", mediumaquamarine: "66cdaa", mediumblue: "0000cd", mediumorchid: "ba55d3", mediumpurple: "9370db",
  mediumseagreen: "3cb371", mediumslateblue: "7b68ee", mediumspringgreen: "00fa9a", mediumturquoise: "48d1cc",
  mediumvioletred: "c71585", midnightblue: "191970", mintcream: "f5fffa", mistyrose: "ffe4e1", moccasin: "ffe4b5",
  navajowhite: "ffdead", navy: "000080", oldlace: "fdf5e6", olive: "808000", olivedrab: "6b8e23", orange: "ffa500",
  orangered: "ff4500", orchid: "da70d6", palegoldenrod: "eee8aa", palegreen: "98fb98", paleturquoise: "afeeee",
  palevioletred: "db7093", papayawhip: "ffefd5", peachpuff: "ffdab9", peru: "cd853f", pink: "ffc0cb", plum: "dda0dd",
  powderblue: "b0e0e6", purple: "800080", rebeccapurple: "663399", red: "ff0000", rosybrown: "bc8f8f", royalblue: "4169e1",
  saddlebrown: "8b4513", salmon: "fa8072", sandybrown: "f4a460", seagreen: "2e8b57", seashell: "fff5ee", sienna: "a0522d",
  silver: "c0c0c0", skyblue: "87ceeb", slateblue: "6a5acd", slategray: "708090", slategrey: "708090", snow: "fffafa",
  springgreen: "00ff7f", steelblue: "4682b4", tan: "d2b48c", teal: "008080", thistle: "d8bfd8", tomato: "ff6347",
  turquoise: "40e0d0", violet: "ee82ee", wheat: "f5deb3", white: "ffffff", whitesmoke: "f5f5f5", yellow: "ffff00",
  yellowgreen: "9acd32",
};

const clamp = (value, low, high) => Math.min(Math.max(value, low), high);

function hslToRgb(h, s, l) {
  h = ((h % 360) + 360) % 360;
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return { r: Math.round((r + m) * 255), g: Math.round((g + m) * 255), b: Math.round((b + m) * 255) };
}

function rgbToHsl({ r, g, b }) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
  if (d === 0) return { h: 0, s: 0, l };
  const s = d / (1 - Math.abs(2 * l - 1));
  const h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return { h: (h * 60 + 360) % 360, s: clamp(s, 0, 1), l };
}

/**
 * Reads a CSS colour written as hex, rgb()/rgba(), hsl()/hsla() or a named keyword.
 * Returns { r, g, b } (0–255) or null for anything else, including `transparent`, `currentcolor` and `var()`.
 */
export function parseColor(input) {
  if (typeof input !== "string") return null;
  const value = input.trim().toLowerCase();
  let match = /^#([0-9a-f]{3,8})$/.exec(value);
  if (match) {
    let hex = match[1];
    if (hex.length === 3 || hex.length === 4) hex = [...hex].map((c) => c + c).join("");
    if (hex.length !== 6 && hex.length !== 8) return null;
    return { r: parseInt(hex.slice(0, 2), 16), g: parseInt(hex.slice(2, 4), 16), b: parseInt(hex.slice(4, 6), 16) };
  }
  match = /^rgba?\(\s*(\d{1,3}(?:\.\d+)?)(%?)\s*[, ]\s*(\d{1,3}(?:\.\d+)?)(%?)\s*[, ]\s*(\d{1,3}(?:\.\d+)?)(%?)\s*(?:[,/]\s*\d*\.?\d+%?\s*)?\)$/.exec(value);
  if (match) {
    const channel = (number, percent) => Math.round(clamp(percent ? Number(number) * 2.55 : Number(number), 0, 255));
    return { r: channel(match[1], match[2]), g: channel(match[3], match[4]), b: channel(match[5], match[6]) };
  }
  match = /^hsla?\(\s*(-?\d{1,3}(?:\.\d+)?)(?:deg)?\s*[, ]\s*(\d{1,3}(?:\.\d+)?)%\s*[, ]\s*(\d{1,3}(?:\.\d+)?)%\s*(?:[,/]\s*\d*\.?\d+%?\s*)?\)$/.exec(value);
  if (match) return hslToRgb(Number(match[1]), clamp(Number(match[2]) / 100, 0, 1), clamp(Number(match[3]) / 100, 0, 1));
  if (Object.prototype.hasOwnProperty.call(NAMED, value)) return parseColor("#" + NAMED[value]);
  return null;
}

export const toHex = ({ r, g, b }) => "#" + [r, g, b].map((channel) => clamp(Math.round(channel), 0, 255).toString(16).padStart(2, "0")).join("");

/** WCAG relative luminance. */
export function luminance({ r, g, b }) {
  const linear = (channel) => { const c = channel / 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
}

/** WCAG contrast ratio between two { r, g, b } colours, 1 to 21. */
export function contrast(a, b) {
  const la = luminance(a), lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

const asRGB = (color) => (typeof color === "string" ? parseColor(color) : color);
const blend = (over, under, alpha) => ({
  r: under.r + (over.r - under.r) * alpha, g: under.g + (over.g - under.g) * alpha, b: under.b + (over.b - under.b) * alpha,
});

/** One colour laid over another at `amount` (0 to 1), as a hex string. */
export function mix(over, under, amount) {
  const top = asRGB(over), bottom = asRGB(under);
  return top && bottom ? toHex(blend(top, bottom, amount)) : null;
}

// The editor's rule for a picked text colour (FormatPalette.legible in Swift), step for step and in the
// same arithmetic (channels 0 to 1, nothing rounded until the end), so the reader and the editor draw
// the same colour. Tests/Fixtures/Rendering/legible-colours.json holds what both must answer.
const unitLuminance = ({ red, green, blue }) => {
  const linear = (value) => (value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4));
  return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue);
};
const unitContrast = (first, second) => {
  const a = unitLuminance(first), b = unitLuminance(second);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
};
function unitHsl({ red, green, blue }) {
  const high = Math.max(red, green, blue), low = Math.min(red, green, blue), lightness = (high + low) / 2;
  if (!(high > low)) return { hue: 0, saturation: 0, lightness };
  const spread = high - low;
  const saturation = lightness > 0.5 ? spread / (2 - high - low) : spread / (high + low);
  let hue;
  if (high === red) hue = (green - blue) / spread + (green < blue ? 6 : 0);
  else if (high === green) hue = (blue - red) / spread + 2;
  else hue = (red - green) / spread + 4;
  return { hue: hue / 6, saturation, lightness };
}
function unitRgb(hue, saturation, lightness) {
  const limit = (value) => Math.min(Math.max(value, 0), 1);
  if (!(saturation > 0)) return { red: limit(lightness), green: limit(lightness), blue: limit(lightness) };
  const q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation;
  const p = 2 * lightness - q;
  const channel = (shifted) => {
    let t = shifted;
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return { red: limit(channel(hue + 1 / 3)), green: limit(channel(hue)), blue: limit(channel(hue - 1 / 3)) };
}

/**
 * A picked text colour made readable on one background, exactly as the editor does it: kept as it is
 * when it already has `minimum` contrast; otherwise its lightness moves in steps of 0.01, hue and
 * saturation kept, up on a dark background (luminance under 0.18) and down on a light one, to the
 * first step that has. Returns a hex string, or null when `color` isn't a colour.
 */
const toUnit = ({ r, g, b }) => ({ red: r / 255, green: g / 255, blue: b / 255 });
const unitHex = ({ red, green, blue }) => toHex({ r: red * 255, g: green * 255, b: blue * 255 });

function legibleUnit(start, under, minimum) {
  if (!(unitContrast(start, under) < minimum)) return start;
  const { hue, saturation, lightness: from } = unitHsl(start);
  const step = unitLuminance(under) < 0.18 ? 0.01 : -0.01;
  let lightness = from, result = start;
  for (let count = 0; count < 100; count++) {
    lightness = Math.min(Math.max(lightness + step, 0), 1);
    result = unitRgb(hue, saturation, lightness);
    if (unitContrast(result, under) >= minimum || lightness <= 0 || lightness >= 1) break;
  }
  return result;
}

export function legible(color, background, minimum = 4.5) {
  const ink = asRGB(color), ground = asRGB(background);
  if (!ink) return null;
  if (!ground) return toHex(ink);
  return unitHex(legibleUnit(toUnit(ink), toUnit(ground), minimum));
}

/** How strongly a highlight colour is washed over the page: stronger on dark themes, where a thin wash disappears. Same as the editor. */
export const washStrength = (dark) => (dark ? 0.42 : 0.3);

/** The colour a highlight makes on the page, as a hex string: the highlight washed over the background. */
export function wash(color, background, dark) {
  const tint = asRGB(color), ground = asRGB(background);
  if (!tint || !ground) return null;
  const over = toUnit(tint), under = toUnit(ground), strength = washStrength(dark);
  return unitHex({
    red: under.red + (over.red - under.red) * strength, green: under.green + (over.green - under.green) * strength,
    blue: under.blue + (over.blue - under.blue) * strength,
  });
}

/** The highlight as CSS: see-through at the wash strength, so it gives the washed colour over the page. */
export function washCss(color, dark) {
  const tint = asRGB(color);
  return tint ? `rgba(${tint.r}, ${tint.g}, ${tint.b}, ${washStrength(dark)})` : "";
}

/**
 * The colour of text on a highlight, as the editor works it out. A picked colour (`ink`) is first made
 * readable on the page, the theme's own `text` is taken as it is; either is then moved until it can be
 * read against `behind`, the washed colour from `wash()`. Returns a hex string; "" when the theme's
 * text needs no change.
 */
export function textOnWash(ink, text, page, behind, minimum = 4.5) {
  const under = asRGB(behind), ground = asRGB(page);
  const picked = ink ? asRGB(ink) : null, own = asRGB(text);
  if (!under || (!picked && !own)) return "";
  const start = picked ? (ground ? legibleUnit(toUnit(picked), toUnit(ground), minimum) : toUnit(picked)) : toUnit(own);
  const shown = legibleUnit(start, toUnit(under), minimum);
  if (!picked && shown === start) return "";
  return unitHex(shown);
}

/**
 * A text colour that reads on every one of `backgrounds`: the author's colour when it already has
 * `minimum` contrast, otherwise the same hue made lighter (on dark) or darker (on light) by the least
 * that reaches it. Returns a hex string, or null when `color` isn't a colour.
 */
export function readableTextColor(color, backgrounds, minimum = 4.5) {
  const ink = asRGB(color);
  const grounds = (Array.isArray(backgrounds) ? backgrounds : [backgrounds]).map(asRGB).filter(Boolean);
  if (!ink) return null;
  if (!grounds.length) return toHex(ink);
  const worst = (candidate) => Math.min(...grounds.map((ground) => contrast(candidate, ground)));
  if (worst(ink) >= minimum) return toHex(ink);
  const { h, s, l } = rgbToHsl(ink);
  const dark = grounds.reduce((sum, ground) => sum + luminance(ground), 0) / grounds.length < 0.4;
  const at = (lightness) => hslToRgb(h, s, lightness);
  // Walk lightness toward the far end until it passes, then settle on the nearest lightness that does.
  let low = l, high = dark ? 1 : 0;
  if (worst(at(high)) < minimum) return toHex(at(high));
  for (let step = 0; step < 24; step++) {
    const middle = (low + high) / 2;
    if (worst(at(middle)) >= minimum) high = middle; else low = middle;
  }
  return toHex(at(high));
}

/** Syntax colours before a theme adjusts them: one set for light themes, one for dark. Same values as render.css. */
export const CODE_TOKENS = {
  light: { keyword: "#a2389b", string: "#1b7a4e", number: "#a35c00", title: "#2a5bd0", type: "#0f7c8c" },
  dark: { keyword: "#e08bd8", string: "#7fd3a4", number: "#e8b46a", title: "#8fb0ff", type: "#6fcfdc" },
};

/**
 * The syntax colours for one theme, as CSS variables: each base colour, moved just far enough (hue kept)
 * to have 4.5:1 against the theme's code background. Comments, and the green and red of a diff, come from
 * the theme's own muted, success and danger colours; comments need 3.5:1.
 */
export function codeTokenColors({ codeBackground, dark, muted, success, danger }) {
  const ground = asRGB(codeBackground);
  if (!ground) return {};
  const base = dark ? CODE_TOKENS.dark : CODE_TOKENS.light;
  const result = {};
  for (const [name, value] of Object.entries(base)) result[`--perch-code-${name}`] = readableTextColor(value, ground, 4.5);
  if (asRGB(muted)) result["--perch-code-comment"] = readableTextColor(muted, ground, 3.5);
  if (asRGB(success)) result["--perch-code-added"] = readableTextColor(success, ground, 4.5);
  if (asRGB(danger)) result["--perch-code-removed"] = readableTextColor(danger, ground, 4.5);
  return result;
}

const COLOR_VALUE = /^(?:#[0-9a-f]{3,8}|rgba?\([\d.%,\s/]+\)|hsla?\([\d.%,\s/deg-]+\)|[a-z]{3,24})$/i;
const STYLE_RULES = {
  color: (value) => (parseColor(value) ? value : null),
  "background-color": (value) => (parseColor(value) ? value : null),
  "font-size": (value) => {
    const match = /^(\d*\.?\d+)em$/.exec(value);
    return match && Number(match[1]) >= 0.7 && Number(match[1]) <= 2 ? `${Number(match[1])}em` : null;
  },
  "text-align": (value) => (/^(left|center|right)$/.test(value) ? value : null),
  "font-weight": (value) => (/^(normal|bold|bolder|lighter|[1-9]00)$/.test(value) ? value : null),
  "font-style": (value) => (/^(normal|italic|oblique)$/.test(value) ? value : null),
  "text-decoration": (value) => (/^(underline|line-through|underline line-through|line-through underline)$/.test(value) ? value : null),
};

/**
 * Rebuilds an inline `style` from the few declarations notes may use: color, background-color,
 * font-size (0.7em to 2em), text-align, font-weight, font-style and text-decoration. Every other
 * property, and any value that isn't plainly one of the expected kinds, is dropped: no url(), var(),
 * expression(), !important, escapes, comments or at-rules get through. Returns "" when nothing is left.
 */
export function cleanStyle(style) {
  if (typeof style !== "string" || style.length > 2000) return "";
  const kept = new Map();
  for (const declaration of style.split(";")) {
    const colon = declaration.indexOf(":");
    if (colon < 0) continue;
    const property = declaration.slice(0, colon).trim().toLowerCase();
    const value = declaration.slice(colon + 1).trim().toLowerCase().replace(/\s+/g, " ");
    if (!Object.prototype.hasOwnProperty.call(STYLE_RULES, property)) continue;
    if (/[\\"'<>{}@!]|\/\*|url|var|expression|calc|env|attr/.test(value)) continue;
    if ((property === "color" || property === "background-color") && !COLOR_VALUE.test(value)) continue;
    const clean = STYLE_RULES[property](value);
    if (clean) kept.set(property, clean);
  }
  return [...kept].map(([property, value]) => `${property}: ${value}`).join("; ");
}
