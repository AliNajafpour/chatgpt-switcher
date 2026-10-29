$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'ChatGPT-Switcher.ps1'), [ref]$tokens, [ref]$errors)
foreach ($fn in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
  . ([scriptblock]::Create($fn.Extent.Text))
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
function Ensure-Gui { [Windows.Forms.Application]::EnableVisualStyles() }
function Set-JumpList {}
function Get-AppIconPath { return $null }
function Get-RunningAccountIds { return $script:TestRunning }
$script:MainId = '__main__'; $script:MainLabel = 'Main (existing login)'
$script:TestRunning = @()
$script:TestRows = @(1..30 | ForEach-Object { [pscustomobject]@{id=('p{0:00}' -f $_); display=('Profile {0:00}' -f $_); color='#4285F4'; mode='isolated'} })
function Get-Config { [pscustomobject]@{accounts=$script:TestRows} }
$script:UiFailure = $null; $script:TickDone = $false
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 100
$timer.add_Tick({
  if ($script:TickDone -or -not $script:PickerForm -or -not $script:PickerForm.Visible) { return }
  $script:TickDone = $true
  try {
    $refresh = @($script:PickerForm.Controls.Find('RefreshButton', $true))
    Assert ($refresh.Count -eq 1) 'Picker needs a visible Refresh button'
    Assert $script:PickerPanel.AutoScroll 'Account list does not scroll'
    Assert ($script:PickerPanel.Height -le 520) 'Account list is not bounded'
    $oldRow = $script:PickerPanel.Controls.Find('Account_p01', $false)[0]
    $oldImage = $oldRow.Image
    $script:TestRunning = @('p01')
    $refresh[0].PerformClick()
    $newRow = $script:PickerPanel.Controls.Find('Account_p01', $false)[0]
    Assert ($newRow.Text -match 'Running') 'Refresh does not update running state'
    Assert $oldRow.IsDisposed 'Refresh did not dispose the old row'
    $imageDisposed = $false
    $imageProbe = New-Object IO.MemoryStream
    try { $oldImage.Save($imageProbe, [Drawing.Imaging.ImageFormat]::Png) } catch { $imageDisposed = $true }
    finally { $imageProbe.Dispose() }
    Assert $imageDisposed 'Refresh did not dispose the old avatar'
    Assert ($script:PickerPanel.Controls.Count -eq 32) 'Refresh lost account rows or duplicated controls'
    function Get-RunningAccountIds { throw 'Simulated process-query failure' }
    $refresh[0].PerformClick()
    Assert ($script:PickerStatus.Text -match 'unavailable') 'Refresh failure has no visible status'
    Assert ($script:PickerPanel.Controls.Find('Account_p01', $false).Count -eq 1) 'Status failure hid accounts'
  } catch { $script:UiFailure = $_ }
  finally { $script:PickerForm.Close() }
})
try {
  $timer.Start()
  Show-Picker
  if ($script:UiFailure) { throw $script:UiFailure }
  Assert $script:TickDone 'UI test callback did not run'
} finally { $timer.Stop(); $timer.Dispose() }

$script:TrayMutexName = 'Local\CodexSwitcher.SelfCheck.' + [guid]::NewGuid().ToString('N')
$mutex = New-Object Threading.Mutex($false, $script:TrayMutexName)
try {
  function Ensure-Gui { throw 'Duplicate tray must return before opening GUI' }
  function Write-Log {}
  Start-Tray
} finally { $mutex.Dispose() }

$temp = Join-Path $PSScriptRoot ('.self-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  $script:ScriptPath = Join-Path $PSScriptRoot 'ChatGPT-Switcher.ps1'
  function Get-TrayStartupPath { Join-Path $temp 'Codex Switcher (tray).lnk' }
  $legacy = Join-Path $temp 'ChatGPT Switcher (tray).lnk'
  Set-Content -LiteralPath $legacy -Value 'legacy shortcut placeholder'
  $link = Install-TrayAutoStart
  Assert (Test-Path -LiteralPath $link) 'Startup enable did not create a shortcut'
  Assert (-not (Test-Path -LiteralPath $legacy)) 'Startup did not migrate legacy shortcut'
  $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
  Assert ($shortcut.Arguments -match '\s-Tray\b') 'Startup does not launch tray mode'
  Install-TrayAutoStart -Disable | Out-Null
  Assert (-not (Test-Path -LiteralPath $link)) 'Startup disable did not remove shortcut'
  Write-Host 'PASS: bounded picker, refresh/status, row/avatar disposal, single tray, startup enable/disable.'
} finally {
  if ((Split-Path -Parent ([IO.Path]::GetFullPath($temp))) -ne [IO.Path]::GetFullPath($PSScriptRoot)) { throw 'Unsafe cleanup path' }
  Remove-Item -LiteralPath $temp -Recurse -Force
}
