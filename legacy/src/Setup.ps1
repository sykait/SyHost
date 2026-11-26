# =====================================================================
#  SyHost Setup - one-time preparation
#  Installs the font, Java, (optionally) the playit.gg connection and shortcuts.
#  Author: sykait
# =====================================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$SrcDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppRoot = Split-Path -Parent $SrcDir
$Data    = Join-Path $env:LOCALAPPDATA 'SyHost'
New-Item -ItemType Directory -Force $Data | Out-Null
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = 'SyHost Setup'

# Files downloaded as a GitHub zip are blocked by Windows; unblock them
Get-ChildItem $AppRoot -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

$E = [char]27
$Red = "$E[38;2;239;55;66m"; $White = "$E[38;2;240;240;240m"; $Gray = "$E[38;2;140;140;146m"; $Green = "$E[38;2;120;220;140m"; $Yel = "$E[38;2;255;170;120m"; $Rs = "$E[0m"; $Bd = "$E[1m"

# ---------- Texts: key = @(English, Türkçe, 日本語) ----------
$KT = @{
    tagline   = @('Setup · modded Minecraft server hub · sykait', 'Kurulum · modlu Minecraft sunucu merkezi · sykait', 'セットアップ · MOD入り Minecraft サーバーハブ · sykait')
    intro     = @('This window will get everything ready in a few minutes.', 'Bu pencere birkaç dakika içinde her şeyi hazırlayacak.', 'このウィンドウが数分ですべてを準備します。')
    yesno     = @('(Y/N)', '(E/H)', '(Y/N)')
    s1        = @('Checking your system', 'Sistem kontrol ediliyor', 'システムを確認しています')
    needWin   = @('SyHost needs Windows 10 or 11.', 'SyHost Windows 10 veya 11 ister.', 'SyHost には Windows 10 または 11 が必要です。')
    noWinget  = @("winget was not found. Install 'App Installer' from the Microsoft Store, then run this setup again.", "winget bulunamadı. Microsoft Store'dan 'Uygulama Yükleyici' (App Installer) kur, sonra bu kurulumu tekrar çalıştır.", 'winget が見つかりません。Microsoft Store から「アプリ インストーラー」を入れて、もう一度実行してください。')
    wingetOk  = @('winget is ready', 'winget hazır', 'winget の準備完了')
    hw        = @('{0} GB RAM, {1} cores', '{0} GB RAM, {1} çekirdek', 'RAM {0} GB、{1} コア')
    lowRam    = @('At least 8 GB of RAM is recommended for modded servers.', 'Modlu sunucular için en az 8 GB RAM önerilir.', 'MOD入りサーバーには 8 GB 以上の RAM をおすすめします。')
    s2        = @('Checking Java 21', 'Java 21 kontrol ediliyor', 'Java 21 を確認しています')
    javaHave  = @('Java 21 is already installed', 'Java 21 zaten kurulu', 'Java 21 はインストール済みです')
    javaDl    = @('Downloading Java 21 (if Windows asks, click Yes)...', 'Java 21 indiriliyor (Windows izin isterse Evet de)...', 'Java 21 をダウンロード中（Windows に確認されたら「はい」）...')
    javaOk    = @('Java 21 installed', 'Java 21 kuruldu', 'Java 21 をインストールしました')
    javaFail  = @('Could not install Java 21. No worries, SyHost will try again when installing a server.', 'Java 21 kurulamadı. Merak etme, SyHost sunucu kurarken tekrar deneyecek.', 'Java 21 をインストールできませんでした。サーバーのインストール時に SyHost が再試行します。')
    javaOld   = @('Older packs (needing Java 8/17) get their Java installed by SyHost when needed.', 'Eski sürüm paketler (Java 8/17 isteyen) gerekirse SyHost onları kendisi kurar.', '古いパック（Java 8/17 が必要）は必要に応じて SyHost が自動でインストールします。')
    s3        = @('Connection for your friends (playit.gg)', 'Arkadaşların için bağlantı (playit.gg)', '友達用の接続 (playit.gg)')
    cgnat1    = @('On most home connections (CGNAT) your friends cannot connect to you directly.', 'Çoğu ev internetinde (CGNAT) arkadaşların doğrudan bağlanamaz.', '多くの家庭用回線（CGNAT）では、友達が直接接続できません。')
    cgnat2    = @('playit.gg fixes this for free and gives you a fixed address (e.g. some-name.joinmc.link).', 'playit.gg bunu bedava çözer ve sana sabit bir adres verir (ör. bir-sey.joinmc.link).', 'playit.gg が無料で解決し、固定アドレス（例: some-name.joinmc.link）をくれます。')
    cgnat3    = @('SyHost only runs playit while SyHost itself is open, never at Windows startup.', 'SyHost playit''i sadece kendisi açıkken çalıştırır, bilgisayarın açılışında başlamaz.', 'SyHost は自身が開いている間だけ playit を動かします。Windows 起動時には動きません。')
    askPlayit = @('Should your friends be able to join over the internet?', 'Arkadaşların internetten bağlanabilsin mi?', '友達がインターネット経由で参加できるようにしますか？')
    playitDl  = @('Downloading playit (if Windows asks, click Yes)...', 'playit indiriliyor (Windows izin isterse Evet de)...', 'playit をダウンロード中（Windows に確認されたら「はい」）...')
    playitOk  = @('playit installed', 'playit kuruldu', 'playit をインストールしました')
    playitBad = @('Could not install playit, skipping this step.', 'playit kurulamadı, bu adım atlanıyor.', 'playit をインストールできなかったため、この手順をスキップします。')
    s4        = @('Settings that need administrator permission', 'Yönetici izni gereken ayarlar', '管理者権限が必要な設定')
    uac       = @('A Windows permission prompt will appear once, click Yes:', 'Bir kere Windows izin penceresi çıkacak, Evet de:', 'Windows の確認画面が一度表示されます。「はい」を選んでください:')
    uacFont   = @(' - Cascadia Mono font (so the animations look right)', ' - Cascadia Mono yazı tipi (animasyonların düzgün görünmesi için)', ' - Cascadia Mono フォント（アニメーションを正しく表示するため）')
    uacPlayit = @(' - stop playit from starting with Windows', ' - playit''in bilgisayar açılınca kendiliğinden başlamaması', ' - Windows 起動時に playit が自動で起動しないようにする')
    fontOk    = @('Font installed', 'Yazı tipi kuruldu', 'フォントをインストールしました')
    fontBad   = @('Could not install the font (SyHost still works, some symbols may look different).', 'Yazı tipi kurulamadı (SyHost yine çalışır, bazı semboller farklı görünebilir).', 'フォントをインストールできませんでした（SyHost は動作しますが、一部の記号の見た目が変わる場合があります）。')
    playitSet = @('playit set to run only while SyHost is open', 'playit sadece SyHost açıkken çalışacak şekilde ayarlandı', 'playit は SyHost が開いている間だけ動くように設定しました')
    noUac     = @('Permission was not given. Font and playit settings were skipped (you can run setup again).', 'İzin verilmedi. Yazı tipi ve playit ayarı atlandı (kurulumu tekrar çalıştırabilirsin).', '許可されなかったため、フォントと playit の設定をスキップしました（もう一度実行できます）。')
    noNeed    = @('Not needed, everything is already in place', 'Gerek yok, her şey zaten hazır', '必要ありません。すべて準備済みです')
    keepAcc   = @('playit already looks connected. Keep using the same account?', 'playit zaten bağlı görünüyor. Aynı hesapla devam edilsin mi?', 'playit はすでに接続済みのようです。同じアカウントを使いますか？')
    linkTitle = @('Linking your playit account', 'playit hesabına bağlanma', 'playit アカウントとの連携')
    link1     = @('1. playit.gg will open in your browser in a moment.', '1. Birazdan tarayıcıda playit.gg açılacak.', '1. まもなくブラウザで playit.gg が開きます。')
    link2     = @("2. If you don't have an account, create one for free (Create Account); otherwise log in.", '2. Hesabın yoksa bedava oluştur (Create Account), varsa giriş yap.', '2. アカウントがなければ無料で作成（Create Account）、あればログイン。')
    link3     = @('3. Approve this computer on the page that opens (Continue / Add Agent).', '3. Çıkan sayfada bu bilgisayarı onayla (Continue / Add Agent).', '3. 表示されたページでこのPCを承認（Continue / Add Agent）。')
    ready     = @('Press Enter when ready', 'Hazırsan Enter', '準備ができたら Enter')
    waiting   = @('Waiting for you to approve it in the browser (up to 10 minutes)...', 'Tarayıcıda onaylamanı bekliyorum (en fazla 10 dakika)...', 'ブラウザでの承認を待っています（最大10分）...')
    linked    = @('Connected to your playit account', 'playit hesabına bağlandı', 'playit アカウントに接続しました')
    linkFail  = @('The playit link was not completed. You can run setup again to retry.', 'playit bağlantısı tamamlanmadı. Kurulumu tekrar çalıştırıp deneyebilirsin.', 'playit との連携が完了しませんでした。もう一度セットアップを実行してください。')
    linkErr   = @('playit link error: {0}', 'playit bağlantısında hata: {0}', 'playit 連携エラー: {0}')
    accOk     = @('playit account linked', 'playit hesabı bağlı', 'playit アカウント連携済み')
    addrTitle = @('The address your friends will use', 'Arkadaşlarının bağlanacağı adres', '友達が使うアドレス')
    addr1     = @('1. The playit.gg tunnels page will open in a moment.', '1. Birazdan playit.gg tünel sayfası açılacak.', '1. まもなく playit.gg のトンネルページが開きます。')
    addr2     = @('2. "Add Tunnel" > "Minecraft Java" > Continue > region "Automatic (Free)" > Create Tunnel.', '2. "Add Tunnel" > "Minecraft Java" seç > Continue > bölge "Automatic (Free)" > Create Tunnel.', '2. 「Add Tunnel」>「Minecraft Java」> Continue > リージョン「Automatic (Free)」> Create Tunnel。')
    addr3     = @('3. If you use the voice chat mod, also create a "MC: Simple Voice Chat" tunnel.', '3. Sesli sohbet modu kullanıyorsan bir tane de "MC: Simple Voice Chat" tüneli oluştur.', '3. ボイスチャット MOD を使う場合は「MC: Simple Voice Chat」トンネルも作成。')
    addr4     = @('4. Paste the tunnel addresses below (right-click = paste).', '4. Tünellerin adreslerini aşağıya yapıştır (sağ tık = yapıştır).', '4. 下にトンネルのアドレスを貼り付けてください（右クリック = 貼り付け）。')
    mcAddr    = @('Minecraft address', 'Minecraft adresi', 'Minecraft アドレス')
    mcEx      = @('(e.g. some-name.joinmc.link or xxx.tun.ply.gg)', '(ör. bir-sey.joinmc.link veya xxx.tun.ply.gg)', '（例: some-name.joinmc.link または xxx.tun.ply.gg）')
    voAddr    = @('Voice chat address', 'Sesli sohbet adresi', 'ボイスチャット アドレス')
    voEx      = @('(leave empty and press Enter if none)', '(yoksa boş bırakıp Enter)', '（なければ空のまま Enter）')
    voBad     = @('Could not understand the voice chat address, left it empty.', 'Sesli sohbet adresi anlaşılamadı, boş bırakıldı.', 'ボイスチャットのアドレスを認識できなかったため、空にしました。')
    addrSaved = @('Friend address saved: {0}', 'Arkadaş adresi kaydedildi: {0}', '友達用アドレスを保存しました: {0}')
    skipped   = @('Skipped. The server can be joined from this PC and your home network. You can run setup again later.', 'Atlandı. Sunucuya bu bilgisayardan ve aynı evdeki ağdan girilebilir. İstersen kurulumu sonra tekrar çalıştırabilirsin.', 'スキップしました。このPCと同じ家のネットワークからは参加できます。後でもう一度実行できます。')
    s5        = @('Creating shortcuts', 'Kısayollar oluşturuluyor', 'ショートカットを作成しています')
    shortOk   = @('"SyHost" was added to your Desktop and Start menu', 'Masaüstüne ve Başlat menüsüne "SyHost" eklendi', 'デスクトップとスタートメニューに「SyHost」を追加しました')
    done      = @('Setup complete!', 'Kurulum tamam!', 'セットアップ完了！')
    howTo     = @('To add a server: open SyHost > "Add a new server" > pick a Modrinth pack (.mrpack).', 'Sunucu eklemek için: SyHost''u aç > "Yeni sunucu ekle" > Modrinth paketini (.mrpack) seç.', 'サーバーの追加: SyHost を開く >「新しいサーバーを追加」> Modrinth パック (.mrpack) を選択。')
    openNow   = @('Open SyHost now?', 'SyHost şimdi açılsın mı?', '今すぐ SyHost を開きますか？')
    pressEnd  = @('Press Enter to close', 'Kapatmak için Enter', 'Enter で閉じる')
    desc      = @('SyHost - modded Minecraft server hub', 'SyHost - modlu Minecraft sunucu merkezi', 'SyHost - MOD入り Minecraft サーバーハブ')
}
$LangIdx = 0
function K([string]$key) { $v = $KT[$key][$LangIdx]; if ($args.Count) { return ($v -f $args) }; $v }

function Say([string]$t, [string]$col = $White) { Write-Host ($col + $t + $Rs) }
function Step([int]$n, [int]$of, [string]$t) { Write-Host ''; Write-Host ("$Red$Bd[$n/$of]$Rs $Bd$t$Rs") }
function Ok([string]$t) { Write-Host ("   $Green✓$Rs $t") }
function Info([string]$t) { Write-Host ("   $Gray$t$Rs") }
function Warn([string]$t) { Write-Host ("   $Yel!$Rs $t") }
function Ask([string]$q) {
    while ($true) {
        Write-Host ("   $Bd$q$Rs $Gray$(K yesno)$Rs ") -NoNewline
        $a = (Read-Host).Trim().ToLower()
        if ($a -in 'y', 'yes', 'e', 'evet', 'はい', '') { return $true }
        if ($a -in 'n', 'no', 'h', 'hayir', 'hayır', 'いいえ') { return $false }
    }
}
function Pause-Exit([int]$code) { Write-Host ''; Read-Host ('   ' + (K pressEnd)) | Out-Null; exit $code }

Clear-Host
Write-Host ''
Write-Host "$Red$Bd   ███████╗██╗   ██╗██╗  ██╗ ██████╗ ███████╗████████╗$Rs"
Write-Host "$Red$Bd   ██╔════╝╚██╗ ██╔╝██║  ██║██╔═══██╗██╔════╝╚══██╔══╝$Rs"
Write-Host "$Red$Bd   ███████╗ ╚████╔╝ ███████║██║   ██║███████╗   ██║   $Rs"
Write-Host "$Red$Bd   ╚════██║  ╚██╔╝  ██╔══██║██║   ██║╚════██║   ██║   $Rs"
Write-Host "$Red$Bd   ███████║   ██║   ██║  ██║╚██████╔╝███████║   ██║   $Rs"
Write-Host "$Red$Bd   ╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   $Rs"
Write-Host ''

# ---------- Language / Dil / 言語 ----------
Write-Host "   $Bd Language / Dil / 言語$Rs"
Write-Host "   $Red 1$Rs English   $Red 2$Rs Türkçe   $Red 3$Rs 日本語"
Write-Host "   $Gray(Enter = English)$Rs " -NoNewline
$pick = (Read-Host).Trim()
$LangIdx = switch ($pick) { '2' { 1 } '3' { 2 } default { 0 } }
$LangCode = @('en', 'tr', 'ja')[$LangIdx]
Write-Host ''
Say ('   ' + (K tagline)) $Gray
Say ('   ' + (K intro)) $Gray

$Total = 5

# ---------------------------------------------------------------------
Step 1 $Total (K s1)
$os = [Environment]::OSVersion.Version
if ($os.Major -lt 10) { Warn (K needWin); Pause-Exit 1 }
Ok "Windows $(if ($os.Build -ge 22000) { '11' } else { '10' }) ($($os.Build))"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Warn (K noWinget)
    Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1'
    Pause-Exit 1
}
Ok (K wingetOk)
$ramGb = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
Ok (K hw $ramGb ([Environment]::ProcessorCount))
if ($ramGb -lt 8) { Warn (K lowRam) }

# ---------------------------------------------------------------------
Step 2 $Total (K s2)
$java = Get-ChildItem 'C:\Program Files\Microsoft\jdk-21*\bin\java.exe', 'C:\Program Files\Eclipse Adoptium\jdk-21*\bin\java.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($java) { Ok (K javaHave) }
else {
    Info (K javaDl)
    & winget install --id Microsoft.OpenJDK.21 -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
    $java = Get-ChildItem 'C:\Program Files\Microsoft\jdk-21*\bin\java.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($java) { Ok (K javaOk) } else { Warn (K javaFail) }
}
Info (K javaOld)

# ---------------------------------------------------------------------
Step 3 $Total (K s3)
Info (K cgnat1); Info (K cgnat2); Info (K cgnat3)
$usePlayit = Ask (K askPlayit)
$playitBin = 'C:\Program Files\playit_gg\bin'
if ($usePlayit -and -not (Test-Path "$playitBin\playitd.exe")) {
    Info (K playitDl)
    & winget install --id DevelopedMethods.playit -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
    if (Test-Path "$playitBin\playitd.exe") { Ok (K playitOk) } else { Warn (K playitBad); $usePlayit = $false }
}

# ---------------------------------------------------------------------
Step 4 $Total (K s4)
$fontOk = Test-Path 'C:\Windows\Fonts\CascadiaMono-Regular.ttf'
if ((-not $fontOk) -or $usePlayit) {
    Info (K uac)
    if (-not $fontOk) { Info (K uacFont) }
    if ($usePlayit) { Info (K uacPlayit) }
    $adminScript = Join-Path $env:TEMP ('syhost-admin-' + [guid]::NewGuid().ToString('N') + '.ps1')
    @"
`$ErrorActionPreference = 'Continue'
if ('$(-not $fontOk)' -eq 'True') {
    Copy-Item '$AppRoot\fonts\CascadiaMono-Regular.ttf' 'C:\Windows\Fonts\CascadiaMono-Regular.ttf' -Force
    Copy-Item '$AppRoot\fonts\CascadiaMono-Bold.ttf' 'C:\Windows\Fonts\CascadiaMono-Bold.ttf' -Force
    `$k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    Set-ItemProperty `$k 'Cascadia Mono Regular (TrueType)' 'CascadiaMono-Regular.ttf'
    Set-ItemProperty `$k 'Cascadia Mono Bold (TrueType)' 'CascadiaMono-Bold.ttf'
}
`$c = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Console\TrueTypeFont'
`$vals = (Get-ItemProperty `$c).PSObject.Properties | Where-Object { `$_.Name -match '^0+$' }
if (-not (`$vals | Where-Object { `$_.Value -eq 'Cascadia Mono' })) {
    `$name = '0'; while (`$vals | Where-Object { `$_.Name -eq `$name }) { `$name += '0' }
    Set-ItemProperty `$c `$name 'Cascadia Mono'
}
if ('$usePlayit' -eq 'True') {
    Stop-Service playitd -Force -ErrorAction SilentlyContinue
    Set-Service playitd -StartupType Disabled -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name playit -ErrorAction SilentlyContinue
    Get-Process playitd-tray, playit-gui -ErrorAction SilentlyContinue | Stop-Process -Force
}
"@ | Set-Content $adminScript -Encoding UTF8
    try {
        Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$adminScript`""
        if (-not $fontOk) { if (Test-Path 'C:\Windows\Fonts\CascadiaMono-Regular.ttf') { Ok (K fontOk) } else { Warn (K fontBad) } }
        if ($usePlayit) { Ok (K playitSet) }
    } catch { Warn (K noUac) }
    Remove-Item $adminScript -ErrorAction SilentlyContinue
} else { Ok (K noNeed) }

# ---------- Settings file ----------
$cfgFile = Join-Path $Data 'ayarlar.json'
if (-not (Test-Path $cfgFile)) { Copy-Item (Join-Path $AppRoot 'config\default-settings.json') $cfgFile }
$cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
function Set-Cfg([string]$name, $value) { if ($null -eq $cfg.PSObject.Properties[$name]) { $cfg | Add-Member -NotePropertyName $name -NotePropertyValue $value } else { $cfg.$name = $value } }
Set-Cfg 'dil' $LangCode

if ($usePlayit) {
    $secretFile = Join-Path $Data 'playit.toml'
    $haveSecret = (Test-Path $secretFile) -and ((Get-Content $secretFile -Raw) -match '[0-9a-f]{64}')
    if ($haveSecret -and -not (Ask (K keepAcc))) { $haveSecret = $false }
    if (-not $haveSecret) {
        Write-Host ''
        Say ('   ' + (K linkTitle)) $White
        Info (K link1); Info (K link2); Info (K link3)
        Read-Host ('   ' + (K ready)) | Out-Null
        try {
            $code = (& "$playitBin\playit.exe" claim generate 2>$null | Select-Object -Last 1).Trim()
            $url = (& "$playitBin\playit.exe" claim url $code --name "SyHost" 2>$null | Select-Object -Last 1).Trim()
            Start-Process $url
            Info (K waiting)
            $out = (& "$playitBin\playit.exe" claim exchange $code --wait 600 2>&1 | Out-String)
            if ($out -match '([0-9a-f]{64})') {
                [IO.File]::WriteAllText($secretFile, "secret_key = `"$($Matches[1])`"`n", (New-Object Text.UTF8Encoding $false))
                Ok (K linked)
                $haveSecret = $true
            } else { Warn (K linkFail) }
        } catch { Warn (K linkErr $_.Exception.Message) }
    } else { Ok (K accOk) }

    if ($haveSecret) {
        Write-Host ''
        Say ('   ' + (K addrTitle)) $White
        Info (K addr1); Info (K addr2); Info (K addr3); Info (K addr4)
        Start-Process 'https://playit.gg/account/tunnels'
        do { Write-Host "   $Bd$(K mcAddr)$Rs $Gray$(K mcEx)$Rs`: " -NoNewline; $mcAddr = (Read-Host).Trim() } while ($mcAddr -notmatch '^[\w\.-]+\.\w+(:\d+)?$')
        Write-Host "   $Bd$(K voAddr)$Rs $Gray$(K voEx)$Rs`: " -NoNewline; $voAddr = (Read-Host).Trim()
        if ($voAddr -and $voAddr -notmatch '^[\w\.-]+\.\w+(:\d+)?$') { Warn (K voBad); $voAddr = '' }
        Set-Cfg 'arkadasAdresi' $mcAddr
        Set-Cfg 'sesAdresi' $voAddr
        Set-Cfg 'playitKullan' $true
        Ok (K addrSaved $mcAddr)
    }
} else {
    Info (K skipped)
}
[IO.File]::WriteAllText($cfgFile, ($cfg | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))

# ---------------------------------------------------------------------
Step 5 $Total (K s5)
$target = "$env:SystemRoot\System32\conhost.exe"
$argsLine = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$AppRoot\src\SyHost.ps1`""
$shell = New-Object -ComObject WScript.Shell
foreach ($lp in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'SyHost.lnk'), (Join-Path ([Environment]::GetFolderPath('Programs')) 'SyHost.lnk'))) {
    $l = $shell.CreateShortcut($lp); $l.TargetPath = $target; $l.Arguments = $argsLine; $l.WorkingDirectory = $AppRoot
    $l.IconLocation = "$env:SystemRoot\System32\imageres.dll,145"; $l.Description = (K desc); $l.Save()
}
Ok (K shortOk)

Write-Host ''
Write-Host "$Green$Bd   $(K done)$Rs"
Info (K howTo)
Write-Host ''
if (Ask (K openNow)) { Start-Process $target -ArgumentList $argsLine }
