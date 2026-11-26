# =====================================================================
#  SyHost - iki sürümün ekran eşliği testi (parity)
#  Her senaryo hem C# sürümünde (SyHost.exe --frame) hem Terminal
#  sürümünde (SyHost.ps1 -TestFrame) tek bir kare olarak çizilir.
#  İki çıktı bayt bayt aynı olmalıdır.
#
#    tests\parity\Run-Parity.ps1                    hepsi (önce dist\SyHost.exe derlenir)
#    tests\parity\Run-Parity.ps1 -Filter 'home-*'   yalnızca adı uyan senaryolar
#    tests\parity\Run-Parity.ps1 -NoBuild           var olan dist\SyHost.exe ile
#
#  Senaryo biçimi: src\SyHost\App\App.cs (RunFrameTest, ApplyScenario).
#  Yalnızca bu betiğin okuduğu alanlar:
#    lang     dil: tr | en | ja                 -> ayarlar.json "dil"
#    cfg      ayar alanları                     -> legacy\config\default-settings.json ile birleştirilir
#    servers  sunucu listesi                    -> sunucular.json
#  Farklar: tests\parity\out\<senaryo>.diff.txt (ESC karakteri ␛ olarak yazılır).
#  Çalışma klasörü: <WorkRoot>\<senaryo>\ (her çalıştırmada yeniden kurulur, sonra incelenebilsin diye kalır)
#    cs\Data\{ayarlar.json,sunucular.json}   cs.txt    C# sürümü (--root cs)
#    ps\SyHost\{ayarlar.json,sunucular.json} ps.txt    Terminal sürümü (LOCALAPPDATA = ps)
# =====================================================================
[CmdletBinding()]
param(
    [string]$Filter = '*',
    [switch]$NoBuild,
    [string]$WorkRoot = 'D:\SyHostTest\parity\run',
    [ValidateRange(1, 16)][int]$Parallel = 4
)
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$Repo = Split-Path -Parent (Split-Path -Parent $Here)
$Exe = Join-Path $Repo 'dist\SyHost.exe'
$PsApp = Join-Path $Repo 'legacy\src\SyHost.ps1'
$OutDir = Join-Path $Here 'out'
$Utf8 = New-Object Text.UTF8Encoding $false
$Esc = [string][char]27
$AnsiRx = [regex]"$Esc\[[0-9;?]*[A-Za-z]"
$WideRx = [regex]'[ᄀ-ᅟ⺀-〾ぁ-㏿㐀-䶿一-鿿ꀀ-꓏가-힣豈-﫿︰-﹏＀-｠￠-￦]'

# ---------- C# sürümünü derle ----------
if (-not $NoBuild) {
    Write-Host 'C# sürümü derleniyor (build\Build.ps1 -Publish)...' -ForegroundColor DarkGray
    $ErrorActionPreference = 'Continue'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'build\Build.ps1') -Publish | Out-Host
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($code -ne 0) { throw "Derleme başarısız (kod $code)" }
}
if (-not (Test-Path $Exe)) { throw "$Exe bulunamadı. -NoBuild olmadan çalıştır." }

$files = @(Get-ChildItem (Join-Path $Here 'scenarios') -Filter *.json | Where-Object { $_.BaseName -like $Filter } | Sort-Object Name)
if ($files.Count -eq 0) { throw "Senaryo bulunamadı: $Filter" }
New-Item -ItemType Directory -Force $OutDir, $WorkRoot | Out-Null
$DefaultCfg = [IO.File]::ReadAllText((Join-Path $Repo 'legacy\config\default-settings.json'), [Text.Encoding]::UTF8)

# ---------- yardımcılar ----------
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $Utf8) }

# Ayarları birleştir: iç içe nesneler (paketler.normal.ramMax gibi) alan alan, gerisi doğrudan
function Merge-Json($dst, $src) {
    foreach ($p in $src.PSObject.Properties) {
        $cur = $dst.PSObject.Properties[$p.Name]
        if ($cur -and $cur.Value -is [System.Management.Automation.PSCustomObject] -and $p.Value -is [System.Management.Automation.PSCustomObject]) { Merge-Json $cur.Value $p.Value }
        else { $dst | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    }
}

# Senaryonun çalışma klasörünü kur: iki sürüme aynı ayarlar ve sunucu listesi
function New-Workspace($t) {
    if (Test-Path $t.Dir) { Remove-Item $t.Dir -Recurse -Force }
    New-Item -ItemType Directory -Force (Join-Path $t.Dir 'cs\Data'), (Join-Path $t.Dir 'ps\SyHost'), (Join-Path $t.Dir 'cs-localappdata') | Out-Null
    $sc = $t.Scenario
    $cfg = $DefaultCfg | ConvertFrom-Json
    if ($null -ne $sc.cfg) { Merge-Json $cfg $sc.cfg }
    if ($null -ne $sc.lang) { $cfg | Add-Member -NotePropertyName dil -NotePropertyValue ([string]$sc.lang) -Force }
    $cfg | Add-Member -NotePropertyName paketlerAyarlandi -NotePropertyValue $true -Force
    $cfgJson = ConvertTo-Json -InputObject $cfg -Depth 10
    $srvJson = if ($null -eq $sc.servers) { '[]' } else { ConvertTo-Json -InputObject @($sc.servers) -Depth 10 }
    foreach ($d in (Join-Path $t.Dir 'cs\Data'), (Join-Path $t.Dir 'ps\SyHost')) {
        Write-Utf8 (Join-Path $d 'ayarlar.json') $cfgJson
        Write-Utf8 (Join-Path $d 'sunucular.json') $srvJson
    }
}

# C# sürümü: konsol gerekmez, çıktısı ve hatası yakalanır
function Invoke-CsFrame($t) {
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe
    $psi.Arguments = "--frame `"$($t.File)`" `"$($t.CsOut)`" --root `"$(Join-Path $t.Dir 'cs')`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $t.Dir
    # gerçek kullanıcı verisine (LOCALAPPDATA\SyHost) hiçbir koşulda dokunmasın
    $psi.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $t.Dir 'cs-localappdata'
    $p = [Diagnostics.Process]::Start($psi)
    $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch {}; $t.CsError = 'zaman aşımı (60 sn)'; return }
    $p.WaitForExit()
    $t.CsCode = $p.ExitCode
    $msg = ($so.Result + $se.Result).Trim()
    if ($p.ExitCode -ne 0 -or -not (Test-Path $t.CsOut)) { $t.CsError = "çıkış kodu $($p.ExitCode)" + $(if ($msg) { "`n$msg" } else { '' }) }
}

# Terminal sürümü: gerçek (gizli) bir konsol penceresinde, LOCALAPPDATA senaryonun klasörü
function Start-PsFrame($t) {
    $old = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = Join-Path $t.Dir 'ps'
    try {
        $a = "-NoProfile -ExecutionPolicy Bypass -File `"$PsApp`" -TestFrame `"$($t.File)`" -TestOut `"$($t.PsOut)`""
        $p = Start-Process powershell.exe -ArgumentList $a -WorkingDirectory $t.Dir -WindowStyle Hidden -PassThru
        $null = $p.Handle   # çıkış kodunu sonra okuyabilmek için
        $t.Proc = $p; $t.Started = [DateTime]::Now
    } finally { $env:LOCALAPPDATA = $old }
}
function Complete-PsFrame($t) {
    $p = $t.Proc
    if (-not $p.HasExited) { try { $p.Kill() } catch {}; $t.PsError = 'zaman aşımı (120 sn)'; return }
    $p.WaitForExit()
    $t.PsCode = $p.ExitCode
    $err = $t.PsOut + '.error.txt'
    if ($p.ExitCode -ne 0 -or -not (Test-Path $t.PsOut)) {
        $t.PsError = "çıkış kodu $($p.ExitCode)" + $(if (Test-Path $err) { "`n" + [IO.File]::ReadAllText($err, [Text.Encoding]::UTF8).Trim() } else { '' })
    }
}

# Fark dosyası: farklı her satır için iki sürüm, ESC = ␛, ilk farklı karakter ve ekran sütunu
function Show-Esc([string]$s) { $s.Replace($Esc, '␛') }
function Get-ScreenCol([string]$prefix) {
    $i = $prefix.LastIndexOf($Esc)
    if ($i -ge 0 -and -not $AnsiRx.Match($prefix, $i).Success) { $prefix = $prefix.Substring(0, $i) }   # yarım kalmış renk kodu
    $plain = $AnsiRx.Replace($prefix, '')
    $plain.Length + $WideRx.Matches($plain).Count + 1
}
function Write-Diff($t) {
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("Senaryo : $($t.Name)  ($($t.File))")
    [void]$sb.AppendLine("C#      : $($t.CsOut)")
    [void]$sb.AppendLine("Terminal: $($t.PsOut)")
    if ($t.CsError) { [void]$sb.AppendLine("C# sürümü çalışmadı: $($t.CsError)") }
    if ($t.PsError) { [void]$sb.AppendLine("Terminal sürümü çalışmadı: $($t.PsError)") }
    if (-not $t.CsError -and -not $t.PsError) {
        $cl = [IO.File]::ReadAllText($t.CsOut, [Text.Encoding]::UTF8) -split "`n"
        $pl = [IO.File]::ReadAllText($t.PsOut, [Text.Encoding]::UTF8) -split "`n"
        $n = [Math]::Max($cl.Count, $pl.Count); $diff = 0
        $body = New-Object Text.StringBuilder
        for ($i = 0; $i -lt $n; $i++) {
            $a = if ($i -lt $cl.Count) { $cl[$i] } else { $null }
            $b = if ($i -lt $pl.Count) { $pl[$i] } else { $null }
            if ($a -ceq $b) { continue }
            $diff++
            if ($null -eq $a -or $null -eq $b) {
                [void]$body.AppendLine(''); [void]$body.AppendLine("satır $($i + 1): yalnızca " + $(if ($null -eq $a) { 'Terminal sürümünde var' } else { 'C# sürümünde var' }))
                [void]$body.AppendLine('  C#      : ' + $(if ($null -ne $a) { Show-Esc $a } else { '(yok)' }))
                [void]$body.AppendLine('  Terminal: ' + $(if ($null -ne $b) { Show-Esc $b } else { '(yok)' }))
                continue
            }
            $k = 0; $m = [Math]::Min($a.Length, $b.Length)
            while ($k -lt $m -and $a[$k] -ceq $b[$k]) { $k++ }
            $from = [Math]::Max(0, $k - 40)
            [void]$body.AppendLine('')
            [void]$body.AppendLine("satır $($i + 1): ilk fark $($k + 1). karakterde (ekran sütunu $(Get-ScreenCol $a.Substring(0, $k)))")
            [void]$body.AppendLine('  C#      : ' + (Show-Esc $a))
            [void]$body.AppendLine('  Terminal: ' + (Show-Esc $b))
            [void]$body.AppendLine('  C#   yazı: ' + $AnsiRx.Replace($a, ''))
            [void]$body.AppendLine('  Term yazı: ' + $AnsiRx.Replace($b, ''))
            [void]$body.AppendLine('  C#   farkta: …' + (Show-Esc $a.Substring($from, [Math]::Min($a.Length - $from, 100))))
            [void]$body.AppendLine('  Term farkta: …' + (Show-Esc $b.Substring($from, [Math]::Min($b.Length - $from, 100))))
        }
        [void]$sb.AppendLine("Satırlar: C# $($cl.Count), Terminal $($pl.Count); farklı satır: $diff (satır numaraları 1'den başlar, son satır imleç: #cursor)")
        [void]$sb.Append($body.ToString())
        $t.DiffLines = $diff
    }
    Write-Utf8 $t.DiffFile $sb.ToString()
}

# ---------- çalıştır ----------
$tasks = @(foreach ($f in $files) {
    $dir = Join-Path $WorkRoot $f.BaseName
    $diffFile = Join-Path $OutDir ($f.BaseName + '.diff.txt')
    if (Test-Path $diffFile) { Remove-Item $diffFile -Force }
    [pscustomobject]@{ Name = $f.BaseName; File = $f.FullName; Dir = $dir; CsOut = (Join-Path $dir 'cs.txt'); PsOut = (Join-Path $dir 'ps.txt'); DiffFile = $diffFile
        Scenario = $null; Proc = $null; Started = $null; CsCode = $null; PsCode = $null; CsError = $null; PsError = $null; DiffLines = 0; Pass = $false; Done = $false }
})
$sw = [Diagnostics.Stopwatch]::StartNew()
Write-Host ("{0} senaryo, çalışma klasörü {1}" -f $tasks.Count, $WorkRoot) -ForegroundColor DarkGray

# Terminal sürümü yardımcı kodu (SyHost.Core.cs) ilk senaryoda bir kez derlenir, sonra kopyalanır
$CoreDll = $null
$queue = New-Object System.Collections.Generic.Queue[object]
foreach ($t in $tasks) { $queue.Enqueue($t) }
$running = New-Object System.Collections.Generic.List[object]
$pass = 0; $fail = 0
function Finish-Task($t) {
    Complete-PsFrame $t
    if (-not $t.CsError -and -not $t.PsError) {
        $a = [IO.File]::ReadAllBytes($t.CsOut); $b = [IO.File]::ReadAllBytes($t.PsOut)
        $t.Pass = ($a.Length -eq $b.Length) -and [Convert]::ToBase64String($a) -ceq [Convert]::ToBase64String($b)
    }
    if ($t.Pass) { $script:pass++; Write-Host ('PASS  ' + $t.Name) -ForegroundColor Green }
    else {
        $script:fail++
        Write-Diff $t
        $why = if ($t.CsError) { 'C# sürümü çalışmadı' } elseif ($t.PsError) { 'Terminal sürümü çalışmadı' } else { "$($t.DiffLines) satır farklı" }
        Write-Host ('FAIL  {0}  ({1})' -f $t.Name, $why) -ForegroundColor Red
    }
    $t.Done = $true
}
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    # ilk senaryo bitip derlenmiş dll hazır olana kadar tek tek
    $limit = if ($CoreDll) { $Parallel } else { 1 }
    while ($queue.Count -gt 0 -and $running.Count -lt $limit) {
        $t = $queue.Dequeue()
        try {
            $t.Scenario = [IO.File]::ReadAllText($t.File, [Text.Encoding]::UTF8) | ConvertFrom-Json
            New-Workspace $t
            if ($CoreDll) { $cd = Join-Path $t.Dir 'ps\SyHost\cache'; New-Item -ItemType Directory -Force $cd | Out-Null; Copy-Item $CoreDll $cd }
            Invoke-CsFrame $t
            Start-PsFrame $t
            $running.Add($t)
        } catch {
            $t.PsError = "senaryo hazırlanamadı: $($_.Exception.Message)"
            $fail++; Write-Diff $t; Write-Host ('FAIL  {0}  ({1})' -f $t.Name, $t.PsError) -ForegroundColor Red
        }
    }
    foreach ($t in $running.ToArray()) {
        if ($t.Proc.HasExited -or ([DateTime]::Now - $t.Started).TotalSeconds -gt 120) {
            $running.Remove($t) | Out-Null
            Finish-Task $t
            if (-not $CoreDll) {
                $dll = Join-Path $t.Dir 'ps\SyHost\cache\SyHost.Core.dll'
                if (Test-Path $dll) { $CoreDll = Join-Path $WorkRoot 'SyHost.Core.dll'; Copy-Item $dll $CoreDll -Force }
                else { $CoreDll = '' }
            }
        }
    }
    if ($running.Count -gt 0) { Start-Sleep -Milliseconds 100 }
}

Write-Host ''
$color = if ($fail) { 'Red' } else { 'Green' }
Write-Host ("Sonuç: {0} PASS, {1} FAIL (toplam {2}, {3:0} sn)" -f $pass, $fail, $tasks.Count, $sw.Elapsed.TotalSeconds) -ForegroundColor $color
if ($fail) { Write-Host "Farklar: $OutDir" -ForegroundColor DarkGray }
exit $(if ($fail) { 1 } else { 0 })
