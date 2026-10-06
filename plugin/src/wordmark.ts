// The ckode wordmark, in the same two-tone style as OpenCode's own logo, drawn
// for any title so the installer's --title can rebrand it.
//
// `left` renders muted and `right` renders bold (see tui.tsx). A title with
// several words splits after the first word; a single word splits in the
// middle, so "ckode" is "ck" + "ode", the treatment upstream gives
// "open" + "code".
//
// Lowercase letters sit on rows 1-3 and only ascenders (`b d f h k l t`) reach
// into row 0; digits are full height. Capitals are drawn as lowercase. A half
// block ▀ at the bottom puts a letter's baseline at the middle of row 3.
//
// Glyph vocabulary, interpreted by glyphs() in tui.tsx:
//   █ ▀ ▄  literal blocks
//   _      space on a shadow ground, a letter's inner counter
//   ^      ▀ in the foreground on a shadow ground, a crossbar
//   ~      ▀ in shadow, an open bottom
//   ,      ▄ in shadow

export const DEFAULT_TITLE = "ckode"
export const MAX_TITLE = 24
/** Wider than this and the wordmark would not fit a terminal, so the title is shown as plain text. */
export const MAX_WIDTH = 64

const FONT: Record<string, string[]> = {
  a: ["     ", "▄▀▀▀▄", "█▀▀▀█", "▀   ▀"],
  b: ["▄    ", "█▀▀▀▄", "█___█", "▀▀▀▀▀"],
  c: ["     ", "█▀▀▀▀", "█____", "▀▀▀▀▀"],
  d: ["    ▄", "█▀▀▀█", "█___█", "▀▀▀▀▀"],
  e: ["     ", "█▀▀▀█", "█^^^^", "▀▀▀▀▀"],
  f: ["▄▀▀▀", "█▀▀ ", "█   ", "▀   "],
  g: ["     ", "█▀▀▀█", "▀▀▀▀█", "▀▀▀▀▀"],
  h: ["▄    ", "█▀▀▀▄", "█   █", "▀   ▀"],
  i: ["▀", "█", "█", "▀"],
  j: ["  ▀", "  █", "  █", "▀▀▀"],
  k: ["     ", "█ ▄▀▀", "██▀  ", "█ ▀▄▄"],
  l: ["▄", "█", "█", "▀"],
  m: ["       ", "█▀▀█▀▀█", "█  █  █", "▀  ▀  ▀"],
  n: ["     ", "█▀▀▀▄", "█   █", "▀   ▀"],
  o: ["     ", "█▀▀▀█", "█___█", "▀▀▀▀▀"],
  p: ["     ", "█▀▀▀█", "█▄▄▄▀", "█    "],
  q: ["     ", "█▀▀▀█", "▀▄▄▄█", "    █"],
  r: ["    ", "█▀▀▀", "█   ", "▀   "],
  s: ["     ", "█▀▀▀▀", "▀▀▀▀█", "▀▀▀▀▀"],
  t: ["▄   ", "█▀▀▀", "█   ", "▀▀▀▀"],
  u: ["     ", "█   █", "█   █", "▀▀▀▀▀"],
  v: ["     ", "█   █", "▀▄ ▄▀", "  ▀  "],
  w: ["       ", "█  █  █", "█  █  █", "▀▄▀ ▀▄▀"],
  x: ["     ", "▀▄ ▄▀", "  █  ", "▄▀ ▀▄"],
  y: ["     ", "█   █", "▀▄▄▄█", "▄▄▄▄▀"],
  z: ["     ", "▀▀▀▀█", " ▄▀  ", "█▀▀▀▀"],
  "0": ["█▀▀▀█", "█   █", "█   █", "▀▀▀▀▀"],
  "1": ["▄█ ", " █ ", " █ ", "▀▀▀"],
  "2": ["█▀▀▀█", "  ▄▄▀", "▄▀   ", "▀▀▀▀▀"],
  "3": ["▀▀▀▀█", "  ▀▀▄", "    █", "▀▀▀▀▀"],
  "4": ["█   █", "▀▀▀▀█", "    █", "    ▀"],
  "5": ["█▀▀▀▀", "▀▀▀▀▄", "    █", "▀▀▀▀▀"],
  "6": ["█▀▀▀▀", "█▀▀▀▄", "█   █", "▀▀▀▀▀"],
  "7": ["▀▀▀▀█", "   ▄▀", "  █  ", "  ▀  "],
  "8": ["█▀▀▀█", "▄▀▀▀▄", "█   █", "▀▀▀▀▀"],
  "9": ["█▀▀▀█", "▀▀▀▀█", "    █", "▀▀▀▀▀"],
  ".": [" ", " ", " ", "▀"],
  "-": ["   ", "   ", "▄▄▄", "   "],
  _: ["    ", "    ", "    ", "▄▄▄▄"],
  " ": ["   ", "   ", "   ", "   "],
}

/**
 * The title as the user typed it, or the default when it is empty. Only letters,
 * digits, space, `.`, `-` and `_` are allowed so it is safe to store in a shell
 * or batch settings file; anything else makes the whole title invalid.
 */
export function parseTitle(raw: string | undefined): string | undefined {
  const title = (raw ?? "").trim().replace(/\s+/g, " ")
  if (!title) return DEFAULT_TITLE
  if (title.length > MAX_TITLE || !/^[A-Za-z0-9 ._-]+$/.test(title)) return undefined
  return title
}

function render(text: string) {
  const glyphs = [...text.toLowerCase()].map((char) => FONT[char]).filter((glyph): glyph is string[] => !!glyph)
  return [0, 1, 2, 3].map((row) => glyphs.map((glyph) => glyph[row]).join(" "))
}

/** Splits a title into the muted and bold halves, each as four rows of glyphs. */
export function wordmark(title: string) {
  const words = title.trim().split(/\s+/)
  let left: string
  let right: string
  if (words.length > 1) {
    left = words[0]
    // The leading space makes the gap between words wider than between letters.
    right = " " + words.slice(1).join(" ")
  } else {
    const split = Math.floor(title.length / 2)
    left = title.slice(0, split)
    right = title.slice(split)
  }
  return { left: render(left), right: render(right) }
}

/** Columns the wordmark takes, including the one-column gap between its halves. */
export function wordmarkWidth(mark: { left: string[]; right: string[] }) {
  return [...mark.left[0]].length + 1 + [...mark.right[0]].length
}
