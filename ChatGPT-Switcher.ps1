#Requires -Version 5.1
<#
.SYNOPSIS
  ChatGPT アカウント切替ランチャー（Windows / 新ChatGPTデスクトップアプリ用）

.DESCRIPTION
  アカウントごとに独立したデータ領域（Electron の user-data と CODEX_HOME）を用意し、
  ChatGPTデスクトップアプリを別プロセスとして起動します。複数アカウントの同時起動も可能。
  既存のログイン（メイン）はそのまま残ります。

  使い方:
    ChatGPT-Switcher.ps1                  … 切替ウィンドウ（ピッカー）を表示
    ChatGPT-Switcher.ps1 -Launch 仕事用    … 指定アカウントで起動（起動中なら前面に）
    ChatGPT-Switcher.ps1 -Add 仕事用       … アカウント追加（デスクトップにショートカットも作成）
    ChatGPT-Switcher.ps1 -Remove 仕事用    … アカウント削除（ローカルデータも削除）
    ChatGPT-Switcher.ps1 -List            … アカウント一覧
    ChatGPT-Switcher.ps1 -Setup           … ピッカーのショートカットをデスクトップ/スタートメニューに作成
    ChatGPT-Switcher.ps1 -Tray            … タスクトレイに常駐（左クリック=ピッカー、右クリック=一覧）
    ChatGPT-Switcher.ps1 -AutoStartTray   … トレイ常駐をWindows起動時に自動開始
    ChatGPT-Switcher.ps1 -Diagnose        … 環境診断（アプリ検出・パス・起動状況）

  データ保存先: %USERPROFILE%\ChatGPT-Accounts\<アカウントID>\{electron,codex}
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

$script:Version    = '1.0.0'
$script:ScriptPath = $MyInvocation.MyCommand.Path
$script:Root       = Join-Path $env:USERPROFILE 'ChatGPT-Accounts'
$script:ConfigPath = Join-Path $script:Root 'accounts.json'
$script:LogPath    = Join-Path $script:Root 'switcher.log'
$script:MainId     = '__main__'
$script:MainLabel  = 'メイン（元々ログインしているアカウント）'
$script:Palette    = @('#4285F4','#34A853','#EA4335','#F9AB00','#A142F4','#F538A0','#12B5CB','#FF6D01')
$script:AppCache   = $null
$script:Gui        = $false

# ------------------------------------------------------------------ 共通

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
}

function Get-DialogOwner {
  # ピッカーが表示中ならそれを親にする（ダイアログが背面に隠れるのを防ぐ）
  $f = $script:PickerForm
  if ($f -and -not $f.IsDisposed -and $f.Visible) { return $f }
  return $null
}

function Show-Message {
  param([string]$Text, [string]$Title = 'ChatGPT アカウント切替', [string]$Icon = 'Information')
  Ensure-Gui
  $owner = Get-DialogOwner
  if ($owner) { [void][System.Windows.Forms.MessageBox]::Show($owner, $Text, $Title, 'OK', $Icon) }
  else        { [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', $Icon) }
}

function Ask-YesNo {
  param([string]$Text, [string]$Title = 'ChatGPT アカウント切替')
  Ensure-Gui
  $owner = Get-DialogOwner
  if ($owner) { $r = [System.Windows.Forms.MessageBox]::Show($owner, $Text, $Title, 'YesNo', 'Question') }
  else        { $r = [System.Windows.Forms.MessageBox]::Show($Text, $Title, 'YesNo', 'Question') }
  return ($r -eq 'Yes')
}

function Show-InputDialog {
  # 自前の入力ダイアログ（VisualBasic の InputBox は親を持てず背面に隠れるため）
  param([string]$Prompt, [string]$Title = 'ChatGPT アカウント切替', [string]$Default = '')
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
  $dlg.Font = New-Object System.Drawing.Font('Yu Gothic UI', 10)

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
  $cancel.Text = 'キャンセル'
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

# ------------------------------------------------------------------ アプリ検出

function Get-ChatGptApp {
  if ($script:AppCache) { return $script:AppCache }

  # Microsoft Store (MSIX) 版: OpenAI.Codex_2p2nqsd0c76g0  ※現在の「ChatGPT」デスクトップアプリ
  $pkg = $null
  try {
    if ($PSVersionTable.PSEdition -eq 'Core') { Import-Module Appx -UseWindowsPowerShell -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
      Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
  } catch {}

  if ($pkg) {
    $loc = $pkg.InstallLocation
    $exe = $null
    foreach ($cand in @((Join-Path $loc 'ChatGPT.exe'), (Join-Path $loc 'app\ChatGPT.exe'), (Join-Path $loc 'Codex.exe'))) {
      if (Test-Path -LiteralPath $cand) { $exe = $cand; break }
    }
    if (-not $exe) {
      $found = Get-ChildItem -LiteralPath $loc -Filter 'ChatGPT.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($found) { $exe = $found.FullName }
    }
    $appId = $null
    try {
      $manifest = Get-AppxPackageManifest -Package $pkg
      $appId = @($manifest.Package.Applications.Application)[0].Id
    } catch {}
    $script:AppCache = [pscustomobject]@{
      Kind              = 'Store'
      Exe               = $exe
      PackageFamilyName = $pkg.PackageFamilyName
      AppId             = $appId
      Version           = $pkg.Version
      InstallLocation   = $loc
    }
    return $script:AppCache
  }

  # 通常インストーラー版（念のため）
  foreach ($c in @(
      (Join-Path $env:LOCALAPPDATA 'Programs\ChatGPT\ChatGPT.exe'),
      (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe'),
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
  return $null
}

# ------------------------------------------------------------------ 設定

function Get-Config {
  $cfg = $null
  if (Test-Path -LiteralPath $script:ConfigPath) {
    try {
      $raw = [System.IO.File]::ReadAllText($script:ConfigPath, [System.Text.Encoding]::UTF8)
      $cfg = $raw | ConvertFrom-Json
    } catch { Write-Log "config read error: $_" }
  }
  if (-not $cfg) { $cfg = [pscustomobject]@{ accounts = @() } }
  if (-not ($cfg.PSObject.Properties.Name -contains 'accounts')) {
    $cfg | Add-Member -NotePropertyName accounts -NotePropertyValue @() -Force
  }
  $cfg.accounts = @($cfg.accounts | Where-Object { $_ -ne $null })
  return $cfg
}

function Save-Config {
  param($Config)
  New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
  $Config.accounts = @($Config.accounts)
  $json = ConvertTo-Json -InputObject $Config -Depth 5
  [System.IO.File]::WriteAllText($script:ConfigPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-AccountPaths {
  param([string]$Id)
  $base = Join-Path $script:Root $Id
  return [pscustomobject]@{
    Base     = $base
    Electron = (Join-Path $base 'electron')
    Codex    = (Join-Path $base 'codex')
  }
}

function Find-Account {
  param([string]$Key)   # ID でも表示名でもOK
  $cfg = Get-Config
  $acc = $cfg.accounts | Where-Object { $_.id -eq $Key } | Select-Object -First 1
  if (-not $acc) { $acc = $cfg.accounts | Where-Object { $_.display -eq $Key } | Select-Object -First 1 }
  if (-not $acc) { $acc = $cfg.accounts | Where-Object { $_.id -eq (Get-SafeName $Key) } | Select-Object -First 1 }
  return $acc
}

function Add-Account {
  param([string]$Display, [switch]$SkipShortcut)
  $Display = $Display.Trim()
  if ([string]::IsNullOrWhiteSpace($Display)) { throw 'アカウント名が空です。' }
  $cfg = Get-Config
  if ($cfg.accounts | Where-Object { $_.display -eq $Display }) { throw "「$Display」は既に登録されています。" }
  $id = Get-SafeName $Display
  $n = 2
  while ($cfg.accounts | Where-Object { $_.id -eq $id }) { $id = (Get-SafeName $Display) + "_$n"; $n++ }
  $color = $script:Palette[ $cfg.accounts.Count % $script:Palette.Count ]
  $acc = [pscustomobject]@{
    id      = $id
    display = $Display
    color   = $color
    created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  }
  $cfg.accounts = @($cfg.accounts) + @($acc)
  Save-Config $cfg
  $p = Get-AccountPaths $id
  New-Item -ItemType Directory -Force -Path $p.Electron, $p.Codex | Out-Null
  Write-Log "account added: $id ($Display)"
  if (-not $SkipShortcut) { New-AccountShortcut -Account $acc | Out-Null }
  return $acc
}

function Remove-Account {
  param([string]$Key)
  $acc = Find-Account $Key
  if (-not $acc) { throw "アカウント「$Key」が見つかりません。" }
  if ((Get-RunningAccountIds) -contains $acc.id) { throw "「$($acc.display)」のChatGPTが起動中です。先に終了してください。" }
  $p = Get-AccountPaths $acc.id
  if (Test-Path -LiteralPath $p.Base) { Remove-Item -LiteralPath $p.Base -Recurse -Force }
  $cfg = Get-Config
  $cfg.accounts = @($cfg.accounts | Where-Object { $_.id -ne $acc.id })
  Save-Config $cfg
  $lnk = Get-AccountShortcutPath $acc
  if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
  Write-Log "account removed: $($acc.id)"
}

function Rename-Account {
  param([string]$Key, [string]$NewDisplay)
  $acc = Find-Account $Key
  if (-not $acc) { throw "アカウント「$Key」が見つかりません。" }
  $NewDisplay = $NewDisplay.Trim()
  if ([string]::IsNullOrWhiteSpace($NewDisplay)) { return }
  $old = Get-AccountShortcutPath $acc
  $cfg = Get-Config
  foreach ($a in $cfg.accounts) { if ($a.id -eq $acc.id) { $a.display = $NewDisplay } }
  Save-Config $cfg
  if (Test-Path -LiteralPath $old) {
    Remove-Item -LiteralPath $old -Force
    New-AccountShortcut -Account (Find-Account $acc.id) | Out-Null
  }
}

# ------------------------------------------------------------------ 起動

function Get-RunningAccountIds {
  $ids = @()
  $procs = @()
  try { $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe' OR Name = 'Codex.exe'" -ErrorAction SilentlyContinue) } catch {}
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
  if (-not $app) { throw 'ChatGPTデスクトップアプリが見つかりません。Microsoft Store から「ChatGPT」をインストールしてください。' }

  if ($Id -eq $script:MainId) {
    if ($app.Kind -eq 'Store' -and $app.AppId) {
      Start-Process -FilePath 'explorer.exe' -ArgumentList ("shell:AppsFolder\{0}!{1}" -f $app.PackageFamilyName, $app.AppId)
    } else {
      Start-Process -FilePath $app.Exe
    }
    Write-Log 'launched: main'
    return
  }

  $acc = Find-Account $Id
  if (-not $acc) { throw "アカウント「$Id」が登録されていません。" }
  if (-not $app.Exe) { throw "ChatGPT.exe が見つかりません（$($app.InstallLocation)）。" }

  $p = Get-AccountPaths $acc.id
  New-Item -ItemType Directory -Force -Path $p.Electron, $p.Codex | Out-Null

  # アカウント分離の要: Electron のユーザーデータ (Cookie/ログイン) と Codex のホーム
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
  }
}

# ------------------------------------------------------------------ ショートカット

function Get-PowerShellExe {
  return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
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
  $lnk.WindowStyle = 7   # 最小化で起動（コンソールのチラつき防止）
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
  $desktop = [Environment]::GetFolderPath('Desktop')
  return (Join-Path $desktop ('ChatGPT - {0}.lnk' -f (Get-SafeName $Account.display)))
}

function New-AccountShortcut {
  param($Account)
  $lnk = Get-AccountShortcutPath $Account
  New-Shortcut -LnkPath $lnk -Arguments ('-Launch "{0}"' -f $Account.id) -IconPath (Get-AppIconPath) -Description ("ChatGPT を「{0}」で起動" -f $Account.display)
  Write-Log "shortcut created: $lnk"
  return $lnk
}

function New-PickerShortcuts {
  $icon = Get-AppIconPath
  $desktop = [Environment]::GetFolderPath('Desktop')
  $programs = Join-Path ([Environment]::GetFolderPath('Programs')) 'ChatGPT アカウント切替'
  $made = @()
  $made += New-Shortcut -LnkPath (Join-Path $desktop 'ChatGPT アカウント切替.lnk') -Arguments '' -IconPath $icon -Description 'ChatGPT のアカウントを選んで起動'
  $made += New-Shortcut -LnkPath (Join-Path $programs 'ChatGPT アカウント切替.lnk') -Arguments '' -IconPath $icon -Description 'ChatGPT のアカウントを選んで起動'
  $made += New-Shortcut -LnkPath (Join-Path $programs 'ChatGPT 切替（トレイ常駐）.lnk') -Arguments '-Tray' -IconPath $icon -Description 'タスクトレイに常駐して右クリックで切替'
  return $made
}

function Install-TrayAutoStart {
  $startup = [Environment]::GetFolderPath('Startup')
  return New-Shortcut -LnkPath (Join-Path $startup 'ChatGPT 切替（トレイ常駐）.lnk') -Arguments '-Tray' -IconPath (Get-AppIconPath) -Description 'ChatGPT アカウント切替（トレイ常駐）'
}

# ------------------------------------------------------------------ GUI: ピッカー

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
  $font = New-Object System.Drawing.Font('Yu Gothic UI', [float]($Size * 0.45), [System.Drawing.FontStyle]::Bold)
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $rect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
  $g.DrawString($Text, $font, [System.Drawing.Brushes]::White, $rect, $fmt)
  $g.Dispose()
  return $bmp
}

function Invoke-AddAccountFlow {
  Ensure-Gui
  $name = Show-InputDialog -Prompt 'アカウントの表示名を入力してください（例: 仕事用 / 個人 / 副業）' -Title 'アカウントを追加'
  if ([string]::IsNullOrWhiteSpace($name)) { return $null }
  try {
    $acc = Add-Account -Display $name
  } catch {
    Show-Message $_.Exception.Message 'エラー' 'Error'
    return $null
  }
  if (Ask-YesNo ("「{0}」を追加しました。デスクトップにショートカットも作りました。`n`n今すぐ起動してログインしますか？" -f $acc.display)) {
    try { Start-Account $acc.id } catch { Show-Message $_.Exception.Message 'エラー' 'Error' }
  }
  return $acc
}

function Show-Picker {
  Ensure-Gui

  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'ChatGPT アカウント切替'
  $form.StartPosition = 'CenterScreen'
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false
  $form.MinimizeBox = $false
  $form.ShowInTaskbar = $true
  $form.KeyPreview = $true
  # 常時最前面にはしない（入力ダイアログが裏に隠れる原因になる）。表示時に一度だけ前面へ。
  $form.add_Shown({ $this.Activate(); $this.TopMost = $true; $this.TopMost = $false; $this.BringToFront() })
  $form.AutoSize = $true
  $form.AutoSizeMode = 'GrowAndShrink'
  $form.Font = New-Object System.Drawing.Font('Yu Gothic UI', 10)
  $form.BackColor = [System.Drawing.Color]::White
  $form.Padding = New-Object System.Windows.Forms.Padding(12)
  $iconPath = Get-AppIconPath
  if ($iconPath) { try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath) } catch {} }

  $script:PickerForm = $form

  $header = New-Object System.Windows.Forms.Label
  $header.Text = 'どのアカウントで開く？'
  $header.Font = New-Object System.Drawing.Font('Yu Gothic UI', 12, [System.Drawing.FontStyle]::Bold)
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
  $btnAdd.Text = '＋ アカウントを追加'
  $btnAdd.AutoSize = $true
  $btnAdd.Height = 34
  $btnAdd.FlatStyle = 'System'
  $btnAdd.add_Click({ if (Invoke-AddAccountFlow) { Update-PickerRows } })

  $btnMenu = New-Object System.Windows.Forms.Button
  $btnMenu.Text = '設定 ▾'
  $btnMenu.AutoSize = $true
  $btnMenu.Height = 34
  $btnMenu.FlatStyle = 'System'
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  [void]$menu.Items.Add('この切替ウィンドウのショートカットを作る（デスクトップ/スタート）', $null, { try { New-PickerShortcuts | Out-Null; Show-Message 'ショートカットを作成しました。' } catch { Show-Message $_.Exception.Message 'エラー' 'Error' } })
  [void]$menu.Items.Add('タスクトレイに常駐して使う（今すぐ開始）', $null, { Start-Process -FilePath (Get-PowerShellExe) -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Tray' -f $script:ScriptPath) })
  [void]$menu.Items.Add('トレイ常駐をWindows起動時に自動開始する', $null, { try { Install-TrayAutoStart | Out-Null; Show-Message 'スタートアップに登録しました。' } catch { Show-Message $_.Exception.Message 'エラー' 'Error' } })
  [void]$menu.Items.Add('-')
  [void]$menu.Items.Add('データフォルダを開く', $null, { New-Item -ItemType Directory -Force -Path $script:Root | Out-Null; Start-Process explorer.exe $script:Root })
  [void]$menu.Items.Add('環境診断を表示', $null, { Start-Process -FilePath (Get-PowerShellExe) -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" -Diagnose' -f $script:ScriptPath) })
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
  $rows += [pscustomobject]@{ id = $script:MainId; display = $script:MainLabel; color = '#10A37F'; initial = 'M' }
  foreach ($a in $cfg.accounts) {
    $rows += [pscustomobject]@{ id = $a.id; display = $a.display; color = $a.color; initial = $a.display.Substring(0, 1) }
  }

  foreach ($r in $rows) {
    $btn = New-Object System.Windows.Forms.Button
    $isRunning = ($running -contains $r.id)
    $btn.Text = '   ' + $r.display + $(if ($isRunning) { '   ● 起動中' } else { '' })
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
      } catch { Show-Message $_.Exception.Message 'エラー' 'Error' }
    })

    if ($r.id -ne $script:MainId) {
      $cm = New-Object System.Windows.Forms.ContextMenuStrip
      $cm.Tag = $r.id
      $mi1 = $cm.Items.Add('デスクトップにショートカットを作る')
      $mi1.Tag = $r.id
      $mi1.add_Click({ try { New-AccountShortcut -Account (Find-Account $this.Tag) | Out-Null; Show-Message 'デスクトップにショートカットを作成しました。' } catch { Show-Message $_.Exception.Message 'エラー' 'Error' } })
      $mi2 = $cm.Items.Add('名前を変更')
      $mi2.Tag = $r.id
      $mi2.add_Click({
        $acc = Find-Account $this.Tag
        $n = Show-InputDialog -Prompt '新しい表示名を入力してください' -Title '名前を変更' -Default $acc.display
        if (-not [string]::IsNullOrWhiteSpace($n)) { try { Rename-Account $this.Tag $n; Update-PickerRows } catch { Show-Message $_.Exception.Message 'エラー' 'Error' } }
      })
      $mi3 = $cm.Items.Add('このアカウントを削除…')
      $mi3.Tag = $r.id
      $mi3.add_Click({
        $acc = Find-Account $this.Tag
        if (Ask-YesNo ("「{0}」を削除しますか？`nこのPC上のログイン情報とキャッシュが消えます（ChatGPT側のアカウントや履歴は消えません）。" -f $acc.display)) {
          try { Remove-Account $this.Tag; Update-PickerRows } catch { Show-Message $_.Exception.Message 'エラー' 'Error' }
        }
      })
      $btn.ContextMenuStrip = $cm
    }
    $panel.Controls.Add($btn)
  }

  $hint = New-Object System.Windows.Forms.Label
  $hint.Text = '右クリックでショートカット作成・名前変更・削除。複数アカウントの同時起動も可。'
  $hint.AutoSize = $true
  $hint.ForeColor = [System.Drawing.Color]::Gray
  $hint.Font = New-Object System.Drawing.Font('Yu Gothic UI', 8.5)
  $hint.Margin = New-Object System.Windows.Forms.Padding(6, 6, 4, 0)
  $panel.Controls.Add($hint)

  $panel.ResumeLayout()
}

# ------------------------------------------------------------------ GUI: トレイ常駐

function Start-Tray {
  Ensure-Gui
  $ni = New-Object System.Windows.Forms.NotifyIcon
  $iconPath = Get-AppIconPath
  $ni.Icon = [System.Drawing.SystemIcons]::Application
  if ($iconPath) { try { $ni.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath) } catch {} }
  $ni.Text = 'ChatGPT アカウント切替'
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $menu.Font = New-Object System.Drawing.Font('Yu Gothic UI', 10)

  $menu.add_Opening({
    $m = $this
    $m.Items.Clear()
    $running = Get-RunningAccountIds
    $head = $m.Items.Add('ChatGPT を開く:')
    $head.Enabled = $false
    $mainItem = $m.Items.Add($script:MainLabel + $(if ($running -contains $script:MainId) { '  ● 起動中' } else { '' }))
    $mainItem.Tag = $script:MainId
    $mainItem.Image = New-AvatarImage -Hex '#10A37F' -Text 'M' -Size 20
    $mainItem.add_Click({ try { Start-Account $this.Tag } catch { Show-Message $_.Exception.Message 'エラー' 'Error' } })
    foreach ($a in (Get-Config).accounts) {
      $it = $m.Items.Add($a.display + $(if ($running -contains $a.id) { '  ● 起動中' } else { '' }))
      $it.Tag = $a.id
      $it.Image = New-AvatarImage -Hex $a.color -Text $a.display.Substring(0, 1) -Size 20
      $it.add_Click({ try { Start-Account $this.Tag } catch { Show-Message $_.Exception.Message 'エラー' 'Error' } })
    }
    [void]$m.Items.Add('-')
    $add = $m.Items.Add('＋ アカウントを追加')
    $add.add_Click({ Invoke-AddAccountFlow | Out-Null })
    $pick = $m.Items.Add('切替ウィンドウを開く')
    $pick.add_Click({ Show-Picker })
    [void]$m.Items.Add('-')
    $quit = $m.Items.Add('常駐を終了')
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

# ------------------------------------------------------------------ 診断

function Show-Diagnose {
  Write-Host '=== ChatGPT アカウント切替 環境診断 ===' -ForegroundColor Cyan
  Write-Host ("バージョン   : {0}" -f $script:Version)
  Write-Host ("スクリプト   : {0}" -f $script:ScriptPath)
  Write-Host ("データ保存先 : {0}" -f $script:Root)
  Write-Host ("PowerShell   : {0}" -f $PSVersionTable.PSVersion)
  Write-Host ("OS           : {0}" -f [Environment]::OSVersion.VersionString)
  Write-Host ''
  $app = Get-ChatGptApp
  if (-not $app) {
    Write-Host 'ChatGPTデスクトップアプリ: 見つかりません（Store の OpenAI.Codex / 通常インストール版のどちらも）' -ForegroundColor Red
  } else {
    Write-Host 'ChatGPTデスクトップアプリ:' -ForegroundColor Green
    Write-Host ("  種別      : {0}" -f $app.Kind)
    Write-Host ("  バージョン: {0}" -f $app.Version)
    Write-Host ("  場所      : {0}" -f $app.InstallLocation)
    Write-Host ("  EXE       : {0}" -f $(if ($app.Exe) { $app.Exe } else { '(見つからず)' }))
    Write-Host ("  PFN       : {0}" -f $app.PackageFamilyName)
    Write-Host ("  AppId     : {0}" -f $app.AppId)
    if ($app.Exe) {
      try { $null = [System.IO.File]::OpenRead($app.Exe).Dispose(); Write-Host '  EXE 読み取り: OK' } catch { Write-Host "  EXE 読み取り: NG ($_)" -ForegroundColor Yellow }
    }
  }
  Write-Host ''
  Write-Host ("標準の CODEX_HOME  : {0}  (存在: {1})" -f (Join-Path $env:USERPROFILE '.codex'), (Test-Path (Join-Path $env:USERPROFILE '.codex')))
  $stock = Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Roaming\Codex'
  Write-Host ("標準の Electron data: {0}  (存在: {1})" -f $stock, (Test-Path $stock))
  Write-Host ''
  $running = Get-RunningAccountIds
  $cfg = Get-Config
  Write-Host ("登録アカウント: {0} 件" -f $cfg.accounts.Count) -ForegroundColor Cyan
  Write-Host ("  [main] {0}{1}" -f $script:MainLabel, $(if ($running -contains $script:MainId) { '  ● 起動中' } else { '' }))
  foreach ($a in $cfg.accounts) {
    $p = Get-AccountPaths $a.id
    Write-Host ("  [{0}] {1}{2}" -f $a.id, $a.display, $(if ($running -contains $a.id) { '  ● 起動中' } else { '' }))
    Write-Host ("      electron: {0}" -f $p.Electron)
    Write-Host ("      codex   : {0}" -f $p.Codex)
  }
  Write-Host ''
  Write-Host 'ChatGPT.exe プロセス:' -ForegroundColor Cyan
  try {
    Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" | Where-Object { $_.CommandLine -notmatch '--type=' } |
      ForEach-Object { Write-Host ("  PID {0}: {1}" -f $_.ProcessId, $_.CommandLine) }
  } catch { Write-Host "  (取得失敗: $_)" }
  Write-Host ''
  Write-Host ("ログ: {0}" -f $script:LogPath)
}

# ------------------------------------------------------------------ エントリ

try {
  if ($Version) { Write-Host ("ChatGPT-Switcher {0}" -f $script:Version); return }

  if ($Diagnose) { Show-Diagnose; return }

  if ($List) {
    $running = Get-RunningAccountIds
    $cfg = Get-Config
    Write-Host ("[{0}] {1}{2}" -f $script:MainId, $script:MainLabel, $(if ($running -contains $script:MainId) { '  (起動中)' } else { '' }))
    foreach ($a in $cfg.accounts) {
      Write-Host ("[{0}] {1}{2}" -f $a.id, $a.display, $(if ($running -contains $a.id) { '  (起動中)' } else { '' }))
    }
    return
  }

  if ($Add) {
    $acc = Add-Account -Display $Add -SkipShortcut:$NoShortcut
    Write-Host ("追加しました: [{0}] {1}" -f $acc.id, $acc.display)
    Write-Host ("起動: ChatGPT-Switcher.ps1 -Launch {0}" -f $acc.id)
    return
  }

  if ($Remove) { Remove-Account $Remove; Write-Host "削除しました: $Remove"; return }

  if ($Setup) {
    $made = New-PickerShortcuts
    $made | ForEach-Object { Write-Host "作成: $_" }
    if (-not $NoShortcut) { Show-Message ("ショートカットを作成しました:`n" + ($made -join "`n")) }
    return
  }

  if ($AutoStartTray) { $lnk = Install-TrayAutoStart; Write-Host "スタートアップに登録: $lnk"; return }

  if ($Tray) { Start-Tray; return }

  if ($Launch) { Start-Account $Launch; return }

  Show-Picker
} catch {
  Write-Log ("ERROR: {0}`n{1}" -f $_.Exception.Message, $_.ScriptStackTrace)
  if ($Diagnose -or $List -or $Add -or $Remove) {
    Write-Host ("エラー: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
  }
  Show-Message ("エラー: {0}`n`n詳細ログ: {1}" -f $_.Exception.Message, $script:LogPath) 'ChatGPT アカウント切替' 'Error'
  exit 1
}
