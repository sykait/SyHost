@echo off
rem Opens SyHost. Run Setup.bat first if this is your first time.
start "" "%SystemRoot%\System32\conhost.exe" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\SyHost.ps1"
