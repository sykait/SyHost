# =====================================================================
#  SyHost - Terminal sürümünün tek exe'si (dist\SyHost-Terminal.exe) için denetim
#    tests\terminal\Test-TerminalExe.ps1               dist\SyHost-Terminal.exe
#    tests\terminal\Test-TerminalExe.ps1 -Exe <yol>    başka bir derleme
#  Pencere açmaz, uygulamayı başlatmaz: gizli öz denetimle (--selftest extract) gömülü uygulamayı
#  geçici bir klasöre çıkarır ve şunlara bakar:
#    - her dosya repodakiyle bayt bayt aynı (legacy\src, config, fonts, simgeler)
#    - bin\SyHost.Core.dll Windows PowerShell 5.1'de yüklenir (SyHost.ps1'deki Add-Type -Path gibi)
#    - App\version.txt sürümü exe'nin sürümüyle aynı
#    - exe bir Windows (GUI) uygulaması: açılırken boş konsol penceresi yanıp sönmez
#  Geçici klasör sonunda silinir.
# =====================================================================
[CmdletBinding()]
param([string]$Exe)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Exe) { $Exe = Join-Path $Repo 'dist\SyHost-Terminal.exe' }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('syhost-terminal-test-' + [guid]::NewGuid().ToString('N'))
$fails = 0
function Check([string]$name, [bool]$ok) {
    if ($ok) { Write-Host "  ok    $name" -ForegroundColor Green } else { Write-Host "  FAIL  $name" -ForegroundColor Red; $script:fails++ }
}

try {
    # Exe'nin alt sistemi (PE başlığı): 2 = Windows GUI, 3 = konsol
    $b = [IO.File]::ReadAllBytes($Exe)
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    $subsystem = [BitConverter]::ToUInt16($b, $pe + 24 + 68)
    Check "Windows (GUI) exe, no console window of its own (subsystem $subsystem)" ($subsystem -eq 2)
    $vi = (Get-Item -LiteralPath $Exe).VersionInfo
    # Derlemenin adı SyHost (kurulunca SyHost.exe olarak kopyalanır; sürüm bilgisi ana sürümünkiyle aynı biçimde)
    Check "version info: $($vi.ProductName) $($vi.FileVersion), assembly $($vi.OriginalFilename)" ($vi.ProductName -eq 'SyHost' -and $vi.FileVersion -and $vi.OriginalFilename -eq 'SyHost.dll')

    $p = Start-Process -FilePath $Exe -ArgumentList '--selftest', 'extract', "`"$work`"" -Wait -PassThru
    Check "--selftest extract (exit $($p.ExitCode))" ($p.ExitCode -eq 0)

    $map = [ordered]@{}
    Get-ChildItem -Path (Join-Path $Repo 'legacy\src\*.ps1'), (Join-Path $Repo 'legacy\src\*.cs') | ForEach-Object { $map["src\$($_.Name)"] = $_.FullName }
    $map['config\default-settings.json'] = Join-Path $Repo 'legacy\config\default-settings.json'
    Get-ChildItem -LiteralPath (Join-Path $Repo 'legacy\fonts') -File | ForEach-Object { $map["fonts\$($_.Name)"] = $_.FullName }
    $assets = Join-Path $Repo 'src\SyHost\Assets'
    Get-ChildItem -Path (Join-Path $assets 'icons\*.ico'), (Join-Path $assets 'SyHost.ico'), (Join-Path $assets 'server-icon.png') | ForEach-Object { $map["icons\$($_.Name)"] = $_.FullName }
    $bad = @($map.Keys | Where-Object { -not (Test-Path -LiteralPath (Join-Path $work $_)) -or (Get-FileHash -LiteralPath (Join-Path $work $_)).Hash -ne (Get-FileHash -LiteralPath $map[$_]).Hash })
    Check "$($map.Count) app files identical to the repo$(if ($bad) { ': ' + ($bad -join ', ') })" ($bad.Count -eq 0)
    $extra = @(Get-ChildItem -LiteralPath $work -Recurse -File | ForEach-Object { $_.FullName.Substring($work.Length + 1) } | Where-Object { -not $map.Contains($_) -and $_ -ne 'version.txt' -and $_ -ne 'bin\SyHost.Core.dll' })
    Check "no unexpected files$(if ($extra) { ': ' + ($extra -join ', ') })" ($extra.Count -eq 0)

    $marker = @([IO.File]::ReadAllLines((Join-Path $work 'version.txt')))
    Check "version.txt: $($marker[0]) + payload hash" ($marker.Count -eq 2 -and $vi.FileVersion -like "$($marker[0])*" -and $marker[1] -match '^[0-9a-f]{64}$')

    # Ayrı bir Windows PowerShell 5.1 sürecinde (DLL bu süreci kilitlemesin, klasör silinebilsin)
    $dll = Join-Path $work 'bin\SyHost.Core.dll'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $types = & $ps -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -Path '$($dll.Replace("'", "''"))'; 'Native', 'Tray', 'Server', 'JobGuard', 'CloseGuard', 'Backup' | Where-Object { ('SyHost.' + `$_) -as [type] }"
    Check "SyHost.Core.dll loads in Windows PowerShell 5.1 ($(@($types).Count) core types)" (@($types).Count -eq 6)
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check 'temporary folder removed' (-not (Test-Path -LiteralPath $work))
if ($fails) { Write-Host "$fails check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'Terminal exe OK' -ForegroundColor Green
