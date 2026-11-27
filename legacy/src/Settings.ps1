# =====================================================================
#  SyHost - Ayarlar ekranı (ana menüde F9)  (Terminal sürümü)
#  C# karşılığı: src\SyHost\App\App.Settings.cs. İki sürüm aynı kareyi çizer (tests\parity).
#  Görünüm ana menüdeki liste gibi: seçili satır nabız gibi atan koyu kırmızı
#  zeminle vurgulanır, altta seçili ayarın açıklaması kartta görünür.
#  Her değişiklik hemen ayarlar.json'a yazılır.
# =====================================================================
$SetSel = 0; $SetNote = $null; $SetNoteCol = $null

# Satırlar: anahtar, grup, etiket, açıklama (etiket, grup ve açıklama L ile çevrilir)
$SettingRows = @(
    [pscustomobject]@{ Key = 'dil'; Group = 'GENEL'; Label = 'Dil'; Help = 'Arayüzün dili. Klasör adları da bu dilde görünür.' }
    [pscustomobject]@{ Key = 'klasor'; Group = 'GENEL'; Label = 'Sunucu klasörü'; Help = 'Yeni sunucuların kurulacağı yer. Enter ile değiştir.' }
    [pscustomobject]@{ Key = 'masaustu'; Group = 'GENEL'; Label = 'Masaüstü kısayolu'; Help = 'Enter ile aç ya da kapat.' }
    [pscustomobject]@{ Key = 'baslat'; Group = 'GENEL'; Label = 'Başlat menüsü kısayolu'; Help = 'Enter ile aç ya da kapat.' }
    [pscustomobject]@{ Key = 'yazi'; Group = 'GENEL'; Label = 'Yazı boyutu'; Help = '← → ile ayarla. Pencere yeni boyuta göre büyür ya da küçülür.' }
    [pscustomobject]@{ Key = 'arkadas'; Group = 'SUNUCU'; Label = 'Arkadaş bağlantısı (playit)'; Help = 'Arkadaşlarının internetten bağlanması için. Enter ile kur ya da yeniden bağla.' }
    [pscustomobject]@{ Key = 'java'; Group = 'SUNUCU'; Label = 'Java'; Help = "Bulunan Java sürümleri. Enter ile Java 21'i SyHost klasörüne indir." }
    [pscustomobject]@{ Key = 'oyuncu'; Group = 'SUNUCU'; Label = 'Maksimum oyuncu'; Help = 'Yeni kurulan sunucular için. ← → ile ayarla.' }
    [pscustomobject]@{ Key = 'yedek'; Group = 'SUNUCU'; Label = 'Otomatik yedek'; Help = 'Sunucu açıkken dünya kaç saatte bir yedeklensin. 0 = kapalı.' }
    [pscustomobject]@{ Key = 'sakla'; Group = 'SUNUCU'; Label = 'Saklanacak yedek'; Help = 'Her sunucuda tutulacak en yeni yedek sayısı.' }
    [pscustomobject]@{ Key = 'cokme'; Group = 'SUNUCU'; Label = 'Çökerse yeniden başlat'; Help = 'Sunucu beklenmedik şekilde kapanırsa 10 saniye sonra yeniden açılır.' }
    [pscustomobject]@{ Key = 'ac'; Group = 'SYHOST'; Label = 'Klasörü aç'; Help = "SyHost klasörünü Explorer'da açar." }
    [pscustomobject]@{ Key = 'kaldir'; Group = 'SYHOST'; Label = "SyHost'u kaldır"; Help = 'Kısayolları ve klasör dışındaki izleri kaldırır; istersen klasörü de siler.' }
)

# ---------- Yavaş sorgular için önbellek ----------
# C# sürümü Java'yı (4 sürüm) ve iki kısayolu her karede sorar. PowerShell'de bu her karede diske gider ve
# ekran takılır; burada sonuç saklanır. Yenilenir: ekran açılınca, her değişiklikten sonra (ilk açılışın tek
# adımına ya da kaldır ekranına gidince de; dönünce taze okunur) ve en geç 2 saniyede bir.
# Değerler C#'taki yardımcılarla (Find-Java, Get-ShortcutState) bulunur: kare aynı kalır.
$SetCache = $null
$SetClock = [Diagnostics.Stopwatch]::StartNew()
function Update-SettingsCache {
    $java = @{}
    foreach ($m in 25, 21, 17, 8) { $java[$m] = $false; try { $java[$m] = $null -ne (Find-Java $m) } catch {} }
    $short = @('Missing', 'Missing')
    for ($i = 0; $i -lt 2; $i++) { try { $short[$i] = [string](Get-ShortcutState $i) } catch {} }
    $script:SetCache = @{ Java = $java; Short = $short; At = $SetClock.Elapsed.TotalSeconds }
}
function Get-SettingsCache {
    if ($null -eq $SetCache -or ($SetClock.Elapsed.TotalSeconds - $SetCache.At) -ge 2) { Update-SettingsCache }
    $SetCache
}
function Reset-SettingsCache { $script:SetCache = $null }

function Open-Settings {
    $script:SetSel = 0; $script:SetNote = $null
    $script:Screen = 'settings'
    Reset-SettingsCache
    Reset-Frame
}

function OnOff([bool]$on) {
    if ($on) { return $c.green + '● ' + (L 'açık') + $R }
    $c.dim + '○ ' + (L 'kapalı') + $R
}

# Kısayol satırının değeri: 0 Masaüstü, 1 Başlat menüsü (durum Get-ShortcutState ile, önbellekten)
function ShortcutValue([int]$i) {
    $st = (Get-SettingsCache).Short[$i]
    if ($st -eq 'Ours') { return OnOff $true }
    if ($st -eq 'OtherLive') { return $c.yellow + '● ' + (L "başka bir SyHost'u açıyor") + $R }
    OnOff $false
}

function SettingValue([string]$key) {
    switch -CaseSensitive ($key) {
        'dil' { $name = $Languages[$LangCode]; if ($null -eq $name) { $name = $LangCode }; return $c.text + $name + $R }
        'klasor' { return $c.text + $Cfg.sunucuKokKlasoru + $R }
        'masaustu' { return ShortcutValue 0 }
        'baslat' { return ShortcutValue 1 }
        'yazi' { return $c.text + $(if ($Cfg.yaziTipiBoyutu) { $Cfg.yaziTipiBoyutu } else { 16 }) + $R + $c.dark + '   ‹ ›' + $R }
        'arkadas' {
            if (PlayitOn) { return $c.green + (L '● açık (playit)') + $R + '  ' + $Bo + $c.cyan + $Cfg.arkadasAdresi + $R }
            if ($HasFriendAddr) { return $c.yellow + (L '● bağlanıyor') + $R + '  ' + $Bo + $c.cyan + $Cfg.arkadasAdresi + $R }
            return $c.dim + (L 'kurulu değil') + $R
        }
        'java' {
            $java = (Get-SettingsCache).Java
            $parts = foreach ($m in 25, 21, 17, 8) { if ($java[$m]) { $c.text + $m + ' ' + $c.green + '✓' + $R } else { $c.dark + $m + ' —' + $R } }
            return $parts -join '   '
        }
        'oyuncu' { return $c.text + $MaxPlayers + $R + $c.dark + '   ‹ ›' + $R }
        'yedek' { return $c.text + $(if ([double]$Cfg.otomatikYedekSaat -le 0) { L 'kapalı' } else { L '{0} saatte bir' $Cfg.otomatikYedekSaat }) + $R + $c.dark + '   ‹ ›' + $R }
        'sakla' { return $c.text + $Cfg.saklanacakYedek + $R + $c.dark + '   ‹ ›' + $R }
        'cokme' { return OnOff ([bool]$Cfg.cokerseYenidenBaslat) }
        'ac' { return $c.dim + $AppRoot + $R }
    }
    ''
}

function Render-Settings([int]$W, [int]$H) {
    $rows = New-Object System.Collections.Generic.List[string]
    $rows.Add('')
    $rows.Add('  ' + $Bo + $c.brass + (L 'AYARLAR') + $R + '   ' + (VersionLine))
    $group = $null
    for ($i = 0; $i -lt $SettingRows.Count; $i++) {
        $s = $SettingRows[$i]
        if ($s.Group -cne $group) { $group = $s.Group; $rows.Add(''); $rows.Add((Rule (L $group) $W)) }
        $sel = $i -eq $SetSel
        $label = if ($s.Key -ceq 'kaldir') { $(if ($sel) { $Bo + $c.red } else { $c.red }) + (L $s.Label) } else { $(if ($sel) { $Bo + $c.text } else { $c.soft }) + (L $s.Label) }
        $line = '  ' + $(if ($sel) { $c.brass + $Bo + '❯' } else { ' ' }) + $R + ' ' + (PadV $label 30) + '  ' + (SettingValue $s.Key)
        $rows.Add($(if ($sel) { SelLine $line $W } else { $line }))
    }
    $rows.Add('')
    $cur = $SettingRows[$SetSel]
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in (WordWrap (L $cur.Help) ([Math]::Min($W, 90) - 6))) { $lines.Add($c.soft + $l + $R) }
    if ($null -ne $SetNote) { foreach ($l in (WordWrap $SetNote ([Math]::Min($W, 90) - 6))) { $lines.Add($SetNoteCol + $l + $R) } }
    foreach ($l in (Card (Up (L $cur.Label)) $lines ([Math]::Min($W, 90)))) { $rows.Add(' ' + $l) }

    while ($rows.Count -lt $H - 2) { $rows.Add('') }
    Update-Sky $W $H 0.07 1 $false 0.75
    for ($r1 = 0; $r1 -lt $rows.Count; $r1++) { if ($rows[$r1] -eq '') { $rows[$r1] = Sky-Seg $r1 0 $W } }
    $rows.Add($c.dark + ('─' * $W) + $R)
    $rows.Add(' ' + (Key '↑↓' (L 'seç')) + (Key 'Enter' (L 'değiştir')) + (Key '← →' (L 'ayarla')) + (Key 'Esc' (L 'geri')))
    , $rows
}

function Handle-SettingsKey([ConsoleKeyInfo]$k, [bool]$ctrl) {
    $n = $SettingRows.Count
    $key = $SettingRows[$SetSel].Key
    switch ($k.Key) {
        'UpArrow' { $script:SetSel = ($SetSel + $n - 1) % $n; $script:SetNote = $null; return }
        'DownArrow' { $script:SetSel = ($SetSel + 1) % $n; $script:SetNote = $null; return }
        'Escape' { $script:Screen = 'home'; Reset-Frame; return }
        'F9' { $script:Screen = 'home'; Reset-Frame; return }
        # Değişiklikten sonra önbellek tazelenir (ilk açılış adımından ya da kaldır ekranından dönünce de)
        'LeftArrow' { $null = SettingAdjust $key (-1); Reset-SettingsCache; return }
        'RightArrow' { $null = SettingAdjust $key 1; Reset-SettingsCache; return }
        'Enter' { $null = SettingEnter $key; Reset-SettingsCache; return }
    }
}

function SettingAdjust([string]$key, [int]$d) {
    switch -CaseSensitive ($key) {
        'dil' {
            $codes = @($Languages.Keys)
            $i = [Array]::IndexOf($codes, $LangCode)
            $n = $codes.Count
            Set-Language $codes[(($i + $d) % $n + $n) % $n]
            return
        }
        'yazi' {
            $Cfg.yaziTipiBoyutu = [Math]::Max(10, [Math]::Min(36, $(if ($Cfg.yaziTipiBoyutu) { [int]$Cfg.yaziTipiBoyutu } else { 16 }) + $d))
            $null = Save-Config
            [void][SyHost.Native]::SetFont('Cascadia Mono', [int16]$Cfg.yaziTipiBoyutu)
            Reset-Frame
            return
        }
        'oyuncu' { $script:MaxPlayers = [Math]::Max(1, [Math]::Min(200, [int]$MaxPlayers + $d)); $Cfg.maksOyuncu = $MaxPlayers; $null = Save-Config; return }
        'yedek' { $Cfg.otomatikYedekSaat = [Math]::Max(0, [Math]::Min(24, [int][Math]::Round([double]$Cfg.otomatikYedekSaat) + $d)); $null = Save-Config; return }
        'sakla' { $Cfg.saklanacakYedek = [Math]::Max(1, [Math]::Min(100, [int]$Cfg.saklanacakYedek + $d)); $null = Save-Config; return }
        'cokme' { $Cfg.cokerseYenidenBaslat = -not [bool]$Cfg.cokerseYenidenBaslat; $null = Save-Config; return }
        'masaustu' { SettingEnter $key; return }
        'baslat' { SettingEnter $key; return }
    }
}

function SettingEnter([string]$key) {
    $script:SetNote = $null
    switch -CaseSensitive ($key) {
        'dil' { SettingAdjust 'dil' 1; return }
        'klasor' {
            # test modunda pencere açılmaz; pencere açılamazsa seçilmemiş sayılır (C# Native.PickFolder gibi)
            $picked = if ($TestFrame) { $null } else { try { Pick-Folder (L 'Yeni sunucuların kurulacağı klasörü seç') $(if ([IO.Directory]::Exists([string]$Cfg.sunucuKokKlasoru)) { $Cfg.sunucuKokKlasoru } else { $AppRoot }) } catch { $null } }
            Reset-Frame
            if ([string]::IsNullOrEmpty($picked)) { return }
            $oneDrive = $false; try { $oneDrive = [bool](Test-InOneDrive $picked) } catch {}
            if ($oneDrive) { $script:SetNote = L 'Bu klasör OneDrive ile eşitleniyor. Sunucu dosyaları büyük ve sürekli değişir; OneDrive dışında bir yer önerilir.'; $script:SetNoteCol = $c.yellow }
            $Cfg.sunucuKokKlasoru = [string]$picked; $null = Save-Config
            return
        }
        'masaustu' { Switch-SettingShortcut $key; return }
        'baslat' { Switch-SettingShortcut $key; return }
        'arkadas' { $null = Start-FirstRun 'arkadas'; Reset-Frame; return }
        'java' {
            if ($null -ne (Find-Java 21)) { $script:SetNote = L 'Java 21 hazır'; $script:SetNoteCol = $c.green; return }
            $null = Start-FirstRun 'java'; Reset-Frame; return
        }
        'yazi' { SettingAdjust $key 1; return }
        'oyuncu' { SettingAdjust $key 1; return }
        'yedek' { SettingAdjust $key 1; return }
        'sakla' { SettingAdjust $key 1; return }
        'cokme' { SettingAdjust $key 1; return }
        'ac' { if (-not $TestFrame) { try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $AppRoot + '"') } catch {} }; return }
        'kaldir' { $null = Start-Uninstall; return }
    }
}

# Masaüstü ya da Başlat menüsü kısayolunu aç/kapat. Durum diskten okunur (önbellekten ya da test değerinden değil, C# gibi).
function Switch-SettingShortcut([string]$key) {
    $locs = @(Get-ShortcutLocations)
    $desk = $false; $start = $false
    try { $desk = (Get-LinkState $locs[0] $ExePath) -eq 'Ours' } catch {}
    try { $start = (Get-LinkState $locs[1] $ExePath) -eq 'Ours' } catch {}
    if ($key -ceq 'masaustu') { $desk = -not $desk } else { $start = -not $start }
    $null = Apply-Shortcuts $desk $start
}

# Dili hemen değiştir (yeniden başlatmadan): metinler, klasör adları ve kısayol açıklamaları
function Set-Language([string]$code) {
    $script:LangCode = $code; $Cfg.dil = $code; $null = Save-Config
    $null = Init-Tables
    # test modunda gerçek klasörlere dokunulmaz
    if (-not $TestFrame) { try { $null = Start-FolderLook $AppRoot $code @(foreach ($sv in $Servers) { [string]$sv.klasor }) } catch {} }
    $desc = L 'SyHost - modlu Minecraft sunucu merkezi'
    if (ShortcutsWritable) { foreach ($lnk in @(Get-ShortcutLocations)) { try { if ((Get-LinkState $lnk $ExePath) -eq 'Ours') { $null = Write-Shortcut $lnk $ExePath $desc } } catch {} } }
    Update-TrayLanguage
    Reset-SettingsCache
    Reset-Frame
}

# Tepsi menüsünün yazıları: C# sürümü menüyü her açılışta seçili dille kurar. Terminal sürümünde menü bir kez
# kurulur; tepsi çevirisi (Installer bölümü, SyHost.Core.cs Tray) yeniden yazdıran bir çağrı sunuyorsa onu kullan.
function Update-TrayLanguage {
    if ($TestFrame) { return }
    foreach ($fn in 'Update-TrayLabels', 'Update-TrayMenu', 'Set-TrayLabels') {
        if (Get-Command $fn -CommandType Function -ErrorAction SilentlyContinue) { try { $null = & $fn } catch {}; return }
    }
}
