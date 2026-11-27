# =====================================================================
#  SyHost - Kaldır (legacy\src\Uninstall.ps1) işlev testleri (Terminal sürümü)
#    powershell -NoProfile -ExecutionPolicy RemoteSigned -File tests\legacy\Test-Uninstall.ps1
#        [-WorkRoot D:\SyHostTest\uninstall\func] [-Exe dist\SyHost.exe] [-SkipFont] [-SkipCs]
#  Her şey -WorkRoot içinde olur (her çalıştırmada yeniden kurulur; "SyHostTest" adlı bir klasörün içinde olmalı).
#  Gerçek kullanıcı verisine dokunulmaz:
#    - kısayollar (SYHOST_SHORTCUT_DIR), eski veri klasörü (SYHOST_LEGACY_DATA) ve %TEMP% deneme klasörüne yönlendirilir;
#    - Program Files'taki playit, Java, C:\Windows\Fonts ve gerçek eski kurulum (%LOCALAPPDATA%\Programs\SyHost) yalnızca
#      bulunur ve deneme modunda (SYHOST_DRYRUN=1) "kaldırılır": kaldırıcıları hiç çalıştırılmaz;
#    - gerçek silme yalnızca hedefi deneme klasöründe olan satırlarla yapılır (her satır önce denetlenir);
#    - yazı tipi testi yalnızca bu kullanıcıda SyHost'un yazı tipi ve HKCU'da Cascadia kaydı yokken çalışır ve
#      yalnızca kendi kurduğunu kaldırır (-SkipFont ile atlanır);
#    - başta ve sonda gerçek yerlerin listesi alınıp karşılaştırılır.
#  Portable.ps1 henüz iskeletse kısayol ve yazı tipi işleri için C# Shortcuts/Fonts ile aynı test yedekleri kullanılır.
#  C# sürümüyle karşılaştırma: <Exe> --selftest uninstall (aynı satırları üretir; -SkipCs ile atlanır).
# =====================================================================
[CmdletBinding()]
param(
    [string]$WorkRoot = 'D:\SyHostTest\uninstall\func',
    [string]$Exe,
    [switch]$SkipFont,
    [switch]$SkipCs
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LegacyDir = Join-Path $Repo 'legacy'
$SrcDir = Join-Path $LegacyDir 'src'
if (-not $Exe) { $Exe = Join-Path $Repo 'dist\SyHost.exe' }
$Utf8 = New-Object Text.UTF8Encoding $false

# ---------- güvenlik: yalnızca deneme klasörü ----------
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\')
if (($WorkRoot + '\') -notmatch '\\SyHostTest\\.+') { throw "WorkRoot bir SyHostTest klasörünün içinde olmalı: $WorkRoot" }
function TdInside([string]$path, [string]$root) {
    $p = [IO.Path]::GetFullPath($path).TrimEnd('\') + '\'; $r = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    $p.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)
}
# cmd'yi tam olarak verilen argümanla çalıştır (PowerShell 5.1 tırnakları bozmasın)
function TdCmd([string]$arguments) {
    $psi = New-Object Diagnostics.ProcessStartInfo ([IO.Path]::Combine([Environment]::SystemDirectory, 'cmd.exe')), $arguments
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi); $p.WaitForExit(); $code = $p.ExitCode; $p.Dispose(); $code
}
function TdRemoveTree([string]$dir) {
    if (-not (TdInside $dir $WorkRoot)) { throw "deneme klasörünün dışı: $dir" }
    if ([IO.Directory]::Exists($dir)) { [void](TdCmd ('/c rmdir /s /q "' + $dir + '"')) }
}
function TdJunction([string]$link, [string]$target) { [void](TdCmd ('/c mklink /J "' + $link + '" "' + $target + '"')); if (-not [IO.Directory]::Exists($link)) { throw "bağlantı kurulamadı: $link" } }
function TdWrite([string]$path, [string]$text = 'x') { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)); [IO.File]::WriteAllText($path, $text, $Utf8) }
function TdAttr([string]$path, [IO.FileAttributes]$a) { (Get-Item -LiteralPath $path -Force).Attributes = $a }
function TdLink([string]$lnk, [string]$target, [string]$arguments) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($lnk))
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk); $s.TargetPath = $target; $s.Arguments = $arguments; $s.Save()
}
$Count = 0; $Fails = 0
function Check([bool]$ok, [string]$what) {
    $script:Count++
    if ($ok) { Write-Host ('ok    ' + $what) } else { $script:Fails++; Write-Host ('HATA  ' + $what) -ForegroundColor Red }
}
function Section([string]$s) { Write-Host ''; Write-Host "== $s" -ForegroundColor Cyan }

# ---------- gerçek yerlerin listesi (yalnızca okunur) ----------
function Get-RealSnapshot {
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($d in [IO.Path]::Combine($local, 'SyHost'), [IO.Path]::Combine($local, 'Programs\SyHost')) {
        if ([IO.Directory]::Exists($d)) {
            $n = 0; try { foreach ($e in [IO.Directory]::EnumerateFileSystemEntries($d, '*', 'AllDirectories')) { $n++ } } catch { $n = -1 }
            $lines.Add($d + '|var|' + $n + '|' + ((@([IO.Directory]::GetFileSystemEntries($d) | ForEach-Object { [IO.Path]::GetFileName($_) }) | Sort-Object) -join ','))
        } else { $lines.Add($d + '|yok') }
    }
    foreach ($l in [IO.Path]::Combine([Environment]::GetFolderPath('DesktopDirectory'), 'SyHost.lnk'), [IO.Path]::Combine([Environment]::GetFolderPath('Programs'), 'SyHost.lnk')) {
        $lines.Add($l + '|' + $(if ([IO.File]::Exists($l)) { 'var|' + [IO.File]::GetLastWriteTimeUtc($l).Ticks } else { 'yok' }))
    }
    $uf = [IO.Path]::Combine($local, 'Microsoft\Windows\Fonts')
    $lines.Add('kullanıcı yazı tipleri|' + ((@(if ([IO.Directory]::Exists($uf)) { [IO.Directory]::GetFiles($uf, '*Cascadia*') | ForEach-Object { [IO.Path]::GetFileName($_) } }) | Sort-Object) -join ','))
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts')
    $lines.Add('HKCU yazı tipleri|' + ((@(if ($k) { $k.GetValueNames() | Where-Object { $_ -like '*Cascadia*' } }) | Sort-Object) -join ','))
    if ($k) { $k.Dispose() }
    $lines.Add('Windows\Fonts|' + ((@([IO.Directory]::GetFiles([IO.Path]::Combine([Environment]::GetFolderPath('Windows'), 'Fonts'), 'Cascadia*') | ForEach-Object { [IO.Path]::GetFileName($_) }) | Sort-Object) -join ','))
    , $lines
}
$RealBefore = Get-RealSnapshot

# ---------- deneme klasörü ve ortam ----------
TdRemoveTree $WorkRoot
[void][IO.Directory]::CreateDirectory($WorkRoot)
$Temp = Join-Path $WorkRoot 'temp'; [void][IO.Directory]::CreateDirectory($Temp)
$env:SYHOST_TEST_TITLE = 'SyHostUninstallTest'
$env:SYHOST_SHORTCUT_DIR = Join-Path $WorkRoot 'shortcuts'
$env:SYHOST_LEGACY_DATA = Join-Path $WorkRoot 'legacy'
$env:SYHOST_DEFAULT_ROOT = Join-Path $WorkRoot 'defaultroot'
$env:SYHOST_DRYRUN = '1'
$env:TEMP = $Temp; $env:TMP = $Temp
$DryLog = Join-Path $Temp 'syhost-dryrun.log'

# Uninstall.ps1'in ana betikten beklediği değişkenler ve fonksiyonlar (kayıt tutan yedekler)
$AppDir = $LegacyDir
$AppRoot = Join-Path $WorkRoot 'Root'; $ExePath = Join-Path $AppRoot 'SyHost.exe'
$Data = Join-Path $AppRoot 'Data'; $PlayitToolDir = Join-Path $Data 'tools\playit'; $PlayitLegacyBin = 'C:\Program Files\playit_gg\bin'
$Servers = New-Object System.Collections.Generic.List[object]
$Screen = 'uninstall'; $Dirty = $false; $DeleteRootAfterExit = $false; $TestFrame = $null; $LangCode = 'tr'
$TdCalls = New-Object System.Collections.Generic.List[string]
# Yardımcı C# (SyHost.Core.dll): Portable.ps1'in kısayol, yol ve yazı tipi işleri onu kullanır. SyHost.ps1'deki gibi
# derlenir; arka plandaki kaldırma işi (UninstallJob.ps1) aynı süreçteki türleri kullanır.
$Bin = Join-Path $WorkRoot 'bin'; [void][IO.Directory]::CreateDirectory($Bin)
$CoreDll = Join-Path $Bin 'SyHost.Core.dll'
Add-Type -Path @(Get-ChildItem -LiteralPath $SrcDir -Filter 'SyHost.*.cs' | Sort-Object Name | ForEach-Object { $_.FullName }) -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.IO.Compression, System.IO.Compression.FileSystem -OutputAssembly $CoreDll -OutputType Library
Add-Type -Path $CoreDll
. (Join-Path $SrcDir 'Lang.ps1')
. (Join-Path $SrcDir 'Lang.Screens.ps1')
. (Join-Path $SrcDir 'Portable.ps1')
$TdFonts = @(@('CascadiaMono-Regular.ttf', 'Cascadia Mono Regular (TrueType)'), @('CascadiaMono-Bold.ttf', 'Cascadia Mono Bold (TrueType)'))
$TdFontKey = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
function TdUserFontDir { [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Microsoft\Windows\Fonts') }
. (Join-Path $SrcDir 'Uninstall.ps1')
# Ana betiğin ekran fonksiyonları yerine kayıt tutanlar; Explorer açılmasın
function Reset-Frame { $script:TdCalls.Add('Reset-Frame') }
function Stop-Playit { $script:TdCalls.Add('Stop-Playit') }
function Start-Outro { $script:TdCalls.Add('Start-Outro') }
function Show-UninstallFolder([string]$root) { $script:TdCalls.Add('Show-UninstallFolder ' + $root) }

# ---------- yardımcılar ----------
function Read-TdServers([string]$root) {
    $list = New-Object System.Collections.Generic.List[object]
    $f = [IO.Path]::Combine($root, 'Data\sunucular.json')
    if ([IO.File]::Exists($f)) {
        $all = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($sv in $all) {
            if ($null -eq $sv) { continue }
            $k = [Environment]::ExpandEnvironmentVariables([string]$sv.klasor)
            if ($k -and -not [IO.Path]::IsPathRooted($k)) { $k = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $k)) }
            $sv.klasor = $k; $list.Add($sv)
        }
    }
    , $list
}
function ItemLines($items) { @(foreach ($it in $items) { 'item|' + $it.Key + '|' + $it.Title + '|' + $it.Detail + '|' + $it.On + '|' + $it.NeedsAdmin }) }
function Find-Item($items, [string]$key) { foreach ($it in $items) { if ($it.Key -ceq $key) { return $it } }; $null }
function Wait-Job0($job, [int]$seconds, $items, $seen) {
    # İş bitene kadar bekle; $seen verilirse her satırın görülen durumlarını topla (ekranın her karede okuduğu gibi)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $job.Handle.IsCompleted -and $sw.Elapsed.TotalSeconds -lt $seconds) {
        if ($seen) { foreach ($it in $items) { [void]$seen[$it.Key].Add([int]$it.State) } }
        Start-Sleep -Milliseconds 15
    }
    $done = $job.Handle.IsCompleted
    if ($done) { try { [void]$job.PS.EndInvoke($job.Handle) } catch {} }
    $errs = @($job.PS.Streams.Error | ForEach-Object { [string]$_ })
    try { $job.PS.Dispose() } catch {}
    [pscustomobject]@{ Done = $done; Seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 2); Errors = $errs }
}
function Read-DryLog([string]$file) { @(if ([IO.File]::Exists($file)) { [IO.File]::ReadAllLines($file, [Text.Encoding]::UTF8) | ForEach-Object { if ($_.Length -gt 9) { $_.Substring(9) } else { $_ } } }) }
# Deneme modu bir gün bozulsa bile gerçek yerlere dokunulmasın: deneme klasörünün dışını gösteren satırların Run'ı silinir.
# Deneme modunda Run hiç kullanılmaz; kullanılırsa satır hata verir ve test bunu yakalar.
function Disarm($items) {
    if (-not (Test-DryRun)) { throw 'deneme modu kapalı: deneme testi çalıştırılmaz' }
    foreach ($it in $items) {
        $safe = switch -CaseSensitive ($it.Key) {
            'kisayol' { @(@(Get-ShortcutLocations) | Where-Object { -not (TdInside $_ $WorkRoot) }).Count -eq 0 }
            'eskiveri' { TdInside $it.Run.Path $WorkRoot }
            'klasor' { $true }
            default { $false }
        }
        if (-not $safe) { $it.Run = $null }
    }
}
# Gerçek silmeden önce: her satırın hedefi deneme klasöründe mi? Değilse hiçbir şey çalıştırılmaz.
$FontMine = $false
function Assert-Sandbox($items) {
    foreach ($it in $items) {
        switch -CaseSensitive ($it.Key) {
            'kisayol' { foreach ($l in @(Get-ShortcutLocations)) { if (-not (TdInside $l $WorkRoot)) { throw "kısayol deneme klasörünün dışında: $l" } } }
            'eskiveri' { if (-not (TdInside $it.Run.Path $WorkRoot)) { throw "deneme klasörünün dışı: $($it.Run.Path)" } }
            'eskikurulum' {
                if (-not (TdInside $it.Run.Path $WorkRoot)) { throw "deneme klasörünün dışı: $($it.Run.Path)" }
                foreach ($l in @(Get-ShortcutLocations)) { if (-not (TdInside $l $WorkRoot)) { throw "kısayol deneme klasörünün dışında: $l" } }
            }
            'klasor' { if (-not (TdInside $it.Detail $WorkRoot)) { throw "deneme klasörünün dışı: $($it.Detail)" } }
            'yazitipi' { if (-not $script:FontMine) { throw 'yazı tipi bu testin kurduğu değil' } }
            default { throw "gerçek çalıştırmada izin verilmeyen satır: $($it.Key)" }
        }
    }
}

# ---------- sahte SyHost klasörü, eski veri klasörü, kısayollar ----------
function New-FakeRoot([string]$root) {
    TdWrite ([IO.Path]::Combine($root, 'SyHost.exe')) 'sahte exe'
    TdWrite ([IO.Path]::Combine($root, 'Data\ayarlar.json')) '{"dil":"tr"}'
    TdWrite ([IO.Path]::Combine($root, 'Servers\Ic\world\level.dat'))
    $out = [IO.Path]::Combine($WorkRoot, 'Disarida\Dunya'); TdWrite ([IO.Path]::Combine($out, 'world\level.dat'))
    $json = '[{"id":"ic","ad":"Ic","klasor":"Servers\\Ic"},{"id":"dis","ad":"Dis","klasor":"' + $out.Replace('\', '\\') + '"}]'
    TdWrite ([IO.Path]::Combine($root, 'Data\sunucular.json')) $json
}
$Legacy = $env:SYHOST_LEGACY_DATA
$OldFake = Join-Path $WorkRoot 'OldInstall'
$Desk = [IO.Path]::Combine($env:SYHOST_SHORTCUT_DIR, 'Desktop\SyHost.lnk')
$Start = [IO.Path]::Combine($env:SYHOST_SHORTCUT_DIR, 'Programs\SyHost.lnk')
$Conhost = [IO.Path]::Combine([Environment]::SystemDirectory, 'conhost.exe')
New-FakeRoot $AppRoot
foreach ($f in 'ayarlar.json', 'sunucular.json', 'playit.toml', 'SyHost-TASINDI.txt', 'cache\SyHost.Core.dll') { TdWrite ([IO.Path]::Combine($Legacy, $f)) }
TdWrite ([IO.Path]::Combine($OldFake, 'src\SyHost.ps1'))
TdLink $Desk $Conhost ('"' + $ExePath + '" --hosted')                                                                   # bu SyHost: Ours
TdLink $Start $Conhost ('powershell.exe -File "' + $OldFake + '\src\SyHost.ps1"')   # 0.5.0 kısayolu: OtherLive
foreach ($sv in (Read-TdServers $AppRoot)) { $Servers.Add($sv) }

# =====================================================================
Section 'Bulma (deneme klasöründe)'
$items = Get-UninstallItems $AppRoot $ExePath $Servers
$keys = @($items | ForEach-Object { $_.Key })
Write-Host ('      bulunan: ' + ($keys -join ', ')) -ForegroundColor DarkGray
$order = @('kisayol', 'yazitipi', 'eskiveri', 'eskikurulum', 'eskiplayit', 'eskiyazitipi', 'java', 'klasor')
$pos = @($keys | ForEach-Object { [Array]::IndexOf($order, $_) })
$sorted = $true; for ($i = 1; $i -lt $pos.Count; $i++) { if ($pos[$i] -lt $pos[$i - 1]) { $sorted = $false } }
Check ($sorted -and -not ($pos -contains -1)) 'satırlar C# sırasında ve tanınan türlerde'
$it = Find-Item $items 'kisayol'
Check ($null -ne $it -and $it.On -and -not $it.NeedsAdmin -and $it.Detail -ceq $Desk -and $it.Title -ceq 'Masaüstü ve Başlat menüsü kısayolları') 'kisayol: yalnızca bu SyHost''u açan kısayol, seçili'
$it = Find-Item $items 'yazitipi'
Check (($null -ne $it) -eq [bool](Test-FontBySyHost)) 'yazitipi: yalnızca SyHost''un kurduğu yazı tipi varsa'
$it = Find-Item $items 'eskiveri'
Check ($null -ne $it -and -not $it.On -and -not $it.NeedsAdmin -and $it.Detail -ceq $Legacy -and $it.Title -ceq 'Eski sürümün veri klasörü') 'eskiveri: SYHOST_LEGACY_DATA klasörü, seçili değil'
$realOld = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Programs\SyHost')
$it = Find-Item $items 'eskikurulum'
Check ((($null -ne $it) -eq [IO.Directory]::Exists($realOld)) -and ($null -eq $it -or (-not $it.On -and $it.Detail -ceq $realOld -and $it.Title -ceq 'Eski sürümün program klasörü'))) 'eskikurulum: %LOCALAPPDATA%\Programs\SyHost varsa, seçili değil'
$it = Find-Item $items 'eskiplayit'
Check ($null -eq $it -or (-not $it.On -and $it.NeedsAdmin -and $it.Title -ceq 'Eski playit kurulumu (Program Files)' -and $it.Detail -like 'playit*')) 'eskiplayit: seçili değil, Windows izni ister'
$sysFont = [IO.Path]::Combine([Environment]::GetFolderPath('Windows'), 'Fonts\CascadiaMono-Regular.ttf')
$it = Find-Item $items 'eskiyazitipi'
Check ((($null -ne $it) -eq [IO.File]::Exists($sysFont)) -and ($null -eq $it -or (-not $it.On -and $it.NeedsAdmin -and $it.Detail -ceq $sysFont))) 'eskiyazitipi: C:\Windows\Fonts''taki yazı tipi, seçili değil, Windows izni ister'
$javas = @($items | Where-Object { $_.Key -ceq 'java' })
Check (@($javas | Where-Object { $_.On -or -not $_.NeedsAdmin -or $_.Title -cne 'Java (başka programlar da kullanıyor olabilir)' }).Count -eq 0) ("java: $($javas.Count) satır, hiçbiri seçili değil")
$it = Find-Item $items 'klasor'
Check ($null -ne $it -and -not $it.On -and $it.Detail -ceq $AppRoot -and $it.Title -ceq 'SyHost klasörünün kendisi') 'klasor: SyHost klasörü, seçili değil'
Check ($null -ne (Find-Item $items 'kisayol').Run -and $null -ne (Find-Item $items 'eskiveri').Run) 'satırlar ne yapılacağını taşıyor (Run)'

Section 'Bulma: korumalar'
$env:SYHOST_LEGACY_DATA = $WorkRoot
Check ($null -eq (Find-Item (Get-UninstallItems $AppRoot $ExePath $Servers) 'eskiveri')) 'eski veri klasörü SyHost klasörünü içeriyorsa önerilmez'
$env:SYHOST_LEGACY_DATA = $AppRoot
Check ($null -eq (Find-Item (Get-UninstallItems $AppRoot $ExePath $Servers) 'eskiveri')) 'eski veri klasörü SyHost klasörünün kendisiyse önerilmez'
$env:SYHOST_LEGACY_DATA = $Legacy
$srvIn = [pscustomobject]@{ id = 'eski'; ad = 'Eski'; klasor = [IO.Path]::Combine($Legacy, 'Sunucu') }
$Servers.Add($srvIn)
Check ($null -eq (Find-Item (Get-UninstallItems $AppRoot $ExePath $Servers) 'eskiveri')) 'eski veri klasöründe kayıtlı bir sunucu varsa önerilmez'
[void]$Servers.Remove($srvIn)
Check ($null -ne (Find-Item (Get-UninstallItems $AppRoot $ExePath $Servers) 'eskiveri')) 'sunucu listeden çıkınca yeniden önerilir'
$gitRoot = Join-Path $WorkRoot 'GitRoot'; [void][IO.Directory]::CreateDirectory((Join-Path $gitRoot '.git'))
Check ($null -eq (Find-Item (Get-UninstallItems $gitRoot (Join-Path $gitRoot 'SyHost.exe') $Servers) 'klasor')) 'git deposu olan SyHost klasörü önerilmez'
$drive = [IO.Path]::GetPathRoot($WorkRoot)
Check ($null -eq (Find-Item (Get-UninstallItems $drive (Join-Path $drive 'SyHost.exe') $Servers) 'klasor')) "sürücü kökü ($drive) önerilmez"
$prof = [Environment]::GetFolderPath('UserProfile')
foreach ($case in @(
        @($AppRoot, $true), @((Join-Path $prof 'SyHost'), $true), @($drive, $false), @($prof, $false), @((UnDownloads), $false),
        @([Environment]::GetFolderPath('DesktopDirectory'), $false), @([Environment]::GetFolderPath('MyDocuments'), $false), @([Environment]::GetFolderPath('Windows'), $false),
        @([Environment]::GetFolderPath('ProgramFiles'), $false), @([IO.Path]::GetDirectoryName($prof), $false), @([Environment]::GetFolderPath('LocalApplicationData'), $false), @($gitRoot, $false))) {
    Check ((Test-RootDeletable $case[0]) -eq $case[1]) ('Test-RootDeletable ' + $case[0] + ' = ' + $case[1])
}
$UnItems = New-Object System.Collections.Generic.List[object]
$UnSel = 0; $UnPhase = 'liste'
foreach ($kk in 'UpArrow', 'DownArrow', 'Spacebar') { Handle-UninstallKey (New-Object ConsoleKeyInfo ([char]0), ([ConsoleKey]$kk), $false, $false, $false) $false }
Check ($UnSel -eq 0 -and $UnPhase -ceq 'liste') 'boş listede Yukarı/Aşağı/Boşluk hata vermez'

# =====================================================================
Section 'Deneme modu: RunSelected (aynı iş parçacığında ve arka planda)'
$env:SYHOST_DRYRUN = '1'
foreach ($bg in $false, $true) {
    if ([IO.File]::Exists($DryLog)) { [IO.File]::Delete($DryLog) }
    $items = Get-UninstallItems $AppRoot $ExePath $Servers
    foreach ($it in $items) { $it.On = $true }   # Java, playit ve sistem yazı tipi dahil: deneme modunda hiçbiri çalışmaz
    Disarm $items
    $label = if ($bg) { 'arka planda' } else { 'aynı iş parçacığında' }
    if ($bg) { $r = Wait-Job0 (Start-UninstallJob $items) 120; Check ($r.Done -and $r.Errors.Count -eq 0) "iş bitti ($($r.Seconds) sn, hata kaydı yok)" }
    else { Invoke-UninstallItems $items }
    Check (@($items | Where-Object { $_.State -ne 2 -or $null -ne $_.Error }).Count -eq 0) "${label}: bütün satırlar bitti, hata yok"
    $log = Read-DryLog $DryLog
    $want = @(foreach ($it in $items) { if ($it.Key -cne 'klasor') { '[deneme] yapılacaktı: ' + $it.Key + '  ' + $it.Detail } })
    Check (($log -join "`n") -ceq ($want -join "`n")) "${label}: günlükte her satır için ""yapılacaktı"" yazıyor ($($log.Count) satır)"
    Check ([IO.File]::Exists($Desk) -and [IO.File]::Exists($Start) -and [IO.File]::Exists([IO.Path]::Combine($Legacy, 'cache\SyHost.Core.dll')) -and [IO.Directory]::Exists($AppRoot)) "${label}: hiçbir şey silinmedi"
}
if ([IO.File]::Exists($DryLog)) { [IO.File]::Delete($DryLog) }
Check ($null -eq (UnDeleteDir $Legacy) -and [IO.Directory]::Exists($Legacy)) 'deneme modunda klasör silinmez'
Remove-RootAfterExit $AppRoot @($ExePath)
Check ([IO.Directory]::Exists($AppRoot) -and [IO.File]::Exists($ExePath) -and [IO.Directory]::Exists((Join-Path $AppRoot 'Servers')) -and ((Read-DryLog $DryLog) -contains ('klasör silinecekti: ' + $Legacy)) -and ((Read-DryLog $DryLog) -contains ('SyHost kapanınca klasör silinecekti: ' + $AppRoot))) 'deneme modunda Remove-RootAfterExit yalnızca günlüğe yazar'
# Sistem yazı tipi (çalıştırılmaz): iki sürüm de SyHost.exe'yi yalnızca aynı anahtarla yönetici olarak açar;
# kaldırma kodunda PowerShell'e kodlanmış komut, gizli pencere, Base64 ya da cmd silme döngüsü yoktur
$csUn = [IO.File]::ReadAllText((Join-Path $Repo 'src\SyHost\Setup\Uninstall.cs'), [Text.Encoding]::UTF8)
$csFont = [IO.File]::ReadAllText((Join-Path $Repo 'src\SyHost\Setup\OldSystemFont.cs'), [Text.Encoding]::UTF8)
$psUn = [IO.File]::ReadAllText((Join-Path $SrcDir 'Uninstall.ps1'), [Text.Encoding]::UTF8)
$fontArg = [regex]::Match($csFont, 'const string Arg = "([^"]+)"').Groups[1].Value
Check ($fontArg -ceq '--remove-old-system-font' -and $psUn.Contains("'" + $fontArg + "'") -and $csUn.Contains('OldSystemFont.Arg')) "sistem yazı tipi: iki sürüm de SyHost.exe $fontArg ile açar (çalıştırılmadı)"
$banned = @('EncodedCommand', 'ToBase64String', 'WindowStyle Hidden', 'ProcessWindowStyle.Hidden', 'ping -n', 'rmdir /s', 'attrib -', 'cmd.exe', 'scriptblock]::Create', 'Get-ChildItem function:')
$hits = @($banned | Where-Object { $csUn.Contains($_) -or $psUn.Contains($_) })
Check ($hits.Count -eq 0) ('kaldırma kodunda kodlanmış komut, gizli pencere, metinden kod ya da cmd silme döngüsü yok' + $(if ($hits) { ': ' + ($hits -join ', ') }))
foreach ($pf in 'src\SyHost\Program.cs', 'src\SyHost.Terminal\Program.cs') {
    $t = [IO.File]::ReadAllText((Join-Path $Repo $pf), [Text.Encoding]::UTF8)
    $iArg = $t.IndexOf('OldSystemFont.Arg'); $iLock = $t.IndexOf('Mutex')
    Check ($iArg -gt 0 -and $iLock -gt $iArg) "${pf}: yönetici anahtarı tek kopya kilidinden önce işlenir"
}

# =====================================================================
Section 'Tuşlar ve UnFinish (işlev düzeyinde)'
function TdKey([string]$name) { New-Object ConsoleKeyInfo ([char]0), ([ConsoleKey]$name), $false, $false, $false }
function TdItems([bool]$folder) {
    $l = New-Object System.Collections.Generic.List[object]
    $l.Add((New-UnItem 'kisayol' 'Masaüstü ve Başlat menüsü kısayolları' 'a.lnk' $false $false @{ Exe = $ExePath }))
    $l.Add((New-UnItem 'eskiveri' 'Eski sürümün veri klasörü' $Legacy $false $false @{ Path = $Legacy }))
    $l.Add((New-UnItem 'klasor' 'SyHost klasörünün kendisi' $AppRoot $folder $false @{}))
    , $l
}
$env:SYHOST_DRYRUN = '1'
$UnItems = TdItems $false; $UnSel = 0; $UnPhase = 'liste'; $UnJob = $null; $Screen = 'uninstall'; $TdCalls.Clear()
Handle-UninstallKey (TdKey 'UpArrow') $false; Check ($UnSel -eq 2) 'Yukarı: baştan sona'
Handle-UninstallKey (TdKey 'DownArrow') $false; Check ($UnSel -eq 0) 'Aşağı: sondan başa'
Handle-UninstallKey (TdKey 'Enter') $false; Check ($UnPhase -ceq 'bitti' -and $null -eq $UnJob -and -not $DeleteRootAfterExit) 'hiçbir şey seçili değilken Enter kaldırma başlatmaz, "bitti" ekranına geçer'
$UnPhase = 'liste'
Handle-UninstallKey (TdKey 'Spacebar') $false; Check ($UnItems[0].On) 'Boşluk seçer'
Handle-UninstallKey (TdKey 'Spacebar') $false; Check (-not $UnItems[0].On) 'Boşluk bırakır'
$UnItems[2].On = $true
Handle-UninstallKey (TdKey 'Enter') $false; Check ($UnPhase -ceq 'onay' -and $null -eq $UnJob) 'klasör seçiliyken Enter önce onay ister'
Handle-UninstallKey (TdKey 'DownArrow') $false; Check ($UnPhase -ceq 'liste') 'onaydayken ok tuşu onayı kaldırır'
Handle-UninstallKey (TdKey 'Enter') $false; Handle-UninstallKey (TdKey 'Enter') $false
Check ($UnPhase -ceq 'calisiyor' -and $null -ne $UnJob -and $TdCalls.Contains('Stop-Playit') -and $PlayitHold) 'ikinci Enter kaldırmayı başlatır (playit durdurulur ve yeniden açılmaz, iş arka planda)'
$PlayitHold = $false
Handle-UninstallKey (TdKey 'Escape') $false; Check ($UnPhase -ceq 'calisiyor' -and $Screen -ceq 'uninstall') 'kaldırılırken Esc bir şey yapmaz'
$r = Wait-Job0 ([pscustomobject]@{ PS = $UnJob.PS; Handle = $UnJob.Handle }) 120
Check ($r.Done -and @($UnItems | Where-Object { $_.State -ne $(if ($_.On) { 2 } else { 4 }) }).Count -eq 0) "iş bitti; seçili satırlar bitti, ötekiler atlandı: $((@($UnItems | ForEach-Object { $_.Key + '=' + $_.State })) -join ' ')"
$UnJob = $null; $DeleteRootAfterExit = $false; $TdCalls.Clear()
UnFinish
Check ($UnPhase -ceq 'bitti' -and $DeleteRootAfterExit -and -not $TdCalls.Contains('Show-UninstallFolder ' + $AppRoot)) 'klasör seçiliyse: kapanınca silinecek, Explorer açılmaz'
Handle-UninstallKey (TdKey 'Enter') $false; Check ($TdCalls.Contains('Start-Outro')) 'bitti ekranında Enter SyHost''u kapatır'
Remove-Item env:SYHOST_DRYRUN
$UnItems = TdItems $false; $UnPhase = 'calisiyor'; $DeleteRootAfterExit = $false; $TdCalls.Clear()
UnFinish
Check ($UnPhase -ceq 'bitti' -and -not $DeleteRootAfterExit -and $TdCalls.Contains('Show-UninstallFolder ' + $AppRoot)) 'klasör seçili değilse: Explorer''da gösterilir, klasör silinmez'
$env:SYHOST_DRYRUN = '1'
$UnItems = TdItems $true; $UnSel = 0; $UnPhase = 'liste'; $UnJob = $null; $TestFrame = 'senaryo.json'
Handle-UninstallKey (TdKey 'Enter') $false; Handle-UninstallKey (TdKey 'Enter') $false
Check ($UnPhase -ceq 'calisiyor' -and $null -eq $UnJob) 'test modunda kaldırma işi başlamaz'
$TestFrame = $null
$UnItems = TdItems $false; $UnPhase = 'liste'; $Screen = 'uninstall'; $TdCalls.Clear()
Handle-UninstallKey (TdKey 'Escape') $false; Check ($Screen -ceq 'settings' -and $null -eq $UnItems -and $TdCalls.Contains('Reset-Frame')) 'Esc ayarlara döner'
$UnItems = TdItems $true; $UnPhase = 'onay'; $Screen = 'uninstall'
Handle-UninstallKey (TdKey 'Escape') $false; Check ($Screen -ceq 'settings' -and $null -eq $UnItems) 'onaydayken Esc de ayarlara döner'

# =====================================================================
Section 'Gerçek kaldırma: yalnızca deneme klasöründeki satırlar'
Remove-Item env:SYHOST_DRYRUN
$out4 = Join-Path $WorkRoot 'Outside4'; TdWrite (Join-Path $out4 'keep.txt'); TdAttr (Join-Path $out4 'keep.txt') 'Hidden, ReadOnly'
for ($d = 0; $d -lt 30; $d++) { for ($f = 0; $f -lt 100; $f++) { TdWrite ([IO.Path]::Combine($Legacy, "cok\$d\$f.dat")) } }   # canlı durumu görmek için iş biraz sürsün
TdWrite (Join-Path $Legacy 'ro.txt'); TdAttr (Join-Path $Legacy 'ro.txt') 'ReadOnly'
TdWrite (Join-Path $Legacy 'gizli.txt'); TdAttr (Join-Path $Legacy 'gizli.txt') 'Hidden, System, ReadOnly'
TdAttr (Join-Path $Legacy 'cache') 'Directory, ReadOnly, Hidden'
TdJunction (Join-Path $Legacy 'Baglanti') $out4
$items = Get-UninstallItems $AppRoot $ExePath $Servers
$run = New-Object System.Collections.Generic.List[object]
foreach ($k in 'kisayol', 'eskiveri', 'klasor') { $x = Find-Item $items $k; $x.On = $true; $run.Add($x) }
$run.Add((New-UnItem 'eskikurulum' 'Eski sürümün program klasörü' $OldFake $true $false @{ Path = $OldFake }))
Assert-Sandbox $run
$seen = @{}; foreach ($x in $run) { $seen[$x.Key] = New-Object 'System.Collections.Generic.HashSet[int]' }
$r = Wait-Job0 (Start-UninstallJob $run) 180 $run $seen
Check ($r.Done -and $r.Errors.Count -eq 0) "iş bitti ($($r.Seconds) sn)"
Check (@($run | Where-Object { $_.State -ne 2 -or $null -ne $_.Error }).Count -eq 0) ("bütün satırlar bitti: " + ((@($run | ForEach-Object { $_.Key + '=' + $_.State + $(if ($_.Error) { ' (' + $_.Error + ')' }) })) -join ' '))
Check ($seen['eskiveri'].Contains(1)) ('ekran işi canlı görür: eskiveri sürerken durum 1 (görülen: ' + ((@($seen['eskiveri']) | Sort-Object) -join ',') + ')')
Check (-not [IO.Directory]::Exists($Legacy)) 'eski veri klasörü silindi (salt okunur, gizli, sistem dosyaları dahil)'
Check ([IO.File]::Exists((Join-Path $out4 'keep.txt')) -and ((Get-Item -LiteralPath (Join-Path $out4 'keep.txt') -Force).Attributes -eq 'Hidden, ReadOnly')) 'bağlantının gösterdiği klasöre dokunulmadı (dosya ve öznitelikleri duruyor)'
Check (-not [IO.Directory]::Exists($OldFake)) 'eski program klasörü silindi'
Check (-not [IO.File]::Exists($Desk)) 'bu SyHost''un kısayolu silindi'
Check (-not [IO.File]::Exists($Start)) 'eski program klasörünü açan 0.5.0 kısayolu silindi'
Check ([IO.Directory]::Exists($AppRoot) -and [IO.File]::Exists($ExePath)) 'SyHost klasörü şimdi silinmedi (kapanınca silinir)'
Check ([IO.File]::Exists([IO.Path]::Combine($WorkRoot, 'Disarida\Dunya\world\level.dat'))) 'klasör dışındaki sunucuya dokunulmadı'

# Başka kısayollara dokunulmaz: başka bir SyHost'u açan ve SyHost'a ait olmayan kısayol durur
$other = Join-Path $WorkRoot 'Baska\SyHost.exe'; TdWrite $other
$old2 = Join-Path $WorkRoot 'OldInstall2'; TdWrite (Join-Path $old2 'src\SyHost.ps1')
TdLink $Desk $Conhost ('"' + $other + '" --hosted')
TdLink $Start ([IO.Path]::Combine([Environment]::SystemDirectory, 'notepad.exe')) ''
$run = New-Object System.Collections.Generic.List[object]
$run.Add((New-UnItem 'eskikurulum' 'Eski sürümün program klasörü' $old2 $true $false @{ Path = $old2 }))
Assert-Sandbox $run
Invoke-UninstallItems $run
Check ($run[0].State -eq 2 -and -not [IO.Directory]::Exists($old2) -and [IO.File]::Exists($Desk) -and [IO.File]::Exists($Start)) 'eski program klasörü silinirken başka SyHost''un ve yabancı kısayol durdu'
Check ((Get-LinkState $Desk $ExePath) -ceq 'OtherLive' -and (Get-LinkState $Start $ExePath) -ceq 'Foreign') 'kısayol durumları: OtherLive, Foreign'
$bad = New-UnItem 'eskiveri' 'Eski sürümün veri klasörü' 'yok' $true $false @{ Path = (Join-Path $WorkRoot 'Kilitli') }
TdWrite (Join-Path $WorkRoot 'Kilitli\acik.dat'); $fs = [IO.File]::Open((Join-Path $WorkRoot 'Kilitli\acik.dat'), 'Open', 'ReadWrite', 'None')
try { Assert-Sandbox @($bad); Invoke-UninstallItems @($bad) } finally { $fs.Dispose() }
Check ($bad.State -eq 3 -and $bad.Error -and $bad.Error -notmatch 'Exception calling') ("silinemeyen klasör hata olarak gösterilir: " + $bad.Error)
$scnDir = Join-Path $WorkRoot 'SenaryoDetay'; TdWrite (Join-Path $scnDir 'duruyor.txt')
$scn = [pscustomobject]@{ Key = 'eskiveri'; Title = 'Eski sürümün veri klasörü'; Detail = $scnDir; On = $true; NeedsAdmin = $false; State = 0; Error = $null }
Invoke-UninstallItems @($scn)
Check ($scn.State -eq 3 -and [IO.File]::Exists((Join-Path $scnDir 'duruyor.txt'))) 'test senaryosundaki satır (Run yok) ayrıntıdaki yola dokunmaz, hata verir'
$env:SYHOST_DRYRUN = '1'

# =====================================================================
Section 'Yazı tipi: testin kendi kurduğu kullanıcı yazı tipi'
$ufd = TdUserFontDir
$pre = (@(if ([IO.Directory]::Exists($ufd)) { [IO.Directory]::GetFiles($ufd, 'SyHost-Cascadia*') }).Count -eq 0)
$hk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($TdFontKey)
if ($hk) { foreach ($f in $TdFonts) { if ($null -ne $hk.GetValue($f[1])) { $pre = $false } }; $hk.Dispose() }
if ($SkipFont) { Write-Host 'atlandı (-SkipFont)' -ForegroundColor Yellow }
elseif (-not $pre) { Write-Host 'atlandı: bu kullanıcıda zaten SyHost yazı tipi ya da HKCU Cascadia kaydı var (gerçek kurulum olabilir; dokunulmaz)' -ForegroundColor Yellow }
else {
    try {
        $FontMine = $true
        Check ([bool](@(Install-FontPerUser)[-1])) 'yazı tipi bu kullanıcıya kuruldu (deneme)'
        Check ([bool](Test-FontBySyHost)) 'Test-FontBySyHost: var'
        $items = Get-UninstallItems $AppRoot $ExePath $Servers
        $it = Find-Item $items 'yazitipi'
        Check ($null -ne $it -and $it.On -and -not $it.NeedsAdmin -and $it.Detail -ceq $ufd -and $it.Title -ceq 'SyHost''un kurduğu Cascadia Mono yazı tipi') 'yazitipi bulundu, seçili, ayrıntı kullanıcı yazı tipi klasörü'
        Remove-Item env:SYHOST_DRYRUN
        $run = New-Object System.Collections.Generic.List[object]; $run.Add($it)
        Assert-Sandbox $run
        $r = Wait-Job0 (Start-UninstallJob $run) 60
        Check ($r.Done -and $it.State -eq 2 -and $null -eq $it.Error) ("arka planda kaldırıldı: durum $($it.State) $($it.Error)")
        $left = @([IO.Directory]::GetFiles($ufd, 'SyHost-Cascadia*'))
        $hk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($TdFontKey); $vals = @(if ($hk) { foreach ($f in $TdFonts) { if ($null -ne $hk.GetValue($f[1])) { $f[1] } }; $hk.Dispose() })
        Check ($left.Count -eq 0 -and $vals.Count -eq 0 -and -not (Test-FontBySyHost)) 'dosyalar ve HKCU kayıtları gitti'
        Check ($null -eq (Find-Item (Get-UninstallItems $AppRoot $ExePath $Servers) 'yazitipi')) 'artık listede yok'
    } finally {
        $env:SYHOST_DRYRUN = '1'
        # Ne olursa olsun testin kurduğu her şeyi kaldır
        if (@([IO.Directory]::GetFiles($ufd, 'SyHost-Cascadia*')).Count -gt 0) { [void](Uninstall-FontPerUser) }
        $FontMine = $false
    }
}

# =====================================================================
Section 'Remove-RootAfterExit: SyHost kapanırken klasörün içini bu süreçte siler'
Remove-Item env:SYHOST_DRYRUN
$gone = Join-Path $WorkRoot 'gone\SyHost Kök'
$outside = Join-Path $WorkRoot 'gone-outside'; TdWrite (Join-Path $outside 'keep.txt'); TdAttr (Join-Path $outside 'keep.txt') 'Hidden, ReadOnly'
$sibling = Join-Path $WorkRoot 'gone\diger\SyHost Kök'; [void][IO.Directory]::CreateDirectory($sibling); TdAttr $sibling 'Directory, Hidden'
New-FakeRoot $gone
TdWrite (Join-Path $gone 'App\bin\SyHost.Core.dll'); TdWrite (Join-Path $gone 'App\src\SyHost.ps1')
TdWrite (Join-Path $gone 'Data\kilit.dat'); TdWrite (Join-Path $gone 'Data\ro.txt'); TdAttr (Join-Path $gone 'Data\ro.txt') 'ReadOnly, Hidden, System'
TdWrite (Join-Path $gone 'desktop.ini') "[.ShellClassInfo]`r`n"; TdAttr (Join-Path $gone 'desktop.ini') 'Hidden, System'
TdWrite (Join-Path $gone 'Servers\Ic\world\region\r.0.0.mca')
TdAttr (Join-Path $gone 'Data') 'Directory, Hidden'; TdAttr $gone 'Directory, ReadOnly, System'
TdJunction (Join-Path $gone 'Servers\Disarida') $outside
# Kapanmakta olan SyHost: başlatıcı exe ve App (yüklü SyHost.Core.dll) saklanır; Data'daki bir dosya da açık kalır
$here = (Get-Location).Path
$procsBefore = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
$fs = [IO.File]::Open((Join-Path $gone 'Data\kilit.dat'), 'Open', 'ReadWrite', 'None')
$sw = [Diagnostics.Stopwatch]::StartNew()
try { Remove-RootAfterExit $gone @((Join-Path $gone 'SyHost.exe'), (Join-Path $gone 'App')) } finally { $fs.Dispose(); Set-Location -LiteralPath $here; [Environment]::CurrentDirectory = $here }
$secs = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
$spawned = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $procsBefore -notcontains $_.Id -and $_.ProcessName -in 'cmd', 'powershell', 'pwsh', 'conhost' })
Check ($spawned.Count -eq 0) ('yardımcı süreç başlatılmadı (cmd ya da PowerShell yok)' + $(if ($spawned) { ': ' + (($spawned | ForEach-Object { $_.ProcessName }) -join ', ') }))
Check ([IO.File]::Exists((Join-Path $gone 'SyHost.exe')) -and [IO.File]::Exists((Join-Path $gone 'App\bin\SyHost.Core.dll'))) 'saklananlar kaldı: SyHost.exe ve App'
Check (-not [IO.Directory]::Exists((Join-Path $gone 'Servers')) -and -not [IO.File]::Exists((Join-Path $gone 'desktop.ini')) -and -not [IO.File]::Exists((Join-Path $gone 'Data\ro.txt')) -and -not [IO.File]::Exists((Join-Path $gone 'Data\ayarlar.json'))) 'sunucular, desktop.ini ve salt okunur/gizli/sistem dosyaları silindi'
Check ([IO.File]::Exists((Join-Path $gone 'Data\kilit.dat')) -and $secs -ge 3 -and $secs -lt 20) "kullanımdaki dosya hata değil: bir süre denendi ($secs sn) ve kaldı (kullanıcı Explorer'dan siler)"
Check (((Get-Item -LiteralPath $gone -Force).Attributes -band ([IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::System)) -eq 0) 'SyHost klasörünün salt okunur ve sistem özniteliği kaldırıldı'
Check ([IO.File]::Exists((Join-Path $outside 'keep.txt')) -and ((Get-Item -LiteralPath (Join-Path $outside 'keep.txt') -Force).Attributes -eq 'Hidden, ReadOnly')) 'bağlantının gösterdiği klasöre dokunulmadı (dosya ve öznitelikleri duruyor)'
Check ([IO.Directory]::Exists($sibling) -and ((Get-Item -LiteralPath $sibling -Force).Attributes -band [IO.FileAttributes]::Hidden)) 'başka yerdeki aynı adlı klasörün özniteliklerine dokunulmadı'
$git2 = Join-Path $WorkRoot 'gone\GitKok'; [void][IO.Directory]::CreateDirectory((Join-Path $git2 '.git')); TdWrite (Join-Path $git2 'SyHost.exe'); TdWrite (Join-Path $git2 'Data\ayarlar.json')
Remove-RootAfterExit $git2 @((Join-Path $git2 'SyHost.exe'))
Set-Location -LiteralPath $here; [Environment]::CurrentDirectory = $here
Check ([IO.File]::Exists((Join-Path $git2 'Data\ayarlar.json'))) 'git deposu olan klasörün içine dokunulmaz'
$env:SYHOST_DRYRUN = '1'

# =====================================================================
Section 'C# sürümüyle karşılaştırma (SyHost.exe --selftest uninstall)'
if ($SkipCs) { Write-Host 'atlandı (-SkipCs)' -ForegroundColor Yellow }
elseif (-not [IO.File]::Exists($Exe)) { Check $false "C# sürümü yok: $Exe" }
else {
    # Aynı başlangıç: eski veri klasörü, iki kısayol (biri bu SyHost'un)
    foreach ($f in 'ayarlar.json', 'sunucular.json', 'playit.toml') { TdWrite ([IO.Path]::Combine($Legacy, $f)) }
    TdLink $Desk $Conhost ('"' + $ExePath + '" --hosted')
    TdLink $Start $Conhost ('powershell.exe -File "' + $OldFake + '\src\SyHost.ps1"')
    $csDel = Join-Path $WorkRoot 'cs-sil'; $csOut = Join-Path $WorkRoot 'cs-outside'
    TdWrite (Join-Path $csDel 'syhost-selftest-sil.txt'); TdWrite (Join-Path $csDel 'alt\ro.txt'); TdAttr (Join-Path $csDel 'alt\ro.txt') 'ReadOnly, Hidden, System'
    TdWrite (Join-Path $csOut 'keep.txt'); TdJunction (Join-Path $csDel 'Baglanti') $csOut
    $tCs = Join-Path $WorkRoot 'temp-cs'; $tPs = Join-Path $WorkRoot 'temp-ps'; [void][IO.Directory]::CreateDirectory($tCs); [void][IO.Directory]::CreateDirectory($tPs)
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe, ('--selftest uninstall "' + $AppRoot + '" "' + $csDel + '"')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.StandardOutputEncoding = $Utf8
    $psi.EnvironmentVariables['SYHOST_DRYRUN'] = '1'; $psi.EnvironmentVariables['TEMP'] = $tCs; $psi.EnvironmentVariables['TMP'] = $tCs
    $cp = [Diagnostics.Process]::Start($psi); $csText = $cp.StandardOutput.ReadToEnd(); $cp.WaitForExit()
    $csLines = @($csText -split "`r?`n" | Where-Object { $_ })
    Check ($cp.ExitCode -eq 0) "C# öz denetimi çalıştı (çıkış kodu $($cp.ExitCode))"
    Check (($csLines -contains 'sil|silindi|') -and [IO.File]::Exists((Join-Path $csOut 'keep.txt'))) 'C# DeleteDir: klasörü sildi, bağlantının gösterdiği yere dokunmadı'
    # Terminal sürümü aynı satırları üretir
    $env:TEMP = $tPs; $env:TMP = $tPs
    $psLines = New-Object System.Collections.Generic.List[string]
    $servers2 = Read-TdServers $AppRoot
    $items = Get-UninstallItems $AppRoot $ExePath $servers2
    foreach ($l in (ItemLines $items)) { $psLines.Add($l) }
    foreach ($it in $items) { $it.On = $true }
    Disarm $items
    Invoke-UninstallItems $items
    foreach ($it in $items) { $psLines.Add('run|' + $it.Key + '|' + $it.State + '|' + $it.Error) }
    foreach ($pp in @($AppRoot, [IO.Path]::GetDirectoryName($AppRoot), [IO.Path]::GetPathRoot($AppRoot), $prof, [IO.Path]::Combine($prof, 'SyHost'), (UnDownloads),
            [Environment]::GetFolderPath('DesktopDirectory'), [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('ProgramFiles'), [Environment]::GetFolderPath('Windows'), [IO.Path]::GetDirectoryName($prof))) {
        $psLines.Add('candelete|' + $pp + '|' + (Test-RootDeletable $pp))
    }
    # Kaldırıcı komutları yalnızca ayrıştırılır, çalıştırılmaz: kayıt defterindekiler ve C# öz denetimindeki örnekler
    $cmds = @(@(UnFindMsi @('playit', 'Microsoft Build of OpenJDK', 'Eclipse Temurin JRE with Hotspot 8')) | ForEach-Object { $_.Uninstall })
    $cmds += @('MsiExec.exe /I{11111111-2222-3333-4444-555555555555}', '  msiexec.exe /i {AAAA} /qn  ', 'MsiExec.exe /X{BBBB}',
        '"C:\Program Files\Deneme App\unins000.exe" /SILENT', 'C:\Deneme\uninstall.exe /S /D=x', 'C:\Deneme\uninstall.exe', '"C:\Kapanmayan tırnak')
    foreach ($c in $cmds) { try { $fa = @(UnUninstallerCommand $c); $psLines.Add('uninst|' + $c + '|' + $fa[0] + '|' + $fa[1]) } catch { $psLines.Add('uninst|' + $c + '|HATA') } }
    $msiexec = [IO.Path]::Combine([Environment]::SystemDirectory, 'msiexec.exe')
    Check (@($psLines | Where-Object { $_ -like 'uninst|MsiExec.exe /I{*' -and $_ -notlike ('*|' + $msiexec + '|/X{*} /qb') }).Count -eq 0) "MSI kaldırıcısı: MsiExec.exe /I{GUID} -> $msiexec /X{GUID} /qb (tam yoluyla)"
    Remove-RootAfterExit $AppRoot @($ExePath)
    $env:TEMP = $Temp; $env:TMP = $Temp
    $csCmp = @($csLines | Where-Object { -not $_.StartsWith('sil|') })
    $diffAt = -1; for ($i = 0; $i -lt [Math]::Max($csCmp.Count, $psLines.Count); $i++) { if ($i -ge $csCmp.Count -or $i -ge $psLines.Count -or $csCmp[$i] -cne $psLines[$i]) { $diffAt = $i; break } }
    Check ($diffAt -lt 0) ("bulma, deneme çalıştırması, silinebilirlik ve kaldırıcı komutları iki sürümde aynı ($($psLines.Count) satır)" + $(if ($diffAt -ge 0) { "`n      C#      : " + $(if ($diffAt -lt $csCmp.Count) { $csCmp[$diffAt] } else { '(yok)' }) + "`n      Terminal: " + $(if ($diffAt -lt $psLines.Count) { $psLines[$diffAt] } else { '(yok)' }) } else { '' }))
    $lc = Read-DryLog (Join-Path $tCs 'syhost-dryrun.log'); $lp = Read-DryLog (Join-Path $tPs 'syhost-dryrun.log')
    Check (($lc -join "`n") -ceq ($lp -join "`n") -and $lc.Count -gt 0) "deneme günlüğü iki sürümde aynı ($($lc.Count) satır)"
    foreach ($l in $psLines) { if ($l.StartsWith('item|')) { Write-Host ('      ' + $l) -ForegroundColor DarkGray } }
}

# =====================================================================
Section 'Gerçek yerler değişmedi mi?'
$RealAfter = Get-RealSnapshot
for ($i = 0; $i -lt $RealBefore.Count; $i++) { Check ($RealBefore[$i] -ceq $RealAfter[$i]) ('aynı: ' + $RealBefore[$i]) }

Write-Host ''
if ($Fails -eq 0) { Write-Host "SONUÇ: $Count denetim, hepsi geçti" -ForegroundColor Green } else { Write-Host "SONUÇ: $Count denetim, $Fails hata" -ForegroundColor Red }
exit $(if ($Fails) { 1 } else { 0 })
