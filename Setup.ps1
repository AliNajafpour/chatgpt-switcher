#Requires -Version 5.1
<#
.SYNOPSIS
  Install the downloaded switcher locally, without downloads or administrator access.
#>
[CmdletBinding()]
param(
  [string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\CodexAccountSwitcher'),
  [switch]$NoLaunch,
  [switch]$NoShortcuts
)
$ErrorActionPreference = 'Stop'

function Install-Switcher {
  param([string]$SourceDirectory, [string]$InstallDirectory, [switch]$NoLaunch, [switch]$NoShortcuts)
  $source = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\')
  $dest = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\')
  if ($dest -eq [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($InstallDirectory)).TrimEnd('\')) { throw 'Choose a dedicated installation folder, not a drive root.' }
  $files = @('ChatGPT-Switcher.ps1','ChatGPT-Switcher.cmd','Setup.ps1','Setup.cmd','README.md','LICENSE','CHANGELOG.md','CONTRIBUTING.md','SECURITY-REVIEW.md','REVIEW.md')
  $marker = '.codex-switcher-install'
  $identity = 'AliNajafpour.CodexAccountSwitcher'
  foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)) { throw "Incomplete download: missing $file. Extract the entire ZIP and try again." }
  }
  if (Test-Path -LiteralPath $dest) {
    $item = Get-Item -LiteralPath $dest -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'The installation folder must be an ordinary directory.' }
    foreach ($file in ($files + @($marker, '.setup.lock'))) {
      $path = Join-Path $dest $file
      if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Cannot replace a directory or linked file: $path" }
      }
    }
    if (@(Get-ChildItem -LiteralPath $dest -Force | Where-Object { $_.Name -ne '.setup.lock' }).Count -gt 0) {
      $markerPath = Join-Path $dest $marker
      if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf) -or [IO.File]::ReadAllText($markerPath).Trim() -ne $identity) {
        throw 'Choose an empty folder or a folder installed by this setup. Existing unrelated files will not be overwritten.'
      }
    }
  }
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  $lockPath = Join-Path $dest '.setup.lock'
  $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  $stage = $null; $changed = @(); $keepStage = $false
  try {
    if ($source -ne $dest) {
      $stage = Join-Path $dest ('.setup-' + [guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Path $stage | Out-Null
      foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $source $file) -Destination (Join-Path $stage $file) }
      [IO.File]::WriteAllText((Join-Path $stage $marker), $identity)
      foreach ($file in ($files + $marker)) {
        $target = Join-Path $dest $file
        $incoming = Join-Path $stage $file
        if (Test-Path -LiteralPath $target) {
          [IO.File]::Replace($incoming, $target, (Join-Path $stage ($file + '.previous')))
        } else { [IO.File]::Move($incoming, $target) }
        $changed += $file
      }
    }
  } catch {
    $failure = $_
    foreach ($file in $changed) {
      $backup = Join-Path $stage ($file + '.previous')
      $target = Join-Path $dest $file
      try {
        if (Test-Path -LiteralPath $backup) { [IO.File]::Copy($backup, $target, $true) }
        elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
      } catch { $keepStage = $true; Write-Warning "Could not restore $file. Previous program files are preserved in $stage." }
    }
    throw $failure
  } finally {
    $lock.Dispose()
    if (-not $keepStage -and $stage -and (Test-Path -LiteralPath $stage)) {
      if ((Split-Path -Parent ([IO.Path]::GetFullPath($stage))) -ne $dest) { throw 'Unsafe setup cleanup path.' }
      Remove-Item -LiteralPath $stage -Recurse -Force
    }
  }
  # Shortcut changes cannot be rolled back with files; keep their target installed.
  $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $app = Join-Path $dest 'ChatGPT-Switcher.ps1'
  if (-not $NoShortcuts) {
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $app -Setup -NoShortcut | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Program files are installed in $dest, but shortcut creation failed. Run setup again to repair shortcuts." }
  }
  if (-not $NoLaunch) {
    try { Start-Process -FilePath $powershell -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f $app) }
    catch { throw "Program files are installed in $dest, but the picker could not start. Open ChatGPT-Switcher.cmd from that folder. $_" }
  }
  return $dest
}

try {
  Write-Host 'Installing Codex Account Switcher...' -ForegroundColor Cyan
  $installed = Install-Switcher -SourceDirectory $PSScriptRoot -InstallDirectory $InstallDirectory -NoLaunch:$NoLaunch -NoShortcuts:$NoShortcuts
  Write-Host ("Installed to: {0}" -f $installed) -ForegroundColor Green
  if ($NoShortcuts) { Write-Host 'Run ChatGPT-Switcher.cmd from the installation folder.' }
  else { Write-Host 'Open Codex Account Switcher from Start.' }
  Write-Host 'Your account data stays in its existing folder.'
} catch {
  Write-Host ("Setup failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
  exit 1
}
