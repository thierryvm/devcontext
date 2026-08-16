@echo off
rem Entry point for cmd.exe, PowerShell's Application resolution, and npm
rem scripts. Mirrors the npm convention: a .cmd and an extensionless sibling.
rem
rem Always delegates. Filtering arguments in batch first would put the most
rem fragile quoting in the project on the guard's only entry point, to save a
rem few hundred milliseconds on a command that takes seconds.
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0vercel.ps1" %*
exit /b %ERRORLEVEL%
