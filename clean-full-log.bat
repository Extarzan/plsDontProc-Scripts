@echo off
setlocal DisableDelayedExpansion
set "PLSDONTPROC_LOG_INPUT=%~1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0clean-full-log.ps1"
set "cleaner_exit=%ERRORLEVEL%"
if not defined PLSDONTPROC_CLEANER_NO_PAUSE pause
exit /b %cleaner_exit%
