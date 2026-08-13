'use strict';

/* Accent re-tinting.

   The CRT look isn't one green — it's a family of ~14 tokens (bright headings,
   the text ramp, dim labels, hairlines, panel backgrounds) whose hues sit
   between 116° and 149°. Forcing them all onto a single hue would flatten that,
   so instead we rotate the whole family by a delta and scale its saturation,
   keeping each token's own lightness and its hue offset from the base.

   Consequences that matter:
     - picking the default green is a no-op, so the shipped look is exact
     - lightness never moves, so contrast ratios survive any hue
     - the A/B/C/D answer palette in common.js is deliberately untouched: those
       four colours are a semantic set paired with shapes and letters, and
       rotating them would let two options collide. */

const ACCENT_DEFAULT = '#56ff8a';

// Every token derived from the base green, with the literal default it must
// reproduce when the accent is unchanged.
const ACCENT_TOKENS = {
  '--c-green': '#56ff8a',
  '--c-text-bright': '#eaffe9',
  '--c-text': '#c9ffd9',
  '--c-text-soft': '#9ef7ba',
  '--c-dim': '#2f8a4d',
  '--c-green-tint': '#c9ffd9',
  '--line': '#1e4d30',
  '--line-soft': '#123322',
  '--bg-deep': '#030906',
  '--bg': '#04080a',
  '--bg-panel': '#04110a',
  '--bg-input': '#050f08',
  '--bg-btn': '#0a1f12',
  '--bg-btn-primary': '#123f22'
};

// Tokens consumed as "r, g, b" triplets inside rgba() glows.
const ACCENT_RGB_TOKENS = {
  '--c-green-rgb': '#56ff8a',
  '--c-glow-rgb': '#7dff9e'
};

function hexToRgb(hex) {
  const h = String(hex || '').trim().replace('#', '');
  const full = h.length === 3 ? h.split('').map(c => c + c).join('') : h;
  const n = parseInt(full, 16);
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

function rgbToHex({ r, g, b }) {
  const c = v => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, '0');
  return '#' + c(r) + c(g) + c(b);
}

function rgbToHsl({ r, g, b }) {
  const R = r / 255, G = g / 255, B = b / 255;
  const max = Math.max(R, G, B), min = Math.min(R, G, B);
  const l = (max + min) / 2;
  const d = max - min;
  if (!d) return { h: 0, s: 0, l };
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === R) h = ((G - B) / d + (G < B ? 6 : 0)) / 6;
  else if (max === G) h = ((B - R) / d + 2) / 6;
  else h = ((R - G) / d + 4) / 6;
  return { h: h * 360, s, l };
}

function hslToRgb({ h, s, l }) {
  const H = (((h % 360) + 360) % 360) / 360;
  if (!s) { const v = l * 255; return { r: v, g: v, b: v }; }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const chan = t => {
    let T = t;
    if (T < 0) T += 1;
    if (T > 1) T -= 1;
    if (T < 1 / 6) return p + (q - p) * 6 * T;
    if (T < 1 / 2) return q;
    if (T < 2 / 3) return p + (q - p) * (2 / 3 - T) * 6;
    return p;
  };
  return { r: chan(H + 1 / 3) * 255, g: chan(H) * 255, b: chan(H - 1 / 3) * 255 };
}

const isHex = v => /^#?[0-9a-fA-F]{6}$/.test(String(v || '').trim()) || /^#?[0-9a-fA-F]{3}$/.test(String(v || '').trim());

/* Rotate one token to match the picked accent.
   `deltaH` shifts hue; `satScale` re-weights saturation relative to the fully
   saturated default; lightness is left alone on purpose. */
function shiftHex(hex, deltaH, satScale) {
  const hsl = rgbToHsl(hexToRgb(hex));
  return rgbToHex(hslToRgb({
    h: hsl.h + deltaH,
    s: Math.min(1, Math.max(0, hsl.s * satScale)),
    l: hsl.l
  }));
}

// → { '--c-green': '#…', '--c-green-rgb': 'r, g, b', … }
function accentVars(accent) {
  const picked = isHex(accent) ? accent : ACCENT_DEFAULT;
  const base = rgbToHsl(hexToRgb(ACCENT_DEFAULT));
  const target = rgbToHsl(hexToRgb(picked));
  const deltaH = target.h - base.h;
  // A fully saturated pick leaves the ramp untouched; a muted pick mutes it.
  const satScale = base.s ? target.s / base.s : 1;

  const vars = {};
  // Exact short-circuit for the shipped palette: hex -> hsl -> hex can drift a
  // digit through rounding, and the default must reproduce byte-for-byte.
  if (deltaH === 0 && satScale === 1) {
    for (const [name, hex] of Object.entries(ACCENT_TOKENS)) vars[name] = hex;
    for (const [name, hex] of Object.entries(ACCENT_RGB_TOKENS)) {
      const { r, g, b } = hexToRgb(hex);
      vars[name] = `${r}, ${g}, ${b}`;
    }
    return vars;
  }

  for (const [name, hex] of Object.entries(ACCENT_TOKENS)) {
    vars[name] = shiftHex(hex, deltaH, satScale);
  }
  for (const [name, hex] of Object.entries(ACCENT_RGB_TOKENS)) {
    const { r, g, b } = hexToRgb(shiftHex(hex, deltaH, satScale));
    vars[name] = `${Math.round(r)}, ${Math.round(g)}, ${Math.round(b)}`;
  }
  return vars;
}

// Paints the accent onto :root. Called on first sync and whenever the operator
// changes it; passing null/garbage restores the default green.
function applyAccent(accent, root) {
  const el = root || (typeof document !== 'undefined' ? document.documentElement : null);
  if (!el || !el.style) return null;
  const vars = accentVars(accent);
  for (const [name, value] of Object.entries(vars)) el.style.setProperty(name, value);
  return vars;
}
