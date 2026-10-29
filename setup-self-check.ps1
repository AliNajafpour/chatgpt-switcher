#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Must-Fail([scriptblock]$Action, $Message) {
  $failed = $false
  try { & $Action | Out-Null } catch { $failed = $true }
  Assert $failed $Message
}
$installer = Join-Path $PSScriptRoot 'Setup.ps1'
Assert (Test-Path -LiteralPath $installer) 'Local setup script is missing'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'Setup script has syntax errors'
$fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Install-Switcher' }, $false)
Assert ($null -ne $fn) 'Installer entry function is missing'
. ([scriptblock]::Create($fn.Extent.Text))
$temp = Join-Path $PSScriptRoot ('.self-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  $source = Join-Path $temp 'source with spaces'
  $dest = Join-Path $temp 'installed with spaces'
  New-Item -ItemType Directory -Path $source | Out-Null
  foreach ($file in @('Setup.ps1','Setup.cmd','ChatGPT-Switcher.ps1','ChatGPT-Switcher.cmd','README.md','LICENSE','CHANGELOG.md','CONTRIBUTING.md','SECURITY-REVIEW.md','REVIEW.md')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $source
  }
  Set-Content -LiteralPath (Join-Path $source 'ChatGPT-Switcher.ps1') -Encoding UTF8 -Value @'
param([switch]$Setup, [switch]$NoShortcut)
if (-not ($Setup -and $NoShortcut)) { throw 'Expected silent shortcut setup' }
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'shortcut-setup-called.txt') -Value 'setup invoked'
'@
  Set-Content -LiteralPath (Join-Path $source 'do-not-copy.txt') -Value 'not app payload'
  $script:LaunchArguments = $null
  function Start-Process { param($FilePath, $ArgumentList, $WindowStyle) $script:LaunchArguments = $ArgumentList }
  $installed = Install-Switcher -SourceDirectory $source -InstallDirectory $dest
  Assert ($installed -eq $dest) 'Unexpected installation directory'
  Assert (Test-Path -LiteralPath (Join-Path $dest 'ChatGPT-Switcher.cmd')) 'Launcher not installed'
  Assert (Test-Path -LiteralPath (Join-Path $dest 'shortcut-setup-called.txt')) 'Existing shortcut setup was not reused'
  Assert ($script:LaunchArguments.Contains('"' + (Join-Path $dest 'ChatGPT-Switcher.ps1') + '"')) 'Launch does not use the installed copy'
  Assert (-not (Test-Path -LiteralPath (Join-Path $dest 'do-not-copy.txt'))) 'Unexpected source files were copied'
  $script:LaunchArguments = $null
  Set-Content -LiteralPath (Join-Path $dest 'personal-note.txt') -Value 'keep me'
  Set-Content -LiteralPath (Join-Path $source 'README.md') -Value 'updated documentation'
  Install-Switcher -SourceDirectory $source -InstallDirectory $dest -NoLaunch -NoShortcuts | Out-Null
  Assert ((Get-Content -LiteralPath (Join-Path $dest 'README.md') -Raw).Trim() -eq 'updated documentation') 'Reinstall did not update files'
  Assert (Test-Path -LiteralPath (Join-Path $dest 'personal-note.txt')) 'Reinstall removed unrelated files'
  Assert ($null -eq $script:LaunchArguments) 'NoLaunch was ignored'
  $residual = Join-Path $temp 'empty previous attempt'
  New-Item -ItemType Directory -Path $residual | Out-Null
  Set-Content -LiteralPath (Join-Path $residual '.setup.lock') -Value ''
  Install-Switcher -SourceDirectory $source -InstallDirectory $residual -NoLaunch -NoShortcuts | Out-Null
  Assert (Test-Path -LiteralPath (Join-Path $residual 'ChatGPT-Switcher.ps1')) 'Empty previous attempt prevented retry'
  $before = [IO.File]::ReadAllText((Join-Path $dest 'ChatGPT-Switcher.ps1'))
  Add-Content -LiteralPath (Join-Path $source 'ChatGPT-Switcher.ps1') -Value '# new version'
  $locked = [IO.File]::Open((Join-Path $dest 'ChatGPT-Switcher.cmd'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
  try {
    Must-Fail { Install-Switcher -SourceDirectory $source -InstallDirectory $dest -NoLaunch -NoShortcuts } 'Locked update unexpectedly succeeded'
  } finally { $locked.Dispose() }
  Assert ([IO.File]::ReadAllText((Join-Path $dest 'ChatGPT-Switcher.ps1')) -eq $before) 'Failed update did not restore prior files'
  Assert (@(Get-ChildItem -LiteralPath $dest -Filter '.setup-*' -Force).Count -eq 0) 'Temporary setup files remain'
  $workingMain = [IO.File]::ReadAllText((Join-Path $source 'ChatGPT-Switcher.ps1'))
  Set-Content -LiteralPath (Join-Path $source 'ChatGPT-Switcher.ps1') -Encoding UTF8 -Value @'
param([switch]$Setup, [switch]$NoShortcut)
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'partially-created-shortcut.txt') -Value 'shortcut points here'
exit 9
'@
  $shortcutFailure = Join-Path $temp 'shortcut failure'
  try {
    Must-Fail { Install-Switcher -SourceDirectory $source -InstallDirectory $shortcutFailure -NoLaunch } 'Shortcut failure was not reported'
    Assert (Test-Path -LiteralPath (Join-Path $shortcutFailure 'ChatGPT-Switcher.ps1')) 'Shortcut failure left a broken target'
  } finally { [IO.File]::WriteAllText((Join-Path $source 'ChatGPT-Switcher.ps1'), $workingMain) }
  function Start-Process { throw 'Simulated launch failure' }
  $launchFailure = Join-Path $temp 'launch failure'
  Must-Fail { Install-Switcher -SourceDirectory $source -InstallDirectory $launchFailure -NoShortcuts } 'Launch failure was not reported'
  Assert (Test-Path -LiteralPath (Join-Path $launchFailure 'ChatGPT-Switcher.ps1')) 'Launch failure removed the installed program'
  $unrelated = Join-Path $temp 'unrelated'
  New-Item -ItemType Directory -Path $unrelated | Out-Null
  Set-Content -LiteralPath (Join-Path $unrelated 'README.md') -Value 'keep existing content'
  Must-Fail { Install-Switcher -SourceDirectory $source -InstallDirectory $unrelated -NoLaunch -NoShortcuts } 'Non-app directory was overwritten'
  Assert ((Get-Content -LiteralPath (Join-Path $unrelated 'README.md') -Raw).Trim() -eq 'keep existing content') 'Unrelated file was modified'
  Remove-Item -LiteralPath (Join-Path $source 'LICENSE')
  $missing = Join-Path $temp 'missing payload destination'
  Must-Fail { Install-Switcher -SourceDirectory $source -InstallDirectory $missing -NoLaunch -NoShortcuts } 'Incomplete package installed'
  Assert (-not (Test-Path -LiteralPath $missing)) 'Incomplete package left an installation directory'
  Write-Host 'PASS: local installation, installed shortcuts/launch, upgrades, rollback, unrelated files, incomplete package.'
} finally {
  if ((Split-Path -Parent ([IO.Path]::GetFullPath($temp))) -ne [IO.Path]::GetFullPath($PSScriptRoot)) { throw 'Unsafe cleanup path' }
  Remove-Item -LiteralPath $temp -Recurse -Force
}
