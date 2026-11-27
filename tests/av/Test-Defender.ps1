# =====================================================================
#  SyHost - Windows Defender ile yerel denetim (sürüm çıkmadan önce; CI'da değil)
#    tests\av\Test-Defender.ps1              betikler + dist\*.exe
#    tests\av\Test-Defender.ps1 -NoExe       yalnızca betikler
#  Hiçbir şeyi değiştirmez ve SyHost'u çalıştırmaz:
#    1) legacy\src\*.ps1'deki kod parçalarını PowerShell'e verir (Probe-Scripts.ps1; yalnızca tanımlar).
#       Defender bir parçayı engellerse "ENGELLENDİ" yazar: o kod değiştirilmelidir.
#    2) dist\*.exe'lerin internetten inmiş gibi işaretli kopyalarını ve Terminal sürümünün çıkardığı uygulamayı
#       MpCmdRun ile tarar (bulut koruması açıksa bulut da sorulur).
#    3) Defender'ın tespit listesini başta ve sonda karşılaştırır: yeni bir tespit varsa hata.
#  Bir şey engellenirse Windows Güvenliği bildirim gösterir. Defender'a asla dışlama eklenmez.
#  Not: bu yalnızca bugünkü imzalara karşı bir denetimdir; imzasız yeni bir exe'nin bulutta nasıl
#  değerlendirileceğini garanti etmez (bkz. README: Güvenlik ve virüs tarayıcıları).
# =====================================================================
[CmdletBinding()]
param([switch]$NoExe)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Work = Join-Path ([IO.Path]::GetTempPath()) ('syhost-defender-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($Work)
$Ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$MpCmd = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
$fails = 0
function Check([bool]$ok, [string]$name) {
    if ($ok) { Write-Host "  ok    $name" -ForegroundColor Green } else { Write-Host "  HATA  $name" -ForegroundColor Red; $script:fails++ }
}
function Get-Detections { @(try { Get-MpThreatDetection -ErrorAction Stop } catch { }) }

$t0 = Get-Date
$before = @(Get-Detections | ForEach-Object { [string]$_.DetectionID })
try { $st = Get-MpComputerStatus -ErrorAction Stop; Write-Host ("  Defender: gerçek zamanlı koruma {0}, imzalar {1}" -f $(if ($st.RealTimeProtectionEnabled) { 'açık' } else { 'KAPALI' }), $st.AntivirusSignatureVersion) -ForegroundColor DarkGray }
catch { Write-Host '  Defender durumu okunamadı (başka bir virüs tarayıcısı olabilir)' -ForegroundColor Yellow }

try {
    # ---------- 1) Betik parçaları ----------
    $out = Join-Path $Work 'probe.txt'
    $start = 0
    for ($run = 0; $run -lt 20; $run++) {
        & $Ps -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $PSScriptRoot 'Probe-Scripts.ps1') -SrcDir (Join-Path $Repo 'legacy\src') -Out $out -Start $start | Out-Null
        $lines = @(Get-Content -LiteralPath $out -Encoding UTF8)
        if ($lines -contains 'DONE') { break }
        $last = @($lines | Where-Object { $_ -like 'BEGIN *' }) | Select-Object -Last 1
        if (-not $last) { break }
        $i = [int]$last.Split(' ')[1]
        "END $i ENGELLENDİ | (süreç bu parçada kapandı)" | Out-File -LiteralPath $out -Append -Encoding utf8
        $start = $i + 1
    }
    $lines = @(Get-Content -LiteralPath $out -Encoding UTF8)
    $total = ($lines | Where-Object { $_ -like 'TOTAL *' } | Select-Object -First 1) -replace 'TOTAL ', ''
    $blocked = @($lines | Where-Object { $_ -match '^END \d+ ENGELLENDİ' })
    $errors = @($lines | Where-Object { $_ -match '^END \d+ hata' })
    foreach ($b in $blocked) { Write-Host "      $b" -ForegroundColor Red }
    foreach ($e in $errors) { Write-Host "      (PowerShell değil, atlandı) $e" -ForegroundColor DarkGray }
    Check (($lines -contains 'DONE') -and $blocked.Count -eq 0) "betik parçaları: $total parça, engellenen $($blocked.Count)"

    # ---------- 2) Exe'ler ve çıkarılan uygulama ----------
    if (-not $NoExe) {
        if (-not (Test-Path -LiteralPath $MpCmd)) { Check $false "MpCmdRun bulunamadı: $MpCmd" }
        else {
            foreach ($exe in @(Get-ChildItem -LiteralPath (Join-Path $Repo 'dist') -Filter *.exe -ErrorAction SilentlyContinue)) {
                $copy = Join-Path $Work ('indirilen-' + $exe.Name)
                Copy-Item -LiteralPath $exe.FullName -Destination $copy
                # GitHub'dan inmiş gibi: Windows'un kendi koyduğu "internetten geldi" işareti (ZoneId=3)
                Set-Content -LiteralPath $copy -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3`r`nHostUrl=https://github.com/sykait/SyHost/releases/download/test/$($exe.Name)"
                $o = & $MpCmd -Scan -ScanType 3 -File $copy -DisableRemediation 2>&1 | Out-String
                Check ($LASTEXITCODE -eq 0 -and $o -match 'found no threats') "$($exe.Name): MpCmdRun temiz (internetten inmiş kopya)"
            }
            $term = Join-Path $Repo 'dist\SyHost-Terminal.exe'
            if (Test-Path -LiteralPath $term) {
                $app = Join-Path $Work 'App'
                $p = Start-Process -FilePath $term -ArgumentList '--selftest', 'extract', "`"$app`"" -Wait -PassThru
                $o = & $MpCmd -Scan -ScanType 3 -File $app -DisableRemediation 2>&1 | Out-String
                Check ($p.ExitCode -eq 0 -and $LASTEXITCODE -eq 0 -and $o -match 'found no threats') 'Terminal sürümünün çıkardığı uygulama: MpCmdRun temiz'
            }
        }
    }
} finally {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------- 3) Yeni tespit var mı? ----------
Start-Sleep -Seconds 2
$new = @(Get-Detections | Where-Object { $before -notcontains [string]$_.DetectionID -and $_.InitialDetectionTime -ge $t0.AddSeconds(-5) })
foreach ($d in $new) { Write-Host ("      tespit: {0}  {1}  {2}" -f $d.InitialDetectionTime, $d.ThreatID, ($d.Resources -join ' | ')) -ForegroundColor Red }
Check ($new.Count -eq 0) "Defender bu denetim sırasında yeni bir tehdit bildirmedi ($($new.Count))"

if ($fails) { Write-Host "$fails denetim başarısız" -ForegroundColor Red; exit 1 }
Write-Host 'Defender denetimi temiz' -ForegroundColor Green
