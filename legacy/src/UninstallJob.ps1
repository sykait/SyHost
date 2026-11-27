# =====================================================================
#  SyHost - kaldırma işi (Terminal sürümü)
#  Start-UninstallJob (Uninstall.ps1) bu dosyayı ayrı bir çalışma alanında çalıştırır: Portable.ps1 ve
#  Uninstall.ps1 diskten yüklenir, seçili satırlar sırayla uygulanır (Invoke-UninstallItems). Satırlar ana
#  ekranla paylaşılır: iş State ve Error alanlarını yazar, ekran her karede okur. Metinden kod üretilmez;
#  işin gerektirdiği her şey satırların Run bilgisindedir.
#  C# karşılığı: Task.Run(() => Uninstall.RunSelected(items)) (App.Uninstall.cs).
# =====================================================================
param($Items)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Portable.ps1')
. (Join-Path $PSScriptRoot 'Uninstall.ps1')
try { Invoke-UninstallItems $Items }
catch {
    # Beklenmeyen bir hata: başlamış ya da sırası gelmemiş seçili satırlar hata, seçili olmayanlar atlandı sayılır
    $msg = $_.Exception.Message
    foreach ($it in $Items) { if ($it.State -eq 0 -or $it.State -eq 1) { if ($it.On) { $it.Error = $msg; $it.State = 3 } else { $it.State = 4 } } }
}
