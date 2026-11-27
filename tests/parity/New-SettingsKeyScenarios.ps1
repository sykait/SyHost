# Ayarlar ekranı için tuş senaryoları üretir (set-keys-*.json)
# Her senaryo ayarlar ekranında başlar, tuşlara basar ve son kareyi iki sürümde karşılaştırır.
# Ek alanlar (yalnızca Compare-SettingsFiles.ps1 okur, iki sürüm de yok sayar):
#   settingsAfter      tuşlardan sonra ayarlar.json'da beklenen alanlar (iki sürümde de)
#   shortcutsAfter     senaryo klasöründeki kısayollar var mı: desktop, start
#   shortcutDescAfter  Masaüstü kısayolunun açıklaması (dil değişince yeniden yazılır)
# Kısayol senaryolarında "shortcuts" test değeri verilmez: durum gerçekten diskten (SYHOST_SHORTCUT_DIR) okunur.
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'scenarios'
$utf8 = New-Object Text.UTF8Encoding $false
$root = 'C:\SyHostTest\Root'
$servers = @(
    [ordered]@{ id = 'icerde'; ad = 'Create Plus'; klasor = "$root\Servers\CreatePlus"; mc = '1.21.1'; loader = 'neoforge'; loaderSurum = '21.1.172'; java = 21; baslat = 'x nogui'; paket = 'normal'; eklenme = '2026-10-02 18:44'; sonAcilis = '2026-11-27 09:15'; sonBaslatmaSn = 48 },
    [ordered]@{ id = 'icerde2'; ad = 'Skyblock'; klasor = "$root\Servers\Skyblock"; mc = '26.1'; loader = 'fabric'; loaderSurum = '0.17.2'; java = 25; baslat = '-jar fabric-server-launch.jar nogui'; paket = 'dusuk'; eklenme = '2026-11-20 21:03'; sonAcilis = $null; sonBaslatmaSn = $null },
    [ordered]@{ id = 'disarda'; ad = 'Eski Dunya'; klasor = 'C:\SyHostTest\Elsewhere\OldWorld'; mc = '1.20.1'; loader = 'forge'; loaderSurum = '47.3.0'; java = 17; baslat = 'x nogui'; paket = 'yuksek'; eklenme = '2026-09-01 10:00'; sonAcilis = '2026-09-02 10:00'; sonBaslatmaSn = 60 }
)
$javaMix = [ordered]@{ '25' = $false; '21' = $true; '17' = $true; '8' = $false }
$shortcutsHook = [ordered]@{ desktop = 'ours'; start = 'none' }

# Beklenen metinler için dil tablosu (uygulamanın kendi tablosu)
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'legacy\src\Lang.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'legacy\src\Lang.Screens.ps1')
function In([string]$lang, [string]$key) { if ($lang -eq 'tr') { return $key }; $TextTable[$key][$lang] }

# o: Cfg (ayar alanları), After (beklenen ayarlar), Links (beklenen kısayollar), Desc, Disk (kısayol test değeri yok),
#    Note/NoteCol, Screen ('home' ile başla), Home (ana menü kareye girerse sabit mod/dünya bilgisi), W, H
function Save-KeyScenario([string]$name, [string]$lang, [double]$t, [int]$sel, [string[]]$keys, [hashtable]$o = @{}) {
    $cfg = [ordered]@{ sunucuKokKlasoru = "$root\Servers"; maksOyuncu = 8; arkadasAdresi = ''; sesAdresi = ''; playitKullan = $false }
    if ($o.Cfg) { foreach ($k in $o.Cfg.Keys) { $cfg[$k] = $o.Cfg[$k] } }
    $set = [ordered]@{ sel = $sel }
    if ($o.Note) { $set.note = $o.Note; $set.noteCol = $o.NoteCol }
    $st = [ordered]@{ appRoot = $root; defaultRoot = 'C:\Users\Test\SyHost'; legacyDir = 'C:\Users\Test\AppData\Local\SyHost'; osBuild = 26200; totalRam = 34359738368; threads = 16; sysFree = 17179869184; fontOk = $true; dryRun = $false }
    $st.javaFound = $javaMix
    if (-not $o.Disk) { $st.shortcuts = $shortcutsHook }
    if ($o.Home) {
        $st.modCounts = [ordered]@{ icerde = 214; icerde2 = 87; disarda = 156 }
        $st.worldSizes = [ordered]@{ icerde = '1450 MB'; icerde2 = '312 MB'; disarda = '980 MB' }
    }
    $st.screen = $(if ($o.Screen) { $o.Screen } else { 'settings' })
    $st.settings = $set
    $st.keys = @($keys)
    $sc = [ordered]@{ t = $t; now = '2026-11-27 14:30:00'; w = $(if ($o.W) { $o.W } else { 129 }); h = $(if ($o.H) { $o.H } else { 41 }); version = '1.0.0'; edition = 'Test'; lang = $lang; cfg = $cfg; servers = $servers; state = $st }
    if ($o.After) { $sc.settingsAfter = $o.After }
    if ($o.Links) { $sc.shortcutsAfter = $o.Links }
    if ($o.Desc) { $sc.shortcutDescAfter = $o.Desc }
    [IO.File]::WriteAllText((Join-Path $out "$name.json"), ($sc | ConvertTo-Json -Depth 12), $utf8)
    $script:n++
}
function Rep([string]$k, [int]$times) { @(for ($i = 0; $i -lt $times; $i++) { $k }) }
$n = 0
$D = 'DownArrow'; $U = 'UpArrow'; $Lf = 'LeftArrow'; $Rt = 'RightArrow'; $En = 'Enter'

# ---------- Gezinme: 13 satır, iki uçta başa/sona sarar; ↑↓ notu siler ----------
Save-KeyScenario 'set-keys-down-all-tr' 'tr' 3.2 0 (Rep $D 14)                        # hepsinden geçip sarar: 1
Save-KeyScenario 'set-keys-up-all-en' 'en' 3.6 0 (Rep $U 14)                          # geriye sarar: 12
Save-KeyScenario 'set-keys-down-wrap-ja' 'ja' 4.1 12 @($D)                            # 12 → 0
Save-KeyScenario 'set-keys-up-wrap-tr' 'tr' 4.4 0 @($U)                               # 0 → 12
Save-KeyScenario 'set-keys-mixed-en' 'en' 4.9 0 ((Rep $D 5) + (Rep $U 2) + (Rep $D 9)) # 12
Save-KeyScenario 'set-keys-note-clear-ja' 'ja' 5.3 6 @($D, $U) @{ Note = (In 'ja' 'Java 21 hazır'); NoteCol = 'green' }

# ---------- ← → ile ayarla, iki uçta durur; Enter +1 ----------
Save-KeyScenario 'set-keys-yazi-min-tr' 'tr' 5.7 4 (Rep $Lf 3) @{ Cfg = @{ yaziTipiBoyutu = 11 }; After = @{ yaziTipiBoyutu = 10 } }
Save-KeyScenario 'set-keys-yazi-max-en' 'en' 6.0 4 (Rep $Rt 3) @{ Cfg = @{ yaziTipiBoyutu = 35 }; After = @{ yaziTipiBoyutu = 36 } }
Save-KeyScenario 'set-keys-yazi-enter-ja' 'ja' 6.3 4 @($En, $Lf, $Lf) @{ After = @{ yaziTipiBoyutu = 15 } }
Save-KeyScenario 'set-keys-oyuncu-min-ja' 'ja' 6.7 7 (Rep $Lf 3) @{ Cfg = @{ maksOyuncu = 2 }; After = @{ maksOyuncu = 1 } }
Save-KeyScenario 'set-keys-oyuncu-max-tr' 'tr' 7.1 7 @($Rt, $Rt, $En) @{ Cfg = @{ maksOyuncu = 199 }; After = @{ maksOyuncu = 200 } }
Save-KeyScenario 'set-keys-yedek-min-en' 'en' 7.4 8 (Rep $Lf 2) @{ Cfg = @{ otomatikYedekSaat = 1 }; After = @{ otomatikYedekSaat = 0 } }
Save-KeyScenario 'set-keys-yedek-max-ja' 'ja' 7.8 8 (Rep $Rt 3) @{ Cfg = @{ otomatikYedekSaat = 23 }; After = @{ otomatikYedekSaat = 24 } }
# Kesirli saat önce yuvarlanır (iki sürümde de banker's: 2.5 → 2, 3.5 → 4)
Save-KeyScenario 'set-keys-yedek-round-tr' 'tr' 8.2 8 @($Rt) @{ Cfg = @{ otomatikYedekSaat = 2.5 }; After = @{ otomatikYedekSaat = 3 } }
Save-KeyScenario 'set-keys-yedek-round2-en' 'en' 8.5 8 @($Lf) @{ Cfg = @{ otomatikYedekSaat = 3.5 }; After = @{ otomatikYedekSaat = 3 } }
# Kesirli saat dokunulmadan gösterilir (iki sürümde de bilgisayarın sayı biçimiyle)
Save-KeyScenario 'set-keys-yedek-frac-tr' 'tr' 8.6 8 @($D, $U) @{ Cfg = @{ otomatikYedekSaat = 1.5 }; After = @{ otomatikYedekSaat = 1.5 } }
Save-KeyScenario 'set-keys-sakla-min-tr' 'tr' 8.9 9 (Rep $Lf 3) @{ Cfg = @{ saklanacakYedek = 2 }; After = @{ saklanacakYedek = 1 } }
Save-KeyScenario 'set-keys-sakla-max-en' 'en' 9.2 9 @($Rt, $En, $Rt) @{ Cfg = @{ saklanacakYedek = 99 }; After = @{ saklanacakYedek = 100 } }
Save-KeyScenario 'set-keys-cokme-enter-ja' 'ja' 9.6 10 @($En) @{ After = @{ cokerseYenidenBaslat = $false } }
Save-KeyScenario 'set-keys-cokme-lr-tr' 'tr' 10.0 10 @($Lf, $Rt, $Rt) @{ After = @{ cokerseYenidenBaslat = $false } }

# ---------- Dil: hemen değişir (sıra en → tr → ja), kare yeni dilde ----------
Save-KeyScenario 'set-keys-dil-right-tr' 'tr' 10.4 0 @($Rt) @{ After = @{ dil = 'ja' } }
Save-KeyScenario 'set-keys-dil-left-tr' 'tr' 10.7 0 @($Lf) @{ After = @{ dil = 'en' } }
Save-KeyScenario 'set-keys-dil-enter-ja' 'ja' 11.1 0 @($En) @{ After = @{ dil = 'en' } }
Save-KeyScenario 'set-keys-dil-left-en' 'en' 11.5 0 @($Lf) @{ After = @{ dil = 'ja' } }
Save-KeyScenario 'set-keys-dil-cycle-en' 'en' 11.8 0 @($Rt, $Rt, $Rt) @{ After = @{ dil = 'en' } }
Save-KeyScenario 'set-keys-dil-combo-ja' 'ja' 12.2 0 ((Rep $D 8) + @($Rt) + (Rep $U 8) + @($Lf)) @{ After = @{ dil = 'tr'; otomatikYedekSaat = 4 } }
Save-KeyScenario 'set-keys-dil-narrow-en' 'en' 12.4 0 @($Rt, $D, $D, $D, $D) @{ W = 96; H = 30; After = @{ dil = 'tr' } }
# Elle yazılmış "TR" bilinmeyen bir dildir (C# Lang.Has büyük-küçük harfe duyarlı): İngilizce açılır, → ile tr'ye geçer
Save-KeyScenario 'set-keys-dil-upper-tr' 'TR' 12.5 0 @($Rt) @{ After = @{ dil = 'tr' } }

# ---------- Kısayollar: Enter ile yazılır, tekrar Enter ile silinir (SYHOST_SHORTCUT_DIR) ----------
Save-KeyScenario 'set-keys-masaustu-on-tr' 'tr' 12.6 2 @($En) @{ Disk = $true; After = @{ kisayolMasaustu = $true; kisayolBaslat = $false }; Links = @{ desktop = $true; start = $false } }
Save-KeyScenario 'set-keys-masaustu-toggle-en' 'en' 13.0 2 @($En, $En) @{ Disk = $true; After = @{ kisayolMasaustu = $false; kisayolBaslat = $false }; Links = @{ desktop = $false; start = $false } }
Save-KeyScenario 'set-keys-baslat-on-ja' 'ja' 13.3 3 @($En) @{ Disk = $true; After = @{ kisayolMasaustu = $false; kisayolBaslat = $true }; Links = @{ desktop = $false; start = $true } }
Save-KeyScenario 'set-keys-baslat-toggle-tr' 'tr' 13.7 3 @($Rt, $Lf) @{ Disk = $true; After = @{ kisayolMasaustu = $false; kisayolBaslat = $false }; Links = @{ desktop = $false; start = $false } }
Save-KeyScenario 'set-keys-kisayol-both-en' 'en' 14.0 2 @($En, $D, $En) @{ Disk = $true; After = @{ kisayolMasaustu = $true; kisayolBaslat = $true }; Links = @{ desktop = $true; start = $true } }
# Dil değişince bizim kısayolumuzun açıklaması yeni dilde yeniden yazılır
Save-KeyScenario 'set-keys-dil-kisayol-tr' 'tr' 14.4 2 @($En, $U, $U, $Rt) @{ Disk = $true; After = @{ dil = 'ja'; kisayolMasaustu = $true; kisayolBaslat = $false }; Links = @{ desktop = $true; start = $false }; Desc = (In 'ja' 'SyHost - modlu Minecraft sunucu merkezi') }

# ---------- Esc ve F9 ana menüye döner; F9 ayarları baştan açar ----------
Save-KeyScenario 'set-keys-esc-tr' 'tr' 14.8 5 @('Escape') @{ Home = $true }
Save-KeyScenario 'set-keys-f9-en' 'en' 15.2 3 @('F9') @{ Home = $true }
Save-KeyScenario 'set-keys-reopen-ja' 'ja' 15.6 7 @('Escape', 'F9') @{ Note = (In 'ja' 'Java 21 hazır'); NoteCol = 'green' }
Save-KeyScenario 'set-keys-home-f9-tr' 'tr' 16.0 0 @('F9') @{ Screen = 'home'; Home = $true }

# ---------- Not ve etkisiz tuşlar ----------
# Java 21 varsa Enter yalnızca not yazar; ← → notu silmez
Save-KeyScenario 'set-keys-java-note-en' 'en' 16.4 6 @($En, $Rt, $Lf)
# Klasör: test modunda pencere açılmaz; Klasörü aç: Explorer açılmaz; ← → bu satırlarda bir şey yapmaz
Save-KeyScenario 'set-keys-noop-ja' 'ja' 16.8 1 (@($En, $Lf, $Rt) + (Rep $D 10) + @($En, $Lf, $Rt, $D, $Lf, $Rt)) @{ After = @{ dil = 'ja'; maksOyuncu = 8; yaziTipiBoyutu = 16 } }
Save-KeyScenario 'set-keys-noop2-tr' 'tr' 17.2 5 @($Lf, $Rt, $D, $Lf, $Rt) @{ After = @{ dil = 'tr' } }

"senaryo yazıldı: $n"
