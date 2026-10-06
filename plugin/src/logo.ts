// ckode logo: a two-tone "CK" monogram.
//
// `left` renders in brand orange and `right` in the theme text colour, both bold (see tui.tsx). The C carries a
// shadow counter and the K is drawn with half-blocks so its diagonals stay sharp.
//
// Glyph vocabulary, interpreted by glyphs() in tui.tsx:
//   █ ▀ ▄  literal blocks
//   _      space on a shadow ground, a letter's inner counter
//   ^      ▀ in the foreground on a shadow ground
//   ~      ▀ in shadow
//   ,      ▄ in shadow
export const logo = {
  left: [
    "▄▄▄▄▄▄▄",
    "█______",
    "█______",
    "▀▀▀▀▀▀▀",
  ],
  right: [
    "█   ▄▀",
    "█ ▄▀  ",
    "█▀▄   ",
    "█  ▀▄ ",
  ],
}

// ckode brand orange.
export const brand = "#f97316"
