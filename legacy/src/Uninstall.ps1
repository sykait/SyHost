# =====================================================================
#  SyHost - Kaldır ekranı (Ayarlar > SyHost'u kaldır)  (Terminal sürümü)
#  Klasörün dışında kalan her iz ayrı bir satırda; kullanıcı ne kaldırılacağını
#  tek tek seçer (Boşluk). Java varsayılan olarak seçili gelmez. Klasörü silmek
#  ayrıca seçilir ve ikinci bir Enter ile onaylanır. Klasör dışındaki sunuculara
#  asla dokunulmaz. Görünüm "kapatılıyor" ekranındaki adım listesi gibidir.
#  Bulunanlar: bu SyHost'un kısayolları, SyHost'un kurduğu kullanıcı yazı tipi, 0.5.0'dan kalanlar
#  (eski veri klasörü, eski kurulum klasörü, Program Files'taki playit, C:\Windows\Fonts'taki yazı tipi,
#  winget ile kurulmuş Java) ve istenirse SyHost klasörünün kendisi (SyHost kapandıktan sonra silinir).
#  SYHOST_DRYRUN=1: hiçbir şey silinmez, yalnızca ne yapılacağı %TEMP%\syhost-dryrun.log dosyasına yazılır.
#  C# karşılığı: src\SyHost\App\App.Uninstall.cs (ekran) ve src\SyHost\Setup\Uninstall.cs (bulma ve kaldırma).
# =====================================================================
$UnItems = $null       # kaldırılabilecekler (Get-UninstallItems); $null: ekran açılınca yeniden bulunur
$UnSel = 0
$UnPhase = 'liste'     # liste | onay | calisiyor | bitti
$UnJob = $null         # arka plandaki kaldırma işi (Start-UninstallJob)

function Start-Uninstall {
    $script:UnItems = Get-UninstallItems $AppRoot $ExePath $Servers
    $script:UnSel = 0; $script:UnPhase = 'liste'; $script:UnJob = $null
    $script:Screen = 'uninstall'
    Reset-Frame
}

# Klasörle birlikte silinecek sunucu sayısı: listedeki (klasörün içindeki) sunucular ve Servers'taki bütün klasörler.
# Listeden kaldırılmış bir sunucunun dünyası da klasörle gider; sayıda görünmesi gerekir. (C#: UnServersInside)
function UnServersInside {
    $dirs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($sv in $Servers) { if (UnInside ([string]$sv.klasor) $AppRoot) { try { [void]$dirs.Add([IO.Path]::GetFullPath([string]$sv.klasor).TrimEnd('\')) } catch {} } }
    try {
        $sd = [IO.Path]::Combine($AppRoot, 'Servers')
        if ([IO.Directory]::Exists($sd)) { foreach ($d in [IO.Directory]::EnumerateDirectories($sd)) { [void]$dirs.Add([IO.Path]::GetFullPath($d).TrimEnd('\')) } }
    } catch {}
    $dirs.Count
}
function UnFolderOn { foreach ($x in $UnItems) { if ($x.Key -ceq 'klasor' -and $x.On) { return $true } }; $false }
function UnAnyOn { foreach ($x in $UnItems) { if ($x.On) { return $true } }; $false }

function Render-Uninstall([int]$W, [int]$H) {
    if ($null -eq $UnItems) { Start-Uninstall }
    if ($UnPhase -ceq 'calisiyor' -and $null -ne $UnJob -and $UnJob.Handle.IsCompleted) { UnFinish }
    $rows = New-Object System.Collections.Generic.List[string]
    $rows.Add('')
    $rows.Add('  ' + $Bo + $c.red + (L "SYHOST'U KALDIR") + $R + $c.dim + '   ' + $AppRoot + $R)
    $rows.Add('')
    $rows.Add((Rule $(if ($UnPhase -ceq 'bitti') { L 'BİTTİ' } else { L 'NELER KALDIRILSIN?' }) $W))
    $rows.Add('')
    $listing = $UnPhase -ceq 'liste' -or $UnPhase -ceq 'onay'
    for ($i = 0; $i -lt $UnItems.Count; $i++) {
        $it = $UnItems[$i]
        if (-not $listing -and -not $it.On) { continue }
        $detail = if ($it.Key -ceq 'klasor') { $c.yellow + (L 'içinde {0} sunucu ve dünyaları var' (UnServersInside)) + $R } else { $c.dim + $it.Detail + $R }
        if ($it.NeedsAdmin) { $detail += $c.yellow + '  ·  ' + (L 'Windows izin isteyecek') + $R }
        if ($listing) {
            $sel = $i -eq $UnSel
            $box = if ($it.On) { $(if ($it.Key -ceq 'klasor') { $c.red } else { $c.brass }) + $Bo + '■' + $R } else { $c.dark + '□' + $R }
            $line = '  ' + $(if ($sel) { $c.brass + $Bo + '❯' } else { ' ' }) + $R + ' ' + $box + ' ' + (PadV ($(if ($sel) { $Bo + $c.text } else { $c.soft }) + (L $it.Title)) 46) + '  ' + $detail
            $rows.Add($(if ($sel) { SelLine $line $W } else { $line }))
        } else {
            $st = [int]$it.State
            $mark = switch ($st) { 2 { $c.green + $Bo + '✓' } 1 { $c.yellow + (Spin) } 3 { $c.red + $Bo + 'x' } default { $c.dark + '·' } }
            $rows.Add('  ' + $mark + $R + ' ' + $c.text + (L $it.Title) + $R + $(if ($st -eq 3) { $c.red + '   ' + $it.Error + $R } else { '' }))
        }
    }
    $rows.Add('')
    if ($listing) {
        $rows.Add('  ' + $c.dim + (L 'Java varsayılan olarak silinmez; başka programlar da kullanıyor olabilir.') + $R)
        $outside = New-Object System.Collections.Generic.List[string]
        foreach ($sv in $Servers) { if (-not (UnInside ([string]$sv.klasor) $AppRoot)) { $outside.Add([string]$sv.klasor) } }
        if ($outside.Count -gt 0) { foreach ($l in (WordWrap (L 'Klasörün dışındaki sunuculara dokunulmaz: {0}' ($outside -join ', ')) ($W - 6))) { $rows.Add('  ' + $c.dim + $l + $R) } }
        $rows.Add('')
        if ($UnPhase -ceq 'onay') {
            foreach ($l in (WordWrap (L "Emin misin? SyHost klasörü, içindeki sunucular ve dünyalarla birlikte silinecek. Onaylamak için tekrar Enter'a bas.") ($W - 6))) { $rows.Add('  ' + $Bo + $c.red + $l + $R) }
            $rows.Add('')
        }
        $rows.Add('  ' + (Pill '200;30;45' '255;255;255' 'Enter') + $c.text + (L ' Seçilenleri kaldır   ') + $R + (Pill '50;50;56' '235;235;235' (L 'Boşluk')) + $c.text + (L ' seç / bırak   ') + $R + (Pill '50;50;56' '235;235;235' 'Esc') + $c.text + (L ' Vazgeç') + $R)
    } elseif ($UnPhase -ceq 'calisiyor') {
        $rows.Add('  ' + $c.brass + (Pulse) + $R + ' ' + (Shimmer (L 'Kaldırılıyor…') @(110, 110, 120) @(255, 60, 70)))
    } else {
        $folder = UnFolderOn
        $rows.Add('  ' + $c.green + $Bo + (L 'Kaldırma tamamlandı.') + $R)
        $after = if ($folder) { L "SyHost kapanınca klasörün içi silinecek; sonra klasörü Explorer'da göstereceğim, oradan silebilirsin." } else { L "Artık SyHost klasörünü silebilirsin; Explorer'da gösterdim." }
        foreach ($l in (WordWrap $after ($W - 6))) { $rows.Add('  ' + $c.soft + $l + $R) }
        if (DryRunShown) { $rows.Add('  ' + $c.yellow + (L 'Deneme modu: hiçbir şey silinmedi.') + $R) }
        $rows.Add('')
        $rows.Add('  ' + (Pill '240;240;240' '18;18;20' 'Enter') + $c.text + (L " SyHost'u kapat") + $R)
    }
    while ($rows.Count -lt $H - 2) { $rows.Add('') }
    Update-Sky $W $H 0.07 1 $false 0.75
    for ($r1 = 0; $r1 -lt $rows.Count; $r1++) { if ($rows[$r1] -ceq '') { $rows[$r1] = Sky-Seg $r1 0 $W } }
    $rows.Add($c.dark + ('─' * $W) + $R)
    $rows.Add(' ' + $(if ($listing) { (Key '↑↓' (L 'seç')) + (Key (L 'Boşluk') (L 'seç / bırak')) + (Key 'Enter' (L 'kaldır')) + (Key 'Esc' (L 'vazgeç')) } elseif ($UnPhase -ceq 'bitti') { Key 'Enter' (L 'kapat') } else { '' }))
    , $rows
}

function Handle-UninstallKey([ConsoleKeyInfo]$k, [bool]$ctrl) {
    if ($UnPhase -ceq 'liste' -or $UnPhase -ceq 'onay') {
        $n = $UnItems.Count
        switch ($k.Key) {
            'UpArrow' { if ($n -gt 0) { $script:UnSel = ($UnSel + $n - 1) % $n }; $script:UnPhase = 'liste'; return }
            'DownArrow' { if ($n -gt 0) { $script:UnSel = ($UnSel + 1) % $n }; $script:UnPhase = 'liste'; return }
            'Spacebar' { if ($n -gt 0) { $UnItems[$UnSel].On = -not $UnItems[$UnSel].On }; $script:UnPhase = 'liste'; return }
            'Escape' { $script:UnItems = $null; $script:Screen = 'settings'; Reset-Frame; return }
            'Enter' {
                $folder = UnFolderOn
                if ($folder -and $UnPhase -cne 'onay') { $script:UnPhase = 'onay'; return }
                # Hiçbir şey seçilmedi: kaldırılacak iz yok, "bitti" ekranı klasörün silinebileceğini söyler
                if (-not (UnAnyOn)) { UnFinish; return }
                $script:UnPhase = 'calisiyor'
                # Klasör silinecek: playit kapanır ve bu oturumda yeniden açılmaz (dosyaları serbest kalsın)
                if ($folder) { $script:PlayitHold = $true; Stop-Playit }
                # Test modunda kaldırma başlamaz: kare her seferinde aynı çıkar ve hiçbir şeye dokunulmaz
                if (-not $TestFrame) { $script:UnJob = Start-UninstallJob $UnItems }
                return
            }
        }
        return
    }
    if ($UnPhase -ceq 'bitti' -and $k.Key -eq 'Enter') { Start-Outro }
}

function UnFinish {
    $script:UnPhase = 'bitti'
    if ($null -ne $UnJob) { try { [void]$UnJob.PS.EndInvoke($UnJob.Handle) } catch {}; try { $UnJob.PS.Dispose() } catch {} }
    if (UnFolderOn) { $script:DeleteRootAfterExit = $true }
    elseif (-not (Test-DryRun) -and -not $TestFrame) { Show-UninstallFolder $AppRoot }
    $script:Dirty = $true
}

# ---------- Bulma ve kaldırma (C#: Setup\Uninstall.cs) ----------
# Bir satır: Key kisayol | yazitipi | eskiveri | eskikurulum | eskiplayit | eskiyazitipi | java | klasor;
# Title ekranda görünen ad (Türkçe anahtar, L ile çevrilir); Detail ayrıntı (yol vb., çevrilmez);
# State 0 bekliyor, 1 sürüyor, 2 bitti, 3 hata, 4 atlandı; Error hata metni;
# Run kaldırmanın ayrıntıları (yalnızca Get-UninstallItems doldurur; test senaryosundaki satırlarda yoktur).
function New-UnItem([string]$key, [string]$title, [string]$detail, [bool]$on, [bool]$admin, $run) {
    [pscustomobject]@{ Key = $key; Title = $title; Detail = $detail; On = $on; NeedsAdmin = $admin; State = 0; Error = $null; Run = $run }
}

# Bir yol SyHost klasörünün içinde mi? (C# Portable.IsInside ile aynı: klasörün kendisi de içinde sayılır.)
# Silme kararları başka bir dosyaya bağlı kalmasın diye burada ayrıca tanımlı.
function UnInside([string]$path, [string]$root) {
    try {
        $p = [IO.Path]::GetFullPath($path).TrimEnd('\') + '\'
        $r = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
        $p.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)
    } catch { $false }
}
# Kayıtlı bir sunucu bu klasörün içinde mi? (öyleyse klasör kaldırılmaya önerilmez)
# Not: listeler @(...) içine alınmaz: Windows PowerShell 5.1.26100'de @($x), $x bir List[object] ise
# "Argument types do not match" hatası veriyor (List[string], ArrayList ve dizilerde sorun yok).
function UnHoldsServer($servers, [string]$dir) {
    foreach ($sv in $servers) { $k = [string]$sv.klasor; if ($k -and (UnInside $k $dir)) { return $true } }
    $false
}

# İndirilenler klasörü (C#: Portable.Downloads)
function UnDownloads {
    try {
        $d = [Microsoft.Win32.Registry]::GetValue('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders', '{374DE290-123F-4565-9164-39C4925E467B}', $null)
        if ($d -is [string] -and $d) { return [Environment]::ExpandEnvironmentVariables($d) }
    } catch {}
    [IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'), 'Downloads')
}
# Silinmesi felaket olacak klasörler: SyHost klasörü bunlardan biriyse ya da birini içeriyorsa silinmez
function UnProtectedFolders {
    foreach ($f in 'UserProfile', 'DesktopDirectory', 'MyDocuments', 'MyMusic', 'MyPictures', 'MyVideos', 'ApplicationData', 'LocalApplicationData', 'CommonApplicationData', 'ProgramFiles', 'ProgramFilesX86', 'Windows', 'Programs') { [Environment]::GetFolderPath($f) }
    UnDownloads
    foreach ($v in 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial') { [Environment]::GetEnvironmentVariable($v) }
}
# SyHost klasörünün kendisi silinebilir mi? Sürücü kökü (ör. bir USB bellek), git deposu, kullanıcı klasörü,
# Masaüstü, Belgeler, İndirilenler, Program Files, Windows ya da bunlardan birini içeren bir klasör silinmez.
function Test-RootDeletable([string]$root) {
    try {
        $full = [IO.Path]::GetFullPath($root).TrimEnd('\')
        $drive = [IO.Path]::GetPathRoot($full)
        if ([string]::IsNullOrEmpty($drive) -or [string]::Equals($drive.TrimEnd('\'), $full, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $git = [IO.Path]::Combine($full, '.git')
        if ([IO.Directory]::Exists($git) -or [IO.File]::Exists($git)) { return $false }
        foreach ($p in @(UnProtectedFolders)) { if ($p -and (UnInside $p $full)) { return $false } }
        return $true
    } catch { return $false }
}

# Kaldırılabilecek her şeyi bul (C#: Uninstall.Detect). Bir denetim hata verirse o satır gösterilmez.
function Get-UninstallItems([string]$root, [string]$exe, $servers) {
    $list = New-Object System.Collections.Generic.List[object]
    $local = [Environment]::GetFolderPath('LocalApplicationData')

    # 1) Bu SyHost'u açan kısayollar
    try {
        $ours = New-Object System.Collections.Generic.List[string]
        foreach ($l in @(Get-ShortcutLocations)) { if ((Get-LinkState $l $exe) -eq 'Ours') { $ours.Add($l) } }
        if ($ours.Count -gt 0) { $list.Add((New-UnItem 'kisayol' 'Masaüstü ve Başlat menüsü kısayolları' ($ours -join '  ·  ') $true $false @{ Exe = $exe })) }
    } catch {}

    # 2) SyHost'un bu kullanıcıya kurduğu yazı tipi
    try {
        if (Test-FontBySyHost) { $list.Add((New-UnItem 'yazitipi' "SyHost'un kurduğu Cascadia Mono yazı tipi" ([IO.Path]::Combine($local, 'Microsoft\Windows\Fonts')) $true $false @{})) }
    } catch {}

    # 3) 0.5.0'ın veri klasörü (SyHost klasörünü ya da kayıtlı bir sunucuyu içeriyorsa önerilmez)
    try {
        $legacy = Get-LegacyDir
        if ([IO.Directory]::Exists($legacy) -and -not (UnInside $legacy $root) -and -not (UnInside $root $legacy) -and -not (UnHoldsServer $servers $legacy)) {
            $list.Add((New-UnItem 'eskiveri' 'Eski sürümün veri klasörü' $legacy $false $false @{ Path = $legacy }))
        }
    } catch {}

    # 4) 0.5.0'ın kurulum klasörü (install.ps1 buraya kuruyordu) ve onu açan eski kısayollar
    try {
        $old = [IO.Path]::Combine($local, 'Programs\SyHost')
        if ([IO.Directory]::Exists($old) -and -not (UnInside $old $root) -and -not (UnInside $root $old) -and -not (UnHoldsServer $servers $old)) {
            $list.Add((New-UnItem 'eskikurulum' 'Eski sürümün program klasörü' $old $false $false @{ Path = $old }))
        }
    } catch {}

    # 5) Program Files'taki playit (eski kurulum, winget)
    try {
        $playit = @(UnFindMsi @('playit'))
        if ($playit.Count -gt 0) { $list.Add((New-UnItem 'eskiplayit' 'Eski playit kurulumu (Program Files)' $playit[0].Name $false $true @{ Command = $playit[0].Uninstall })) }
    } catch {}

    # 6) Eski kurulumun C:\Windows\Fonts'a koyduğu yazı tipi
    try {
        $sysFont = [IO.Path]::Combine([Environment]::GetFolderPath('Windows'), 'Fonts\CascadiaMono-Regular.ttf')
        if ([IO.File]::Exists($sysFont)) { $list.Add((New-UnItem 'eskiyazitipi' 'Eski kurulumun sisteme koyduğu yazı tipi' $sysFont $false $true @{ Exe = $exe })) }
    } catch {}

    # 7) Eski sürümün winget ile kurduğu Java'lar (varsayılan: silinmez)
    try {
        foreach ($j in @(UnFindMsi @('Microsoft Build of OpenJDK', 'Eclipse Temurin JRE with Hotspot 8'))) {
            $list.Add((New-UnItem 'java' 'Java (başka programlar da kullanıyor olabilir)' $j.Name $false $true @{ Command = $j.Uninstall }))
        }
    } catch {}

    # 8) SyHost klasörünün kendisi (sunucular ve dünyalar dahil)
    if (Test-RootDeletable $root) { $list.Add((New-UnItem 'klasor' 'SyHost klasörünün kendisi' $root $false $false @{})) }
    , $list
}

# Kayıt defterindeki kurulu programlar: adı verilen öneklerden biriyle başlayanlar (64 ve 32 bit görünüm)
function UnFindMsi([string[]]$prefixes) {
    $r = New-Object System.Collections.Generic.List[object]
    foreach ($view in [Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32) {
        $hk = $null; $k = $null
        try {
            $hk = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $k = $hk.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if ($null -eq $k) { continue }
            foreach ($sub in $k.GetSubKeyNames()) {
                $e = $null
                try {
                    $e = $k.OpenSubKey($sub)
                    if ($null -eq $e) { continue }
                    $name = $e.GetValue('DisplayName')
                    if ($name -isnot [string]) { continue }
                    $hit = $false
                    foreach ($p in $prefixes) { if ($name.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { $hit = $true; break } }
                    if (-not $hit) { continue }
                    $u = $e.GetValue('QuietUninstallString')
                    if ($u -isnot [string]) { $u = $e.GetValue('UninstallString'); if ($u -isnot [string]) { $u = $null } }
                    if ([string]::IsNullOrEmpty($u)) { continue }
                    $dup = $false
                    foreach ($x in $r) { if ($x.Name -ceq $name) { $dup = $true; break } }
                    if (-not $dup) { $r.Add([pscustomobject]@{ Name = $name; Uninstall = $u }) }
                } catch {} finally { if ($null -ne $e) { $e.Dispose() } }
            }
        } catch {} finally { if ($null -ne $k) { $k.Dispose() }; if ($null -ne $hk) { $hk.Dispose() } }
    }
    $r   # tek tek: çağıran @(...) ile toplar
}

# Seçili adımları sırayla çalıştır (C#: Uninstall.RunSelected; arka planda Start-UninstallJob çağırır)
function Invoke-UninstallItems($items) {
    foreach ($it in $items) {   # @($items) değil: bkz. UnHoldsServer
        if (-not $it.On -or $it.Key -ceq 'klasor') { $it.State = $(if ($it.On) { 2 } else { 4 }); continue }
        $it.State = 1
        try {
            $err = if (Test-DryRun) { UnDryRunLog $it } else { UnRunItem $it }
            $it.Error = $err; $it.State = $(if ($null -eq $err) { 2 } else { 3 })
        } catch { $it.Error = UnErrorText $_; $it.State = 3 }
    }
}

# Bir adımı gerçekten uygula: hata metni ya da $null döner
function UnRunItem($it) {
    $run = $it.Run
    if ($null -eq $run) { throw (New-Object NullReferenceException) }   # test senaryosundaki satır: yapılacak bir şey yok
    switch -CaseSensitive ($it.Key) {
        'kisayol' { $null = Remove-OurShortcuts $run.Exe; return $null }
        'yazitipi' { $ok = @(Uninstall-FontPerUser); if ($ok.Count -gt 0 -and [bool]$ok[$ok.Count - 1]) { return $null }; return '?' }
        'eskiveri' { return (UnDeleteDir $run.Path) }
        'eskikurulum' {
            foreach ($l in @(Get-ShortcutLocations)) {
                $p = UnLinkSyHostPath $l
                if ($p -and (UnInside $p $run.Path)) { if (Test-DryRun) { UnLog ('kısayol silinecekti: ' + $l) } else { try { [IO.File]::Delete($l) } catch {} } }
            }
            return (UnDeleteDir $run.Path)
        }
        'eskiplayit' { return (UnRunUninstaller $run.Command) }
        'java' { return (UnRunUninstaller $run.Command) }
        'eskiyazitipi' { return (UnRemoveSystemFont $run.Exe) }
    }
    $null
}

function UnDryRunLog($it) { UnLog ('[deneme] yapılacaktı: ' + $it.Key + '  ' + $it.Detail); $null }

function UnLog([string]$s) {
    try { [IO.File]::AppendAllText([IO.Path]::Combine([IO.Path]::GetTempPath(), 'syhost-dryrun.log'), [DateTime]::Now.ToString('HH:mm:ss ') + $s + [Environment]::NewLine) } catch {}
}

# PowerShell .NET hatalarını "Exception calling ..." diye sarar; C# sürümündeki gibi asıl hata gösterilsin
function UnInnerError($er) {
    $x = $er.Exception
    while ($x -is [System.Management.Automation.MethodInvocationException] -and $null -ne $x.InnerException) { $x = $x.InnerException }
    $x
}
function UnErrorText($er) { [string](UnInnerError $er).Message }

# Klasörü sil. Bağlantılara (junction, sembolik bağlantı) girilmez: bağlantının kendisi silinir, gösterdiği yer
# olduğu gibi kalır. Silmeyi engelleyen tek öznitelik olan "salt okunur" silmeden önce kaldırılır. (C#: DeleteDir)
function UnClearReadOnly([IO.FileSystemInfo]$e) {
    try { if (($e.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) { $e.Attributes = $e.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly) } } catch {}
}
function UnDeleteDir([string]$dir) {
    if (Test-DryRun) { UnLog ('klasör silinecekti: ' + $dir); return $null }
    try {
        $top = New-Object IO.DirectoryInfo $dir
        if (($top.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { [IO.Directory]::Delete($top.FullName, $false); return $null }
        UnClearReadOnly $top
        $links = New-Object System.Collections.Generic.List[IO.FileSystemInfo]
        $stack = New-Object System.Collections.Generic.Stack[IO.DirectoryInfo]
        $stack.Push($top)
        while ($stack.Count -gt 0) {
            foreach ($e in $stack.Pop().EnumerateFileSystemInfos()) {
                if (($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $links.Add($e); continue }
                UnClearReadOnly $e
                if ($e -is [IO.DirectoryInfo]) { $stack.Push($e) }
            }
        }
        foreach ($l in $links) { if ($l -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($l.FullName, $false) } else { [IO.File]::Delete($l.FullName) } }
        [IO.Directory]::Delete($top.FullName, $true)
        return $null
    } catch { return (UnErrorText $_) }
}

# Kısayolun açtığı SyHost'un yolu (exe ya da eski sürümün SyHost.ps1'i); SyHost kısayolu değilse $null
# (C#: Shortcuts.Read + SyHostPathOf; Portable.ps1'deki okuyucu, COM nesnesi açılmaz)
function UnLinkSyHostPath([string]$lnk) {
    if (-not [IO.File]::Exists($lnk)) { return $null }
    try { $i = Read-Shortcut $lnk; if ($null -ne $i) { return (Get-LinkSyHostPath $i) } } catch {}
    $null
}

# Kaldırıcı komutunu çalıştırılacak dosya ve argümanlara ayır: @(dosya, argümanlar) (C#: Uninstall.UninstallerCommand)
function UnUninstallerCommand([string]$cmd) {
    $cmd = $cmd.Trim()
    # MsiExec.exe /I{GUID} -> /X{GUID} /qb (yalnızca ilerleme çubuğu). Tam yoluyla: yalın ad, SyHost klasöründeki
    # aynı adlı bir dosyayı da bulabilirdi (çalışma klasörü SyHost klasörü) ve o yönetici olarak açılırdı.
    if ($cmd.StartsWith('MsiExec.exe', [StringComparison]::OrdinalIgnoreCase)) {
        return @([IO.Path]::Combine([Environment]::SystemDirectory, 'msiexec.exe'), ([regex]::Replace($cmd.Substring('MsiExec.exe'.Length), '/I', '/X', [Text.RegularExpressions.RegexOptions]::IgnoreCase).Trim() + ' /qb'))
    }
    if ($cmd.StartsWith('"')) {
        $q = $cmd.IndexOf([char]'"', 1)
        return @($cmd.Substring(1, $q - 1), $cmd.Substring($q + 1).Trim())
    }
    $sp = $cmd.IndexOf([char]' ')
    if ($sp -lt 0) { return @($cmd, '') }
    @($cmd.Substring(0, $sp), $cmd.Substring($sp + 1))
}

# Bir programın kendi kaldırıcısını çalıştır (MSI ise Windows izin penceresi çıkar)
function UnRunUninstaller([string]$cmd) {
    try {
        $fa = @(UnUninstallerCommand $cmd)
        $psi = New-Object Diagnostics.ProcessStartInfo $fa[0], $fa[1]
        $psi.UseShellExecute = $true; $psi.Verb = 'runas'
        $p = [Diagnostics.Process]::Start($psi)
        if ($null -eq $p) { return $null }
        try { $p.WaitForExit(); $code = $p.ExitCode } finally { $p.Dispose() }
        if ($code -eq 0 -or $code -eq 3010) { return $null }
        return 'kod ' + $code
    } catch {
        $x = UnInnerError $_
        if ($x -is [System.ComponentModel.Win32Exception] -and $x.NativeErrorCode -eq 1223) { return 'izin verilmedi' }
        return [string]$x.Message
    }
}

# Eski kurulumun C:\Windows\Fonts'a koyduğu Cascadia Mono'yu kaldır: SyHost.exe (başlatıcı) kendini yalnızca
# --remove-old-system-font ile yönetici olarak açar (Windows izin penceresinde SyHost görünür). PowerShell,
# kodlanmış komut ya da gizli pencere yoktur. Exe yoksa (ör. repodan çalıştırma) 'kod 2'.
# (C#: Uninstall.RemoveSystemFont, anahtar: OldSystemFont.Arg)
function UnRemoveSystemFont([string]$exe) {
    try {
        if (-not $exe -or -not [IO.File]::Exists($exe)) { return 'kod 2' }
        $psi = New-Object Diagnostics.ProcessStartInfo $exe, '--remove-old-system-font'
        $psi.UseShellExecute = $true; $psi.Verb = 'runas'
        $p = [Diagnostics.Process]::Start($psi)
        if ($null -eq $p) { return $null }
        try { $p.WaitForExit(); $code = $p.ExitCode } finally { $p.Dispose() }
        if ($code -eq 0) { return $null }
        return 'kod ' + $code
    } catch {
        $x = UnInnerError $_
        if ($x -is [System.ComponentModel.Win32Exception] -and $x.NativeErrorCode -eq 1223) { return 'izin verilmedi' }
        return [string]$x.Message
    }
}

# ---------- Arka plan işi ----------
# Kaldırma ayrı bir çalışma alanında UninstallJob.ps1 dosyasıyla yürür: o dosya Portable.ps1 ile Uninstall.ps1'i
# diskten yükler (ikisinin de en üst düzeyinde yalnızca atama ve fonksiyon tanımı vardır) ve seçili satırları işler.
# Satırlar (UnItems) paylaşılır: iş State ve Error alanlarını yazar, ekran her karede okur. Metinden kod
# üretilmez; işin gerektirdiği her şey satırın Run bilgisindedir. SyHost.Core.dll türleri süreçte zaten yüklüdür.
# (C#: Task.Run(() => Uninstall.RunSelected(items)))
$UnJobFile = Join-Path $PSScriptRoot 'UninstallJob.ps1'
function Start-UninstallJob($items) {
    $ps = [powershell]::Create()
    [void]$ps.AddCommand($UnJobFile).AddParameter('Items', $items)
    [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
}

# Kaldır > "SyHost klasörünün kendisi": SyHost kapanırken (sunucu, playit ve tepsi kapandıktan sonra, tek kopya kilidi
# henüz bırakılmadan) klasörün içi BU süreçte silinir; kendini silen yardımcı bir süreç başlatılmaz. $keep'tekiler
# (başlatıcı exe ve SyHost.Core.dll'i yüklü App klasörü) ile kullanımdaki dosyalar kalır, klasörün kendisi de kalır
# (SyHost'un çalışma klasörüdür): ardından Explorer klasörü gösterir, kullanıcı kalanı oradan siler.
# (C#: Uninstall.DeleteFolderAfterExit)
function Remove-RootAfterExit([string]$root, [string[]]$keep) {
    if (-not (Test-RootDeletable $root)) { return }
    if (Test-DryRun) { UnLog ('SyHost kapanınca klasör silinecekti: ' + $root); return }
    $tmp = [IO.Path]::GetTempPath()
    try { [Environment]::CurrentDirectory = $tmp; Set-Location -LiteralPath $tmp } catch {}
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($k in $keep) { try { if ($k) { $kept.Add([IO.Path]::GetFullPath($k).TrimEnd('\')) } } catch {} }
    # Yeni kapanan sunucu ya da playit dosyaları bir an daha tutabilir: birkaç tur dene (en çok ~5 sn)
    for ($round = 0; $round -lt 10 -and -not (UnEmptyFolder $root $kept); $round++) { Start-Sleep -Milliseconds 500 }
    try { $di = New-Object IO.DirectoryInfo $root; $di.Attributes = $di.Attributes -band (-bnot ([IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::System)) } catch {}
}
# Klasörün içini sil (klasörün kendisi kalır); $keep'tekiler kalır. Silinemeyen bir şey kaldıysa $false. (C#: EmptyFolder)
function UnEmptyFolder([string]$dir, $keep) {
    try { $entries = @((New-Object IO.DirectoryInfo $dir).EnumerateFileSystemInfos()) } catch { return $false }
    $clean = $true
    foreach ($e in $entries) {
        $full = $e.FullName.TrimEnd('\')
        $isKept = $false
        foreach ($k in $keep) { if ([string]::Equals($k, $full, [StringComparison]::OrdinalIgnoreCase)) { $isKept = $true; break } }
        if ($isKept) { continue }
        try {
            if (($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                # Bağlantı: yalnızca kendisi silinir, gösterdiği yer olduğu gibi kalır
                if ($e -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($full, $false) } else { [IO.File]::Delete($full) }
            } elseif ($e -is [IO.DirectoryInfo]) {
                # İçinde saklanacak bir şey varsa klasörün içine girilir, yoksa bütünüyle silinir
                $holds = $false
                foreach ($k in $keep) { if (UnInside $k $full) { $holds = $true; break } }
                if ($holds) { if (-not (UnEmptyFolder $full $keep)) { $clean = $false } }
                elseif ($null -ne (UnDeleteDir $full)) { $clean = $false }
            } else {
                UnClearReadOnly $e
                [IO.File]::Delete($full)
            }
        } catch { $clean = $false }
    }
    $clean
}

# Explorer'da SyHost klasörünü seçili göster ("artık silebilirsin")
function Show-UninstallFolder([string]$root) {
    try {
        # Tam yoluyla: yalın "explorer.exe" çalışma klasöründe (SyHost klasörü) de aranırdı
        $explorer = [IO.Path]::Combine([Environment]::GetFolderPath('Windows'), 'explorer.exe')
        $psi = New-Object Diagnostics.ProcessStartInfo $explorer, ('/select,"' + $root.TrimEnd('\') + '"')
        $psi.UseShellExecute = $true
        $p = [Diagnostics.Process]::Start($psi)
        if ($null -ne $p) { $p.Dispose() }
    } catch {}
}
