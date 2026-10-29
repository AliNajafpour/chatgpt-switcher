#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Invoke-Launcher([string]$Path, [string]$Arguments) {
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = $env:ComSpec
  $info.Arguments = '/d /s /c ""{0}" {1}"' -f $Path, $Arguments
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $info
  try {
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(20000)) {
      & taskkill.exe /PID $process.Id /T /F | Out-Null
      throw "Launcher did not return: $Arguments"
    }
    [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result; Error = $stderr.Result }
  } finally { $process.Dispose() }
}

$launcher = Join-Path $PSScriptRoot 'ChatGPT-Switcher.cmd'
$version = Invoke-Launcher $launcher '-Version'
Assert ($version.ExitCode -eq 0) 'Version command failed'
Assert ($version.Output -match 'ChatGPT-Switcher \S+') 'Version output was lost by the CMD launcher'
$invalid = Invoke-Launcher $launcher '-UnknownSwitcherParameter'
Assert ($invalid.ExitCode -ne 0) 'Invalid parameter returned success'
Assert (($invalid.Output + $invalid.Error) -match 'UnknownSwitcherParameter') 'Invalid parameter error was lost'
$invalidCombo = Invoke-Launcher $launcher '-Tray -Version'
Assert ($invalidCombo.ExitCode -ne 0) 'Conflicting tray command returned success'
Assert (($invalidCombo.Output + $invalidCombo.Error) -match 'one primary operation') 'Conflicting tray command did not return its CLI error'

# A stand-in script exercises every CLI flag without touching accounts or opening UI.
$temp = Join-Path $PSScriptRoot ('.cli-self-check with spaces-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  Copy-Item -LiteralPath $launcher -Destination $temp
  Set-Content -LiteralPath (Join-Path $temp 'ChatGPT-Switcher.ps1') -Encoding UTF8 -Value @'
Write-Output ('forwarded:' + ($args -join '|'))
[Console]::Error.WriteLine('expected stderr')
exit 23
'@
  foreach ($flag in @('-Version', '-List', '-Diagnose', '-Add', '-Remove', '-Launch', '-Setup', '-AutoStartTray', '-NoAutoStartTray')) {
    $result = Invoke-Launcher (Join-Path $temp 'ChatGPT-Switcher.cmd') ($flag + ' "Account With Spaces"')
    Assert ($result.ExitCode -eq 23) "$flag lost the script exit status"
    Assert ($result.Output -match ([regex]::Escape('forwarded:' + $flag + '|Account With Spaces'))) "$flag lost output or quoted arguments"
    Assert ($result.Error -match 'expected stderr') "$flag lost stderr"
  }
  $result = Invoke-Launcher (Join-Path $temp 'ChatGPT-Switcher.cmd') '-Tray -UnknownSwitcherParameter'
  Assert ($result.ExitCode -eq 23) 'Tray with extra flags did not use the synchronous CLI path'
} finally {
  Assert ((Split-Path -Parent $temp) -eq $PSScriptRoot) 'Unexpected temporary directory'
  Remove-Item -LiteralPath $temp -Recurse -Force
}
Write-Host 'CLI self-check passed.'
