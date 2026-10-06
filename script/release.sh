#!/usr/bin/env bash
# Builds the release assets into dist/:
#   install.sh               the Linux/macOS installer, stamped with this release's URLs
#   install.ps1              the Windows installer, stamped the same way
#   ckode-bundle.tar.gz  plugin, both launchers and both stamped installers
#
#   script/release.sh <version> <download-base> <latest-base>
#
# download-base is where this release's assets live, e.g.
#   https://github.com/<org>/<repo>/releases/download/v0.1.0
# latest-base is where `ckode upgrade` looks, e.g.
#   https://github.com/<org>/<repo>/releases/latest/download
set -euo pipefail

version="${1:?version required}"
download_base="${2:?download base URL required}"
latest_base="${3:?latest base URL required}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist="$root/dist"

rm -rf "$dist"
mkdir -p "$dist/bundle/plugin" "$dist/bundle/launcher"

stamp() {
  sed \
    -e "s|__CKODE_VERSION__|$version|" \
    -e "s|__BUNDLE_URL__|$download_base/ckode-bundle.tar.gz|" \
    -e "s|__LATEST_INSTALLER_URL__|$latest_base/install.sh|" \
    -e "s|__LATEST_INSTALLER_PS1_URL__|$latest_base/install.ps1|" \
    "$root/$1" >"$dist/$1"
  if grep -q "__[A-Z0-9_]*__" "$dist/$1"; then
    echo "$1 still has unstamped placeholders" >&2
    exit 1
  fi
}
stamp install.sh
stamp install.ps1
chmod 755 "$dist/install.sh"

cp "$dist/install.sh" "$dist/install.ps1" "$dist/bundle/"
cp "$root/launcher/ckode" "$root/launcher/ckode.cmd" "$root/launcher/ckode-menu.ps1" "$dist/bundle/launcher/"
cp -R "$root/plugin/src" "$root/plugin/themes" "$root/plugin/package.json" "$dist/bundle/plugin/"
cp "$root/README.md" "$root/NOTICE" "$dist/bundle/"

tar -czf "$dist/ckode-bundle.tar.gz" -C "$dist/bundle" .
rm -rf "$dist/bundle"
(cd "$dist" && sha256sum install.sh install.ps1 ckode-bundle.tar.gz >SHA256SUMS)
ls -l "$dist"
