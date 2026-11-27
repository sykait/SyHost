# =====================================================================
#  SyHost - Test-Defender.ps1'in yardımcısı (ayrı bir powershell.exe'de çalışır)
#  legacy\src\*.ps1'deki kod parçalarını PowerShell'e SyHost'un arka plan işlerinin yaptığı gibi verir:
#  her fonksiyon, uzun betik blokları, uzun metin blokları ve dosyanın tamamı. Hepsi bir fonksiyon tanımının
#  içine konur; bir fonksiyon tanımını çalıştırmak yalnızca onu tanımlar, hiçbir SyHost kodu çalışmaz.
#  Çıktı (-Out): her parça için "BEGIN i" ve "END i <ok|ENGELLENDİ|hata> | dosya | tür | ad | uzunluk".
#  Süreç bir parçada kapanırsa çağıran -Start ile kalan yerden devam eder.
# =====================================================================
param(
    [Parameter(Mandatory)][string]$SrcDir,
    [Parameter(Mandatory)][string]$Out,
    [int]$Start = 0
)
$ErrorActionPreference = 'Continue'
$units = New-Object System.Collections.Generic.List[object]
foreach ($file in @(Get-ChildItem -LiteralPath $SrcDir -Filter *.ps1 | Sort-Object Name)) {
    $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tok, [ref]$err)
    foreach ($f in $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $units.Add([pscustomobject]@{ File = $file.Name; Kind = 'fonksiyon'; Name = $f.Name; Text = $f.Extent.Text })
    }
    foreach ($s in $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true)) {
        if ($s.Extent.Text.Length -lt 300) { continue }
        $units.Add([pscustomobject]@{ File = $file.Name; Kind = 'blok'; Name = ('satır ' + $s.Extent.StartLineNumber); Text = ('function __syhost_probe ' + $s.Extent.Text) })
    }
    foreach ($s in $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $a.StringConstantType -in 'SingleQuotedHereString', 'DoubleQuotedHereString' }, $true)) {
        if ($s.Value.Length -lt 200) { continue }
        # Metin bloğu PowerShell değilse (ör. C#) tanım hata verir: bu bir engelleme değildir
        $units.Add([pscustomobject]@{ File = $file.Name; Kind = 'metin'; Name = ('satır ' + $s.Extent.StartLineNumber); Text = ("function __syhost_probe {`r`n" + $s.Value + "`r`n}") })
    }
    $units.Add([pscustomobject]@{ File = $file.Name; Kind = 'dosya'; Name = '(tamamı)'; Text = ("function __syhost_probe {`r`n" + $text + "`r`n}") })
}
if ($Start -eq 0) { "TOTAL $($units.Count)" | Out-File -LiteralPath $Out -Append -Encoding utf8 }
for ($i = $Start; $i -lt $units.Count; $i++) {
    $u = $units[$i]
    "BEGIN $i" | Out-File -LiteralPath $Out -Append -Encoding utf8
    $r = 'ok'
    try { & ([scriptblock]::Create($u.Text)) }
    catch {
        $m = $_.Exception.Message + ' ' + $_.FullyQualifiedErrorId
        $r = if ($m -match 'ScriptContainedMaliciousContent|malicious') { 'ENGELLENDİ' } else { 'hata' }
    }
    ("END {0} {1} | {2} | {3} | {4} | {5}" -f $i, $r, $u.File, $u.Kind, $u.Name, $u.Text.Length) | Out-File -LiteralPath $Out -Append -Encoding utf8
}
'DONE' | Out-File -LiteralPath $Out -Append -Encoding utf8
