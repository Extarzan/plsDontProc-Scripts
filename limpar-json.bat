@echo off
setlocal DisableDelayedExpansion
rem SPDX-License-Identifier: MIT
rem Only the first dropped file is processed. No download or installation.
rem Pass the path as data, never as PowerShell command text.
set "PLSDONTPROC_CLEANER_INPUT=%~1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0limpar-json.ps1"
set "cleaner_exit=%ERRORLEVEL%"
if not defined PLSDONTPROC_CLEANER_NO_PAUSE pause
exit /b %cleaner_exit%
