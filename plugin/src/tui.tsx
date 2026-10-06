import type { TuiPlugin, TuiPluginApi } from "@opencode-ai/plugin/tui"
import { RGBA, TextAttributes } from "@opentui/core"
import path from "path"
import { For, type JSX } from "solid-js"
import { logo } from "./logo"

/**
 * TUI half of ckode: the logo, the brand theme and the terminal title.
 * Everything here goes through public plugin API except the title, which
 * OpenCode hard-codes; see retitle().
 */
const tui: TuiPlugin = async (api) => {
  await api.theme.install(path.join(import.meta.dir, "..", "themes", "ckode.json"))
  // Only replace the stock default, so a theme the user picked themselves survives.
  if (api.theme.selected === "opencode") api.theme.set("ckode")

  api.slots.register({
    slots: {
      home_logo: () => <Logo api={api} />,
    },
  })
  retitle(api)
}

export default { id: "ckode.brand", tui }

/**
 * OpenCode sets the terminal title to a fixed "OpenCode" / "OC | <session>"
 * with no hook to change it, so this rewrites the brand part of whatever the
 * host sets. It is a patch on a live object: if upstream renames the method it
 * does nothing, and it never changes the session part of the title.
 */
function retitle(api: TuiPluginApi) {
  const renderer = api.renderer
  const original = renderer.setTerminalTitle.bind(renderer)
  const rebrand = (title: string) => title.replace(/^OpenCode$/, "ckode").replace(/^OC \| /, "ckode | ")
  renderer.setTerminalTitle = (title: string) => original(rebrand(title))
  // The host may have titled the terminal before this plugin loaded.
  if (api.route.current.name === "home") original("ckode")
  api.lifecycle.onDispose(() => {
    renderer.setTerminalTitle = original
  })
}

function Logo(props: { api: TuiPluginApi }) {
  const theme = () => props.api.theme.current
  return (
    <box flexDirection="row" gap={2}>
      <box>
        <For each={logo.left}>
          {(line, index) => (
            <box flexDirection="row" gap={1}>
              <box flexDirection="row">{glyphs(line, theme().textMuted, theme().background, false)}</box>
              <box flexDirection="row">{glyphs(logo.right[index()], theme().text, theme().background, true)}</box>
            </box>
          )}
        </For>
      </box>
    </box>
  )
}

/** Renders the glyph vocabulary documented in logo.ts. */
function glyphs(line: string, fg: RGBA, background: RGBA, bold: boolean): JSX.Element[] {
  const shadow = blend(background, fg, 0.25)
  const attributes = bold ? TextAttributes.BOLD : undefined
  const cell = (char: string, color: RGBA, bg?: RGBA) => (
    <text fg={color} bg={bg} attributes={attributes} selectable={false}>
      {char}
    </text>
  )
  return Array.from(line).map((char) => {
    if (char === "_") return cell(" ", fg, shadow)
    if (char === "^") return cell("▀", fg, shadow)
    if (char === "~") return cell("▀", shadow)
    if (char === ",") return cell("▄", shadow)
    return cell(char, fg)
  })
}

function blend(from: RGBA, to: RGBA, amount: number) {
  return RGBA.fromValues(
    from.r + (to.r - from.r) * amount,
    from.g + (to.g - from.g) * amount,
    from.b + (to.b - from.b) * amount,
    1,
  )
}
