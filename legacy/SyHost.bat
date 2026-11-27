@echo off
rem SyHost Terminal surumunu bu repodan calistirir (gelistirme icin).
rem Kullanici verileri repo kokundeki .dev klasorune yazilir; git ona dokunmaz.
rem Son kullanicilar bunu degil, Releases sayfasindaki SyHost-<surum>-Terminal.exe dosyasini kullanir.
setlocal
set "ROOT=%~dp0..\.dev"
if not exist "%ROOT%\Data" mkdir "%ROOT%\Data"
if not exist "%ROOT%\Data\sunucular.json" (echo []) > "%ROOT%\Data\sunucular.json"
start "" "%SystemRoot%\System32\conhost.exe" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\SyHost.ps1" -Root "%ROOT%"
