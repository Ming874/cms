@echo off
rem CMS Docker helper: runs cms.ps1 from cmd.exe or PowerShell without changing the execution policy.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cms.ps1" %*
exit /b %ERRORLEVEL%
