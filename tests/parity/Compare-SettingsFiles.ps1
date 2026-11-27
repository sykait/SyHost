# =====================================================================
#  SyHost - tuş senaryolarından sonra iki sürümün yazdığı ayarlar.json'ı karşılaştırır
#  Run-Parity.ps1'den sonra, aynı -WorkRoot ile çalıştır:
#    tests\parity\Run-Parity.ps1 -NoBuild -Filter 'set-keys-*' -WorkRoot D:\SyHostTest\parity\run
#    tests\parity\Compare-SettingsFiles.ps1 -Filter 'set-keys-*' -WorkRoot D:\SyHostTest\parity\run
#  Her senaryo için:
#    - <WorkRoot>\<senaryo>\cs\Data\ayarlar.json ile ps\Data\ayarlar.json alan alan aynı mı
#      (eksik alan null sayılır: C# boş alanları null yazar, Terminal sürümü hiç yazmaz)
#    - senaryodaki settingsAfter alanları iki dosyada da beklenen değerde mi
#    - shortcutsAfter: senaryo klasöründeki kısayollar (shortcuts\Desktop, shortcuts\Programs) var mı
#    - shortcutDescAfter: Masaüstü kısayolunun açıklaması
#  Kısayol klasörü iki sürümde ortaktır ve Terminal sürümü ikinci çalışır: kısayollar onun son hâlidir.
# =====================================================================
[CmdletBinding()]
param([string]$Filter = 'set-keys-*', [string]$WorkRoot = 'D:\SyHostTest\parity\run')
$ErrorActionPreference = 'Stop'
$Inv = [Globalization.CultureInfo]::InvariantCulture

# JSON değerini karşılaştırılabilir yazıya çevir: sayılar tek biçimde (3 = 3.0), türler ayrı
function Format-Value($v) {
    if ($null -eq $v) { return 'null' }
    if ($v -is [bool]) { if ($v) { return 'true' }; return 'false' }
    if ($v -is [string]) { return 's:' + $v }
    if ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) { return 'n:' + ([double]$v).ToString('R', $Inv) }
    'x:' + [string]$v
}
# İç içe nesneleri "paketler.normal.ramMax" gibi yollarla düzleştir
function Add-Flat($obj, [string]$prefix, [hashtable]$into) {
    foreach ($p in $obj.PSObject.Properties) {
        $k = $prefix + $p.Name
        if ($p.Value -is [System.Management.Automation.PSCustomObject]) { Add-Flat $p.Value ($k + '.') $into }
        elseif ($p.Value -is [array]) { $into[$k] = 'a:' + ((@($p.Value) | ForEach-Object { Format-Value $_ }) -join ',') }
        else { $into[$k] = Format-Value $p.Value }
    }
}
function Read-Flat([string]$path) {
    $h = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    Add-Flat ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json) '' $h
    $h
}
function Get-Flat([hashtable]$h, [string]$k) { if ($h.ContainsKey($k)) { return $h[$k] }; 'null' }

# Kısayolun açıklamasını Unicode oku (IShellLinkW). WScript.Shell ANSI'den geçirir: Japonca metin '?' olur.
function Get-LinkDescription([string]$lnk) {
    if (-not ('SyHostParity.ShellLinkFile' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
namespace SyHostParity
{
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cch);
    }
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    class CShellLink { }
    public static class ShellLinkFile
    {
        public static string Description(string path)
        {
            object o = new CShellLink();
            try
            {
                ((IPersistFile)o).Load(path, 0);
                StringBuilder sb = new StringBuilder(1024);
                ((IShellLinkW)o).GetDescription(sb, sb.Capacity);
                return sb.ToString();
            }
            finally { Marshal.ReleaseComObject(o); }
        }
    }
}
'@
    }
    [SyHostParity.ShellLinkFile]::Description($lnk)
}

$files = @(Get-ChildItem (Join-Path $PSScriptRoot 'scenarios') -Filter *.json | Where-Object { $_.BaseName -like $Filter } | Sort-Object Name)
if ($files.Count -eq 0) { throw "Senaryo bulunamadı: $Filter" }
$pass = 0; $fail = 0
foreach ($f in $files) {
    $sc = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $dir = Join-Path $WorkRoot $f.BaseName
    $problems = New-Object System.Collections.Generic.List[string]
    $csFile = Join-Path $dir 'cs\Data\ayarlar.json'; $psFile = Join-Path $dir 'ps\Data\ayarlar.json'
    if (-not (Test-Path -LiteralPath $csFile) -or -not (Test-Path -LiteralPath $psFile)) { $problems.Add('ayarlar.json yok (önce Run-Parity.ps1 aynı -WorkRoot ile çalışmalı)') }
    else {
        $a = Read-Flat $csFile; $b = Read-Flat $psFile
        foreach ($k in (@($a.Keys) + @($b.Keys) | Sort-Object -Unique -CaseSensitive)) {
            $va = Get-Flat $a $k; $vb = Get-Flat $b $k
            if ($va -cne $vb) { $problems.Add("$k  C#=$va  Terminal=$vb") }
        }
        if ($null -ne $sc.settingsAfter) {
            foreach ($p in $sc.settingsAfter.PSObject.Properties) {
                $want = Format-Value $p.Value
                $ga = Get-Flat $a $p.Name; $gb = Get-Flat $b $p.Name
                if ($ga -cne $want) { $problems.Add("C# $($p.Name)=$ga (beklenen $want)") }
                if ($gb -cne $want) { $problems.Add("Terminal $($p.Name)=$gb (beklenen $want)") }
            }
        }
    }
    if ($null -ne $sc.shortcutsAfter) {
        foreach ($loc in @(@('desktop', 'Desktop'), @('start', 'Programs'))) {
            $want = $sc.shortcutsAfter.($loc[0])
            if ($null -eq $want) { continue }
            $have = Test-Path -LiteralPath (Join-Path $dir "shortcuts\$($loc[1])\SyHost.lnk")
            if ($have -ne [bool]$want) { $problems.Add("kısayol $($loc[0]): " + $(if ($have) { 'var' } else { 'yok' }) + ' (beklenen ' + $(if ($want) { 'var' } else { 'yok' }) + ')') }
        }
    }
    if ($null -ne $sc.shortcutDescAfter) {
        $lnk = Join-Path $dir 'shortcuts\Desktop\SyHost.lnk'
        $desc = if (Test-Path -LiteralPath $lnk) { Get-LinkDescription $lnk } else { '(kısayol yok)' }
        if ($desc -cne [string]$sc.shortcutDescAfter) { $problems.Add("kısayol açıklaması '$desc' (beklenen '$($sc.shortcutDescAfter)')") }
    }
    if ($problems.Count -eq 0) { $pass++; Write-Host ('PASS  ' + $f.BaseName) -ForegroundColor Green }
    else {
        $fail++; Write-Host ('FAIL  ' + $f.BaseName) -ForegroundColor Red
        foreach ($pr in $problems) { Write-Host ('      ' + $pr) -ForegroundColor DarkYellow }
    }
}
Write-Host ''
Write-Host ("Ayar dosyaları: {0} PASS, {1} FAIL (toplam {2})" -f $pass, $fail, $files.Count) -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })
