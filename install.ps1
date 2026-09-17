<#
  ChatGPT Switcher for Windows - one-line installer
    irm https://raw.githubusercontent.com/kociden/chatgpt-switcher/main/install.ps1 | iex

  Downloads the switcher into Documents\ChatGPT-Switcher and creates
  Desktop + Start Menu shortcuts. Nothing is installed system-wide and
  no background service is registered.
#>
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$repoRaw = 'https://raw.githubusercontent.com/kociden/chatgpt-switcher/main'
$dest    = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ChatGPT-Switcher'
$files   = @('ChatGPT-Switcher.ps1', 'ChatGPT-Switcher.cmd', 'README.md', 'README.ja.md', 'LICENSE')

Write-Host "ChatGPT Switcher installer" -ForegroundColor Cyan
Write-Host ("Installing to: {0}" -f $dest)
New-Item -ItemType Directory -Force -Path $dest | Out-Null

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
foreach ($f in $files) {
  $url = "$repoRaw/$f"
  $out = Join-Path $dest $f
  Write-Host ("  downloading {0}" -f $f)
  Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
}

# Create Desktop + Start Menu shortcuts via the script itself
& (Join-Path $dest 'ChatGPT-Switcher.ps1') -Setup -NoShortcut

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Launch it from the Start Menu / Desktop shortcut 'ChatGPT アカウント切替',"
Write-Host ("or run: {0}" -f (Join-Path $dest 'ChatGPT-Switcher.cmd'))
