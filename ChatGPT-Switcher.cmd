@echo off
rem ChatGPT account switcher launcher (double-click to open the picker)
rem Usage: ChatGPT-Switcher.cmd [-Launch name | -Add name | -Remove name | -List | -Setup | -Tray | -AutoStartTray | -Diagnose]
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if /I "%~1"=="-Diagnose" (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0ChatGPT-Switcher.ps1" %*
) else if /I "%~1"=="-List" (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0ChatGPT-Switcher.ps1" %*
) else (
  start "" "%PS%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ChatGPT-Switcher.ps1" %*
)
endlocal
