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

function UnServersInside { $n = 0; foreach ($sv in $Servers) { if (UnInside ([string]$sv.klasor) $AppRoot) { $n++ } }; $n }
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
        $rows.Add('  ' + $c.soft + $(if ($folder) { L 'SyHost kapanınca klasörü de silinecek.' } else { L "Artık SyHost klasörünü silebilirsin; Explorer'da gösterdim." }) + $R)
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
                if (-not (UnAnyOn)) { return }
                $script:UnPhase = 'calisiyor'
                if ($folder) { Stop-Playit }
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
        if ([IO.File]::Exists($sysFont)) { $list.Add((New-UnItem 'eskiyazitipi' 'Eski kurulumun sisteme koyduğu yazı tipi' $sysFont $false $true @{})) }
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
        'eskiyazitipi' { return (UnRemoveSystemFont) }
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
# olduğu gibi kalır. Salt okunur, gizli ve sistem öznitelikleri silmeden önce kaldırılır.
function UnDeleteDir([string]$dir) {
    if (Test-DryRun) { UnLog ('klasör silinecekti: ' + $dir); return $null }
    try {
        $top = New-Object IO.DirectoryInfo $dir
        if (($top.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { [IO.Directory]::Delete($top.FullName, $false); return $null }
        try { $top.Attributes = [IO.FileAttributes]::Normal } catch {}
        $links = New-Object System.Collections.Generic.List[IO.FileSystemInfo]
        $stack = New-Object System.Collections.Generic.Stack[IO.DirectoryInfo]
        $stack.Push($top)
        while ($stack.Count -gt 0) {
            foreach ($e in $stack.Pop().EnumerateFileSystemInfos()) {
                if (($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $links.Add($e); continue }
                try { $e.Attributes = [IO.FileAttributes]::Normal } catch {}
                if ($e -is [IO.DirectoryInfo]) { $stack.Push($e) }
            }
        }
        foreach ($l in $links) { if ($l -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($l.FullName, $false) } else { [IO.File]::Delete($l.FullName) } }
        [IO.Directory]::Delete($top.FullName, $true)
        return $null
    } catch { return (UnErrorText $_) }
}

# Kısayolun açtığı SyHost'un yolu (exe ya da eski sürümün SyHost.ps1'i); SyHost kısayolu değilse $null (C#: Shortcuts.SyHostPathOf)
function UnLinkSyHostPath([string]$lnk) {
    if (-not [IO.File]::Exists($lnk)) { return $null }
    try {
        $sl = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        foreach ($s in @([string]$sl.Arguments, [string]$sl.TargetPath)) {
            $m = [regex]::Match($s, '"?([^"]*?(?:SyHost[^"\\]*\.exe|SyHost\.ps1))"?', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($m.Success) { return $m.Groups[1].Value.Trim() }
        }
    } catch {}
    $null
}

# Bir programın kendi kaldırıcısını çalıştır (MSI ise Windows izin penceresi çıkar)
function UnRunUninstaller([string]$cmd) {
    try {
        $cmd = $cmd.Trim()
        if ($cmd.StartsWith('MsiExec.exe', [StringComparison]::OrdinalIgnoreCase)) {
            # MsiExec.exe /I{GUID} -> /X{GUID} /qb (yalnızca ilerleme çubuğu)
            $file = 'msiexec.exe'
            $arg = [regex]::Replace($cmd.Substring('MsiExec.exe'.Length), '/I', '/X', [Text.RegularExpressions.RegexOptions]::IgnoreCase).Trim() + ' /qb'
        } elseif ($cmd.StartsWith('"')) {
            $q = $cmd.IndexOf([char]'"', 1)
            $file = $cmd.Substring(1, $q - 1); $arg = $cmd.Substring($q + 1).Trim()
        } else {
            $sp = $cmd.IndexOf([char]' ')
            $file = if ($sp -lt 0) { $cmd } else { $cmd.Substring(0, $sp) }
            $arg = if ($sp -lt 0) { '' } else { $cmd.Substring($sp + 1) }
        }
        $psi = New-Object Diagnostics.ProcessStartInfo $file, $arg
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

# Eski kurulumun C:\Windows\Fonts'a koyduğu Cascadia Mono'yu kaldıran komut (yönetici izniyle çalışır)
function UnSystemFontScript {
    '$k=''HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'';' +
    'Remove-ItemProperty $k ''Cascadia Mono Regular (TrueType)'' -ErrorAction SilentlyContinue;' +
    'Remove-ItemProperty $k ''Cascadia Mono Bold (TrueType)'' -ErrorAction SilentlyContinue;' +
    'foreach($f in ''CascadiaMono-Regular.ttf'',''CascadiaMono-Bold.ttf''){ $p=Join-Path $env:WINDIR (''Fonts\''+$f); try{ Remove-Item $p -Force -ErrorAction Stop }catch{} }'
}
function UnRemoveSystemFont {
    try {
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((UnSystemFontScript)))
        $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe', ('-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ' + $enc)
        $psi.UseShellExecute = $true; $psi.Verb = 'runas'; $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $p = [Diagnostics.Process]::Start($psi)
        if ($null -ne $p) { try { $p.WaitForExit() } finally { $p.Dispose() } }
        return $null
    } catch {
        $x = UnInnerError $_
        if ($x -is [System.ComponentModel.Win32Exception] -and $x.NativeErrorCode -eq 1223) { return 'izin verilmedi' }
        return [string]$x.Message
    }
}

# ---------- Arka plan işi ----------
# İş, ana oturumun bir kopyasında çalışır: bütün betik fonksiyonları (Portable.ps1'deki kısayol ve yazı tipi
# işleri dahil) metinden yeniden tanımlanır, betik değişkenleri aktarılır. Satırlar (UnItems) paylaşılır:
# iş State ve Error alanlarını yazar, ekran her karede okur. Scriptblock'lar metin olarak taşınır
# (bir runspace'in scriptblock'unu başka bir runspace'te çalıştırmak güvenli değildir).
$UnSkipVars = @('$', '^', '_', 'args', 'input', 'MyInvocation', 'PSBoundParameters', 'PSCmdlet', 'PSCommandPath', 'PSScriptRoot', 'PSItem',
    'this', 'foreach', 'switch', 'Matches', 'LASTEXITCODE', 'Error', 'StackTrace', 'null', 'true', 'false', 'PWD', 'Host', 'ExecutionContext',
    'PID', 'HOME', 'PSHOME', 'ShellId', 'PSVersionTable', 'PSEdition', 'PSCulture', 'PSUICulture', 'NestedPromptLevel', 'PROFILE',
    'ConsoleFileName', 'Event', 'EventArgs', 'EventSubscriber', 'Sender', 'PSDebugContext', 'PSSenderInfo')
$UnJobScript = @'
param($UnJobItems, $UnJobFuncs, $UnJobVars, $UnJobBlocks)
foreach ($UnJobKv in $UnJobVars.GetEnumerator()) { try { Set-Variable -Name $UnJobKv.Key -Value $UnJobKv.Value -Scope Global -Force } catch {} }
foreach ($UnJobKv in $UnJobBlocks.GetEnumerator()) { try { Set-Variable -Name $UnJobKv.Key -Value ([scriptblock]::Create($UnJobKv.Value)) -Scope Global -Force } catch {} }
foreach ($UnJobF in $UnJobFuncs) { try { . ([scriptblock]::Create($UnJobF)) } catch {} }
try { Invoke-UninstallItems $UnJobItems }
catch {
    $UnJobMsg = $_.Exception.Message
    foreach ($UnJobIt in $UnJobItems) { if ($UnJobIt.State -eq 0 -or $UnJobIt.State -eq 1) { if ($UnJobIt.On) { $UnJobIt.Error = $UnJobMsg; $UnJobIt.State = 3 } else { $UnJobIt.State = 4 } } }
}
'@
function Start-UninstallJob($items) {
    $funcs = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem function:)) {
        $sb = $f.ScriptBlock
        if ($null -eq $sb -or -not $sb.File) { continue }   # PowerShell'in kendi fonksiyonları
        $fd = $sb.Ast.Parent
        if ($fd -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $funcs.Add($fd.Extent.Text) }
        else { $funcs.Add('function ' + $f.Name + " {`r`n" + $sb.ToString() + "`r`n}") }
    }
    $vars = @{}; $blocks = @{}
    $fixed = [System.Management.Automation.ScopedItemOptions]::ReadOnly -bor [System.Management.Automation.ScopedItemOptions]::Constant
    foreach ($v in @(Get-Variable -Scope Script)) {
        if (($v.Options -band $fixed) -ne 0 -or $UnSkipVars -contains $v.Name) { continue }
        if ($v.Value -is [scriptblock]) { $blocks[$v.Name] = $v.Value.ToString() } else { $vars[$v.Name] = $v.Value }
    }
    $ps = [powershell]::Create()
    [void]$ps.AddScript($UnJobScript, $false).AddArgument($items).AddArgument($funcs).AddArgument($vars).AddArgument($blocks)
    [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
}

# Klasörü silen cmd komutu (C#: Uninstall.DeleteFolderCommand): 60 kez dener, SyHost'un açık tuttuğu dosyalar o
# kapanınca silinir. Yalnızca klasörün kendi öznitelikleri kaldırılır ("attrib /s" klasörün dışına da dokunuyordu);
# rmdir /s salt okunur, gizli ve sistem dosyalarını kendisi siler ve bağlantıların içine girmez.
function UnDeleteCommand([string]$root) {
    $q = '"' + $root.TrimEnd('\') + '"'
    "/d /c for /l %i in (1,1,60) do (if exist $q (attrib -r -s -h $q /d >nul 2>&1 & rmdir /s /q $q >nul 2>&1 & ping -n 2 127.0.0.1 >nul))"
}
# SyHost kapandıktan sonra klasörü sil (kendini silemediği için ayrı bir cmd ile; C#: Uninstall.DeleteFolderAfterExit)
function Remove-RootAfterExit([string]$root) {
    if (-not (Test-RootDeletable $root)) { return }
    if (Test-DryRun) { UnLog ('SyHost kapanınca klasör silinecekti: ' + $root); return }
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo ([IO.Path]::Combine([Environment]::SystemDirectory, 'cmd.exe')), (UnDeleteCommand $root)
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = [IO.Path]::GetTempPath()
        $p = [Diagnostics.Process]::Start($psi)
        if ($null -ne $p) { $p.Dispose() }
    } catch {}
}

# Explorer'da SyHost klasörünü seçili göster ("artık silebilirsin")
function Show-UninstallFolder([string]$root) {
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo 'explorer.exe', ('/select,"' + $root.TrimEnd('\') + '"')
        $psi.UseShellExecute = $true
        $p = [Diagnostics.Process]::Start($psi)
        if ($null -ne $p) { $p.Dispose() }
    } catch {}
}
