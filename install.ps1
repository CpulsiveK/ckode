# ckode installer for Windows: installs a pinned, unmodified OpenCode
# release plus the ckode plugin and the `ckode` launcher. Nothing outside
# CKODE_HOME is touched except one entry in the user's PATH.
#
#   irm https://github.com/CpulsiveK/ckode/releases/latest/download/install.ps1 | iex
#
# With options (piped scripts cannot take parameters):
#   & ([scriptblock]::Create((irm https://github.com/CpulsiveK/ckode/releases/latest/download/install.ps1))) -Version <opencode version>
#
# To make it your own, pass a title (the name shown in the logo and terminal):
#   & ([scriptblock]::Create((irm https://github.com/CpulsiveK/ckode/releases/latest/download/install.ps1))) -Title "My Agent"
# or set $env:CKODE_TITLE first when piping to iex.
#
# Works on Windows PowerShell 5.1, which every supported Windows ships with.
# Run under `iex`, so it must never call `exit`: that would close the user's
# window. Failures throw instead. Mirrors install.sh; keep the two in step.
param(
  [string] $Title = "",
  [string] $Version = "",
  [string] $Bundle = "",
  [switch] $NoModifyPath
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# The OpenCode release ckode has been evaluated against. Bump it with
# OPENCODE_VERSION in install.sh; the two installers must pin the same release.
$OpenCodeVersion = "1.18.33"

# Stamped by script/release.sh. Left as placeholders when run from a checkout.
$ckodeVersion = "__CKODE_VERSION__"
$BundleUrl = "__BUNDLE_URL__"
$LatestInstallerUrl = "__LATEST_INSTALLER_PS1_URL__"

function Stamped([string] $value) { if ($value -match "^__.*__$") { "" } else { $value } }
function Fail([string] $message) { throw "ckode install failed: $message" }

$home_ = if ($env:CKODE_HOME) { $env:CKODE_HOME } else { Join-Path $env:USERPROFILE ".ckode" }
$version_ = if ($Version) { $Version.TrimStart("v") } else { $OpenCodeVersion }
$releaseVersion = Stamped $ckodeVersion
$bundleUrl_ = if ($env:CKODE_BUNDLE_URL) { $env:CKODE_BUNDLE_URL } else { Stamped $BundleUrl }
$installerUrl = if ($env:CKODE_INSTALLER_URL) { $env:CKODE_INSTALLER_URL } else { Stamped $LatestInstallerUrl }
# The title is trimmed, and refused if it could not be stored safely in
# settings.cmd. Keep in step with install.sh and parseTitle in plugin/src/wordmark.ts.
if (-not $Title) { $Title = $env:CKODE_TITLE }
$Title = ("$Title" -replace "\s+", " ").Trim()
if (-not $Title) {
  # Re-installing or upgrading keeps the title the user chose.
  $existing = Join-Path $home_ "settings.cmd"
  if (Test-Path $existing) {
    $line = Get-Content $existing | Where-Object { $_ -like '@set "TITLE=*' } | Select-Object -First 1
    if ($line) { $Title = $line.Substring(12).TrimEnd('"').Replace("%%", "%") }
  }
}
if (-not $Title) { $Title = "ckode" }
if ($Title.Length -gt 24 -or $Title -notmatch '^[A-Za-z0-9 ._-]+$') {
  Fail "invalid -Title '$Title': use up to 24 letters, digits, spaces, dots, hyphens or underscores."
}
# Piped through iex the script takes no switches, so CI and tests use this.
if ($env:CKODE_NO_MODIFY_PATH) { $NoModifyPath = $true }

# curl.exe and tar.exe ship with Windows 10 1803 and later. `curl` alone is an
# alias for Invoke-WebRequest in Windows PowerShell, hence the .exe.
foreach ($tool in "curl.exe", "tar.exe") {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    Fail "$tool is missing. ckode needs Windows 10 version 1803 or later."
  }
}

function Test-Bundle([string] $dir) {
  (Test-Path (Join-Path $dir "plugin\src")) -and
  (Test-Path (Join-Path $dir "launcher\ckode.cmd")) -and
  (Test-Path (Join-Path $dir "install.ps1"))
}

function New-TempDir {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ("ckode-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $dir | Out-Null
  $dir
}

function Get-Platform {
  $arch = $env:PROCESSOR_ARCHITECTURE
  # A 32-bit or emulated PowerShell reports its own architecture here.
  if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
  if ($arch -eq "ARM64") { return "windows-arm64" }
  if ($arch -ne "AMD64") { Fail "unsupported architecture $arch. ckode needs 64-bit Windows." }
  # Same choice as install.sh: CPUs without AVX2 need the baseline build.
  # Assume none when the check itself cannot run (e.g. constrained language
  # mode), since the baseline build runs everywhere.
  $avx2 = $false
  try {
    Add-Type -Namespace ckode -Name Cpu -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(uint feature);'
    $avx2 = [ckode.Cpu]::IsProcessorFeaturePresent(40) # PF_AVX2_INSTRUCTIONS_AVAILABLE
  } catch {}
  if ($avx2) { "windows-x64" } else { "windows-x64-baseline" }
}

# Windows PowerShell 5.1 turns a native tool's stderr into error records when
# output is redirected (CI, logs), which "Stop" would make fatal: curl's
# progress bar alone would abort the install. Judge tools by exit code instead.
function Invoke-Native([scriptblock] $command) {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try { & $command 2>&1 | ForEach-Object { "$_" } | Write-Host } finally { $ErrorActionPreference = $previous }
}

# The archive is ~60 MB and slow VPN links reset it partway, so resume rather
# than restart, as install.sh does.
function Get-File([string] $url, [string] $out) {
  $attempts = 5
  for ($attempt = 1; ; $attempt++) {
    if ([Console]::IsErrorRedirected) {
      Invoke-Native { curl.exe -fL -sS -C - -o $out $url }
    } else {
      # Left unredirected so the progress bar draws in place.
      $previous = $ErrorActionPreference
      $ErrorActionPreference = "Continue"
      try { & curl.exe -fL --progress-bar -C - -o $out $url } finally { $ErrorActionPreference = $previous }
    }
    if ($LASTEXITCODE -eq 0) { return }
    if ($attempt -ge $attempts) { Fail "download failed after $attempts attempts: $url" }
    Write-Host "Download interrupted, resuming (attempt $($attempt + 1) of $attempts)"
    Start-Sleep -Seconds 2
  }
}

function Install-OpenCode {
  $dest = Join-Path $home_ "opencode\$version_"
  if (Test-Path (Join-Path $dest "opencode.exe")) {
    Write-Host "OpenCode $version_ already installed"
    return
  }
  $platform = Get-Platform
  $url = "https://github.com/anomalyco/opencode/releases/download/v$version_/opencode-$platform.zip"
  $tmp = New-TempDir
  try {
    Write-Host "Downloading OpenCode $version_ ($platform)"
    Get-File $url (Join-Path $tmp "archive.zip")
    Invoke-Native { tar.exe -xf (Join-Path $tmp "archive.zip") -C $tmp }
    if ($LASTEXITCODE -ne 0) { Fail "could not unpack $url" }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Move-Item (Join-Path $tmp "opencode.exe") (Join-Path $dest "opencode.exe")
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

function Install-Bundle([string] $from) {
  $bin = Join-Path $home_ "bin"
  $plugin = Join-Path $home_ "plugin"
  New-Item -ItemType Directory -Force -Path $bin | Out-Null
  # Replaced wholesale so files removed from the plugin do not linger.
  if (Test-Path $plugin) { Remove-Item -Recurse -Force $plugin }
  New-Item -ItemType Directory -Path $plugin | Out-Null
  foreach ($item in "src", "themes", "package.json") {
    Copy-Item -Recurse (Join-Path $from "plugin\$item") $plugin
  }
  Copy-Item (Join-Path $from "launcher\ckode.cmd") (Join-Path $bin "ckode.cmd")
  Copy-Item (Join-Path $from "launcher\ckode-menu.ps1") (Join-Path $bin "ckode-menu.ps1")
  Copy-Item (Join-Path $from "install.ps1") (Join-Path $home_ "install.ps1")

  # OpenCode accepts a plain drive path for a plugin and converts it to a file
  # URL itself, so spaces in the user name need no encoding. Forward slashes
  # keep it valid JSON without escaping.
  $pluginPath = $plugin.Replace("\", "/")
  # Read by the launcher with `call`; % would be expanded there, so double it.
  $settings = @(
    "@set ""CKODE_VERSION=$releaseVersion"""
    "@set ""TITLE=$Title"""
    "@set ""OPENCODE_VERSION=$version_"""
    "@set ""INSTALLER_URL=$installerUrl"""
    "@set ""PLUGIN_PATH=$pluginPath"""
  ) | ForEach-Object { $_.Replace("%", "%%") }
  Set-Content -Path (Join-Path $home_ "settings.cmd") -Value $settings -Encoding ASCII
  Set-Content -Path (Join-Path $home_ "tui.json") -Value "{ ""plugin"": [""$pluginPath""] }" -Encoding ASCII
}

# Keep the active release and the most recent other one, so a bad upgrade can
# be undone by editing OPENCODE_VERSION in settings.cmd.
function Remove-OldReleases {
  $dirs = Get-ChildItem -Directory (Join-Path $home_ "opencode") | Sort-Object LastWriteTime -Descending
  $previous = $dirs | Where-Object { $_.Name -ne $version_ } | Select-Object -First 1
  foreach ($dir in $dirs) {
    if ($dir.Name -ne $version_ -and (-not $previous -or $dir.Name -ne $previous.Name)) {
      Remove-Item -Recurse -Force $dir.FullName
    }
  }
}

function Add-ToPath {
  $bin = Join-Path $home_ "bin"
  # Read the raw registry value: going through [Environment] would expand
  # entries such as %USERPROFILE%\bin and save them back as fixed paths.
  $key = Get-Item "HKCU:\Environment"
  $current = $key.GetValue("Path", "", "DoNotExpandEnvironmentNames")
  $entries = @($current -split ";" | Where-Object { $_ })
  if ($entries -notcontains $bin) {
    Set-ItemProperty -Path "HKCU:\Environment" -Name Path -Type ExpandString -Value (($entries + $bin) -join ";")
    # Setting any user variable broadcasts the change, so terminals opened
    # from now on see the new PATH without signing out.
    [Environment]::SetEnvironmentVariable("CKODE_PATH_UPDATED", "1", "User")
    [Environment]::SetEnvironmentVariable("CKODE_PATH_UPDATED", $null, "User")
    Write-Host "Added $bin to your PATH."
  }
  if (($env:Path -split ";") -notcontains $bin) { $env:Path = "$env:Path;$bin" }
}

$source = $Bundle
$cleanup = $null
# Run from a checkout or an unpacked bundle, use the files beside the script.
if (-not $source -and $PSCommandPath -and (Test-Bundle (Split-Path -Parent $PSCommandPath))) {
  $source = Split-Path -Parent $PSCommandPath
}
try {
  if (-not $source -and $bundleUrl_) {
    $cleanup = New-TempDir
    $source = $cleanup
    $label = if ($releaseVersion) { $releaseVersion } else { "bundle" }
    Write-Host "Downloading ckode $label"
    Get-File $bundleUrl_ (Join-Path $cleanup "bundle.tar.gz")
    Invoke-Native { tar.exe -xzf (Join-Path $cleanup "bundle.tar.gz") -C $cleanup }
    if ($LASTEXITCODE -ne 0) { Fail "could not unpack $bundleUrl_" }
  }
  if (-not $source -or -not (Test-Bundle $source)) {
    Fail "could not find the ckode bundle (plugin\, launcher\, install.ps1). Pass -Bundle <dir>."
  }

  New-Item -ItemType Directory -Force -Path $home_ | Out-Null
  Install-OpenCode
  Install-Bundle $source
  Remove-OldReleases
  if (-not $NoModifyPath) { Add-ToPath }
} finally {
  if ($cleanup) { Remove-Item -Recurse -Force $cleanup -ErrorAction SilentlyContinue }
}

$label = if ($releaseVersion) { $releaseVersion } else { "(local)" }
Write-Host "$Title $label installed (OpenCode $version_)."
if ($NoModifyPath) {
  Write-Host "Run: $(Join-Path $home_ 'bin\ckode.cmd')"
} else {
  Write-Host "Run: ckode   (new terminals pick it up automatically)"
}
