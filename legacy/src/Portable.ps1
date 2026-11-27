# =====================================================================
#  SyHost - taşınabilir klasör (Terminal sürümü)
#  Her şey SyHost klasörünün içinde durur:
#    SyHost\SyHost.exe       görünen tek dosya (Terminal sürümünde küçük bir başlatıcı)
#    SyHost\Servers\         yeni sunucuların varsayılan yeri
#    SyHost\Data\  (gizli)   ayarlar, sunucu listesi, playit anahtarı, indirilen Java ve playit
#    SyHost\App\   (gizli)   bu uygulama (src, config, fonts, icons, bin\SyHost.Core.dll)
#  Klasör istenen yere taşınabilir; yollar SyHost klasörüne göre hesaplanır.
#  C# karşılığı: src\SyHost\Setup\Portable.cs, Migration.cs, FolderLook.cs, Fonts.cs, Shortcuts.cs,
#  Core\Native.Dialogs.cs (klasör seçici), Native.SetWindowIcon, App.Server.cs (SrvFindPlayit), App.cs (PortableStartup).
#  Windows'a dokunan parçalar SyHost.Setup.cs'te: [SyHost.Portable], [SyHost.ShellLink], [SyHost.FolderLook].
#  Java (bulma ve indirme) SyHost.ps1'deki $JavaFuncs'ta (arka plan işlerinde de yüklenir).
#  Testler için: SYHOST_DEFAULT_ROOT (varsayılan kurulum yeri), SYHOST_LEGACY_DATA (eski veri klasörü),
#  SYHOST_SHORTCUT_DIR (kısayolların yeri), SYHOST_DRYRUN=1 (kaldır hiçbir şey silmez).
# =====================================================================

# PowerShell .NET yöntemlerinin hatasını MethodInvocationException içine sarar; C# sürümünün gösterdiği metin
# (ve catch [System.IO.IOException]) için asıl hatayı çıkar
function Get-InnerException($e) {
    while ($e -is [System.Management.Automation.MethodInvocationException] -and $null -ne $e.InnerException) { $e = $e.InnerException }
    $e
}

# ---------- Klasör ve kurulum (C#: Portable.cs) ----------
# Önerilen kurulum yeri: C:\Users\<ad>\SyHost (OneDrive'a eşitlenmez)
function Get-DefaultRoot {
    # Testler varsayılan yeri bir test klasörüne yönlendirebilir
    if ($env:SYHOST_DEFAULT_ROOT) { return $env:SYHOST_DEFAULT_ROOT }
    [IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'), 'SyHost')
}

# Bu klasörde kurulu bir SyHost var mı (Data klasörü)?
function Test-Installed([string]$root) { try { [IO.Directory]::Exists([IO.Path]::Combine($root, 'Data')) } catch { $false } }

# Windows'un dili: Türkçe ve Japonca dışındakiler için İngilizce
function Get-UiLanguage {
    $two = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
    if ($two -ceq 'tr') { 'tr' } elseif ($two -ceq 'ja') { 'ja' } else { 'en' }
}

# İndirilenler klasörü
function Get-Downloads { [SyHost.Portable]::Downloads() }

# Exe kendi boş klasöründe mi? (yanında yalnızca kendisi var). İndirilenler, Masaüstü, Belgeler, kullanıcı klasörü
# ve sürücü kökleri her zaman "boş değil" sayılır: oraya Data/Servers açılmaz.
function Test-OwnEmptyFolder([string]$dir, [string]$exe) {
    try {
        $full = [IO.Path]::GetFullPath($dir).TrimEnd('\')
        if ([IO.Path]::GetPathRoot($full).TrimEnd('\').Equals($full, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $special = @([Environment]::GetFolderPath('UserProfile'), [Environment]::GetFolderPath('DesktopDirectory'), [Environment]::GetFolderPath('MyDocuments'),
            [Environment]::GetFolderPath('ProgramFiles'), [Environment]::GetFolderPath('ProgramFilesX86'), [Environment]::GetFolderPath('Windows'), (Get-Downloads))
        foreach ($s in $special) { if (-not [string]::IsNullOrEmpty($s) -and $full.Equals($s.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { return $false } }
        foreach ($e in [IO.Directory]::EnumerateFileSystemEntries($full)) {
            $name = [IO.Path]::GetFileName($e)
            if ($e.Equals($exe, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($name.Equals('desktop.ini', [StringComparison]::OrdinalIgnoreCase) -or $name.Equals('Thumbs.db', [StringComparison]::OrdinalIgnoreCase)) { continue }
            return $false
        }
        $true
    } catch { $false }
}

# Yol OneDrive ile eşitlenen bir klasörde mi?
function Test-InOneDrive([string]$path) {
    try {
        $full = [IO.Path]::GetFullPath($path).TrimEnd('\') + '\'
        foreach ($v in 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial') {
            $r = [Environment]::GetEnvironmentVariable($v)
            if (-not [string]::IsNullOrEmpty($r) -and $full.StartsWith($r.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        [regex]::IsMatch($full, '\\OneDrive( - [^\\]+)?\\', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    } catch { $false }
}

# Klasöre yazılabiliyor mu? (Program Files gibi yerlerde hayır.) Klasör yoksa açılır.
function Test-CanWrite([string]$dir) {
    try {
        [void][IO.Directory]::CreateDirectory($dir)
        $f = [IO.Path]::Combine($dir, '.syhost-yazma-denemesi-' + [Guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($f, 'x')
        [IO.File]::Delete($f)
        $true
    } catch { $false }
}

# Bir yol SyHost klasörünün içinde mi? (klasörün kendisi de içinde sayılır)
function Test-Inside([string]$path, [string]$root) { [SyHost.Portable]::IsInside($path, $root) }

# SyHost'u bu klasöre kur ya da güncelle: exe'yi kopyalar, Data ve Servers'ı açar, ilk ayarları yazar.
# Data ve Servers içindeki dosyalara asla dokunmaz. (App klasörünü yeni yerdeki SyHost.exe ilk açılışta kendisi çıkarır.)
# Hata olursa C# sürümündeki hatayı fırlatır (hedefteki SyHost açıksa [System.IO.IOException]).
function Install-SyHostTo([string]$root, [string]$sourceExe, [string]$lang) {
    try {
        [void][IO.Directory]::CreateDirectory($root)
        $dataDir = [IO.Path]::Combine($root, 'Data')
        [void][IO.Directory]::CreateDirectory($dataDir)
        [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($root, 'Servers'))
        $target = [IO.Path]::Combine($root, 'SyHost.exe')
        if (-not [string]::Equals([IO.Path]::GetFullPath($sourceExe), [IO.Path]::GetFullPath($target), [StringComparison]::OrdinalIgnoreCase)) { Copy-SyHostExe $sourceExe $target }
        $cfg = [IO.Path]::Combine($dataDir, 'ayarlar.json')
        if (-not [IO.File]::Exists($cfg)) {
            $s = Read-DefaultSettings
            $s | Add-Member -NotePropertyName dil -NotePropertyValue $lang -Force
            $s | Add-Member -NotePropertyName kurulumTamam -NotePropertyValue $false -Force
            Write-TextFile $cfg ($s | ConvertTo-Json -Depth 6)
        }
        [SyHost.Portable]::HideDir($dataDir)
    } catch { throw (Get-InnerException $_.Exception) }
}

# Exe'yi kopyala: önce geçici dosyaya, sonra yerine (yarım dosya kalmasın).
# Hedef açık olduğu için değiştirilemiyorsa [System.IO.IOException] fırlatır.
function Copy-SyHostExe([string]$src, [string]$dst) {
    $tmp = $dst + '.yeni'
    try {
        [IO.File]::Copy($src, $tmp, $true)
        [SyHost.Portable]::MoveReplace($tmp, $dst)
    } catch {
        $ex = Get-InnerException $_.Exception
        try { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } } catch {}   # yarım kalan kopya ortada kalmasın
        throw $ex
    }
}

# Bir SyHost.exe'nin dosya sürümü ([version]); okunamazsa $null (C#: FrNewerVersion'ın okuduğu FileVersion)
function Get-ExeVersion([string]$exe) {
    try {
        $v = $null
        if ([version]::TryParse([Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion, [ref]$v)) { return $v }
    } catch {}
    $null
}

# Konsol çizilmeden önce gösterilen düz Windows uyarısı (ör. klasöre yazılamıyor)
function Show-Alert([string]$text) { [SyHost.Portable]::Alert($text) }

# Kaldır'ın deneme modu: hiçbir şey silinmez, yalnızca ne yapılacağı yazılır (testler için)
function Test-DryRun { $env:SYHOST_DRYRUN -ceq '1' }

# ---------- Eski verilerin taşınması (C#: Migration.cs) ----------
# 0.5.0 ayarları, sunucu listesini ve playit anahtarını %LOCALAPPDATA%\SyHost'ta tutuyordu. Yeni SyHost ilk
# açılışta bunları bir kez kendi Data klasörüne KOPYALAR.
#  - Eski klasör asla silinmez. İçine yalnızca "veriler şuraya taşındı" notu bırakılır.
#  - Not varken başka bir kopya açılırsa önce sorulur (aynı playit anahtarını iki kopya kullanırsa çakışırlar).
#  - Sunucu klasörlerine dokunulmaz, yolları aynen kalır.
$MigrationNote = 'SyHost-TASINDI.txt'
$MigrationFiles = @('ayarlar.json', 'sunucular.json', 'pencere.json', 'playit.toml', 'playit.log')

# Eski veri klasörü (0.5.0). Test için SYHOST_LEGACY_DATA onu bir kopyaya yönlendirir.
function Get-LegacyDir {
    if ($env:SYHOST_LEGACY_DATA) { return $env:SYHOST_LEGACY_DATA }
    [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'SyHost')
}

# Taşınacak eski veri var mı?
function Test-LegacyData {
    $d = Get-LegacyDir
    [IO.File]::Exists([IO.Path]::Combine($d, 'sunucular.json')) -or [IO.File]::Exists([IO.Path]::Combine($d, 'ayarlar.json'))
}

# Bu Data klasörü henüz boş mu (sunucu listesi yok)?
function Test-DataFresh([string]$data) { -not [IO.File]::Exists([IO.Path]::Combine($data, 'sunucular.json')) }

# Eski veriler daha önce başka bir yere taşınmışsa o yer (not dosyasından), not yoksa $null, yer okunamıyorsa '?'
function Get-MovedTo {
    try {
        $note = [IO.Path]::Combine((Get-LegacyDir), $MigrationNote)
        if (-not [IO.File]::Exists($note)) { return $null }
        foreach ($line in [IO.File]::ReadAllLines($note, [Text.Encoding]::UTF8)) {
            if ($line.StartsWith('path=', [StringComparison]::Ordinal)) {
                $p = $line.Substring(5).Trim()
                if ($p) { return $p }
                break   # "path=" boş: yer bilinmiyor (C# boş metin döner ve açılışta çöker)
            }
        }
    } catch {}
    '?'
}

# Eski verileri Data klasörüne kopyala. $lang: ilk açılışta seçilen dil (ayarlara yazılır).
# Eski klasöre taşındığını anlatan not bırakılır. Sonuç: Servers (sunucu sayısı), Playit (anahtar geldi mi), Copied (dosyalar).
function Copy-LegacyData([string]$data, [string]$root, [string]$lang) {
    $src = Get-LegacyDir
    $copied = New-Object System.Collections.Generic.List[string]
    [void][IO.Directory]::CreateDirectory($data)
    foreach ($f in $MigrationFiles) {
        $from = [IO.Path]::Combine($src, $f)
        if (-not [IO.File]::Exists($from)) { continue }
        [IO.File]::Copy($from, [IO.Path]::Combine($data, $f), $true)
        $copied.Add($f)
    }
    # Ayarlar: eski ayarlar korunur, yalnızca seçilen dil ve kurulum bilgisi eklenir
    $cfg = [IO.Path]::Combine($data, 'ayarlar.json')
    if ([IO.File]::Exists($cfg)) {
        try {
            $s = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($s -isnot [System.Management.Automation.PSCustomObject]) { throw 'ayar dosyası bir nesne değil' }
            if ($lang) { $s | Add-Member -NotePropertyName dil -NotePropertyValue $lang -Force }
            if ($null -eq $s.PSObject.Properties['kurulumTamam'] -or $null -eq $s.kurulumTamam) { $s | Add-Member -NotePropertyName kurulumTamam -NotePropertyValue $false -Force }
            Write-TextFile $cfg ($s | ConvertTo-Json -Depth 6)
        } catch {}
    }
    # Sunucu listesi yoksa boş liste: taşıma bir daha tekrarlanmasın
    $list = [IO.Path]::Combine($data, 'sunucular.json')
    if (-not [IO.File]::Exists($list)) { Write-TextFile $list '[]' }
    $count = 0
    try { $count = Get-ServerCount ([IO.File]::ReadAllText($list, [Text.Encoding]::UTF8)) } catch {}
    $playit = [IO.File]::Exists([IO.Path]::Combine($data, 'playit.toml'))
    Write-MigrationNote $src $root
    [pscustomobject]@{ Servers = $count; Playit = $playit; Copied = $copied.ToArray() }
}

# sunucular.json'daki kayıt sayısı (C#: Json.ParseServers(...).Count; tek sunucu dizi olmadan yazılmış olabilir)
function Get-ServerCount([string]$json) {
    $t = $json.Trim()
    if (-not $t) { return 0 }
    if ($t.StartsWith('{')) { $t = '[' + $t + ']' }
    $d = ConvertFrom-Json $t
    if ($null -eq $d) { return 0 }
    if ($d -is [array]) { return $d.Count }
    1
}

# Eski klasöre üç dilde not: "veriler şuraya kopyalandı". İlk satır (path=) bir sonraki açılışta okunur.
function Write-MigrationNote([string]$legacy, [string]$root) {
    try {
        $when = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm')
        $sb = New-Object Text.StringBuilder
        [void]$sb.Append('path=').Append($root).Append("`r`n")
        [void]$sb.Append('date=').Append($when).Append("`r`n`r`n")
        [void]$sb.Append('Bu klasördeki SyHost verileri şuraya kopyalandı: ').Append($root).Append(' (').Append($when).Append(").`r`n")
        [void]$sb.Append("Yeni SyHost artık oradakileri kullanıyor. Bu klasörü silmek istersen SyHost'un Ayarlar > SyHost'u kaldır bölümünden silebilirsin.`r`n`r`n")
        [void]$sb.Append('The SyHost data in this folder was copied to: ').Append($root).Append(' (').Append($when).Append(").`r`n")
        [void]$sb.Append("The new SyHost uses that copy now. You can remove this folder from SyHost: Settings > Uninstall SyHost.`r`n`r`n")
        [void]$sb.Append('このフォルダーの SyHost データは次の場所にコピーされました: ').Append($root).Append('（').Append($when).Append("）。`r`n")
        [void]$sb.Append("新しい SyHost はそちらを使用しています。このフォルダーは SyHost の「設定」>「SyHost をアンインストール」から削除できます。`r`n")
        [IO.File]::WriteAllText([IO.Path]::Combine($legacy, $MigrationNote), $sb.ToString(), (New-Object Text.UTF8Encoding $true))
    } catch {}
}

# ---------- Klasörlerin Explorer'daki görünümü (C#: FolderLook.cs) ----------
# desktop.ini ile her klasöre kendi simgesi ve seçilen dilde adı verilir. Diskteki ad hiç değişmez ("Servers"),
# yalnızca görünen ad değişir; dil değişince hiçbir yol bozulmaz. Simge yolları görelidir: klasör taşınsa da
# simgeler yerinde kalır. Her açılışta yeniden yazılır. Yalnızca SyHost klasörünün İÇİNE yazılır.
# Simgeler App\icons'tan (başlatıcı oraya çıkarır; repodan çalışırken src\SyHost\Assets\icons) Data\icons'a kopyalanır.

# Belirli bir dildeki karşılık (C#: Lang.In); arka plan işinde L olmadığı için adlar önceden çevrilir
function Get-PortableText([string]$lang, [string]$key) {
    if ($lang -ceq 'tr') { return $key }
    $e = $TextTable[$key]
    if ($null -eq $e) { return $key }
    $t = if ($lang -ceq 'ja') { $e['ja'] } else { $e['en'] }
    if ([string]::IsNullOrEmpty($t)) { return $e['en'] }
    $t
}

# Klasör simgelerinin kaynağı; bulunamazsa $null (o zaman yalnızca görünen adlar yazılır)
function Get-FolderIconSource {
    foreach ($d in [IO.Path]::Combine($AppDir, 'icons'), [IO.Path]::Combine([IO.Path]::GetDirectoryName($AppDir), 'src\SyHost\Assets\icons')) {
        if ([IO.File]::Exists([IO.Path]::Combine($d, 'folder-syhost.ico'))) { return $d }
    }
    $null
}

# SyHost klasörünün ve içindeki sunucu klasörlerinin görünümünü uygula (bitene kadar bekler)
function Set-FolderLook([string]$root, [string]$lang, $serverDirs) {
    if ($TestFrame) { return }   # test modunda gerçek klasörlere dokunulmaz
    [SyHost.FolderLook]::Apply($root, (Get-FolderIconSource), (Get-PortableText $lang 'Sunucular'), (Get-PortableText $lang 'Yedekler'), [string[]]@($serverDirs))
}

# Aynısı arka planda (açılışı ve dil değişimini bekletmesin)
function Start-FolderLook([string]$root, [string]$lang, $serverDirs) {
    if ($TestFrame) { return }   # test modunda gerçek klasörlere dokunulmaz
    [void][SyHost.FolderLook]::ApplyAsync($root, (Get-FolderIconSource), (Get-PortableText $lang 'Sunucular'), (Get-PortableText $lang 'Yedekler'), [string[]]@($serverDirs))
}

# ---------- Cascadia Mono yazı tipi (C#: Fonts.cs) ----------
# Logonun ve animasyonların doğru görünmesi için gerekir. Bilgisayarda yoksa yönetici izni istemeden YALNIZCA bu
# kullanıcıya kurulur (%LOCALAPPDATA%\Microsoft\Windows\Fonts + HKCU). Kaldırırken yalnızca SyHost'un kurduğu
# dosyalar silinir. Dosyalar App\fonts'ta (repoda legacy\fonts). Lisans: SIL Open Font License 1.1 (fonts\OFL.txt).
$FontRegPath = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$FontFiles = @(@('CascadiaMono-Regular.ttf', 'Cascadia Mono Regular (TrueType)'), @('CascadiaMono-Bold.ttf', 'Cascadia Mono Bold (TrueType)'))
function Get-UserFontDir { [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Microsoft\Windows\Fonts') }
function Get-OurFontFile([string]$file) { [IO.Path]::Combine((Get-UserFontDir), 'SyHost-' + $file) }

# Cascadia Mono bu bilgisayarda (sistemde ya da kullanıcıda) kurulu mu?
function Test-FontAvailable {
    foreach ($hive in [Microsoft.Win32.Registry]::LocalMachine, [Microsoft.Win32.Registry]::CurrentUser) {
        try {
            $k = $hive.OpenSubKey($FontRegPath)
            if ($null -eq $k) { continue }
            try {
                foreach ($n in $k.GetValueNames()) {
                    if ($n.StartsWith('Cascadia Mono ', [StringComparison]::OrdinalIgnoreCase) -or $n.Equals('Cascadia Mono', [StringComparison]::OrdinalIgnoreCase)) { return $true }
                }
            } finally { $k.Close() }
        } catch {}
    }
    $false
}

# SyHost'un kendi kurduğu kullanıcı yazı tipi duruyor mu?
function Test-FontBySyHost { [IO.File]::Exists((Get-OurFontFile $FontFiles[0][0])) }

# Yazı tipini yalnızca bu kullanıcıya kur (yönetici izni gerekmez). Kurulduysa $true.
function Install-FontPerUser {
    try {
        [void][IO.Directory]::CreateDirectory((Get-UserFontDir))
        $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($FontRegPath)
        try {
            foreach ($ff in $FontFiles) {
                $src = [IO.Path]::Combine($AppDir, 'fonts', $ff[0])
                if (-not [IO.File]::Exists($src)) { return $false }
                $path = Get-OurFontFile $ff[0]
                if (-not [IO.File]::Exists($path) -or (New-Object IO.FileInfo $path).Length -ne (New-Object IO.FileInfo $src).Length) { [IO.File]::Copy($src, $path, $true) }
                $k.SetValue($ff[1], $path, [Microsoft.Win32.RegistryValueKind]::String)
                [void][SyHost.Portable]::AddFont($path)
            }
        } finally { $k.Close() }
        [SyHost.Portable]::FontsChanged()
        Test-FontAvailable
    } catch { $false }
}

# SyHost'un kurduğu kullanıcı yazı tipini kaldır (başkasının kaydına dokunmaz). Hepsi kalktıysa $true.
function Uninstall-FontPerUser {
    $ok = $true
    $k = $null
    try {
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($FontRegPath, $true)
        foreach ($ff in $FontFiles) {
            $path = Get-OurFontFile $ff[0]
            for ($i = 0; $i -lt 8 -and [SyHost.Portable]::RemoveFont($path); $i++) { }
            try {
                if ($null -ne $k) { $v = $k.GetValue($ff[1]); if ($v -is [string] -and $v.Equals($path, [StringComparison]::OrdinalIgnoreCase)) { $k.DeleteValue($ff[1], $false) } }
            } catch { $ok = $false }
        }
        [SyHost.Portable]::FontsChanged()
        foreach ($ff in $FontFiles) {
            $path = Get-OurFontFile $ff[0]
            for ($i = 0; $i -lt 10 -and [IO.File]::Exists($path); $i++) { try { [IO.File]::Delete($path) } catch { Start-Sleep -Milliseconds 300 } }
            if ([IO.File]::Exists($path)) { $ok = $false }
        }
    } catch { $ok = $false }
    finally { if ($null -ne $k) { $k.Close() } }
    $ok
}

# ---------- Masaüstü ve Başlat menüsü kısayolları (C#: Shortcuts.cs) ----------
# "Bu klasörün kısayolu" = açtığı SyHost.exe bu exe olan kısayol. Gösterdiği SyHost artık yoksa (klasör taşınmış)
# kendiliğinden bu exe'ye çevrilir; hâlâ duran başka bir SyHost'u gösteriyorsa dokunulmaz (kullanıcıya sorulur).
# İki biçim de aynı exe'nin kısayolu sayılır (iki sürüm aynı klasörü kullanabilsin):
#   Terminal sürümü: SyHost.exe'nin kendisi (başlatıcı bir pencere uygulamasıdır), argüman yok
#   C# sürümü:       conhost.exe "<SyHost.exe>" --hosted
# Test için SYHOST_SHORTCUT_DIR kısayolları başka bir klasöre yönlendirir.
$SyHostLinkRx = New-Object Text.RegularExpressions.Regex('"?([^"]*?(?:SyHost[^"\\]*\.exe|SyHost\.ps1))"?', [Text.RegularExpressions.RegexOptions]'IgnoreCase, Compiled')

# Kısayolların duracağı yerler: [0] Masaüstü, [1] Başlat menüsü (Programlar)
function Get-ShortcutLocations {
    if ($env:SYHOST_SHORTCUT_DIR) { return @([IO.Path]::Combine($env:SYHOST_SHORTCUT_DIR, 'Desktop', 'SyHost.lnk'), [IO.Path]::Combine($env:SYHOST_SHORTCUT_DIR, 'Programs', 'SyHost.lnk')) }
    @([IO.Path]::Combine([Environment]::GetFolderPath('DesktopDirectory'), 'SyHost.lnk'), [IO.Path]::Combine([Environment]::GetFolderPath('Programs'), 'SyHost.lnk'))
}

# Kısayolun içi: Target, Args, WorkDir, Icon. Yoksa ya da okunamazsa $null.
function Read-Shortcut([string]$lnk) {
    $r = $null
    try { $r = [SyHost.ShellLink]::Read($lnk) } catch {}
    if ($null -eq $r) { return $null }
    [pscustomobject]@{ Target = $r[0]; Args = $r[1]; WorkDir = $r[2]; Icon = $r[3] }
}

# Kısayolun açtığı SyHost'un yolu (exe ya da eski sürümün SyHost.ps1'i). SyHost kısayolu değilse $null.
function Get-LinkSyHostPath($info) {
    foreach ($s in @([string]$info.Args, [string]$info.Target)) {
        $m = $SyHostLinkRx.Match($s)
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    }
    $null
}

# Okunmuş bir kısayolun bu exe'ye göre durumu
function Get-LinkStateOf($info, [string]$lnk, [string]$exe) {
    if ($null -eq $info) { if ([IO.File]::Exists($lnk)) { return 'Foreign' }; return 'Missing' }
    $p = Get-LinkSyHostPath $info
    if ($null -eq $p) { return 'Foreign' }
    try { if ([string]::Equals([IO.Path]::GetFullPath($p), [IO.Path]::GetFullPath($exe), [StringComparison]::OrdinalIgnoreCase)) { return 'Ours' } } catch {}
    if ([IO.File]::Exists($p)) { return 'OtherLive' }
    'Dead'
}

# Bir kısayolun bu exe'ye göre durumu: Missing | Ours | Dead | OtherLive | Foreign
function Get-LinkState([string]$lnk, [string]$exe) { Get-LinkStateOf (Read-Shortcut $lnk) $lnk $exe }

# Kısayol Terminal biçiminde mi? (hedefi bu exe, argüman yok)
function Test-TerminalLink($info, [string]$exe) {
    if ($null -eq $info -or -not [string]::IsNullOrWhiteSpace($info.Args)) { return $false }
    try { [string]::Equals([IO.Path]::GetFullPath($info.Target), [IO.Path]::GetFullPath($exe), [StringComparison]::OrdinalIgnoreCase) } catch { $false }
}

# Kısayolu oluştur ya da üzerine yaz: SyHost.exe'yi doğrudan açar, çalışma klasörü SyHost klasörü, simgesi exe'den.
# Çıktısı yoktur; kaydedilemezse hata fırlatır.
function Write-Shortcut([string]$lnk, [string]$exe, [string]$desc) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($lnk))
    if (-not [SyHost.ShellLink]::Write($lnk, $exe, '', [IO.Path]::GetDirectoryName($exe), $desc, $exe, 0)) { throw "Kısayol kaydedilemedi: $lnk" }
}

# Taşınmış klasör: gösterdiği SyHost artık olmayan kısayolları bu exe'ye çevir. Değişen kısayol sayısını döner.
function Repair-MovedShortcuts([string]$exe, [string]$desc) {
    $n = 0
    foreach ($lnk in Get-ShortcutLocations) {
        try { if ((Get-LinkState $lnk $exe) -ceq 'Dead') { Write-Shortcut $lnk $exe $desc; $n++ } } catch {}
    }
    $n
}

# Hâlâ duran başka bir SyHost (exe) kurulumunun klasörü; yoksa $null
function Find-OtherInstall([string]$exe) {
    foreach ($lnk in Get-ShortcutLocations) {
        try {
            $i = Read-Shortcut $lnk
            if ($null -eq $i) { continue }
            $p = Get-LinkSyHostPath $i
            if ($null -eq $p -or -not $p.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($p)) { continue }
            if ([string]::Equals([IO.Path]::GetFullPath($p), [IO.Path]::GetFullPath($exe), [StringComparison]::OrdinalIgnoreCase)) { continue }
            $r = [IO.Path]::GetDirectoryName($p)
            if ([IO.Directory]::Exists([IO.Path]::Combine($r, 'Data'))) { return $r }
        } catch {}
    }
    $null
}

# Yalnızca bu exe'yi gösteren kısayolları sil
function Remove-OurShortcuts([string]$exe) {
    foreach ($lnk in Get-ShortcutLocations) {
        try { if ((Get-LinkState $lnk $exe) -ceq 'Ours') { [IO.File]::Delete($lnk) } } catch {}
    }
}

# ---------- playit ajanı (C#: App.Server.cs SrvFindPlayit) ----------
# Önce SyHost'un kendi indirdiği taşınabilir kopya (Data\tools\playit), yoksa bilgisayara kurulu olan.
# playit.exe de kabul edilir (playitd o adla kaydedildiyse); ama gerçek playit komut satırı aracı
# tünel çalıştıramaz (--secret-path almaz), onu atla.
function Find-PlayitDaemon {
    foreach ($exe in [IO.Path]::Combine($PlayitToolDir, 'playitd.exe'), [IO.Path]::Combine($PlayitToolDir, 'playit.exe'), [IO.Path]::Combine($PlayitLegacyBin, 'playitd.exe')) {
        if ([IO.File]::Exists($exe) -and -not (Test-PlayitCli $exe)) { return $exe }
    }
    $null
}
function Test-PlayitCli([string]$exe) {
    try { [string]::Equals([Diagnostics.FileVersionInfo]::GetVersionInfo($exe).ProductName, 'playit-cli', [StringComparison]::OrdinalIgnoreCase) } catch { $false }
}

# ---------- Pencereler (C#: Native.PickFolder, Native.SetWindowIcon) ----------
# Klasör seçme penceresi (konsolun önünde açılır). initialDir yoksa var olan en yakın üst klasörden başlar.
# Seçilen klasörün tam yolu; vazgeçilirse $null.
function Pick-Folder([string]$title, [string]$initialDir) {
    if ($TestFrame) { return $null }   # test modunda pencere açılmaz
    $r = $null
    try { $r = [SyHost.Portable]::PickFolder($title, $initialDir) } catch {}
    if ([string]::IsNullOrEmpty($r)) { return $null }
    $r
}

# Konsol penceresine ve görev çubuğuna SyHost simgesini koy (SyHost.exe'den; repodan çalışırken SyHost.ico'dan)
function Set-WindowIcon {
    $src = $null
    if ($ExePath -and [IO.File]::Exists($ExePath)) { $src = $ExePath }
    else {
        foreach ($ico in [IO.Path]::Combine($AppDir, 'icons\SyHost.ico'), [IO.Path]::Combine([IO.Path]::GetDirectoryName($AppDir), 'src\SyHost\Assets\SyHost.ico')) {
            if ([IO.File]::Exists($ico)) { $src = $ico; break }
        }
    }
    if ($src) { [SyHost.Portable]::SetWindowIcon($src) }
}

# ---------- Açılış (C#: App.PortableStartup) ----------
# Eski verileri taşı, taşınmış klasörün kısayollarını düzelt, klasör görünümünü uygula, açılış animasyonundan
# sonra gidilecek ekranı seç.
function Invoke-PortableStartup {
    if ($SetupMode) { $script:NextAfterSplash = 'firstrun'; return }
    # 0.5.0'dan kalan veriler: bu Data henüz boşsa bir kez kopyala
    if ((Test-LegacyData) -and (Test-DataFresh $Data)) {
        $moved = Get-MovedTo
        $here = $false
        if ($null -ne $moved) { try { $here = [string]::Equals([IO.Path]::GetFullPath($moved).TrimEnd('\'), $AppRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) } catch {} }
        if ($null -eq $moved -or $here) {
            try {
                $script:FrMigrated = Copy-LegacyData $Data $AppRoot $Cfg.dil
                Load-Config
                # C# LoadConfig pencere.json'u da okur: taşınan pencere konumları bu oturumda kullanılsın, kapanırken kaybolmasın
                if ($null -ne $Win -and (Test-Path -LiteralPath $WinFile)) {
                    try { $w0 = Get-Content -LiteralPath $WinFile -Raw | ConvertFrom-Json; foreach ($pn in $w0.PSObject.Properties.Name) { if ($null -ne $Win.PSObject.Properties[$pn]) { $Win.$pn = $w0.$pn } } } catch {}
                }
            } catch {}
        } else { $script:FrMovedTo = $moved }
    }
    Load-Servers
    $desc = L 'SyHost - modlu Minecraft sunucu merkezi'
    # Klasör taşındıysa eski yeri gösteren kısayolları buraya çevir
    try { if ((Repair-MovedShortcuts $ExePath $desc) -gt 0) { Home-Msg (L 'Kısayollar yeni yere güncellendi.') } } catch {}
    # Bu klasörü C# sürümü de kullandıysa onun biçimindeki kısayolumuz (conhost "<SyHost.exe>" --hosted)
    # Terminal biçimine çevrilir: buradaki SyHost.exe artık doğrudan açılan başlatıcı
    foreach ($lnk in Get-ShortcutLocations) {
        try {
            $i = Read-Shortcut $lnk
            if ((Get-LinkStateOf $i $lnk $ExePath) -ceq 'Ours' -and -not (Test-TerminalLink $i $ExePath)) { Write-Shortcut $lnk $ExePath $desc }
        } catch {}
    }
    Start-FolderLook $AppRoot $LangCode @(foreach ($sv in $Servers) { $sv.klasor })
    $done = $Cfg.PSObject.Properties['kurulumTamam']
    $notDone = $null -ne $done -and $done.Value -is [bool] -and -not $done.Value
    $script:NextAfterSplash = if ($notDone -or $null -ne $FrMigrated -or $null -ne $FrMovedTo) { 'firstrun' } else { 'home' }
}
