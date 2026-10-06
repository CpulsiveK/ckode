// ckode wordmark, in the same two-tone style as OpenCode's own logo.
//
// `left` renders muted and `right` renders bold (see tui.tsx), so the split is
// "ck" + "ode": the same treatment upstream gives "open" + "code".
//
// Every letter is lowercase, so they sit on rows 1-3 and only the ascenders
// (`k`, `d`) reach into row 0. A half-block ▄ in row 0 puts an ascender's top
// edge at the middle of the row, which reads as a stem rather than a full cell.
//
// Glyph vocabulary, interpreted by glyphs() in tui.tsx:
//   █ ▀ ▄  literal blocks
//   _      space on a shadow ground, a letter's inner counter
//   ^      ▀ in the foreground on a shadow ground, a crossbar
//   ~      ▀ in shadow, an open bottom
//   ,      ▄ in shadow
export const logo = {
  left: [
    "      ▄    ",
    "█▀▀▀▀ █  ▄▀",
    "█____ █▀▄  ",
    "▀▀▀▀▀ ▀  ▀▄",
  ],
  right: [
    "          ▄      ",
    "█▀▀▀█ █▀▀▀█ █▀▀▀█",
    "█___█ █___█ █^^^^",
    "▀▀▀▀▀ ▀▀▀▀▀ ▀▀▀▀▀",
  ],
}
