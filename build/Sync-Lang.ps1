# =====================================================================
#  SyHost - C# sürümünün yeni metinlerini Terminal sürümüne aktarır
#  Kaynak: src\SyHost\App\Lang.Screens.cs, src\SyHost\Setup\Lang.Portable.cs,
#          src\SyHost\Core\Installer.cs (AddInstall), src\SyHost\Core\Tray.cs (AddTray)
#  Hedef : legacy\src\Lang.Screens.ps1 (elle düzenlenmez; bu betikle yeniden üretilir)
#  Temel tablo (legacy\src\Lang.ps1) ile C#'taki Lang.Table.cs zaten aynıdır.
#
#    build\Sync-Lang.ps1          üret
#    build\Sync-Lang.ps1 -Check   yalnızca güncel mi bak (CI için; değilse çıkış kodu 1)
# =====================================================================
[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$sources = @(
    'src\SyHost\App\Lang.Screens.cs',
    'src\SyHost\Setup\Lang.Portable.cs',
    'src\SyHost\Core\Installer.cs',
    'src\SyHost\Core\Tray.cs'
)
$out = Join-Path $repo 'legacy\src\Lang.Screens.ps1'

# C# dizesini çöz: \n \t \" \\ \uXXXX
function ConvertFrom-CsString([string]$s) {
    $sb = New-Object Text.StringBuilder
    for ($i = 0; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($ch -ne '\') { [void]$sb.Append($ch); continue }
        $i++
        switch -CaseSensitive ($s[$i]) {
            'n' { [void]$sb.Append("`n") }
            't' { [void]$sb.Append("`t") }
            '"' { [void]$sb.Append('"') }
            '\' { [void]$sb.Append('\') }
            "'" { [void]$sb.Append("'") }
            '0' { [void]$sb.Append([char]0) }
            'u' { [void]$sb.Append([char][Convert]::ToInt32($s.Substring($i + 1, 4), 16)); $i += 4 }
            default { throw "Bilinmeyen kaçış: \$($s[$i])" }
        }
    }
    $sb.ToString()
}
# PowerShell dizesi yaz: satır sonu yoksa tek tırnak, varsa çift tırnak (`n ile)
function ConvertTo-PsString([string]$s) {
    if ($s -notmatch "[`n`t]") { return "'" + $s.Replace("'", "''") + "'" }
    $e = $s.Replace('`', '``').Replace('"', '`"').Replace('$', '`$').Replace("`n", '`n').Replace("`t", '`t')
    '"' + $e + '"'
}

$strRx = '"((?:[^"\\]|\\.)*)"'
$txRx = [regex]('Tx\(\s*' + $strRx + '\s*,\s*' + $strRx + '\s*,\s*' + $strRx + '\s*\)\s*;')
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# =====================================================================')
$lines.Add('#  SyHost - yeni ekranların metinleri (ilk açılış, ayarlar, kaldır, tepsi, kurulum)')
$lines.Add('#  BU DOSYA ÜRETİLİR: build\Sync-Lang.ps1 (kaynak: C# sürümündeki Tx satırları).')
$lines.Add('#  Elle düzenleme; metni C# tarafında değiştirip betiği yeniden çalıştır.')
$lines.Add('# =====================================================================')
# büyük/küçük harf ayrı: "Hazır" ile "HAZIR" iki ayrı metindir (Lang.ps1'deki tablo da böyle)
$seen = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
$n = 0
foreach ($rel in $sources) {
    $text = [IO.File]::ReadAllText((Join-Path $repo $rel), [Text.Encoding]::UTF8)
    $ms = $txRx.Matches($text)
    if ($ms.Count -eq 0) { throw "$rel içinde Tx bulunamadı" }
    $lines.Add('')
    $lines.Add("# ---------- $rel ----------")
    foreach ($m in $ms) {
        $tr = ConvertFrom-CsString $m.Groups[1].Value
        $en = ConvertFrom-CsString $m.Groups[2].Value
        $ja = ConvertFrom-CsString $m.Groups[3].Value
        # C#'ta sonraki Tx öncekinin üzerine yazar; sıra karışmasın diye farklı çeviri hiç kabul edilmez
        if ($seen.ContainsKey($tr)) { if ($seen[$tr] -cne "$en|$ja") { throw "Aynı anahtar farklı çeviriyle iki kez: $tr" }; continue }
        $seen[$tr] = "$en|$ja"
        $lines.Add('Tx ' + (ConvertTo-PsString $tr) + ' ' + (ConvertTo-PsString $en) + ' ' + (ConvertTo-PsString $ja))
        $n++
    }
}
$content = ($lines -join "`r`n") + "`r`n"
$enc = New-Object Text.UTF8Encoding $true
if ($Check) {
    $cur = if (Test-Path -LiteralPath $out) { [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8) } else { '' }
    if ($cur.TrimStart([char]0xFEFF) -ne $content) { Write-Host 'legacy\src\Lang.Screens.ps1 güncel değil: build\Sync-Lang.ps1 çalıştır.' -ForegroundColor Red; exit 1 }
    Write-Host "Lang.Screens.ps1 güncel ($n metin)."
    exit 0
}
[IO.File]::WriteAllText($out, $content, $enc)
Write-Host "Yazıldı: $out ($n metin)"
