# =====================================================================
#  SyHost - kaldırma işi (Terminal sürümü)
#  Start-UninstallJob (Uninstall.ps1) bu dosyayı ayrı bir çalışma alanında çalıştırır: Portable.ps1 ve
#  Uninstall.ps1 diskten yüklenir, seçili satırlar sırayla uygulanır (Invoke-UninstallItems). Satırlar ana
#  ekranla paylaşılır: iş State ve Error alanlarını yazar, ekran her karede okur. Metinden kod üretilmez;
#  işin gerektirdiği her şey satırların Run bilgisindedir.
#  İş beklenmedik bir hatayla durursa ya da hiç başlayamazsa (bir dosya yok, açılamadı ya da virüs tarayıcısı
#  engelledi) bitmemiş satırları ana ekran kapatır: UnFinish, hatayı her seçili satırın yanında gösterir.
#  C# karşılığı: Task.Run(() => Uninstall.RunSelected(items)) (App.Uninstall.cs).
# =====================================================================
param($Items)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Portable.ps1')
. (Join-Path $PSScriptRoot 'Uninstall.ps1')
Invoke-UninstallItems $Items
