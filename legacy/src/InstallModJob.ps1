# =====================================================================
#  SyHost - paralel mod indirmede bir dosyanın işi (Terminal sürümü)
#  Inst-AllMods (Install.ps1) her dosya için bunu bir iş parçacığı havuzunda çalıştırır: Install.ps1'i diskten
#  yükler ve o dosyayı indirip doğrular (Inst-ModJob). Metinden kod üretilmez. C#: Installer.DownloadAll
# =====================================================================
param($f, $ctx)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Install.ps1')
Inst-ModJob $f $ctx
