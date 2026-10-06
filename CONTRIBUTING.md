# Contributing to ckode

This document covers everything a developer needs to start working on ckode: what it is, the tools and access you need, how to build and test it on Windows, Linux or macOS, and how changes get from your machine into a release.

> **Status:** v0.2.0 is released.
> - **Windows 10/11 (64-bit):** native support, tested on Windows 11 and on GitHub's Windows runners. WSL also works.
> - **Linux and WSL:** tested.
> - **macOS:** expected to work, but not yet tested.
> - **Windows on ARM:** gets the arm64 OpenCode build, but not yet tested.

---

## 1. What ckode is

ckode is a terminal coding agent. It is [OpenCode](https://github.com/anomalyco/opencode) (open source, MIT licence), locked to the one OpenAI-compatible server the user picks at first launch (a local Ollama, or a hosted OpenAI-compatible gateway) and branded as ckode. The team uses it instead of paying per seat for a third-party agent.

**We do not fork OpenCode.** Users get the official, unmodified OpenCode release for their platform. Everything ckode-specific is in a few small pieces that this repo ships:

| Piece | Windows | Linux / macOS / WSL | What it does |
|---|---|---|---|
| **Plugin** | `plugin/` | `plugin/` (same code) | Uses OpenCode's public plugin API. It registers the `ckode` provider, loads the model list from the gateway, blocks every other provider, and adds the ckode logo, theme and terminal title. |
| **Launcher** | `launcher/ckode.cmd` | `launcher/ckode` | The `ckode` command. It runs the pinned OpenCode binary with the plugin loaded, shows the provider menu, and handles `ckode upgrade` and `ckode --version`. |
| **Installer** | `install.ps1` | `install.sh` | Downloads the pinned OpenCode release from GitHub, installs the plugin and launcher into `~/.ckode`, and puts `ckode` on the user's PATH. |

The two launchers behave the same, and so do the two installers. **A change to one must be made to its twin in the same PR.**

Because nothing in OpenCode is modified, **taking an upstream OpenCode update means changing one version number** in each installer (`OPENCODE_VERSION` in `install.sh` and `$OpenCodeVersion` in `install.ps1`), not merging a fork. CI fails if the two pins differ.

### How the pieces fit together

```
ckode (launcher: ckode.cmd on Windows, bash elsewhere)
  │  reads ~/.ckode/settings(.cmd): versions, installer URL
  │  shows the provider menu (default: OpenCode free models); saved providers are in ~/.ckode/providers
  │  sets OPENCODE_CONFIG_CONTENT  → loads plugin/src/server.ts
  │  sets OPENCODE_TUI_CONFIG      → loads plugin/src/tui.tsx
  ▼
opencode / opencode.exe (pinned upstream binary, unmodified)
  │  config hook → plugin injects the "ckode" provider and models,
  │                forces enabled_providers=["ckode","opencode"], autoupdate=false
  │  auth hook   → API-key login for "ckode"
  ▼
OpenAI-compatible server (local or hosted)
     /v1/models       models this key may use
     /v1/model/info   limits, prices, mode, vision/PDF support
```

---

## 2. Repositories and links

| What | Link | Notes |
|---|---|---|
| **ckode** (this project) | https://github.com/CpulsiveK/ckode | Public. Plugin, launchers, installers, CI. |
| Releases | https://github.com/CpulsiveK/ckode/releases | `install.ps1`, `install.sh`, the bundle and `SHA256SUMS` are published here |
| CI runs | https://github.com/CpulsiveK/ckode/actions | `test` runs on every push to `main` and every PR (Linux and Windows); `release` runs on `v*` tags |
| **OpenCode** (upstream) | https://github.com/anomalyco/opencode | Read its source to check how plugin hooks behave. We don't change it. |
| OpenCode releases | https://github.com/anomalyco/opencode/releases | The installers download the pinned binary from here (`opencode-windows-x64.zip`, `opencode-linux-x64.tar.gz`, …) |

---

## 3. What you need

### 3.1 Access

| Access | Why | How to get it |
|---|---|---|
| GitHub account with access to the ckode repo | To open PRs | Ask the maintainer (see section 16) to add you as a collaborator, or fork the repo |
| A model server | Something for ckode to talk to | A local Ollama (no key), or a hosted gateway URL and API key from its operator |

### 3.2 Tools on Windows

| Tool | Version | Needed for | Install |
|---|---|---|---|
| Windows 10 (1803 or later) or Windows 11, 64-bit | — | Everything | — |
| Windows PowerShell | 5.1 (built in) | Running `install.ps1` | Already installed. Test with **Windows PowerShell 5.1**, which every user has, not only PowerShell 7 (`pwsh`). |
| `curl.exe`, `tar.exe` | built in | The installer uses them | Already installed on Windows 10 1803 and later |
| Git for Windows | any recent | Source control | [git-scm.com/download/win](https://git-scm.com/download/win), or `winget install Git.Git` |
| **Bun** | **1.4.2** (same as CI) | Plugin tests and typecheck | In PowerShell: `iex "& {$(irm https://bun.sh/install.ps1)} -Version 1.4.2"` ([bun.sh](https://bun.sh)) |
| GitHub CLI `gh` | any recent | Opening PRs and reading CI logs (optional but recommended) | `winget install GitHub.cli`, then `gh auth login` |
| Windows Terminal | any | Running the TUI comfortably | Built into Windows 11; `winget install Microsoft.WindowsTerminal` on Windows 10 |
| An editor with TypeScript support | — | Development | VS Code, WebStorm, etc. |

### 3.3 Tools on Linux, macOS or WSL

| Tool | Version | Needed for | Install |
|---|---|---|---|
| Git | any recent | Source control | [git-scm.com/downloads](https://git-scm.com/downloads) |
| Bash, curl, tar | standard | Installer and launcher | Already present |
| **Bun** | **1.4.2** (same as CI) | Plugin tests and typecheck | `curl -fsSL https://bun.sh/install \| bash -s bun-v1.4.2` |
| GitHub CLI `gh` | any recent | Optional, recommended | [cli.github.com](https://cli.github.com), then `gh auth login` |
| tmux | any | Testing the TUI from a script (optional) | `sudo apt install tmux` / `brew install tmux` |

You do **not** need Node.js, npm or a local OpenCode install on any platform. The plugin has no runtime dependencies (everything in `package.json` is a dev dependency), and OpenCode compiles the `.tsx` TUI plugin itself at runtime.

> **Use Bun 1.4.2 exactly.** `bun.lock` was written by 1.4.2, and older Bun versions such as 1.3.x cannot read it, so `bun install --frozen-lockfile` fails. If you upgrade Bun, update `bun-version` in **every** job in both workflow files in the same PR.

Check Bun is on your PATH:

```bash
bun --version   # should print 1.4.2
```

On Linux/macOS the installer puts Bun in `~/.bun/bin`. If `bun` isn't found, run `export PATH="$HOME/.bun/bin:$PATH"`. On Windows, open a new terminal after installing Bun.

---

## 4. Getting started

### 4.1 Clone and install dependencies

```bash
git clone git@github.com:CpulsiveK/ckode.git
cd ckode/plugin
bun install --frozen-lockfile
```

Line endings are handled by `.gitattributes`: `.cmd` and `.ps1` files are checked out with CRLF, and shell scripts with LF, on every OS. **Don't override this with `core.autocrlf` tricks.** `cmd.exe` misreads batch files that have LF-only line endings, and bash can't run scripts that have CRLF.

### 4.2 Run the checks

These are the same checks CI runs. Run them before every push.

```bash
# from plugin/ (works the same on Windows and Linux)
bun test           # unit tests
bunx tsc -p .      # typecheck
```

```bash
# from the repo root, on Linux/macOS/WSL
bash -n install.sh && bash -n launcher/ckode && bash -n script/release.sh
```

The tests start a small local stand-in gateway with `Bun.serve` that returns LiteLLM-shaped responses. They need **no VPN, no key and no network**. CI runs them on both Linux and Windows, because timing differences between the two have already caught one real bug.

### 4.3 Run your working copy end to end on Windows

Install from your checkout into a **separate, throwaway location**, so your real install and your PATH stay untouched. In PowerShell, from the repo root:

```powershell
$env:CKODE_HOME = "$env:USERPROFILE\ckode-dev"
.\install.ps1 -NoModifyPath
& "$env:CKODE_HOME\bin\ckode.cmd" --version    # ckode (local) (OpenCode 1.18.33)
```

If PowerShell refuses to run the script ("running scripts is disabled on this system"), run it once with `powershell -ExecutionPolicy Bypass -File .\install.ps1 -NoModifyPath`. Users never hit this, because they run the installer through `irm | iex`.

Then, on the VPN, from a project folder:

```powershell
& "$env:CKODE_HOME\bin\ckode.cmd"
```

- On launch it shows a provider menu; press Enter for the OpenCode free models, or add a provider (name, URL, optional key). To skip the menu, set `$env:CKODE_BASE_URL` (and `$env:CKODE_API_KEY`, `$env:CKODE_PROVIDER_NAME`). `ckode connect` adds a provider directly.
- After changing plugin or launcher code, re-run `.\install.ps1 -NoModifyPath`. It copies your files again and skips the OpenCode download because that version is already installed.
- Plugin logs are written to `%USERPROFILE%\.cache\ckode\plugin.log`. Check this first when something looks wrong.
- To test changes to PATH handling, use a VM or Windows Sandbox, not your own account. The installer writes the PATH entry to your user registry.
- When you are done, run `Remove-Item -Recurse -Force "$env:USERPROFILE\ckode-dev"` and `Remove-Item Env:CKODE_HOME`.

To test the piped one-liner form (`irm … | iex`, which can't take switches) without touching PATH, set `$env:CKODE_NO_MODIFY_PATH = "1"` first.

### 4.4 Run your working copy end to end on Linux, macOS or WSL

```bash
# from the repo root
export CKODE_HOME="$HOME/ckode-dev"
export PATH="$CKODE_HOME/bin:$PATH"   # set before installing so the installer won't edit ~/.bashrc
./install.sh
ckode --version                        # ckode (local) (OpenCode 1.18.33)
cd ~/some/project && ckode
```

The same rules apply: re-run `./install.sh` after changes, and logs go to `~/.cache/ckode/plugin.log`. When you are done, run `unset CKODE_HOME` and `rm -rf ~/ckode-dev`.

For a fully isolated run, for example to test a fresh install or the first-launch key prompt, use a temporary HOME:

```bash
scratch=$(mktemp -d)
env -i HOME="$scratch" PATH=/usr/bin:/bin TERM="$TERM" bash -c './install.sh && ~/.ckode/bin/ckode'
```

### 4.5 Testing the TUI from a script (optional, Linux/macOS/WSL)

The TUI is interactive. To check it from a script or an AI agent, run it in tmux and capture the screen:

```bash
tmux new-session -d -s ac -x 160 -y 45 "ckode"
sleep 5
tmux capture-pane -p -t ac      # print what's on screen
tmux send-keys -t ac "hello" Enter
tmux kill-session -t ac
```

There is no equivalent on Windows, so check Windows TUI changes by hand in Windows Terminal. For non-interactive checks on Windows, use `ckode models`, which lists only the configured provider's (`ckode/...`) models, and `ckode run "Reply with exactly: pong"`.

### 4.6 Running the plugin against OpenCode source (advanced)

You only need this when you are debugging OpenCode's own behaviour. Clone [anomalyco/opencode](https://github.com/anomalyco/opencode), then from `packages/opencode` run `bun dev` with:

```bash
export OPENCODE_CONFIG_CONTENT='{"plugin":[["/path/to/ckode/plugin",{"baseURL":"http://localhost:11434/v1"}]]}'
export OPENCODE_TUI_CONFIG=/path/to/tui.json   # file contents: {"plugin":["/path/to/ckode/plugin"]}
```

On Windows, use a drive path with forward slashes, for example `C:/Users/you/ckode/plugin`.

---

## 5. Repository layout

```
ckode/
├── install.ps1                Windows installer (PowerShell 5.1); $OpenCodeVersion pin at the top
├── install.sh                 Linux/macOS installer; OPENCODE_VERSION pin at the top
├── launcher/
│   ├── ckode.cmd          The `ckode` command on Windows (batch)
│   └── ckode              The `ckode` command elsewhere (bash)
├── plugin/
│   ├── package.json           Exports "./server" and "./tui" separately (see section 6, point 4)
│   ├── src/
│   │   ├── server.ts          config hook (provider + lock) and auth hook
│   │   ├── gateway.ts         /v1/models + /v1/model/info → OpenCode model entries
│   │   ├── tui.tsx            Logo slot, theme, terminal title
│   │   └── logo.ts            ckode wordmark
│   ├── themes/ckode.json  Orange theme (#f97316), derived from OpenCode's default
│   └── test/server.test.ts    Tests against a stand-in gateway
├── script/
│   └── release.sh             Builds dist/: stamped install.sh + install.ps1, bundle, SHA256SUMS
├── .github/workflows/
│   ├── test.yml               PRs and pushes to main: Linux job + Windows job
│   └── release.yml            v* tags: build → Windows smoke test → publish
├── .gitattributes             CRLF for .cmd/.ps1, LF for shell scripts
├── NOTICE                     OpenCode MIT licence and attribution
└── README.md                  User-facing install and usage
```

### Where things are installed on a user's machine

| What | Windows | Linux / macOS / WSL |
|---|---|---|
| Install directory (`CKODE_HOME` overrides) | `%USERPROFILE%\.ckode\` | `~/.ckode/` |
| Launcher | `bin\ckode.cmd` | `bin/ckode` |
| Settings | `settings.cmd` (batch `set` lines, also `PLUGIN_PATH`) | `settings` (shell variables) |
| OpenCode binary | `opencode\<version>\opencode.exe` | `opencode/<version>/opencode` |
| PATH entry | `…\.ckode\bin` added to the user `Path` in the registry | one `# ckode` line in `~/.bashrc` / `~/.zshrc` / fish config, or a `~/.local/bin` link |
| Saved key (written by OpenCode) | `%USERPROFILE%\.local\share\opencode\auth.json` | `~/.local/share/opencode/auth.json` |
| Model cache and `plugin.log` | `%USERPROFILE%\.cache\ckode\` | `~/.cache/ckode/` |

The installers keep the active OpenCode version and the one before it. To roll back, set `OPENCODE_VERSION` in the settings file to the previous version.

---

## 6. How it works: upstream behaviour we depend on

These points were worked out by reading OpenCode's source and by testing on Windows. They explain design decisions that otherwise look odd, so **read this before changing the plugin, a launcher or an installer.**

### All platforms

1. **The provider must be injected in the `config` hook.** OpenCode skips the plugin `provider.models` hook for any provider that isn't listed on models.dev, and `ckode` isn't listed.
2. **Forcing `enabled_providers` in the `config` hook is what enforces the lock.** That hook changes the same config object that both the provider service and the Connect dialog read. Even if a user's own config enables OpenAI, Anthropic or OpenRouter with real keys, they only see the configured provider's models plus OpenCode's free ones (the `opencode` provider, which offers only free models without a key). This has been verified on Linux and Windows.
3. **The TUI config comes from `OPENCODE_TUI_CONFIG`.** The TUI does not read the managed `/etc/opencode` directory. The host compiles external `.tsx` TUI plugins at runtime, so no `node_modules` is needed on the user's machine.
4. **A plugin module's default export can have `server()` or `tui()`, but not both.** That's why `package.json` has two separate exports.
5. **OpenCode can't upgrade our install itself.** `opencode upgrade` only recognises its own install locations. Upgrades go through `ckode upgrade`, which re-runs the latest installer, and `autoupdate` is forced off.
6. **A provider with no models is dropped without any error.** The user then sees "No provider selected". The usual causes are no VPN, a bad key, a dev key used against prod, or a gateway timeout. Check `plugin.log`.
7. **The model list is cached** in `~/.cache/ckode`. The cached list is served first and refreshed in the background, with a 5 second timeout, so startup never waits on the network. The refresh's error handler is attached as soon as the refresh starts. If you restructure this code, keep it that way: a gateway that fails faster than the cache read otherwise causes an unhandled rejection, and Windows triggers this reliably.
8. **The gateway model list is filtered.** Models whose `mode` isn't `chat`/`responses` are removed (for example, the Deepgram transcription models), and so are embedding models (removed by name). Prices are converted from per token to per million tokens.
9. **The terminal title is set by wrapping the renderer's `setTerminalTitle`**, not through a public hook. If upstream renames it, the title goes back to "OpenCode" and nothing else breaks.

### Windows only

10. **The plugin is referenced by a plain drive path, not a `file://` URL.** OpenCode accepts `C:/Users/…/plugin` and converts it to a URL itself. Forward slashes keep the JSON valid without escaping, and user names with spaces or parentheses need no encoding. This has been tested with a folder named `home (x)`.
11. **The launcher is a `.cmd` file, not `.ps1`.** Windows' default execution policy (`Restricted`) blocks `.ps1` scripts, while `.cmd` runs from cmd, PowerShell and Windows Terminal alike. In `ckode.cmd`, never expand a path variable inside a parenthesised `( … )` block, because a `)` in a user name ends the block early. Use one-line `if` statements and `goto` labels instead.
12. **`settings.cmd` is loaded with `call`, so `%` in values must be written as `%%`.** The installer already does this.
13. **`install.ps1` runs under `irm | iex`, so it must never call `exit`, because that closes the user's PowerShell window.** Failures `throw` instead, through the `Fail` function. Parameters are validated in code rather than with `ValidateSet`, because a `ValidateSet` error prints the whole script source when it runs from a scriptblock.
14. **In Windows PowerShell 5.1, a native tool's stderr becomes error records when output is redirected**, as in CI or logs. With `$ErrorActionPreference = "Stop"`, curl's progress bar alone would abort the install. Run `curl.exe` and `tar.exe` through `Invoke-Native`, and judge them by `$LASTEXITCODE`.
15. **Write `curl.exe`, not `curl`.** In Windows PowerShell, `curl` is an alias for `Invoke-WebRequest`.
16. **Write the user PATH through the registry.** The installer reads and writes `HKCU:\Environment` with `DoNotExpandEnvironmentNames` and keeps the `ExpandString` type. Going through `[Environment]::SetEnvironmentVariable` would expand entries such as `%USERPROFILE%\bin` and save them back as fixed paths, which breaks the user's other tools.
17. **The OpenCode download resumes when interrupted.** The archive is about 60 MB, and slow VPN or WSL links reset the connection partway. Both installers retry up to 5 times with `curl -C -`, which continues from the bytes already downloaded.

### Known gaps (no hook exists)

- The sidebar label `• OpenCode <version>`, the exit-screen wordmark and the `--help` text still say OpenCode. The plan is an upstream PR that makes product branding configurable.
- The gateway's `supports_reasoning` isn't mapped yet, so models get no reasoning-effort options.
- Windows on ARM and macOS have not been tested.

---

## 7. Contribution workflow

We use a standard GitHub flow: short-lived branches, pull requests, review, and squash merge into `main`.

### 7.1 Before you start

- Check the open issues and PRs so you don't duplicate work.
- For anything larger than a small fix, open an issue (or comment on an existing one) describing the problem and your approach, and get agreement before writing code. This matters most for anything that touches the provider lock, the installers, or upstream behaviour.

### 7.2 Branches

Branch from an up-to-date `main`:

```bash
git switch main && git pull
git switch -c feat/reasoning-variants
```

| Prefix | Use for |
|---|---|
| `feat/` | New behaviour |
| `fix/` | Bug fixes |
| `docs/` | Documentation only |
| `ci/` | Workflows and release tooling |
| `chore/` | Dependency bumps, cleanup, the OpenCode version bump |

Use short kebab-case descriptions. Never push directly to `main`.

### 7.3 Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <summary in the imperative, lower case, no full stop>

<optional body: why the change was needed, and anything a reviewer would not see from the diff>
```

Examples:

```
fix(launcher): keep the saved providers when upgrading
feat(plugin): map supports_reasoning to reasoning-effort variants
chore: bump OpenCode to 1.19.0
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `ci`, `chore`. Useful scopes: `plugin`, `launcher`, `installer`, `windows`, `release`.

Keep each commit focused on one change, and don't commit generated files (`dist/`, `node_modules/`).

### 7.4 Pull requests

1. Push your branch and open a PR against `main`:
   ```bash
   git push -u origin feat/reasoning-variants
   gh pr create --fill
   ```
2. The PR description should say:
   - **What** changed and **why** (link the issue).
   - **How you tested it**: which checks you ran, **on which OS**, and for behaviour changes, what you saw in a real `ckode` session. For TUI changes, include screenshots or `tmux capture-pane` output.
   - **Risk**: anything that affects the provider lock, the install and upgrade path, PATH handling, or existing users' installs.
3. CI must pass: both the `test` (Linux) and `windows` jobs.
4. At least **one approving review** is required. The reviewer checks correctness, that the provider lock still holds, that the twin launcher or installer was updated too, and the code standards in section 8.
5. Resolve all review comments, then **squash merge**. The squash commit message must follow the commit convention, because it becomes the history.
6. Delete the branch after merging.

### 7.5 Definition of done

- [ ] `bun test` and `bunx tsc -p .` pass locally; the `bash -n` checks pass; CI's Linux and Windows jobs pass
- [ ] Launcher or installer changes were made to **both** twins (`.cmd` + bash, `.ps1` + `.sh`)
- [ ] New behaviour has tests (plugin) or a documented manual check (launchers/installers)
- [ ] Tested end to end with an install from your checkout (sections 4.3 and 4.4) on every OS the change affects
- [ ] `README.md` is updated if user-facing commands or behaviour changed
- [ ] `CONTRIBUTING.md` (this file) is updated if the developer workflow or an upstream assumption changed
- [ ] No secrets, keys or tokens in code, tests, logs or screenshots

---

## 8. Code standards

- **Follow the existing style in each file.** Match its naming, comment density and idioms. Comments explain *why*, not what.
- **The plugin has no runtime dependencies.** Use Bun and Node built-ins only. Anything added to `package.json` must be a `devDependency` used only for types or tests. Build paths with `path.join` and never hard-code `/`, because the same plugin runs on Windows.
- **Keep OpenCode unmodified.** If something can't be done through the plugin API, the launchers or environment variables, raise it before adding a workaround. The preferred fix is an upstream PR to OpenCode.
- **TypeScript:** `strict` mode, ESM, no `any` without a comment explaining why.
- **Bash** (`install.sh`, `launcher/ckode`):
  - Start with `set -euo pipefail`.
  - Quote every expansion.
  - Stay POSIX-friendly where possible.
  - Never edit files outside `CKODE_HOME` apart from the single PATH line.
- **PowerShell** (`install.ps1`):
  - Must run on **Windows PowerShell 5.1**, so no `??`, `?:`, `&&` or other PowerShell 7-only syntax.
  - ASCII only.
  - Never call `exit`; use `Fail` to throw.
  - Run native tools through `Invoke-Native`.
  - Never touch anything outside `CKODE_HOME` apart from the user `Path` registry value.
- **Batch** (`launcher/ckode.cmd`):
  - `setlocal` at the top.
  - No path expansion inside `( … )` blocks.
  - Always quote paths (`"%AC_HOME%\…"`).
  - Pass arguments through with `%*`.
  - Exit with `exit /b`.
- **Fail with a message that tells the user what to do.** For example, "Re-run the installer" rather than a stack trace.
- **Never print, log or commit a key.** The plugin log must not contain credentials.

---

## 9. Testing standards

- **Plugin:** add tests in `plugin/test/` using `bun:test`.
  - Test against the local `Bun.serve` stand-in gateway rather than mocking `fetch`. Add a new scenario to the stand-in when the gateway response you need differs.
  - Always `await` a promise assertion (`await expect(p).rejects…`). A missing `await` passed on Linux and failed on Windows.
  - Tests must not need the VPN, a real key or network access.
- **Launchers and installers:** CI covers the basics:
  - syntax checks for the bash scripts;
  - on Windows, a checkout install, `--version`, the PATH entry, and no duplicate entry after reinstalling;
  - on both platforms, a smoke install of the stamped release.

  Anything else, test by hand in a throwaway location (sections 4.3 and 4.4) and describe what you checked in the PR.
- **Awkward Windows paths:** for changes to path handling, test with an `CKODE_HOME` (or test profile folder) whose name contains a space and parentheses, for example `C:\Temp\home (x)\.ckode`.
- **Provider lock:** any change near `server.ts`'s `config` hook must still pass the test showing that a user config enabling other providers ends up with only `ckode`.
- **Gateway flakiness:** the gateway is VPN-only and sometimes times out, especially from WSL. A timeout during manual testing is usually the network, not your change. Retry before debugging.

---

## 10. CI

| Workflow | Job | Runs on | Steps |
|---|---|---|---|
| `test.yml` | `test` | `ubuntu-latest`, every PR and push to `main` | `bun install --frozen-lockfile`, `bun test`, `tsc`, `bash -n` on all scripts, check that both installers pin the same OpenCode |
| `test.yml` | `windows` | `windows-latest` (Windows PowerShell 5.1) | `bun install`, `bun test`, `install.ps1` from the checkout, launcher `--version`, user PATH entry present and not duplicated |
| `release.yml` | `build` | `ubuntu-latest`, on `v*` tags | Tests → `script/release.sh` → Linux smoke install → upload `dist/` |
| `release.yml` | `windows` | `windows-latest` | Unpack the release bundle with Windows `tar`, install with the stamped `install.ps1`, check `ckode --version` shows the release and OpenCode versions |
| `release.yml` | `publish` | `ubuntu-latest`, after both pass | `gh release create` with `install.sh`, `install.ps1`, `ckode-bundle.tar.gz`, `SHA256SUMS` |

If CI fails, open the run on the [Actions page](https://github.com/CpulsiveK/ckode/actions), or use `gh run view --log-failed`. Full logs require being signed in to GitHub.

---

## 11. Releasing (maintainers)

ckode uses [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

| Change | Bump | Example |
|---|---|---|
| Bug fix only | PATCH | `0.2.0` → `0.2.1` |
| New feature, a new platform, or a new OpenCode version | MINOR | `0.2.1` → `0.3.0` |
| Breaking change to installs or usage | MAJOR | `1.x` → `2.0.0` |

While the major version is `0`, the project is pre-stable. Version `1.0.0` will be released once the team relies on it daily.

The ckode version is separate from the OpenCode version. `ckode --version` prints both, for example `ckode 0.2.0 (OpenCode 1.18.33)`.

To release:

```bash
git switch main && git pull
git tag v0.3.0
git push origin v0.3.0
```

Then:

1. Watch the `release` workflow on the Actions page until all three jobs (`build`, `windows`, `publish`) succeed.
2. Check the release lists `install.sh`, `install.ps1`, `ckode-bundle.tar.gz` and `SHA256SUMS`.
3. Test the real one-liners in a clean environment. On **Windows**, in PowerShell:
   ```powershell
   $env:USERPROFILE = "$env:TEMP\ckode-release-check"; $env:CKODE_NO_MODIFY_PATH = "1"
   New-Item -ItemType Directory -Force $env:USERPROFILE | Out-Null
   irm https://github.com/CpulsiveK/ckode/releases/latest/download/install.ps1 | iex
   & "$env:USERPROFILE\.ckode\bin\ckode.cmd" --version
   ```
   Run this in a **separate PowerShell window** and close it afterwards, because it changes `USERPROFILE` for that session.

   On **Linux/macOS**:
   ```bash
   scratch=$(mktemp -d)
   env -i HOME="$scratch" PATH=/usr/bin:/bin bash -c 'curl -fsSL https://github.com/CpulsiveK/ckode/releases/latest/download/install.sh | bash && ~/.ckode/bin/ckode --version'
   ```
4. Test `ckode upgrade` from the previous release on both platforms. It should keep the saved providers, skip re-downloading an OpenCode version that is already installed, and not add a second PATH entry.
5. Announce the release with a summary of the changes.

Only maintainers push tags. Don't move or delete a published tag; release a new version instead.

---

## 12. Taking an upstream OpenCode update

1. Read the OpenCode release notes for changes to the plugin API, the `config`/`auth` hooks, the `home_logo` slot, `OPENCODE_CONFIG_CONTENT` / `OPENCODE_TUI_CONFIG`, the provider and Connect dialog code, or the release asset names, such as `opencode-windows-x64.zip`.
2. Install the new version from a checkout without changing the pin.

   Windows:
   ```powershell
   $env:CKODE_HOME = "$env:USERPROFILE\ckode-eval"; .\install.ps1 -Version <new> -NoModifyPath
   ```

   Linux/macOS:
   ```bash
   CKODE_HOME="$HOME/ckode-eval" PATH="$HOME/ckode-eval/bin:$PATH" ./install.sh --version <new>
   ```
3. On **both Windows and Linux**, check that:
   - the lock still holds, so a user config enabling other providers still shows only the configured provider's models;
   - the logo, theme and title still appear;
   - prompts return and their cost is recorded;
   - the evaluation task set passes.
4. If the plugin API types changed, bump `@opencode-ai/plugin` in `plugin/package.json` to match, then run `bun install`, `bun test` and `tsc`.
5. Open a `chore: bump OpenCode to <new>` PR that changes **both** `OPENCODE_VERSION` in `install.sh` and `$OpenCodeVersion` in `install.ps1` (CI fails if they differ). After it merges, release a MINOR version.

---

## 13. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `irm … install.ps1` or `curl … install.sh` returns 404 | No release published, or a wrong URL | Check the [Releases page](https://github.com/CpulsiveK/ckode/releases) |
| Windows: `ckode` is not recognized | The terminal was opened before installing | Open a new terminal. If it's still missing, check that `%USERPROFILE%\.ckode\bin` is in your user `Path` |
| Windows: "running scripts is disabled on this system" | Running `.\install.ps1` directly under the default execution policy | Use the `irm … \| iex` one-liner, or `powershell -ExecutionPolicy Bypass -File .\install.ps1` |
| Windows: `irm` fails with a TLS / "could not create SSL/TLS secure channel" error | An old Windows PowerShell default without TLS 1.2 | Run `[Net.ServicePointManager]::SecurityProtocol = 'Tls12'` first, then the one-liner (`ckode upgrade` already does this) |
| Windows: "curl.exe is missing" or "tar.exe is missing" | Windows older than 10 version 1803 | Update Windows |
| Linux/macOS: `ckode: command not found` after installing | Your shell hasn't reloaded PATH | Open a new terminal |
| Installer prints `Download interrupted, resuming` | The connection to GitHub dropped partway through the 60 MB OpenCode download (common on VPN/WSL) | Nothing to do: it resumes up to 5 times. If it still fails, re-run the installer |
| "No provider selected", or an empty model list | The server is unreachable, the URL is wrong (a local server needs its `/v1` path, which the menu adds for a bare `host:port`), or the key is invalid | Check the server is running, re-add the provider, read `plugin.log` |
| `plugin.log` shows `401 Unauthorized` | The key isn't valid for this gateway | Pick the provider in the menu, remove it with `r` and add it again with the right key |
| `bun install --frozen-lockfile` fails with `UnknownLockfileVersion` | Wrong Bun version | Install Bun 1.4.2 |
| `bun: command not found` | Bun isn't on your PATH | Linux/macOS: `export PATH="$HOME/.bun/bin:$PATH"`. Windows: open a new terminal |
| A `.cmd` file behaves strangely after editing (labels not found, lines skipped) | It was saved with LF line endings | Re-check it out (`git checkout -- launcher/ckode.cmd`), and make your editor keep CRLF for `.cmd` files |
| Gateway requests time out from WSL | WSL network or VPN is unreliable | Retry, or test natively on Windows |
| The title still says "OpenCode" after an upstream bump | The renderer's `setTerminalTitle` changed upstream | Update the wrapper in `plugin/src/tui.tsx` |

To change a provider, add it again under the same name from the menu (`a`). To remove one, use `r` in the menu or delete `~/.ckode/providers`.

---

## 14. Security

- Never commit API keys, gateway tokens or other credentials, including in test fixtures, logs and screenshots. Tests use the fake key `sk-good` against the local stand-in gateway.
- Users' provider keys are stored in `~/.ckode/providers` (mode 600 on Linux and macOS), or come from `CKODE_API_KEY`. Don't log, copy or send that file's contents.
- When testing on your own Windows account, use `-NoModifyPath` or `CKODE_NO_MODIFY_PATH=1` so test installs don't land in your real PATH.
- Report a suspected leak or vulnerability to the maintainer privately, not in a public issue. **The repo is public.** Revoke a leaked key immediately.

---

## 15. Licensing

OpenCode is MIT-licensed. ckode downloads it unmodified, and two files are derived from it: `plugin/themes/ckode.json` (OpenCode's default theme with new colours) and the platform detection in `install.sh`. The `NOTICE` file contains the MIT licence text and this attribution, and it ships in every release bundle. Keep `NOTICE` up to date whenever you add anything derived from OpenCode.

---

## 16. Contacts

| Role | Person |
|---|---|
| Maintainer / release owner | Clifford Kwakye (https://github.com/CpulsiveK) |
