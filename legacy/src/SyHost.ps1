# =====================================================================
#  SyHost - Modlu Minecraft sunucu merkezi (Terminal sürümü)
#  Modrinth paketlerinden (.mrpack) sunucu kurar, açar ve yönetir.
#
#  Yapımcı : sykait
#  Lisans  : LICENSE.md (kullanırsan kredi vermek zorunlu)
# =====================================================================
#  -Root      SyHost klasörü (Data ve Servers burada). Verilmezse uygulama klasörünün bir üstü.
#  -Exe       SyHost.exe'nin yolu (başlatıcı verir): kurulum, kısayollar ve yeniden açma bunu kullanır
#  -NoSplash  açılış animasyonunu atla (kurulumdan hemen sonra yeniden açılınca)
#  -TestFrame senaryo.json -TestOut kare.txt
#             test modu: senaryodaki durumu kurar, tek bir kareyi dosyaya yazar ve çıkar.
#             C# sürümüyle (SyHost.exe --frame) aynı biçim; tests\parity iki çıktıyı karşılaştırır.
param([string]$Root, [string]$Exe, [switch]$NoSplash, [string]$TestFrame, [string]$TestOut)
$ErrorActionPreference = 'Stop'
$SrcDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
# Uygulama dosyaları (src, config, fonts, icons). Kurulumda SyHost klasöründeki gizli App klasörüdür.
$AppDir  = Split-Path -Parent $SrcDir
if (-not $Root) { $Root = Split-Path -Parent $AppDir }
$AppRoot = [IO.Path]::GetFullPath($Root)
# Testlerde pencere adı (ve tek kopya kilidi) değişebilir: açık olan gerçek SyHost'a dokunulmaz
$Title   = if ($env:SYHOST_TEST_TITLE) { $env:SYHOST_TEST_TITLE } else { 'SyHost' }
$Version = '1.0.0'
$VersionText = $Version
$Edition = 'Terminal'
# SyHost.exe (başlatıcı): kısayollar onu açar, kurulum onu kopyalar
$ExePath = if ($Exe) { [IO.Path]::GetFullPath($Exe) } else { Join-Path $AppRoot 'SyHost.exe' }

# Kullanıcı verileri (ayarlar, sunucu listesi, playit anahtarı) SyHost klasöründeki gizli Data klasöründe durur.
# İki sürüm de aynı düzeni ve aynı dosyaları kullanır; biri bırakıp diğeri devam edebilir.
$Data = Join-Path $AppRoot 'Data'
# Data yoksa SyHost bu klasörde kurulu değil (ör. İndirilenler'den açıldı): ilk açılışın 1. aşaması, diske yazılmaz
$SetupMode = (-not $TestFrame) -and -not (Test-Path -LiteralPath $Data -PathType Container)

# ---------- Tek kopya (test modunda atlanır: açık bir SyHost'a dokunmasın) ----------
# İki sürüm aynı kilidi kullanır: aynı anda yalnızca bir SyHost açık olabilir
$MutexName = 'Local\SyHostSunucuMerkezi' + $(if ($Title -eq 'SyHost') { '' } else { "-$Title" })
if (-not $TestFrame) {
    $created = $false
    $mutex = New-Object System.Threading.Mutex($true, $MutexName, [ref]$created)
    if (-not $created) {
        Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
'@
        $hw = [W.U]::FindWindow('ConsoleWindowClass', $Title)
        if ($hw -ne [IntPtr]::Zero) { [void][W.U]::ShowWindow($hw, 9); [void][W.U]::ShowWindow($hw, 5); [void][W.U]::SetForegroundWindow($hw) }
        exit
    }
}

$Host.UI.RawUI.WindowTitle = $(if ($TestFrame) { "$Title test" } else { $Title })
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Console]::InputEncoding  = New-Object Text.UTF8Encoding $false
[Console]::TreatControlCAsInput = $true
try { (Get-Process -Id $PID).PriorityClass = 'High' } catch {}

# ---------- Yardımcı kod (C#) ----------
# Başlatıcı (SyHost.exe) derlenmiş hâlini App\bin klasörüne koyar. Geliştirirken kaynaktan derlenip
# App\cache klasörüne yazılır (yalnızca kaynak değişince).
$CoreDll = Join-Path $AppDir 'bin\SyHost.Core.dll'
if (-not (Test-Path -LiteralPath $CoreDll)) {
    $CoreSrc = @(Get-ChildItem -LiteralPath $SrcDir -Filter 'SyHost.*.cs' | Sort-Object Name)
    $CoreDll = Join-Path $AppDir 'cache\SyHost.Core.dll'
    $CoreNewest = ($CoreSrc | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    if (-not (Test-Path -LiteralPath $CoreDll) -or $CoreNewest -gt (Get-Item -LiteralPath $CoreDll).LastWriteTimeUtc) {
        New-Item -ItemType Directory -Force (Split-Path $CoreDll) | Out-Null
        Write-Host 'Preparing SyHost...'
        Add-Type -Path @($CoreSrc | ForEach-Object { $_.FullName }) -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.IO.Compression, System.IO.Compression.FileSystem -OutputAssembly $CoreDll -OutputType Library
    }
}
Add-Type -Path $CoreDll
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.IO.Compression.FileSystem
[SyHost.Native]::DpiAware()

# ---------- Dosyalar ----------
$DefaultCfgFile = Join-Path $AppDir 'config\default-settings.json'
$CfgFile      = Join-Path $Data 'ayarlar.json'
$ServersFile  = Join-Path $Data 'sunucular.json'
$WinFile      = Join-Path $Data 'pencere.json'
$ErrorLog     = Join-Path $Data 'hata.log'
$PlayitSecret = Join-Path $Data 'playit.toml'
$Utf8NoBom    = New-Object Text.UTF8Encoding $false

# Dil: en (varsayılan), tr, ja. Lang.Screens.ps1 üretilir (build\Sync-Lang.ps1).
. (Join-Path $SrcDir 'Lang.ps1')
. (Join-Path $SrcDir 'Lang.Screens.ps1')

# Metni dosyaya güvenle yaz: önce geçici dosya, sonra yerine koy (yarım dosya kalmasın). UTF-8, BOM'suz.
function Write-TextFile([string]$path, [string]$text) {
    $tmp = $path + '.tmp'
    [IO.File]::WriteAllText($tmp, $text, $Utf8NoBom)
    if ([IO.File]::Exists($path)) { try { [IO.File]::Replace($tmp, $path, $null); return } catch { [IO.File]::Copy($tmp, $path, $true); [IO.File]::Delete($tmp); return } }
    [IO.File]::Move($tmp, $path)
}

# ---------- Ayarlar ----------
# C# sürümündeki Settings sınıfıyla aynı varsayılanlar (dosyada olmayan alan bu değeri alır)
$CfgDefaults = [ordered]@{ dil = 'en'; sunucuKokKlasoru = 'Servers'; arkadasAdresi = ''; sesAdresi = ''; playitKullan = $false; maksOyuncu = 5; cokerseYenidenBaslat = $true; otomatikYedekSaat = 3; saklanacakYedek = 10; yaziTipiBoyutu = 16 }
$PackKeys = @('dusuk', 'normal', 'yuksek')
function Read-DefaultSettings { Get-Content -LiteralPath $DefaultCfgFile -Raw -Encoding UTF8 | ConvertFrom-Json }

# sunucuKokKlasoru: boşsa SyHost klasöründeki Servers, göreliyse SyHost klasörüne göre
function Resolve-RootDir([string]$v) {
    $v = [Environment]::ExpandEnvironmentVariables([string]$v).Trim()
    if ($v.Length -eq 0) { return [IO.Path]::Combine($AppRoot, 'Servers') }
    if (-not [IO.Path]::IsPathRooted($v)) { return [IO.Path]::GetFullPath([IO.Path]::Combine($AppRoot, $v)) }
    $v
}
# SyHost klasörünün içindeki yol göreli ("Servers\Ad") yazılır, dışındaki mutlak kalır
function ConvertTo-StoredPath([string]$abs) {
    if ([string]::IsNullOrEmpty($abs)) { return $abs }
    try {
        $full = [IO.Path]::GetFullPath($abs).TrimEnd('\')
        $rootT = $AppRoot.TrimEnd('\')
        if ($full.StartsWith($rootT + '\', [StringComparison]::OrdinalIgnoreCase)) { return $full.Substring($rootT.Length + 1) }
        if ([string]::Equals($full, $rootT, [StringComparison]::OrdinalIgnoreCase)) { return '.' }
        return $full
    } catch { return $abs }
}
# Dosyadaki yolu mutlak yola çevir (göreliyse SyHost klasörüne göre)
function ConvertFrom-StoredPath([string]$stored) {
    if ([string]::IsNullOrEmpty($stored)) { return $stored }
    $v = [Environment]::ExpandEnvironmentVariables($stored)
    try { if ([IO.Path]::IsPathRooted($v)) { return $v }; return [IO.Path]::GetFullPath([IO.Path]::Combine($AppRoot, $v)) } catch { return $v }
}

function Load-Config {
    if ($SetupMode) {
        # Henüz kurulmadı: diske hiçbir şey yazma, Windows'un dilini öner
        $cfg = Read-DefaultSettings
        $cfg.dil = Get-UiLanguage
    } else {
        New-Item -ItemType Directory -Force -Path $Data | Out-Null
        if (-not (Test-Path -LiteralPath $CfgFile)) { Write-TextFile $CfgFile ([IO.File]::ReadAllText($DefaultCfgFile, [Text.Encoding]::UTF8)) }
        try {
            $cfg = Get-Content -LiteralPath $CfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg -isnot [System.Management.Automation.PSCustomObject]) { throw 'ayar dosyası bir nesne değil' }
        } catch {
            # Bozuk ayar dosyası: kenara al, varsayılanla devam et (veri kaybolmasın)
            try { Copy-Item -LiteralPath $CfgFile -Destination ($CfgFile + '.bozuk') -Force } catch {}
            $cfg = Read-DefaultSettings
        }
    }
    foreach ($k in $CfgDefaults.Keys) {
        if ($null -eq $cfg.PSObject.Properties[$k]) { $cfg | Add-Member -NotePropertyName $k -NotePropertyValue $CfgDefaults[$k] }
        elseif ($null -eq $cfg.$k -and $k -in 'arkadasAdresi', 'sesAdresi', 'dil', 'sunucuKokKlasoru') { $cfg.$k = $CfgDefaults[$k] }
    }
    $cfg.sunucuKokKlasoru = Resolve-RootDir $cfg.sunucuKokKlasoru
    # Dil: en (varsayılan), tr, ja
    $script:LangCode = if ($Languages.Contains([string]$cfg.dil)) { [string]$cfg.dil } else { 'en' }
    # Eksik paket varsa varsayılandan tamamla
    $def = $null
    if ($null -eq $cfg.PSObject.Properties['paketler'] -or $null -eq $cfg.paketler) { $def = Read-DefaultSettings; $cfg | Add-Member -NotePropertyName paketler -NotePropertyValue $def.paketler -Force }
    foreach ($pk in $PackKeys) {
        if ($null -eq $cfg.paketler.PSObject.Properties[$pk]) { if (-not $def) { $def = Read-DefaultSettings }; $cfg.paketler | Add-Member -NotePropertyName $pk -NotePropertyValue $def.paketler.$pk }
    }
    $script:Cfg = $cfg
    # İlk açılışta paketleri bu bilgisayarın RAM'ine ve çekirdek sayısına göre ayarla
    if ($null -eq $cfg.PSObject.Properties['paketlerAyarlandi'] -or $null -eq $cfg.paketlerAyarlandi) {
        $totGb = [Math]::Floor((New-Object Microsoft.VisualBasic.Devices.ComputerInfo).TotalPhysicalMemory / 1GB)
        $thr = [Environment]::ProcessorCount
        function Clamp([double]$v, [int]$lo, [int]$hi) { [int][Math]::Max($lo, [Math]::Min($hi, [Math]::Round($v))) }
        $plan = @{ dusuk = @((Clamp ($totGb * 0.2) 3 8), 2, [Math]::Max(2, [int]($thr / 4))); normal = @((Clamp ($totGb * 0.33) 4 12), 4, [Math]::Max(2, [int]($thr / 2))); yuksek = @((Clamp ($totGb * 0.5) 5 20), 6, $thr) }
        foreach ($pk in $PackKeys) {
            $mx = $plan[$pk][0]
            $cfg.paketler.$pk.ramMax = $mx
            $cfg.paketler.$pk.ramMin = [Math]::Max(2, $mx - $plan[$pk][1])
            $cfg.paketler.$pk.cekirdek = $plan[$pk][2]
        }
        $cfg | Add-Member -NotePropertyName paketlerAyarlandi -NotePropertyValue $true -Force
        if (-not $SetupMode) { Save-Config }
    }
    $script:Packs = $cfg.paketler
    $script:MaxPlayers = if ($cfg.maksOyuncu) { [int]$cfg.maksOyuncu } else { 5 }
    $script:Threads  = [Environment]::ProcessorCount
    $script:TotalRam = (New-Object Microsoft.VisualBasic.Devices.ComputerInfo).TotalPhysicalMemory
    $script:HasFriendAddr = [bool]$cfg.arkadasAdresi -and [bool]$cfg.playitKullan
}
# Ayarları kaydet. Sunucu kök klasörü SyHost klasörünün içindeyse göreli yazılır.
function Save-Config {
    $abs = $Cfg.sunucuKokKlasoru
    $Cfg.sunucuKokKlasoru = ConvertTo-StoredPath $abs
    try { Write-TextFile $CfgFile ($Cfg | ConvertTo-Json -Depth 6) } finally { $Cfg.sunucuKokKlasoru = $abs }
}

# Taşınabilir klasör: kurulum, eski verinin taşınması, kısayollar, klasör görünümü, yazı tipi (Portable.ps1)
. (Join-Path $SrcDir 'Portable.ps1')

# Kurulu klasöre yazılamıyorsa (ör. Program Files'a taşınmış) sessizce çökme, anlaşılır uyarı göster (C#: Program.cs).
# Diske ilk yazan Load-Config'ten önce; uyarı Windows'un dilinde.
if (-not $SetupMode -and -not $TestFrame -and -not (Test-CanWrite $Data)) {
    $LangCode = Get-UiLanguage
    Show-Alert (L "SyHost bu klasöre yazamıyor:`n{0}`n`nSyHost.exe'yi yazılabilir bir klasöre taşı (ör. {1}) ve oradan aç." $AppRoot (Get-DefaultRoot))
    exit 1
}

Load-Config
[void][SyHost.Native]::SetFont('Cascadia Mono', [int16]$(if ($Cfg.yaziTipiBoyutu) { $Cfg.yaziTipiBoyutu } else { 16 }))
$PackNameKey = @{ dusuk = 'DÜŞÜK'; normal = 'NORMAL'; yuksek = 'YÜKSEK' }
$PackDescKey = @{ dusuk = 'Ağır bir oyun oynarken. Sistemini en az yoran ayar.'; normal = 'Günlük kullanım. 2-5 kişi için en dengeli ayar.'; yuksek = 'Dev fabrikalar ve hızlı keşif için tam güç.' }
function PackName([string]$k) { L $PackNameKey[$k] }
function PackDesc([string]$k) { L $PackDescKey[$k] }
$FriendAddr = if ($HasFriendAddr) { $Cfg.arkadasAdresi } else { (L 'henüz yok') }

# ---------- Sunucu listesi ----------
# Dosyada SyHost klasörünün içindeki sunucular göreli ("Servers\Ad") durur; bellekte hep mutlak yoldur.
$Servers = New-Object System.Collections.Generic.List[object]
function Load-Servers {
    $script:Servers.Clear()
    if (Test-Path -LiteralPath $ServersFile) {
        $data = Get-Content -LiteralPath $ServersFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($sv in $data) {
            if ($null -eq $sv) { continue }
            foreach ($f in 'paket', 'sonAcilis', 'sonBaslatmaSn', 'eklenme') { if ($null -eq $sv.PSObject.Properties[$f]) { $sv | Add-Member -NotePropertyName $f -NotePropertyValue $null -Force } }
            if (-not $sv.paket) { $sv.paket = 'normal' }
            if ($null -ne $sv.PSObject.Properties['klasor']) { $sv.klasor = ConvertFrom-StoredPath ([string]$sv.klasor) }
            $script:Servers.Add($sv)
        }
    }
}
function Save-Servers {
    $arr = @(foreach ($sv in $Servers) { $o = $sv.PSObject.Copy(); if ($null -ne $o.PSObject.Properties['klasor']) { $o.klasor = ConvertTo-StoredPath ([string]$sv.klasor) }; $o })
    $json = if ($arr.Count -eq 0) { '[]' } elseif ($arr.Count -eq 1) { '[' + ($arr[0] | ConvertTo-Json -Depth 5) + ']' } else { $arr | ConvertTo-Json -Depth 5 }
    Write-TextFile $ServersFile $json
}
if (-not $SetupMode) { Load-Servers }

# ---------- Java (kurulumda da kullanılır; C#: Core\Java.cs) ----------
# Java yoksa bilgisayara kurulmaz: Eclipse Temurin JRE, SyHost'un kendi klasörüne (Data\tools\java-N) indirilir;
# yönetici izni istemez, bilgisayarın geri kalanına dokunmaz. Bu blok ana betikte ve arka plan işlerinde
# (runspace) nokta ile yüklenir; yükleyen $DataDir'i ayarlar. Runspace'te L yoktur: Install-Java'ya ilk satırı
# -HeadText ile ver (çevrilmiş metin; içinde {0} varsa Java sürümüyle doldurulur).
#   Get-JavaMajor $mc                      Minecraft sürümüne göre gereken Java (8, 17, 21, 25)
#   Find-Java $major                       java.exe ya da $null
#   Install-Java $major $OnDetail $HeadText  indirir, java.exe'yi döner; olmazsa nedeniyle hata fırlatır.
#                                          $OnDetail önce ilk satırla, sonra "<dosya>  ·  <MB> / <MB> MB" ile çağrılır
$DataDir = $Data
$JavaFuncs = {
    # Baştaki rakamlar: "5-pre1" -> 5, "" -> 0 (sığmayan sayı: en büyük int)
    function Get-JavaLead([string]$s) {
        $m = [regex]::Match($s, '^[0-9]+')
        if (-not $m.Success) { return 0 }
        $v = 0
        if ([int]::TryParse($m.Value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $v }
        [int]::MaxValue
    }
    # Minecraft sürümüne göre gereken Java (8, 17, 21, 25)
    function Get-JavaMajor([string]$mc) {
        $p = $mc.Split('.')
        # Yıl numaralı sürümler (26.1, 26.2 ...) Java 25 ister (Mojang sürüm listesi: javaVersion.majorVersion = 25)
        if ($p[0] -ne '1') { if ((Get-JavaLead $p[0]) -ge 26) { return 25 }; return 21 }
        # Ön sürümlerde ("1.21-rc1", "1.20.5-pre1") baştaki sayı alınır
        $minor = if ($p.Count -gt 1) { Get-JavaLead $p[1] } else { 0 }
        $patch = if ($p.Count -gt 2) { Get-JavaLead $p[2] } else { 0 }
        if ($minor -ge 21) { return 21 }
        if ($minor -eq 20 -and $patch -ge 5) { return 21 }
        if ($minor -ge 17) { return 17 }
        8
    }
    # parent\desen\bin\java.exe: bulunanların en büyüğü (gizli klasörler sayılmaz, büyük-küçük harfe bakılmaz)
    function Get-JavaNewest([string]$parent, [string]$pattern) {
        $hits = New-Object System.Collections.Generic.List[string]
        try {
            if (-not [IO.Directory]::Exists($parent)) { return $null }
            foreach ($d in (New-Object IO.DirectoryInfo $parent).EnumerateDirectories()) {
                if (($d.Attributes -band [IO.FileAttributes]::Hidden) -ne 0 -or $d.Name -notlike $pattern) { continue }
                $j = [IO.Path]::Combine($d.FullName, 'bin', 'java.exe')
                if ([IO.File]::Exists($j)) { $hits.Add($j) }
            }
        } catch {}
        if ($hits.Count -eq 0) { return $null }
        @($hits | Sort-Object)[-1]
    }
    # klasör\bin\java.exe ya da bir alt klasörde (Adoptium zip'i böyle açılır: jdk-21.0.5+11-jre\bin\java.exe)
    function Get-JavaLocate([string]$root) {
        $j = [IO.Path]::Combine($root, 'bin', 'java.exe')
        if ([IO.File]::Exists($j)) { return $j }
        if ([IO.Directory]::Exists($root)) { return (Get-JavaNewest $root '*') }
        $null
    }
    # Önce bilgisayardaki Java (Program Files, eski sürümdeki yerler ve sırayla), yoksa SyHost'un indirdiği (Data\tools\java-N)
    function Find-Java([int]$major) {
        $pats = if ($major -eq 8) { @(@('Eclipse Adoptium', 'jre-8*'), @('Eclipse Adoptium', 'jdk-8*')) }
                else { @(@('Microsoft', "jdk-$major*"), @('Eclipse Adoptium', "jdk-$major*"), @('Eclipse Adoptium', "jre-$major*")) }
        # Eski sürüm "C:\Program Files" yazardı; Windows başka sürücüdeyse oradaki de bakılır
        $pfs = @('C:\Program Files')
        $pf = [Environment]::GetFolderPath('ProgramFiles')
        if (-not [string]::IsNullOrEmpty($pf) -and -not [string]::Equals($pf.TrimEnd('\'), 'C:\Program Files', [StringComparison]::OrdinalIgnoreCase)) { $pfs += $pf }
        foreach ($pt in $pats) { foreach ($root in $pfs) { $j = Get-JavaNewest ([IO.Path]::Combine($root, $pt[0])) $pt[1]; if ($j) { return $j } } }
        if ([string]::IsNullOrEmpty($DataDir)) { return $null }
        try { Get-JavaLocate ([IO.Path]::Combine($DataDir, 'tools', "java-$major")) } catch { $null }
    }

    # PowerShell .NET hatalarını MethodInvocationException içine sarar: asıl hata (C# sürümündeki metin)
    function Get-JavaError($e) {
        while ($e -is [System.Management.Automation.MethodInvocationException] -and $null -ne $e.InnerException) { $e = $e.InnerException }
        $e
    }
    # Sunucu "böyle bir şey yok" dedi (4xx; 408 ve 429 hariç): tekrar denemek boşuna
    function Test-JavaPermanent($e) {
        if ($e -isnot [Net.WebException] -or $e.Status -ne [Net.WebExceptionStatus]::ProtocolError -or $null -eq $e.Response) { return $false }
        $code = [int]$e.Response.StatusCode
        $code -ge 400 -and $code -lt 500 -and $code -ne 408 -and $code -ne 429
    }
    # İstek: SyHost'u tanıtan User-Agent, yönlendirmeler izlenir, sıkıştırma kapalı (karma baytı baytına doğrulansın).
    # Başlıklar 100 sn içinde gelmeli; sonra 60 sn hiç veri gelmezse bağlantı kopmuş sayılır.
    function New-JavaRequest([string]$url) {
        $r = [Net.HttpWebRequest]::Create($url)
        $r.UserAgent = 'SyHost/1.0 (+https://github.com/sykait/SyHost)'
        $r.AllowAutoRedirect = $true; $r.MaximumAutomaticRedirections = 10
        $r.AutomaticDecompression = [Net.DecompressionMethods]::None
        $r.Timeout = 100000; $r.ReadWriteTimeout = 60000
        $r
    }
    function Get-JavaText([string]$url) {
        $resp = (New-JavaRequest $url).GetResponse()
        try { $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8); try { $sr.ReadToEnd() } finally { $sr.Dispose() } }
        finally { $resp.Close() }
    }
    function Get-JavaStr($o, [string]$n) { $p = $o.PSObject.Properties[$n]; if ($null -ne $p -and $p.Value -is [string]) { $p.Value } else { $null } }
    # assets API'sindeki package.checksum (zip'in SHA-256'sı); ulaşılamazsa $null
    function Get-JavaChecksum([int]$major) {
        try {
            $doc = ConvertFrom-Json (Get-JavaText "https://api.adoptium.net/v3/assets/latest/$major/hotspot?architecture=x64&image_type=jre&os=windows&vendor=eclipse")
            if ($doc -isnot [array]) { return $null }
            foreach ($rel in $doc) {
                if ($rel -isnot [System.Management.Automation.PSCustomObject]) { continue }
                $b = $rel.PSObject.Properties['binary']
                if ($null -eq $b -or $b.Value -isnot [System.Management.Automation.PSCustomObject]) { continue }
                $b = $b.Value
                if (-not ((Get-JavaStr $b 'os') -eq 'windows' -and (Get-JavaStr $b 'architecture') -eq 'x64' -and (Get-JavaStr $b 'image_type') -eq 'jre')) { continue }
                $pk = $b.PSObject.Properties['package']
                if ($null -eq $pk -or $pk.Value -isnot [System.Management.Automation.PSCustomObject]) { continue }
                $sum = Get-JavaStr $pk.Value 'checksum'
                if ($null -ne $sum -and $sum -match '^[0-9a-fA-F]{64}$') { return $sum }
            }
        } catch {}
        $null
    }
    # İlerleme satırı (dile bağlı değil): "OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11.zip  ·  23 / 48 MB"
    function Format-JavaProgress([string]$name, [long]$got, [long]$total) {
        $name + '  ·  ' + ($got -shr 20) + $(if ($total -gt 0) { ' / ' + ($total -shr 20) } else { '' }) + ' MB'
    }
    # Adresi dosyaya indirir (en çok 1 GB), inerken SHA-256'sını hesaplar ve döner. İlerleme en çok saniyede 5 kez.
    function Save-JavaFile([string]$url, [string]$path, [scriptblock]$OnDetail) {
        $resp = (New-JavaRequest $url).GetResponse()
        try {
            $length = $resp.ContentLength   # bilinmiyorsa -1
            # Dosya adı: GitHub'ın son adresinde ad yerine bir kimlik durur; asıl ad Content-Disposition'da
            $name = $null
            $cd = $resp.Headers['Content-Disposition']
            if ($cd) {
                $m = [regex]::Match($cd, 'filename\*?\s*=\s*(?:[\w-]+''[\w-]*'')?"?([^";]+)"?', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($m.Success) { $name = [Uri]::UnescapeDataString($m.Groups[1].Value.Trim()) }
            }
            if (-not $name) { $name = [Uri]::UnescapeDataString([IO.Path]::GetFileName($resp.ResponseUri.AbsolutePath)) }
            $tick = [Diagnostics.Stopwatch]::StartNew()
            if ($OnDetail) { $null = & $OnDetail (Format-JavaProgress $name 0 $length) }
            $sha = [Security.Cryptography.SHA256]::Create()
            $body = $resp.GetResponseStream()
            $fs = New-Object IO.FileStream($path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 65536)
            try {
                $buf = New-Object byte[] 65536
                $total = [long]0
                while (($n = $body.Read($buf, 0, $buf.Length)) -gt 0) {
                    $total += $n
                    if ($total -gt 1GB) { throw (New-Object IO.InvalidDataException 'The download is larger than expected.') }
                    [void]$sha.TransformBlock($buf, 0, $n, $null, 0)
                    $fs.Write($buf, 0, $n)
                    if ($OnDetail -and $tick.ElapsedMilliseconds -ge 200) { $tick.Restart(); $null = & $OnDetail (Format-JavaProgress $name $total $length) }
                }
                [void]$sha.TransformFinalBlock($buf, 0, 0)
                if ($OnDetail) { $null = & $OnDetail (Format-JavaProgress $name $total $length) }
                ([BitConverter]::ToString($sha.Hash) -replace '-', '').ToLowerInvariant()
            } finally { $fs.Dispose(); $body.Dispose(); $sha.Dispose() }
        } finally { $resp.Close() }
    }
    # java.exe -version çalışıyor mu? Sorun yoksa $null, varsa nedeni.
    function Test-JavaRuns([string]$exe, [int]$major) {
        if (-not $exe) { return 'java.exe not found after extracting' }
        $psi = New-Object Diagnostics.ProcessStartInfo $exe
        $psi.Arguments = '-version'
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        # Hiç başlatılamıyorsa (ör. güvenlik yazılımı engelledi) bu da bir neden: çalışmayan kopya yerinde kalmasın
        try { $p = [Diagnostics.Process]::Start($psi) } catch { return (Get-JavaError $_.Exception).Message }
        try {
            $err = $p.StandardError.ReadToEndAsync(); $out = $p.StandardOutput.ReadToEndAsync()
            if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch {}; return 'java -version did not finish' }
            $text = $err.Result + $out.Result
            if ($p.ExitCode -ne 0) { return ('java -version exited with code {0}: {1}' -f $p.ExitCode, $text.Trim()) }
            # openjdk version "21.0.5" / "1.8.0_432"
            $m = [regex]::Match($text, 'version "(\d+)(?:\.(\d+))?')
            $v = 0
            if ($m.Success -and [int]::TryParse($m.Groups[1].Value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
                if ($v -eq 1 -and $m.Groups[2].Success) { [void][int]::TryParse($m.Groups[2].Value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) }
                if ($v -ne $major) { return "expected Java $major but the archive has Java $v" }
            }
            $null
        } finally { $p.Dispose() }
    }
    function Remove-JavaFile([string]$path) { try { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } } catch {} }
    function Remove-JavaDir([string]$dir) {
        for ($i = 0; $i -lt 5; $i++) {
            try { if (-not [IO.Directory]::Exists($dir)) { return }; [IO.Directory]::Delete($dir, $true); return } catch { Start-Sleep -Milliseconds 300 }
        }
    }
    # Virüs tarayıcısı yeni açılan dosyaları kısa süre kilitleyebilir: taşımayı birkaç kez dene
    function Move-JavaDir([string]$from, [string]$to) {
        for ($i = 0; ; $i++) {
            try { [IO.Directory]::Move($from, $to); return }
            catch {
                $e = Get-JavaError $_.Exception
                if ($i -lt 10 -and ($e -is [IO.IOException] -or $e -is [UnauthorizedAccessException])) { Start-Sleep -Milliseconds 300 } else { throw $e }
            }
        }
    }
    # Önceki yarım kalmış denemelerin artıkları: java-N.xxxx.zip / .tmp / .old
    function Clear-JavaLeftovers([string]$tools, [int]$major) {
        try {
            foreach ($f in [IO.Directory]::GetFiles($tools, "java-$major.*.zip")) { Remove-JavaFile $f }
            foreach ($d in [IO.Directory]::GetDirectories($tools, "java-$major.*.tmp")) { Remove-JavaDir $d }
            foreach ($d in [IO.Directory]::GetDirectories($tools, "java-$major.*.old")) { Remove-JavaDir $d }
        } catch {}
    }
    # Java'yı Data\tools\java-N içine indirir, java.exe yolunu döner (olmazsa nedeniyle hata fırlatır)
    function Install-Java([int]$major, [scriptblock]$OnDetail, [string]$HeadText) {
        $head = if ($HeadText) { if ($HeadText.Contains('{0}')) { $HeadText -f $major } else { $HeadText } }
                elseif (Get-Command L -CommandType Function -ErrorAction SilentlyContinue) { L 'Java {0} indiriliyor...' $major }
                else { 'Java {0} indiriliyor...' -f $major }
        if ($OnDetail) { $null = & $OnDetail $head }
        if ([string]::IsNullOrEmpty($DataDir)) { throw (New-Object InvalidOperationException 'Install-Java: $DataDir is not set.') }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        # Eski Windows'larda TLS 1.2 kendiliğinden açık olmayabilir
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $tools = [IO.Path]::Combine([IO.Path]::GetFullPath($DataDir), 'tools')
        [void][IO.Directory]::CreateDirectory($tools)
        $final = [IO.Path]::Combine($tools, "java-$major")
        Clear-JavaLeftovers $tools $major
        $last = $null
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            if ($attempt -gt 0) { Start-Sleep -Milliseconds (2000 * $attempt) }
            $id = [Guid]::NewGuid().ToString('N').Substring(0, 8)
            $zip = [IO.Path]::Combine($tools, "java-$major.$id.zip")
            $tmp = [IO.Path]::Combine($tools, "java-$major.$id.tmp")
            try {
                # Adoptium'un bildirdiği SHA-256 (ulaşılamazsa $null: o zaman zip'in açılması ve java -version yeter)
                $sum = Get-JavaChecksum $major
                $hash = Save-JavaFile "https://api.adoptium.net/v3/binary/latest/$major/ga/windows/x64/jre/hotspot/normal/eclipse" $zip $OnDetail
                # Tutmazsa bir kez daha sor: iki istek arasında yeni sürüm çıkmış olabilir
                if ($sum -and $sum -ne $hash -and (Get-JavaChecksum $major) -ne $hash) { throw (New-Object IO.InvalidDataException "The Java $major archive does not match its SHA-256 checksum.") }
                [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
                if (-not (Get-JavaLocate $tmp)) { throw (New-Object IO.InvalidDataException "java.exe is missing from the Java $major archive.") }
                Remove-JavaFile $zip
                # Yarım kalmış eski klasörü kenara al, yenisini tek adımda yerine koy
                if ([IO.Directory]::Exists($final)) {
                    $old = [IO.Path]::Combine($tools, "java-$major.$id.old")
                    Move-JavaDir $final $old
                    Remove-JavaDir $old
                }
                Move-JavaDir $tmp $final
                $exe = Get-JavaLocate $final
                $why = Test-JavaRuns $exe $major
                if ($why) {
                    # Çalışmayan Java "bulunmuş" sayılmasın: silinemezse en azından adı değişsin
                    Remove-JavaDir $final
                    if ([IO.Directory]::Exists($final)) { $bad = [IO.Path]::Combine($tools, "java-$major.$id.old"); try { Move-JavaDir $final $bad; Remove-JavaDir $bad } catch {} }
                    throw (New-Object IO.InvalidDataException $why)
                }
                return $exe
            } catch {
                $last = Get-JavaError $_.Exception
                if (Test-JavaPermanent $last) { break }   # böyle bir sürüm yok: tekrar denemek boşuna
            } finally {
                Remove-JavaFile $zip
                Remove-JavaDir $tmp
            }
        }
        $msg = "Java $major could not be downloaded: " + $(if ($null -ne $last) { $last.Message } else { '' })
        throw (New-Object IO.IOException -ArgumentList $msg, ([Exception]$last))
    }
}
. $JavaFuncs

# ---------- Renkler ve metin ----------
$E = [char]27
function Rgb($cr, $cg, $cb) { "$E[38;2;${cr};${cg};${cb}m" }
$R = "$E[0m"; $Bo = "$E[1m"
$c = @{
    brass = (Rgb 239 55 66); copper = (Rgb 160 28 40); text = (Rgb 240 240 240); soft = (Rgb 165 165 170)
    dim = (Rgb 110 110 116); dark = (Rgb 58 58 64); green = (Rgb 120 220 140); yellow = (Rgb 255 135 135)
    red = (Rgb 255 70 80); cyan = (Rgb 255 255 255); blue = (Rgb 220 220 225); orange = (Rgb 220 60 70); violet = (Rgb 255 160 165)
}
$PackColor = @{ dusuk = (Rgb 235 235 235); normal = (Rgb 239 55 66); yuksek = (Rgb 255 30 45) }
$PrioTr = @{ Normal = (L 'Normal'); AboveNormal = (L 'Normal Üstü'); High = (L 'Yüksek'); BelowNormal = (L 'Düşük'); Idle = (L 'En Düşük') }
$LoaderName = @{ neoforge = 'NeoForge'; forge = 'Forge'; fabric = 'Fabric'; quilt = 'Quilt' }

$AnsiRx = [regex]"$E\[[0-9;?]*[A-Za-z]"
# Japonca/Çince gibi geniş karakterler ekranda iki sütun kaplar
$WideRx = [regex]'[ᄀ-ᅟ⺀-〾ぁ-㏿㐀-䶿一-鿿ꀀ-꓏가-힣豈-﫿︰-﹏＀-｠￠-￦]'
function CharW([char]$ch) { if ([int]$ch -ge 0x1100 -and $WideRx.IsMatch([string]$ch)) { 2 } else { 1 } }
function VLen([string]$str) { $plain = $AnsiRx.Replace($str, ''); $plain.Length + $WideRx.Matches($plain).Count }
function Cut([string]$str, [int]$w) {
    $sb = New-Object Text.StringBuilder; $n = 0; $i = 0
    while ($i -lt $str.Length -and $n -lt $w) {
        if ($str[$i] -eq $E) { $m = $AnsiRx.Match($str, $i); if ($m.Success -and $m.Index -eq $i) { [void]$sb.Append($m.Value); $i += $m.Length; continue } }
        $cw = CharW $str[$i]
        if ($n + $cw -gt $w) { break }
        [void]$sb.Append($str[$i]); $n += $cw; $i++
    }
    [void]$sb.Append($R)
    if ($n -lt $w) { [void]$sb.Append(' ' * ($w - $n)) }
    $sb.ToString()
}
function PadV([string]$str, [int]$w) {
    $l = VLen $str
    if ($l -lt $w) { return $str + $R + (' ' * ($w - $l)) }
    if ($l -gt $w) { return Cut $str $w }
    $str + $R
}
function WordWrap([string]$text, [int]$w) {
    $out = New-Object System.Collections.Generic.List[string]; $line = ''
    foreach ($word in ($text -split ' ')) {
        if ($line.Length -eq 0) { $line = $word } elseif (($line.Length + 1 + $word.Length) -le $w) { $line += ' ' + $word } else { $out.Add($line); $line = $word }
    }
    if ($line) { $out.Add($line) }
    , $out
}
function Pill([string]$bg, [string]$fg, [string]$text) { "$E[48;2;${bg}m$E[38;2;${fg}m$E[1m $text $R" }
function Norm([string]$str) {
    $str = $str.ToLower([Globalization.CultureInfo]::GetCultureInfo('tr-TR'))
    $str.Replace('ı', 'i').Replace('ş', 's').Replace('ğ', 'g').Replace('ü', 'u').Replace('ö', 'o').Replace('ç', 'c')
}

# ---------- Animasyon araçları ----------
$Clock = [Diagnostics.Stopwatch]::StartNew()
function T { $Clock.Elapsed.TotalSeconds }
$SpinFrames = '⣾⣽⣻⢿⡿⣟⣯⣷'
function Spin([double]$speed = 12) { [string]$SpinFrames[[int]((T) * $speed) % $SpinFrames.Length] }
$PulseFrames = @('∙', '•', '◉', '⬤', '◉', '•')
function Pulse { [string]$PulseFrames[[int]((T) * 7) % $PulseFrames.Count] }

# Parıltı: metnin üzerinden ışık geçer
function Shimmer([string]$text, [int[]]$base, [int[]]$hi, [double]$speed = 16, [double]$width = 4) {
    $len = $text.Length
    if ($len -eq 0) { return '' }
    $center = (((T) * $speed) % ($len + 14)) - 7
    $sb = New-Object Text.StringBuilder
    for ($i = 0; $i -lt $len; $i++) {
        $k = [Math]::Max(0.0, 1.0 - [Math]::Abs($i - $center) / $width)
        $cr = [int]($base[0] + ($hi[0] - $base[0]) * $k); $cg = [int]($base[1] + ($hi[1] - $base[1]) * $k); $cb = [int]($base[2] + ($hi[2] - $base[2]) * $k)
        [void]$sb.Append("$E[38;2;$cr;$cg;${cb}m").Append($text[$i])
    }
    [void]$sb.Append($R); $sb.ToString()
}

$Verbs = @((L 'Dişliler hizalanıyor'), (L 'Çarklar yağlanıyor'), (L 'Pirinç parlatılıyor'), (L 'Redstone ısıtılıyor'), (L "Chunk'lar örülüyor"),
    (L "Creeper'lar sakinleştiriliyor"), (L 'Köylüler pazarlığa hazırlanıyor'), (L 'Elmaslar sayılıyor'), (L 'Su çarkı çevriliyor'),
    (L 'Biyomlar boyanıyor'), (L 'Ender incileri cilalanıyor'), (L 'Mekanik presler ayarlanıyor'), (L 'Trenler raya oturtuluyor'), (L 'Rüzgar değirmeni kuruluyor'))
function Verb { $Verbs[[int]((T) / 2.6) % $Verbs.Count] }

function BarP([double]$pct, [int]$w) {
    if ($pct -lt 0) { $pct = 0 }; if ($pct -gt 100) { $pct = 100 }
    $fill = [int][Math]::Round($pct / 100 * $w)
    $sb = New-Object Text.StringBuilder
    $head = [int]((T) * 14) % [Math]::Max(1, $w + 6)
    for ($i = 0; $i -lt $w; $i++) {
        if ($i -lt $fill) {
            $k = [Math]::Max(0.0, 1.0 - [Math]::Abs($i - $head) / 3.0)
            $cr = [int](200 + 55 * $k); $cg = [int](30 + 225 * $k); $cb = [int](42 + 213 * $k)
            [void]$sb.Append("$E[38;2;$cr;$cg;${cb}m▰")
        } else { [void]$sb.Append($c.dark + '▱') }
    }
    [void]$sb.Append($R); $sb.ToString()
}
function Bar([double]$f, [int]$w) {
    if ($f -lt 0) { $f = 0 }; if ($f -gt 1) { $f = 1 }
    $n = [int][Math]::Round($f * $w)
    $col = if ($f -lt 0.6) { $c.green } elseif ($f -lt 0.85) { $c.yellow } else { $c.red }
    $col + ([string][char]0x2588 * $n) + $c.dark + ([string][char]0x2591 * ($w - $n)) + $R
}

# ---------- Logo ----------
$Font = @{
    'S' = @('███████╗', '██╔════╝', '███████╗', '╚════██║', '███████║', '╚══════╝')
    'Y' = @('██╗   ██╗', '╚██╗ ██╔╝', ' ╚████╔╝ ', '  ╚██╔╝  ', '   ██║   ', '   ╚═╝   ')
    'H' = @('██╗  ██╗', '██║  ██║', '███████║', '██╔══██║', '██║  ██║', '╚═╝  ╚═╝')
    'O' = @(' ██████╗ ', '██╔═══██╗', '██║   ██║', '██║   ██║', '╚██████╔╝', ' ╚═════╝ ')
    'T' = @('████████╗', '╚══██╔══╝', '   ██║   ', '   ██║   ', '   ██║   ', '   ╚═╝   ')
}
$LogoPlain = 0..5 | ForEach-Object { $row = $_; ('SYHOST'.ToCharArray() | ForEach-Object { $Font[[string]$_][$row] }) -join '' }
$LogoW = $LogoPlain[0].Length

# Logo: kırmızı-beyaz dalga sürekli akar, ara ara parlar ve "glitch" yapar
$Rnd = New-Object Random
$GlitchUntil = 0.0; $GlitchNext = 4.0; $GlitchRows = @{}
function Render-Logo([double]$reveal = 1.0, [double]$shine = -100) {
    $rows = New-Object System.Collections.Generic.List[string]
    $now = T
    if ($now -gt $GlitchNext) { $script:GlitchUntil = $now + 0.18; $script:GlitchNext = $now + 3.5 + $Rnd.NextDouble() * 4; $script:GlitchRows = @{}; foreach ($gr in 0..5) { if ($Rnd.NextDouble() -lt 0.45) { $GlitchRows[$gr] = $Rnd.Next(-3, 4) } } }
    $glitch = $now -lt $GlitchUntil
    $edge = $reveal * ($LogoW + 4)
    for ($r0 = 0; $r0 -lt 6; $r0++) {
        $sb = New-Object Text.StringBuilder; $line = $LogoPlain[$r0]
        $shift = if ($glitch -and $GlitchRows.ContainsKey($r0)) { $GlitchRows[$r0] } else { 0 }
        if ($shift -gt 0) { [void]$sb.Append(' ' * $shift) }
        $startI = if ($shift -lt 0) { -$shift } else { 0 }
        for ($i = $startI; $i -lt $line.Length; $i++) {
            $ch = $line[$i]
            if ($ch -eq ' ' -or $i -gt $edge) { [void]$sb.Append(' '); continue }
            # akan dalga: 0..1
            $wave = ([Math]::Sin(($i / 7.0) - $now * 2.6 + $r0 * 0.35) + 1) / 2
            if ($ch -eq [char]0x2588) { $cr = 175 + 80 * $wave; $cg = 18 + 70 * [Math]::Pow($wave, 3); $cb = 30 + 70 * [Math]::Pow($wave, 3) }
            else { $cr = 70 + 40 * $wave; $cg = 14; $cb = 20 }
            $k = 0.0
            if ($edge - $i -lt 3 -and $reveal -lt 1) { $k = 1 - ($edge - $i) / 3 }
            $d = [Math]::Abs(($i - $r0 * 0.8) - $shine); if ($d -lt 5) { $k = [Math]::Max($k, 1 - $d / 5) }
            if ($glitch -and $GlitchRows.ContainsKey($r0)) { $k = [Math]::Max($k, 0.55) }
            $cr = [int]($cr + (255 - $cr) * $k); $cg = [int]($cg + (255 - $cg) * $k); $cb = [int]($cb + (255 - $cb) * $k)
            [void]$sb.Append("$E[38;2;$cr;$cg;${cb}m$ch")
        }
        [void]$sb.Append($R); $rows.Add($sb.ToString())
    }
    , $rows
}
function Logo-Shine { $p = (T) % 4.5; if ($p -lt 1.3) { return ($p / 1.3) * ($LogoW + 16) - 8 }; -100 }

# ---------- Durum ----------
$Screen = 'splash'            # splash | home | wizard | server
$SplashStart = 0.0
$HomeSel = 0; $HomeMode = 'list'; $HomeMsg = ''; $HomeMsgUntil = [DateTime]::MinValue
$WorldSizeCache = @{}; $ModCountCache = @{}
$Cur = $null
$S = $null
$Status = 'KAPALI'
$StatusLook = @{ KAPALI = @($c.red, (L 'KAPALI')); BASLIYOR = @($c.yellow, (L 'AÇILIYOR')); ACIK = @($c.green, (L 'AÇIK')); DURUYOR = @($c.orange, (L 'KAPANIYOR')) }
$StartTime = $null; $WasRunning = $false; $StopRequested = $false; $AfterStop = $null; $AutoRestartAt = $null; $StopSentAt = $null
$Players = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$LoadedRamMax = 0; $RamPending = $false
$Log = New-Object System.Collections.Generic.List[object]
$Scroll = 0; $Mode = 'log'; $ActivePack = 'normal'; $PackSel = 1
$InputText = ''; $History = New-Object System.Collections.Generic.List[string]; $HistIdx = -1
$Dirty = $true; $LastRender = [DateTime]::MinValue; $LastSize = ''; $WasVisible = $true; $HideTipShown = $false
$PrevFrame = @()
$RamNow = 0; $CpuNow = 0; $LastCpuMs = 0; $LastStat = Get-Date; $SysFree = 0; $LastSlow = [DateTime]::MinValue
$BackupStage = $null; $BackupTask = $null; $BackupDst = $null; $BackupSince = $null; $LastBackup = Get-Date
$Detail = $false; $ReplyUntil = [DateTime]::MinValue
$Stage = 0; $StopPhase = 0; $ClosingSince = $null; $ShutdownStopAt = $null; $FinishAt = $null; $AfterClose = 'home'
$ExpectedStart = 35; $ModCount = 0
$CrashTimes = New-Object System.Collections.Generic.List[datetime]
$Quit = $false
$RestartApp = $false
$Wiz = $null

# ---------- Yeni ekranlar: ilk açılış, ayarlar, kaldır (FirstRun.ps1, Settings.ps1, Uninstall.ps1) ----------
$NextAfterSplash = 'home'      # açılış animasyonundan sonra gidilecek ekran
$LaunchAfterExit = $null       # SyHost kapanınca açılacak SyHost.exe (kurulum ya da güncellemeden sonra)
$DeleteRootAfterExit = $false  # kaldır: SyHost kapanınca klasörü de sil
$FrMigrated = $null            # açılışta eski veriler kopyalandıysa: [pscustomobject]@{ Servers = <sayı>; Playit = <bool> }
$FrMovedTo = $null             # eski veriler daha önce başka bir SyHost klasörüne taşınmışsa o klasör
$Fr = $null                    # ilk açılış durumu (New-FirstRunState)
# Test modunda sabitlenen sistem bilgileri (C#: App.FirstRun.cs Test* alanları). $null: gerçek değer kullanılır.
$TestJava = $null; $TestJavaOwn = $null; $TestFontOk = $null; $TestPlayitReady = $null; $TestDryRun = $null
$TestShortcut = $null; $TestOsBuild = $null; $TestDefaultRoot = $null; $TestLegacyDir = $null

# ---------- Pencere modu ----------
$Win = [pscustomobject]@{ mod = 'buyuk'; buyukX = $null; buyukY = $null; kucukX = $null; kucukY = $null; ustte = $true }
if (-not $SetupMode -and (Test-Path -LiteralPath $WinFile)) { try { $w0 = Get-Content -LiteralPath $WinFile -Raw | ConvertFrom-Json; foreach ($pn in $w0.PSObject.Properties.Name) { $Win.$pn = $w0.$pn } } catch {} }
$UiMode = 'buyuk'
$BigSize = @(130, 42); $MiniSize = @(54, 15)

function Set-ConsoleSize([int]$w, [int]$h) {
    try {
        $max = $Host.UI.RawUI.MaxPhysicalWindowSize
        $w = [Math]::Min($w, $max.Width); $h = [Math]::Min($h, $max.Height)
        [Console]::SetWindowSize(1, 1); [Console]::SetBufferSize($w, $h); [Console]::SetWindowSize($w, $h)
    } catch {}
}
function Save-WinState {
    try {
        $rc = [SyHost.Native]::GetRect()
        if ([SyHost.Native]::Visible -and $rc[2] -gt 100) {
            if ($UiMode -eq 'kucuk') { $Win.kucukX = $rc[0]; $Win.kucukY = $rc[1] } else { $Win.buyukX = $rc[0]; $Win.buyukY = $rc[1] }
        }
        if ($Screen -eq 'server') { $Win.mod = $UiMode }
        if ($TestFrame) { return }
        Write-TextFile $WinFile ($Win | ConvertTo-Json)
    } catch {}
}
function Wait-WinRect {
    $prev = [SyHost.Native]::GetRect()
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 40
        $cur2 = [SyHost.Native]::GetRect()
        if ($cur2[2] -eq $prev[2] -and $cur2[3] -eq $prev[3] -and $i -ge 2) { return , $cur2 }
        $prev = $cur2
    }
    , $prev
}
function Reset-Frame { $script:PrevFrame = @(); [Console]::Write("$E[2J"); $script:Dirty = $true }
function Set-UiMode([string]$m, [switch]$NoSave) {
    if (-not $NoSave) { Save-WinState }
    $script:UiMode = $m
    if ($m -eq 'kucuk') {
        if ($Mode -notin 'log', 'kapat', 'closing') { $script:Mode = 'log' }
        Set-ConsoleSize $MiniSize[0] $MiniSize[1]
        $rc = Wait-WinRect
        if ($Win.kucukX -ne $null -and [SyHost.Native]::OnAnyScreen($Win.kucukX, $Win.kucukY)) { [SyHost.Native]::MoveTo($Win.kucukX, $Win.kucukY) }
        else { $wa = [SyHost.Native]::WorkArea(); [SyHost.Native]::MoveTo($wa[0] + $wa[2] - $rc[2] - 12, $wa[1] + $wa[3] - $rc[3] - 12) }
        [SyHost.Native]::SetTopMost([bool]$Win.ustte)
    } else {
        [SyHost.Native]::SetTopMost($false)
        Set-ConsoleSize $BigSize[0] $BigSize[1]
        if ($Win.buyukX -ne $null -and [SyHost.Native]::OnAnyScreen($Win.buyukX, $Win.buyukY)) { [SyHost.Native]::MoveTo($Win.buyukX, $Win.buyukY) }
        else { $rc = Wait-WinRect; $wa = [SyHost.Native]::WorkArea(); [SyHost.Native]::MoveTo($wa[0] + [int](($wa[2] - $rc[2]) / 2), $wa[1] + [int](($wa[3] - $rc[3]) / 2)) }
    }
    Reset-Frame; $script:LastSize = ''
    if (-not $NoSave) { Save-WinState }
}

# Tuş basılı tutulunca art arda tetiklenmesin
$LastPress = @{}
function Allow([string]$key, [int]$ms = 1000) {
    $now = Get-Date
    if ($LastPress.ContainsKey($key) -and ($now - $LastPress[$key]).TotalMilliseconds -lt $ms) { return $false }
    $LastPress[$key] = $now
    $true
}
function Clear-KeyBuffer { try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } } catch {} }
function Toggle-UiMode {
    if ($Screen -ne 'server') { return }
    if (-not (Allow 'mini' 1000)) { Clear-KeyBuffer; return }
    if (-not [SyHost.Native]::Visible) { [SyHost.Native]::Show() }
    if ($UiMode -eq 'kucuk') { Set-UiMode 'buyuk' } else { Set-UiMode 'kucuk' }
    Clear-KeyBuffer
    $script:LastPress['mini'] = Get-Date
}

# ---------- Konsol kaydı ----------
function Add-Log([string]$kind, [string]$msg, [string]$time, [bool]$vis = $true) {
    if (-not $time) { $time = (Get-Date).ToString('HH:mm:ss') }
    $script:Log.Add([pscustomobject]@{ T = $time; K = $kind; M = $msg; V = $vis })
    if ($script:Log.Count -gt 4000) { $script:Log.RemoveRange(0, 1000) }
    if ($script:Scroll -gt 0 -and ($vis -or $Detail)) { $script:Scroll++ }
    $script:Dirty = $true
}
# Dili sırayla değiştir (en → tr → ja), ayara kaydet ve SyHost'u yeni dille yeniden aç
function Switch-Language {
    $codes = @($Languages.Keys)
    $next = $codes[([Array]::IndexOf($codes, $LangCode) + 1) % $codes.Count]
    $Cfg.dil = $next
    Save-Config
    $script:RestartApp = $true; $script:Quit = $true
}
function Home-Msg([string]$msg) { $script:HomeMsg = $msg; $script:HomeMsgUntil = (Get-Date).AddSeconds(6); $script:Dirty = $true }

# ---------- Paketler ----------
function Get-Mask([int]$n) {
    if ($n -le 0 -or $n -ge $Threads) { $n = $Threads }
    $m = [long]0
    for ($i = $Threads - $n; $i -lt $Threads; $i++) { $m = $m -bor ([long]1 -shl $i) }
    $m
}
function Apply-PackLive {
    if (-not ($S -and $S.Running)) { return }
    $p = $Packs.$ActivePack
    try { $S.P.PriorityClass = [Diagnostics.ProcessPriorityClass]$p.oncelik } catch {}
    try { $S.P.ProcessorAffinity = [IntPtr](Get-Mask $p.cekirdek) } catch {}
}
function Set-Pack([string]$name) {
    $n = Norm $name
    $key = switch -Regex ($n) { '^(dusuk|low|eco|1|低)$' { 'dusuk' } '^(normal|orta|2|標準)$' { 'normal' } '^(yuksek|high|max|3|高)$' { 'yuksek' } default { $null } }
    if (-not $key) { Add-Log warn (L "Böyle bir paket yok: '{0}'. Seçenekler: dusuk, normal, yuksek" $name); return }
    $script:ActivePack = $key
    $script:PackSel = [Array]::IndexOf($PackKeys, $key)
    if ($Cur) { $Cur.paket = $key; Save-Servers }
    $p = $Packs.$key
    Apply-PackLive
    Add-Log ok ((L "Paket: {0}  ·  RAM {1}-{2} GB  ·  {3} çekirdek  ·  öncelik {4}") -f (PackName $key), $p.ramMin, $p.ramMax, [Math]::Min($p.cekirdek, $Threads), $PrioTr[$p.oncelik])
    if ($S -and $S.Running) {
        if ($p.ramMax -ne $LoadedRamMax) { $script:RamPending = $true; Add-Log panel (L "Çekirdek ve öncelik hemen uygulandı. RAM değişikliği için 'yeniden' yaz.") }
        else { $script:RamPending = $false }
    }
}

# ---------- playit (sadece SyHost açıkken) ----------
# playit 2.x: playitd.exe tünelleri çalıştırır. Data\tools\playit içine iner (FirstRun.ps1, arkadaş adımı);
# eski sürümün Program Files'taki kopyası da kullanılabilir. Yalnızca SyHost açıkken çalışır.
$PlayitToolDir = Join-Path $Data 'tools\playit'
$PlayitLegacyBin = 'C:\Program Files\playit_gg\bin'
$PlayitExe = $null
$Pl = $null
function Start-Playit {
    if (-not $Cfg.playitKullan) { return }
    if ($Pl -and $Pl.Running) { return }
    $script:PlayitExe = Find-PlayitDaemon
    # Program ya da anahtar yoksa playit'i bu oturum için kapat (ayar dosyadaki gibi kalır; program gelince yeniden denenir)
    if (-not $PlayitExe -or -not (Test-Path -LiteralPath $PlayitSecret)) { $script:HasFriendAddr = $false; return }
    $script:Pl = New-Object SyHost.Server
    try { $Pl.Start($PlayitExe, "--secret-path `"$PlayitSecret`" --socket-path \\.\pipe\syhost-playit --log-path `"$(Join-Path (Split-Path $PlayitSecret) 'playit.log')`"", (Split-Path $PlayitSecret)) } catch {}
}
function Stop-Playit { if ($Pl -and $Pl.Running) { try { $Pl.P.Kill() } catch {} } }
function PlayitOn { [bool]($Pl -and $Pl.Running) }

# ---------- Sunucu kontrolü ----------
$JvmBase = '-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1'

function Get-ModCount([string]$dir) { @(Get-ChildItem (Join-Path $dir 'mods') -Filter *.jar -ErrorAction SilentlyContinue).Count }

function Ensure-VoiceHost {
    if (-not $Cfg.sesAdresi -or -not $Cfg.playitKullan) { return }
    $vp = Join-Path $Cur.klasor 'config\voicechat\voicechat-server.properties'
    if (-not (Test-Path $vp)) { return }
    $txt = [IO.File]::ReadAllText($vp)
    if ($txt -match '(?m)^voice_host=(.*)$' -and $Matches[1].Trim() -ne $Cfg.sesAdresi) {
        $txt = [regex]::Replace($txt, '(?m)^voice_host=.*$', "voice_host=$($Cfg.sesAdresi)")
        [IO.File]::WriteAllText($vp, $txt, (New-Object Text.UTF8Encoding $false))
    }
}

function Start-Server {
    if ($S -and $S.Running) { Add-Log panel (L 'Sunucu zaten açık.'); return }
    if (-not (Test-Path (Join-Path $Cur.klasor 'mods')) -and -not (Test-Path $Cur.klasor)) { Add-Log error (L 'Sunucu klasörü bulunamadı: {0}  (taşındı ya da silindi)' $Cur.klasor); return }
    $other = @(Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'nogui' })
    if ($other.Count) { Add-Log error ((L "Başka bir sunucu zaten çalışıyor (PID {0}). Önce onu kapat ya da 'zorla' yaz.") -f $other[0].ProcessId); return }
    $java = Find-Java ([int]$Cur.java)
    if (-not $java) { Add-Log error (L 'Java {0} bulunamadı. Sunucuyu yeniden kurman gerekebilir.' $Cur.java); return }
    $eula = Join-Path $Cur.klasor 'eula.txt'
    if (-not (Test-Path $eula) -or -not (Select-String -Path $eula -Pattern 'eula=true' -Quiet)) { Set-Content $eula 'eula=true' -Encoding ASCII }
    Ensure-VoiceHost
    $p = $Packs.$ActivePack
    $gc = if ($p.ramMax -ge 12) { '-XX:G1NewSizePercent=40 -XX:G1MaxNewSizePercent=50 -XX:G1HeapRegionSize=16M' } else { '-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M' }
    $jargs = "-Xms$($p.ramMin)G -Xmx$($p.ramMax)G $JvmBase $gc -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 -Dsyhost=1 $($Cur.baslat)"
    $script:S = New-Object SyHost.Server
    try { $S.Start($java, $jargs, $Cur.klasor) } catch { Add-Log error (L 'Sunucu başlatılamadı: {0}' $_.Exception.Message); return }
    [SyHost.CloseGuard]::Current = $S
    Apply-PackLive
    $script:Status = 'BASLIYOR'; $script:StartTime = Get-Date; $script:Players.Clear()
    $script:LoadedRamMax = $p.ramMax; $script:RamPending = $false; $script:StopRequested = $false; $script:AutoRestartAt = $null
    $script:LastCpuMs = 0; $script:WasRunning = $true; $script:Stage = 1; $script:StopPhase = 0
    $Cur.sonAcilis = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Save-Servers
    Add-Log panel ((L "Sunucu başlatılıyor...  paket {0} · RAM {1}-{2} GB") -f (PackName $ActivePack), $p.ramMin, $p.ramMax)
}
function Stop-Server([string]$then) {
    if (-not ($S -and $S.Running)) {
        if ($then -eq 'close') { $script:FinishAt = (Get-Date).AddMilliseconds(700) } elseif ($then -eq 'restart') { Start-Server } else { Add-Log panel (L 'Sunucu zaten kapalı.') }
        return
    }
    $script:AfterStop = $then; $script:StopRequested = $true; $script:Status = 'DURUYOR'; $script:StopSentAt = Get-Date; $script:StopPhase = 1
    $S.Send('stop')
    Add-Log panel (L 'Sunucu durduruluyor, dünya kaydediliyor...')
}

function Start-Backup {
    if ($BackupStage) { Add-Log warn (L 'Zaten bir yedek alınıyor.'); return }
    $dir = Join-Path $Cur.klasor 'yedekler'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $script:BackupDst = Join-Path $dir ("world-{0}.zip" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    $script:LastBackup = Get-Date
    if ($S -and $S.Running -and $Status -eq 'ACIK') {
        $S.Send('save-off'); $S.Send('save-all flush')
        $script:BackupStage = 'saving'; $script:BackupSince = Get-Date
        Add-Log panel (L 'Yedek: dünya diske kaydediliyor...')
    } else { Begin-Zip }
}
function Begin-Zip {
    if (-not (Test-Path (Join-Path $Cur.klasor 'world'))) { Add-Log warn (L 'Yedeklenecek dünya henüz yok (sunucu bir kez açılınca oluşur).'); if ($S -and $S.Running) { $S.Send('save-on') }; $script:BackupStage = $null; return }
    $script:BackupTask = [SyHost.Backup]::ZipAsync((Join-Path $Cur.klasor 'world'), $BackupDst)
    $script:BackupStage = 'zipping'
    Add-Log panel (L 'Yedek: sıkıştırılıyor (oyun devam edebilir)...')
}
function Check-Backup {
    if ($BackupStage -eq 'saving' -and ((Get-Date) - $BackupSince).TotalSeconds -gt 40) { Begin-Zip }
    if ($BackupStage -eq 'zipping' -and $BackupTask.IsCompleted) {
        if ($S -and $S.Running) { $S.Send('save-on') }
        if ($BackupTask.IsFaulted) { Add-Log error ((L "Yedek alınamadı: ") + $BackupTask.Exception.InnerException.Message) }
        else {
            $mb = [Math]::Round((Get-Item $BackupDst).Length / 1MB)
            Add-Log ok ((L "Yedek alındı: {0}  ({1} MB)") -f (Split-Path $BackupDst -Leaf), $mb)
            $keep = [int]$Cfg.saklanacakYedek
            if ($keep -gt 0) { Get-ChildItem (Split-Path $BackupDst) -Filter 'world-*.zip' | Sort-Object Name -Descending | Select-Object -Skip $keep | Remove-Item -Force -ErrorAction SilentlyContinue }
        }
        $script:BackupStage = $null; $script:BackupTask = $null
    }
}

$LineRx = [regex]'^\[(\d\d:\d\d:\d\d)\] \[(.+?)/([A-Z]+)\] \[(.*?)\]: ?(.*)$'
$LineRx2 = [regex]'^\[(\d\d:\d\d:\d\d)\] \[(.+?)/([A-Z]+)\]: ?(.*)$'
function Add-ServerLine([string]$raw) {
    $raw = $AnsiRx.Replace($raw, '')
    $m = $LineRx.Match($raw)
    if ($m.Success) { $t = $m.Groups[1].Value; $lvl = $m.Groups[3].Value; $msg = $m.Groups[5].Value }
    else {
        $m2 = $LineRx2.Match($raw)
        if ($m2.Success) { $t = $m2.Groups[1].Value; $lvl = $m2.Groups[3].Value; $msg = $m2.Groups[4].Value }
        else { $t = $null; $lvl = if ($raw.StartsWith('[STDERR]')) { 'ERROR' } else { 'INFO' }; $msg = $raw }
    }
    $kind = switch ($lvl) { 'WARN' { 'warn' } 'ERROR' { 'error' } 'FATAL' { 'error' } default { 'info' } }

    if ($Status -eq 'BASLIYOR') {
        if ($Stage -lt 2) { $script:Stage = 2 }
        if ($msg -match '^Starting minecraft server version' -and $Stage -lt 3) { $script:Stage = 3 }
        elseif ($msg -match 'Preparing (level|start region|spawn)' -and $Stage -lt 4) { $script:Stage = 4 }
    }
    if ($msg -match '^Stopping the server') { $script:StopPhase = [Math]::Max($StopPhase, 1) }
    elseif ($msg -match 'Saving (worlds|chunks|players)') { $script:StopPhase = [Math]::Max($StopPhase, 2) }
    elseif ($msg -match 'All (dimensions|chunks) are saved') { $script:StopPhase = [Math]::Max($StopPhase, 3) }

    if ($msg -match '^Done \(([\d\.,]+)s\)!') {
        $script:Status = 'ACIK'
        if ($StartTime) { $script:ExpectedStart = [int][Math]::Ceiling(((Get-Date) - $StartTime).TotalSeconds); $Cur.sonBaslatmaSn = $ExpectedStart; Save-Servers }
        Add-Log info $msg $t $false
        if ($HasFriendAddr) { Add-Log ok ((L "Sunucu hazır! ({0} sn)  Arkadaşların şu adresle girebilir: {1}") -f $ExpectedStart, $FriendAddr) }
        else { Add-Log ok ((L "Sunucu hazır! ({0} sn)  Bu bilgisayardan 'localhost' ile girebilirsin.") -f $ExpectedStart) }
        [SyHost.Tray]::Balloon((L '{0} açık' $Cur.ad), (L 'Arkadaşların artık girebilir.'))
        return
    }
    if ($msg -match '^(\S{1,16}) joined the game$') { [void]$Players.Add($Matches[1]); $kind = 'join'; $msg = L '{0} oyuna katıldı' $Matches[1] }
    elseif ($msg -match '^(\S{1,16}) left the game$') { [void]$Players.Remove($Matches[1]); $kind = 'leave'; $msg = L '{0} oyundan ayrıldı' $Matches[1] }
    elseif ($msg -match '^<([^>]+)> (.*)$') { $kind = 'chat' }
    elseif ($msg -match 'There are (\d+) of a max of (\d+) players online:?\s*(.*)$') {
        $Players.Clear(); foreach ($n in ($Matches[3] -split ',\s*')) { if ($n.Trim()) { [void]$Players.Add($n.Trim()) } }
        $msg = (L 'Çevrimiçi: {0}/{1}' $Matches[1] $Matches[2]) + $(if ($Players.Count) { "  ·  " + ($Players -join ', ') } else { '' }); $kind = 'ok'
    }
    elseif ($msg -match '^Saved the game' -and $BackupStage -eq 'saving') { Add-Log info $msg $t $false; Begin-Zip; return }
    elseif ($msg -match '^Stopping the server') { $script:Status = 'DURUYOR' }
    $vis = ($kind -in 'join', 'leave', 'chat', 'ok') -or ($kind -eq 'error' -and $Status -eq 'ACIK') -or ((Get-Date) -lt $ReplyUntil)
    Add-Log $kind $msg $t $vis
}

# ---------- Ekranlar arası geçiş ----------
function Enter-Server($srv) {
    $script:Cur = $srv
    $script:Log.Clear(); $script:Scroll = 0; $script:Mode = 'log'; $script:InputText = ''
    $script:ActivePack = if ($PackKeys -contains $srv.paket) { $srv.paket } else { 'normal' }
    $script:PackSel = [Array]::IndexOf($PackKeys, $ActivePack)
    $script:ExpectedStart = if ($srv.sonBaslatmaSn) { [Math]::Max(10, [int]$srv.sonBaslatmaSn) } else { 45 }
    $script:ModCount = Get-ModCount $srv.klasor
    $script:Status = 'KAPALI'; $script:WasRunning = $false; $script:Players.Clear(); $script:LastBackup = Get-Date
    $script:AutoRestartAt = $null; $script:StopSentAt = $null; $script:RamNow = 0; $script:CpuNow = 0; $script:Detail = $false
    $CrashTimes.Clear()
    $script:Screen = 'server'
    if ($Win.mod -eq 'kucuk' -and $UiMode -ne 'kucuk') { Set-UiMode 'kucuk' -NoSave } else { Reset-Frame }
    Add-Log panel (L '{0} açılıyor. Kapatmak için F10, nasıl kullanılır için F1.' $srv.ad)
    Start-Server
}
function Go-Home {
    $script:Screen = 'home'; $script:Mode = 'log'; $script:HomeMode = 'list'
    $script:S = $null; $script:Status = 'KAPALI'; $script:FinishAt = $null; $script:ShutdownStopAt = $null; $script:AutoRestartAt = $null; $script:StopSentAt = $null
    $CrashTimes.Clear()
    $ModCountCache.Clear(); $WorldSizeCache.Clear()
    if ($UiMode -eq 'kucuk') { Set-UiMode 'buyuk' -NoSave; $Win.mod = 'kucuk' } else { Reset-Frame }
}
function Begin-Shutdown([string]$after) {
    if ($Mode -eq 'closing') { return }
    $script:AfterClose = $after
    $script:Mode = 'closing'; $script:ClosingSince = Get-Date
    [SyHost.Native]::Show()
    if ($S -and $S.Running) {
        if ($Status -eq 'ACIK' -and $Players.Count) {
            $S.Send('say ' + (L 'Sunucu kapaniyor, dunya kaydediliyor. Gorusuruz!'))
            $script:ShutdownStopAt = (Get-Date).AddSeconds(3)
        } else { $script:ShutdownStopAt = Get-Date }
    } else { $script:ShutdownStopAt = $null; $script:FinishAt = (Get-Date).AddMilliseconds(700) }
    $script:Dirty = $true
}
function Hide-Panel {
    [SyHost.Native]::Hide()
    if (-not $HideTipShown) { [SyHost.Tray]::Balloon((L 'SyHost gizlendi'), (L 'Sunucu çalışmaya devam ediyor. Geri getirmek için Ctrl+Alt+G ya da saat yanındaki simge.')); $script:HideTipShown = $true }
}

# ---------- Kurulum sihirbazı ----------
function Read-Pack([string]$path) {
    $zip = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        $ie = $zip.GetEntry('modrinth.index.json')
        if (-not $ie) { throw (L 'Bu dosya bir Modrinth paketi (.mrpack) değil.') }
        $sr = New-Object IO.StreamReader($ie.Open()); $idx = $sr.ReadToEnd() | ConvertFrom-Json; $sr.Close()
        $deps = $idx.dependencies
        $loader = $null; $lv = $null
        foreach ($k in 'neoforge', 'forge', 'fabric-loader', 'quilt-loader') { if ($deps.PSObject.Properties.Name -contains $k) { $loader = ($k -replace '-loader', ''); $lv = $deps.$k; break } }
        if (-not $loader) { throw (L 'Paketin mod yükleyicisi anlaşılamadı.') }
        $saves = @($zip.Entries | Where-Object { $_.FullName -match '^overrides/saves/([^/]+)/level\.dat$' } | ForEach-Object { ($_.FullName -split '/')[2] } | Sort-Object -Unique)
        $srvFiles = @($idx.files | Where-Object { $_.env.server -ne 'unsupported' -and $_.path -like 'mods/*' })
        [pscustomobject]@{
            Path = $path; Name = $idx.name; Version = $idx.versionId; Mc = $deps.minecraft; Loader = $loader; LoaderVer = $lv
            Java = (Get-JavaMajor $deps.minecraft); Mods = $srvFiles.Count; ClientOnly = @($idx.files | Where-Object { $_.env.server -eq 'unsupported' }).Count
            Saves = $saves; SizeMb = [Math]::Round((Get-Item $path).Length / 1MB)
        }
    } finally { $zip.Dispose() }
}

function Safe-FolderName([string]$name) {
    $n = ($name -replace '[\\/:*?"<>|]', '').Trim().TrimEnd('.')
    $n = $n -replace '\s+', ''
    if (-not $n) { $n = 'Sunucu' }
    $base = Join-Path $Cfg.sunucuKokKlasoru $n; $p = $base; $i = 2
    while (Test-Path $p) { $p = "$base-$i"; $i++ }
    $p
}

$InstallScript = {
    param($sync, $info, $target, $worldName, $voiceHost, $maxPlayers, $motd, $javaFuncs, $tt)
    $ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
    . ([scriptblock]::Create($javaFuncs))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $cur = 0
    function Step([int]$i, [int]$st) { $sync.Steps[$i].S = $st; if ($st -eq 1) { Set-Variable -Name cur -Value $i -Scope 1 } }
    function Det([string]$t) { $sync.Detail = $t }
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($info.Path)
        $sr = New-Object IO.StreamReader($zip.GetEntry('modrinth.index.json').Open()); $index = $sr.ReadToEnd() | ConvertFrom-Json; $sr.Close()
        $mc = $info.Mc; $lv = $info.LoaderVer

        # 0 klasör
        $cur = 0; Step 0 1
        New-Item -ItemType Directory -Force $target, (Join-Path $target 'mods') | Out-Null
        Step 0 2

        # 1 Java
        $cur = 1; Step 1 1
        $jm = Get-JavaMajor $mc
        $java = Find-Java $jm
        if (-not $java) {
            Det ($tt.javaDl -f $jm)
            & winget install --id (Get-JavaWingetId $jm) -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
            $java = Find-Java $jm
            if (-not $java) { throw ($tt.javaFail -f $jm) }
        }
        Det ($tt.javaOk -f $jm)
        Step 1 2

        # 2 Mod yükleyici
        $cur = 2; Step 2 1
        $launch = $null
        switch ($info.Loader) {
            'neoforge' {
                Det ($tt.dl -f 'NeoForge', $lv)
                $inst = Join-Path $target 'neoforge-installer.jar'
                Invoke-WebRequest "https://maven.neoforged.net/releases/net/neoforged/neoforge/$lv/neoforge-$lv-installer.jar" -OutFile $inst -UseBasicParsing
                Det ($tt.inst -f 'NeoForge', $lv)
                $ok = $false
                for ($try = 0; $try -lt 3 -and -not $ok; $try++) { Push-Location $target; & $java -jar $inst --install-server $target *> (Join-Path $target 'kurulum.log'); $ok = ($LASTEXITCODE -eq 0); Pop-Location }
                if (-not $ok) { throw ($tt.instFail -f 'NeoForge') }
                Remove-Item $inst, (Join-Path $target 'neoforge-installer.jar.log') -ErrorAction SilentlyContinue
                $launch = "@libraries/net/neoforged/neoforge/$lv/win_args.txt nogui"
            }
            'forge' {
                $fv = "$mc-$lv"
                Det ($tt.dl -f 'Forge', $fv)
                $inst = Join-Path $target 'forge-installer.jar'
                Invoke-WebRequest "https://maven.minecraftforge.net/net/minecraftforge/forge/$fv/forge-$fv-installer.jar" -OutFile $inst -UseBasicParsing
                Det ($tt.inst -f 'Forge', $fv)
                $ok = $false
                for ($try = 0; $try -lt 3 -and -not $ok; $try++) { Push-Location $target; & $java -jar $inst --installServer $target *> (Join-Path $target 'kurulum.log'); $ok = ($LASTEXITCODE -eq 0); Pop-Location }
                if (-not $ok) { throw ($tt.instFail -f 'Forge') }
                Remove-Item $inst, (Join-Path $target 'forge-installer.jar.log') -ErrorAction SilentlyContinue
                if (Test-Path (Join-Path $target "libraries\net\minecraftforge\forge\$fv\win_args.txt")) { $launch = "@libraries/net/minecraftforge/forge/$fv/win_args.txt nogui" }
                else {
                    $jar = Get-ChildItem $target -Filter 'forge-*.jar' | Where-Object { $_.Name -notmatch 'installer' } | Select-Object -First 1
                    if (-not $jar) { throw $tt.forgeNoJar }
                    $launch = "-jar $($jar.Name) nogui"
                }
            }
            'fabric' {
                Det ($tt.dl -f 'Fabric', $lv)
                $instVer = (Invoke-RestMethod 'https://meta.fabricmc.net/v2/versions/installer' | Where-Object { $_.stable } | Select-Object -First 1).version
                Invoke-WebRequest "https://meta.fabricmc.net/v2/versions/loader/$mc/$lv/$instVer/server/jar" -OutFile (Join-Path $target 'fabric-server-launch.jar') -UseBasicParsing
                $launch = '-jar fabric-server-launch.jar nogui'
            }
            default { throw ($tt.unsupported -f $info.Loader) }
        }
        Step 2 2

        # 3 Modlar
        $cur = 3; Step 3 1
        $files = @($index.files | Where-Object { $_.env.server -ne 'unsupported' -and $_.path -notmatch '^(resourcepacks|shaderpacks)/' })
        $n = 0; $fail = @()
        $full = [IO.Path]::GetFullPath($target)
        foreach ($f in $files) {
            $n++
            $sync.Pct = [int]($n / [Math]::Max(1, $files.Count) * 100); $sync.Count = "$n/$($files.Count)"
            Det (Split-Path $f.path -Leaf)
            $out = [IO.Path]::GetFullPath((Join-Path $target ($f.path -replace '/', '\')))
            if (-not $out.StartsWith($full)) { continue }
            New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
            $ok = $false
            for ($try = 0; $try -lt 3 -and -not $ok; $try++) {
                foreach ($url in $f.downloads) {
                    try {
                        Invoke-WebRequest $url -OutFile $out -UseBasicParsing
                        if ((Get-FileHash $out -Algorithm SHA1).Hash.ToLower() -eq $f.hashes.sha1) { $ok = $true; break }
                    } catch {}
                }
            }
            if (-not $ok) { $fail += (Split-Path $f.path -Leaf); Remove-Item $out -ErrorAction SilentlyContinue }
        }
        $sync.Failed = $fail
        $sync.Pct = 100
        Step 3 2

        # 4 Ayar dosyaları
        $cur = 4; Step 4 1
        foreach ($en in $zip.Entries) {
            $fn = $en.FullName
            if (-not ($fn.StartsWith('overrides/') -or $fn.StartsWith('server-overrides/')) -or -not $en.Name) { continue }
            $rel = $fn.Substring($fn.IndexOf('/') + 1)
            if ($rel -match '^(resourcepacks|shaderpacks|saves)/') { continue }
            $dst = [IO.Path]::GetFullPath((Join-Path $target ($rel -replace '/', '\')))
            if (-not $dst.StartsWith($full)) { continue }
            New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($en, $dst, $true)
        }
        Step 4 2

        # 5 Dünya
        $cur = 5; Step 5 1
        if ($worldName) {
            Det $tt.worldCopy
            $pre = "overrides/saves/$worldName/"
            foreach ($en in $zip.Entries) {
                if (-not $en.FullName.StartsWith($pre) -or -not $en.Name) { continue }
                $rel = $en.FullName.Substring($pre.Length)
                if ($rel -eq 'session.lock') { continue }
                $dst = [IO.Path]::GetFullPath((Join-Path (Join-Path $target 'world') ($rel -replace '/', '\')))
                if (-not $dst.StartsWith($full)) { continue }
                New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($en, $dst, $true)
            }
        } else { Det $tt.worldNew }
        Step 5 2

        # 6 Son ayarlar
        $cur = 6; Step 6 1
        $props = [ordered]@{ 'motd' = $motd; 'level-name' = 'world'; 'max-players' = "$maxPlayers"; 'online-mode' = 'true'; 'difficulty' = 'normal'; 'spawn-protection' = '0'; 'view-distance' = '10'; 'simulation-distance' = '8'; 'allow-flight' = 'true'; 'server-port' = '25565'; 'enable-command-block' = 'true' }
        $pf = Join-Path $target 'server.properties'
        $lines = New-Object System.Collections.Generic.List[string]
        if (Test-Path $pf) { foreach ($ln in [IO.File]::ReadAllLines($pf)) { $lines.Add($ln) } }
        foreach ($k in $props.Keys) {
            $found = $false
            for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^$([regex]::Escape($k))=") { $lines[$i] = "$k=$($props[$k])"; $found = $true } }
            if (-not $found) { $lines.Add("$k=$($props[$k])") }
        }
        [IO.File]::WriteAllLines($pf, $lines.ToArray(), (New-Object Text.UTF8Encoding $false))
        Set-Content (Join-Path $target 'eula.txt') 'eula=true' -Encoding ASCII
        if ($voiceHost -and @(Get-ChildItem (Join-Path $target 'mods') -Filter '*voicechat*' -ErrorAction SilentlyContinue).Count) {
            $vd = Join-Path $target 'config\voicechat'; New-Item -ItemType Directory -Force $vd | Out-Null
            $vp = Join-Path $vd 'voicechat-server.properties'
            if (-not (Test-Path $vp)) { [IO.File]::WriteAllLines($vp, [string[]]@('port=24454', 'bind_address=', "voice_host=$voiceHost"), (New-Object Text.UTF8Encoding $false)) }
            else { $vt = [IO.File]::ReadAllText($vp); if ($vt -match '(?m)^voice_host=') { $vt = [regex]::Replace($vt, '(?m)^voice_host=.*$', "voice_host=$voiceHost") } else { $vt = $vt.TrimEnd() + "`nvoice_host=$voiceHost`n" }; [IO.File]::WriteAllText($vp, $vt, (New-Object Text.UTF8Encoding $false)) }
        }
        Step 6 2
        $zip.Dispose()
        $sync.Result = @{ mc = $mc; loader = $info.Loader; loaderSurum = $lv; java = $jm; baslat = $launch }
    } catch {
        $sync.Error = $_.Exception.Message
        try { $sync.Steps[$cur].S = 3 } catch {}
        try { $zip.Dispose() } catch {}
    }
    $sync.Done = $true
}

function Start-Wizard {
    $path = [SyHost.Native]::PickFile((L 'Kurulacak modpack dosyasını seç (.mrpack)'), (L 'Modrinth paketi (*.mrpack)|*.mrpack'))
    Reset-Frame
    if (-not $path) { Home-Msg (L 'Dosya seçilmedi.'); return }
    try { $info = Read-Pack $path } catch { Home-Msg (L 'Paket okunamadı: {0}' $_.Exception.Message); return }
    if ($info.Loader -eq 'quilt') { Home-Msg (L 'Quilt paketleri henüz desteklenmiyor (NeoForge, Forge, Fabric destekleniyor).'); return }
    $script:Wiz = [pscustomobject]@{ Step = 'isim'; Info = $info; Name = $info.Name; WorldSel = 0; Sync = $null; PS = $null; Handle = $null; Target = $null; StartedAt = $null }
    $script:Screen = 'wizard'
}
function Wizard-WorldOptions {
    $opts = @()
    $i = 1
    foreach ($sv in $Wiz.Info.Saves) {
        $label = (L 'Paketteki kayıtlı dünyayla başla') + $(if ($Wiz.Info.Saves.Count -gt 1) { " ($i)" } else { '' })
        $opts += , @($label, [string]$sv)
        $i++
    }
    $opts += , @((L 'Yepyeni bir dünya oluştur'), '')
    , $opts
}
# Kurulum adımlarının ekranda görünen adları (sırası $InstallScript'teki adımlarla aynı)
function Get-InstallStepNames($info) {
    @((L 'Klasör hazırlanıyor'), (L 'Java {0} kontrol ediliyor' $info.Java), (L '{0} {1} kuruluyor' $LoaderName[$info.Loader] $info.LoaderVer), (L 'Modlar indiriliyor'), (L 'Ayar dosyaları kopyalanıyor'), (L 'Dünya hazırlanıyor'), (L 'Son ayarlar yapılıyor'))
}
function Begin-Install {
    $w = $Wiz
    $w.Target = Safe-FolderName $w.Name
    $worldName = if ($w.Info.Saves.Count) { (Wizard-WorldOptions)[$w.WorldSel][1] } else { '' }
    $sync = [hashtable]::Synchronized(@{ Steps = @(); Pct = 0; Count = ''; Detail = ''; Done = $false; Error = $null; Result = $null; Failed = @() })
    $names = Get-InstallStepNames $w.Info
    $sync.Steps = @($names | ForEach-Object { [hashtable]::Synchronized(@{ N = $_; S = 0 }) })
    $ps = [powershell]::Create()
    [void]$ps.AddScript($InstallScript.ToString()).AddArgument($sync).AddArgument($w.Info).AddArgument($w.Target).AddArgument($worldName).AddArgument($(if ($Cfg.playitKullan) { $Cfg.sesAdresi } else { '' })).AddArgument($MaxPlayers).AddArgument("$($w.Name) | SyHost").AddArgument($JavaFuncs.ToString()).AddArgument(@{
        javaDl = (L 'Java {0} indiriliyor... (Windows izin isteyebilir, Evet de)'); javaFail = (L 'Java {0} kurulamadı.'); javaOk = (L 'Java {0} hazır')
        dl = (L '{0} {1} indiriliyor'); inst = (L '{0} {1} kuruluyor (biraz sürebilir)'); instFail = (L '{0} kurulamadı (kurulum.log dosyasına bak).')
        forgeNoJar = (L 'Forge başlatma dosyası bulunamadı.'); unsupported = (L '{0} henüz desteklenmiyor (NeoForge, Forge ve Fabric destekleniyor).')
        worldCopy = (L 'Paketteki dünya kopyalanıyor'); worldNew = (L 'İlk açılışta yeni bir dünya oluşturulacak')
    })
    $w.Sync = $sync; $w.PS = $ps; $w.Handle = $ps.BeginInvoke(); $w.StartedAt = Get-Date
    $w.Step = 'kurulum'
}
function Check-Install {
    if (-not $Wiz -or $Wiz.Step -ne 'kurulum' -or -not $Wiz.Sync.Done) { return }
    try { $Wiz.PS.EndInvoke($Wiz.Handle) } catch {}
    try { $Wiz.PS.Dispose() } catch {}
    if ($Wiz.Sync.Error) { $Wiz.Step = 'hata'; return }
    $res = $Wiz.Sync.Result
    $id = (Norm $Wiz.Name) -replace '[^a-z0-9]', ''
    if (-not $id) { $id = 'sunucu' }
    $base = $id; $k = 2; while ($Servers | Where-Object { $_.id -eq $id }) { $id = "$base$k"; $k++ }
    $entry = [pscustomobject]@{ id = $id; ad = $Wiz.Name; klasor = $Wiz.Target; mc = $res.mc; loader = $res.loader; loaderSurum = $res.loaderSurum; java = [int]$res.java; baslat = $res.baslat; paket = 'normal'; eklenme = (Get-Date).ToString('yyyy-MM-dd HH:mm'); sonAcilis = $null; sonBaslatmaSn = $null }
    $Servers.Add($entry); Save-Servers
    $script:HomeSel = $Servers.Count - 1
    $Wiz.Step = 'bitti'
}

# ---------- Komutlar (sunucu ekranı) ----------
$BuiltinsTr = @('yardim', 'baslat', 'durdur', 'yeniden', 'paket', 'yedek', 'oyuncular', 'adres', 'kopyala', 'gizle', 'kucuk', 'buyuk', 'ustte', 'detay', 'sade', 'temizle', 'klasor', 'zorla', 'menu', 'cikis')
$BuiltinsEn = @('help', 'start', 'stop', 'restart', 'pack', 'backup', 'players', 'address', 'copy', 'hide', 'mini', 'full', 'pin', 'detail', 'simple', 'clear', 'folder', 'force', 'menu', 'exit')
$Builtins = if ($LangCode -eq 'tr') { $BuiltinsTr } else { $BuiltinsEn }
# Ekranda gösterilen komut adı (Türkçe dışındaki dillerde İngilizce komutlar)
function Cmd([string]$tr) { if ($LangCode -eq 'tr') { return $tr }; $i = [Array]::IndexOf($BuiltinsTr, $tr); if ($i -ge 0) { $BuiltinsEn[$i] } else { $tr } }
$PlayerCmds = @('op', 'deop', 'kick', 'ban', 'pardon', 'tp', 'msg', 'tell', 'gamemode', 'give', 'kill', 'whitelist')

function Run-Command([string]$line) {
    $line = $line.Trim()
    if (-not $line) { return }
    if ($History.Count -eq 0 -or $History[$History.Count - 1] -ne $line) { $History.Add($line) }
    $script:HistIdx = -1
    $parts = $line -split '\s+', 2
    $cmd = Norm $parts[0]
    $arg = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    switch ($cmd) {
        { $_ -in 'yardim', 'help', '?' } { $script:Mode = 'help'; break }
        { $_ -in 'baslat', 'start' } { Start-Server; break }
        { $_ -in 'durdur', 'stop' } { if ($AutoRestartAt) { $script:AutoRestartAt = $null; Add-Log ok (L 'Otomatik yeniden başlatma iptal edildi.') } else { Stop-Server $null }; break }
        { $_ -in 'yeniden', 'restart' } { Add-Log panel (L 'Yeniden başlatılıyor...'); Stop-Server 'restart'; break }
        { $_ -in 'paket', 'pack' } { if ($arg) { Set-Pack $arg } else { $script:Mode = 'paket' }; break }
        { $_ -in 'yedek', 'backup' } { Start-Backup; break }
        { $_ -in 'oyuncular', 'players', 'list' } { if ($S -and $S.Running) { $script:ReplyUntil = (Get-Date).AddSeconds(2); $S.Send('list') } else { Add-Log warn (L 'Sunucu kapalı.') }; break }
        { $_ -in 'adres', 'address' } {
            Add-Log ok (L 'Arkadaşların:  {0}' $FriendAddr)
            Add-Log ok (L 'Sen (bu PC):   localhost')
            if ($Cfg.sesAdresi -and $HasFriendAddr) { Add-Log ok (L 'Sesli sohbet:  {0}  (otomatik)' $Cfg.sesAdresi) }
            break
        }
        { $_ -in 'kopyala', 'copy' } { if ($HasFriendAddr) { Set-Clipboard -Value $FriendAddr; Add-Log ok (L "Adres panoya kopyalandı: {0}  (Discord'a yapıştırabilirsin)" $FriendAddr) } else { Add-Log warn (L 'Henüz arkadaşların için bir dış adres yok.') }; break }
        { $_ -in 'gizle', 'hide' } { Hide-Panel; break }
        { $_ -in 'kucuk', 'mini' } { if ($UiMode -ne 'kucuk') { Set-UiMode 'kucuk' }; break }
        { $_ -in 'buyuk', 'tam', 'full' } { if ($UiMode -ne 'buyuk') { Set-UiMode 'buyuk' }; break }
        { $_ -in 'ustte', 'pin' } {
            $Win.ustte = -not [bool]$Win.ustte
            if ($UiMode -eq 'kucuk') { [SyHost.Native]::SetTopMost([bool]$Win.ustte) }
            Add-Log ok ($(if ($Win.ustte) { (L 'Küçük mod her zaman üstte kalacak.') } else { (L 'Küçük mod artık üstte sabitlenmiyor.') }))
            Save-WinState; break
        }
        { $_ -in 'detay', 'sade', 'detail', 'simple' } { $script:Detail = ($_ -in 'detay', 'detail'); $script:Scroll = 0; Add-Log ok ($(if ($Detail) { (L 'Detaylı konsol: tüm teknik kayıtlar görünüyor. (F5 ile sade görünüme dön)') } else { (L 'Sade konsol: sadece önemli olaylar görünüyor. (F5 ile detaylı görünüm)') })); break }
        { $_ -in 'temizle', 'cls', 'clear' } { $Log.Clear(); $script:Scroll = 0; break }
        { $_ -in 'klasor', 'folder' } { Start-Process explorer.exe $Cur.klasor; break }
        { $_ -in 'zorla', 'force' } {
            if ($S -and $S.Running) { $script:StopRequested = $true; $S.P.Kill(); Add-Log warn (L 'Sunucu zorla kapatıldı (son otomatik kayıttan sonrası kaybolabilir).') }
            else { Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'nogui' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Add-Log warn (L 'Eski sunucu süreci kapatıldı (PID {0}).' $_.ProcessId) } }
            break
        }
        { $_ -in 'menu', 'kapat', 'close' } { Begin-Shutdown 'home'; break }
        { $_ -in 'cikis', 'exit', 'quit' } { Begin-Shutdown 'quit'; break }
        default {
            if ($S -and $S.Running) { Add-Log cmd $line; $script:ReplyUntil = (Get-Date).AddSeconds(2); $S.Send($line.TrimStart('/')) }
            else { Add-Log warn (L "Bilinmeyen komut ya da sunucu kapalı: '{0}'  (F1 yardım)" $line) }
        }
    }
}
function Complete-Input {
    $txt = $script:InputText
    if ($txt -notmatch '\s') {
        $hits = @($Builtins | Where-Object { $_.StartsWith((Norm $txt)) })
        if ($hits.Count -eq 1) { $script:InputText = $hits[0] + ' ' }
        elseif ($hits.Count -gt 1) { Add-Log panel ((L 'Seçenekler: ') + ($hits -join ', ')) }
        return
    }
    $parts0 = ($txt -split '\s+')[0]
    $first = Norm $parts0
    if ($first -in 'paket', 'pack') { $last = ($txt -split '\s+')[-1]; $hh = @($PackKeys | Where-Object { $_.StartsWith((Norm $last)) }); if ($hh.Count -eq 1) { $script:InputText = $parts0 + ' ' + $hh[0] }; return }
    if ($PlayerCmds -contains $first) {
        $last = ($txt -split '\s+')[-1]
        $hh = @($Players | Where-Object { $_.StartsWith($last, [StringComparison]::OrdinalIgnoreCase) })
        if ($hh.Count -eq 1) { $script:InputText = $txt.Substring(0, $txt.Length - $last.Length) + $hh[0] + ' ' }
    }
}

# ---------- Tuşlar ----------
function Handle-Key([ConsoleKeyInfo]$k) {
    $script:Dirty = $true
    $ctrl = ($k.Modifiers -band [ConsoleModifiers]::Control) -ne 0
    switch ($Screen) {
        'splash' { After-Splash; return }
        'outro' { $script:Quit = $true; return }
        'home' { Handle-HomeKey $k $ctrl; return }
        'wizard' { Handle-WizardKey $k $ctrl; return }
        'firstrun' { Handle-FirstRunKey $k $ctrl; return }
        'settings' { Handle-SettingsKey $k $ctrl; return }
        'uninstall' { Handle-UninstallKey $k $ctrl; return }
    }
    # --- sunucu ekranı ---
    if ($Mode -eq 'closing') { return }
    if ($Mode -eq 'kapat') {
        switch ($k.Key) {
            'Enter' { Begin-Shutdown 'home'; return }
            'K' { Begin-Shutdown 'quit'; return }
            'Escape' { $script:Mode = 'log'; return } 'H' { $script:Mode = 'log'; return }
        }
        return
    }
    if ($k.Key -eq 'F10' -or ($ctrl -and $k.Key -eq 'Q')) { if (Allow 'kapat') { $script:Mode = 'kapat' }; return }
    if ($Mode -eq 'paket') {
        switch ($k.Key) {
            'LeftArrow' { $script:PackSel = ($PackSel + 2) % 3; return }
            'RightArrow' { $script:PackSel = ($PackSel + 1) % 3; return }
            'D1' { $script:PackSel = 0; return } 'D2' { $script:PackSel = 1; return } 'D3' { $script:PackSel = 2; return }
            'Enter' { Set-Pack $PackKeys[$PackSel]; $script:Mode = 'log'; return }
            'Escape' { $script:Mode = 'log'; return }
            'F3' { $script:Mode = 'log'; return }
        }
    }
    if ($UiMode -eq 'kucuk' -and $k.Key -in 'F1', 'F3') { Set-UiMode 'buyuk' }
    switch ($k.Key) {
        'F1' { $script:Mode = if ($Mode -eq 'help') { 'log' } else { 'help' }; return }
        'F2' { if (Allow 'F2') { Hide-Panel }; return }
        'F3' { $script:Mode = 'paket'; $script:PackSel = [Array]::IndexOf($PackKeys, $ActivePack); return }
        'F4' { Toggle-UiMode; return }
        'F5' { if (Allow 'F5' 400) { Run-Command $(if ($Detail) { 'simple' } else { 'detail' }) }; return }
        'F6' { if (Allow 'F6') { Run-Command 'pin' }; return }
        'PageUp' { $script:Scroll = [Math]::Min($Log.Count - 1, $Scroll + 10); return }
        'PageDown' { $script:Scroll = [Math]::Max(0, $Scroll - 10); return }
        'End' { $script:Scroll = 0; return }
        'Home' { $script:Scroll = [Math]::Max(0, $Log.Count - 5); return }
        'UpArrow' { if ($History.Count) { if ($HistIdx -lt 0) { $script:HistIdx = $History.Count - 1 } elseif ($HistIdx -gt 0) { $script:HistIdx-- }; $script:InputText = $History[$HistIdx] }; return }
        'DownArrow' { if ($HistIdx -ge 0) { if ($HistIdx -lt $History.Count - 1) { $script:HistIdx++; $script:InputText = $History[$HistIdx] } else { $script:HistIdx = -1; $script:InputText = '' } }; return }
        'Tab' { Complete-Input; return }
        'Enter' { $t = $InputText; $script:InputText = ''; if ($Mode -ne 'log') { $script:Mode = 'log' }; Run-Command $t; return }
        'Escape' { if ($Mode -ne 'log') { $script:Mode = 'log' } else { $script:InputText = '' }; return }
        'Backspace' { if ($InputText.Length) { if ($ctrl) { $script:InputText = ($InputText -replace '\S+\s*$', '') } else { $script:InputText = $InputText.Substring(0, $InputText.Length - 1) } }; return }
    }
    if ($ctrl -and $k.Key -eq 'C') { $script:InputText = ''; return }
    if ($ctrl -and $k.Key -eq 'L') { $Log.Clear(); $script:Scroll = 0; return }
    if ($k.KeyChar -and [int]$k.KeyChar -ge 32) {
        if ($Mode -eq 'help') { $script:Mode = 'log' }
        if ($InputText.Length -lt 240) { $script:InputText += $k.KeyChar }
    }
}

function Handle-HomeKey([ConsoleKeyInfo]$k, [bool]$ctrl) {
    $count = $Servers.Count + 1   # + yeni sunucu
    if ($HomeMode -eq 'sil') {
        switch ($k.Key) {
            'Enter' { $gone = $Servers[$HomeSel]; $Servers.RemoveAt($HomeSel); Save-Servers; $script:HomeSel = [Math]::Max(0, $HomeSel - 1); $script:HomeMode = 'list'; Home-Msg (L '{0} listeden kaldırıldı (dosyaları duruyor: {1})' $gone.ad $gone.klasor) }
            default { $script:HomeMode = 'list' }
        }
        return
    }
    switch ($k.Key) {
        'UpArrow' { $script:HomeSel = ($HomeSel + $count - 1) % $count; return }
        'DownArrow' { $script:HomeSel = ($HomeSel + 1) % $count; return }
        'Enter' {
            if (-not (Allow 'homeEnter' 800)) { return }
            if ($HomeSel -ge $Servers.Count) { Start-Wizard } else { Enter-Server $Servers[$HomeSel] }
            return
        }
        'Delete' { if ($HomeSel -lt $Servers.Count) { $script:HomeMode = 'sil' }; return }
        'F2' { if (Allow 'F2') { Hide-Panel }; return }
        'F9' { Open-Settings; return }
        'F10' { if (Allow 'F10') { Start-Outro }; return }
        'Escape' { return }
    }
    if ($ctrl -and $k.Key -eq 'Q') { Start-Outro; return }
    if ($k.Key -eq 'L' -and -not $ctrl) { if (Allow 'lang' 1500) { Switch-Language }; return }
    if ($k.KeyChar -eq '+' -or $k.KeyChar -eq 'n' -or $k.KeyChar -eq 'N') { $script:HomeSel = $Servers.Count; Start-Wizard }
}

function Handle-WizardKey([ConsoleKeyInfo]$k, [bool]$ctrl) {
    $w = $Wiz
    switch ($w.Step) {
        'isim' {
            switch ($k.Key) {
                'Enter' { if ($w.Name.Trim()) { $w.Name = $w.Name.Trim(); $w.Step = if ($w.Info.Saves.Count) { 'dunya' } else { 'onay' } }; return }
                'Escape' { $script:Screen = 'home'; Reset-Frame; return }
                'Backspace' { if ($w.Name.Length) { $w.Name = $w.Name.Substring(0, $w.Name.Length - 1) }; return }
            }
            if ($k.KeyChar -and [int]$k.KeyChar -ge 32 -and $w.Name.Length -lt 32) { $w.Name += $k.KeyChar }
        }
        'dunya' {
            $n = (Wizard-WorldOptions).Count
            switch ($k.Key) {
                'UpArrow' { $w.WorldSel = ($w.WorldSel + $n - 1) % $n }
                'DownArrow' { $w.WorldSel = ($w.WorldSel + 1) % $n }
                'Enter' { $w.Step = 'onay' }
                'Escape' { $w.Step = 'isim' }
            }
        }
        'onay' {
            switch ($k.Key) {
                'Enter' { Begin-Install }
                'Escape' { $w.Step = if ($w.Info.Saves.Count) { 'dunya' } else { 'isim' } }
            }
        }
        'bitti' {
            switch ($k.Key) {
                'Enter' { $srv = $Servers[$Servers.Count - 1]; $script:Wiz = $null; Enter-Server $srv }
                'Escape' { $script:Wiz = $null; $script:Screen = 'home'; Reset-Frame }
            }
        }
        'hata' { if ($k.Key -in 'Enter', 'Escape') { $script:Wiz = $null; $script:Screen = 'home'; Reset-Frame } }
    }
}

# ---------- Çizim: ortak ----------
function New-Badges {
    @{
        info = @((L 'BİLGİ'), $c.dim, $c.soft); warn = @((L 'UYARI'), $c.yellow, (Rgb 253 230 138)); error = @((L 'HATA'), $c.red, (Rgb 254 202 202))
        panel = @('SYHOST', $c.brass, $c.brass); ok = @('SYHOST', $c.green, (Rgb 187 247 208)); join = @((L 'GİRİŞ'), $c.green, $c.green)
        leave = @((L 'ÇIKIŞ'), $c.orange, $c.orange); chat = @((L 'SOHBET'), $c.cyan, $c.cyan); cmd = @((L 'KOMUT'), $c.violet, $c.violet)
    }
}
$Badge = New-Badges
function Card([string]$title, [string[]]$lines, [int]$w) {
    $bc = $c.dark
    $top = $bc + '╭─ ' + $R + $Bo + $c.brass + $title + $R + ' ' + $bc + ('─' * [Math]::Max(0, $w - (VLen $title) - 5)) + '╮' + $R
    $out = @($top)
    foreach ($l in $lines) { $out += $bc + '│' + $R + ' ' + (PadV $l ($w - 4)) + ' ' + $bc + '│' + $R }
    $out += $bc + '╰' + ('─' * ($w - 2)) + '╯' + $R
    , $out
}
function Fmt-Dur([TimeSpan]$t) { '{0:00}:{1:00}:{2:00}' -f [int][Math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds }
function Fmt-When([string]$when) {
    if (-not $when) { return (L 'hiç açılmadı') }
    try { $d = [datetime]::ParseExact($when, 'yyyy-MM-dd HH:mm', $null) } catch { return $when }
    if ($d.Date -eq (Get-Date).Date) { return (L 'bugün ') + $d.ToString('HH:mm') }
    if ($d.Date -eq (Get-Date).Date.AddDays(-1)) { return (L 'dün ') + $d.ToString('HH:mm') }
    $d.ToString('dd.MM.yyyy')
}
function Rule([string]$label, [int]$W, [string]$extra = '') {
    $n = [Math]::Max(0, $W - (VLen $label) - 4 - (VLen $extra))
    $pos = ((T) * 38) % [Math]::Max(1, $n + 24) - 12
    $sb = New-Object Text.StringBuilder
    for ($i = 0; $i -lt $n; $i++) {
        $k = [Math]::Max(0.0, 1.0 - [Math]::Abs($i - $pos) / 10.0)
        $cr = [int](58 + 197 * $k); $cg = [int](58 - 18 * $k); $cb = [int](64 - 14 * $k)
        [void]$sb.Append("$E[38;2;$cr;$cg;${cb}m─")
    }
    $c.dark + '── ' + $R + $Bo + (Shimmer $label @(239, 55, 66) @(255, 255, 255) 9 3) + $R + ' ' + $sb.ToString() + $R + $extra
}
function Key([string]$key, [string]$what) { $c.brass + $key + $R + $c.dim + " $what  " + $R }

# ---------- Çizim: açılış ----------
$LogoLetters = @('S', 'Y', 'H', 'O', 'S', 'T')
# Tek bir logo satırını renklendir: k = beyazlık (0..1), fade = karartma (0..1)
function Color-LogoLine([string]$line, [int]$r0, [double]$k, [double]$fade = 0) {
    $sb = New-Object Text.StringBuilder
    $now = T
    for ($i = 0; $i -lt $line.Length; $i++) {
        $ch = $line[$i]
        if ($ch -eq ' ') { [void]$sb.Append(' '); continue }
        $wave = ([Math]::Sin(($i / 7.0) - $now * 2.6 + $r0 * 0.35) + 1) / 2
        if ($ch -eq [char]0x2588) { $cr = 175 + 80 * $wave; $cg = 18 + 70 * [Math]::Pow($wave, 3); $cb = 30 + 70 * [Math]::Pow($wave, 3) }
        else { $cr = 70 + 40 * $wave; $cg = 14; $cb = 20 }
        $cr = $cr + (255 - $cr) * $k; $cg = $cg + (255 - $cg) * $k; $cb = $cb + (255 - $cb) * $k
        $cr = [int]($cr + (24 - $cr) * $fade); $cg = [int]($cg + (24 - $cg) * $fade); $cb = [int]($cb + (28 - $cb) * $fade)
        [void]$sb.Append("$E[38;2;$cr;$cg;${cb}m$ch")
    }
    [void]$sb.Append($R); $sb.ToString()
}
function Render-LogoDrop([double]$el) {
    $rows = New-Object System.Collections.Generic.List[string]
    $landAll = 5 * 0.11 + 0.38
    $flash = if ($el -gt $landAll) { [Math]::Max(0.0, 1.0 - ($el - $landAll) / 0.45) } else { 0.0 }
    $shine = if ($el -gt $landAll + 0.25 -and $el -lt $landAll + 1.4) { (($el - $landAll - 0.25) / 1.15) * ($LogoW + 16) - 8 } else { -100 }
    for ($r0 = 0; $r0 -lt 6; $r0++) {
        $line = ''
        $ks = New-Object System.Collections.Generic.List[double]
        for ($L = 0; $L -lt 6; $L++) {
            $glyph = $Font[$LogoLetters[$L]]; $wd = $glyph[0].Length
            $pp = [Math]::Min(1.0, [Math]::Max(0.0, ($el - $L * 0.11) / 0.38))
            $ease = 1 - [Math]::Pow(1 - $pp, 3)
            $off = [int][Math]::Round((1 - $ease) * 7)
            $src = $r0 - $off
            $seg = if ($pp -gt 0 -and $src -ge 0 -and $src -le 5) { $glyph[$src] } else { ' ' * $wd }
            # harf inerken beyaz, indikten sonra kırmızıya döner
            $land = [Math]::Max(0.0, 1.0 - [Math]::Max(0.0, $el - ($L * 0.11 + 0.38)) / 0.3)
            $kk = if ($pp -lt 1) { 0.85 } else { 0.85 * $land }
            for ($q = 0; $q -lt $wd; $q++) { $ks.Add($kk) }
            $line += $seg
        }
        $sb = New-Object Text.StringBuilder
        $now = T
        for ($i = 0; $i -lt $line.Length; $i++) {
            $ch = $line[$i]
            if ($ch -eq ' ') { [void]$sb.Append(' '); continue }
            $wave = ([Math]::Sin(($i / 7.0) - $now * 2.6 + $r0 * 0.35) + 1) / 2
            if ($ch -eq [char]0x2588) { $cr = 175 + 80 * $wave; $cg = 18 + 70 * [Math]::Pow($wave, 3); $cb = 30 + 70 * [Math]::Pow($wave, 3) }
            else { $cr = 70 + 40 * $wave; $cg = 14; $cb = 20 }
            $k = [Math]::Max($ks[$i], $flash * 0.7)
            $d = [Math]::Abs(($i - $r0 * 0.8) - $shine); if ($d -lt 5) { $k = [Math]::Max($k, 1 - $d / 5) }
            $cr = [int]($cr + (255 - $cr) * $k); $cg = [int]($cg + (255 - $cg) * $k); $cb = [int]($cb + (255 - $cb) * $k)
            [void]$sb.Append("$E[38;2;$cr;$cg;${cb}m$ch")
        }
        [void]$sb.Append($R); $rows.Add($sb.ToString())
    }
    , $rows
}

# ---------- Gökyüzü: rastgele kayan yıldızlar (meteorlar) + hafif yanıp sönen yıldızlar ----------
$Meteors = New-Object System.Collections.Generic.List[hashtable]
$MeteorRows = @{}; $MeteorLastT = 0.0; $MeteorNextSpawn = 0.0
$Stars = @{}; $StarsSize = ''; $TwinkleOn = $false

function Update-Sky([int]$W, [int]$H, [double]$perSec, [int]$maxN, [bool]$twinkle, [double]$bright = 1.0) {
    $now = T
    $dt = [Math]::Min(0.15, [Math]::Max(0.0, $now - $script:MeteorLastT)); $script:MeteorLastT = $now
    $script:TwinkleOn = $twinkle
    # arka plandaki yıldızlar (ekran boyutu değişince yeniden dağıt)
    if ($twinkle -and $script:StarsSize -ne "$W,$H") {
        $script:Stars = @{}; $script:StarsSize = "$W,$H"
        $count = [int]($W * $H * 0.010)
        for ($i = 0; $i -lt $count; $i++) { $ry = $Rnd.Next(0, $H); if (-not $Stars.ContainsKey($ry)) { $Stars[$ry] = New-Object System.Collections.Generic.List[object] }; $Stars[$ry].Add(@($Rnd.Next(0, $W), ($Rnd.NextDouble() * 100))) }
    }
    # yeni meteor: rastgele aralıklarla (üstel dağılım)
    if ($perSec -gt 0 -and $now -ge $script:MeteorNextSpawn) {
        if ($Meteors.Count -lt $maxN) {
            $dir = if ($Rnd.NextDouble() -lt 0.7) { -1 } else { 1 }
            $vy = 7 + $Rnd.NextDouble() * 9
            $Meteors.Add(@{
                x = [double]($Rnd.Next([int]($W * 0.1), $W + 10)); y = [double]($Rnd.Next(-2, [int][Math]::Max(1, $H * 0.45)))
                vx = $dir * $vy * (1.8 + $Rnd.NextDouble() * 1.2); vy = $vy; len = $Rnd.Next(5, 12)
                age = 0.0; life = 0.7 + $Rnd.NextDouble() * 1.1
            })
            if ($dir -gt 0) { $Meteors[$Meteors.Count - 1].x = [double]($Rnd.Next(-10, [int]($W * 0.9))) }
        }
        $script:MeteorNextSpawn = $now + (-[Math]::Log(1 - $Rnd.NextDouble() * 0.999)) / $perSec
    }
    # hareket ettir, ömrü bitenleri sil
    for ($i = $Meteors.Count - 1; $i -ge 0; $i--) {
        $m = $Meteors[$i]
        $m.x += $m.vx * $dt; $m.y += $m.vy * $dt; $m.age += $dt
        if ($m.age -gt $m.life -or $m.y -gt $H + $m.len -or $m.x -lt -20 -or $m.x -gt $W + 20) { $Meteors.RemoveAt($i) }
    }
    # hücrelere dök: kafa beyaz, kuyruk kırmızıdan karanlığa
    $rowsMap = @{}
    foreach ($m in $Meteors) {
        $fade = 1.0 - [Math]::Max(0.0, ($m.age - $m.life * 0.6) / ($m.life * 0.4))
        $fade = [Math]::Min($fade, [Math]::Min(1.0, $m.age / 0.12)) * $bright
        $sx = if ($m.vx -lt 0) { 1.0 } else { -1.0 }
        $sy = - [Math]::Abs($m.vy / $m.vx)
        for ($k = $m.len; $k -ge 0; $k--) {
            $col = [int][Math]::Round($m.x + $sx * $k); $row = [int][Math]::Round($m.y + $sy * $k)
            if ($row -lt 0 -or $row -ge $H -or $col -lt 0 -or $col -ge $W) { continue }
            $t = $k / [double]$m.len
            if ($t -lt 0.15) { $cr = 255; $cg = 235; $cb = 230 } elseif ($t -lt 0.5) { $q = ($t - 0.15) / 0.35; $cr = 255 - 20 * $q; $cg = 235 - 190 * $q; $cb = 230 - 175 * $q } else { $q = ($t - 0.5) / 0.5; $cr = 235 - 170 * $q; $cg = 45 - 30 * $q; $cb = 55 - 35 * $q }
            $cr = [int](12 + ($cr - 12) * $fade); $cg = [int](12 + ($cg - 12) * $fade); $cb = [int](12 + ($cb - 12) * $fade)
            $ch = if ($k -eq 0) { '●' } elseif ($t -lt 0.35) { '•' } else { '·' }
            if (-not $rowsMap.ContainsKey($row)) { $rowsMap[$row] = @{} }
            $rowsMap[$row][$col] = "$E[38;2;$cr;$cg;${cb}m$ch"
        }
    }
    $script:MeteorRows = $rowsMap
}

# Bir satırın [x0, x1) aralığındaki gökyüzü parçası
function Sky-Seg([int]$row, [int]$x0, [int]$x1) {
    if ($x1 -le $x0) { return '' }
    $marks = New-Object 'System.Collections.Generic.SortedDictionary[int,string]'
    if ($TwinkleOn -and $Stars.ContainsKey($row)) {
        $now = T
        foreach ($sv in $Stars[$row]) {
            $col = [int]$sv[0]; $seed = [double]$sv[1]
            if ($col -lt $x0 -or $col -ge $x1) { continue }
            $b = ([Math]::Sin($now * (0.8 + ($seed % 7) * 0.25) + $seed) + 1) / 2
            if ($b -gt 0.45) { $v = [int](40 + 70 * ($b - 0.45) / 0.55); $marks[$col] = "$E[38;2;$($v + 20);$([int]($v * 0.35));$([int]($v * 0.4))m·" }
        }
    }
    if ($MeteorRows.ContainsKey($row)) { foreach ($kv in $MeteorRows[$row].GetEnumerator()) { if ($kv.Key -ge $x0 -and $kv.Key -lt $x1) { $marks[$kv.Key] = $kv.Value } } }
    if ($marks.Count -eq 0) { return ' ' * ($x1 - $x0) }
    $sb = New-Object Text.StringBuilder; $pos = $x0
    foreach ($kv in $marks.GetEnumerator()) { if ($kv.Key -gt $pos) { [void]$sb.Append(' ' * ($kv.Key - $pos)) }; [void]$sb.Append($kv.Value); $pos = $kv.Key + 1 }
    if ($pos -lt $x1) { [void]$sb.Append($R).Append(' ' * ($x1 - $pos)) }
    [void]$sb.Append($R); $sb.ToString()
}
function Sky-Row([int]$row, [int]$W, [string]$text, [int]$col) {
    if (-not $text) { return Sky-Seg $row 0 $W }
    $len = VLen $text
    (Sky-Seg $row 0 $col) + $text + $R + (Sky-Seg $row ($col + $len) $W)
}

$SplashLen = 2.6
function Render-Splash([int]$W, [int]$H) {
    $rows = New-Object System.Collections.Generic.List[string]
    $el = (T) - $SplashStart
    $top = [int][Math]::Max(1, ($H - 14) / 2)
    Update-Sky $W $H 2.6 6 $true
    # içerik: satır -> (metin, başlangıç sütunu)
    $items = @{}
    $lc = [int][Math]::Max(0, ($W - $LogoW) / 2)
    $li = 0; foreach ($l in (Render-LogoDrop $el)) { $items[$top + $li] = @($l, $lc); $li++ }
    $tag = (L 'modlu Minecraft sunucu merkezi')
    $typed = $tag.Substring(0, [int][Math]::Min($tag.Length, [Math]::Max(0, ($el - 1.0) * 34)))
    $caret = if ($el -gt 0.9 -and ($typed.Length -lt $tag.Length -or [int]((T) * 3) % 2 -eq 0)) { $c.brass + '▌' } else { ' ' }
    $tc = [int][Math]::Max(0, ($W - $tag.Length) / 2)
    $items[$top + 7] = @(($c.text + $typed + $caret + (' ' * ($tag.Length - $typed.Length))), $tc)
    $pct = [Math]::Min(100, $el / ($SplashLen - 0.2) * 100)
    $items[$top + 9] = @((BarP $pct 30), [int][Math]::Max(0, ($W - 30) / 2))
    $word = if ($pct -lt 100) { (L 'hazırlanıyor') } else { (L 'hazır       ') }
    $items[$top + 10] = @(($c.brass + $(if ($pct -lt 100) { Spin } else { '✓' }) + $R + ' ' + (Shimmer $word @(120, 120, 126) @(255, 255, 255))), [int][Math]::Max(0, ($W - 16) / 2))
    for ($r1 = 0; $r1 -lt $H; $r1++) {
        if ($items.ContainsKey($r1)) { $rows.Add((Sky-Row $r1 $W $items[$r1][0] $items[$r1][1])) }
        else { $rows.Add((Sky-Seg $r1 0 $W)) }
    }
    , $rows
}

# ---------- Kapanış: logo kıvılcımlara dağılır ----------
$OutroStart = 0.0; $OutroLen = 2.0
function Start-Outro {
    if (-not [SyHost.Native]::Visible) { $script:Quit = $true; return }
    $script:Screen = 'outro'; $script:OutroStart = T
    Reset-Frame
}
function Noise([int]$x, [int]$y) { $v = [Math]::Sin($x * 12.9898 + $y * 78.233) * 43758.5453; $v - [Math]::Floor($v) }
function Render-Outro([int]$W, [int]$H) {
    $rows = New-Object System.Collections.Generic.List[string]
    $el = (T) - $OutroStart
    $p = [Math]::Min(1.0, $el / ($OutroLen - 0.35))
    $top = [int][Math]::Max(1, ($H - 12) / 2)
    for ($i = 0; $i -lt $top; $i++) { $rows.Add('') }
    $pad = ' ' * [int][Math]::Max(0, ($W - $LogoW) / 2)
    for ($r0 = 0; $r0 -lt 6; $r0++) {
        $src = $LogoPlain[$r0]; $chars = New-Object char[] $src.Length
        for ($i = 0; $i -lt $src.Length; $i++) {
            $n = Noise $i $r0
            # önce sağdan sola bir dalga, sonra rastgele dağılma
            $thr = $p * 1.25 - (1 - $i / [double]$LogoW) * 0.25
            if ($src[$i] -eq ' ' -or $n -lt $thr) { $chars[$i] = ' ' }
            elseif ($n -lt $thr + 0.08) { $chars[$i] = '·' }
            else { $chars[$i] = $src[$i] }
        }
        $line = New-Object string (, $chars)
        $flash = [Math]::Max(0.0, 1.0 - $el / 0.25) * 0.8
        $rows.Add($pad + (Color-LogoLine $line $r0 $flash ([Math]::Min(1.0, $p * 0.9))))
    }
    $rows.Add('')
    $msg = (L 'görüşürüz')
    $fade = [Math]::Min(1.0, [Math]::Max(0.0, ($el - 0.9) / 0.7))
    $base = [int](240 - 200 * $fade)
    $rows.Add((' ' * [int][Math]::Max(0, ($W - $msg.Length) / 2)) + (Shimmer $msg @($base, $base, $base) @(255, [int](70 + 150 * $fade), [int](80 + 140 * $fade)) 14 3))
    $rows.Add('')
    $rows.Add((' ' * [int][Math]::Max(0, ($W - 22) / 2)) + $c.dark + (L 'sunucular kapalı · ') + $c.copper + '■' + $R)
    , $rows
}

# ---------- Çizim: ana menü ----------
function Render-Home([int]$W, [int]$H) {
    $rows = New-Object System.Collections.Generic.List[string]
    $logo = Render-Logo 1.0 (Logo-Shine)
    $info = @(
        ($Bo + $c.brass + (L 'SUNUCU MERKEZİ') + $R),
        ($c.dim + "v$VersionText  ·  $Edition  ·  sykait" + $R),
        ($c.dark + ('─' * 38) + $R),
        ($c.soft + (L 'Arkadaş adresi  ') + $R + $(if ($HasFriendAddr) { $Bo + $c.cyan + $FriendAddr } else { $c.dim + (L 'henüz yok') }) + $R),
        ($c.soft + (L 'Dış erişim      ') + $R + $(if (PlayitOn) { $c.green + (L '● açık (playit)') } elseif ($HasFriendAddr) { $c.yellow + (L '● bağlanıyor') } else { $c.yellow + (L '● kurulu değil') + $c.dim + (L '  (F9 ayarlar)') }) + $R),
        ($c.soft + (L 'Bilgisayar      ') + $R + $c.text + ((L '{0:0.0} GB boş') -f ($SysFree / 1GB)) + $R + $c.dim + (' / {0:0} GB' -f ($TotalRam / 1GB)) + $R)
    )
    $rows.Add('')
    for ($i = 0; $i -lt 6; $i++) { $rows.Add('    ' + $logo[$i] + $(if ($W -ge $LogoW + 52) { '        ' + $info[$i] } else { '' })) }
    $rows.Add('')
    $rows.Add((Rule (L 'SUNUCULARIN') $W ($c.dim + (L ' {0} sunucu ' $Servers.Count) + $R)))
    $rows.Add('')
    $sel = [Math]::Min($HomeSel, $Servers.Count)
    $pulse = ([Math]::Sin((T) * 4) + 1) / 2
    $hlBg = "$E[48;2;$([int](45 + 35 * $pulse));$([int](14 + 6 * $pulse));$([int](20 + 8 * $pulse))m"
    for ($i = 0; $i -le $Servers.Count; $i++) {
        $isSel = ($i -eq $sel)
        if ($i -lt $Servers.Count) {
            $sv = $Servers[$i]
            if (-not $ModCountCache.ContainsKey($sv.id)) { $ModCountCache[$sv.id] = Get-ModCount $sv.klasor }
            $icon = if ($isSel) { $c.brass + (Spin 6) } else { $c.dark + '⬡' }
            $name = ($sv.ad).PadRight(22).Substring(0, 22)
            $meta = (L '{0} {1} · {2} mod' $LoaderName[$sv.loader] $sv.mc $ModCountCache[$sv.id])
            $line = '  ' + $(if ($isSel) { $c.brass + $Bo + '❯' } else { ' ' }) + $R + ' ' + $icon + $R + ' ' + $(if ($isSel) { $Bo + $c.text } else { $c.soft }) + $name + $R + '  ' + $c.dim + $meta.PadRight(32) + $R + '  ' + $c.dark + (L 'son açılış: ') + $R + $c.soft + (Fmt-When $sv.sonAcilis) + $R
        } else {
            $line = '  ' + $(if ($isSel) { $c.green + $Bo + '❯' } else { ' ' }) + $R + ' ' + $c.green + '+' + $R + ' ' + $(if ($isSel) { $Bo + $c.green } else { $c.soft }) + (L 'Yeni sunucu ekle') + $R + $c.dim + (L '   bir .mrpack dosyası seçip kur') + $R
        }
        if ($isSel) { $vl = VLen $line; $line = $hlBg + $line.Replace($R, $R + $hlBg) + (' ' * [Math]::Max(0, $W - 1 - $vl)) + $R }
        $rows.Add($line)
    }
    $rows.Add('')

    # Seçili sunucu ayrıntısı
    if ($HomeMode -eq 'sil' -and $sel -lt $Servers.Count) {
        $sv = $Servers[$sel]
        foreach ($l in (Card (L 'LİSTEDEN KALDIR') @(
            ($Bo + $c.red + (L '{0} listeden kaldırılsın mı?' $sv.ad) + $R),
            ($c.soft + (L 'Dosyaları silinmez, klasörü yerinde kalır:') + $R),
            ($c.dim + $sv.klasor + $R),
            '',
            ((Pill '200;30;45' '255;255;255' 'Enter') + $c.text + (L ' Evet, kaldır    ') + $R + (Pill '50;50;56' '235;235;235' (L 'herhangi bir tuş')) + $c.text + (L ' Vazgeç') + $R)
        ) ([Math]::Min($W, 90)))) { $rows.Add(' ' + $l) }
    } elseif ($sel -lt $Servers.Count) {
        $sv = $Servers[$sel]
        if (-not $WorldSizeCache.ContainsKey($sv.id)) {
            $wd = Join-Path $sv.klasor 'world'
            $WorldSizeCache[$sv.id] = if (Test-Path $wd) { '{0:0} MB' -f ((Get-ChildItem $wd -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB) } else { (L 'henüz oluşmadı') }
        }
        $pk = if ($PackKeys -contains $sv.paket) { $sv.paket } else { 'normal' }
        foreach ($l in (Card (Up $sv.ad) @(
            ($c.soft + (L 'Sürüm     ') + $R + $c.text + "Minecraft $($sv.mc)  ·  $($LoaderName[$sv.loader]) $($sv.loaderSurum)" + $R),
            ($c.soft + (L 'Paket     ') + $R + $Bo + $PackColor[$pk] + (PackName $pk) + $R + $c.dim + (L '   ·   Java {0}   ·   dünya {1}' $sv.java $WorldSizeCache[$sv.id]) + $R),
            ($c.soft + (L 'Klasör    ') + $R + $c.dim + $sv.klasor + $R),
            ($c.dim + (L 'Enter ile aç: sunucu kendiliğinden başlar.') + $R)
        ) ([Math]::Min($W, 90)))) { $rows.Add(' ' + $l) }
    } else {
        foreach ($l in (Card (L 'YENİ SUNUCU') @(
            ($c.text + (L "Enter'a bas, Modrinth paketini (.mrpack) seç.") + $R),
            ($c.soft + (L 'Java, mod yükleyici, modlar ve ayarlar kendiliğinden kurulur.') + $R),
            ($c.dim + (L 'Desteklenen: NeoForge · Forge · Fabric') + $R),
            ''
        ) ([Math]::Min($W, 90)))) { $rows.Add(' ' + $l) }
    }
    if ($HomeMsg -and (Get-Date) -lt $HomeMsgUntil) { $rows.Add(''); $rows.Add('  ' + $c.yellow + '● ' + $HomeMsg + $R) }

    while ($rows.Count -lt $H - 2) { $rows.Add('') }
    Update-Sky $W $H 0.07 1 $false 0.75
    for ($r1 = 0; $r1 -lt $rows.Count; $r1++) { if ($rows[$r1] -eq '') { $rows[$r1] = Sky-Seg $r1 0 $W } }
    $rows.Add($c.dark + ('─' * $W) + $R)
    $rows.Add(' ' + (Key '↑↓' (L 'seç')) + (Key 'Enter' (L 'aç')) + (Key '+' (L 'yeni sunucu')) + (Key 'Del' (L 'listeden kaldır')) + (Key 'L' ((L 'dil') + ': ' + $Languages[$LangCode])) + (Key 'F9' (L 'ayarlar')) + (Key 'F2' (L 'gizle')) + $c.dark + '│  ' + $R + (Pill '200;30;45' '255;255;255' (L 'F10 ÇIK')))
    , $rows
}

# ---------- Çizim: sihirbaz ----------
function Render-Wizard([int]$W, [int]$H) {
    $rows = New-Object System.Collections.Generic.List[string]
    $wz = $Wiz; $inf = $wz.Info
    $rows.Add('')
    $rows.Add('  ' + $Bo + $c.brass + (L 'YENİ SUNUCU KURULUMU') + $R + $c.dim + "   $($inf.Name) $($inf.Version)" + $R)
    $steps = @('isim', 'dunya', 'onay', 'kurulum')
    $labels = @((L 'İsim'), (L 'Dünya'), (L 'Onay'), (L 'Kurulum'))
    $curIdx = switch ($wz.Step) { 'isim' { 0 } 'dunya' { 1 } 'onay' { 2 } default { 3 } }
    $sb = '  '
    for ($i = 0; $i -lt 4; $i++) {
        if ($i -eq 1 -and -not $inf.Saves.Count) { continue }
        $col = if ($i -lt $curIdx -or $wz.Step -eq 'bitti') { $c.green } elseif ($i -eq $curIdx) { $c.brass + $Bo } else { $c.dark }
        $sb += $col + "$($i + 1) $($labels[$i])" + $R + $c.dark + $(if ($i -lt 3) { '  ›  ' } else { '' }) + $R
    }
    $rows.Add($sb)
    $rows.Add('')
    $rows.Add((Rule (L 'PAKET') $W))
    $rows.Add('  ' + $c.soft + (L 'Minecraft ') + $R + $c.text + $inf.Mc + $R + $c.dark + '  ·  ' + $R + $c.soft + (L 'Yükleyici ') + $R + $c.text + "$($LoaderName[$inf.Loader]) $($inf.LoaderVer)" + $R + $c.dark + '  ·  ' + $R + $c.soft + (L 'Sunucu modu ') + $R + $c.text + $inf.Mods + $R + $c.dim + (L ' (+{0} sadece oyuncuda)' $inf.ClientOnly) + $R + $c.dark + '  ·  ' + $R + $c.soft + 'Java ' + $R + $c.text + $inf.Java + $R)
    $rows.Add('')

    switch ($wz.Step) {
        'isim' {
            $rows.Add((Rule (L 'SUNUCUNUN ADI') $W))
            $rows.Add('')
            $rows.Add('  ' + $c.soft + (L 'Listede görünecek isim:') + $R)
            $rows.Add('  ' + $c.brass + $Bo + '❯ ' + $R + $Bo + $c.text + $wz.Name + $R + $(if ([int]((T) * 2) % 2 -eq 0) { $c.brass + '▌' } else { ' ' }) + $R)
            $rows.Add('')
            $rows.Add('  ' + $c.dim + (L 'Kurulacağı klasör: {0}' (Safe-FolderName $wz.Name)) + $R)
            $rows.Add('')
            $rows.Add('  ' + (Key 'Enter' (L 'devam')) + (Key 'Esc' (L 'iptal')))
        }
        'dunya' {
            $rows.Add((Rule (L 'DÜNYA') $W))
            $rows.Add('')
            $rows.Add('  ' + $c.soft + (L 'Pakette hazır bir dünya var. Nasıl başlayalım?') + $R)
            $rows.Add('')
            $opts = Wizard-WorldOptions
            for ($i = 0; $i -lt $opts.Count; $i++) {
                $isS = ($i -eq $wz.WorldSel)
                $rows.Add('   ' + $(if ($isS) { $c.brass + $Bo + '❯ ' + $c.text } else { '  ' + $c.soft }) + $opts[$i][0] + $R)
            }
            $rows.Add('')
            $rows.Add('  ' + (Key '↑↓' (L 'seç')) + (Key 'Enter' (L 'devam')) + (Key 'Esc' (L 'geri')))
        }
        'onay' {
            $rows.Add((Rule (L 'ÖZET') $W))
            $rows.Add('')
            $worldTxt = if ($inf.Saves.Count) { (Wizard-WorldOptions)[$wz.WorldSel][0] } else { (L 'Yeni dünya') }
            $rows.Add('  ' + $c.soft + (L 'İsim       ') + $R + $Bo + $c.text + $wz.Name + $R)
            $rows.Add('  ' + $c.soft + (L 'Klasör     ') + $R + $c.text + (Safe-FolderName $wz.Name) + $R)
            $rows.Add('  ' + $c.soft + (L 'Dünya      ') + $R + $c.text + $worldTxt + $R)
            $rows.Add('  ' + $c.soft + (L 'İndirilecek') + $R + $c.text + (L ' {0} mod' $inf.Mods) + $(if (-not (Find-Java $inf.Java)) { " + Java $($inf.Java)" } else { '' }) + " + $($LoaderName[$inf.Loader])" + $R)
            $rows.Add('')
            $rows.Add('  ' + $c.dim + (L 'Kurarak Minecraft kullanım sözleşmesini (aka.ms/MinecraftEULA) kabul etmiş olursun.') + $R)
            if (-not (Find-Java $inf.Java)) { $rows.Add('  ' + $c.dim + (L 'Java {0} otomatik olarak SyHost klasörüne indirilecek.' $inf.Java) + $R) }
            $rows.Add('')
            $rows.Add('  ' + (Pill '240;240;240' '18;18;20' 'Enter') + $c.text + (L ' Kur   ') + $R + (Pill '50;50;56' '235;235;235' 'Esc') + $c.text + (L ' Geri') + $R)
        }
        { $_ -in 'kurulum', 'bitti', 'hata' } {
            $sy = $wz.Sync
            $rows.Add((Rule (L 'KURULUM') $W ($c.dim + ' ' + (Fmt-Dur ((Get-Date) - $wz.StartedAt)) + ' ' + $R)))
            $rows.Add('')
            $stIdx = -1
            foreach ($st in $sy.Steps) {
                $stIdx++
                $mark = switch ([int]$st.S) { 2 { $c.green + $Bo + '✓' } 1 { $c.brass + (Spin) } 3 { $c.red + $Bo + 'x' } default { $c.dark + '·' } }
                $txt = if ([int]$st.S -eq 1) { Shimmer $st.N @(229, 231, 235) @(255, 70, 80) } elseif ([int]$st.S -eq 2) { $c.soft + $st.N } elseif ([int]$st.S -eq 3) { $c.red + $st.N } else { $c.dark + $st.N }
                $rows.Add('   ' + $mark + $R + '  ' + $txt + $R)
                if ([int]$st.S -eq 1 -and $stIdx -eq 3) { $rows.Add('      ' + (BarP $sy.Pct 30) + ' ' + $c.brass + $Bo + "%$($sy.Pct)" + $R + $c.dim + "  $($sy.Count)" + $R) }
            }
            $rows.Add('')
            if ($wz.Step -eq 'kurulum') {
                $rows.Add('   ' + $c.dim + $sy.Detail + $R)
                $rows.Add('')
                $rows.Add('   ' + $c.brass + (Pulse) + $R + ' ' + (Shimmer ((Verb) + '…') @(110, 110, 120) @(255, 60, 70)))
            } elseif ($wz.Step -eq 'bitti') {
                $rows.Add('   ' + $Bo + $c.green + (L '{0} hazır!' $wz.Name) + $R)
                if (@($sy.Failed).Count) { $rows.Add('   ' + $c.yellow + (L 'Şu modlar indirilemedi: {0}' ((@($sy.Failed)) -join ', ')) + $R) }
                $rows.Add('')
                $rows.Add('   ' + (Pill '240;240;240' '18;18;20' 'Enter') + $c.text + (L ' Sunucuyu şimdi aç   ') + $R + (Pill '50;50;56' '235;235;235' 'Esc') + $c.text + (L ' Ana menü') + $R)
            } else {
                $rows.Add('   ' + $Bo + $c.red + (L 'Kurulum tamamlanamadı:') + $R)
                foreach ($l in (WordWrap ([string]$sy.Error) ($W - 8))) { $rows.Add('   ' + $c.red + $l + $R) }
                $rows.Add('')
                $rows.Add('   ' + $c.dim + (L 'Yarım kalan klasör: {0}' $wz.Target) + $R)
                $rows.Add('   ' + (Pill '50;50;56' '235;235;235' 'Enter') + $c.text + (L ' Ana menüye dön') + $R)
            }
        }
    }
    while ($rows.Count -lt $H) { $rows.Add('') }
    , $rows
}

# ---------- Çizim: sunucu ekranı ----------
$StageNames = @{ 0 = (L 'Java açılıyor'); 1 = (L 'Java açılıyor'); 2 = (L 'Modlar yükleniyor'); 3 = (L 'Sunucu ayarları yükleniyor'); 4 = (L 'Dünya hazırlanıyor') }
function Get-StartPct {
    if (-not $StartTime) { return 0 }
    $el = ((Get-Date) - $StartTime).TotalSeconds
    $pct = [Math]::Min(95, $el / [Math]::Max(5, $ExpectedStart) * 100)
    $min = switch ([int]$Stage) { 2 { 8 } 3 { 55 } 4 { 75 } default { 0 } }
    [int][Math]::Max($pct, $min)
}
function Get-StatusStrip([switch]$Short) {
    switch ($Status) {
        'KAPALI' {
            if ($AutoRestartAt) {
                $sec = [int][Math]::Max(0, ($AutoRestartAt - (Get-Date)).TotalSeconds)
                return (Pill '200;30;45' '255;255;255' (L '■ KAPALI')) + $c.yellow + $(if ($Short) { (L '  {0} sn sonra açılıyor' $sec) } else { (L '  Sunucu çöktü, {0} sn sonra kendiliğinden yeniden açılacak.' $sec) }) + $R
            }
            if ($Short) { return (Pill '200;30;45' '255;255;255' (L '■ KAPALI')) + $c.soft + (L '  açmak: baslat') + $R }
            return (Pill '200;30;45' '255;255;255' (L '■ SUNUCU KAPALI')) + $c.soft + (L '  Açmak için ') + $R + $Bo + $c.brass + (Cmd 'baslat') + $R + $c.soft + (L " yaz ve Enter'a bas.") + $R
        }
        'BASLIYOR' {
            $pct = Get-StartPct
            if ($Short) { return (Pill '190;28;42' '255;255;255' ((Spin) + (L ' AÇILIYOR'))) + ' ' + (BarP $pct 10) + $c.yellow + " %$pct" + $R }
            $left = [int][Math]::Max(0, $ExpectedStart - ((Get-Date) - $StartTime).TotalSeconds)
            $eta = if ($left -gt 0) { (L '~{0} sn' $left) } else { (L 'birazdan') }
            return (Pill '190;28;42' '255;255;255' ((Spin) + (L ' HAZIRLANIYOR'))) + '  ' + (BarP $pct 16) + ' ' + $c.yellow + $Bo + "%$pct" + $R + '  ' + (Shimmer (L 'Adım {0}/4 · {1}' ([Math]::Max(1, [int]$Stage)) $StageNames[[int]$Stage]) @(229, 231, 235) @(255, 70, 80)) + $c.dim + (L '  ·  {0}  ·  ' $eta) + $R + $c.dark + (Verb) + '…' + $R
        }
        'ACIK' {
            if ($Short) { return (Pill '240;240;240' '18;18;20' (L '● AÇIK')) + $c.green + (L '  girilebilir') + $R }
            return (Pill '240;240;240' '18;18;20' (L '● SUNUCU AÇIK')) + $(if ($HasFriendAddr) { $c.green + (L '  Arkadaşların girebilir: ') + $R + $Bo + $c.cyan + $FriendAddr + $R + $c.dim + (L "   (kopyalamak için: kopyala)") } else { $c.green + (L '  Sen girebilirsin: ') + $R + $Bo + $c.cyan + 'localhost' }) + $R
        }
        'DURUYOR' {
            $ph = switch ([int]$StopPhase) { 2 { (L 'Dünya kaydediliyor') } 3 { (L 'Son işlemler yapılıyor') } default { (L 'Kapatılıyor') } }
            if ($Short) { return (Pill '110;14;24' '255;220;222' ((Spin) + (L ' KAPANIYOR'))) + $c.orange + "  $ph" + $R }
            return (Pill '110;14;24' '255;220;222' ((Spin) + (L ' SUNUCU KAPANIYOR'))) + '  ' + (Shimmer "$ph…" @(220, 45, 55) @(255, 255, 255)) + $c.dim + (L '  lütfen bekle') + $R
        }
    }
}

function Render-Header([int]$W) {
    $rows = New-Object System.Collections.Generic.List[string]
    $look = $StatusLook[$Status]
    $p = $Packs.$ActivePack
    if ($script:ShowLogo) {
        $logo = Render-Logo 1.0 (Logo-Shine)
        $info = @(
            ($Bo + $c.brass + (Up $Cur.ad) + $R),
            ($c.dim + (L '{0} {1}  ·  {2} mod  ·  en fazla {3} oyuncu' $LoaderName[$Cur.loader] $Cur.mc $ModCount $MaxPlayers) + $R),
            ($c.dark + ('─' * 38) + $R),
            ($c.soft + (L 'Adres  ') + $R + $(if ($HasFriendAddr) { $Bo + $c.cyan + $FriendAddr } else { $c.dim + (L 'dış adres yok') }) + $R),
            ($c.soft + (L 'Yerel  ') + $R + $c.dim + (L 'localhost  (bu bilgisayardan giriş)') + $R),
            ($c.dim + (L 'F1 nasıl kullanılır  ·  F3 paket  ·  F2 gizle') + $R)
        )
        $rows.Add('')
    for ($i = 0; $i -lt 6; $i++) { $rows.Add('    ' + $logo[$i] + $(if ($W -ge $LogoW + 52) { '        ' + $info[$i] } else { '' })) }
        $rows.Add('')
    }
    $lw = [int][Math]::Floor($W / 2); $rw = $W - $lw
    $up = if ($StartTime -and $S -and $S.Running) { Fmt-Dur ((Get-Date) - $StartTime) } else { '--:--:--' }
    $plist = if ($Players.Count) { $c.text + ($Players -join ', ') } else { $c.dim + (L 'kimse yok') }
    $dot = if ($Status -in 'BASLIYOR', 'DURUYOR') { Spin } else { '●' }
    $left = @(
        ($look[0] + $Bo + "$dot " + $look[1] + $R + '     ' + $c.dim + (L 'süre ') + $R + $c.text + $up + $R),
        ($c.soft + (L 'Oyuncular ') + $R + $Bo + $c.text + "$($Players.Count)/$MaxPlayers" + $R + '   ' + $plist + $R),
        ($c.soft + (L 'Paket     ') + $R + $Bo + $PackColor[$ActivePack] + (PackName $ActivePack) + $R + '   ' + $c.dim + (L 'öncelik ') + $R + $c.text + $PrioTr[$p.oncelik] + $R + $(if ($RamPending) { '   ' + $c.yellow + (L "! RAM için 'yeniden'") + $R } else { '' }))
    )
    $barW = [Math]::Max(8, $rw - 40)
    $running = $S -and $S.Running
    $ramGb = $RamNow / 1GB
    $ramMax = if ($running) { $LoadedRamMax } else { $p.ramMax }
    $ramTxt = if ($running) { '{0,4:0.0} / {1} GB' -f $ramGb, $ramMax } else { "  - / $ramMax GB" }
    $cpuTxt = if ($running) { '{0,4:0}%' -f $CpuNow } else { '   -' }
    $cores = [Math]::Min($p.cekirdek, $Threads)
    $plTxt = if ($HasFriendAddr -and (PlayitOn)) { $c.green + (L '● açık (playit)') } elseif ($HasFriendAddr) { $c.yellow + (L '● bağlanıyor') } else { $c.yellow + (L '● yok') }
    $right = @(
        ($c.soft + 'RAM  ' + $R + (Bar ($(if ($running) { $ramGb / [Math]::Max(1, $ramMax) } else { 0 })) $barW) + ' ' + $c.text + $ramTxt + $R),
        ($c.soft + 'CPU  ' + $R + (Bar ($(if ($running) { $CpuNow / 100 } else { 0 })) $barW) + ' ' + $c.text + $cpuTxt + $R + $c.dim + (L '  {0}/{1} çekirdek' $cores $Threads) + $R),
        ($c.soft + (L 'Dış erişim ') + $R + $plTxt + $R + '    ' + $c.soft + (L 'Bilgisayar ') + $R + $c.text + ((L '{0:0.0} GB boş') -f ($SysFree / 1GB)) + $R)
    )
    $lc = Card (L 'DURUM') $left $lw
    $rc = Card (L 'KAYNAKLAR') $right $rw
    for ($i = 0; $i -lt $lc.Count; $i++) { $rows.Add($lc[$i] + $rc[$i]) }
    , $rows
}

function Render-Log([int]$W, [int]$H) {
    $rows = New-Object System.Collections.Generic.List[string]
    $pre = 18; $avail = [Math]::Max(10, $W - $pre - 1)
    $idx = $Log.Count - 1; $skip = $Scroll
    while ($idx -ge 0 -and $skip -gt 0) { if ($Detail -or $Log[$idx].V) { $skip-- }; $idx-- }
    while ($idx -ge 0 -and $rows.Count -lt $H) {
        $en = $Log[$idx]
        if (-not $Detail -and -not $en.V) { $idx--; continue }
        $bd = $Badge[$en.K]; if (-not $bd) { $bd = $Badge.info }
        $msg = $en.M; $chunks = New-Object System.Collections.Generic.List[string]
        if ($msg.Length -eq 0) { $chunks.Add('') }
        for ($i = 0; $i -lt $msg.Length; $i += $avail) { $chunks.Add($msg.Substring($i, [Math]::Min($avail, $msg.Length - $i))) }
        for ($j = $chunks.Count - 1; $j -ge 0; $j--) {
            if ($j -eq 0) { $head = $c.dark + $en.T + ' ' + $R + $bd[1] + $Bo + $bd[0].PadRight(6) + $R + $c.dark + ' │ ' + $R }
            else { $head = (' ' * 15) + $c.dark + ' │ ' + $R }
            $rows.Insert(0, $head + $bd[2] + $chunks[$j] + $R)
        }
        $idx--
    }
    while ($rows.Count -gt $H) { $rows.RemoveAt(0) }
    if ($rows.Count -eq 0) { $rows.Add($c.dim + (L '  Henüz önemli bir olay yok. Tüm teknik kayıtları görmek için F5.') + $R) }
    while ($rows.Count -lt $H) { $rows.Insert(0, '') }
    , $rows
}

function Render-Help([int]$W, [int]$H) {
    $k = $c.brass; $d = $c.soft; $hd = $Bo + $c.text
    $items = @(
        ($Bo + $c.brass + (L 'NASIL KULLANILIR?') + $R + $c.dim + (L '   (Esc ile kapat)') + $R),
        '',
        ($hd + (L '1) Sunucu açılırken') + $R),
        ($d + '   ' + (L 'Üstteki şerit SARI iken bekle. YEŞİL/BEYAZ "SUNUCU AÇIK" yazınca hazırdır.') + $R),
        ($hd + (L '2) Arkadaşını oyuna almak') + $R),
        ($d + '   ' + (L "a. {0} yaz, Enter'a bas  →  adres panoya kopyalanır" ($k + (Cmd 'kopyala') + $R + $d)) + $R),
        ($d + '   ' + (L "b. Discord'dan arkadaşına yapıştır (Ctrl+V)") + $R),
        ($d + '   ' + (L 'c. Arkadaşın: Minecraft → Çok Oyunculu → Sunucu Ekle → adresi yapıştırır') + $R),
        ($hd + (L '3) Kapatmak') + $R),
        ($d + '   ' + (L 'F10 → Enter: sunucuyu kapatıp ana menüye döner.  K: her şeyi kapatır.') + $R),
        ($hd + (L '4) Gizlemek / küçültmek') + $R),
        ($d + '   ' + (L 'F2 gizler (sunucu çalışmaya devam eder). Geri getirmek için Ctrl+Alt+G (her yerden).') + $R),
        ($d + '   ' + (L 'F4 ya da Ctrl+Alt+K köşedeki küçük moda geçirir. F6 küçük modu üstte tutar.') + $R),
        ($hd + (L '5) Performans paketi') + $R),
        ($d + '   ' + (L 'F3 bas → ← → ile seç → Enter. Oyun oynarken DÜŞÜK, normalde NORMAL.') + $R),
        ($hd + (L '6) Diğer') + $R),
        ($d + '   ' + (L '{0} dünyayı yedekler (zaten 3 saatte bir kendiliğinden)   F5 tüm teknik kayıtları gösterir' ($k + (Cmd 'yedek') + $R + $d)) + $R),
        ($d + '   ' + (L 'Oyun komutlarını direkt yaz: op isim (yönetici yap)  kick isim  say mesaj  time set day') + $R),
        '',
        ($c.dim + '  ' + (L 'Tüm komutlar: {0}' ($Builtins -join ' ')) + $R)
    )
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($i in $items) { if ($rows.Count -lt $H) { $rows.Add('  ' + $i) } }
    while ($rows.Count -lt $H) { $rows.Add('') }
    , $rows
}

function Render-Packs([int]$W, [int]$H) {
    $rows = New-Object System.Collections.Generic.List[string]
    $cw = [int][Math]::Floor(($W - 6) / 3); $inner = $cw - 4
    $cards = @()
    for ($i = 0; $i -lt 3; $i++) {
        $key = $PackKeys[$i]; $p = $Packs.$key; $sel = ($i -eq $PackSel); $act = ($key -eq $ActivePack)
        if ($sel) { $bc = $c.brass; $tl = '╔'; $tr = '╗'; $bl = '╚'; $br = '╝'; $hz = '═'; $vt = '║' } else { $bc = $c.dark; $tl = '╭'; $tr = '╮'; $bl = '╰'; $br = '╯'; $hz = '─'; $vt = '│' }
        $body = New-Object System.Collections.Generic.List[string]
        $body.Add('')
        $body.Add($Bo + $PackColor[$key] + "$($i + 1)  " + (PackName $key) + $R)
        $body.Add($c.dark + ('─' * [Math]::Min(18, $inner)) + $R)
        $body.Add($c.soft + (L 'RAM       ') + $R + $c.text + "$($p.ramMin)-$($p.ramMax) GB" + $R)
        $body.Add($c.soft + (L 'Çekirdek  ') + $R + $c.text + "$([Math]::Min($p.cekirdek,$Threads)) / $Threads" + $R)
        $body.Add($c.soft + (L 'Öncelik   ') + $R + $c.text + $PrioTr[$p.oncelik] + $R)
        $body.Add('')
        foreach ($l in (WordWrap (PackDesc $key) $inner)) { $body.Add($c.dim + $l + $R) }
        while ($body.Count -lt 11) { $body.Add('') }
        $body.Add($(if ($act) { $c.green + $Bo + (L '● ŞU AN AKTİF') + $R } elseif ($sel) { $c.brass + (L 'Enter ile seç') + $R } else { '' }))
        $card = @($bc + $tl + ($hz * ($cw - 2)) + $tr + $R)
        foreach ($l in $body) { $card += $bc + $vt + $R + ' ' + (PadV $l $inner) + ' ' + $bc + $vt + $R }
        $card += $bc + $bl + ($hz * ($cw - 2)) + $br + $R
        $cards += , $card
    }
    $rows.Add('')
    $rows.Add('  ' + $Bo + $c.brass + (L 'KAYNAK PAKETİ SEÇ') + $R + $c.dim + (L '   Çekirdek ve öncelik anında değişir, RAM yeniden başlatınca.') + $R)
    $rows.Add('')
    for ($ri = 0; $ri -lt $cards[0].Count; $ri++) { $rows.Add('  ' + $cards[0][$ri] + ' ' + $cards[1][$ri] + ' ' + $cards[2][$ri]) }
    $rows.Add('')
    $rows.Add('  ' + (Key '← →' (L 'seç')) + (Key '1 2 3' (L 'hızlı seçim')) + (Key 'Enter' (L 'uygula')) + (Key 'Esc' (L 'vazgeç')))
    while ($rows.Count -gt $H) { $rows.RemoveAt($rows.Count - 1) }
    while ($rows.Count -lt $H) { $rows.Add('') }
    , $rows
}

function Mark([int]$state) { switch ($state) { 2 { $c.green + $Bo + '✓' + $R } 1 { $c.yellow + (Spin) + $R } default { $c.dark + '·' + $R } } }
function Render-Confirm([int]$W, [int]$H) {
    $rows = New-Object System.Collections.Generic.List[string]
    $rows.Add('')
    $rows.Add('  ' + $Bo + $c.red + (L '{0} KAPATILSIN MI?' (Up $Cur.ad)) + $R)
    $rows.Add('')
    if ($Players.Count) { $rows.Add('  ' + $c.yellow + (L 'Dikkat: şu an {0} kişi oyunda ({1})' $Players.Count ($Players -join ', ')) + $R); $rows.Add('') }
    $rows.Add('  ' + $c.soft + (L 'Oyunculara haber verilir, dünya kaydedilir, sunucu kapanır.') + $R)
    $rows.Add('')
    $rows.Add('  ' + (Pill '190;28;42' '255;255;255' 'Enter') + $c.text + (L ' Kapat, ana menüye dön') + $R)
    $rows.Add('  ' + (Pill '200;30;45' '255;255;255' '  K  ') + $c.text + (L " Kapat ve SyHost'u tamamen kapat") + $R)
    $rows.Add('  ' + (Pill '50;50;56' '235;235;235' ' Esc ') + $c.text + (L ' Vazgeç') + $R)
    while ($rows.Count -gt $H) { $rows.RemoveAt($rows.Count - 1) }
    while ($rows.Count -lt $H) { $rows.Add('') }
    , $rows
}
function Render-Closing([int]$W, [int]$H) {
    $running = $S -and $S.Running
    $s1 = if ($ShutdownStopAt) { 1 } else { 2 }
    $s2 = if (-not $running -or $StopPhase -ge 3) { 2 } elseif (-not $ShutdownStopAt) { 1 } else { 0 }
    $s3 = if (-not $running) { 2 } elseif ($StopPhase -ge 3) { 1 } else { 0 }
    $s4 = if ($FinishAt) { 1 } else { 0 }
    $el = if ($ClosingSince) { [int]((Get-Date) - $ClosingSince).TotalSeconds } else { 0 }
    $last = if ($AfterClose -eq 'quit') { (L "SyHost kapanıyor") } else { (L 'Ana menüye dönülüyor') }
    $rows = New-Object System.Collections.Generic.List[string]
    $rows.Add('')
    $rows.Add('  ' + (Shimmer (L 'KAPATILIYOR') @(220, 45, 55) @(255, 255, 255) 10) + $c.dim + "   $el sn" + $R)
    $rows.Add('')
    $rows.Add('  ' + (Mark $s1) + ' ' + $c.text + (L 'Oyunculara haber veriliyor') + $R)
    $rows.Add('  ' + (Mark $s2) + ' ' + $c.text + (L 'Dünya kaydediliyor') + $R)
    $rows.Add('  ' + (Mark $s3) + ' ' + $c.text + (L 'Sunucu kapanıyor') + $R)
    $rows.Add('  ' + (Mark $s4) + ' ' + $c.text + $last + $R)
    $rows.Add('')
    if ($FinishAt) { $rows.Add('  ' + $c.green + $Bo + (L 'Her şey kaydedildi.') + $R) }
    else { $rows.Add('  ' + $c.dim + (L 'Bekle, kendisi bitecek. 60 sn içinde kapanmazsa zorla kapatılır.') + $R) }
    while ($rows.Count -gt $H) { $rows.RemoveAt($rows.Count - 1) }
    while ($rows.Count -lt $H) { $rows.Add('') }
    , $rows
}

$MiniKinds = @('join', 'leave', 'chat', 'panel', 'ok', 'error', 'cmd')
function Render-Mini([int]$W, [int]$H) {
    $rows = New-Object System.Collections.Generic.List[string]
    $running = $S -and $S.Running
    $p = $Packs.$ActivePack
    $up = if ($StartTime -and $running) { Fmt-Dur ((Get-Date) - $StartTime) } else { '--:--:--' }
    $pin = if ($Win.ustte) { $c.brass + '■' } else { $c.dark + '□' }
    $left = Get-StatusStrip -Short
    $right = $c.text + $up + $R + ' ' + $pin + $R
    $rows.Add($left + (' ' * [Math]::Max(1, $W - (VLen $left) - (VLen $right))) + $right)
    $rows.Add($c.dark + ('─' * $W) + $R)
    $plist = if ($Players.Count) { $c.text + ($Players -join ', ') } else { $c.dim + (L 'kimse yok') }
    $rows.Add($Bo + $c.brass + $Cur.ad + $R + $c.dark + '  ·  ' + $R + $c.soft + (L 'Oyuncu ') + $R + $Bo + $c.text + "$($Players.Count)/$MaxPlayers  " + $R + $plist + $R)
    $ramMax = if ($running) { $LoadedRamMax } else { $p.ramMax }
    $barW = [Math]::Max(6, $W - 22)
    $rows.Add($c.soft + 'RAM ' + $R + (Bar ($(if ($running) { ($RamNow / 1GB) / [Math]::Max(1, $ramMax) } else { 0 })) $barW) + $c.text + $(if ($running) { ' {0,4:0.0}/{1} GB' -f ($RamNow / 1GB), $ramMax } else { "   -/$ramMax GB" }) + $R)
    $rows.Add($c.soft + 'CPU ' + $R + (Bar ($(if ($running) { $CpuNow / 100 } else { 0 })) $barW) + $c.text + $(if ($running) { ' {0,4:0}%' -f $CpuNow } else { '    -' }) + $R)
    $plTxt = if ($HasFriendAddr -and (PlayitOn)) { $c.green + '●' } else { $c.yellow + '●' }
    $rows.Add($c.soft + (L 'Paket ') + $R + $Bo + $PackColor[$ActivePack] + (PackName $ActivePack) + $R + $(if ($RamPending) { $c.yellow + ' !' + $R } else { '' }) + $c.dark + '  ·  ' + $R + $c.soft + (L 'dış ') + $R + $plTxt + $R + $(if ($BackupStage) { $c.dark + '  ·  ' + $R + $c.brass + (L 'yedek...') + $R } else { '' }))
    $rows.Add($(if ($HasFriendAddr) { $Bo + $c.cyan + $FriendAddr } else { $c.dim + (L 'yerel: localhost') }) + $R)
    $rows.Add($c.dark + '── ' + $R + $c.dim + (L 'son olaylar ') + $c.dark + ('─' * [Math]::Max(0, $W - 15)) + $R)
    $evH = $H - $rows.Count - 2
    if ($Mode -in 'kapat', 'closing') {
        $ov = if ($Mode -eq 'kapat') { Render-Confirm $W ($evH + 1) } else { Render-Closing $W ($evH + 1) }
        $rows.RemoveAt($rows.Count - 1)
        foreach ($l in $ov) { $rows.Add($l.Substring([Math]::Min(1, $l.Length))) }
        $rows.Add($(if ($Mode -eq 'kapat') { $c.text + (L 'Enter menü · K tamamen kapat · Esc vazgeç') } else { $c.dim + (L 'kapanıyor, bekle...') }) + $R)
        return , $rows
    }
    $ev = New-Object System.Collections.Generic.List[string]
    for ($i = $Log.Count - 1; $i -ge 0 -and $ev.Count -lt $evH; $i--) {
        $en = $Log[$i]
        if ($MiniKinds -notcontains $en.K) { continue }
        $bd = $Badge[$en.K]
        $ev.Insert(0, $c.dark + $en.T.Substring(0, 5) + ' ' + $R + $bd[2] + $en.M + $R)
    }
    if ($ev.Count -eq 0) { $ev.Add($c.dim + (L 'henüz bir şey yok') + $R) }
    while ($ev.Count -lt $evH) { $ev.Add('') }
    foreach ($l in $ev) { $rows.Add($l) }
    $rows.Add((Key 'F4' (L 'büyüt')) + (Key 'F2' (L 'gizle')) + (Key 'F6' (L 'üstte')) + $c.red + $Bo + 'F10' + $R + $c.dim + (L ' kapat') + $R)
    , $rows
}

function Render-Server([int]$W, [int]$H) {
    $all = New-Object System.Collections.Generic.List[string]
    if ($UiMode -eq 'kucuk') {
        foreach ($mr in (Render-Mini ($W - 1) ($H - 1))) { $all.Add(' ' + $mr) }
        return , $all
    }
    $script:ShowLogo = ($H -ge 34 -and $W -ge 70)
    foreach ($hr in (Render-Header $W)) { $all.Add($hr) }
    $all.Add(' ' + (Get-StatusStrip))
    $label = switch ($Mode) { 'help' { (L 'YARDIM') } 'paket' { (L 'PAKETLER') } 'kapat' { (L 'KAPAT') } 'closing' { (L 'KAPATILIYOR') } default { if ($Detail) { (L 'KONSOL · detaylı') } else { (L 'KONSOL · sade (önemli olaylar)') } } }
    $extra = if ($Mode -eq 'log' -and $Scroll -gt 0) { $c.yellow + (L ' ▲ {0} satır yukarıdasın · End ile en alta ' $Scroll) + $R } elseif ($BackupStage) { $c.brass + ' ' + (Spin) + (L ' yedek alınıyor... ') + $R } else { '' }
    $all.Add((Rule $label $W $extra))
    $bodyH = $H - $all.Count - 3
    $body = switch ($Mode) { 'help' { Render-Help $W $bodyH } 'paket' { Render-Packs $W $bodyH } 'kapat' { Render-Confirm $W $bodyH } 'closing' { Render-Closing $W $bodyH } default { Render-Log $W $bodyH } }
    foreach ($br2 in $body) { $all.Add($br2) }
    $all.Add($c.dark + ('─' * $W) + $R)
    $all.Add(' ' + (Key 'F1' (L 'nasıl kullanılır')) + (Key 'F2' (L 'gizle')) + (Key 'F3' (L 'paket')) + (Key 'F4' (L 'küçük')) + (Key 'F5' (L 'detaylı konsol')) + $c.dark + '│  ' + $R + (Pill '200;30;45' '255;255;255' (L 'F10 KAPAT')))
    , $all
}

# ---------- Çizim: kare ----------
# Bir kareyi hazırla: her satır tam $W genişliğinde. Test modunda dosyaya yazılan şey de budur.
# ---------- Yeni ekranlar için ortak yardımcılar (C#: App.FirstRun.cs, App.Settings.cs) ----------
# İlk açılış durumu (C#: FirstRunState). Arka plan işi: Job (çalışırken $null değil), Sync (iş ile paylaşılan tablo:
# Done bitti mi, Text ekranda görünen ilerleme yazısı, Error hata metni).
function New-FirstRunState {
    [pscustomobject]@{
        Steps = New-Object System.Collections.Generic.List[string]; Index = 0; Sel = 0
        ReturnTo = $null      # $null: ilk açılış; 'settings': Ayarlar'dan açılan tek adım
        Target = $null        # kurulum yeri
        OtherInstall = $null  # bilgisayardaki başka bir SyHost
        Note = $null; NoteCol = $null   # adımın altındaki kısa not
        Confirm = $false      # OneDrive uyarısından sonra ikinci Enter bekleniyor
        Job = $null; Sync = [hashtable]::Synchronized(@{ Done = $true; Text = ''; Error = $null })
        Desk = $true; Start = $true
        Phase = ''            # arkadaş adımının alt aşaması: soru, indir, bagla, adres, hazir
        Code = $null          # playit eşleştirme kodu
        Field = 0             # 0: Minecraft adresi, 1: sesli sohbet adresi
        McAddr = ''; VoiceAddr = ''
    }
}
# Test modunda sabitlenebilen bilgiler (C#: FontOk, OsBuild, DefaultRootShown, LegacyDirShown, DryRunShown, ShortcutState)
function FontOk { if ($null -ne $TestFontOk) { return [bool]$TestFontOk }; [bool](Test-FontAvailable) }
function OsBuild { if ($null -ne $TestOsBuild) { return [int]$TestOsBuild }; [Environment]::OSVersion.Version.Build }
function DefaultRootShown { if ($null -ne $TestDefaultRoot) { return [string]$TestDefaultRoot }; Get-DefaultRoot }
function LegacyDirShown { if ($null -ne $TestLegacyDir) { return [string]$TestLegacyDir }; Get-LegacyDir }
function DryRunShown { if ($null -ne $TestDryRun) { return [bool]$TestDryRun }; [bool](Test-DryRun) }
# Kısayol durumu: 0 Masaüstü, 1 Başlat menüsü. Değer: Missing | Ours | Dead | OtherLive | Foreign
function Get-ShortcutState([int]$i) {
    if ($null -ne $TestShortcut) { $k = if ($i -eq 0) { 'desktop' } else { 'start' }; if ($TestShortcut.ContainsKey($k)) { return $TestShortcut[$k] }; return 'Missing' }
    Get-LinkState (Get-ShortcutLocations)[$i] $ExePath
}
# Seçili satır vurgusu (nabız gibi atan koyu kırmızı zemin; C#: SelLine)
function SelLine([string]$line, [int]$W) {
    $pulse = ([Math]::Sin((T) * 4) + 1) / 2
    $hlBg = "$E[48;2;$([int](45 + 35 * $pulse));$([int](14 + 6 * $pulse));$([int](20 + 8 * $pulse))m"
    $vl = VLen $line
    $hlBg + $line.Replace($R, $R + $hlBg) + (' ' * [Math]::Max(0, $W - 1 - $vl)) + $R
}
function VersionLine { $c.dim + 'v' + $VersionText + '  ·  ' + $Edition + '  ·  sykait' + $R }
# Arayüz dilinin kurallarıyla büyük harf (Türkçede i → İ; İngilizce ve Japoncada i → I)
function Up([string]$s) { if ($null -eq $s) { return '' }; $s.ToUpper([Globalization.CultureInfo]::GetCultureInfo($(if ($LangCode -eq 'tr') { 'tr-TR' } else { 'en-US' }))) }
# Kısayolları istenen hâle getir: açıksa yaz (başka bir SyHost'unkini de değiştirir), kapalıysa bizimkini sil
function Apply-Shortcuts([bool]$desk, [bool]$start) {
    foreach ($p in @(@('kisayolMasaustu', $desk), @('kisayolBaslat', $start))) { $Cfg | Add-Member -NotePropertyName $p[0] -NotePropertyValue $p[1] -Force }
    Save-Config
    $desc = L 'SyHost - modlu Minecraft sunucu merkezi'
    $locs = @(Get-ShortcutLocations)
    $want = @($desk, $start)
    for ($i = 0; $i -lt $locs.Count; $i++) {
        try {
            if ($want[$i]) { [void](Write-Shortcut $locs[$i] $ExePath $desc) }
            elseif ((Get-LinkState $locs[$i] $ExePath) -eq 'Ours') { Remove-Item -LiteralPath $locs[$i] -Force }
        } catch {}
    }
}
# Dile bağlı tablolar (açılışta bir kez hesaplananlar): dil değişince ve eski veriler taşınınca yeniden hesaplanır
function Init-Tables {
    $script:FriendAddr = if ($HasFriendAddr) { $Cfg.arkadasAdresi } else { (L 'henüz yok') }
    $script:PrioTr = @{ Normal = (L 'Normal'); AboveNormal = (L 'Normal Üstü'); High = (L 'Yüksek'); BelowNormal = (L 'Düşük'); Idle = (L 'En Düşük') }
    $script:Verbs = @((L 'Dişliler hizalanıyor'), (L 'Çarklar yağlanıyor'), (L 'Pirinç parlatılıyor'), (L 'Redstone ısıtılıyor'), (L "Chunk'lar örülüyor"),
        (L "Creeper'lar sakinleştiriliyor"), (L 'Köylüler pazarlığa hazırlanıyor'), (L 'Elmaslar sayılıyor'), (L 'Su çarkı çevriliyor'),
        (L 'Biyomlar boyanıyor'), (L 'Ender incileri cilalanıyor'), (L 'Mekanik presler ayarlanıyor'), (L 'Trenler raya oturtuluyor'), (L 'Rüzgar değirmeni kuruluyor'))
    $script:StatusLook = @{ KAPALI = @($c.red, (L 'KAPALI')); BASLIYOR = @($c.yellow, (L 'AÇILIYOR')); ACIK = @($c.green, (L 'AÇIK')); DURUYOR = @($c.orange, (L 'KAPANIYOR')) }
    $script:StageNames = @{ 0 = (L 'Java açılıyor'); 1 = (L 'Java açılıyor'); 2 = (L 'Modlar yükleniyor'); 3 = (L 'Sunucu ayarları yükleniyor'); 4 = (L 'Dünya hazırlanıyor') }
    $script:Badge = New-Badges
    $script:Builtins = if ($LangCode -eq 'tr') { $BuiltinsTr } else { $BuiltinsEn }
}
# SyHost'u (yeniden) aç: başlatıcı varsa onu, yoksa (geliştirirken) betiği doğrudan
function Start-SyHost([string]$exe, [switch]$NoSplash) {
    if ($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)) {
        if ($NoSplash) { Start-Process -FilePath $exe -ArgumentList '--no-splash' } else { Start-Process -FilePath $exe }
        return
    }
    $a = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$SrcDir\SyHost.ps1`" -Root `"$AppRoot`"" + $(if ($NoSplash) { ' -NoSplash' } else { '' })
    Start-Process "$env:SystemRoot\System32\conhost.exe" -ArgumentList $a
}

# Yeni ekranlar (her biri kendi dosyasında; C# App.FirstRun.cs + App.PlayitSetup.cs, App.Settings.cs, App.Uninstall.cs)
. (Join-Path $SrcDir 'FirstRun.ps1')
. (Join-Path $SrcDir 'Settings.ps1')
. (Join-Path $SrcDir 'Uninstall.ps1')

function Build-Frame([int]$W, [int]$H) {
    $showCursor = $false; $cursorCol = 1
    switch ($Screen) {
        'splash' { $rows = Render-Splash $W $H }
        'outro' { $rows = Render-Outro $W $H }
        'home' { $rows = Render-Home $W $H }
        'wizard' { $rows = Render-Wizard $W $H }
        'firstrun' { $rows = Render-FirstRun $W $H }
        'settings' { $rows = Render-Settings $W $H }
        'uninstall' { $rows = Render-Uninstall $W $H }
        default {
            $rows = Render-Server $W $H
            $promptCol = if ($S -and $S.Running) { $c.green } else { $c.red }
            $prompt = ' ' + $promptCol + $Bo + '❯' + $R + ' '
            $maxIn = $W - 4
            $shown = if ($InputText.Length -gt $maxIn) { $InputText.Substring($InputText.Length - $maxIn) } else { $InputText }
            if ($Mode -eq 'closing') { $rows.Add('') }
            elseif ($shown.Length -eq 0) { $rows.Add($prompt + $c.dark + (L 'komut yaz... (F1 yardım)') + $R) } else { $rows.Add($prompt + $c.text + $shown + $R) }
            $showCursor = ($Mode -ne 'closing'); $cursorCol = 4 + $shown.Length
        }
    }
    $newFrame = New-Object string[] $H
    for ($i = 0; $i -lt $H; $i++) {
        $line = if ($i -lt $rows.Count) { PadV $rows[$i] $W } else { ' ' * $W }
        $newFrame[$i] = $line
    }
    @{ Frame = $newFrame; ShowCursor = $showCursor; CursorCol = $cursorCol }
}
# Kareyi konsola çiz: yalnızca değişen satırlar yazılır
function Render {
    $W = [Console]::WindowWidth - 1; $H = [Console]::WindowHeight
    try { if ([Console]::BufferHeight -ne $H -or [Console]::BufferWidth -ne ($W + 1)) { [Console]::SetBufferSize($W + 1, $H) } } catch {}
    $fr = Build-Frame $W $H
    $newFrame = $fr.Frame
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("$E[?25l")
    for ($i = 0; $i -lt $H; $i++) {
        $line = $newFrame[$i]
        if ($i -ge $PrevFrame.Count -or $PrevFrame[$i] -ne $line) { [void]$sb.Append("$E[$($i + 1);1H").Append($line) }
    }
    $script:PrevFrame = $newFrame
    if ($fr.ShowCursor) { [void]$sb.Append("$E[$H;$($fr.CursorCol)H$E[?25h") }
    [Console]::Write($sb.ToString())
}
function Animating {
    if ($Screen -in 'splash', 'wizard', 'home', 'outro', 'firstrun', 'settings', 'uninstall') { return $true }
    if ($Screen -eq 'server' -and $UiMode -eq 'buyuk') { return $true }
    if ($Screen -eq 'server' -and ($Status -in 'BASLIYOR', 'DURUYOR' -or $Mode -in 'closing', 'kapat' -or $BackupStage)) { return $true }
    $false
}

# ---------- Test modu: tek bir kareyi dosyaya yaz ----------
# SyHost.ps1 -TestFrame senaryo.json -TestOut kare.txt
# Senaryodaki durumu kurar, saati dondurur, bir kare çizer ve satırları dosyaya yazar.
# C# sürümündeki App.RunFrameTest / ApplyScenario'nun birebir karşılığı (src\SyHost\App\App.cs):
# aynı senaryo iki sürümde de çalıştırılır, iki çıktı bayt bayt aynı olmalıdır (tests\parity).
# Dil ve ayarlar normal açılıştaki gibi ayarlar.json'dan, sunucular sunucular.json'dan gelir.
if ($TestFrame) {
    $TestOutPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TestOut)
    try {
        $TestScn = Get-Content -LiteralPath $TestFrame -Raw -Encoding UTF8 | ConvertFrom-Json
        $TestInv = [Globalization.CultureInfo]::InvariantCulture
        # Alan var ve null değil mi (C#: Has)
        function Test-ScnHas($obj, [string]$name) { $null -ne $obj -and $null -ne $obj.PSObject.Properties[$name] -and $null -ne $obj.PSObject.Properties[$name].Value }
        function ConvertTo-ScnDate($v) { [datetime]::ParseExact([string]$v, 'yyyy-MM-dd HH:mm:ss', $TestInv) }

        # Saat donar: T ve Get-Date hep senaryodaki değeri verir
        $TestT = [double]$TestScn.t
        $TestNow = ConvertTo-ScnDate $TestScn.now
        function T { $script:TestT }
        function Get-Date([string]$Format) { if ($Format) { $script:TestNow.ToString($Format) } else { $script:TestNow } }
        if (Test-ScnHas $TestScn 'version') { $Version = [string]$TestScn.version; $VersionText = $Version }
        if (Test-ScnHas $TestScn 'edition') { $Edition = [string]$TestScn.edition }
        $TestW = [int]$TestScn.w; $TestH = [int]$TestScn.h
        $TestSt = $TestScn.state
        if ($TestSt -is [System.Management.Automation.PSCustomObject]) {
            if (Test-ScnHas $TestSt 'screen') { $Screen = [string]$TestSt.screen }
            if (Test-ScnHas $TestSt 'splashStart') { $SplashStart = [double]$TestSt.splashStart }
            if (Test-ScnHas $TestSt 'outroStart') { $OutroStart = [double]$TestSt.outroStart }
            # Rastgelelik kapalı: glitch ve yeni meteor yok, yalnızca senaryodakiler
            $GlitchNext = 1e9; $GlitchUntil = 0.0
            if (Test-ScnHas $TestSt 'glitch') {
                $TestG = $TestSt.glitch
                $GlitchUntil = [double]$TestG.until
                $GlitchNext = if ($null -ne $TestG.PSObject.Properties['next']) { [double]$TestG.next } else { 1e9 }
                $GlitchRows = @{}
                foreach ($TestP in $TestG.rows.PSObject.Properties) { $GlitchRows[[int]::Parse($TestP.Name, $TestInv)] = [int]$TestP.Value }
            }
            $MeteorNextSpawn = if (Test-ScnHas $TestSt 'meteorNextSpawn') { [double]$TestSt.meteorNextSpawn } else { 1e9 }
            $MeteorLastT = $TestT
            $StarsSize = "$TestW,$TestH"
            $Stars = @{}
            if (Test-ScnHas $TestSt 'stars') {
                foreach ($TestS in $TestSt.stars) {
                    $TestRow = [int]$TestS[0]
                    if (-not $Stars.ContainsKey($TestRow)) { $Stars[$TestRow] = New-Object System.Collections.Generic.List[object] }
                    $Stars[$TestRow].Add(@([int]$TestS[1], [double]$TestS[2]))
                }
            }
            $Meteors = New-Object System.Collections.Generic.List[hashtable]
            if (Test-ScnHas $TestSt 'meteors') {
                foreach ($TestM in $TestSt.meteors) {
                    $Meteors.Add(@{ x = [double]$TestM.x; y = [double]$TestM.y; vx = [double]$TestM.vx; vy = [double]$TestM.vy; len = [int]$TestM.len; age = [double]$TestM.age; life = [double]$TestM.life })
                }
            }

            # Ana menü
            if (Test-ScnHas $TestSt 'homeSel') { $HomeSel = [int]$TestSt.homeSel }
            if (Test-ScnHas $TestSt 'homeMode') { $HomeMode = [string]$TestSt.homeMode }
            if (Test-ScnHas $TestSt 'homeMsg') { $HomeMsg = [string]$TestSt.homeMsg }
            if (Test-ScnHas $TestSt 'homeMsgUntil') { $HomeMsgUntil = ConvertTo-ScnDate $TestSt.homeMsgUntil }
            if (Test-ScnHas $TestSt 'modCounts') { foreach ($TestP in $TestSt.modCounts.PSObject.Properties) { $ModCountCache[$TestP.Name] = [int]$TestP.Value } }
            if (Test-ScnHas $TestSt 'worldSizes') { foreach ($TestP in $TestSt.worldSizes.PSObject.Properties) { $WorldSizeCache[$TestP.Name] = [string]$TestP.Value } }
            if (Test-ScnHas $TestSt 'sysFree') { $SysFree = [double]$TestSt.sysFree }
            if (Test-ScnHas $TestSt 'totalRam') { $TotalRam = [double]$TestSt.totalRam }
            if (Test-ScnHas $TestSt 'threads') { $Threads = [int]$TestSt.threads }
            if (Test-ScnHas $TestSt 'javaFound') {
                $TestJavaFound = [bool]$TestSt.javaFound
                function Find-Java([int]$major) { if ($script:TestJavaFound) { 'java.exe' } else { $null } }
            }
            # playit yok; açık mı kapalı mı senaryo söyler (yoksa kapalı)
            $Pl = [pscustomobject]@{ Running = ((Test-ScnHas $TestSt 'playitOn') -and [bool]$TestSt.playitOn) }

            # Sunucu ekranı
            if (Test-ScnHas $TestSt 'cur') { $Cur = $null; foreach ($TestSv in $Servers) { if ($TestSv.id -ceq [string]$TestSt.cur) { $Cur = $TestSv; break } } }
            if (Test-ScnHas $TestSt 'status') { $Status = [string]$TestSt.status }
            if (Test-ScnHas $TestSt 'mode') { $Mode = [string]$TestSt.mode }
            if (Test-ScnHas $TestSt 'uiMode') { $UiMode = [string]$TestSt.uiMode }
            if (Test-ScnHas $TestSt 'detail') { $Detail = [bool]$TestSt.detail }
            if (Test-ScnHas $TestSt 'scroll') { $Scroll = [int]$TestSt.scroll }
            # Süreç yok: yalnızca "çalışıyor mu" bilgisi
            if (Test-ScnHas $TestSt 'running') { $S = [pscustomobject]@{ Running = [bool]$TestSt.running } }
            if (Test-ScnHas $TestSt 'startTime') { $StartTime = ConvertTo-ScnDate $TestSt.startTime }
            if (Test-ScnHas $TestSt 'players') { foreach ($TestP in $TestSt.players) { [void]$Players.Add([string]$TestP) } }
            if (Test-ScnHas $TestSt 'ramNow') { $RamNow = [double]$TestSt.ramNow }
            if (Test-ScnHas $TestSt 'cpuNow') { $CpuNow = [double]$TestSt.cpuNow }
            if (Test-ScnHas $TestSt 'loadedRamMax') { $LoadedRamMax = [int]$TestSt.loadedRamMax }
            if (Test-ScnHas $TestSt 'ramPending') { $RamPending = [bool]$TestSt.ramPending }
            if (Test-ScnHas $TestSt 'activePack') { $ActivePack = [string]$TestSt.activePack }
            if (Test-ScnHas $TestSt 'packSel') { $PackSel = [int]$TestSt.packSel }
            if (Test-ScnHas $TestSt 'stage') { $Stage = [int]$TestSt.stage }
            if (Test-ScnHas $TestSt 'stopPhase') { $StopPhase = [int]$TestSt.stopPhase }
            if (Test-ScnHas $TestSt 'expectedStart') { $ExpectedStart = [int]$TestSt.expectedStart }
            if (Test-ScnHas $TestSt 'modCount') { $ModCount = [int]$TestSt.modCount }
            if (Test-ScnHas $TestSt 'backupStage') { $BackupStage = [string]$TestSt.backupStage }
            if (Test-ScnHas $TestSt 'autoRestartAt') { $AutoRestartAt = ConvertTo-ScnDate $TestSt.autoRestartAt }
            if (Test-ScnHas $TestSt 'closingSince') { $ClosingSince = ConvertTo-ScnDate $TestSt.closingSince }
            if (Test-ScnHas $TestSt 'shutdownStopAt') { $ShutdownStopAt = ConvertTo-ScnDate $TestSt.shutdownStopAt }
            if (Test-ScnHas $TestSt 'finishAt') { $FinishAt = ConvertTo-ScnDate $TestSt.finishAt }
            if (Test-ScnHas $TestSt 'afterClose') { $AfterClose = [string]$TestSt.afterClose }
            if (Test-ScnHas $TestSt 'inputText') { $InputText = [string]$TestSt.inputText }
            if (Test-ScnHas $TestSt 'winUstte') { $Win.ustte = [bool]$TestSt.winUstte }
            if (Test-ScnHas $TestSt 'log') {
                foreach ($TestE in $TestSt.log) { $Log.Add([pscustomobject]@{ T = [string]$TestE.T; K = [string]$TestE.K; M = [string]$TestE.M; V = [bool]$TestE.V }) }
            }

            # Sihirbaz
            if (Test-ScnHas $TestSt 'wizard') {
                $TestWz = $TestSt.wizard; $TestI = $TestWz.info
                $TestInfo = [pscustomobject]@{
                    Path = [string]$TestI.Path; Name = [string]$TestI.Name; Version = [string]$TestI.Version; Mc = [string]$TestI.Mc; Loader = [string]$TestI.Loader; LoaderVer = [string]$TestI.LoaderVer
                    Java = [int]$TestI.Java; Mods = [int]$TestI.Mods; ClientOnly = [int]$TestI.ClientOnly
                    Saves = @(foreach ($TestX in $TestI.Saves) { [string]$TestX }); SizeMb = [double]$TestI.SizeMb
                }
                $Wiz = [pscustomobject]@{ Step = [string]$TestWz.step; Info = $TestInfo; Name = [string]$TestWz.name; WorldSel = [int]$TestWz.worldSel; Sync = $null; PS = $null; Handle = $null; Target = $null; StartedAt = $null }
                if (Test-ScnHas $TestWz 'target') { $Wiz.Target = [string]$TestWz.target }
                if (Test-ScnHas $TestWz 'startedAt') { $Wiz.StartedAt = ConvertTo-ScnDate $TestWz.startedAt }
                if (Test-ScnHas $TestWz 'sync') {
                    $TestY = $TestWz.sync
                    $TestSync = [hashtable]::Synchronized(@{ Steps = @(); Pct = 0; Count = ''; Detail = ''; Done = $false; Error = $null; Result = $null; Failed = @() })
                    $TestNames = @(Get-InstallStepNames $TestInfo)
                    $TestK = 0
                    $TestSync.Steps = @(foreach ($TestX in $TestY.steps) { [hashtable]::Synchronized(@{ N = $(if ($TestK -lt $TestNames.Count) { $TestNames[$TestK] } else { '' }); S = [int]$TestX }); $TestK++ })
                    if (Test-ScnHas $TestY 'pct') { $TestSync.Pct = [int]$TestY.pct }
                    if (Test-ScnHas $TestY 'count') { $TestSync.Count = [string]$TestY.count }
                    if (Test-ScnHas $TestY 'detail') { $TestSync.Detail = [string]$TestY.detail }
                    if (Test-ScnHas $TestY 'error') { $TestSync.Error = [string]$TestY.error }
                    if (Test-ScnHas $TestY 'failed') { $TestSync.Failed = @(foreach ($TestX in $TestY.failed) { [string]$TestX }) }
                    $Wiz.Sync = $TestSync
                }
            }
        }

        # ---------- Yeni ekranlar (ilk açılış, ayarlar, kaldır): C# App.TestScenario.cs ile aynı alanlar ----------
        if ($TestSt -is [System.Management.Automation.PSCustomObject]) {
            function Get-ScnStr($o, [string]$n) { if ($null -ne $o.PSObject.Properties[$n] -and $o.$n -is [string]) { [string]$o.$n } else { $null } }
            function Get-ScnBool($o, [string]$n, [bool]$def = $false) { if ($null -ne $o.PSObject.Properties[$n] -and $o.$n -is [bool]) { [bool]$o.$n } else { $def } }
            function Get-ScnInt($o, [string]$n, [int]$def = 0) { if ($null -ne $o.PSObject.Properties[$n] -and $null -ne $o.$n -and $o.$n -isnot [string] -and $o.$n -isnot [bool]) { [int]$o.$n } else { $def } }
            function Get-ScnColor([string]$n) { switch ($n) { 'yellow' { $c.yellow } 'red' { $c.red } 'green' { $c.green } 'dim' { $c.dim } 'soft' { $c.soft } 'text' { $c.text } 'brass' { $c.brass } default { $null } } }
            if (Test-ScnHas $TestSt 'appRoot') { $AppRoot = [string]$TestSt.appRoot }
            if (Test-ScnHas $TestSt 'setupMode') { $SetupMode = [bool]$TestSt.setupMode }
            if (Test-ScnHas $TestSt 'defaultRoot') { $TestDefaultRoot = [string]$TestSt.defaultRoot }
            if (Test-ScnHas $TestSt 'legacyDir') { $TestLegacyDir = [string]$TestSt.legacyDir }
            if (Test-ScnHas $TestSt 'osBuild') { $TestOsBuild = [int]$TestSt.osBuild }
            if (Test-ScnHas $TestSt 'dryRun') { $TestDryRun = [bool]$TestSt.dryRun }
            if (Test-ScnHas $TestSt 'fontOk') { $TestFontOk = [bool]$TestSt.fontOk }
            if (Test-ScnHas $TestSt 'javaOwn') { $TestJavaOwn = [bool]$TestSt.javaOwn }
            if (Test-ScnHas $TestSt 'playitReady') { $TestPlayitReady = [bool]$TestSt.playitReady }
            if ((Test-ScnHas $TestSt 'javaFound') -and $TestSt.javaFound -is [System.Management.Automation.PSCustomObject]) {
                $TestJava = @{}
                foreach ($TestP in $TestSt.javaFound.PSObject.Properties) { $TestJava[[int]::Parse($TestP.Name, $TestInv)] = [bool]$TestP.Value }
                function Find-Java([int]$major) { if ($script:TestJava.ContainsKey($major) -and $script:TestJava[$major]) { 'java.exe' } else { $null } }
            }
            if (Test-ScnHas $TestSt 'shortcuts') {
                $TestShortcut = @{}
                foreach ($TestP in $TestSt.shortcuts.PSObject.Properties) {
                    $TestShortcut[$TestP.Name] = switch -CaseSensitive ([string]$TestP.Value) { 'ours' { 'Ours' } 'other' { 'OtherLive' } 'dead' { 'Dead' } 'foreign' { 'Foreign' } default { 'Missing' } }
                }
            }
            if (Test-ScnHas $TestSt 'migrated') { $FrMigrated = [pscustomobject]@{ Servers = (Get-ScnInt $TestSt.migrated 'servers'); Playit = (Get-ScnBool $TestSt.migrated 'playit') } }
            if (Test-ScnHas $TestSt 'movedTo') { $FrMovedTo = [string]$TestSt.movedTo }
            if (Test-ScnHas $TestSt 'firstRun') {
                $TestF = $TestSt.firstRun
                $Fr = New-FirstRunState
                $Fr.Index = Get-ScnInt $TestF 'index'; $Fr.Sel = Get-ScnInt $TestF 'sel'; $Fr.ReturnTo = Get-ScnStr $TestF 'returnTo'
                $Fr.Target = Get-ScnStr $TestF 'target'; $Fr.OtherInstall = Get-ScnStr $TestF 'otherInstall'
                $Fr.Note = Get-ScnStr $TestF 'note'; $Fr.NoteCol = Get-ScnColor (Get-ScnStr $TestF 'noteCol'); $Fr.Confirm = Get-ScnBool $TestF 'confirm'
                $Fr.Sync.Text = $(if ($null -ne (Get-ScnStr $TestF 'jobText')) { Get-ScnStr $TestF 'jobText' } else { '' })
                $Fr.Desk = Get-ScnBool $TestF 'desk' $true; $Fr.Start = Get-ScnBool $TestF 'start' $true
                $Fr.Phase = $(if ($null -ne (Get-ScnStr $TestF 'phase')) { Get-ScnStr $TestF 'phase' } else { '' }); $Fr.Field = Get-ScnInt $TestF 'field'
                $Fr.McAddr = $(if ($null -ne (Get-ScnStr $TestF 'mcAddr')) { Get-ScnStr $TestF 'mcAddr' } else { '' })
                $Fr.VoiceAddr = $(if ($null -ne (Get-ScnStr $TestF 'voiceAddr')) { Get-ScnStr $TestF 'voiceAddr' } else { '' })
                foreach ($TestX in $TestF.steps) { $Fr.Steps.Add([string]$TestX) }
                if (Get-ScnBool $TestF 'busy') { $Fr.Job = 'test'; $Fr.Sync.Done = $false }
            }
            if (Test-ScnHas $TestSt 'settings') {
                $SetSel = Get-ScnInt $TestSt.settings 'sel'; $SetNote = Get-ScnStr $TestSt.settings 'note'; $SetNoteCol = Get-ScnColor (Get-ScnStr $TestSt.settings 'noteCol')
            }
            if (Test-ScnHas $TestSt 'uninstall') {
                $UnItems = New-Object System.Collections.Generic.List[object]
                foreach ($TestX in $TestSt.uninstall.items) {
                    $UnItems.Add([pscustomobject]@{
                        Key = (Get-ScnStr $TestX 'key'); Title = (Get-ScnStr $TestX 'title'); Detail = $(if ($null -ne (Get-ScnStr $TestX 'detail')) { Get-ScnStr $TestX 'detail' } else { '' })
                        On = (Get-ScnBool $TestX 'on'); NeedsAdmin = (Get-ScnBool $TestX 'needsAdmin'); State = (Get-ScnInt $TestX 'state'); Error = (Get-ScnStr $TestX 'error')
                    })
                }
                $UnSel = Get-ScnInt $TestSt.uninstall 'sel'; $UnPhase = $(if ($null -ne (Get-ScnStr $TestSt.uninstall 'phase')) { Get-ScnStr $TestSt.uninstall 'phase' } else { 'liste' })
            }
            # Tuşlar: durum kurulduktan sonra sırayla basılır (C#: TestKey). Tek karakter yazılan harftir;
            # diğerleri ConsoleKey adıdır (önüne Ctrl+, Shift+, Alt+ gelebilir).
            if (Test-ScnHas $TestSt 'keys') {
                function ConvertTo-TestKey([string]$s) {
                    if ($s.Length -eq 1) {
                        $ch = $s[0]; $n = [int]$ch
                        $key = if (($n -ge 97 -and $n -le 122) -or ($n -ge 65 -and $n -le 90)) { [ConsoleKey][int][char]::ToUpperInvariant($ch) }
                               elseif ($n -ge 48 -and $n -le 57) { [ConsoleKey]([int][ConsoleKey]::D0 + $n - 48) }
                               elseif ($ch -eq ' ') { [ConsoleKey]::Spacebar } elseif ($ch -eq '+') { [ConsoleKey]::OemPlus } elseif ($ch -eq '-') { [ConsoleKey]::OemMinus } elseif ($ch -eq '.') { [ConsoleKey]::OemPeriod }
                               else { [ConsoleKey]::NoName }
                        return New-Object ConsoleKeyInfo $ch, $key, ($n -ge 65 -and $n -le 90), $false, $false
                    }
                    $shift = $false; $alt = $false; $ctrl = $false
                    while ($true) {
                        if ($s.StartsWith('Ctrl+', [StringComparison]::Ordinal)) { $ctrl = $true; $s = $s.Substring(5) }
                        elseif ($s.StartsWith('Shift+', [StringComparison]::Ordinal)) { $shift = $true; $s = $s.Substring(6) }
                        elseif ($s.StartsWith('Alt+', [StringComparison]::Ordinal)) { $alt = $true; $s = $s.Substring(4) }
                        else { break }
                    }
                    $k = [ConsoleKey]$s
                    $c0 = switch ($k) { 'Enter' { [char]13 } 'Spacebar' { [char]32 } 'Tab' { [char]9 } 'Escape' { [char]27 } 'Backspace' { [char]8 } default { [char]0 } }
                    $ki = [int]$k
                    if ($ctrl -and $ki -ge 65 -and $ki -le 90) { $c0 = [char]($ki - 64) }
                    elseif ($ki -ge 65 -and $ki -le 90) { $c0 = if ($shift) { [char]$ki } else { [char]($ki + 32) } }
                    New-Object ConsoleKeyInfo $c0, $k, $shift, $alt, $ctrl
                }
                foreach ($TestKs in $TestSt.keys) { Handle-Key (ConvertTo-TestKey ([string]$TestKs)) }
            }
        }

        # Kareyi çiz ve yaz: her satır "\n" ile biter, en sonda imleç satırı; UTF-8 (BOM'suz)
        $TestFr = Build-Frame $TestW $TestH
        $TestSb = New-Object Text.StringBuilder
        foreach ($TestLine in $TestFr.Frame) { [void]$TestSb.Append($TestLine).Append("`n") }
        [void]$TestSb.Append('#cursor ').Append($(if ($TestFr.ShowCursor) { 'on ' } else { 'off ' })).Append([string]$TestFr.CursorCol).Append("`n")
        [IO.File]::WriteAllText($TestOutPath, $TestSb.ToString(), (New-Object Text.UTF8Encoding $false))
    } catch {
        # Gizli pencerede hata görünmez: yanına yaz
        try { [IO.File]::WriteAllText($TestOutPath + '.error.txt', ($_ | Out-String) + $_.ScriptStackTrace, (New-Object Text.UTF8Encoding $false)) } catch {}
        exit 1
    }
    exit 0
}

# ---------- Başlangıç ----------
[SyHost.Native]::PrepareConsole()
[SyHost.Native]::DisableCloseButton()
Set-WindowIcon
[SyHost.CloseGuard]::Install()
[SyHost.Tray]::Start($Title)
[SyHost.Native]::MakeOpaque()
# Eski verileri taşı, taşınmış klasörün kısayollarını düzelt, klasör görünümünü uygula (Portable.ps1)
Invoke-PortableStartup
Init-Tables
# Pencere, taşınan pencere.json'daki konuma da yerleşebilsin (C#: SetUiMode, PortableStartup'tan sonra)
Set-UiMode 'buyuk' -NoSave
$SplashStart = if ($NoSplash) { (T) - $SplashLen - 1 } else { T }
Start-Playit
$SysFree = (New-Object Microsoft.VisualBasic.Devices.ComputerInfo).AvailablePhysicalMemory

try {
    while (-not $Quit) {
        $now = Get-Date

        if ($Screen -eq 'splash' -and ((T) - $SplashStart) -gt $SplashLen) { After-Splash }
        Fr-Poll
        if ($Screen -eq 'outro' -and ((T) - $OutroStart) -gt $OutroLen) { $script:Quit = $true; break }

        # Tepsi menüsü ve kısayollar
        $a = $null
        while ([SyHost.Tray]::Actions.TryDequeue([ref]$a)) {
            switch ($a) {
                'mini' { Toggle-UiMode }
                'quit' {
                    if ($Screen -eq 'server') { Begin-Shutdown 'quit' }
                    elseif ($Screen -eq 'wizard' -and $Wiz -and $Wiz.Step -eq 'kurulum') { [SyHost.Tray]::Balloon((L 'Kurulum sürüyor'), (L 'Kurulum bitince kapatabilirsin.')) }
                    elseif ($Screen -ne 'outro') { Start-Outro }
                }
                'restart' { if ($Screen -eq 'server') { Add-Log panel (L 'Yeniden başlatılıyor...'); Stop-Server 'restart' } }
            }
        }

        # Sunucu çıktısı
        if ($S) { $line = $null; $n = 0; while ($n -lt 400 -and $S.Out.TryDequeue([ref]$line)) { Add-ServerLine $line; $n++ } }

        # Sunucu kapandı mı?
        if ($WasRunning -and -not ($S -and $S.Running)) {
            $line = $null; while ($S.Out.TryDequeue([ref]$line)) { Add-ServerLine $line }
            $code = '?'; try { $code = $S.P.ExitCode } catch {}
            $script:Status = 'KAPALI'; $Players.Clear(); $script:WasRunning = $false; $script:RamNow = 0; $script:CpuNow = 0
            if ($StopRequested) { Add-Log ok (L 'Sunucu durdu, dünya kaydedildi.') }
            else {
                Add-Log error (L 'Sunucu beklenmedik şekilde kapandı (kod {0}).' $code)
                [SyHost.Tray]::Balloon((L '{0} kapandı' $Cur.ad), (L 'Beklenmedik bir kapanma oldu.'))
                $CrashTimes.Add($now)
                while ($CrashTimes.Count -and ($now - $CrashTimes[0]).TotalMinutes -gt 10) { $CrashTimes.RemoveAt(0) }
                if ($CrashTimes.Count -ge 3) {
                    Add-Log error (L 'Sunucu son 10 dakikada {0} kez çöktü, otomatik yeniden başlatma durduruldu. F5 ile ayrıntılara bakabilirsin.' $CrashTimes.Count)
                } elseif ($Cfg.cokerseYenidenBaslat -and $Mode -ne 'closing' -and $Screen -eq 'server') { $script:AutoRestartAt = $now.AddSeconds(10); Add-Log panel (L '10 saniye içinde otomatik yeniden başlatılacak... (iptal: durdur)') }
            }
            $then = $AfterStop; $script:AfterStop = $null; $script:StopRequested = $false
            if ($then -eq 'restart') { Start-Server } elseif ($then -eq 'close') { $script:FinishAt = $now.AddMilliseconds(1200) }
        }
        if ($AutoRestartAt -and $now -ge $AutoRestartAt) { $script:AutoRestartAt = $null; if ($Screen -eq 'server' -and $Mode -ne 'closing') { Start-Server } }

        # Kapatma adımları
        if ($ShutdownStopAt -and $now -ge $ShutdownStopAt) { $script:ShutdownStopAt = $null; Stop-Server 'close' }
        if ($Mode -eq 'closing' -and $StopSentAt -and $S -and $S.Running -and ($now - $StopSentAt).TotalSeconds -gt 60) {
            Add-Log warn (L 'Sunucu 60 sn içinde kapanmadı, zorla kapatılıyor.'); $script:StopRequested = $true; try { $S.P.Kill() } catch {}
        }
        if ($FinishAt -and $now -ge $FinishAt) {
            $script:FinishAt = $null
            if ($AfterClose -eq 'quit') { Start-Outro } else { Go-Home }
        }
        if ($Mode -ne 'closing' -and $Status -eq 'DURUYOR' -and $StopSentAt -and ($now - $StopSentAt).TotalSeconds -gt 120 -and $S -and $S.Running) {
            Add-Log warn (L "Sunucu 2 dakikadır kapanmıyor. Zorla kapatmak için 'zorla' yaz."); $script:StopSentAt = $null
        }

        # Yedek ve kurulum
        Check-Backup
        if ($Screen -eq 'server') {
            $autoH = [double]$Cfg.otomatikYedekSaat
            if ($autoH -gt 0 -and $Status -eq 'ACIK' -and -not $BackupStage -and ($now - $LastBackup).TotalHours -ge $autoH) { Add-Log panel (L 'Otomatik yedek zamanı.'); Start-Backup }
        }
        Check-Install

        # Klavye
        if ([SyHost.Native]::Visible) { while ([Console]::KeyAvailable) { Handle-Key ([Console]::ReadKey($true)) } }

        # İstatistikler
        if (($now - $LastStat).TotalMilliseconds -ge 1000) {
            if ($S -and $S.Running) {
                try {
                    $S.P.Refresh(); $script:RamNow = $S.P.WorkingSet64
                    $cpuMs = $S.P.TotalProcessorTime.TotalMilliseconds
                    if ($LastCpuMs -gt 0) { $script:CpuNow = [Math]::Min(100, ($cpuMs - $LastCpuMs) / ($now - $LastStat).TotalMilliseconds / $Threads * 100) }
                    $script:LastCpuMs = $cpuMs
                } catch {}
            }
            $script:SysFree = (New-Object Microsoft.VisualBasic.Devices.ComputerInfo).AvailablePhysicalMemory
            if (($now - $LastSlow).TotalSeconds -ge 10) {
                $script:LastSlow = $now
                [SyHost.Native]::MakeOpaque()
                if ($Pl) { $pll = $null; while ($Pl.Out.TryDequeue([ref]$pll)) {} }
                if ($Cfg.playitKullan -and -not (PlayitOn)) { Start-Playit }
                $tip = if ($Screen -eq 'server') { (L 'SyHost · {0} · {1} · {2}/{3}' $Cur.ad $StatusLook[$Status][1] $Players.Count $MaxPlayers) } else { (L 'SyHost · ana menü') }
                [SyHost.Tray]::SetText($tip)
            }
            $script:LastStat = $now; $script:Dirty = $true
        }

        # Çiz
        $vis = [SyHost.Native]::Visible
        $size = "$([Console]::WindowWidth)x$([Console]::WindowHeight)"
        if ($size -ne $LastSize) { $script:LastSize = $size; Reset-Frame }
        if ($vis -and -not $WasVisible) { Reset-Frame }
        $script:WasVisible = $vis
        $anim = Animating
        $interval = if ($anim) { 60 } else { 40 }
        if ($vis -and ($Dirty -or $anim) -and ($now - $LastRender).TotalMilliseconds -ge $interval) { Render; $script:Dirty = $false; $script:LastRender = $now }

        Start-Sleep -Milliseconds 20
    }
}
catch {
    $msg = $_ | Out-String
    try { [IO.File]::AppendAllText($ErrorLog, ("[{0}] {1}" -f (Get-Date), $msg) + [Environment]::NewLine, $Utf8NoBom) } catch {}
    [SyHost.Native]::Show()
    [Console]::Write("$E[0m$E[2J$E[H$E[?25h")
    Write-Host (L 'SyHost bir hatayla karşılaştı:') -ForegroundColor Red
    Write-Host $msg
    if ($S -and $S.Running) { Write-Host (L 'Sunucu güvenle durduruluyor...') -ForegroundColor Yellow; $S.Send('stop'); [void]$S.P.WaitForExit(60000) }
    Write-Host (L 'Ayrıntı: {0}' $ErrorLog)
    Read-Host (L 'Kapatmak için Enter')
}
finally {
    Save-WinState
    if ($S -and $S.Running) { $S.Send('stop'); [void]$S.P.WaitForExit(60000) }
    if ($S -and $S.Running) { try { $S.P.Kill() } catch {} }
    Stop-Playit
    [SyHost.Tray]::Close()
    try { $mutex.ReleaseMutex(); $mutex.Dispose() } catch {}
    # Kurulumdan/güncellemeden sonra yeni yerden aç; dil değişince yeniden aç; kaldırdıysa klasörü sil
    if ($LaunchAfterExit) { Start-SyHost $LaunchAfterExit -NoSplash } elseif ($RestartApp) { Start-SyHost $ExePath }
    if ($DeleteRootAfterExit) { Remove-RootAfterExit $AppRoot }
}
[Environment]::Exit(0)
