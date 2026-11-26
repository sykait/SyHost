# Yeni ekranlar için eşlik senaryoları üretir (ilk açılış, ayarlar, kaldır)
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

function Base([string]$lang, [double]$t, $state, $cfg = @{}) {
    $c = [ordered]@{ sunucuKokKlasoru = "$root\Servers"; maksOyuncu = 8; arkadasAdresi = ''; sesAdresi = ''; playitKullan = $false }
    foreach ($k in $cfg.Keys) { $c[$k] = $cfg[$k] }
    $s = [ordered]@{ appRoot = $root; defaultRoot = 'C:\Users\Test\SyHost'; legacyDir = 'C:\Users\Test\AppData\Local\SyHost'; osBuild = 26200; totalRam = 34359738368; threads = 16; sysFree = 17179869184; fontOk = $true; dryRun = $false }
    foreach ($k in $state.Keys) { $s[$k] = $state[$k] }
    [ordered]@{ t = $t; now = '2026-11-27 14:30:00'; w = 129; h = 41; version = '1.0.0'; edition = 'Test'; lang = $lang; cfg = $c; servers = $servers; state = $s }
}
function Save([string]$name, $sc) { [IO.File]::WriteAllText((Join-Path $out "$name.json"), ($sc | ConvertTo-Json -Depth 12), $utf8); $script:n++ }
$n = 0

function Fr($steps, [int]$index, $extra = @{}) { $f = [ordered]@{ steps = $steps; index = $index; sel = 0 }; foreach ($k in $extra.Keys) { $f[$k] = $extra[$k] }; $f }

# ---------- İlk açılış: 1. aşama ----------
$i = 0
foreach ($lang in 'tr', 'en', 'ja') {
    Save "fr-dil-$lang" (Base $lang (1.3 + $i) @{ screen = 'firstrun'; setupMode = $true; firstRun = (Fr @('dil', 'konum') 0 @{ sel = $i; target = 'C:\Users\Test\SyHost' }) })
    $i++
}
Save 'fr-konum-default-tr' (Base 'tr' 2.2 @{ screen = 'firstrun'; setupMode = $true; firstRun = (Fr @('dil', 'konum') 1 @{ target = 'C:\Users\Test\SyHost' }) })
Save 'fr-konum-onedrive-en' (Base 'en' 3.1 @{ screen = 'firstrun'; setupMode = $true; firstRun = (Fr @('dil', 'konum') 1 @{ target = 'C:\Users\Test\OneDrive\Desktop\SyHost'; note = 'This folder syncs with OneDrive. Server files are big and change all the time, so a folder outside OneDrive is recommended.'; noteCol = 'yellow' }) })
Save 'fr-konum-confirm-tr' (Base 'tr' 3.4 @{ screen = 'firstrun'; setupMode = $true; firstRun = (Fr @('dil', 'konum') 1 @{ target = 'C:\Users\Test\OneDrive\SyHost'; confirm = $true; note = "Yine de buraya kurmak için tekrar Enter'a bas."; noteCol = 'yellow' }) })
Save 'fr-konum-update-ja' (Base 'ja' 4.0 @{ screen = 'firstrun'; setupMode = $true; firstRun = (Fr @('dil', 'konum') 1 @{ target = 'C:\Users\Test\SyHost'; otherInstall = 'D:\Games\SyHost'; note = 'ここにはすでに SyHost があります。更新して開きます。'; noteCol = 'green' }) })
Save 'fr-konum-pick-tr' (Base 'tr' 4.6 @{ screen = 'firstrun'; setupMode = $true; firstRun = (Fr @('dil', 'konum') 1 @{ sel = 1; target = 'D:\Oyunlar\SyHost' }) })
Save 'fr-konum-nowrite-en' (Base 'en' 5.2 @{ screen = 'firstrun'; setupMode = $true; firstRun = (Fr @('dil', 'konum') 1 @{ target = 'C:\Program Files\SyHost'; note = "This folder can't be written to. Choose another one."; noteCol = 'red' }) })

# ---------- İlk açılış: 2. aşama ----------
$i = 0
foreach ($lang in 'tr', 'en', 'ja') {
    Save "fr-tasima-$lang" (Base $lang (2.0 + $i) @{ screen = 'firstrun'; migrated = @{ servers = 2 + $i; playit = ($i -ne 1) }; firstRun = (Fr $phase2 0) })
    $i++
}
Save 'fr-tasima-ask-tr' (Base 'tr' 2.7 @{ screen = 'firstrun'; movedTo = 'D:\Eski\SyHost'; firstRun = (Fr $phase2 0 @{ sel = 1 }) })
Save 'fr-sistem-tr' (Base 'tr' 3.3 @{ screen = 'firstrun'; firstRun = (Fr $phase2 1) })
Save 'fr-sistem-en' (Base 'en' 3.8 @{ screen = 'firstrun'; firstRun = (Fr $phase2NoMig 0) })
Save 'fr-sistem-lowram-ja' (Base 'ja' 4.4 @{ screen = 'firstrun'; osBuild = 19045; totalRam = 6442450944; threads = 4; firstRun = (Fr $phase2NoMig 0) })
Save 'fr-java-have-tr' (Base 'tr' 5.0 @{ screen = 'firstrun'; javaFound = @{ '21' = $true }; javaOwn = $false; firstRun = (Fr $phase2 2) })
Save 'fr-java-own-en' (Base 'en' 5.5 @{ screen = 'firstrun'; javaFound = @{ '21' = $true }; javaOwn = $true; firstRun = (Fr $phase2NoMig 1) })
Save 'fr-java-ask-ja' (Base 'ja' 6.1 @{ screen = 'firstrun'; javaFound = @{ '21' = $false }; firstRun = (Fr $phase2NoMig 1) })
Save 'fr-java-later-tr' (Base 'tr' 6.6 @{ screen = 'firstrun'; javaFound = @{ '21' = $false }; firstRun = (Fr $phase2NoMig 1 @{ sel = 1 }) })
Save 'fr-java-busy-tr' (Base 'tr' 7.2 @{ screen = 'firstrun'; javaFound = @{ '21' = $false }; firstRun = (Fr $phase2NoMig 1 @{ busy = $true; jobText = 'OpenJDK21U-jre_x64_windows_hotspot_21.0.13_1.zip  ·  %62' }) })
Save 'fr-java-error-en' (Base 'en' 7.9 @{ screen = 'firstrun'; javaFound = @{ '21' = $false }; firstRun = (Fr $phase2NoMig 1 @{ note = "Couldn't download Java 21: The remote name could not be resolved: 'api.adoptium.net'"; noteCol = 'red' }) })
$i = 0
foreach ($lang in 'tr', 'en', 'ja') {
    Save "fr-arkadas-ask-$lang" (Base $lang (8.0 + $i) @{ screen = 'firstrun'; playitReady = $false; firstRun = (Fr $phase2NoMig 2 @{ phase = 'soru'; sel = ($i % 2) }) })
    $i++
}
Save 'fr-arkadas-ready-tr' (Base 'tr' 9.3 @{ screen = 'firstrun'; playitReady = $true; firstRun = (Fr $phase2 3 @{ phase = 'soru' }) } @{ arkadasAdresi = 'ornek-ad.joinmc.link'; playitKullan = $true })
Save 'fr-arkadas-ready-relink-ja' (Base 'ja' 9.6 @{ screen = 'firstrun'; playitReady = $true; firstRun = (Fr $phase2 3 @{ phase = 'soru'; sel = 1 }) } @{ arkadasAdresi = 'ornek-ad.joinmc.link'; playitKullan = $true })
Save 'fr-arkadas-error-en' (Base 'en' 9.9 @{ screen = 'firstrun'; playitReady = $false; firstRun = (Fr $phase2NoMig 2 @{ phase = 'soru'; note = 'The playit link was not completed. You can try again.'; noteCol = 'yellow' }) })
Save 'fr-arkadas-indir-en' (Base 'en' 10.4 @{ screen = 'firstrun'; firstRun = (Fr $phase2NoMig 2 @{ phase = 'indir'; busy = $true; jobText = 'Downloading playit...' }) })
Save 'fr-arkadas-bagla-ja' (Base 'ja' 10.9 @{ screen = 'firstrun'; firstRun = (Fr $phase2NoMig 2 @{ phase = 'bagla'; busy = $true; jobText = 'ブラウザでの承認を待っています（最大 10 分）...' }) })
Save 'fr-arkadas-adres-tr' (Base 'tr' 11.5 @{ screen = 'firstrun'; firstRun = (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 0; mcAddr = 'ornek-ad.joinmc' }) })
Save 'fr-arkadas-adres-blink-tr' (Base 'tr' 11.75 @{ screen = 'firstrun'; firstRun = (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 0; mcAddr = 'ornek-ad.joinmc' }) })
Save 'fr-arkadas-adres2-en' (Base 'en' 12.0 @{ screen = 'firstrun'; firstRun = (Fr $phase2NoMig 2 @{ phase = 'adres'; field = 1; mcAddr = 'some-name.joinmc.link'; voiceAddr = 'voice.tun.ply.gg:24454'; note = "That address doesn't look right. Example: some-name.joinmc.link"; noteCol = 'yellow' }) })
Save 'fr-arkadas-hazir-ja' (Base 'ja' 12.6 @{ screen = 'firstrun'; firstRun = (Fr $phase2NoMig 2 @{ phase = 'hazir' }) } @{ arkadasAdresi = 'ornek-ad.joinmc.link'; sesAdresi = 'ses.tun.ply.gg:24454'; playitKullan = $true })
Save 'fr-yazi-ok-tr' (Base 'tr' 13.0 @{ screen = 'firstrun'; fontOk = $true; firstRun = (Fr $phase2 4) })
Save 'fr-yazi-install-en' (Base 'en' 13.4 @{ screen = 'firstrun'; fontOk = $false; firstRun = (Fr $phase2NoMig 3) })
Save 'fr-yazi-fail-ja' (Base 'ja' 13.9 @{ screen = 'firstrun'; fontOk = $false; firstRun = (Fr $phase2NoMig 3 @{ confirm = $true; note = 'フォントをインストールできませんでした。SyHost は動作しますが、一部の記号の見た目が変わる場合があります。'; noteCol = 'yellow' }) })
Save 'fr-kisayol-tr' (Base 'tr' 14.3 @{ screen = 'firstrun'; firstRun = (Fr $phase2 5 @{ desk = $true; start = $false }) })
Save 'fr-kisayol-other-en' (Base 'en' 14.8 @{ screen = 'firstrun'; firstRun = (Fr $phase2NoMig 4 @{ sel = 1; note = 'The SyHost shortcut on your desktop opens another SyHost; it will be replaced with this one.'; noteCol = 'yellow' }) })
$i = 0
foreach ($lang in 'tr', 'en', 'ja') { Save "fr-bitti-$lang" (Base $lang (15.0 + $i) @{ screen = 'firstrun'; firstRun = (Fr $phase2 6) }); $i++ }
Save 'fr-single-arkadas-tr' (Base 'tr' 16.2 @{ screen = 'firstrun'; playitReady = $false; firstRun = (Fr @('arkadas') 0 @{ returnTo = 'settings'; phase = 'soru' }) })
Save 'fr-single-java-en' (Base 'en' 16.7 @{ screen = 'firstrun'; javaFound = @{ '21' = $false }; firstRun = (Fr @('java') 0 @{ returnTo = 'settings' }) })

# ---------- Ayarlar ----------
$javaMix = @{ '25' = $false; '21' = $true; '17' = $true; '8' = $false }
$sc = @{ desktop = 'ours'; start = 'none' }
$cases = @(
    @('set-sel0-tr', 'tr', 0, @{}, @{}), @('set-sel1-en', 'en', 1, @{}, @{}), @('set-sel2-ja', 'ja', 2, @{}, @{}),
    @('set-sel3-tr', 'tr', 3, @{}, @{}), @('set-sel4-en', 'en', 4, @{}, @{ yaziTipiBoyutu = 18 }), @('set-sel5-ja', 'ja', 5, @{}, @{}),
    @('set-sel5-on-tr', 'tr', 5, @{ playitOn = $true }, @{ arkadasAdresi = 'ornek-ad.joinmc.link'; playitKullan = $true }),
    @('set-sel5-conn-en', 'en', 5, @{ playitOn = $false }, @{ arkadasAdresi = 'some-name.joinmc.link'; playitKullan = $true }),
    @('set-sel6-tr', 'tr', 6, @{}, @{}), @('set-sel7-en', 'en', 7, @{}, @{}), @('set-sel8-ja', 'ja', 8, @{}, @{ otomatikYedekSaat = 0 }),
    @('set-sel9-tr', 'tr', 9, @{}, @{ saklanacakYedek = 25 }), @('set-sel10-en', 'en', 10, @{}, @{ cokerseYenidenBaslat = $false }),
    @('set-sel11-ja', 'ja', 11, @{}, @{}), @('set-sel12-tr', 'tr', 12, @{}, @{}), @('set-sel12-en', 'en', 12, @{}, @{})
)
foreach ($cs in $cases) {
    $st = @{ screen = 'settings'; settings = @{ sel = $cs[2] }; javaFound = $javaMix; shortcuts = $sc }
    foreach ($k in $cs[3].Keys) { $st[$k] = $cs[3][$k] }
    Save $cs[0] (Base $cs[1] (3.0 + $cs[2] * 0.37) $st $cs[4])
}
Save 'set-other-tr' (Base 'tr' 6.4 @{ screen = 'settings'; settings = @{ sel = 2 }; javaFound = $javaMix; shortcuts = @{ desktop = 'other'; start = 'ours' } })
Save 'set-note-ja' (Base 'ja' 6.9 @{ screen = 'settings'; settings = @{ sel = 1; note = 'このフォルダーは OneDrive と同期されています。サーバーのファイルは大きく常に変化するため、OneDrive の外をおすすめします。'; noteCol = 'yellow' }; javaFound = $javaMix; shortcuts = $sc })
Save 'set-note-java-en' (Base 'en' 7.3 @{ screen = 'settings'; settings = @{ sel = 6; note = 'Java 21 is ready'; noteCol = 'green' }; javaFound = $javaMix; shortcuts = $sc })

# ---------- Kaldır ----------
function Items([bool]$folder, [int[]]$states = @(0, 0, 0, 0, 0, 0, 0)) {
    @(
        [ordered]@{ key = 'kisayol'; title = 'Masaüstü ve Başlat menüsü kısayolları'; detail = 'C:\Users\Test\Desktop\SyHost.lnk  ·  C:\Users\Test\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\SyHost.lnk'; on = $true; needsAdmin = $false; state = $states[0] },
        [ordered]@{ key = 'yazitipi'; title = "SyHost'un kurduğu Cascadia Mono yazı tipi"; detail = 'C:\Users\Test\AppData\Local\Microsoft\Windows\Fonts'; on = $true; needsAdmin = $false; state = $states[1] },
        [ordered]@{ key = 'eskiveri'; title = 'Eski sürümün veri klasörü'; detail = 'C:\Users\Test\AppData\Local\SyHost'; on = $false; needsAdmin = $false; state = $states[2] },
        [ordered]@{ key = 'eskikurulum'; title = 'Eski sürümün program klasörü'; detail = 'C:\Users\Test\AppData\Local\Programs\SyHost'; on = $false; needsAdmin = $false; state = $states[3] },
        [ordered]@{ key = 'eskiplayit'; title = 'Eski playit kurulumu (Program Files)'; detail = 'playit'; on = $false; needsAdmin = $true; state = $states[4] },
        [ordered]@{ key = 'java'; title = 'Java (başka programlar da kullanıyor olabilir)'; detail = 'Microsoft Build of OpenJDK with Hotspot 21.0.13+11 (x64)'; on = $false; needsAdmin = $true; state = $states[5] },
        [ordered]@{ key = 'klasor'; title = 'SyHost klasörünün kendisi'; detail = $root; on = $folder; needsAdmin = $false; state = $states[6] }
    )
}
Save 'un-list-tr' (Base 'tr' 4.1 @{ screen = 'uninstall'; uninstall = @{ items = (Items $false); sel = 0; phase = 'liste' } })
Save 'un-list-sel4-en' (Base 'en' 4.6 @{ screen = 'uninstall'; uninstall = @{ items = (Items $false); sel = 4; phase = 'liste' } })
Save 'un-list-klasor-ja' (Base 'ja' 5.2 @{ screen = 'uninstall'; uninstall = @{ items = (Items $true); sel = 6; phase = 'liste' } })
Save 'un-onay-tr' (Base 'tr' 5.8 @{ screen = 'uninstall'; uninstall = @{ items = (Items $true); sel = 6; phase = 'onay' } })
Save 'un-onay-en' (Base 'en' 6.3 @{ screen = 'uninstall'; uninstall = @{ items = (Items $true); sel = 6; phase = 'onay' } })
Save 'un-calisiyor-ja' (Base 'ja' 6.9 @{ screen = 'uninstall'; uninstall = @{ items = (Items $true @(2, 1, 4, 4, 4, 4, 0)); sel = 0; phase = 'calisiyor' } })
$err = Items $false @(2, 3, 4, 4, 4, 4, 4); $err[1].error = 'izin verilmedi'
Save 'un-bitti-error-tr' (Base 'tr' 7.4 @{ screen = 'uninstall'; uninstall = @{ items = $err; sel = 0; phase = 'bitti' } })
Save 'un-bitti-folder-en' (Base 'en' 7.9 @{ screen = 'uninstall'; uninstall = @{ items = (Items $true @(2, 2, 4, 4, 4, 4, 2)); sel = 0; phase = 'bitti' } })
Save 'un-bitti-dry-ja' (Base 'ja' 8.5 @{ screen = 'uninstall'; dryRun = $true; uninstall = @{ items = (Items $false @(2, 2, 4, 4, 4, 4, 4)); sel = 0; phase = 'bitti' } })

"senaryo yazıldı: $n"
