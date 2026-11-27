@echo off
rem SyHost Terminal surumunu bu repodan calistirir (gelistirme icin).
rem Kullanici verileri repo kokundeki .dev klasorune yazilir; git ona dokunmaz.
rem Son kullanicilar bunu degil, Releases sayfasindaki SyHost-Legacy-<surum>.exe dosyasini kullanir.
rem RemoteSigned: git ile alinan betikler calisir. Repo zip olarak indirildiyse once klasordeki dosyalarin
rem "internetten geldi" isaretini kaldir (Ozellikler > Engellemeyi kaldir) ya da git clone kullan.
setlocal
set "ROOT=%~dp0..\.dev"
if not exist "%ROOT%\Data" mkdir "%ROOT%\Data"
if not exist "%ROOT%\Data\sunucular.json" (echo []) > "%ROOT%\Data\sunucular.json"
start "" "%SystemRoot%\System32\conhost.exe" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0src\SyHost.ps1" -Root "%ROOT%"
