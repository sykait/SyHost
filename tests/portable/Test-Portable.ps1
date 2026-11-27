# =====================================================================
#  SyHost - Terminal sürümünün taşınabilir arka ucu: işlev testleri
#  legacy\src\Portable.ps1, legacy\src\SyHost.Setup.cs ve SyHost.ps1'deki $JavaFuncs ile açılıştaki yazma denetimi.
#
#    tests\portable\Test-Portable.ps1                         hızlı testler (hepsi WorkRoot içinde)
#    ... -CsExe dist\SyHost.exe                               C# sürümünün --selftest / --frame çıktısıyla karşılaştır
#    ... -Windows                                             klasör seçiciyi ve uyarıyı gizli bir konsolda gerçekten açıp kapatır
#    ... -Font                                                yazı tipini BU KULLANICIYA gerçekten kurar ve hemen kaldırır
#    ... -Java                                                Java 17'yi WorkRoot\Data'ya gerçekten indirir (~45 MB, iki kez)
#
#  Gerçek kullanıcı verisine dokunmaz: kısayollar (SYHOST_SHORTCUT_DIR), eski veri (SYHOST_LEGACY_DATA) ve
#  varsayılan kurulum yeri (SYHOST_DEFAULT_ROOT) WorkRoot'a yönlendirilir; değişkenler yalnızca bu süreçte geçerlidir.
#  -Font tek istisnadır: HKCU yazı tipi kaydı ve %LOCALAPPDATA%\Microsoft\Windows\Fonts (sonunda her durumda kaldırılır).
# =====================================================================
[CmdletBinding()]
param(
    [string]$WorkRoot = 'D:\SyHostTest\portable\harness',
    [string]$CsExe,
    [switch]$Windows,
    [switch]$Font,
    [switch]$Java
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SrcDir = Join-Path $Repo 'legacy\src'
if ($CsExe) { $CsExe = (Resolve-Path $CsExe).Path }

# ---------- test klasörü ve ortam (yalnızca bu süreç) ----------
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
if ($WorkRoot.TrimEnd('\').Length -lt 8) { throw "WorkRoot çok kısa: $WorkRoot" }
function Clear-Dir([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return }
    # desktop.ini klasörleri salt okunur, ini dosyaları gizli+sistem: önce öznitelikleri temizle
    foreach ($i in @(Get-ChildItem -LiteralPath $dir -Recurse -Force)) { try { $i.Attributes = 'Normal' } catch {} }
    Remove-Item -LiteralPath $dir -Recurse -Force
}
Clear-Dir $WorkRoot
New-Item -ItemType Directory -Force $WorkRoot | Out-Null
$env:SYHOST_SHORTCUT_DIR = Join-Path $WorkRoot 'shortcuts'
$env:SYHOST_DEFAULT_ROOT = Join-Path $WorkRoot 'defaultroot'
$env:SYHOST_LEGACY_DATA = Join-Path $WorkRoot 'legacy'
$env:SYHOST_DRYRUN = '1'
$env:SYHOST_TEST_TITLE = 'SyHostPortableTest'

$script:Pass = 0; $script:Fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { $script:Pass++; Write-Host "ok    $what" }
    else { $script:Fail++; Write-Host "HATA  $what" -ForegroundColor Red }
}
function Section([string]$t) { Write-Host ''; Write-Host "---------- $t ----------" -ForegroundColor Cyan }
function Hex([byte[]]$b) { ($b | ForEach-Object { $_.ToString('x2') }) -join ' ' }
$Utf8NoBom = New-Object Text.UTF8Encoding $false

# ---------- uygulamanın kendi kodunu yükle ----------
# Yardımcı C# (SyHost.*.cs) SyHost.ps1'deki gibi derlenir (C# 5, .NET Framework derleyicisi)
$Bin = Join-Path $WorkRoot 'bin'; New-Item -ItemType Directory -Force $Bin | Out-Null
$CoreDll = Join-Path $Bin 'SyHost.Core.dll'
Add-Type -Path @(Get-ChildItem -LiteralPath $SrcDir -Filter 'SyHost.*.cs' | Sort-Object Name | ForEach-Object { $_.FullName }) -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.IO.Compression, System.IO.Compression.FileSystem -OutputAssembly $CoreDll -OutputType Library
Add-Type -Path $CoreDll
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.IO.Compression.FileSystem

# SyHost.ps1'in değişkenleri (Use-Root her test kökü için yeniden kurar)
$AppDir = Join-Path $Repo 'legacy'
$DefaultCfgFile = Join-Path $AppDir 'config\default-settings.json'
$TestFrame = $null; $SetupMode = $false
$Servers = New-Object System.Collections.Generic.List[object]
$HomeMsg = ''; $HomeMsgUntil = [DateTime]::MinValue; $Dirty = $false
$NextAfterSplash = 'home'; $FrMigrated = $null; $FrMovedTo = $null
function Use-Root([string]$root) {
    $script:AppRoot = [IO.Path]::GetFullPath($root)
    $script:Data = Join-Path $script:AppRoot 'Data'
    $script:ExePath = Join-Path $script:AppRoot 'SyHost.exe'
    $script:CfgFile = Join-Path $script:Data 'ayarlar.json'
    $script:ServersFile = Join-Path $script:Data 'sunucular.json'
    $script:WinFile = Join-Path $script:Data 'pencere.json'
    $script:PlayitSecret = Join-Path $script:Data 'playit.toml'
    $script:PlayitToolDir = Join-Path $script:Data 'tools\playit'
    $script:DataDir = $script:Data
    $script:FrMigrated = $null; $script:FrMovedTo = $null; $script:NextAfterSplash = 'home'; $script:HomeMsg = ''
}
Use-Root (Join-Path $WorkRoot 'root')
$PlayitLegacyBin = Join-Path $WorkRoot 'programfiles\playit_gg\bin'

# Dil tabloları ve Portable.ps1 (SyHost.ps1'deki sırayla)
. (Join-Path $SrcDir 'Lang.ps1')
. (Join-Path $SrcDir 'Lang.Screens.ps1')
$LangCode = 'tr'
. (Join-Path $SrcDir 'Portable.ps1')

# SyHost.ps1'den gerekenler: ayar/sunucu işlevleri, $JavaFuncs ve açılıştaki yazma denetimi (betiği çalıştırmadan, AST ile)
$MainAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $SrcDir 'SyHost.ps1'), [ref]$null, [ref]$null)
$CoreFuncs = 'Write-TextFile', 'Read-DefaultSettings', 'Resolve-RootDir', 'ConvertTo-StoredPath', 'ConvertFrom-StoredPath', 'Load-Config', 'Save-Config', 'Load-Servers', 'Save-Servers', 'Home-Msg'
$WriteCheckText = $null
foreach ($st in $MainAst.EndBlock.Statements) {
    if ($st -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $CoreFuncs -contains $st.Name) { . ([scriptblock]::Create($st.Extent.Text)) }
    elseif ($st -is [System.Management.Automation.Language.AssignmentStatementAst] -and @('$CfgDefaults', '$PackKeys', '$JavaFuncs') -contains $st.Left.Extent.Text) { . ([scriptblock]::Create($st.Extent.Text)) }
    elseif ($st -is [System.Management.Automation.Language.IfStatementAst] -and $st.Extent.Text -like '*Test-CanWrite $Data*') { $WriteCheckText = $st.Extent.Text }
}
. $JavaFuncs
Check ($null -ne (Get-Command Install-Java -ErrorAction SilentlyContinue) -and $null -ne (Get-Command Load-Config -ErrorAction SilentlyContinue)) 'SyHost.ps1: $JavaFuncs ve ayar işlevleri yüklendi'
Check ($null -ne $WriteCheckText) 'SyHost.ps1: açılıştaki yazma denetimi bulundu'
Check ($null -eq (Get-Command Remove-RootAfterExit -ErrorAction SilentlyContinue)) 'Portable.ps1: Remove-RootAfterExit yok (Uninstall.ps1 sağlar)'
Check ($null -eq (Get-Command Get-JavaWingetId -ErrorAction SilentlyContinue)) '$JavaFuncs: winget kalmadı'

# Test için küçük exe'ler: uzun süre çalışan (kilitli exe) ve ürün adı "playit-cli" olan
$Sleeper = Join-Path $Bin 'Sleeper.exe'
Add-Type -TypeDefinition 'public static class SleeperMain { public static void Main() { System.Threading.Thread.Sleep(30000); } }' -OutputAssembly $Sleeper -OutputType ConsoleApplication
$FakeCli = Join-Path $Bin 'PlayitCli.exe'
Add-Type -TypeDefinition '[assembly: System.Reflection.AssemblyProduct("playit-cli")] public static class CliMain { public static void Main() { } }' -OutputAssembly $FakeCli -OutputType ConsoleApplication

# C# sürümünü bir test klasöründe çalıştır (gerçek LOCALAPPDATA'ya da dokunmasın).
# --selftest çıktısı konsolun OEM kod sayfasında (437'de "ı" -> "i"): Türkçe harfler eşleşmede joker sayılır (CsRx).
Add-Type -Namespace SyHostTest -Name Cp -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint GetOEMCP();'
$OemEnc = [Text.Encoding]::GetEncoding([int][SyHostTest.Cp]::GetOEMCP())
function CsRx([string]$s) { ($s.ToCharArray() | ForEach-Object { if ([int]$_ -gt 127) { '.' } else { [regex]::Escape([string]$_) } }) -join '' }
function Invoke-Cs([string[]]$arguments, [string]$exe = $CsExe) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = (($arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $OemEnc; $psi.StandardErrorEncoding = $OemEnc
    $psi.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $WorkRoot 'cs-localappdata'
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(60000)) { $p.Kill(); throw 'C# sürümü bitmedi' }
    [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result + $e.Result }
}

# =====================================================================
Section 'Yollar ve kararlar (Portable.cs)'
Check ((Get-DefaultRoot) -eq $env:SYHOST_DEFAULT_ROOT) "Get-DefaultRoot test yerini verir: $(Get-DefaultRoot)"
$saved = $env:SYHOST_DEFAULT_ROOT; $env:SYHOST_DEFAULT_ROOT = $null
Check ((Get-DefaultRoot) -eq (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'SyHost')) "Get-DefaultRoot değişken yoksa kullanıcı klasörü\SyHost: $(Get-DefaultRoot)"
$env:SYHOST_DEFAULT_ROOT = $saved
Check ((Get-LegacyDir) -eq $env:SYHOST_LEGACY_DATA) 'Get-LegacyDir test yerini verir'
$saved = $env:SYHOST_LEGACY_DATA; $env:SYHOST_LEGACY_DATA = $null
Check ((Get-LegacyDir) -eq (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'SyHost')) 'Get-LegacyDir değişken yoksa %LOCALAPPDATA%\SyHost (yalnızca yol, dokunulmaz)'
$env:SYHOST_LEGACY_DATA = $saved
$ui = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
Check ((Get-UiLanguage) -ceq $(if ($ui -eq 'tr' -or $ui -eq 'ja') { $ui } else { 'en' })) "Get-UiLanguage: $(Get-UiLanguage) (Windows: $ui)"
Check (Test-DryRun) 'Test-DryRun: SYHOST_DRYRUN=1'
$env:SYHOST_DRYRUN = '0'; Check (-not (Test-DryRun)) 'Test-DryRun: 0 iken kapalı'; $env:SYHOST_DRYRUN = '1'
$locs = @(Get-ShortcutLocations)
Check ($locs.Count -eq 2 -and $locs[0] -eq (Join-Path $env:SYHOST_SHORTCUT_DIR 'Desktop\SyHost.lnk') -and $locs[1] -eq (Join-Path $env:SYHOST_SHORTCUT_DIR 'Programs\SyHost.lnk')) 'Get-ShortcutLocations test klasörünü gösterir'

# Test-Inside
$r0 = Join-Path $WorkRoot 'root'
Check (Test-Inside $r0 $r0) 'Test-Inside: klasörün kendisi içinde sayılır'
Check (Test-Inside "$r0\Servers\A" "$r0\") 'Test-Inside: alt klasör (kökün sonunda \ olsa da)'
Check (Test-Inside "$($r0.ToUpper())\X" $r0) 'Test-Inside: büyük-küçük harf farkı önemsiz'
Check (-not (Test-Inside "$r0-2\X" $r0)) 'Test-Inside: aynı adla başlayan komşu klasör içinde değil'
Check (-not (Test-Inside '' $r0)) 'Test-Inside: boş yol içinde değil'
Check (-not (Test-Inside 'C:\a|b' $r0)) 'Test-Inside: geçersiz yol içinde değil'

# OneDrive
Check (Test-InOneDrive 'C:\Users\x\OneDrive - Contoso\SyHost') 'Test-InOneDrive: "OneDrive - Şirket" klasörü'
Check (Test-InOneDrive 'D:\Yedek\OneDrive\SyHost') 'Test-InOneDrive: yol içinde \OneDrive\'
Check (-not (Test-InOneDrive 'D:\OneDriveYedek\SyHost')) 'Test-InOneDrive: OneDriveYedek OneDrive değil'
Check (-not (Test-InOneDrive $WorkRoot)) "Test-InOneDrive: test klasörü değil"
$od = Join-Path $WorkRoot 'od'
$savedOd = $env:OneDriveCommercial; $env:OneDriveCommercial = $od
Check (Test-InOneDrive "$od\Sub\SyHost") 'Test-InOneDrive: OneDriveCommercial ortam değişkeninin altı'
Check (-not (Test-InOneDrive "$od-2\SyHost")) 'Test-InOneDrive: aynı adla başlayan komşu klasör değil'
$env:OneDriveCommercial = $savedOd
Check (-not (Test-InOneDrive '')) 'Test-InOneDrive: boş yol hayır'

# Kendi boş klasörü mü?
$own = Join-Path $WorkRoot 'own'; New-Item -ItemType Directory -Force $own | Out-Null
$ownExe = Join-Path $own 'SyHost.exe'; [IO.File]::WriteAllText($ownExe, 'x')
Check (Test-OwnEmptyFolder $own $ownExe) 'Test-OwnEmptyFolder: yalnızca exe varsa evet'
[IO.File]::WriteAllText((Join-Path $own 'desktop.ini'), 'x'); [IO.File]::WriteAllText((Join-Path $own 'Thumbs.db'), 'x')
Check (Test-OwnEmptyFolder "$own\" $ownExe) 'Test-OwnEmptyFolder: desktop.ini ve Thumbs.db sayılmaz'
[IO.File]::WriteAllText((Join-Path $own 'baska.txt'), 'x')
Check (-not (Test-OwnEmptyFolder $own $ownExe)) 'Test-OwnEmptyFolder: başka dosya varsa hayır'
New-Item -ItemType Directory -Force (Join-Path $WorkRoot 'own2\Data') | Out-Null
Check (-not (Test-OwnEmptyFolder (Join-Path $WorkRoot 'own2') (Join-Path $WorkRoot 'own2\SyHost.exe'))) 'Test-OwnEmptyFolder: alt klasör varsa hayır'
Check (-not (Test-OwnEmptyFolder 'D:\' 'D:\SyHost.exe')) 'Test-OwnEmptyFolder: sürücü kökü hayır'
foreach ($sf in 'UserProfile', 'DesktopDirectory', 'MyDocuments', 'ProgramFiles') {
    $p = [Environment]::GetFolderPath($sf)
    Check (-not (Test-OwnEmptyFolder $p (Join-Path $p 'SyHost.exe'))) "Test-OwnEmptyFolder: $sf hayır ($p)"
}
$dl = Get-Downloads
Check ($dl -and (Test-Path -LiteralPath $dl)) "Get-Downloads: $dl"
Check (-not (Test-OwnEmptyFolder $dl (Join-Path $dl 'SyHost.exe'))) 'Test-OwnEmptyFolder: İndirilenler hayır'
Check (-not (Test-OwnEmptyFolder (Join-Path $WorkRoot 'yok') 'x')) 'Test-OwnEmptyFolder: olmayan klasör hayır'

# Yazılabilir mi?
$cw = Join-Path $WorkRoot 'canwrite\new\deep'
Check (Test-CanWrite $cw) 'Test-CanWrite: olmayan klasörü açar ve yazar'
Check (@(Get-ChildItem -LiteralPath $cw -Force).Count -eq 0) 'Test-CanWrite: deneme dosyası kalmaz'
Check (-not (Test-CanWrite 'C:\Program Files\SyHostDeneme') -and -not (Test-Path 'C:\Program Files\SyHostDeneme')) 'Test-CanWrite: Program Files hayır (yönetici değil)'
$ro = Join-Path $WorkRoot 'readonly'; New-Item -ItemType Directory -Force $ro | Out-Null
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $ro /deny "${me}:(OI)(CI)(W)" | Out-Null
try {
    Check (-not (Test-CanWrite $ro)) 'Test-CanWrite: yazma izni olmayan klasör hayır (icacls deny W)'
    Check (-not (Test-CanWrite (Join-Path $ro 'Data'))) 'Test-CanWrite: yazılamayan klasörün altı da hayır'
} finally { & icacls.exe $ro /remove:d $me | Out-Null }
Check (Test-CanWrite $ro) 'Test-CanWrite: izin geri gelince evet'
Check (-not (Test-CanWrite '')) 'Test-CanWrite: boş yol hayır'

# Açılıştaki yazma denetimi (SyHost.ps1): Data'ya yazılamıyorsa uyarı ve çıkış kodu 1 (uyarı penceresi yerine dosyaya yazılır)
$wcRoot = Join-Path $WorkRoot 'writecheck'; $wcData = Join-Path $wcRoot 'Data'; New-Item -ItemType Directory -Force $wcData | Out-Null
$wcScript = Join-Path $WorkRoot 'writecheck.ps1'; $wcOut = Join-Path $WorkRoot 'writecheck.txt'
$wcBody = @"
`$ErrorActionPreference = 'Stop'
Add-Type -Path '$CoreDll'
. '$SrcDir\Lang.ps1'; . '$SrcDir\Lang.Screens.ps1'
`$AppDir = '$AppDir'; `$TestFrame = `$null; `$SetupMode = `$false
. '$SrcDir\Portable.ps1'
function Show-Alert([string]`$text) { [IO.File]::WriteAllText('$wcOut', `$text, (New-Object Text.UTF8Encoding `$false)) }
`$AppRoot = '$wcRoot'; `$Data = '$wcData'
$WriteCheckText
'ulaşıldı' | Out-File '$wcOut.reached'
exit 0
"@
[IO.File]::WriteAllText($wcScript, $wcBody, (New-Object Text.UTF8Encoding $true))
& icacls.exe $wcData /deny "${me}:(OI)(CI)(W)" | Out-Null
try {
    $p = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$wcScript`"" -WindowStyle Hidden -PassThru -Wait
    $alert = if (Test-Path $wcOut) { [IO.File]::ReadAllText($wcOut, [Text.Encoding]::UTF8) } else { '' }
    $LangCode = Get-UiLanguage
    $expect = L "SyHost bu klasöre yazamıyor:`n{0}`n`nSyHost.exe'yi yazılabilir bir klasöre taşı (ör. {1}) ve oradan aç." $wcRoot (Get-DefaultRoot)
    $LangCode = 'tr'
    Check ($p.ExitCode -eq 1 -and -not (Test-Path "$wcOut.reached")) "yazma denetimi: çıkış kodu 1, betik durdu (kod $($p.ExitCode))"
    Check ($alert -ceq $expect) "yazma denetimi: uyarı Windows dilinde ve iki yer tutucu dolu: $($alert -replace "`n", ' | ')"
} finally { & icacls.exe $wcData /remove:d $me | Out-Null }
Remove-Item $wcOut -ErrorAction SilentlyContinue
$p = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$wcScript`"" -WindowStyle Hidden -PassThru -Wait
Check ($p.ExitCode -eq 0 -and (Test-Path "$wcOut.reached") -and -not (Test-Path $wcOut)) 'yazma denetimi: yazılabilen klasörde uyarı yok, açılış sürer'

if ($CsExe) {
    $cs = Invoke-Cs @('--selftest', 'paths', $own)
    $lines = $cs.Out -split "`r?`n"
    function CsValue([string]$prefix) { $rx = '^' + (CsRx $prefix) + '\s*(.*)$'; foreach ($l in $lines) { $m = [regex]::Match($l, $rx); if ($m.Success) { return $m.Groups[1].Value.Trim() } }; '?' }
    $desk = [Environment]::GetFolderPath('DesktopDirectory')
    Check ((CsValue 'varsayılan kurulum yeri:') -eq (Get-DefaultRoot)) 'C# ile aynı: varsayılan kurulum yeri'
    Check ((CsValue 'İndirilenler:') -eq (Get-Downloads)) 'C# ile aynı: İndirilenler'
    Check ((CsValue 'Windows dili:') -eq (Get-UiLanguage)) 'C# ile aynı: Windows dili'
    Check ((CsValue "OneDrive mı ($own):") -eq [string](Test-InOneDrive $own)) 'C# ile aynı: OneDrive mı (test klasörü)'
    Check ((CsValue 'OneDrive mı (Masaüstü):') -eq [string](Test-InOneDrive $desk)) "C# ile aynı: OneDrive mı (Masaüstü = $(Test-InOneDrive $desk))"
    Check ((CsValue "yazılabilir mi ($own):") -eq [string](Test-CanWrite $own)) 'C# ile aynı: yazılabilir mi (test klasörü)'
    Check ((CsValue 'yazılabilir mi (Program Files):') -eq [string](Test-CanWrite 'C:\Program Files\SyHostDeneme')) 'C# ile aynı: yazılabilir mi (Program Files)'
    Check ((CsValue 'kendi boş klasörü mü (İndirilenler):') -eq [string](Test-OwnEmptyFolder (Get-Downloads) (Join-Path (Get-Downloads) 'SyHost.exe'))) 'C# ile aynı: kendi boş klasörü mü (İndirilenler)'
    Check ((CsValue 'Cascadia Mono kurulu mu:') -eq [string](Test-FontAvailable)) "C# ile aynı: Cascadia Mono kurulu mu ($(Test-FontAvailable))"
}

# =====================================================================
Section 'Kurulum ve exe (InstallTo, CopyExe)'
$src = Join-Path $WorkRoot 'src-exe\SyHost.exe'; New-Item -ItemType Directory -Force (Split-Path $src) | Out-Null
[IO.File]::WriteAllBytes($src, [byte[]](1..200))
$inst = Join-Path $WorkRoot 'install\SyHost'
Install-SyHostTo $inst $src 'ja'
$ic = [IO.File]::ReadAllText("$inst\Data\ayarlar.json", [Text.Encoding]::UTF8) | ConvertFrom-Json
Check ((Test-Path "$inst\SyHost.exe") -and (Test-Path "$inst\Servers") -and (Test-Path "$inst\Data")) 'Install-SyHostTo: exe, Data ve Servers'
Check ([IO.File]::ReadAllBytes("$inst\SyHost.exe").Length -eq 200 -and -not (Test-Path "$inst\SyHost.exe.yeni")) 'Install-SyHostTo: exe kopyalandı, geçici dosya kalmadı'
Check (((Get-Item -LiteralPath "$inst\Data" -Force).Attributes -band 'Hidden') -ne 0) 'Install-SyHostTo: Data gizli'
Check ($ic.dil -ceq 'ja' -and $ic.kurulumTamam -eq $false -and $ic.paketler.normal.ramMax -eq 10) 'Install-SyHostTo: ilk ayarlar (dil, kurulumTamam=false, varsayılan paketler)'
$cfgBytes = [IO.File]::ReadAllBytes("$inst\Data\ayarlar.json")
Check (-not ($cfgBytes[0] -eq 0xEF -and $cfgBytes[1] -eq 0xBB)) 'Install-SyHostTo: ayarlar.json UTF-8 BOM''suz'
[IO.File]::WriteAllText("$inst\Data\ayarlar.json", '{"dil":"tr","benim":1}', $Utf8NoBom)
[IO.File]::WriteAllText("$inst\Servers\dunya.txt", 'dokunma', $Utf8NoBom)
[IO.File]::WriteAllBytes($src, [byte[]](1..100))
Install-SyHostTo $inst $src 'en'
Check ([IO.File]::ReadAllText("$inst\Data\ayarlar.json") -eq '{"dil":"tr","benim":1}' -and [IO.File]::ReadAllText("$inst\Servers\dunya.txt") -eq 'dokunma') 'Install-SyHostTo (güncelleme): Data ve Servers dokunulmadı'
Check ([IO.File]::ReadAllBytes("$inst\SyHost.exe").Length -eq 100) 'Install-SyHostTo (güncelleme): exe yenilendi'
Install-SyHostTo $inst "$inst\SyHost.exe" 'en'
Check ([IO.File]::ReadAllBytes("$inst\SyHost.exe").Length -eq 100) 'Install-SyHostTo: kaynak ve hedef aynıysa kopyalamaz'

# Kilitli hedef: çalışan exe ve paylaşımsız açık dosya -> [System.IO.IOException]
$lockDir = Join-Path $WorkRoot 'locked'; New-Item -ItemType Directory -Force $lockDir | Out-Null
$lockExe = Join-Path $lockDir 'SyHost.exe'; Copy-Item $Sleeper $lockExe
$proc = Start-Process $lockExe -WindowStyle Hidden -PassThru
Start-Sleep -Milliseconds 400
$caught = $null
try { Copy-SyHostExe $src $lockExe } catch [System.IO.IOException] { $caught = $_.Exception }
Check ($null -ne $caught -and $caught -is [System.IO.IOException]) "Copy-SyHostExe: çalışan exe -> IOException ($($caught.GetType().Name): $($caught.Message))"
Check (-not (Test-Path "$lockExe.yeni")) 'Copy-SyHostExe: başarısız olunca .yeni kalmaz'
$caught = $null
try { Install-SyHostTo $lockDir $src 'tr' } catch [System.IO.IOException] { $caught = $_.Exception }
Check ($null -ne $caught) 'Install-SyHostTo: hedefteki SyHost açıksa [System.IO.IOException] (ilk açılış: "SyHost orada açık")'
$proc.Kill(); $proc.WaitForExit()
$lockFile = Join-Path $lockDir 'kilit.exe'; [IO.File]::WriteAllText($lockFile, 'x')
$fs = [IO.File]::Open($lockFile, 'Open', 'ReadWrite', 'None')
$caught = $null
try { Copy-SyHostExe $src $lockFile } catch [System.IO.IOException] { $caught = $_.Exception }
$fs.Dispose()
Check ($null -ne $caught) "Copy-SyHostExe: paylaşımsız açık dosya -> IOException ($($caught.Message))"
Copy-SyHostExe $src $lockExe
Check ([IO.File]::ReadAllBytes($lockExe).Length -eq 100) 'Copy-SyHostExe: kilit kalkınca kopyalar'
$caught = $null
try { Copy-SyHostExe (Join-Path $WorkRoot 'yok.exe') $lockExe } catch { $caught = $_.Exception }
Check ($caught -is [System.IO.FileNotFoundException] -and $caught.Message -notmatch 'Exception calling') "Copy-SyHostExe: kaynak yoksa C#'taki hata metni ($($caught.Message))"

# Get-ExeVersion
if ($CsExe) { $v = Get-ExeVersion $CsExe; Check ($v -is [version] -and $v -eq [version]'1.0.0.0') "Get-ExeVersion: C# SyHost.exe $v" }
Check ($null -eq (Get-ExeVersion $src)) 'Get-ExeVersion: sürüm bilgisi olmayan dosya $null'
Check ($null -eq (Get-ExeVersion (Join-Path $WorkRoot 'yok.exe'))) 'Get-ExeVersion: olmayan dosya $null'
Check ((Get-ExeVersion $Sleeper) -eq [version]'0.0.0.0') 'Get-ExeVersion: sürümü 0.0.0.0 olan exe'
Check ($null -eq (Get-ExeVersion "$env:SystemRoot\System32\whoami.exe")) 'Get-ExeVersion: "10.0.x (WinBuild...)" gibi ekli sürüm metni $null (C# Version.TryParse gibi)'

# =====================================================================
Section 'Eski verilerin taşınması (Migration.cs)'
$legacy = $env:SYHOST_LEGACY_DATA
function New-FakeLegacy([string]$dir) {
    Clear-Dir $dir; New-Item -ItemType Directory -Force $dir | Out-Null
    [IO.File]::WriteAllText("$dir\ayarlar.json", '{ "dil": "tr", "sunucuKokKlasoru": "C:\\MinecraftServer", "arkadasAdresi": "ornek.joinmc.link", "sesAdresi": "", "playitKullan": true, "maksOyuncu": 7 }', $Utf8NoBom)
    [IO.File]::WriteAllText("$dir\sunucular.json", '[ { "id": "a", "ad": "A", "klasor": "C:\\MinecraftServer\\A" }, { "id": "b", "ad": "B", "klasor": "C:\\MinecraftServer\\B" } ]', $Utf8NoBom)
    [IO.File]::WriteAllText("$dir\pencere.json", '{ "mod": "buyuk", "ustte": true }', $Utf8NoBom)
    [IO.File]::WriteAllText("$dir\playit.toml", 'secret_key = "sahte-test-anahtari-gercek-degil"', $Utf8NoBom)
    [IO.File]::WriteAllText("$dir\playit.log", 'deneme', $Utf8NoBom)
}
New-FakeLegacy $legacy
$mroot = Join-Path $WorkRoot 'migrate\SyHost'; $mdata = Join-Path $mroot 'Data'
Check (Test-LegacyData) 'Test-LegacyData: eski veri bulundu'
Check (Test-DataFresh $mdata) 'Test-DataFresh: yeni Data boş'
Check ($null -eq (Get-MovedTo)) 'Get-MovedTo: not yoksa $null'
$res = Copy-LegacyData $mdata $mroot 'en'
Check ($res.Servers -eq 2 -and $res.Playit -eq $true -and @($res.Copied).Count -eq 5) "Copy-LegacyData: 5 dosya, 2 sunucu, playit ($(@($res.Copied) -join ', '))"
Check ([IO.File]::ReadAllText("$mdata\playit.toml") -eq 'secret_key = "sahte-test-anahtari-gercek-degil"') 'Copy-LegacyData: playit.toml aynen kopyalandı'
$mc = [IO.File]::ReadAllText("$mdata\ayarlar.json", [Text.Encoding]::UTF8) | ConvertFrom-Json
Check ($mc.dil -ceq 'en' -and $mc.kurulumTamam -eq $false -and $mc.sunucuKokKlasoru -eq 'C:\MinecraftServer' -and $mc.maksOyuncu -eq 7 -and $mc.arkadasAdresi -eq 'ornek.joinmc.link') 'Copy-LegacyData: eski ayarlar korundu, dil ve kurulumTamam eklendi'
Check (-not (Test-DataFresh $mdata)) 'Test-DataFresh: kopyadan sonra boş değil'
$note = Join-Path $legacy 'SyHost-TASINDI.txt'
$nb = [IO.File]::ReadAllBytes($note); $nt = [IO.File]::ReadAllText($note, [Text.Encoding]::UTF8)
Check ($nb[0] -eq 0xEF -and $nb[1] -eq 0xBB -and $nb[2] -eq 0xBF) 'not: UTF-8 BOM''lu'
Check ($nt.StartsWith("path=$mroot`r`ndate=") -and $nt.Contains('şuraya kopyalandı') -and $nt.Contains('was copied to') -and $nt.Contains('コピーされました')) 'not: path satırı ve üç dil'
Check ((Get-MovedTo) -eq $mroot) "Get-MovedTo: notu okur ($(Get-MovedTo))"
Check ([IO.File]::Exists("$legacy\sunucular.json") -and [IO.File]::Exists("$legacy\playit.toml")) 'eski klasör silinmedi'
# sunucular.json yoksa boş liste yazılır
New-FakeLegacy $legacy; Remove-Item "$legacy\sunucular.json"
$m2 = Join-Path $WorkRoot 'migrate2'
$res2 = Copy-LegacyData "$m2\Data" $m2 ''
Check ($res2.Servers -eq 0 -and [IO.File]::ReadAllText("$m2\Data\sunucular.json") -eq '[]') 'Copy-LegacyData: sunucu listesi yoksa "[]" yazar (taşıma tekrarlanmaz)'
$m2c = [IO.File]::ReadAllText("$m2\Data\ayarlar.json", [Text.Encoding]::UTF8) | ConvertFrom-Json
Check ($m2c.dil -ceq 'tr') 'Copy-LegacyData: dil boşsa eski dil kalır'
# Not dosyasının bozuk hâlleri
[IO.File]::WriteAllText($note, "path=`r`ndate=x", $Utf8NoBom); Check ((Get-MovedTo) -eq '?') 'Get-MovedTo: "path=" boşsa ? (C# boş metinle açılışta çöker)'
[IO.File]::WriteAllText($note, "date=x`r`nbaska", $Utf8NoBom); Check ((Get-MovedTo) -eq '?') 'Get-MovedTo: path satırı yoksa ?'
[IO.File]::WriteAllText($note, "PATH=C:\x`r`npath=  D:\Yer  `r`n", $Utf8NoBom); Check ((Get-MovedTo) -eq 'D:\Yer') 'Get-MovedTo: büyük harfli PATH= sayılmaz, boşluklar kırpılır'
# Sunucu sayısı
Check ((Get-ServerCount '{ "id": "a" }') -eq 1 -and (Get-ServerCount '  ') -eq 0 -and (Get-ServerCount '[]') -eq 0 -and (Get-ServerCount '[{"id":"a"},{"id":"b"},{"id":"c"}]') -eq 3) 'Get-ServerCount: tek nesne 1, boş 0, [] 0, dizi 3'

if ($CsExe) {
    # C# ile aynı not (tarih ve kök hariç bayt bayt)
    $csLegacy = Join-Path $WorkRoot 'cs-legacy'; New-FakeLegacy $csLegacy
    $csRoot = Join-Path $WorkRoot 'cs-migrate\SyHost'
    $cs = Invoke-Cs @('--selftest', 'migration', $csLegacy, $csRoot)
    Check ($cs.Code -eq 0) "C# --selftest migration geçti ($(($cs.Out -split "`r?`n" | Where-Object { $_ -like '*kopyalanan*' }) -join ''))"
    New-FakeLegacy $legacy
    $pr = Join-Path $WorkRoot 'cs-migrate\SyHost'   # aynı kök metni: notlar bayt bayt karşılaştırılabilsin
    Clear-Dir (Join-Path $pr 'Data')
    $res3 = Copy-LegacyData (Join-Path $pr 'Data') $pr 'tr'
    $a = [IO.File]::ReadAllText((Join-Path $csLegacy 'SyHost-TASINDI.txt'), [Text.Encoding]::UTF8) -replace '\d{4}-\d\d-\d\d \d\d:\d\d', 'TARIH'
    $b = [IO.File]::ReadAllText($note, [Text.Encoding]::UTF8) -replace '\d{4}-\d\d-\d\d \d\d:\d\d', 'TARIH'
    $ab = [IO.File]::ReadAllBytes((Join-Path $csLegacy 'SyHost-TASINDI.txt')); $bb = [IO.File]::ReadAllBytes($note)
    Check ($a -ceq $b -and $ab[0] -eq $bb[0] -and $ab.Length -eq $bb.Length) "C# ile aynı: not metni ve kodlaması ($($bb.Length) bayt)"
    $csCfg = [IO.File]::ReadAllText((Join-Path $csRoot 'Data\ayarlar.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    $psCfg = [IO.File]::ReadAllText((Join-Path $pr 'Data\ayarlar.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    Check ($csCfg.dil -ceq $psCfg.dil -and $csCfg.kurulumTamam -eq $psCfg.kurulumTamam -and $csCfg.sunucuKokKlasoru -eq $psCfg.sunucuKokKlasoru -and $csCfg.maksOyuncu -eq $psCfg.maksOyuncu -and $csCfg.playitKullan -eq $psCfg.playitKullan) 'C# ile aynı: taşınan ayarların değerleri'
    foreach ($f in 'sunucular.json', 'pencere.json', 'playit.toml', 'playit.log') {
        Check ([IO.File]::ReadAllText((Join-Path $csRoot "Data\$f")) -ceq [IO.File]::ReadAllText((Join-Path $pr "Data\$f"))) "C# ile aynı: $f"
    }
}

# =====================================================================
Section 'Klasör görünümü (FolderLook.cs)'
function New-LookRoot([string]$root) {
    Clear-Dir $root
    New-Item -ItemType Directory -Force "$root\Servers\Deneme Sunucu\yedekler", "$root\Data" | Out-Null
    "$root\Servers\Deneme Sunucu"
}
function Get-Ini([string]$dir) { $f = Join-Path $dir 'desktop.ini'; if (Test-Path -LiteralPath $f) { [IO.File]::ReadAllBytes($f) } else { $null } }
$IconSrc = Join-Path $Repo 'src\SyHost\Assets\icons'
Check ((Get-FolderIconSource) -eq $IconSrc) "Get-FolderIconSource: repodan çalışırken $IconSrc"
$flRoot = Join-Path $WorkRoot 'look\tr\SyHost'
$srv = New-LookRoot $flRoot
$outside = Join-Path $WorkRoot 'look\disarida'; New-Item -ItemType Directory -Force "$outside\yedekler" | Out-Null
Set-FolderLook $flRoot 'tr' @($srv, $outside, '', $null, (Join-Path $flRoot 'Servers\Yok'))
$expect = [ordered]@{
    $flRoot = "[.ShellClassInfo]`r`nIconResource=Data\icons\folder-syhost.ico,0`r`n"
    "$flRoot\Servers" = "[.ShellClassInfo]`r`nLocalizedResourceName=Sunucular`r`nIconResource=..\Data\icons\folder-servers.ico,0`r`n"
    $srv = "[.ShellClassInfo]`r`nIconResource=..\..\Data\icons\folder-server.ico,0`r`n"
    "$srv\yedekler" = "[.ShellClassInfo]`r`nLocalizedResourceName=Yedekler`r`nIconResource=..\..\..\Data\icons\folder-backups.ico,0`r`n"
}
foreach ($d in $expect.Keys) {
    $b = Get-Ini $d
    $want = [byte[]](@(0xFF, 0xFE) + [Text.Encoding]::Unicode.GetBytes($expect[$d]))
    Check ($null -ne $b -and (Hex $b) -eq (Hex $want)) "desktop.ini UTF-16 LE + BOM, beklenen metin: $($d.Substring($WorkRoot.Length))"
    $ia = (Get-Item -LiteralPath (Join-Path $d 'desktop.ini') -Force).Attributes
    Check (($ia -band 'Hidden') -and ($ia -band 'System')) "desktop.ini gizli + sistem: $($d.Substring($WorkRoot.Length))"
    Check (((Get-Item -LiteralPath $d -Force).Attributes -band 'ReadOnly') -ne 0) "klasör salt okunur (Explorer desktop.ini'yi okusun): $($d.Substring($WorkRoot.Length))"
}
Check (((Get-Item -LiteralPath "$flRoot\Data" -Force).Attributes -band 'Hidden') -ne 0) 'Data gizli'
foreach ($n in 'folder-syhost.ico', 'folder-servers.ico', 'folder-server.ico', 'folder-backups.ico') {
    Check ((Hex ([IO.File]::ReadAllBytes("$flRoot\Data\icons\$n"))) -eq (Hex ([IO.File]::ReadAllBytes("$IconSrc\$n")))) "Data\icons\$n kaynakla aynı"
}
Check (-not (Test-Path -LiteralPath "$outside\desktop.ini") -and -not (Test-Path -LiteralPath "$outside\yedekler\desktop.ini")) 'SyHost klasörünün dışındaki sunucuya dokunulmadı'
$t0 = (Get-Item -LiteralPath "$flRoot\Servers\desktop.ini" -Force).LastWriteTimeUtc
Start-Sleep -Milliseconds 50
Set-FolderLook $flRoot 'tr' @($srv)
Check ((Get-Item -LiteralPath "$flRoot\Servers\desktop.ini" -Force).LastWriteTimeUtc -eq $t0) 'değişmediyse yeniden yazılmaz'
Set-FolderLook $flRoot 'ja' @($srv)
Check ([Text.Encoding]::Unicode.GetString((Get-Ini "$flRoot\Servers"), 2, (Get-Ini "$flRoot\Servers").Length - 2).Contains('LocalizedResourceName=サーバー') -and [Text.Encoding]::Unicode.GetString((Get-Ini "$srv\yedekler"), 2, (Get-Ini "$srv\yedekler").Length - 2).Contains('LocalizedResourceName=バックアップ')) 'dil değişince ad yenilenir (ja: サーバー, バックアップ)'
Check (((Get-Item -LiteralPath "$flRoot\Servers\desktop.ini" -Force).Attributes -band 'Hidden') -ne 0) 'yeniden yazılan desktop.ini yine gizli'
# İngilizce, simgeler yokken (yalnızca adlar yazılır)
$enRoot = Join-Path $WorkRoot 'look\noicons\SyHost'; $enSrv = New-LookRoot $enRoot
$savedApp = $AppDir; $AppDir = Join-Path $WorkRoot 'bos-app'
Check ($null -eq (Get-FolderIconSource)) 'Get-FolderIconSource: simge yoksa $null'
Set-FolderLook $enRoot 'en' @($enSrv)
$AppDir = $savedApp
Check ($null -eq (Get-Ini $enRoot) -and $null -eq (Get-Ini $enSrv)) 'simge yoksa kök ve sunucu klasörüne desktop.ini yazılmaz'
Check ((Hex (Get-Ini "$enRoot\Servers")) -eq (Hex ([byte[]](@(0xFF, 0xFE) + [Text.Encoding]::Unicode.GetBytes("[.ShellClassInfo]`r`nLocalizedResourceName=Servers`r`n"))))) 'simge yoksa Servers yalnızca adla (en: Servers)'
# Arka planda
$bgRoot = Join-Path $WorkRoot 'look\bg\SyHost'; $bgSrv = New-LookRoot $bgRoot
Start-FolderLook $bgRoot 'en' @($bgSrv)
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt 10000 -and $null -eq (Get-Ini "$bgSrv\yedekler")) { Start-Sleep -Milliseconds 50 }
Check ($null -ne (Get-Ini "$bgSrv\yedekler")) "Start-FolderLook: arka planda bitti ($($sw.ElapsedMilliseconds) ms)"
# Test modunda hiçbir şeye dokunulmaz
$tmRoot = Join-Path $WorkRoot 'look\testmode\SyHost'; $tmSrv = New-LookRoot $tmRoot
$TestFrame = 'senaryo.json'
Set-FolderLook $tmRoot 'tr' @($tmSrv); Start-FolderLook $tmRoot 'tr' @($tmSrv)
Check ($null -eq (Pick-Folder 'Deneme' $WorkRoot)) 'test modunda Pick-Folder $null (pencere açılmaz)'
Start-Sleep -Milliseconds 300
$TestFrame = $null
Check ($null -eq (Get-Ini $tmRoot) -and -not (Test-Path "$tmRoot\Data\icons")) 'test modunda Set-FolderLook / Start-FolderLook hiçbir şey yazmaz'

if ($CsExe) {
    foreach ($lng in 'tr', 'ja', 'en') {
        $cr = Join-Path $WorkRoot "look\cs-$lng\SyHost"; $pr2 = Join-Path $WorkRoot "look\ps-$lng\SyHost"
        Clear-Dir $cr
        $cs = Invoke-Cs @('--selftest', 'folderlook', $cr, $lng)
        $ps2 = New-LookRoot $pr2
        Set-FolderLook $pr2 $lng @($ps2)
        $same = $cs.Code -eq 0
        foreach ($rel in '', 'Servers', 'Servers\Deneme Sunucu', 'Servers\Deneme Sunucu\yedekler') {
            $ca = Get-Ini (Join-Path $cr $rel); $pa = Get-Ini (Join-Path $pr2 $rel)
            if ($null -eq $ca -or (Hex $ca) -ne (Hex $pa)) { $same = $false; Write-Host "      fark: $rel" }
            $cAt = (Get-Item -LiteralPath (Join-Path (Join-Path $cr $rel) 'desktop.ini') -Force).Attributes; $pAt = (Get-Item -LiteralPath (Join-Path (Join-Path $pr2 $rel) 'desktop.ini') -Force).Attributes
            $cDa = (Get-Item -LiteralPath (Join-Path $cr $rel) -Force).Attributes; $pDa = (Get-Item -LiteralPath (Join-Path $pr2 $rel) -Force).Attributes
            if ($cAt -ne $pAt -or $cDa -ne $pDa) { $same = $false; Write-Host "      öznitelik farkı: $rel ($cAt/$cDa - $pAt/$pDa)" }
        }
        foreach ($n in 'folder-syhost.ico', 'folder-servers.ico', 'folder-server.ico', 'folder-backups.ico') {
            if ((Hex ([IO.File]::ReadAllBytes("$cr\Data\icons\$n"))) -ne (Hex ([IO.File]::ReadAllBytes("$pr2\Data\icons\$n")))) { $same = $false; Write-Host "      simge farkı: $n" }
        }
        if ((Get-Item -LiteralPath "$cr\Data" -Force).Attributes -ne (Get-Item -LiteralPath "$pr2\Data" -Force).Attributes) { $same = $false; Write-Host '      Data özniteliği farklı' }
        Check $same "C# ile aynı ($lng): dört desktop.ini bayt bayt, öznitelikler, Data\icons"
    }
}

# =====================================================================
Section 'Kısayollar (Shortcuts.cs): iki biçim, taşınan klasör, başka kurulum'
$scRoot = Join-Path $WorkRoot 'sc'
$exeA = Join-Path $scRoot 'A\SyHost.exe'; $exeB = Join-Path $scRoot 'B\SyHost.exe'
New-Item -ItemType Directory -Force (Split-Path $exeA), (Split-Path $exeB), (Join-Path $scRoot 'A\Data') | Out-Null
[IO.File]::WriteAllText($exeA, 'x'); [IO.File]::WriteAllText($exeB, 'x')
$desk = $locs[0]; $start = $locs[1]
$conhost = Join-Path ([Environment]::SystemDirectory) 'conhost.exe'
# C# sürümünün yazdığı biçim (Shortcuts.Write): conhost.exe "<exe>" --hosted, çalışma klasörü exe'nin klasörü, simge exe
function Write-CsLink([string]$lnk, [string]$exe, [string]$desc) {
    New-Item -ItemType Directory -Force (Split-Path $lnk) | Out-Null
    if (-not [SyHost.ShellLink]::Write($lnk, $conhost, "`"$exe`" --hosted", (Split-Path $exe), $desc, $exe, 0)) { throw "yazılamadı: $lnk" }
}
Check ((Get-LinkState $desk $exeA) -ceq 'Missing') 'durum: kısayol yoksa Missing'
Write-Shortcut $desk $exeA 'SyHost test'
$i = Read-Shortcut $desk
Check ($null -ne $i -and $i.Target -eq $exeA -and $i.Args -eq '' -and $i.WorkDir -eq (Split-Path $exeA) -and $i.Icon -eq $exeA) "Terminal biçimi: hedef=$($i.Target) argümanlar='$($i.Args)' klasör=$($i.WorkDir) simge=$($i.Icon)"
Check ((Test-TerminalLink $i $exeA)) 'Test-TerminalLink: Terminal biçimi tanınır'
Check ((Get-LinkState $desk $exeA) -ceq 'Ours') 'Terminal biçimi: A için Ours'
Check ((Get-LinkState $desk $exeB) -ceq 'OtherLive') 'Terminal biçimi: B için OtherLive (A duruyor)'
Check ((Get-LinkState $desk "$($exeA.ToUpper())") -ceq 'Ours') 'durum: yol büyük-küçük harf farkıyla da Ours'
# C# biçimi: conhost.exe "<exe>" --hosted
Write-CsLink $start $exeA 'SyHost test'
$ci = Read-Shortcut $start
Check ($ci.Target -eq $conhost -and $ci.Args -eq "`"$exeA`" --hosted") "C# biçimi okundu: hedef=$($ci.Target) argümanlar=$($ci.Args)"
Check ((Get-LinkSyHostPath $ci) -eq $exeA -and -not (Test-TerminalLink $ci $exeA)) 'C# biçimi: açtığı exe argümandan bulunur, Terminal biçimi sayılmaz'
Check ((Get-LinkState $start $exeA) -ceq 'Ours' -and (Get-LinkState $start $exeB) -ceq 'OtherLive') 'C# biçimi de A için Ours, B için OtherLive'
Check ((Find-OtherInstall $exeB) -eq (Split-Path $exeA)) 'Find-OtherInstall: B açılınca A''nın klasörü (Data var)'
Check ($null -eq (Find-OtherInstall $exeA)) 'Find-OtherInstall: kendisi başka kurulum sayılmaz'
Remove-Item (Join-Path $scRoot 'A\Data')
Check ($null -eq (Find-OtherInstall $exeB)) 'Find-OtherInstall: Data yoksa kurulum sayılmaz'
New-Item -ItemType Directory -Force (Join-Path $scRoot 'A\Data') | Out-Null
# Taşınan klasör: A silinince iki kısayol da B için Dead, onarılınca Terminal biçiminde Ours
Remove-Item $exeA
Check ((Get-LinkState $desk $exeB) -ceq 'Dead' -and (Get-LinkState $start $exeB) -ceq 'Dead') 'A silinince iki biçim de B için Dead'
Check ($null -eq (Find-OtherInstall $exeB)) 'Find-OtherInstall: exe yoksa $null'
$n = Repair-MovedShortcuts $exeB 'SyHost yeni'
Check ($n -eq 2) "Repair-MovedShortcuts: iki ölü kısayol çevrildi ($n)"
foreach ($l in $desk, $start) { $ri = Read-Shortcut $l; Check ((Get-LinkState $l $exeB) -ceq 'Ours' -and (Test-TerminalLink $ri $exeB)) "onarılan kısayol Terminal biçiminde Ours: $(Split-Path (Split-Path $l) -Leaf)" }
Check ((Repair-MovedShortcuts $exeB 'x') -eq 0) 'Repair-MovedShortcuts: çalışan kısayola dokunmaz (0)'
# Yabancı, bozuk ve eski sürüm kısayolları
$foreign = Join-Path $WorkRoot 'sc\foreign.lnk'
[void][SyHost.ShellLink]::Write($foreign, "$env:SystemRoot\System32\notepad.exe", '', '', 'not', '', 0)
Check ((Get-LinkState $foreign $exeB) -ceq 'Foreign') 'başka programın kısayolu Foreign'
$broken = Join-Path $WorkRoot 'sc\bozuk.lnk'; [IO.File]::WriteAllBytes($broken, [byte[]](1..64))
Check ($null -eq (Read-Shortcut $broken) -and (Get-LinkState $broken $exeB) -ceq 'Foreign') 'bozuk .lnk okunamaz, Foreign'
$oldPs1 = Join-Path $scRoot 'old\src\SyHost.ps1'; New-Item -ItemType Directory -Force (Split-Path $oldPs1) | Out-Null; [IO.File]::WriteAllText($oldPs1, 'x')
$old = Join-Path $WorkRoot 'sc\old.lnk'
[void][SyHost.ShellLink]::Write($old, $conhost, "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$oldPs1`"", '', 'SyHost', '', 0)
Check ((Get-LinkSyHostPath (Read-Shortcut $old)) -eq $oldPs1 -and (Get-LinkState $old $exeB) -ceq 'OtherLive') '0.5.0 kısayolu (SyHost.ps1) duruyorsa OtherLive'
Remove-Item $oldPs1
Check ((Get-LinkState $old $exeB) -ceq 'Dead') '0.5.0 kısayolu, betik yoksa Dead'
# Silme: yalnızca bizimkiler
Write-CsLink $start $exeB 'C#'
[IO.File]::WriteAllText($exeA, 'x')
Write-Shortcut $desk $exeA 'A'
Remove-OurShortcuts $exeB
Check ((Test-Path $desk) -and -not (Test-Path $start)) 'Remove-OurShortcuts: yalnızca B''yi açan (C# biçimi) silindi, A''nınki duruyor'
Remove-OurShortcuts $exeA
Check (-not (Test-Path $desk)) 'Remove-OurShortcuts: Terminal biçimi de silinir'
# Runspace (MTA) içinden okuma: kabuk nesnesi STA iş parçacığında çalışır
Write-Shortcut $desk $exeA 'A'
$rs = [powershell]::Create()
[void]$rs.AddScript("Add-Type -Path '$CoreDll'; [Threading.Thread]::CurrentThread.GetApartmentState().ToString(); ([SyHost.ShellLink]::Read('$desk'))[0]")
$rr = @($rs.Invoke()); $rs.Dispose()
Check ($rr.Count -eq 2 -and $rr[0] -ne 'STA' -and $rr[1] -eq $exeA) "ShellLink.Read arka plan iş parçacığında ($($rr[0])) de okur"
Remove-Item $desk

if ($CsExe) {
    $cs = Invoke-Cs @('--selftest', 'shortcuts', (Join-Path $WorkRoot 'cs-sc'))
    $hl = ($cs.Out -split "`r?`n" | Where-Object { $_ -like '*hedef=*' }) -join ''
    Check ($cs.Code -eq 0) 'C# --selftest shortcuts geçti'
    $csA = Join-Path $WorkRoot 'cs-sc\A\SyHost.exe'
    $emu = Join-Path $WorkRoot 'sc\emu.lnk'
    Write-CsLink $emu $csA 'SyHost test'
    $ei = Read-Shortcut $emu
    Check ($hl.Trim() -cmatch ('^' + (CsRx "hedef=$($ei.Target)  argümanlar=$($ei.Args)  klasör=$($ei.WorkDir)  simge=$($ei.Icon)") + '$')) "C# biçimini C#'ın okuduğu gibi okuyoruz: $($hl.Trim())"
    # C#'ın test modunda Ayarlar'dan yazdığı gerçek kısayol: iki sürüm de Ours der
    $csRoot = Join-Path $WorkRoot 'cs-app'; New-Item -ItemType Directory -Force "$csRoot\Data" | Out-Null
    $csCopy = Join-Path $csRoot 'SyHost.exe'; Copy-Item $CsExe $csCopy
    $scn = Join-Path $WorkRoot 'cs-set-desk.json'
    [IO.File]::WriteAllText($scn, '{ "t": 1.0, "now": "2026-11-27 14:30:00", "w": 129, "h": 41, "state": { "screen": "settings", "settings": { "sel": 2 }, "keys": [ "Enter" ] } }', $Utf8NoBom)
    $savedSc = $env:SYHOST_SHORTCUT_DIR; $env:SYHOST_SHORTCUT_DIR = Join-Path $WorkRoot 'cs-app-shortcuts'
    $cs = Invoke-Cs @('--frame', $scn, (Join-Path $WorkRoot 'cs-set-desk.txt'), '--root', $csRoot) $csCopy
    $csLnk = Join-Path $env:SYHOST_SHORTCUT_DIR 'Desktop\SyHost.lnk'
    $gi = Read-Shortcut $csLnk
    Check ($cs.Code -eq 0 -and $null -ne $gi -and $gi.Target -eq $conhost -and $gi.Args -eq "`"$csCopy`" --hosted") "C#'ın yazdığı kısayol: $($gi.Target) $($gi.Args)"
    Check ((Get-LinkState $csLnk $csCopy) -ceq 'Ours') 'C#''ın yazdığı kısayol bu exe için Ours'
    # Terminal açılışı onu Terminal biçimine çevirir, C# sürümü de Terminal biçimini kendi kısayolu sayar
    Use-Root $csRoot
    $SetupMode = $false; $LangCode = 'en'
    Load-Config
    Invoke-PortableStartup
    $ti = Read-Shortcut $csLnk
    Check ((Test-TerminalLink $ti $csCopy) -and $ti.WorkDir -eq $csRoot -and $ti.Icon -eq $csCopy) "Invoke-PortableStartup: C# biçimindeki kısayolumuz Terminal biçimine çevrildi ($($ti.Target))"
    $env:SYHOST_SHORTCUT_DIR = $savedSc
    Use-Root (Join-Path $WorkRoot 'root')
}

# =====================================================================
Section 'Açılış (App.PortableStartup)'
function New-InstalledRoot([string]$root, $servers = '[]', $kurulum = $true) {
    Clear-Dir $root
    New-Item -ItemType Directory -Force "$root\Data", "$root\Servers" | Out-Null
    $c = Read-DefaultSettings
    $c | Add-Member -NotePropertyName paketlerAyarlandi -NotePropertyValue $true -Force
    if ($null -ne $kurulum) { $c | Add-Member -NotePropertyName kurulumTamam -NotePropertyValue $kurulum -Force }
    [IO.File]::WriteAllText("$root\Data\ayarlar.json", ($c | ConvertTo-Json -Depth 6), $Utf8NoBom)
    if ($null -ne $servers) { [IO.File]::WriteAllText("$root\Data\sunucular.json", $servers, $Utf8NoBom) }
    [IO.File]::WriteAllText("$root\SyHost.exe", 'x')
    Use-Root $root
    $script:SetupMode = $false
    Load-Config
}
Clear-Dir $env:SYHOST_SHORTCUT_DIR; Clear-Dir $legacy
# 1) Kurulum yapılmış, eski veri yok: ana menü, klasör görünümü arka planda
$s1 = Join-Path $WorkRoot 'start1\SyHost'
New-InstalledRoot $s1 ('[ { "id": "x", "ad": "X", "klasor": "Servers\\X" } ]')
New-Item -ItemType Directory -Force "$s1\Servers\X\yedekler" | Out-Null
Invoke-PortableStartup
Check ($NextAfterSplash -ceq 'home' -and $null -eq $FrMigrated -and $null -eq $FrMovedTo -and $Servers.Count -eq 1 -and $Servers[0].klasor -eq "$s1\Servers\X") 'kurulu, eski veri yok: home, sunucu listesi yüklendi (göreli yol çözüldü)'
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt 10000 -and $null -eq (Get-Ini "$s1\Servers\X\yedekler")) { Start-Sleep -Milliseconds 50 }
Check ($null -ne (Get-Ini $s1) -and $null -ne (Get-Ini "$s1\Servers\X\yedekler")) 'açılışta klasör görünümü uygulandı (sunucu ve yedekler dahil)'
# 2) Kurulum yarıda kalmış: ilk açılış
New-InstalledRoot (Join-Path $WorkRoot 'start2\SyHost') '[]' $false
Invoke-PortableStartup
Check ($NextAfterSplash -ceq 'firstrun') 'kurulumTamam=false: firstrun'
# 3) kurulumTamam yok (eski sürümden gelen ayar): kurulum yapılmış sayılır
New-InstalledRoot (Join-Path $WorkRoot 'start3\SyHost') '[]' $null
Invoke-PortableStartup
Check ($NextAfterSplash -ceq 'home') 'kurulumTamam yok: home'
# 4) Kurulum modu
$SetupMode = $true; $NextAfterSplash = 'home'
Invoke-PortableStartup
Check ($NextAfterSplash -ceq 'firstrun') 'kurulum modu (Data yok): firstrun'
$SetupMode = $false
# 5) Eski veri var, Data boş, not yok: kopyalanır, ayarlar yeniden yüklenir
New-FakeLegacy $legacy
$s5 = Join-Path $WorkRoot 'start5\SyHost'
New-InstalledRoot $s5 $null $false
$Cfg.dil = 'ja'
Invoke-PortableStartup
Check ($null -ne $FrMigrated -and $FrMigrated.Servers -eq 2 -and $FrMigrated.Playit -and $NextAfterSplash -ceq 'firstrun') 'eski veri kopyalandı: FrMigrated (2 sunucu, playit), firstrun'
Check ($Cfg.maksOyuncu -eq 7 -and $LangCode -ceq 'ja' -and $Servers.Count -eq 2) "taşınan ayarlar ve sunucular yüklendi, seçilen dil korundu (dil: $LangCode)"
Check ((Get-MovedTo) -eq $s5) 'eski klasöre bu klasörü gösteren not bırakıldı'
# 6) Not bu klasörü gösteriyorsa (yeniden kurulmuş Data): yine kopyalanır
New-InstalledRoot $s5 $null $true
Invoke-PortableStartup
Check ($null -ne $FrMigrated -and $null -eq $FrMovedTo) 'not bu klasörü gösteriyor: kopyalanır'
# 7) Not başka bir klasörü gösteriyorsa: kopyalanmaz, sorulur (FrMovedTo)
$s7 = Join-Path $WorkRoot 'start7\SyHost'
New-InstalledRoot $s7 $null $true
Invoke-PortableStartup
Check ($null -eq $FrMigrated -and $FrMovedTo -eq $s5 -and $NextAfterSplash -ceq 'firstrun' -and -not (Test-Path "$s7\Data\sunucular.json")) "not başka klasörü gösteriyor: FrMovedTo=$FrMovedTo, kopyalanmadı"
# 8) Not bozuksa ("path=" boş): çökmez, yer bilinmiyor diye sorulur
[IO.File]::WriteAllText((Join-Path $legacy 'SyHost-TASINDI.txt'), "path=`r`n", $Utf8NoBom)
New-InstalledRoot $s7 $null $true
Invoke-PortableStartup
Check ($FrMovedTo -eq '?' -and $null -eq $FrMigrated) 'bozuk not: çökmez, FrMovedTo=?'
# 9) Klasör taşındı: eski yeri gösteren kısayollar düzeltilir ve ana menüde not çıkar; başka SyHost'unkine dokunulmaz
Clear-Dir $legacy
$s9 = Join-Path $WorkRoot 'start9\SyHost'
New-InstalledRoot $s9 '[]' $true
$gone = Join-Path $WorkRoot 'tasindi\SyHost\SyHost.exe'
Write-Shortcut $desk $gone 'eski'
$live = Join-Path $WorkRoot 'baska\SyHost.exe'; New-Item -ItemType Directory -Force (Split-Path $live) | Out-Null; [IO.File]::WriteAllText($live, 'x')
Write-Shortcut $start $live 'başka'
$LangCode = 'tr'
Invoke-PortableStartup
$di = Read-Shortcut $desk
Check ((Test-TerminalLink $di $ExePath) -and (Get-LinkState $start $ExePath) -ceq 'OtherLive') 'taşınan klasör: ölü kısayol buraya çevrildi, başka SyHost''unkine dokunulmadı'
Check ($HomeMsg -ceq (L 'Kısayollar yeni yere güncellendi.') -and $HomeMsgUntil -gt (Get-Date)) "ana menü notu: $HomeMsg"
Check ($di.WorkDir -eq $s9) 'çevrilen kısayolun çalışma klasörü SyHost klasörü'
# 10) C# biçimindeki kısayolumuz Terminal biçimine çevrilir (simge ve açıklama dahil)
Write-CsLink $desk $ExePath 'C#'
$HomeMsg = ''
Invoke-PortableStartup
Check ((Test-TerminalLink (Read-Shortcut $desk) $ExePath) -and $HomeMsg -eq '') 'C# biçimi Terminal biçimine çevrildi (taşınma notu çıkmaz)'
Remove-Item $desk, $start

# =====================================================================
Section 'playit ajanı (App.Server.cs SrvFindPlayit)'
Use-Root (Join-Path $WorkRoot 'playit\SyHost')
New-Item -ItemType Directory -Force $PlayitToolDir, $PlayitLegacyBin | Out-Null
Check ($null -eq (Find-PlayitDaemon)) 'hiçbiri yoksa $null'
Copy-Item $Sleeper (Join-Path $PlayitLegacyBin 'playitd.exe')
Check ((Find-PlayitDaemon) -eq (Join-Path $PlayitLegacyBin 'playitd.exe')) 'yalnızca Program Files''taki eski kurulum'
Copy-Item $FakeCli (Join-Path $PlayitToolDir 'playit.exe')
Check ((Find-PlayitDaemon) -eq (Join-Path $PlayitLegacyBin 'playitd.exe')) 'Data\tools\playit\playit.exe asıl komut satırı aracıysa (playit-cli) atlanır'
Copy-Item $Sleeper (Join-Path $PlayitToolDir 'playit.exe') -Force
Check ((Find-PlayitDaemon) -eq (Join-Path $PlayitToolDir 'playit.exe')) 'playitd playit.exe adıyla kaydedildiyse o kullanılır'
Copy-Item $Sleeper (Join-Path $PlayitToolDir 'playitd.exe')
Check ((Find-PlayitDaemon) -eq (Join-Path $PlayitToolDir 'playitd.exe')) 'önce SyHost''un kendi playitd.exe''si'

# =====================================================================
Section 'Java (Java.cs): sürüm, arama sırası, artıklar, hata yolları'
$cases = [ordered]@{ '1.21.1' = 21; '1.20.4' = 17; '1.20.5' = 21; '1.20.6-pre1' = 21; '1.21-rc1' = 21; '1.17' = 17; '1.16.5' = 8; '1.12.2' = 8; '1' = 8; '26.1' = 25; '26.1-snapshot-1' = 25; '25w14a' = 21; '27' = 25; '' = 21; 'abc' = 21; '1.x' = 8; '1.99999999999' = 21 }
$bad = @(foreach ($k in $cases.Keys) { $got = Get-JavaMajor $k; if ($got -ne $cases[$k]) { "$k -> $got (beklenen $($cases[$k]))" } })
Check ($bad.Count -eq 0) "Get-JavaMajor: $($cases.Count) sürüm (26.x -> 25, ön sürümler, taşan sayı) $($bad -join '; ')"
Check ((Get-JavaMajor $null) -eq 21) 'Get-JavaMajor: $null -> 21'
$jroot = Join-Path $WorkRoot 'java\SyHost'; Use-Root $jroot
$tools = Join-Path $Data 'tools'
# Yarım kalmış denemelerin artıkları (java-N.xxxx.zip/.tmp/.old); -Filter Win32 kuralıyla java-N klasörünü de sayardı
function Get-Leftovers([string]$tools, [int]$major) { @(Get-ChildItem -LiteralPath $tools -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "java-$major.*" }) }
function New-FakeJava([string]$dir) { New-Item -ItemType Directory -Force "$dir\bin" | Out-Null; [IO.File]::WriteAllText("$dir\bin\java.exe", 'x'); "$dir\bin\java.exe" }
$sys21 = @(Get-ChildItem 'C:\Program Files\Microsoft' -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue | Where-Object { Test-Path "$($_.FullName)\bin\java.exe" } | Sort-Object FullName | Select-Object -Last 1)
$own21 = New-FakeJava "$tools\java-21"
if ($sys21.Count) { Check ((Find-Java 21) -eq "$($sys21[0].FullName)\bin\java.exe") "Find-Java 21: önce bilgisayardaki Java ($(Find-Java 21)), SyHost'unki sonra" }
else { Check ((Find-Java 21) -eq $own21) 'Find-Java 21: bilgisayarda yok, SyHost''unki' }
Check ($null -eq (Find-Java 17)) 'Find-Java 17: hiçbir yerde yok -> $null'
$n1 = New-FakeJava "$tools\java-17\jdk-17.0.9+9-jre"; $n2 = New-FakeJava "$tools\java-17\jdk-17.0.12+7-jre"
$h = New-FakeJava "$tools\java-17\jdk-17.9.9-gizli"; (Get-Item "$tools\java-17\jdk-17.9.9-gizli").Attributes = 'Hidden, Directory'
Check ((Find-Java 17) -eq $n1) "Find-Java 17: bir alt klasörde, en büyük ad (Sort-Object gibi), gizli klasör sayılmaz: $(Split-Path (Split-Path (Split-Path (Find-Java 17))) -Leaf)"
$d17 = New-FakeJava "$tools\java-17"
Check ((Find-Java 17) -eq $d17) 'Find-Java 17: java-17\bin\java.exe varsa önce o'
$DataDir = ''
Check ($null -eq (Find-Java 17)) 'Find-Java: $DataDir yoksa yalnızca bilgisayardaki'
$DataDir = $Data
Check ((Find-Java 8) -eq $null) 'Find-Java 8: yok'
New-FakeJava "$tools\java-8\jdk8u432-b06-jre" | Out-Null
Check ((Find-Java 8) -like '*\java-8\jdk8u432-b06-jre\bin\java.exe') 'Find-Java 8: SyHost''un Java 8''i'
# Artıklar (yarım kalmış denemeler)
New-Item -ItemType Directory -Force "$tools\java-25.ab12cd34.tmp\x", "$tools\java-25.ab12cd34.old", "$tools\java-25" | Out-Null
[IO.File]::WriteAllText("$tools\java-25.ab12cd34.zip", 'x'); [IO.File]::WriteAllText("$tools\java-25.ab12cd34.tmp\x\y", 'x'); [IO.File]::WriteAllText("$tools\java-2.zz.zip", 'x')
Clear-JavaLeftovers $tools 25
Check (-not (Test-Path "$tools\java-25.ab12cd34.zip") -and -not (Test-Path "$tools\java-25.ab12cd34.tmp") -and -not (Test-Path "$tools\java-25.ab12cd34.old") -and (Test-Path "$tools\java-25") -and (Test-Path "$tools\java-2.zz.zip")) 'Clear-JavaLeftovers: yalnızca java-25.*.zip/.tmp/.old silindi'
Check ((Format-JavaProgress 'a.zip' 0 -1) -ceq 'a.zip  ·  0 MB' -and (Format-JavaProgress 'a.zip' 25165824 50331648) -ceq 'a.zip  ·  24 / 48 MB' -and (Format-JavaProgress 'a.zip' 1048575 2097152) -ceq 'a.zip  ·  0 / 2 MB') 'Format-JavaProgress: "<dosya>  ·  <MB> / <MB> MB" (aşağı yuvarlar)'
# Hata yolları (indirme sahte: küçük zip'ler)
function New-TestZip([string]$path, [string]$javaExe) {
    if (Test-Path $path) { Remove-Item $path }
    $z = [IO.Compression.ZipFile]::Open($path, 'Create')
    try {
        if ($javaExe) { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $javaExe, 'jdk-25.0.1+8-jre/bin/java.exe') }
        else { $e = $z.CreateEntry('jdk-25.0.1+8-jre/README'); $w = New-Object IO.StreamWriter($e.Open()); $w.Write('x'); $w.Dispose() }
    } finally { $z.Dispose() }
}
$lines = New-Object System.Collections.Generic.List[string]
$onDetail = { param($t) $lines.Add($t) }
$fakeZip = Join-Path $WorkRoot 'fake.zip'
# İndirme ve sağlama sahte: işlev adları çağrı anında çözülür, buradaki yerel tanımlar Install-Java'dan görünür
function Invoke-MockedInstall([scriptblock]$mockSave, [scriptblock]$mockSum) {
    function Save-JavaFile([string]$url, [string]$path, [scriptblock]$OnDetail) { & $mockSave $url $path }
    function Get-JavaChecksum([int]$major) { & $mockSum }
    try { [void](Install-Java 25 $onDetail 'Java {0} indiriliyor...'); $null } catch { $_.Exception }
}
New-TestZip $fakeZip $null
$sw = [Diagnostics.Stopwatch]::StartNew()
$e = Invoke-MockedInstall { param($u, $p) Copy-Item $fakeZip $p; 'aa' } { $null }
Check ($e -is [System.IO.IOException] -and $e.Message -ceq 'Java 25 could not be downloaded: java.exe is missing from the Java 25 archive.' -and $sw.Elapsed.TotalSeconds -ge 5.5) "java.exe olmayan arşiv: 3 deneme, sonra '$($e.Message)'"
Check ($lines[0] -ceq 'Java 25 indiriliyor...') "ilk satır -HeadText'ten, sürümle dolduruldu: $($lines[0])"
Check (@(Get-Leftovers $tools 25).Count -eq 0 -and -not (Test-Path "$tools\java-25\bin")) 'başarısız denemeler artık bırakmadı'
$e = Invoke-MockedInstall { param($u, $p) Copy-Item $fakeZip $p; 'bb' } { 'a' * 64 }
Check ($e.Message -ceq 'Java 25 could not be downloaded: The Java 25 archive does not match its SHA-256 checksum.') "SHA-256 tutmazsa: '$($e.Message)'"
# java -version çalışmıyor: arşivdeki "java.exe" aslında whoami.exe (hata koduyla çıkar), kopya yerinde kalmamalı
New-TestZip $fakeZip "$env:SystemRoot\System32\whoami.exe"
$e = Invoke-MockedInstall { param($u, $p) Copy-Item $fakeZip $p; 'cc' } { $null }
Check ($e.Message -like 'Java 25 could not be downloaded: java -version exited with code 1:*' -and -not (Test-Path "$tools\java-25\jdk-25.0.1+8-jre") -and @(Get-Leftovers $tools 25).Count -eq 0) "java -version çalışmıyorsa silinir: '$($e.Message.Substring(0, [Math]::Min(90, $e.Message.Length)))...'"
# Gerçek ağ: olmayan sürüm (kalıcı hata) bir kez denenir
$lines.Clear()
$sw = [Diagnostics.Stopwatch]::StartNew()
$e = $null; try { Install-Java 99 $onDetail } catch { $e = $_.Exception }
Check ($e -is [System.IO.IOException] -and $e.Message -match '^Java 99 could not be downloaded: The remote server returned an error: \(4\d\d\)' -and $sw.Elapsed.TotalSeconds -lt 30) "olmayan Java: tekrar denenmez ($([int]$sw.Elapsed.TotalSeconds) sn): $($e.Message)"
Check ($lines.Count -ge 1 -and $lines[0] -ceq (L 'Java {0} indiriliyor...' 99)) "ilk satır L ile (ana betik): $($lines[0])"
$e = $null; try { $DataDir = ''; Install-Java 21 $null } catch { $e = $_.Exception } finally { $DataDir = $Data }
Check ($e -is [InvalidOperationException]) '$DataDir yoksa Install-Java açıkça hata verir'
$sum = Get-JavaChecksum 21
Check ($sum -match '^[0-9a-f]{64}$') "Get-JavaChecksum 21 (Adoptium assets API): $sum"

if ($Java) {
    Section 'Java 17 gerçekten indiriliyor (WorkRoot\Data\tools\java-17)'
    $jd = Join-Path (Split-Path $WorkRoot) 'Data'
    Clear-Dir (Join-Path $jd 'tools\java-17')
    $DataDir = $jd
    Check ($null -eq (Find-Java 17)) 'önce: Java 17 yok'
    $times = New-Object System.Collections.Generic.List[double]
    $lines.Clear(); $clock = [Diagnostics.Stopwatch]::StartNew()
    $onDetail2 = { param($t) $lines.Add($t); $times.Add($clock.Elapsed.TotalMilliseconds) }
    $exe = Install-Java 17 $onDetail2
    Write-Host ("      {0} satır, {1:0.0} sn; ilk: {2} | ikinci: {3} | son: {4}" -f $lines.Count, $clock.Elapsed.TotalSeconds, $lines[0], $lines[1], $lines[$lines.Count - 1])
    Check ($exe -like "$jd\tools\java-17\*\bin\java.exe" -and (Test-Path $exe)) "indirildi: $exe"
    $ver = (cmd.exe /d /c "`"$exe`" -version 2>&1" | Out-String)   # java sürümü stderr'e yazar; PowerShell 5.1 onu hata sayar
    Check ($ver -match 'version "17\.' -and $null -eq (Test-JavaRuns $exe 17)) "java -version: $(($ver -split "`r?`n")[0])"
    Check ($lines[0] -ceq (L 'Java {0} indiriliyor...' 17)) "ilk satır: $($lines[0])"
    $prog = @($lines | Select-Object -Skip 1)
    $badLine = @($prog | Where-Object { $_ -notmatch '^OpenJDK17U-jre_x64_windows_hotspot_[0-9._]+\.zip  ·  \d+ / \d+ MB$' })
    Check ($prog.Count -ge 2 -and $badLine.Count -eq 0) "ilerleme satırları '<dosya>  ·  <MB> / <MB> MB' ($($prog.Count) satır) $($badLine -join ' | ')"
    $lastMb = [regex]::Match($prog[$prog.Count - 1], '(\d+) / (\d+) MB$')
    Check ($prog[0] -match '  ·  0 / \d+ MB$' -and $lastMb.Groups[1].Value -eq $lastMb.Groups[2].Value) "ilk ilerleme 0 MB, son ilerleme tam boy ($($lastMb.Value))"
    $gaps = @(for ($k = 2; $k -lt $times.Count - 1; $k++) { $times[$k] - $times[$k - 1] })
    $minGap = if ($gaps.Count) { ($gaps | Measure-Object -Minimum).Minimum } else { 999 }
    Check ($minGap -ge 195) ("en çok saniyede 5 kez (arka arkaya iki satır arası en az {0:0} ms)" -f $minGap)
    Check (@(Get-Leftovers (Join-Path $jd 'tools') 17).Count -eq 0) 'artık yok (zip, tmp, old)'
    Check ((Find-Java 17) -eq $exe) 'yeniden açılışta Find-Java indirilen kopyayı bulur'
    Check ($null -eq (Find-Java 21) -or (Find-Java 21) -notlike "$jd*") "Find-Java 21 hâlâ bilgisayardakini önce verir: $(Find-Java 21)"
    # Tekrar indirme: eski kopya kenara alınıp yenisi tek adımda yerine konur
    $lines.Clear()
    $exe2 = Install-Java 17 $null
    Check ($exe2 -eq $exe -and (Test-Path $exe2) -and @(Get-Leftovers (Join-Path $jd 'tools') 17).Count -eq 0 -and @(Get-ChildItem (Join-Path $jd 'tools\java-17') -Directory).Count -eq 1) 'ikinci indirme eskisinin yerine geçti, artık yok'
    # Arka plan işinde (runspace, L yok): FirstRun ve kurulum böyle kullanır
    $rs = [powershell]::Create()
    [void]$rs.AddScript({ param($funcs, $dataDir) $DataDir = $dataDir; . ([scriptblock]::Create($funcs)); $j = Find-Java 17; [pscustomobject]@{ Java = $j; HasL = [bool](Get-Command L -ErrorAction SilentlyContinue) } }).AddArgument($JavaFuncs.ToString()).AddArgument($jd)
    $rr = @($rs.Invoke()); $rs.Dispose()
    Check ($rr.Count -eq 1 -and $rr[0].Java -eq $exe -and -not $rr[0].HasL) 'runspace içinde $JavaFuncs: Find-Java indirilen kopyayı bulur (L olmadan)'
    # İlk açılıştaki gibi: arka plan işi, ortak (synchronized) tablo, ilk satır -HeadText ile; geri çağrı runspace içinde tanımlı
    $sync = [hashtable]::Synchronized(@{ Text = ''; Lines = (New-Object System.Collections.ArrayList); Error = $null; Done = $false; Exe = $null })
    $rs = [powershell]::Create()
    [void]$rs.AddScript({
        param($funcs, $dataDir, $sync, $head)
        $DataDir = $dataDir; . ([scriptblock]::Create($funcs))
        try { $sync.Exe = Install-Java 17 { param($t) $sync.Text = $t; [void]$sync.Lines.Add($t) } $head } catch { $sync.Error = $_.Exception.Message }
        $sync.Done = $true
    }).AddArgument($JavaFuncs.ToString()).AddArgument($jd).AddArgument($sync).AddArgument((L 'Java {0} indiriliyor...'))
    $h = $rs.BeginInvoke()
    $seen = New-Object System.Collections.Generic.List[string]
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $sync.Done -and $sw.Elapsed.TotalSeconds -lt 300) { if ($seen.Count -eq 0 -or $seen[$seen.Count - 1] -cne $sync.Text) { $seen.Add($sync.Text) }; Start-Sleep -Milliseconds 50 }
    try { $rs.EndInvoke($h) } catch {}; $rs.Dispose()
    $sl = @($sync.Lines)
    Check ($null -eq $sync.Error -and $sync.Exe -eq $exe) "runspace içinde Install-Java: indirdi ($($sync.Exe)) $($sync.Error)"
    Check ($sl.Count -ge 3 -and $sl[0] -ceq (L 'Java {0} indiriliyor...' 17) -and $sl[$sl.Count - 1] -cmatch '^OpenJDK17U-jre_x64_windows_hotspot_[0-9._]+\.zip  ·  (\d+) / \1 MB$') "runspace: ilk satır -HeadText'ten ('$($sl[0])'), son satır tam boy ('$($sl[$sl.Count - 1])')"
    Check ($seen.Count -ge 3) "ana iş parçacığı ilerlemeyi ortak tablodan okudu ($($seen.Count) farklı metin)"
    $DataDir = $Data
}

Section 'Arka plan işleri (runspace): Install-Java ve Portable.ps1'
# Arka plan işinde (runspace) -HeadText verilmezse ve L yoksa ilk satır Türkçe anahtar olur; kalıcı hata yine tek denemede
$sync2 = [hashtable]::Synchronized(@{ Lines = (New-Object System.Collections.ArrayList); Error = $null })
$rs = [powershell]::Create()
[void]$rs.AddScript({ param($funcs, $dataDir, $sync) $DataDir = $dataDir; . ([scriptblock]::Create($funcs)); try { Install-Java 99 { param($t) [void]$sync.Lines.Add($t) } } catch { $sync.Error = $_.Exception.Message } }).AddArgument($JavaFuncs.ToString()).AddArgument($Data).AddArgument($sync2)
[void]$rs.Invoke(); $rs.Dispose()
Check (@($sync2.Lines).Count -ge 1 -and $sync2.Lines[0] -ceq 'Java 99 indiriliyor...' -and $sync2.Error -like 'Java 99 could not be downloaded: The remote server returned an error: (4*') "runspace, -HeadText yok: '$($sync2.Lines[0])', $($sync2.Error)"

# Portable.ps1 bir arka plan işinde de yüklenebilir (Kaldır'ın silme işi gibi): kısayol silme ve durum okuma çalışır
$bgExe = Join-Path $WorkRoot 'rs-app\SyHost.exe'; New-Item -ItemType Directory -Force (Split-Path $bgExe) | Out-Null; [IO.File]::WriteAllText($bgExe, 'x')
Write-Shortcut $desk $bgExe 'rs'
$rs = [powershell]::Create()
[void]$rs.AddScript({ param($src, $appDir, $exe) $AppDir = $appDir; . (Join-Path $src 'Portable.ps1'); $a = Get-LinkState (Get-ShortcutLocations)[0] $exe; Remove-OurShortcuts $exe; $b = Get-LinkState (Get-ShortcutLocations)[0] $exe; "$a>$b" }).AddArgument($SrcDir).AddArgument($AppDir).AddArgument($bgExe)
$rr = @($rs.Invoke()); $rs.Dispose()
Check ($rr.Count -eq 1 -and $rr[0] -ceq 'Ours>Missing' -and -not (Test-Path $desk)) "runspace içinde Portable.ps1: Get-LinkState ve Remove-OurShortcuts ($($rr -join ','))"


# =====================================================================
if ($Font) {
    Section 'Yazı tipi: bu kullanıcıya kur ve kaldır (HKCU + %LOCALAPPDATA%\Microsoft\Windows\Fonts)'
    $rk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($FontRegPath)
    $pre = @(); if ($rk) { $pre = @($rk.GetValueNames() | Where-Object { $_ -like 'Cascadia Mono*' }); $rk.Close() }
    $preFiles = @($FontFiles | ForEach-Object { Get-OurFontFile $_[0] } | Where-Object { Test-Path $_ })
    if ($pre.Count -or $preFiles.Count) { Check $false "kullanıcıda zaten Cascadia Mono kaydı/dosyası var, dokunulmadı: $($pre -join ', ') $($preFiles -join ', ')" }
    else {
        try {
            Check (-not (Test-FontBySyHost)) 'önce: SyHost''un yazı tipi yok'
            Check (Install-FontPerUser) 'Install-FontPerUser: $true'
            $rk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($FontRegPath)
            foreach ($ff in $FontFiles) {
                $path = Get-OurFontFile $ff[0]
                Check ($rk.GetValue($ff[1]) -eq $path -and $rk.GetValueKind($ff[1]) -eq 'String') "HKCU: $($ff[1]) = $path"
                Check ((Test-Path $path) -and (Get-Item $path).Length -eq (Get-Item (Join-Path $AppDir "fonts\$($ff[0])")).Length) "dosya: $path"
            }
            $rk.Close()
            Check (Test-FontBySyHost) 'Test-FontBySyHost: $true'
            Check (Test-FontAvailable) 'Test-FontAvailable: $true'
            Check (Install-FontPerUser) 'ikinci kurulum da $true (dosyalar aynıysa yeniden yazılmaz)'
        } finally {
            $u = Uninstall-FontPerUser
            Check $u 'Uninstall-FontPerUser: $true'
            $rk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($FontRegPath)
            $left = @(); if ($rk) { $left = @($rk.GetValueNames() | Where-Object { $_ -like 'Cascadia Mono*' }); $rk.Close() }
            $leftFiles = @($FontFiles | ForEach-Object { Get-OurFontFile $_[0] } | Where-Object { Test-Path $_ })
            Check ($left.Count -eq 0 -and $leftFiles.Count -eq 0 -and -not (Test-FontBySyHost)) "kaldırıldı: HKCU kaydı ve dosya kalmadı ($($left -join ', ') $($leftFiles -join ', '))"
        }
    }
    # Başkasının kaydına dokunmaz: yolu bizimki olmayan değer silinmez
    $rk = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($FontRegPath)
    $rk.SetValue('Cascadia Mono Bold (TrueType)', 'C:\baska\yer.ttf'); $rk.Close()
    try {
        [void](Uninstall-FontPerUser)
        $rk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($FontRegPath)
        Check ($rk.GetValue('Cascadia Mono Bold (TrueType)') -eq 'C:\baska\yer.ttf') 'Uninstall-FontPerUser başka yolu gösteren kayda dokunmaz'
        $rk.Close()
    } finally { $rk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($FontRegPath, $true); $rk.DeleteValue('Cascadia Mono Bold (TrueType)', $false); $rk.Close() }
}

# =====================================================================
if ($Windows) {
    Section 'Pencereler: klasör seçici, uyarı, pencere simgesi (gizli konsolda açılıp kapatılır)'
    $wOut = Join-Path $WorkRoot 'windows.txt'
    $wScript = Join-Path $WorkRoot 'windows.ps1'
    $closer = @'
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading;
public static class TestCloser {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetDlgItem(IntPtr h, int id);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    public static string Seen = "";
    // Bu süreçteki ilk görünür #32770 penceresini (dialog) bul, başlığını ve metnini kaydet, kapat
    public static void CloseSoon(int ms) {
        uint me = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
        Thread t = new Thread(delegate () {
            DateTime end = DateTime.Now.AddMilliseconds(ms);
            while (DateTime.Now < end) {
                IntPtr found = IntPtr.Zero;
                EnumWindows(delegate (IntPtr h, IntPtr l) {
                    uint pid; GetWindowThreadProcessId(h, out pid);
                    StringBuilder c = new StringBuilder(64); GetClassName(h, c, 64);
                    if (pid == me && c.ToString() == "#32770" && IsWindowVisible(h)) { found = h; return false; }
                    return true;
                }, IntPtr.Zero);
                if (found != IntPtr.Zero) {
                    Thread.Sleep(300);
                    StringBuilder s = new StringBuilder(512); GetWindowText(found, s, 512);
                    StringBuilder x = new StringBuilder(2048); IntPtr st = GetDlgItem(found, 0xFFFF); if (st != IntPtr.Zero) GetWindowText(st, x, 2048);
                    Seen = s.ToString() + "|" + x.ToString();
                    PostMessage(found, 0x0010, IntPtr.Zero, IntPtr.Zero);   // WM_CLOSE
                    return;
                }
                Thread.Sleep(50);
            }
        });
        t.IsBackground = true; t.Start();
    }
}
'@
    $wBody = @"
`$ErrorActionPreference = 'Stop'
Add-Type -Path '$CoreDll'
Add-Type -TypeDefinition @'
$closer
'@
. '$SrcDir\Lang.ps1'; . '$SrcDir\Lang.Screens.ps1'
`$AppDir = '$AppDir'; `$TestFrame = `$null; `$ExePath = '$(Join-Path $WorkRoot 'yok\SyHost.exe')'
. '$SrcDir\Portable.ps1'
`$r = New-Object System.Collections.Generic.List[string]
[TestCloser]::CloseSoon(15000)
`$sw = [Diagnostics.Stopwatch]::StartNew()
`$picked = Pick-Folder 'SyHost deneme: klasör seç' '$(Join-Path $WorkRoot 'yok\daha\derin')'
`$r.Add('pick=' + [string](`$null -eq `$picked) + '|' + [TestCloser]::Seen + '|' + [int]`$sw.ElapsedMilliseconds)
[TestCloser]::Seen = ''
[TestCloser]::CloseSoon(15000)
Show-Alert "SyHost deneme uyarısı:`nikinci satır"
`$r.Add('alert=' + [TestCloser]::Seen.Replace("`r", '\r').Replace("`n", '\n'))
`$h = [TestCloser]::GetConsoleWindow()
`$b0 = [TestCloser]::SendMessage(`$h, 0x7F, [IntPtr]1, [IntPtr]0)
Set-WindowIcon
`$b1 = [TestCloser]::SendMessage(`$h, 0x7F, [IntPtr]1, [IntPtr]0); `$s1 = [TestCloser]::SendMessage(`$h, 0x7F, [IntPtr]0, [IntPtr]0)
`$r.Add('icon=' + (`$h -ne [IntPtr]::Zero) + '|' + (`$b1 -ne [IntPtr]::Zero -and `$b1 -ne `$b0) + '|' + (`$s1 -ne [IntPtr]::Zero) + '|' + `$b0 + '|' + `$b1)
[IO.File]::WriteAllLines('$wOut', `$r.ToArray(), (New-Object Text.UTF8Encoding `$false))
"@
    [IO.File]::WriteAllText($wScript, $wBody, (New-Object Text.UTF8Encoding $true))
    $p = Start-Process "$env:SystemRoot\System32\conhost.exe" -ArgumentList "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$wScript`"" -WindowStyle Hidden -PassThru
    if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch {}; Check $false 'pencere testi bitmedi (60 sn)' }
    $wr = if (Test-Path $wOut) { [IO.File]::ReadAllLines($wOut, [Text.Encoding]::UTF8) } else { @() }
    $pick = @($wr | Where-Object { $_ -like 'pick=*' }) -join ''
    $alert = @($wr | Where-Object { $_ -like 'alert=*' }) -join ''
    $icon = @($wr | Where-Object { $_ -like 'icon=*' }) -join ''
    Check ($pick -like 'pick=True|SyHost deneme: klasör seç|*') "Pick-Folder: modern seçici başlığıyla açıldı, kapatılınca `$null ($pick)"
    Check ($alert -ceq 'alert=SyHost|SyHost deneme uyarısı:\nikinci satır' -or $alert -ceq 'alert=SyHost|SyHost deneme uyarısı:\r\nikinci satır') "Show-Alert: başlık SyHost, metin aynen ($alert)"
    Check ($icon -like 'icon=True|True|True|*') "Set-WindowIcon: konsol penceresinin büyük ve küçük simgesi kondu (SyHost.ico'dan; $icon)"
}

# =====================================================================
Write-Host ''
$color = if ($script:Fail) { 'Red' } else { 'Green' }
Write-Host ("SONUÇ: {0} geçti, {1} hata" -f $script:Pass, $script:Fail) -ForegroundColor $color
exit $(if ($script:Fail) { 1 } else { 0 })
