@echo off
rem Entry point for cmd.exe, PowerShell's Application resolution, and npm
rem scripts. Mirrors the npm convention: a .cmd and an extensionless sibling.
rem
rem Always delegates. An earlier draft filtered arguments in batch first, to
rem skip the pwsh startup on harmless calls -- but that put the most fragile
rem quoting in the project on the guard's only entry point, to save a few
rem hundred milliseconds on a command that takes seconds.
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0supabase.ps1" %*
exit /b %ERRORLEVEL%
