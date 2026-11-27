# =====================================================================
#  SyHost - virüs tarayıcılarının kötü amaçlı yazılıma benzettiği kalıplar için denetim (statik, CI'da çalışır)
#    tests\av\Test-Lint.ps1           kaynaklar (src, legacy\src, legacy\SyHost.bat) ve varsa dist\*.exe
#    tests\av\Test-Lint.ps1 -NoExe    yalnızca kaynaklar
#
#  Neden: Windows Defender 2026-11-27'de Terminal sürümünün betiklerini çalışırken engelledi
#  (VirTool:PowerShell/MaleficAms.W). Gizli ve kodlanmış PowerShell, kendini silen cmd döngüsü, betik metninden
#  kod üretme gibi kalıplar kaldırıldı. Bu denetim geri gelmelerini engeller.
#  Kurallar tests\av\lint-rules.json dosyasındadır (bu betik o sözcükleri kendisi taşımasın diye).
#  Kural: bir kalıp asla bölünerek, kodlanarak ya da başka adla geçilmez; kod değiştirilir.
#  Exe'ler de taranır: Terminal sürümü betikleri içinde düz metin olarak taşır, bulut tarayıcıları onları görür.
#  Bilinen ve kalan (düşük önemde) iki konu, bu yüzden henüz kural değil: java süreçlerini WMI/ntdll ile bulmak
#  ve takılan kurulum sürecini kapatmak.
# =====================================================================
[CmdletBinding()]
param([switch]$NoExe)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Spec = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'lint-rules.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json

# Taranacak dosyalar
# (bin ve obj repo içindeki yola göre elenir: repo bir ...\bin\... klasöründe olsa da C# dosyaları taranır)
function Get-RepoRel([IO.FileSystemInfo]$f) { $f.FullName.Substring($Repo.Length) }
$shippedCs = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'src') -Recurse -Filter *.cs | Where-Object { (Get-RepoRel $_) -notmatch '\\(bin|obj)\\' })
$legacyPs = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'legacy\src') -Filter *.ps1)
$legacyCs = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'legacy\src') -Filter *.cs)
$shipped = $shippedCs + $legacyPs + $legacyCs + @(Get-ChildItem -LiteralPath (Join-Path $Repo 'legacy') -Filter *.bat)
$dev = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'tests'), (Join-Path $Repo 'build') -Recurse -File | Where-Object { $_.Extension -eq '.ps1' -and (Get-RepoRel $_) -notmatch '\\tests\\parity\\out\\' }) +
       @(Get-ChildItem -LiteralPath (Join-Path $Repo '.github') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq '.yml' })
$scopes = @{ shipped = $shipped; legacy = $legacyPs + $legacyCs; legacyPs = $legacyPs; all = $shipped + $dev }
if ($shippedCs.Count -lt 10 -or $legacyPs.Count -lt 10) { throw "taranacak dosya bulunamadı (C#: $($shippedCs.Count), PowerShell: $($legacyPs.Count))" }

$fails = New-Object System.Collections.Generic.List[string]
foreach ($r in $Spec.rules) {
    if (-not $scopes.ContainsKey([string]$r.scope)) { throw "lint-rules.json: bilinmeyen kapsam '$($r.scope)' ($($r.name))" }
    # Kültürden bağımsız: tr-TR'de (?i) 'I' ile 'i'yi eşlemezdi
    $rx = New-Object Text.RegularExpressions.Regex ([string]$r.pattern), ([Text.RegularExpressions.RegexOptions]::CultureInvariant)
    $allow = @(if ($r.PSObject.Properties['allow']) { $r.allow })
    foreach ($f in $scopes[$r.scope]) {
        $rel = $f.FullName.Substring($Repo.Length + 1)
        if ($allow -contains $rel) { continue }
        $n = 0
        foreach ($line in [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::UTF8)) {
            $n++
            if ($rx.IsMatch($line)) { $fails.Add(('{0}:{1}  [{2}]  {3}' -f $rel, $n, $r.name, $line.Trim())) }
        }
    }
}

# Derlenmiş exe'ler: betik kalıpları içlerinde düz metin olarak da bulunmamalı (Latin-1/UTF-8 ve iki hizada UTF-16)
if (-not $NoExe) {
    foreach ($exe in @(Get-ChildItem -LiteralPath (Join-Path $Repo 'dist') -Filter *.exe -ErrorAction SilentlyContinue)) {
        $b = [IO.File]::ReadAllBytes($exe.FullName)
        $texts = @([Text.Encoding]::GetEncoding(28591).GetString($b), [Text.Encoding]::Unicode.GetString($b))
        if ($b.Length -gt 1) { $texts += [Text.Encoding]::Unicode.GetString($b, 1, $b.Length - 1) }
        foreach ($tok in $Spec.exeTokens) {
            foreach ($t in $texts) { if ($t.IndexOf($tok, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $fails.Add(('dist\{0}  [exe içinde metin]  {1}' -f $exe.Name, $tok)); break } }
        }
        Write-Host ("  taranan exe: {0} ({1:N1} MB)" -f $exe.Name, ($b.Length / 1MB)) -ForegroundColor DarkGray
    }
}

Write-Host ("  kurallar: {0}, dağıtılan kaynak dosya: {1}" -f @($Spec.rules).Count, $shipped.Count) -ForegroundColor DarkGray
if ($fails.Count -gt 0) {
    foreach ($l in $fails) { Write-Host "  YASAK  $l" -ForegroundColor Red }
    Write-Host "$($fails.Count) yasak kalıp bulundu" -ForegroundColor Red
    exit 1
}
Write-Host 'Yasak kalıp yok' -ForegroundColor Green
