@echo off
rem SyHost first-time setup: font, Java, playit connection and shortcuts.
chcp 65001 >nul
title SyHost Setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Setup.ps1"
