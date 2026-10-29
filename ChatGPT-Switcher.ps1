#Requires -Version 5.1
<#
.SYNOPSIS
  Launch separate desktop app accounts on Windows.
.DESCRIPTION
  Each account has separate Electron data and CODEX_HOME.
  Run without arguments for the picker. Options: -Launch name, -Add name,
  -Remove name, -List, -Setup, -Tray, -AutoStartTray, -Diagnose, -Version.
  Removing an account deletes its local data, including local projects/chats.
  Shared mode and online installation have been removed.
#>
param(
  [string]$Launch,
  [string]$Add,
  [string]$Remove,
  [switch]$List,
  [switch]$Setup,
  [switch]$Tray,
  [switch]$AutoStartTray,
  [switch]$Diagnose,
  [switch]$NoShortcut,
  [switch]$Version
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$script:AppVersion = '1.3.0'
$script:AppId      = 'Alyawmu.ChatGPTSwitcher'   # taskbar grouping + jump list identity
$script:ScriptPath = $MyInvocation.MyCommand.Path
$script:Root       = Join-Path $env:USERPROFILE 'ChatGPT-Accounts'
$script:ConfigPath = Join-Path $script:Root 'accounts.json'
$script:LogPath    = Join-Path $script:Root 'switcher.log'
$script:MainId     = '__main__'
$script:MainLabel  = 'Main (existing login)'
$script:Palette    = @('#4285F4','#34A853','#EA4335','#F9AB00','#A142F4','#F538A0','#12B5CB','#FF6D01')
$script:AppCache   = $null
$script:Gui        = $false


function Write-Log {
  param([string]$Message)
  try {
    New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
    Add-Content -Path $script:LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
  } catch {}
}

function Ensure-Gui {
  if ($script:Gui) { return }
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  [System.Windows.Forms.Application]::EnableVisualStyles()
  $script:Gui = $true
  Set-ProcessAppId   # taskbar button groups under the pinned switcher icon
}

function Get-DialogOwner {
  $f = $script:PickerForm
  if ($f -and -not $f.IsDisposed -and $f.Visible) { return $f }
  return $null
}

function Show-Message {
  param([string]$Text, [string]$Title = 'ChatGPT Account Switcher', [string]$Icon = 'Information')
  Ensure-Gui
  $owner = Get-DialogOwner
  if ($owner) { [void][System.Windows.Forms.MessageBox]::Show($owner, $Text, $Title, 'OK', $Icon) }
  else        { [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', $Icon) }
}

function Ask-YesNo {
  param([string]$Text, [string]$Title = 'ChatGPT Account Switcher')
  Ensure-Gui
  $owner = Get-DialogOwner
  if ($owner) { $r = [System.Windows.Forms.MessageBox]::Show($owner, $Text, $Title, 'YesNo', 'Question') }
  else        { $r = [System.Windows.Forms.MessageBox]::Show($Text, $Title, 'YesNo', 'Question') }
  return ($r -eq 'Yes')
}

function Show-InputDialog {
  param([string]$Prompt, [string]$Title = 'ChatGPT Account Switcher', [string]$Default = '')
  Ensure-Gui
  $owner = Get-DialogOwner

  $dlg = New-Object System.Windows.Forms.Form
  $dlg.Text = $Title
  $dlg.FormBorderStyle = 'FixedDialog'
  $dlg.MaximizeBox = $false
  $dlg.MinimizeBox = $false
  $dlg.ShowInTaskbar = $false
  $dlg.TopMost = $true
  $dlg.StartPosition = $(if ($owner) { 'CenterParent' } else { 'CenterScreen' })
  $dlg.ClientSize = New-Object System.Drawing.Size(420, 130)
  $dlg.Font = New-Object System.Drawing.Font('Segoe UI', 10)

  $lbl = New-Object System.Windows.Forms.Label
  $lbl.Text = $Prompt
  $lbl.AutoSize = $false
  $lbl.Location = New-Object System.Drawing.Point(14, 12)
  $lbl.Size = New-Object System.Drawing.Size(392, 40)

  $tb = New-Object System.Windows.Forms.TextBox
  $tb.Location = New-Object System.Drawing.Point(14, 56)
  $tb.Size = New-Object System.Drawing.Size(392, 28)
  $tb.Text = $Default

  $ok = New-Object System.Windows.Forms.Button
  $ok.Text = 'OK'
  $ok.Size = New-Object System.Drawing.Size(90, 30)
  $ok.Location = New-Object System.Drawing.Point(216, 92)
  $ok.DialogResult = 'OK'

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = 'Cancel'
  $cancel.Size = New-Object System.Drawing.Size(90, 30)
  $cancel.Location = New-Object System.Drawing.Point(316, 92)
  $cancel.DialogResult = 'Cancel'

  $dlg.Controls.AddRange(@($lbl, $tb, $ok, $cancel))
  $dlg.AcceptButton = $ok
  $dlg.CancelButton = $cancel
  $dlg.add_Shown({ $this.Activate(); $tb.Focus(); $tb.SelectAll() })

  $result = $(if ($owner) { $dlg.ShowDialog($owner) } else { $dlg.ShowDialog() })
  $text = $tb.Text
  $dlg.Dispose()
  if ($result -eq 'OK') { return $text }
  return $null
}

function Get-SafeName {
  param([string]$Name)
  $invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ''
  $re = '[{0}]' -f [regex]::Escape($invalid)
  $s = ($Name -replace $re, '_').Trim()
  $s = $s -replace '\s+', '_'
  if ([string]::IsNullOrWhiteSpace($s)) { $s = 'account' }
  return $s
}


function Get-ChatGptApp {
  if ($script:AppCache -and $script:AppCache.Exe -and (Test-Path -LiteralPath $script:AppCache.Exe -PathType Leaf)) { return $script:AppCache }
  $script:AppCache = $null

  $pkg = $null
  $storeApp = $null
  try {
    if ($PSVersionTable.PSEdition -eq 'Core') { Import-Module Appx -UseWindowsPowerShell -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
      Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
  } catch {}

  if ($pkg) {
    $loc = $pkg.InstallLocation
    $exe = $null
    foreach ($cand in @((Join-Path $loc 'Codex.exe'), (Join-Path $loc 'app\Codex.exe'), (Join-Path $loc 'ChatGPT.exe'), (Join-Path $loc 'app\ChatGPT.exe'))) {
      if (Test-Path -LiteralPath $cand) { $exe = $cand; break }
    }
    if (-not $exe) {
      $found = Get-ChildItem -LiteralPath $loc -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('Codex.exe', 'ChatGPT.exe') } | Select-Object -First 1
      if ($found) { $exe = $found.FullName }
    }
    $appId = $null
    try {
      $manifest = Get-AppxPackageManifest -Package $pkg
      $appId = @($manifest.Package.Applications.Application)[0].Id
    } catch {}
    $storeApp = [pscustomobject]@{
      Kind              = 'Store'
      Exe               = $exe
      PackageFamilyName = $pkg.PackageFamilyName
      AppId             = $appId
      Version           = $pkg.Version
      InstallLocation   = $loc
    }
    if ($exe) { $script:AppCache = $storeApp; return $script:AppCache }
  }

  foreach ($c in @(
      (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe'),
      (Join-Path $env:LOCALAPPDATA 'Programs\ChatGPT\ChatGPT.exe'),
      (Join-Path $env:ProgramFiles 'ChatGPT\ChatGPT.exe'))) {
    if (Test-Path -LiteralPath $c) {
      $script:AppCache = [pscustomobject]@{
        Kind = 'Installer'; Exe = $c; PackageFamilyName = $null; AppId = $null
        Version = (Get-Item -LiteralPath $c).VersionInfo.ProductVersion
        InstallLocation = (Split-Path -Parent $c)
      }
      return $script:AppCache
    }
  }
  if ($storeApp) { $script:AppCache = $storeApp; return $script:AppCache }
  return $null
}


function Get-Config {
  $cfg = $null
  $null = Get-AccountPaths '_config_check'
  if (Test-Path -LiteralPath $script:ConfigPath) {
    try {
      $raw = [System.IO.File]::ReadAllText($script:ConfigPath, [System.Text.Encoding]::UTF8)
      $cfg = $raw | ConvertFrom-Json
    } catch { throw "Cannot read accounts.json. Restore a valid backup before continuing. $_" }
    if (-not $cfg -or -not ($cfg -is [pscustomobject]) -or
        -not ($cfg.PSObject.Properties.Name -contains 'accounts')) {
      throw 'Invalid accounts.json format. Restore a valid backup before continuing.'
    }
  }
  if (-not $cfg) { $cfg = [pscustomobject]@{ accounts = @() } }
  if (-not ($cfg.PSObject.Properties.Name -contains 'accounts')) {
    $cfg | Add-Member -NotePropertyName accounts -NotePropertyValue @() -Force
  }
  $cfg.accounts = @($cfg.accounts | Where-Object { $_ -ne $null })
  foreach ($account in $cfg.accounts) {
    $null = Get-AccountPaths $account.id
    if (-not ($account.display -is [string]) -or [string]::IsNullOrWhiteSpace($account.display) -or
        -not ($account.color -is [string]) -or $account.color -notmatch '^#[0-9a-fA-F]{6}$') {
      throw "Invalid name or color for profile $($account.id). Restore or correct accounts.json."
    }
  }
  return $cfg
}

function Save-Config {
  param($Config)
  $null = Get-AccountPaths '_config_check'
  New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
  $Config.accounts = @($Config.accounts)
  $json = ConvertTo-Json -InputObject $Config -Depth 5
  $tempPath = $script:ConfigPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
  try {
    [IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $script:ConfigPath) {
      [IO.File]::Replace($tempPath, $script:ConfigPath, ($script:ConfigPath + '.bak'))
    } else { [IO.File]::Move($tempPath, $script:ConfigPath) }
  } finally {
    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
  }
}

function Get-AccountPaths {
  param([string]$Id)
  if ([string]::IsNullOrWhiteSpace($Id) -or $Id -eq $script:MainId -or
      $Id -in @('accounts.json', 'accounts.json.bak', 'accounts.lock', 'switcher.log') -or
      $Id -match '[<>:"/\\|?*\x00-\x1f]' -or $Id -match '[. ]$' -or
      $Id -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])($|\.)') {
    throw 'Invalid account ID. Use a plain folder name, not a path or reserved Windows name.'
  }
  $root = [IO.Path]::GetFullPath($script:Root).TrimEnd('\')
  $base = [IO.Path]::GetFullPath((Join-Path $root $Id))
  if (-not $base.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Account path is outside the data folder.' }
  foreach ($path in @($root, $base, (Join-Path $base 'electron'), (Join-Path $base 'codex'))) {
    if (Test-Path -LiteralPath $path) {
      $item = Get-Item -LiteralPath $path -Force
      if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Account paths must be ordinary directories: $path"
      }
    }
  }
  return [pscustomobject]@{
    Base     = $base
    Electron = (Join-Path $base 'electron')
    Codex    = (Join-Path $base 'codex')
  }
}

function Find-Account {
  param([string]$Key)   # Accept an ID or display name.
  $cfg = Get-Config
  $acc = $cfg.accounts | Where-Object { $_.id -eq $Key } | Select-Object -First 1
  if (-not $acc) { $acc = $cfg.accounts | Where-Object { $_.display -eq $Key } | Select-Object -First 1 }
  if (-not $acc) { $acc = $cfg.accounts | Where-Object { $_.id -eq (Get-SafeName $Key) } | Select-Object -First 1 }
  return $acc
}

function Add-Account {
  param([string]$Display, [switch]$SkipShortcut)
  $null = Get-AccountPaths '_config_check'
  New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
  $lock = [IO.File]::Open((Join-Path $script:Root 'accounts.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    $Display = $Display.Trim()
    if ([string]::IsNullOrWhiteSpace($Display)) { throw 'Account name cannot be empty.' }
    $cfg = Get-Config
    if ($cfg.accounts | Where-Object { $_.display -eq $Display }) { throw "Account $Display is already registered." }
    $id = Get-SafeName $Display
    $n = 2
    while (($cfg.accounts | Where-Object { $_.id -eq $id }) -or (Test-Path -LiteralPath (Get-AccountPaths $id).Base)) {
      $id = (Get-SafeName $Display) + "_$n"; $n++
    }
    $p = Get-AccountPaths $id
    $color = $script:Palette[ $cfg.accounts.Count % $script:Palette.Count ]
    $acc = [pscustomobject]@{
      id      = $id
      display = $Display
      color   = $color
      created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
      mode    = 'isolated'
    }
    $cfg.accounts = @($cfg.accounts) + @($acc)
    Save-Config $cfg
    New-Item -ItemType Directory -Force -Path $p.Electron, $p.Codex | Out-Null
    Write-Log "account added: $id ($Display)"
    if (-not $SkipShortcut) { New-AccountShortcut -Account $acc | Out-Null }
    Set-JumpList
    return $acc
  } finally { $lock.Dispose() }
}

function Remove-Account {
  param([string]$Key)
  $null = Get-AccountPaths '_config_check'
  New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
  $lock = [IO.File]::Open((Join-Path $script:Root 'accounts.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    $acc = Find-Account $Key
    if (-not $acc) { throw "Account $Key was not found." }
    if ((Get-RunningAccountIds) -contains $acc.id) { throw "ChatGPT is running for $($acc.display). Close it first." }
    $p = Get-AccountPaths $acc.id
    if (Test-Path -LiteralPath $p.Base) {
      $links = Get-ChildItem -LiteralPath $p.Base -Recurse -Force -ErrorAction Stop |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
      if ($links) { throw 'Remove linked files/folders from this account before deleting it.' }
      Remove-Item -LiteralPath $p.Base -Recurse -Force
    }
    $cfg = Get-Config
    $cfg.accounts = @($cfg.accounts | Where-Object { $_.id -ne $acc.id })
    Save-Config $cfg
    $lnk = Get-AccountShortcutPath $acc
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
    Write-Log "account removed: $($acc.id)"
    Set-JumpList
  } finally { $lock.Dispose() }
}

function Rename-Account {
  param([string]$Key, [string]$NewDisplay)
  $null = Get-AccountPaths '_config_check'
  New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
  $lock = [IO.File]::Open((Join-Path $script:Root 'accounts.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    $acc = Find-Account $Key
    if (-not $acc) { throw "Account $Key was not found." }
    $NewDisplay = $NewDisplay.Trim()
    if ([string]::IsNullOrWhiteSpace($NewDisplay)) { return }
    $old = Get-AccountShortcutPath $acc
    $cfg = Get-Config
    if ($cfg.accounts | Where-Object { $_.id -ne $acc.id -and $_.display -eq $NewDisplay }) { throw "Account $NewDisplay is already registered." }
    foreach ($a in $cfg.accounts) { if ($a.id -eq $acc.id) { $a.display = $NewDisplay } }
    Save-Config $cfg
    if (Test-Path -LiteralPath $old) {
      Remove-Item -LiteralPath $old -Force
      New-AccountShortcut -Account (Find-Account $acc.id) | Out-Null
    }
    Set-JumpList
  } finally { $lock.Dispose() }
}


function Get-RunningAccountIds {
  $ids = @()
  $procs = @()
  try { $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe' OR Name = 'Codex.exe'" -ErrorAction Stop) }
  catch { throw 'Cannot inspect running desktop processes. Account data will not be deleted. Check Windows permissions and try again.' }
  if ($procs | Where-Object { [string]::IsNullOrWhiteSpace($_.CommandLine) }) {
    throw 'A desktop process has an unreadable command line. Close its window before managing profiles.'
  }
  if ($procs.Count -eq 0) { return $ids }
  $cfg = Get-Config
  foreach ($acc in $cfg.accounts) {
    $p = Get-AccountPaths $acc.id
    $hit = $procs | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($p.Electron, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1
    if ($hit) { $ids += $acc.id }
  }
  $mainHit = $procs | Where-Object {
    $_.CommandLine -and ($_.CommandLine -notmatch '--user-data-dir=') -and ($_.CommandLine -notmatch '--type=')
  } | Select-Object -First 1
  if ($mainHit) { $ids += $script:MainId }
  return $ids
}

function Start-Account {
  param([string]$Id)
  $app = Get-ChatGptApp
  if (-not $app) { throw 'Desktop app was not found. Install the official desktop app first.' }

  if ($Id -eq $script:MainId) {
    $previousHome = $env:CODEX_HOME
    $previousElectron = $env:CODEX_ELECTRON_USER_DATA_PATH
    try {
      Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
      Remove-Item Env:CODEX_ELECTRON_USER_DATA_PATH -ErrorAction SilentlyContinue
      if ($app.Kind -eq 'Store' -and $app.AppId) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ("shell:AppsFolder\{0}!{1}" -f $app.PackageFamilyName, $app.AppId)
      } else {
        Start-Process -FilePath $app.Exe
      }
    } finally {
      $env:CODEX_HOME = $previousHome
      $env:CODEX_ELECTRON_USER_DATA_PATH = $previousElectron
    }
    Write-Log 'launched: main'
    return
  }

  $acc = Find-Account $Id
  if (-not $acc) { throw "Account $Id is not registered." }

  if ($acc.mode -eq 'shared') { throw 'Shared mode has been removed. Add a new isolated account and sign in there.' }

  if (-not $app.Exe) { throw "Desktop executable was not found in $($app.InstallLocation)." }

  $p = Get-AccountPaths $acc.id
  New-Item -ItemType Directory -Force -Path $p.Electron, $p.Codex | Out-Null

  $previousHome = $env:CODEX_HOME
  $previousElectron = $env:CODEX_ELECTRON_USER_DATA_PATH
  $env:CODEX_HOME = $p.Codex
  $env:CODEX_ELECTRON_USER_DATA_PATH = $p.Electron
  $arg = '--user-data-dir="' + $p.Electron + '"'

  try {
    Start-Process -FilePath $app.Exe -ArgumentList $arg -WorkingDirectory $p.Base
    Write-Log "launched: $($acc.id) via direct exe"
  } catch {
    Write-Log "direct launch failed: $_"
    if ($app.Kind -eq 'Store' -and $app.AppId -and (Get-Command Invoke-CommandInDesktopPackage -ErrorAction SilentlyContinue)) {
      Invoke-CommandInDesktopPackage -PackageFamilyName $app.PackageFamilyName -AppId $app.AppId -Command $app.Exe -Args $arg -PreventBreakaway
      Write-Log "launched: $($acc.id) via Invoke-CommandInDesktopPackage"
    } else { throw }
  } finally {
    $env:CODEX_HOME = $previousHome
    $env:CODEX_ELECTRON_USER_DATA_PATH = $previousElectron
  }
}


function Get-PowerShellExe {
  return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}


function Ensure-Native {
  if ('CGS.Native' -as [type]) { return $true }
  $code = @'
using System;
using System.Runtime.InteropServices;
namespace CGS {
  [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class CShellLink { }
  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
  interface IShellLinkW {
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder f, int c, IntPtr fd, int fl);
    void GetIDList(out IntPtr ppidl); void SetIDList(IntPtr pidl);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder n, int c);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string n);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder d, int c);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string d);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder a, int c);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string a);
    void GetHotkey(out short h); void SetHotkey(short h);
    void GetShowCmd(out int s); void SetShowCmd(int s);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder p, int c, out int i);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string p, int i);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string r, int dw);
    void Resolve(IntPtr hwnd, int fl); void SetPath([MarshalAs(UnmanagedType.LPWStr)] string f);
  }
  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("0000010b-0000-0000-C000-000000000046")]
  interface IPersistFile {
    void GetClassID(out Guid c); [PreserveSig] int IsDirty();
    void Load([MarshalAs(UnmanagedType.LPWStr)] string f, int m);
    void Save([MarshalAs(UnmanagedType.LPWStr)] string f, [MarshalAs(UnmanagedType.Bool)] bool r);
    void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string f);
    void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string f);
  }
  [StructLayout(LayoutKind.Sequential)] struct PROPERTYKEY { public Guid fmtid; public uint pid; }
  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99")]
  interface IPropertyStore {
    void GetCount(out uint c); void GetAt(uint i, out PROPERTYKEY k);
    void GetValue(ref PROPERTYKEY k, out PROPVARIANT v);
    void SetValue(ref PROPERTYKEY k, ref PROPVARIANT v); void Commit();
  }
  [StructLayout(LayoutKind.Explicit, Size = 24)] struct PROPVARIANT {
    [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p;
  }
  public static class Native {
    [DllImport("shell32.dll")] static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string id);
    [DllImport("propsys.dll")] static extern int InitPropVariantFromString([MarshalAs(UnmanagedType.LPWStr)] string s, out PROPVARIANT pv);
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PROPVARIANT pv);
    public static void SetProcessAppId(string id) { SetCurrentProcessExplicitAppUserModelID(id); }
    public static void SetShortcutAppId(string lnk, string id) {
      var sl = (IShellLinkW)new CShellLink();
      var pf = (IPersistFile)sl;
      pf.Load(lnk, 2); // STGM_READWRITE
      var ps = (IPropertyStore)sl;
      var key = new PROPERTYKEY(); key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"); key.pid = 5;
      PROPVARIANT pv; InitPropVariantFromString(id, out pv);
      ps.SetValue(ref key, ref pv); ps.Commit();
      pf.Save(lnk, true); PropVariantClear(ref pv);
    }
  }
}
'@
  try { Add-Type -TypeDefinition $code -ErrorAction Stop; return $true }
  catch { Write-Log ("native load failed: {0}" -f $_.Exception.Message); return $false }
}

function Set-ProcessAppId {
  try { if (Ensure-Native) { [CGS.Native]::SetProcessAppId($script:AppId) } } catch { Write-Log "SetProcessAppId: $_" }
}

function Set-ShortcutAppId {
  param([string]$LnkPath)
  try { if (Ensure-Native) { [CGS.Native]::SetShortcutAppId($LnkPath, $script:AppId) } } catch { Write-Log "SetShortcutAppId: $_" }
}

function Set-JumpList {
  try {
    Set-ProcessAppId
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    $ps   = Get-PowerShellExe
    $icon = Get-AppIconPath
    $jl = New-Object System.Windows.Shell.JumpList
    $jl.ShowRecentCategory = $false
    $jl.ShowFrequentCategory = $false

    $rows = @()
    $rows += [pscustomobject]@{ id = $script:MainId; label = 'Main' }
    foreach ($a in (Get-Config).accounts) { $rows += [pscustomobject]@{ id = $a.id; label = $a.display } }

    foreach ($r in $rows) {
      $t = New-Object System.Windows.Shell.JumpTask
      $t.Title           = $r.label
      $t.CustomCategory  = 'Accounts'
      $t.ApplicationPath = $ps
      $t.Arguments       = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Launch "{1}"' -f $script:ScriptPath, $r.id)
      if ($icon) { $t.IconResourcePath = $icon }
      $t.Description = ("Open ChatGPT as {0}" -f $r.label)
      $jl.JumpItems.Add($t)
    }

    $open = New-Object System.Windows.Shell.JumpTask
    $open.Title = 'Open account picker'
    $open.ApplicationPath = $ps
    $open.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script:ScriptPath)
    if ($icon) { $open.IconResourcePath = $icon }
    $jl.JumpItems.Add($open)

    $jl.Apply()
    Write-Log ("jumplist applied: {0} items" -f $jl.JumpItems.Count)
  } catch { Write-Log ("jumplist skipped: {0}" -f $_.Exception.Message) }
}

function New-Shortcut {
  param([string]$LnkPath, [string]$Arguments, [string]$IconPath, [string]$Description)
  $dir = Split-Path -Parent $LnkPath
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $wsh = New-Object -ComObject WScript.Shell
  $lnk = $wsh.CreateShortcut($LnkPath)
  $lnk.TargetPath = Get-PowerShellExe
  $lnk.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" {1}' -f $script:ScriptPath, $Arguments)
  $lnk.WorkingDirectory = Split-Path -Parent $script:ScriptPath
  $lnk.WindowStyle = 7   # Minimize the console window.
  if ($IconPath -and (Test-Path -LiteralPath $IconPath)) { $lnk.IconLocation = "$IconPath,0" }
  if ($Description) { $lnk.Description = $Description }
  $lnk.Save()
  return $LnkPath
}

function Get-AppIconPath {
  $app = Get-ChatGptApp
  if ($app -and $app.Exe) { return $app.Exe }
  return $null
}

function Get-AccountShortcutPath {
  param($Account)
  $null = Get-AccountPaths $Account.id
  $desktop = [Environment]::GetFolderPath('Desktop')
  return (Join-Path $desktop ('ChatGPT - {0}.lnk' -f $Account.id))
}

function New-AccountShortcut {
  param($Account)
  $lnk = Get-AccountShortcutPath $Account
  New-Shortcut -LnkPath $lnk -Arguments ('-Launch "{0}"' -f $Account.id) -IconPath (Get-AppIconPath) -Description ("Launch ChatGPT as {0}" -f $Account.display)
  Write-Log "shortcut created: $lnk"
  return $lnk
}

function New-PickerShortcuts {
  $icon = Get-AppIconPath
  $desktop = [Environment]::GetFolderPath('Desktop')
  $programs = Join-Path ([Environment]::GetFolderPath('Programs')) 'ChatGPT Account Switcher'
  $made = @()
  $made += New-Shortcut -LnkPath (Join-Path $desktop 'ChatGPT Account Switcher.lnk') -Arguments '' -IconPath $icon -Description 'Choose an account to launch ChatGPT'
  $made += New-Shortcut -LnkPath (Join-Path $programs 'ChatGPT Account Switcher.lnk') -Arguments '' -IconPath $icon -Description 'Choose an account to launch ChatGPT'
  $made += New-Shortcut -LnkPath (Join-Path $programs 'ChatGPT Switcher (tray).lnk') -Arguments '-Tray' -IconPath $icon -Description 'Run in the tray; right-click to switch accounts'
  foreach ($m in $made) { Set-ShortcutAppId -LnkPath $m }
  Set-JumpList
  return $made
}

function Install-TrayAutoStart {
  $startup = [Environment]::GetFolderPath('Startup')
  return New-Shortcut -LnkPath (Join-Path $startup 'ChatGPT Switcher (tray).lnk') -Arguments '-Tray' -IconPath (Get-AppIconPath) -Description 'ChatGPT Account Switcher (tray)'
}


function New-AvatarImage {
  param([string]$Hex, [string]$Text, [int]$Size = 28)
  Ensure-Gui
  $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
  $color = [System.Drawing.ColorTranslator]::FromHtml($Hex)
  $brush = New-Object System.Drawing.SolidBrush($color)
  $g.FillEllipse($brush, 0, 0, $Size - 1, $Size - 1)
  $font = New-Object System.Drawing.Font('Segoe UI', [float]($Size * 0.45), [System.Drawing.FontStyle]::Bold)
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $rect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
  $g.DrawString($Text, $font, [System.Drawing.Brushes]::White, $rect, $fmt)
  $g.Dispose()
  return $bmp
}

function Invoke-AddAccountFlow {
  Ensure-Gui
  $name = Show-InputDialog -Prompt 'Enter an account name (for example, Work or Personal)' -Title 'Add account'
  if ([string]::IsNullOrWhiteSpace($name)) { return $null }
  try {
    $acc = Add-Account -Display $name
  } catch {
    Show-Message $_.Exception.Message 'Error' 'Error'
    return $null
  }
  if (Ask-YesNo ("Added {0} and created a desktop shortcut.`n`nLaunch now to sign in?" -f $acc.display)) {
    try { Start-Account $acc.id } catch { Show-Message $_.Exception.Message 'Error' 'Error' }
  }
  return $acc
}

function Show-Picker {
  Ensure-Gui
  Set-JumpList

  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'ChatGPT Account Switcher'
  $form.StartPosition = 'CenterScreen'
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false
  $form.MinimizeBox = $false
  $form.ShowInTaskbar = $true
  $form.KeyPreview = $true
  $form.add_Shown({ $this.Activate(); $this.TopMost = $true; $this.TopMost = $false; $this.BringToFront() })
  $form.AutoSize = $true
  $form.AutoSizeMode = 'GrowAndShrink'
  $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
  $form.BackColor = [System.Drawing.Color]::White
  $form.Padding = New-Object System.Windows.Forms.Padding(12)
  $iconPath = Get-AppIconPath
  if ($iconPath) { try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath) } catch {} }

  $script:PickerForm = $form

  $header = New-Object System.Windows.Forms.Label
  $header.Text = 'Choose an account'
  $header.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
  $header.AutoSize = $true
  $header.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 8)

  $panel = New-Object System.Windows.Forms.FlowLayoutPanel
  $panel.FlowDirection = 'TopDown'
  $panel.WrapContents = $false
  $panel.AutoSize = $true
  $panel.AutoSizeMode = 'GrowAndShrink'
  $script:PickerPanel = $panel

  $footer = New-Object System.Windows.Forms.FlowLayoutPanel
  $footer.FlowDirection = 'LeftToRight'
  $footer.AutoSize = $true
  $footer.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)

  $btnAdd = New-Object System.Windows.Forms.Button
  $btnAdd.Text = '+ Add account'
  $btnAdd.AutoSize = $true
  $btnAdd.Height = 34
  $btnAdd.FlatStyle = 'System'
  $btnAdd.add_Click({ if (Invoke-AddAccountFlow) { Update-PickerRows } })

  $btnMenu = New-Object System.Windows.Forms.Button
  $btnMenu.Text = 'Settings'
  $btnMenu.AutoSize = $true
  $btnMenu.Height = 34
  $btnMenu.FlatStyle = 'System'
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  [void]$menu.Items.Add('Create picker shortcuts (Desktop and Start menu)', $null, { try { New-PickerShortcuts | Out-Null; Show-Message 'Shortcuts created.' } catch { Show-Message $_.Exception.Message 'Error' 'Error' } })
  [void]$menu.Items.Add('Start tray mode', $null, { Start-Process -WindowStyle Hidden -FilePath (Get-PowerShellExe) -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Tray' -f $script:ScriptPath) })
  [void]$menu.Items.Add('Start tray mode when Windows starts', $null, { try { Install-TrayAutoStart | Out-Null; Show-Message 'Added to Windows startup.' } catch { Show-Message $_.Exception.Message 'Error' 'Error' } })
  [void]$menu.Items.Add('-')
  [void]$menu.Items.Add('Open data folder', $null, { New-Item -ItemType Directory -Force -Path $script:Root | Out-Null; Start-Process explorer.exe $script:Root })
  [void]$menu.Items.Add('Show diagnostics', $null, { Start-Process -FilePath (Get-PowerShellExe) -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" -Diagnose' -f $script:ScriptPath) })
  $btnMenu.add_Click({ $menu.Show($btnMenu, (New-Object System.Drawing.Point(0, $btnMenu.Height))) })

  $footer.Controls.Add($btnAdd)
  $footer.Controls.Add($btnMenu)

  $outer = New-Object System.Windows.Forms.FlowLayoutPanel
  $outer.FlowDirection = 'TopDown'
  $outer.WrapContents = $false
  $outer.AutoSize = $true
  $outer.AutoSizeMode = 'GrowAndShrink'
  $outer.Controls.Add($header)
  $outer.Controls.Add($panel)
  $outer.Controls.Add($footer)
  $form.Controls.Add($outer)

  $form.add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $script:PickerForm.Close() } })

  Update-PickerRows
  [void]$form.ShowDialog()
  $form.Dispose()
}

function Update-PickerRows {
  $panel = $script:PickerPanel
  $panel.SuspendLayout()
  $panel.Controls.Clear()
  $running = Get-RunningAccountIds
  $cfg = Get-Config

  $rows = @()
  $rows += [pscustomobject]@{ id = $script:MainId; display = $script:MainLabel; color = '#10A37F'; initial = 'M'; mode = 'isolated' }
  foreach ($a in $cfg.accounts) {
    $m = if ($a.PSObject.Properties.Name -contains 'mode') { $a.mode } else { 'isolated' }
    $rows += [pscustomobject]@{ id = $a.id; display = $a.display; color = $a.color; initial = $a.display.Substring(0, 1); mode = $m }
  }

  foreach ($r in $rows) {
    $btn = New-Object System.Windows.Forms.Button
    $isRunning = ($running -contains $r.id)
    $badge = $(if ($r.mode -eq 'shared') { '  [Shared - disabled]' } else { '' })
    $btn.Text = '   ' + $r.display + $badge + $(if ($isRunning) { '   ● Running' } else { '' })
    $btn.Tag = $r.id
    $btn.Width = 400
    $btn.Height = 46
    $btn.TextAlign = 'MiddleLeft'
    $btn.ImageAlign = 'MiddleLeft'
    $btn.TextImageRelation = 'ImageBeforeText'
    $btn.Image = New-AvatarImage -Hex $r.color -Text $r.initial
    $btn.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(225, 225, 225)
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
    $btn.BackColor = [System.Drawing.Color]::White
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Margin = New-Object System.Windows.Forms.Padding(4, 3, 4, 3)
    if ($isRunning) { $btn.ForeColor = [System.Drawing.Color]::FromArgb(16, 163, 127) }

    $btn.add_Click({
      try {
        Start-Account $this.Tag
        $script:PickerForm.Close()
      } catch { Show-Message $_.Exception.Message 'Error' 'Error' }
    })

    if ($r.id -ne $script:MainId) {
      $cm = New-Object System.Windows.Forms.ContextMenuStrip
      $cm.Tag = $r.id
      $mi1 = $cm.Items.Add('Create desktop shortcut')
      $mi1.Tag = $r.id
      $mi1.add_Click({ try { New-AccountShortcut -Account (Find-Account $this.Tag) | Out-Null; Show-Message 'Desktop shortcut created.' } catch { Show-Message $_.Exception.Message 'Error' 'Error' } })
      $mi2 = $cm.Items.Add('Rename')
      $mi2.Tag = $r.id
      $mi2.add_Click({
        $acc = Find-Account $this.Tag
        $n = Show-InputDialog -Prompt 'Enter a new display name' -Title 'Rename' -Default $acc.display
        if (-not [string]::IsNullOrWhiteSpace($n)) { try { Rename-Account $this.Tag $n; Update-PickerRows } catch { Show-Message $_.Exception.Message 'Error' 'Error' } }
      })
      $mi3 = $cm.Items.Add('Delete this account...')
      $mi3.Tag = $r.id
      $mi3.add_Click({
        $acc = Find-Account $this.Tag
        if (Ask-YesNo ("Delete {0}?`nLocal sign-in data, settings and local projects/chats for this profile will be deleted. The online account is not deleted." -f $acc.display)) {
          try { Remove-Account $this.Tag; Update-PickerRows } catch { Show-Message $_.Exception.Message 'Error' 'Error' }
        }
      })
      $btn.ContextMenuStrip = $cm
    }
    $panel.Controls.Add($btn)
  }

  $hint = New-Object System.Windows.Forms.Label
  $hint.Text = 'Right-click for options. Accounts have separate data and can run together.'
  $hint.AutoSize = $true
  $hint.ForeColor = [System.Drawing.Color]::Gray
  $hint.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
  $hint.Margin = New-Object System.Windows.Forms.Padding(6, 6, 4, 0)
  $panel.Controls.Add($hint)

  $panel.ResumeLayout()
}


function Start-Tray {
  Ensure-Gui
  Set-JumpList
  $ni = New-Object System.Windows.Forms.NotifyIcon
  $iconPath = Get-AppIconPath
  $ni.Icon = [System.Drawing.SystemIcons]::Application
  if ($iconPath) { try { $ni.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath) } catch {} }
  $ni.Text = 'ChatGPT Account Switcher'
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $menu.Font = New-Object System.Drawing.Font('Segoe UI', 10)

  $menu.add_Opening({
    $m = $this
    $m.Items.Clear()
    $running = Get-RunningAccountIds
    $head = $m.Items.Add('Open ChatGPT:')
    $head.Enabled = $false
    $mainItem = $m.Items.Add($script:MainLabel + $(if ($running -contains $script:MainId) { '  ● Running' } else { '' }))
    $mainItem.Tag = $script:MainId
    $mainItem.Image = New-AvatarImage -Hex '#10A37F' -Text 'M' -Size 20
    $mainItem.add_Click({ try { Start-Account $this.Tag } catch { Show-Message $_.Exception.Message 'Error' 'Error' } })
    foreach ($a in (Get-Config).accounts) {
      $it = $m.Items.Add($a.display + $(if ($running -contains $a.id) { '  ● Running' } else { '' }))
      $it.Tag = $a.id
      $it.Image = New-AvatarImage -Hex $a.color -Text $a.display.Substring(0, 1) -Size 20
      $it.add_Click({ try { Start-Account $this.Tag } catch { Show-Message $_.Exception.Message 'Error' 'Error' } })
    }
    [void]$m.Items.Add('-')
    $add = $m.Items.Add('+ Add account')
    $add.add_Click({ Invoke-AddAccountFlow | Out-Null })
    $pick = $m.Items.Add('Open account picker')
    $pick.add_Click({ Show-Picker })
    [void]$m.Items.Add('-')
    $quit = $m.Items.Add('Exit tray mode')
    $quit.add_Click({ [System.Windows.Forms.Application]::Exit() })
  })

  $ni.ContextMenuStrip = $menu
  $ni.add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { Show-Picker } })
  $ni.Visible = $true
  Write-Log 'tray started'
  try {
    [System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
  } finally {
    $ni.Visible = $false
    $ni.Dispose()
  }
}


function Show-Diagnose {
  Write-Host '=== ChatGPT Account Switcher diagnostics ===' -ForegroundColor Cyan
  Write-Host ("Version      : {0}" -f $script:AppVersion)
  Write-Host ("Script       : {0}" -f $script:ScriptPath)
  Write-Host ("Data folder  : {0}" -f $script:Root)
  Write-Host ("PowerShell   : {0}" -f $PSVersionTable.PSVersion)
  Write-Host ("OS           : {0}" -f [Environment]::OSVersion.VersionString)
  Write-Host ''
  $app = Get-ChatGptApp
  if (-not $app) {
    Write-Host 'Desktop app: not found (Store or standalone installation)' -ForegroundColor Red
  } else {
    Write-Host 'Desktop app:' -ForegroundColor Green
    Write-Host ("  Kind      : {0}" -f $app.Kind)
    Write-Host ("  Version   : {0}" -f $app.Version)
    Write-Host ("  Location  : {0}" -f $app.InstallLocation)
    Write-Host ("  EXE       : {0}" -f $(if ($app.Exe) { $app.Exe } else { '(not found)' }))
    Write-Host ("  PFN       : {0}" -f $app.PackageFamilyName)
    Write-Host ("  AppId     : {0}" -f $app.AppId)
    if ($app.Exe) {
      try { $null = [System.IO.File]::OpenRead($app.Exe).Dispose(); Write-Host '  EXE readable: OK' } catch { Write-Host "  EXE readable: FAILED ($_)" -ForegroundColor Yellow }
    }
  }
  Write-Host ''
  Write-Host ("Default CODEX_HOME  : {0}  (exists: {1})" -f (Join-Path $env:USERPROFILE '.codex'), (Test-Path (Join-Path $env:USERPROFILE '.codex')))
  $stock = Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Roaming\Codex'
  Write-Host ("Default Electron data: {0}  (exists: {1})" -f $stock, (Test-Path $stock))
  Write-Host ''
  $running = Get-RunningAccountIds
  $cfg = Get-Config
  Write-Host ("Registered accounts: {0}" -f $cfg.accounts.Count) -ForegroundColor Cyan
  Write-Host ("  [main] {0}{1}" -f $script:MainLabel, $(if ($running -contains $script:MainId) { '  ● Running' } else { '' }))
  foreach ($a in $cfg.accounts) {
    $p = Get-AccountPaths $a.id
    $m = if ($a.PSObject.Properties.Name -contains 'mode') { $a.mode } else { 'isolated' }
    Write-Host ("  [{0}] {1}  <{2}>{3}" -f $a.id, $a.display, $m, $(if ($running -contains $a.id) { '  ● Running' } else { '' }))
    Write-Host ("      electron: {0}" -f $p.Electron)
    Write-Host ("      codex   : {0}" -f $p.Codex)
  }
  Write-Host ''
  Write-Host 'ChatGPT / Codex processes:' -ForegroundColor Cyan
  try {
    Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe' OR Name = 'Codex.exe'" | Where-Object { $_.CommandLine -notmatch '--type=' } |
      ForEach-Object { Write-Host ("  PID {0}: {1}" -f $_.ProcessId, $_.CommandLine) }
  } catch { Write-Host "  (query failed: $_)" }
  Write-Host ''
  Write-Host ("Log: {0}" -f $script:LogPath)
}


try {
  if ($Version) { Write-Host ("ChatGPT-Switcher {0}" -f $script:AppVersion); return }

  if ($Diagnose) { Show-Diagnose; return }

  if ($List) {
    $running = Get-RunningAccountIds
    $cfg = Get-Config
    Write-Host ("[{0}] {1}{2}" -f $script:MainId, $script:MainLabel, $(if ($running -contains $script:MainId) { '  (Running)' } else { '' }))
    foreach ($a in $cfg.accounts) {
      Write-Host ("[{0}] {1}{2}" -f $a.id, $a.display, $(if ($running -contains $a.id) { '  (Running)' } else { '' }))
    }
    return
  }

  if ($Add) {
    $acc = Add-Account -Display $Add -SkipShortcut:$NoShortcut
    Write-Host ("Added: [{0}] {1}" -f $acc.id, $acc.display)
    Write-Host ("Launch: ChatGPT-Switcher.ps1 -Launch {0}" -f $acc.id)
    return
  }

  if ($Remove) { Remove-Account $Remove; Write-Host "Removed: $Remove"; return }

  if ($Setup) {
    $made = New-PickerShortcuts
    $made | ForEach-Object { Write-Host "Created: $_" }
    $msg = "Shortcuts created:`n" + ($made -join "`n") + "`n`nTo pin to the taskbar, right-click ChatGPT Account Switcher in Start and choose Pin to taskbar.`nRight-click the pinned icon to see your accounts."
    Write-Host $msg
    if (-not $NoShortcut) { Show-Message $msg }
    return
  }

  if ($AutoStartTray) { $lnk = Install-TrayAutoStart; Write-Host "Added to startup: $lnk"; return }

  if ($Tray) { Start-Tray; return }

  if ($Launch) { Start-Account $Launch; return }

  Show-Picker
} catch {
  Write-Log ("ERROR: {0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
  if ($Diagnose -or $List -or $Add -or $Remove) {
    Write-Host ("Error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
  }
  Show-Message ("Error: {0}`n`nDetails log: {1}" -f $_.Exception.Message, $script:LogPath) 'ChatGPT Account Switcher' 'Error'
  exit 1
}
