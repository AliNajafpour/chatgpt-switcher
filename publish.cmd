@echo off
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" %*
echo.
echo ---- finished. see _publish_log.txt for details ----
pause
endlocal
