#!/usr/bin/env bash
# ckode installer: installs a pinned, unmodified OpenCode release plus the
# ckode plugin and the `ckode` launcher. Nothing outside CKODE_HOME
# is touched except one PATH entry, so an existing OpenCode install is unaffected.
#
#   curl -fsSL https://github.com/CpulsiveK/ckode/releases/latest/download/install.sh | bash
#
# To make it your own, pass a title (the name shown in the logo and terminal):
#   curl -fsSL .../install.sh | bash -s -- --title "My Agent"
#
# Run from a checkout it installs the files beside it; piped from a release it
# downloads the bundle published with that same release.
#
# Platform detection is adapted from OpenCode's own installer (MIT).
set -euo pipefail

# The OpenCode release ckode has been evaluated against. Bump it only after
# the evaluation set passes on the new release; this line is the upgrade.
OPENCODE_VERSION="1.18.33"

# Stamped by script/release.sh. Left as placeholders when run from a checkout.
CKODE_VERSION="__CKODE_VERSION__"
BUNDLE_URL="__BUNDLE_URL__"
LATEST_INSTALLER_URL="__LATEST_INSTALLER_URL__"

home="${CKODE_HOME:-$HOME/.ckode}"
version="$OPENCODE_VERSION"
bundle=""
title="${CKODE_TITLE:-}"
stamped() { case "$1" in __*__) echo "" ;; *) echo "$1" ;; esac; }
release_version="$(stamped "$CKODE_VERSION")"
bundle_url="${CKODE_BUNDLE_URL:-$(stamped "$BUNDLE_URL")}"
installer_url="${CKODE_INSTALLER_URL:-$(stamped "$LATEST_INSTALLER_URL")}"

usage() {
  cat <<EOF
Usage: install.sh [--title <name>] [--version <opencode version>] [--bundle <dir>]

  --title     The name shown in the logo, terminal title and messages (default: ckode, or the
              title of an existing install). Up to 24 letters, digits, spaces, dots, hyphens
              and underscores. The command is still ckode. CKODE_TITLE does the same.
  --version   Override the pinned OpenCode version ($OPENCODE_VERSION); for evaluating a new release
  --bundle    Directory holding plugin/ and launcher/ (default: beside this script)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --title) [ $# -ge 2 ] || { echo "--title needs a value" >&2; exit 1; }; title="$2"; shift 2 ;;
    --version) version="${2:?--version needs a value}"; version="${version#v}"; shift 2 ;;
    --bundle) bundle="${2:?--bundle needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Normalise the title: trim, collapse spaces, and refuse anything that could not be
# stored safely in the settings file. Keep in step with parseTitle in plugin/src/wordmark.ts.
title="$(printf '%s' "$title" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')"
if [ -z "$title" ] && [ -f "$home/settings" ]; then
  # Re-installing or upgrading keeps the title the user chose.
  title="$(. "$home/settings" 2>/dev/null; printf '%s' "${TITLE:-}")"
fi
title="${title:-ckode}"
if [ "${#title}" -gt 24 ] || ! printf '%s' "$title" | grep -Eq '^[A-Za-z0-9 ._-]+$'; then
  echo "Invalid --title '$title': use up to 24 letters, digits, spaces, dots, hyphens or underscores." >&2
  exit 1
fi

is_bundle() { [ -d "$1/plugin/src" ] && [ -f "$1/launcher/ckode" ] && [ -f "$1/install.sh" ]; }

# Piped from curl there is no script file, so the bundle comes from the release.
if [ -z "$bundle" ] && [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if is_bundle "$here"; then bundle="$here"; fi
fi
if [ -z "$bundle" ] && [ -n "$bundle_url" ]; then
  bundle="$(mktemp -d)"
  trap 'rm -rf "$bundle"' EXIT
  echo "Downloading ckode ${release_version:-bundle}"
  curl -fsSL "$bundle_url" | tar -xz -C "$bundle" || {
    echo "Download failed: $bundle_url" >&2
    exit 1
  }
fi
if [ -z "$bundle" ] || ! is_bundle "$bundle"; then
  echo "Could not find the ckode bundle (plugin/, launcher/, install.sh). Pass --bundle <dir>." >&2
  exit 1
fi

target() {
  local os arch
  case "$(uname -s)" in
    Darwin*) os="darwin" ;;
    Linux*) os="linux" ;;
    *) echo "Unsupported OS: $(uname -s). On Windows, use install.ps1 from PowerShell instead." >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  # An x64 shell under Rosetta should still get the native arm64 build.
  if [ "$os" = "darwin" ] && [ "$arch" = "x64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    arch="arm64"
  fi

  local suffix=""
  if [ "$arch" = "x64" ]; then
    if [ "$os" = "linux" ] && ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then suffix="-baseline"; fi
    if [ "$os" = "darwin" ] && [ "$(sysctl -n hw.optional.avx2_0 2>/dev/null || echo 0)" != "1" ]; then suffix="-baseline"; fi
  fi
  if [ "$os" = "linux" ] && { [ -f /etc/alpine-release ] || ldd --version 2>&1 | grep -qi musl; }; then
    suffix="$suffix-musl"
  fi
  echo "$os-$arch$suffix"
}

install_opencode() {
  local dest="$home/opencode/$version"
  if [ -x "$dest/opencode" ]; then
    echo "OpenCode $version already installed"
    return
  fi
  local platform ext
  platform="$(target)"
  ext=".zip"
  case "$platform" in linux-*) ext=".tar.gz" ;; esac
  local url="https://github.com/anomalyco/opencode/releases/download/v$version/opencode-$platform$ext"
  local tmp
  tmp="$(mktemp -d)"

  echo "Downloading OpenCode $version ($platform)"
  local progress="-sS"
  if [ -t 2 ]; then progress="--progress-bar"; fi
  # The archive is ~60 MB and slow VPN/WSL links reset it partway, so resume
  # rather than restart. A shell loop, because curl's --retry-all-errors needs 7.71+.
  local attempt=1 attempts=5
  until curl -fL "$progress" -C - -o "$tmp/archive$ext" "$url"; do
    if [ "$attempt" -ge "$attempts" ]; then
      rm -rf "$tmp"
      echo "Download failed after $attempts attempts: $url" >&2
      exit 1
    fi
    attempt=$((attempt + 1))
    echo "Download interrupted, resuming (attempt $attempt of $attempts)" >&2
    sleep 2
  done
  if [ "$ext" = ".tar.gz" ]; then tar -xzf "$tmp/archive$ext" -C "$tmp"; fi
  if [ "$ext" = ".zip" ]; then unzip -q "$tmp/archive$ext" -d "$tmp"; fi
  mkdir -p "$dest"
  mv "$tmp/opencode" "$dest/opencode"
  chmod 755 "$dest/opencode"
  rm -rf "$tmp"
}

install_bundle() {
  mkdir -p "$home/bin"
  # Replaced wholesale so files removed from the plugin do not linger.
  rm -rf "$home/plugin"
  mkdir -p "$home/plugin"
  cp -R "$bundle/plugin/src" "$bundle/plugin/themes" "$bundle/plugin/package.json" "$home/plugin/"
  cp "$bundle/launcher/ckode" "$home/bin/ckode"
  cp "$bundle/install.sh" "$home/install.sh"
  chmod 755 "$home/bin/ckode" "$home/install.sh"

  cat >"$home/settings" <<EOF
CKODE_VERSION="$release_version"
TITLE="$title"
OPENCODE_VERSION="$version"
INSTALLER_URL="$installer_url"
EOF
  cat >"$home/tui.json" <<EOF
{ "plugin": ["file://$home/plugin"] }
EOF
}

# Keep the active release and the most recent other one, so a bad upgrade can
# be undone by editing OPENCODE_VERSION in settings.
prune_old() {
  local previous
  previous="$(ls -1t "$home/opencode" | grep -vx "$version" | head -n 1 || true)"
  for dir in "$home/opencode"/*; do
    case "$(basename "$dir")" in "$version"|"$previous") ;; *) rm -rf "$dir" ;; esac
  done
}

add_to_path() {
  local bin="$home/bin"
  case ":$PATH:" in *":$bin:"*) return ;; esac
  # Prefer an existing PATH directory over editing shell startup files.
  if [ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) true ;; *) false ;; esac; then
    ln -sf "$bin/ckode" "$HOME/.local/bin/ckode"
    return
  fi
  local rc line
  case "$(basename "${SHELL:-bash}")" in
    zsh) rc="${ZDOTDIR:-$HOME}/.zshrc"; line="export PATH=\"$bin:\$PATH\"" ;;
    fish) rc="$HOME/.config/fish/config.fish"; line="fish_add_path $bin" ;;
    *) rc="$HOME/.bashrc"; line="export PATH=\"$bin:\$PATH\"" ;;
  esac
  grep -qsF "$line" "$rc" && return
  printf '\n# ckode\n%s\n' "$line" >>"$rc"
  echo "Added $bin to PATH in $rc."
}

install_opencode
install_bundle
prune_old
add_to_path
echo "$title ${release_version:-(local)} installed (OpenCode $version)."
if command -v ckode >/dev/null 2>&1; then
  echo "Run: ckode"
else
  echo "Open a new terminal, then run: ckode"
fi
