# =====================================================================
#  SyHost - Kaldır ekranı (Terminal sürümü)  [GEÇİCİ İSKELET]
#  C# karşılığı: src\SyHost\App\App.Uninstall.cs ve Setup\Uninstall.cs. Bu dosya tam sürümüyle değiştirilecek.
# =====================================================================
$UnItems = $null; $UnSel = 0; $UnPhase = 'liste'; $UnJob = $null
function Start-Uninstall { $script:UnItems = New-Object System.Collections.Generic.List[object]; $script:UnSel = 0; $script:UnPhase = 'liste'; $script:Screen = 'uninstall'; Reset-Frame }
function Render-Uninstall([int]$W, [int]$H) { $rows = New-Object System.Collections.Generic.List[string]; $rows.Add(''); $rows.Add('  kaldır (iskelet)'); $rows }
function Handle-UninstallKey([ConsoleKeyInfo]$k, [bool]$ctrl) { $script:Screen = 'settings'; Reset-Frame }
