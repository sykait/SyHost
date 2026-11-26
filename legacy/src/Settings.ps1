# =====================================================================
#  SyHost - Ayarlar ekranı (Terminal sürümü)  [GEÇİCİ İSKELET]
#  C# karşılığı: src\SyHost\App\App.Settings.cs. Bu dosya tam sürümüyle değiştirilecek.
# =====================================================================
$SetSel = 0; $SetNote = $null; $SetNoteCol = $null
function Open-Settings { $script:SetSel = 0; $script:SetNote = $null; $script:Screen = 'settings'; Reset-Frame }
function Render-Settings([int]$W, [int]$H) { $rows = New-Object System.Collections.Generic.List[string]; $rows.Add(''); $rows.Add('  ayarlar (iskelet)'); $rows }
function Handle-SettingsKey([ConsoleKeyInfo]$k, [bool]$ctrl) { $script:Screen = 'home'; Reset-Frame }
