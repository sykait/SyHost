# =====================================================================
#  SyHost - ilk açılış ekranı (Terminal sürümü)  [GEÇİCİ İSKELET]
#  C# karşılığı: src\SyHost\App\App.FirstRun.cs ve App.PlayitSetup.cs. Bu dosya tam sürümüyle değiştirilecek.
# =====================================================================
function After-Splash { $script:Screen = $NextAfterSplash; if ($Screen -eq 'firstrun' -and $null -eq $Fr) { Start-FirstRun $null }; Reset-Frame }
function Start-FirstRun([string]$only) { $script:Fr = New-FirstRunState; $Fr.ReturnTo = if ($only) { 'settings' } else { $null }; $Fr.Steps.Add($(if ($only) { $only } else { 'bitti' })); $script:Screen = 'firstrun' }
function Fr-Poll { }
function Render-FirstRun([int]$W, [int]$H) { $rows = New-Object System.Collections.Generic.List[string]; $rows.Add(''); $rows.Add('  ilk açılış (iskelet)'); $rows }
function Handle-FirstRunKey([ConsoleKeyInfo]$k, [bool]$ctrl) { $script:Fr = $null; $script:Screen = 'home'; Reset-Frame }
