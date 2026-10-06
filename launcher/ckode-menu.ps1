# ckode provider menu for Windows. Mirrors the menu in launcher/ckode; keep the
# two in step. Run by ckode.cmd, never by hand.
#
# Providers live in -Providers, one per line, tab separated: name, URL, key.
# When the user picks a provider (or adds one), -Out is written as a batch file
# of `set` lines for ckode.cmd to call; picking the default writes nothing.
# -Add skips the menu and only adds a provider.
param(
  [Parameter(Mandatory = $true)] [string] $Providers,
  [Parameter(Mandatory = $true)] [string] $Out,
  [switch] $Add
)

$ErrorActionPreference = "Stop"

function Get-KnownUrl([string] $name) {
  switch ($name.ToLower()) {
    "ollama"     { "http://localhost:11434/v1" }
    "lmstudio"   { "http://localhost:1234/v1" }
    "openai"     { "https://api.openai.com/v1" }
    "anthropic"  { "https://api.anthropic.com/v1" }
    "openrouter" { "https://openrouter.ai/api/v1" }
    default      { "" }
  }
}

function Read-All {
  if (-not (Test-Path $Providers)) { return @() }
  @(Get-Content $Providers | Where-Object { $_ } | ForEach-Object {
    $f = $_ -split "`t"
    [pscustomobject]@{ Name = $f[0]; Url = $f[1]; Key = $(if ($f.Count -gt 2) { $f[2] } else { "" }) }
  })
}

function Save-All($list) {
  Set-Content -Path $Providers -Encoding ASCII -Value @($list | ForEach-Object { "$($_.Name)`t$($_.Url)`t$($_.Key)" })
}

function Add-Provider {
  $name = ""
  while (-not $name) {
    $name = ((Read-Host "Provider name (e.g. ollama, anthropic)").Trim() -replace "[^A-Za-z0-9._-]", "-").Trim("-")
  }
  $suggestion = Get-KnownUrl $name
  $url = ""
  while (-not $url) {
    $label = "Provider URL"
    if ($suggestion) { $label += " [$suggestion]" }
    $url = (Read-Host $label).Trim()
    if (-not $url) { $url = $suggestion }
  }
  if ($url -notmatch "^https?://") { $url = "http://$url" }
  $url = $url.TrimEnd("/")
  # A bare host:port is shorthand for its /v1 API, which is where Ollama serves it.
  if ($url -notmatch "^https?://[^/]+/") { $url += "/v1" }
  $secure = Read-Host "API key (press Enter if not needed)" -AsSecureString
  $key = [Net.NetworkCredential]::new("", $secure).Password.Trim()
  # Re-adding a name replaces it.
  $list = @(Read-All | Where-Object { $_.Name -ne $name }) + [pscustomobject]@{ Name = $name; Url = $url; Key = $key }
  Save-All $list
  [pscustomobject]@{ Name = $name; Url = $url; Key = $key }
}

function Write-Selection($p) {
  # % would be expanded when ckode.cmd calls this file, so double it.
  $lines = @(
    "@set ""CKODE_PROVIDER_NAME=$($p.Name)"""
    "@set ""CKODE_BASE_URL=$($p.Url)"""
  )
  if ($p.Key) { $lines += "@set ""CKODE_API_KEY=$($p.Key)""" }
  Set-Content -Path $Out -Encoding ASCII -Value ($lines | ForEach-Object { $_.Replace("%", "%%") })
}

if ($Add) {
  [void](Add-Provider)
  Write-Host "Saved. Pick it from the menu next time you start ckode."
  exit 0
}

while ($true) {
  $all = Read-All
  Write-Host ""
  Write-Host "ckode  choose a provider"
  Write-Host ""
  Write-Host "  " -NoNewline
  Write-Host "*" -ForegroundColor Green -NoNewline
  Write-Host " 1) opencode  free models  " -NoNewline
  Write-Host "(default)" -ForegroundColor Green
  for ($i = 0; $i -lt $all.Count; $i++) {
    Write-Host ("    {0}) {1}  {2}" -f ($i + 2), $all[$i].Name, $all[$i].Url) -ForegroundColor Gray
  }
  Write-Host "    a) add a provider"
  if ($all.Count) { Write-Host "    r) remove a provider" }
  Write-Host ""
  $choice = (Read-Host "Select [1]").Trim().ToLower()
  if (-not $choice -or $choice -eq "1") { exit 0 }
  if ($choice -eq "a") { Write-Selection (Add-Provider); exit 0 }
  if ($choice -eq "r" -and $all.Count) {
    $n = 0
    if ([int]::TryParse((Read-Host "Number to remove").Trim(), [ref] $n) -and $n -ge 2 -and $n -le $all.Count + 1) {
      Save-All @($all | Where-Object { $_ -ne $all[$n - 2] })
    }
    continue
  }
  $n = 0
  if ([int]::TryParse($choice, [ref] $n) -and $n -ge 2 -and $n -le $all.Count + 1) {
    Write-Selection $all[$n - 2]
    exit 0
  }
  Write-Host "ckode: pick a number from the list, a, or r." -ForegroundColor Red
}
