@echo off
rem ChatGPT account switcher launcher (double-click to open the picker)
rem Only no arguments or a lone -Tray run in the background. All other arguments run synchronously.
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if "%~1"=="" goto background
if /I "%~1"=="-Tray" if "%~2"=="" goto background
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0ChatGPT-Switcher.ps1" %*
exit /b %errorlevel%

:background
start "" "%PS%" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0ChatGPT-Switcher.ps1" %*
exit /b %errorlevel%
