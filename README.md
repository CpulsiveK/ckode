# ckode

ckode is unmodified [OpenCode](https://github.com/anomalyco/opencode) (MIT), locked to one OpenAI-compatible provider that you choose (a local server such as Ollama, or a hosted gateway) and branded through OpenCode's public plugin API. This repo holds only the plugin, launcher and installer; the OpenCode binary is the official upstream release, so taking an upstream release is a version bump, not a merge.

## Install

### Windows

In PowerShell (no admin rights needed):

```powershell
irm https://github.com/CpulsiveK/ckode/releases/latest/download/install.ps1 | iex
```

Then open a new terminal (PowerShell, Command Prompt or Windows Terminal) so `ckode` is on your PATH. Needs 64-bit Windows 10 version 1803 or later.

### Linux, macOS or WSL

```bash
curl -fsSL https://github.com/CpulsiveK/ckode/releases/latest/download/install.sh | bash
```

Then open a new terminal so `ckode` is on your PATH.

### Make it your own

Pass a title when you install and anyone can rebrand ckode as theirs. The title is the name shown in the home-screen logo, the terminal title, `--version`, the provider menu and the installer messages:

```bash
curl -fsSL https://github.com/CpulsiveK/ckode/releases/latest/download/install.sh | bash -s -- --title "My Agent"
```

```powershell
& ([scriptblock]::Create((irm https://github.com/CpulsiveK/ckode/releases/latest/download/install.ps1))) -Title "My Agent"
```

(`CKODE_TITLE` works too, for installs where you can't pass a flag.) A title is up to 24 letters, digits, spaces, dots, hyphens and underscores, and is drawn as a block-letter wordmark in the same two-tone style as the default, split after the first word (or in the middle of a one-word title). Titles too long to fit the terminal are shown as plain bold text. The command you type is still `ckode`. Re-running the installer, or `ckode upgrade`, keeps your title unless you pass a new one.

## Use

Start ckode in the project you want to work on:

```bash
cd ~/projects/my-app
ckode
```

On Windows, the same in PowerShell, Command Prompt or Windows Terminal:

```powershell
cd $HOME\projects\my-app
ckode
```

By default ckode uses OpenCode's free models, with nothing to set up. Each time you start it in a terminal it shows a provider menu, and the default is marked:

```
ckode  choose a provider

  ● 1) opencode  free models  (default)
    2) ollama  http://localhost:11434/v1
    a) add a provider
    r) remove a provider

Select [1]:
```

Press Enter to keep the default. To use another provider, type `a` and enter:

- **Name**, such as `ollama`, `lmstudio`, `openai`, `anthropic` or `openrouter` (any name works; these suggest a URL)
- **URL** of its OpenAI-compatible API (a bare `host:port` becomes `host:port/v1`)
- **API key**, typed hidden. Press Enter to skip it for servers that need none, such as a local Ollama.

Providers are saved in `~/.ckode/providers` (on Windows, `%USERPROFILE%\.ckode\providers`), readable only by you on Linux and macOS, and appear in the menu from then on. The free OpenCode models stay available whichever provider you pick, and ckode lists whatever models the chosen server reports. To pick a provider for one run without the menu, set `CKODE_BASE_URL` (plus `CKODE_API_KEY` and `CKODE_PROVIDER_NAME` if needed). Non-interactive commands such as `ckode run` never show the menu.

| Command | What it does |
|---|---|
| `ckode` | Opens ckode in the current directory |
| `ckode <dir>` | Opens ckode in another directory |
| `ckode run "<prompt>"` | Runs one prompt without opening the interface |
| `ckode upgrade` | Updates to the latest ckode release, keeping your saved providers |
| `ckode --version` | Shows the ckode and OpenCode versions |
| `ckode connect` | Adds a provider without opening the menu |

Every other `opencode` command and flag works the same through `ckode`.

If no models show up, or you see "No provider selected", check that the server is reachable (and, for a hosted gateway, that you are on any VPN it needs and that your key is valid), then look at `~/.cache/ckode/plugin.log` (on Windows, `%USERPROFILE%\.cache\ckode\plugin.log`).

## Uninstall

Removing `~/.ckode` also removes your saved providers and keys.

On Windows, in PowerShell:

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.ckode", "$env:USERPROFILE\.cache\ckode"
```

Then remove `%USERPROFILE%\.ckode\bin` from your user `Path` (Start → "Edit environment variables for your account").

On Linux, macOS or WSL:

```bash
rm -rf ~/.ckode ~/.cache/ckode
```

After that, delete the `# ckode` PATH line the installer added to `~/.bashrc`, `~/.zshrc` or `~/.config/fish/config.fish` (or the `~/.local/bin/ckode` link, if that is where it went).

## Pieces

Everything is installed into `~/.ckode` (`%USERPROFILE%\.ckode` on Windows; `CKODE_HOME` overrides). From a checkout, `./install.sh` (or `.\install.ps1` on Windows) installs the files beside it instead of downloading a release.

| Path | What it does |
|---|---|
| `install.sh` | Downloads the pinned OpenCode release from upstream GitHub, installs the plugin and launcher into `~/.ckode`, adds `ckode` to PATH |
| `install.ps1` | The same for Windows (Windows PowerShell 5.1); adds `bin` to the user `Path` |
| `script/release.sh` | Builds the release assets: stamped `install.sh` and `install.ps1`, `ckode-bundle.tar.gz`, `SHA256SUMS` |
| `launcher/ckode` | Runs the pinned binary with the plugin injected via `OPENCODE_CONFIG_CONTENT` / `OPENCODE_TUI_CONFIG`; shows the provider menu on interactive launches |
| `launcher/ckode.cmd`, `launcher/ckode-menu.ps1` | The same for Windows: a batch file so it runs under the default execution policy, and the provider menu as a PowerShell script it runs with `-ExecutionPolicy Bypass` |
| `plugin/src/server.ts` | `config` hook: registers the configured provider, fills its models from the server's `/models`, forces `enabled_providers: ["ckode", "opencode"]` (the second is OpenCode's free models) and `autoupdate: false`. `auth` hook: API-key login |
| `plugin/src/gateway.ts` | `/v1/models` + `/v1/model/info`: per-key model scoping, limits, per-million pricing, mode filtering |
| `plugin/src/tui.tsx` | `home_logo` slot (wordmark), brand theme, terminal title |
| `plugin/src/wordmark.ts` | The block-letter font and the title rules behind `--title` |

## Releasing

The install one-liner downloads from the latest GitHub release, so it returns 404 until at least one release exists. To publish one, tag `main` and push the tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Use the next version for each later release. `.github/workflows/release.yml` tests the plugin, runs `script/release.sh` to stamp `install.sh` with that release's URLs and pack `ckode-bundle.tar.gz`, smoke-tests the installers on Linux and Windows, and publishes the assets with `SHA256SUMS`.

To take a new upstream OpenCode release: install it with `./install.sh --version <new>`, run the evaluation set, then change `OPENCODE_VERSION` in `install.sh` and `$OpenCodeVersion` in `install.ps1` (CI fails if they differ) and tag a release. The contract with upstream is the plugin API (`@opencode-ai/plugin`), the `config`/`auth` hooks, the `home_logo` slot, and the `OPENCODE_CONFIG_CONTENT` / `OPENCODE_TUI_CONFIG` variables.

## Develop

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup on Windows, Linux and macOS, the contribution workflow, and how releases work. Quick start:

```bash
cd plugin
bun install
bun test
bunx tsc -p .
```

Try the plugin against upstream source without installing: in a clone of [anomalyco/opencode](https://github.com/anomalyco/opencode), from `packages/opencode`, run `bun dev` with `OPENCODE_CONFIG_CONTENT='{"plugin":[["file://<path-to-this-repo>/plugin",{"baseURL":"http://localhost:11434/v1"}]]}'` and `OPENCODE_TUI_CONFIG` pointing at a `tui.json` containing `{"plugin":["file://<path-to-this-repo>/plugin"]}`. Plugin diagnostics go to `~/.cache/ckode/plugin.log`.

## Known limits

- The sidebar's `• OpenCode <version>` label, the exit-screen wordmark and `--help` text still say OpenCode; there is no slot for them.
- The terminal title is rewritten by wrapping the renderer's `setTerminalTitle`, not a public hook; if upstream renames it the title reverts to "OpenCode" and nothing breaks.
- `supports_reasoning` from the gateway is not mapped yet, so models get no reasoning-effort variants.
- Windows on ARM installs the arm64 OpenCode build, which has not been tested.
