# İlk açılış ekranının tuş senaryolarını üretir (fr-keys-*.json): durum kurulur, tuşlara basılır, kare karşılaştırılır.
# Yalnızca senaryo klasöründe yan etkisi olan tuşlar kullanılır: indirme, kurulum, pencere ya da tarayıcı açan tuşlar yok.
# Yazılamayan hedef için C:\Windows\win.ini\... kullanılır: bir dosyanın altında klasör açılamaz, diske hiçbir şey yazılmaz.
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot "scenarios"
$utf8 = New-Object Text.UTF8Encoding $false
$root = 'C:\SyHostTest\Root'
$servers = @(
    [ordered]@{ id = 'icerde'; ad = 'Create Plus'; klasor = "$root\Servers\CreatePlus"; mc = '1.21.1'; loader = 'neoforge'; loaderSurum = '21.1.172'; java = 21; baslat = 'x nogui'; paket = 'normal'; eklenme = '2026-10-02 18:44'; sonAcilis = '2026-11-27 09:15'; sonBaslatmaSn = 48 },
    [ordered]@{ id = 'icerde2'; ad = 'Skyblock'; klasor = "$root\Servers\Skyblock"; mc = '26.1'; loader = 'fabric'; loaderSurum = '0.17.2'; java = 25; baslat = '-jar fabric-server-launch.jar nogui'; paket = 'dusuk'; eklenme = '2026-11-20 21:03'; sonAcilis = $null; sonBaslatmaSn = $null },
    [ordered]@{ id = 'disarda'; ad = 'Eski Dunya'; klasor = 'C:\SyHostTest\Elsewhere\OldWorld'; mc = '1.20.1'; loader = 'forge'; loaderSurum = '47.3.0'; java = 17; baslat = 'x nogui'; paket = 'yuksek'; eklenme = '2026-09-01 10:00'; sonAcilis = '2026-09-02 10:00'; sonBaslatmaSn = 60 }
)
$phase2 = @('tasima', 'sistem', 'java', 'arkadas', 'yazi', 'kisayol', 'bitti')
$phase2NoMig = @('sistem', 'java', 'arkadas', 'yazi', 'kisayol', 'bitti')
$noWrite = 'C:\Windows\win.ini\SyHost'
$noWriteOd = 'C:\Windows\win.ini\OneDrive\SyHost'
$odNote = @{ tr = 'Bu klasör OneDrive ile eşitleniyor. Sunucu dosyaları büyük ve sürekli değişir; OneDrive dışında bir yer önerilir.'; en = 'This folder syncs with OneDrive. Server files are big and change all the time, so a folder outside OneDrive is recommended.'; ja = 'このフォルダーは OneDrive と同期されています。サーバーのファイルは大きく常に変化するため、OneDrive の外をおすすめします。' }
# Ana menüde biten senaryolar için (mod sayısı ve dünya boyutu diske bakılmadan)
$homeCache = @{ modCounts = [ordered]@{ icerde = 214; icerde2 = 87; disarda = 0 }; worldSizes = [ordered]@{ icerde = '1450 MB'; icerde2 = '312 MB'; disarda = '980 MB' } }

function Base([string]$lang, [double]$t, $state, $cfg = @{}, [switch]$RealRam) {
    $c = [ordered]@{ sunucuKokKlasoru = "$root\Servers"; maksOyuncu = 8; arkadasAdresi = ''; sesAdresi = ''; playitKullan = $false }
    foreach ($k in @($cfg.PSBase.Keys)) { $c[$k] = $cfg[$k] }
    $s = [ordered]@{ appRoot = $root; defaultRoot = 'C:\Users\Test\SyHost'; legacyDir = 'C:\Users\Test\AppData\Local\SyHost'; osBuild = 26200; totalRam = 34359738368; threads = 16; sysFree = 17179869184; fontOk = $true; dryRun = $false }
    # Eski veriler kopyalanınca ayarlar yeniden okunur ve RAM ile çekirdek sayısı bu bilgisayarınkine döner (iki sürümde de)
    if ($RealRam) { $s.Remove('totalRam'); $s.Remove('threads') }
    foreach ($k in @($state.PSBase.Keys)) { $s[$k] = $state[$k] }   # PSBase: içinde "keys" alanı var, $state.Keys onu döndürürdü
    [ordered]@{ t = $t; now = '2026-11-27 14:30:00'; w = 129; h = 41; version = '1.0.0'; edition = 'Test'; lang = $lang; cfg = $c; servers = $servers; state = $s }
}
function Save([string]$name, $sc) { [IO.File]::WriteAllText((Join-Path $out "fr-keys-$name.json"), ($sc | ConvertTo-Json -Depth 12), $utf8); $script:n++ }
$n = 0
function Fr($steps, [int]$index, $extra = @{}) { $f = [ordered]@{ steps = @($steps); index = $index; sel = 0 }; foreach ($k in $extra.Keys) { $f[$k] = $extra[$k] }; $f }
# Senaryonun state'i: ekran, ek alanlar, ilk açılış durumu ve basılacak tuşlar ($s.keys değil: o sözlüğün Keys özelliğidir)
function St($firstRun, [string[]]$keys, $extra = @{}) { $s = [ordered]@{ screen = 'firstrun' }; foreach ($k in @($extra.PSBase.Keys)) { $s[$k] = $extra[$k] }; $s['firstRun'] = $firstRun; $s['keys'] = @($keys); $s }

# ---------- 1. aşama: dil ----------
Save 'dil-down-tr' (Base 'tr' 1.4 (St (Fr @('dil', 'konum') 0 @{ sel = 1; target = 'C:\Users\Test\SyHost' }) @('DownArrow') @{ setupMode = $true }))
Save 'dil-up-en' (Base 'en' 1.9 (St (Fr @('dil', 'konum') 0 @{ sel = 0; target = 'C:\Users\Test\SyHost' }) @('UpArrow', 'UpArrow') @{ setupMode = $true }))
Save 'dil-enter-ja' (Base 'ja' 2.3 (St (Fr @('dil', 'konum') 0 @{ sel = 2; target = 'C:\Users\Test\SyHost' }) @('UpArrow', 'Enter') @{ setupMode = $true }))
# Konum adımı yok (exe kendi boş klasöründe): Enter oraya kurar; yazılamıyorsa neden dil adımında görünür
Save 'dil-only-tr' (Base 'tr' 2.6 (St (Fr @('dil') 0 @{ sel = 1; target = $noWrite }) @('Enter') @{ setupMode = $true }))

# ---------- 1. aşama: konum ----------
Save 'konum-moves-ja' (Base 'ja' 4.1 (St (Fr @('dil', 'konum') 1 @{ target = 'C:\Users\Test\SyHost'; otherInstall = 'D:\Games\SyHost'; note = 'ここにはすでに SyHost があります。更新して開きます。'; noteCol = 'green' }) @('DownArrow') @{ setupMode = $true }))
Save 'konum-wrap-tr' (Base 'tr' 4.3 (St (Fr @('dil', 'konum') 1 @{ target = 'C:\Users\Test\SyHost'; otherInstall = 'D:\Games\SyHost' }) @('UpArrow') @{ setupMode = $true }))
Save 'konum-around-en' (Base 'en' 4.5 (St (Fr @('dil', 'konum') 1 @{ target = 'C:\Users\Test\SyHost'; otherInstall = 'D:\Games\SyHost' }) @('DownArrow', 'DownArrow', 'DownArrow') @{ setupMode = $true }))
Save 'konum-esc-tr' (Base 'tr' 4.8 (St (Fr @('dil', 'konum') 1 @{ target = 'C:\Users\Test\SyHost' }) @('Escape') @{ setupMode = $true }))
Save 'konum-pick-en' (Base 'en' 5.0 (St (Fr @('dil', 'konum') 1 @{ sel = 1; target = 'D:\Oyunlar\SyHost' }) @('Enter') @{ setupMode = $true }))
Save 'konum-onedrive1-en' (Base 'en' 5.3 (St (Fr @('dil', 'konum') 1 @{ target = $noWriteOd; note = $odNote.en; noteCol = 'yellow' }) @('Enter') @{ setupMode = $true }))
Save 'konum-onedrive2-tr' (Base 'tr' 5.6 (St (Fr @('dil', 'konum') 1 @{ target = $noWriteOd; note = $odNote.tr; noteCol = 'yellow' }) @('Enter', 'Enter') @{ setupMode = $true }))
Save 'konum-confirm-reset-ja' (Base 'ja' 5.9 (St (Fr @('dil', 'konum') 1 @{ target = $noWriteOd; note = $odNote.ja; noteCol = 'yellow' }) @('Enter', 'DownArrow', 'UpArrow', 'Enter') @{ setupMode = $true }))

# ---------- 2. aşama: eski veriler ----------
Save 'tasima-toggle-tr' (Base 'tr' 2.8 (St (Fr $phase2 0 @{ sel = 1 }) @('DownArrow') @{ movedTo = 'D:\Eski\SyHost' }))
Save 'tasima-fresh-en' (Base 'en' 3.0 (St (Fr $phase2 0 @{ sel = 1 }) @('Enter') @{ movedTo = 'D:\Eski\SyHost' }))
Save 'tasima-back-ja' (Base 'ja' 3.2 (St (Fr $phase2 0 @{ sel = 1 }) @('Enter', 'Escape') @{ movedTo = 'D:\Eski\SyHost' }))
Save 'tasima-copy-tr' (Base 'tr' 3.4 (St (Fr $phase2 0 @{ sel = 1 }) @('UpArrow', 'Enter') @{ movedTo = 'D:\Eski\SyHost' }) -RealRam)
Save 'tasima-done-en' (Base 'en' 3.5 (St (Fr $phase2 0) @('Enter') @{ migrated = @{ servers = 3; playit = $true } }))

# ---------- 2. aşama: sistem, Java ----------
Save 'sistem-enter-en' (Base 'en' 3.6 (St (Fr $phase2NoMig 0) @('Enter') @{ javaFound = @{ '21' = $true }; javaOwn = $false }))
Save 'sistem-esc-tr' (Base 'tr' 3.8 (St (Fr $phase2 1) @('Escape') @{ migrated = @{ servers = 2; playit = $true } }))
Save 'java-later-tr' (Base 'tr' 6.2 (St (Fr $phase2NoMig 1) @('DownArrow', 'Enter') @{ javaFound = @{ '21' = $false }; playitReady = $false }))
Save 'java-toggle-en' (Base 'en' 6.4 (St (Fr $phase2NoMig 1) @('UpArrow') @{ javaFound = @{ '21' = $false } }))
Save 'java-have-esc-ja' (Base 'ja' 6.6 (St (Fr $phase2NoMig 1) @('Escape') @{ javaFound = @{ '21' = $true }; javaOwn = $true }))
Save 'java-have-enter-tr' (Base 'tr' 6.8 (St (Fr $phase2NoMig 1) @('Enter') @{ javaFound = @{ '21' = $true }; playitReady = $false }))
Save 'java-busy-tr' (Base 'tr' 7.3 (St (Fr $phase2NoMig 1 @{ busy = $true; jobText = 'OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11.zip  ·  23 / 48 MB' }) @('DownArrow', 'Enter', 'Escape') @{ javaFound = @{ '21' = $false } }))

# ---------- 2. aşama: arkadaşlar ----------
Save 'arkadas-toggle-tr' (Base 'tr' 8.2 (St (Fr $phase2NoMig 2 @{ phase = 'soru' }) @('DownArrow') @{ playitReady = $false }))
Save 'arkadas-no-en' (Base 'en' 8.4 (St (Fr $phase2NoMig 2 @{ phase = 'soru' }) @('DownArrow', 'Enter') @{ playitReady = $false }) @{ playitKullan = $true })
Save 'arkadas-esc-ja' (Base 'ja' 8.6 (St (Fr $phase2NoMig 2 @{ phase = 'soru' }) @('Escape') @{ playitReady = $false; javaFound = @{ '21' = $true }; javaOwn = $false }))
Save 'arkadas-ready-tr' (Base 'tr' 9.4 (St (Fr $phase2 3 @{ phase = 'soru' }) @('Enter') @{ playitReady = $true }) @{ arkadasAdresi = 'ornek-ad.joinmc.link'; playitKullan = $true })
Save 'arkadas-cancel-en' (Base 'en' 10.9 (St (Fr $phase2NoMig 2 @{ phase = 'bagla'; busy = $true; jobText = 'Waiting for you to approve it in the browser (up to 10 minutes)...' }) @('DownArrow', 'Enter', 'Escape') @{ playitReady = $false }))
Save 'arkadas-indir-esc-ja' (Base 'ja' 10.5 (St (Fr $phase2NoMig 2 @{ phase = 'indir'; busy = $true; jobText = 'playit をダウンロード中...' }) @('Escape') @{ playitReady = $false }))
Save 'adres-type-tr' (Base 'tr' 11.5 (St (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 0; mcAddr = 'ornek-ad.joinmc' }) @('.', 'l', 'i', 'n', 'x', 'Backspace', 'k')))
Save 'adres-next-en' (Base 'en' 11.7 (St (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 0; mcAddr = 'some-name.joinmc.lin' }) @('k', 'Enter')))
Save 'adres-bad-ja' (Base 'ja' 11.9 (St (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 0; mcAddr = 'bad' }) @('Enter')))
Save 'adres-voice-tr' (Base 'tr' 12.1 (St (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 1; mcAddr = 'ornek-ad.joinmc.link' }) @('v', '.', 't', 'u', 'x', 'Backspace', 'n', ':', '2', '4', 'Enter')))
Save 'adres-voicebad-en' (Base 'en' 12.3 (St (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 1; mcAddr = 'some-name.joinmc.link'; voiceAddr = 'nope' }) @('Enter')))
Save 'adres-esc-ja' (Base 'ja' 12.5 (St (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 1; mcAddr = 'ornek-ad.joinmc.link'; voiceAddr = 'ses.tun' }) @('Escape')))
Save 'adres-esc2-tr' (Base 'tr' 12.7 (St (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 1; mcAddr = 'ornek-ad.joinmc.link' }) @('Escape', 'Escape') @{ playitReady = $false }))
Save 'adres-trim-en' (Base 'en' 12.9 (St (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 0; mcAddr = 'some-name.joinmc.link' }) @(' ', 'Enter')))
Save 'hazir-enter-ja' (Base 'ja' 13.1 (St (Fr $phase2NoMig 2 @{ phase = 'hazir' }) @('Enter') @{ fontOk = $true }) @{ arkadasAdresi = 'ornek-ad.joinmc.link'; sesAdresi = 'ses.tun.ply.gg:24454'; playitKullan = $true })

# ---------- 2. aşama: yazı tipi ----------
Save 'yazi-ok-tr' (Base 'tr' 13.2 (St (Fr $phase2 4) @('Enter') @{ fontOk = $true }))
Save 'yazi-fail-en' (Base 'en' 13.5 (St (Fr $phase2NoMig 3) @('Enter') @{ fontOk = $false }))
Save 'yazi-fail-next-ja' (Base 'ja' 13.7 (St (Fr $phase2NoMig 3) @('Enter', 'Enter') @{ fontOk = $false }))
Save 'yazi-esc-tr' (Base 'tr' 13.9 (St (Fr $phase2NoMig 3) @('Escape') @{ fontOk = $true; playitReady = $false }))

# ---------- 2. aşama: kısayollar (Enter kısayolları senaryo klasörüne yazar: SYHOST_SHORTCUT_DIR) ----------
Save 'kisayol-space-tr' (Base 'tr' 14.4 (St (Fr $phase2 5 @{ desk = $true; start = $true }) @('Spacebar')))
Save 'kisayol-space2-en' (Base 'en' 14.6 (St (Fr $phase2 5 @{ desk = $true; start = $true }) @('DownArrow', 'Spacebar')))
Save 'kisayol-apply-ja' (Base 'ja' 14.9 (St (Fr $phase2 5 @{ desk = $true; start = $false }) @('DownArrow', 'Spacebar', 'Enter')))
Save 'kisayol-off-tr' (Base 'tr' 15.1 (St (Fr $phase2 5 @{ desk = $true; start = $true }) @('Spacebar', 'DownArrow', 'Spacebar', 'Enter')))
Save 'kisayol-esc-en' (Base 'en' 15.3 (St (Fr $phase2NoMig 4) @('Escape') @{ fontOk = $false }))

# ---------- 2. aşama: hazır → ana menü ----------
$st = St (Fr $phase2 6) @('Enter'); foreach ($k in $homeCache.Keys) { $st[$k] = $homeCache[$k] }
Save 'bitti-enter-tr' (Base 'tr' 15.5 $st)
$st = St (Fr $phase2NoMig 5) @('Enter'); foreach ($k in $homeCache.Keys) { $st[$k] = $homeCache[$k] }
Save 'bitti-enter-ja' (Base 'ja' 15.7 $st)

# ---------- Ayarlar'dan tek adım ----------
Save 'single-java-tr' (Base 'tr' 16.8 (St (Fr @('java') 0 @{ returnTo = 'settings' }) @('DownArrow') @{ javaFound = @{ '21' = $false } }))
Save 'single-f10-en' (Base 'en' 17.6 (St (Fr @('java') 0 @{ returnTo = 'settings' }) @('F10') @{ javaFound = @{ '21' = $false } }))
# Esc tek adımdan Ayarlar'a döner; ikinci Esc Ayarlar'dan ana menüye (iki sürümde de)
$st = St (Fr @('java') 0 @{ returnTo = 'settings' }) @('Escape', 'Escape') @{ javaFound = @{ '21' = $false } }; foreach ($k in $homeCache.Keys) { $st[$k] = $homeCache[$k] }
Save 'single-esc-en' (Base 'en' 17.0 $st)
$st = St (Fr @('java') 0 @{ returnTo = 'settings' }) @('DownArrow', 'Enter', 'Escape') @{ javaFound = @{ '21' = $false } }; foreach ($k in $homeCache.Keys) { $st[$k] = $homeCache[$k] }
Save 'single-later-ja' (Base 'ja' 17.2 $st)
$st = St (Fr @('arkadas') 0 @{ returnTo = 'settings'; phase = 'soru' }) @('DownArrow', 'Enter', 'Escape') @{ playitReady = $false }; foreach ($k in $homeCache.Keys) { $st[$k] = $homeCache[$k] }
Save 'single-arkadas-tr' (Base 'tr' 17.4 $st @{ arkadasAdresi = 'ornek-ad.joinmc.link'; playitKullan = $true })

"senaryo yazıldı: $n"
