param([string]$Source = (Join-Path $PSScriptRoot 'ChatGPT-Switcher.ps1'))
$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Must-Fail([scriptblock]$Action, $Message) {
  $failed = $false
  try { & $Action | Out-Null } catch { $failed = $true }
  Assert $failed $Message
}
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Source, [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'PowerShell syntax errors'
# Load function definitions only. Never execute the application entry point.
foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
  . ([scriptblock]::Create($fn.Extent.Text))
}
$temp = Join-Path $PSScriptRoot ('.self-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  $script:Root = Join-Path $temp 'accounts'
  $script:ConfigPath = Join-Path $script:Root 'accounts.json'
  $script:LogPath = Join-Path $script:Root 'switcher.log'
  $script:MainId = '__main__'
  $script:Palette = @('#4285F4')
  function Set-JumpList {}
  function Get-RunningAccountIds { @() }
  function Get-AccountShortcutPath { param($Account) (Join-Path $temp ($Account.id + '.lnk')) }
  foreach ($id in @('..', '.', '../outside', '..\outside', 'C:\outside', '__main__', 'Work.', 'CON', 'a"b', 'a*b', 'accounts.json', 'accounts.json.bak', 'accounts.lock', 'switcher.log')) {
    Must-Fail { Get-AccountPaths $id } "Unsafe account ID accepted: $id"
  }
  $orphan = Join-Path $script:Root 'Orphan'
  New-Item -ItemType Directory -Path $orphan -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $orphan 'keep.txt') -Value 'unregistered profile'
  $fresh = Add-Account -Display 'Orphan' -SkipShortcut
  Assert ($fresh.id -ne 'Orphan') 'New account reused an existing unregistered profile'
  Remove-Account $fresh.id
  Assert (Test-Path -LiteralPath (Join-Path $orphan 'keep.txt')) 'Existing profile data changed'
  $heldLock = [IO.File]::Open((Join-Path $script:Root 'accounts.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    Must-Fail { Add-Account -Display 'Concurrent' -SkipShortcut } 'Concurrent account mutation was allowed'
  } finally { $heldLock.Dispose() }
  Assert (-not (Find-Account 'Concurrent')) 'Rejected concurrent mutation changed config'
  $account = Add-Account -Display 'Work' -SkipShortcut
  $heldLock = [IO.File]::Open((Join-Path $script:Root 'accounts.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    Must-Fail { Rename-Account $account.id 'Blocked' } 'Concurrent rename was allowed'
    Must-Fail { Remove-Account $account.id } 'Concurrent removal was allowed'
  } finally { $heldLock.Dispose() }
  Assert ((Find-Account $account.id).display -eq 'Work') 'Rejected concurrent rename changed config'
  Assert ($account.mode -eq 'isolated') 'New accounts must be isolated'
  Assert (Test-Path -LiteralPath (Get-AccountPaths $account.id).Codex) 'Account data missing'
  $other = Add-Account -Display 'Other' -SkipShortcut
  Must-Fail { Rename-Account $account.id 'Other' } 'Rename accepted a duplicate display name'
  Remove-Account $other.id
  $renamed = 'Personal'
  Rename-Account $account.id $renamed
  Assert ((Find-Account $account.id).display -eq $renamed) 'Rename failed'
  Remove-Account $account.id
  Assert ((Get-Config).accounts.Count -eq 0) 'Remove failed'
  Assert (Test-Path -LiteralPath ($script:ConfigPath + '.bak')) 'Config backup missing'
  $linked = Add-Account -Display 'Linked' -SkipShortcut
  $outside = Join-Path $temp 'outside'
  New-Item -ItemType Directory -Path $outside | Out-Null
  Set-Content -LiteralPath (Join-Path $outside 'keep.txt') -Value 'keep'
  $junction = Join-Path (Get-AccountPaths $linked.id).Codex 'link'
  try { New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null }
  catch { Write-Host 'SKIP: junction test (Windows denied junction creation).' }
  if (Test-Path -LiteralPath $junction) {
    try {
      Must-Fail { Remove-Account $linked.id } 'Recursive deletion accepted a linked directory'
      Assert (Test-Path -LiteralPath (Join-Path $outside 'keep.txt')) 'Linked target was deleted'
    } finally { [IO.Directory]::Delete($junction) }
  }
  Remove-Account $linked.id
  Set-Content -LiteralPath $script:ConfigPath -Value '{broken'
  Must-Fail { Get-Config } 'Corrupt config was silently discarded'
  Set-Content -LiteralPath $script:ConfigPath -Value '{}'
  Must-Fail { Get-Config } 'Invalid config schema was accepted'
  Set-Content -LiteralPath $script:ConfigPath -Value '{"accounts":[{"id":"Work","display":"","color":"#4285F4"}]}'
  Must-Fail { Get-Config } 'Empty profile display name was accepted'
  Set-Content -LiteralPath $script:ConfigPath -Value '{"accounts":[{"id":"Work","display":"Work","color":"broken"}]}'
  Must-Fail { Get-Config } 'Invalid profile color was accepted'
  Set-Content -LiteralPath $script:ConfigPath -Value '{"accounts":[{"id":"..","display":"bad"}]}'
  Must-Fail { Get-Config } 'Unsafe config accepted'
  Set-Content -LiteralPath $script:ConfigPath -Value '{"accounts":[{"id":"Work","display":"Work","color":"#4285F4","mode":"shared"}]}'
  function Get-ChatGptApp { [pscustomobject]@{Kind='Installer'; Exe='fake.exe'} }
  $script:LaunchCount = 0
  function Start-Process { $script:LaunchCount++; throw 'Unexpected launch' }
  Must-Fail { Start-Account 'Work' } 'Legacy shared account was allowed'
  Assert ($script:LaunchCount -eq 0) 'Shared account attempted to launch'
  Set-Content -LiteralPath $script:ConfigPath -Value '{"accounts":[{"id":"Work","display":"Work","color":"#4285F4","mode":"isolated"}]}'
  $savedHome = $env:CODEX_HOME; $savedElectron = $env:CODEX_ELECTRON_USER_DATA_PATH
  try {
    $env:CODEX_HOME = 'original-home'; $env:CODEX_ELECTRON_USER_DATA_PATH = 'original-electron'
    function Start-Process {
      Assert ($env:CODEX_HOME -eq (Get-AccountPaths 'Work').Codex) 'Child CODEX_HOME is not isolated'
      Assert ($env:CODEX_ELECTRON_USER_DATA_PATH -eq (Get-AccountPaths 'Work').Electron) 'Child Electron data is not isolated'
    }
    Start-Account 'Work'
    Assert ($env:CODEX_HOME -eq 'original-home') 'CODEX_HOME leaked after launch'
    Assert ($env:CODEX_ELECTRON_USER_DATA_PATH -eq 'original-electron') 'Electron environment leaked after launch'
    function Start-Process { throw 'Simulated launch failure' }
    Must-Fail { Start-Account 'Work' } 'Launch failure was swallowed'
    Assert ($env:CODEX_HOME -eq 'original-home') 'CODEX_HOME leaked after failed launch'
    Assert ($env:CODEX_ELECTRON_USER_DATA_PATH -eq 'original-electron') 'Electron environment leaked after failed launch'
  } finally {
    $env:CODEX_HOME = $savedHome; $env:CODEX_ELECTRON_USER_DATA_PATH = $savedElectron
  }
  Assert (-not (Test-Path (Join-Path $temp 'auth.json'))) 'Unexpected auth file'
  $shortcutBody = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-AccountShortcutPath' }, $false).Body.GetScriptBlock()
  $shortcut1 = & $shortcutBody ([pscustomobject]@{id='A_B'; display='A:B'})
  $shortcut2 = & $shortcutBody ([pscustomobject]@{id='A_B_2'; display='A?B'})
  Assert ($shortcut1 -ne $shortcut2) 'Different profiles share a desktop shortcut path'
  try {
    $env:CODEX_HOME = 'inherited-profile'; $env:CODEX_ELECTRON_USER_DATA_PATH = 'inherited-electron'
    function Start-Process { $script:MainLaunchHome = $env:CODEX_HOME; $script:MainLaunchElectron = $env:CODEX_ELECTRON_USER_DATA_PATH }
    Start-Account '__main__'
    Assert ([string]::IsNullOrEmpty($script:MainLaunchHome)) 'Main inherited another profile home'
    Assert ([string]::IsNullOrEmpty($script:MainLaunchElectron)) 'Main inherited another Electron profile'
    Assert ($env:CODEX_HOME -eq 'inherited-profile') 'Main did not restore parent environment'
  } finally { $env:CODEX_HOME = $savedHome; $env:CODEX_ELECTRON_USER_DATA_PATH = $savedElectron }
  $detectBody = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ChatGptApp' }, $false).Body.GetScriptBlock()
  $packageDir = Join-Path $temp 'package'
  New-Item -ItemType Directory -Path (Join-Path $packageDir 'app') | Out-Null
  $packageExe = Join-Path $packageDir 'app\Codex.exe'
  Set-Content -LiteralPath $packageExe -Value 'fake executable, never run'
  function Import-Module {}
  function Get-AppxPackage { [pscustomobject]@{InstallLocation=$packageDir; Version='1.0'; PackageFamilyName='test-package'} }
  function Get-AppxPackageManifest { [pscustomobject]@{Package=[pscustomobject]@{Applications=[pscustomobject]@{Application=@([pscustomobject]@{Id='App'})}}} }
  $script:AppCache = $null
  Assert ((& $detectBody).Exe -eq $packageExe) 'app\Codex.exe was not detected'
  $electronExe = Join-Path $packageDir 'app\ChatGPT.exe'
  Set-Content -LiteralPath $electronExe -Value 'fake Electron executable, never run'
  $script:AppCache = $null
  Assert ((& $detectBody).Exe -eq $electronExe) 'Codex wrapper was preferred over the real Electron executable'
  Remove-Item -LiteralPath $electronExe
  Remove-Item -LiteralPath $packageExe
  $oldLocal = $env:LOCALAPPDATA; $oldPrograms = $env:ProgramFiles
  try {
    $env:LOCALAPPDATA = Join-Path $temp 'local'; $env:ProgramFiles = Join-Path $temp 'programs'
    $installerDir = Join-Path $env:LOCALAPPDATA 'Programs\Codex'
    New-Item -ItemType Directory -Path $installerDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $installerDir 'Codex.exe') -Value 'fake executable, never run'
    $detected = & $detectBody
    Assert ($detected.Kind -eq 'Installer') ("Unusable Store package blocked standalone fallback: " + ($detected | ConvertTo-Json -Compress))
  } finally { $env:LOCALAPPDATA = $oldLocal; $env:ProgramFiles = $oldPrograms }
  $liveStrings = @($tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Text -match '[\p{IsHiragana}\p{IsKatakana}\p{IsCJKUnifiedIdeographs}]' })
  Assert ($liveStrings.Count -eq 0) 'Japanese UI strings remain'
  Assert (-not (Test-Path (Join-Path $PSScriptRoot 'install.ps1'))) 'Online installer remains'
  Assert (-not (Test-Path (Join-Path $PSScriptRoot 'publish.ps1'))) 'Obsolete publishing utility remains'
  $runningBody = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-RunningAccountIds' }, $false).Body.GetScriptBlock()
  function Get-CimInstance { throw 'Simulated process-query failure' }
  Must-Fail { & $runningBody } 'Process-query failure was silently ignored'
  function Get-CimInstance { [pscustomobject]@{Name='Codex.exe'; CommandLine=$null} }
  Must-Fail { & $runningBody } 'Unreadable process command line was treated as a closed profile'
  Write-Host 'PASS: syntax, reserved/unsafe paths, profile CRUD/locking/orphans, duplicate names, invalid config, backups, Main/isolated environments, discovery/cache/fallback, process safety, English UI, no installer/publisher.'
} finally {
  # The exact test directory is generated directly under this script folder.
  if ((Split-Path -Parent ([IO.Path]::GetFullPath($temp))) -ne [IO.Path]::GetFullPath($PSScriptRoot)) { throw 'Unsafe test cleanup path' }
  Remove-Item -LiteralPath $temp -Recurse -Force
}
