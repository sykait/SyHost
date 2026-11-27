# =====================================================================
#  SyHost - Java (Terminal sürümü; C#: Core\Java.cs)
#  Java yoksa bilgisayara kurulmaz: Eclipse Temurin JRE, SyHost'un kendi klasörüne (Data\tools\java-N) indirilir;
#  yönetici izni istemez, bilgisayarın geri kalanına dokunmaz.
#  Ana betik (SyHost.ps1) ve arka plan işleri (FirstRunJob.ps1, InstallJob.ps1) bu dosyayı nokta ile yükler; en üst
#  düzeyinde yalnızca fonksiyon tanımı vardır. Yükleyen $DataDir'i ayarlar. Arka plan işlerinde L yoktur:
#  Install-Java'ya ilk satırı -HeadText ile ver (çevrilmiş metin; içinde {0} varsa Java sürümüyle doldurulur).
#  TLS 1.2 süreç başında bir kez açılır ([SyHost.Net]::EnableTls12, SyHost.ps1); arka plan işleri de onu kullanır.
#   Get-JavaMajor $mc                      Minecraft sürümüne göre gereken Java (8, 17, 21, 25)
#   Find-Java $major                       java.exe ya da $null
#   Install-Java $major $OnDetail $HeadText  indirir, java.exe'yi döner; olmazsa nedeniyle hata fırlatır.
#                                          $OnDetail önce ilk satırla, sonra "<dosya>  ·  <MB> / <MB> MB" ile çağrılır
# =====================================================================
# Baştaki rakamlar: "5-pre1" -> 5, "" -> 0 (sığmayan sayı: en büyük int)
function Get-JavaLead([string]$s) {
    $m = [regex]::Match($s, '^[0-9]+')
    if (-not $m.Success) { return 0 }
    $v = 0
    if ([int]::TryParse($m.Value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $v }
    [int]::MaxValue
}
# Minecraft sürümüne göre gereken Java (8, 17, 21, 25)
function Get-JavaMajor([string]$mc) {
    $p = $mc.Split('.')
    # Yıl numaralı sürümler (26.1, 26.2 ...) Java 25 ister (Mojang sürüm listesi: javaVersion.majorVersion = 25)
    if ($p[0] -ne '1') { if ((Get-JavaLead $p[0]) -ge 26) { return 25 }; return 21 }
    # Ön sürümlerde ("1.21-rc1", "1.20.5-pre1") baştaki sayı alınır
    $minor = if ($p.Count -gt 1) { Get-JavaLead $p[1] } else { 0 }
    $patch = if ($p.Count -gt 2) { Get-JavaLead $p[2] } else { 0 }
    if ($minor -ge 21) { return 21 }
    if ($minor -eq 20 -and $patch -ge 5) { return 21 }
    if ($minor -ge 17) { return 17 }
    8
}
# parent\desen\bin\java.exe: bulunanların en büyüğü (gizli klasörler sayılmaz, büyük-küçük harfe bakılmaz)
function Get-JavaNewest([string]$parent, [string]$pattern) {
    $hits = New-Object System.Collections.Generic.List[string]
    try {
        if (-not [IO.Directory]::Exists($parent)) { return $null }
        foreach ($d in (New-Object IO.DirectoryInfo $parent).EnumerateDirectories()) {
            if (($d.Attributes -band [IO.FileAttributes]::Hidden) -ne 0 -or $d.Name -notlike $pattern) { continue }
            $j = [IO.Path]::Combine($d.FullName, 'bin', 'java.exe')
            if ([IO.File]::Exists($j)) { $hits.Add($j) }
        }
    } catch {}
    if ($hits.Count -eq 0) { return $null }
    @($hits | Sort-Object)[-1]
}
# klasör\bin\java.exe ya da bir alt klasörde (Adoptium zip'i böyle açılır: jdk-21.0.5+11-jre\bin\java.exe)
function Get-JavaLocate([string]$root) {
    $j = [IO.Path]::Combine($root, 'bin', 'java.exe')
    if ([IO.File]::Exists($j)) { return $j }
    if ([IO.Directory]::Exists($root)) { return (Get-JavaNewest $root '*') }
    $null
}
# Önce bilgisayardaki Java (Program Files, eski sürümdeki yerler ve sırayla), yoksa SyHost'un indirdiği (Data\tools\java-N)
function Find-Java([int]$major) {
    $pats = if ($major -eq 8) { @(@('Eclipse Adoptium', 'jre-8*'), @('Eclipse Adoptium', 'jdk-8*')) }
            else { @(@('Microsoft', "jdk-$major*"), @('Eclipse Adoptium', "jdk-$major*"), @('Eclipse Adoptium', "jre-$major*")) }
    # Eski sürüm "C:\Program Files" yazardı; Windows başka sürücüdeyse oradaki de bakılır
    $pfs = @('C:\Program Files')
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    if (-not [string]::IsNullOrEmpty($pf) -and -not [string]::Equals($pf.TrimEnd('\'), 'C:\Program Files', [StringComparison]::OrdinalIgnoreCase)) { $pfs += $pf }
    foreach ($pt in $pats) { foreach ($root in $pfs) { $j = Get-JavaNewest ([IO.Path]::Combine($root, $pt[0])) $pt[1]; if ($j) { return $j } } }
    if ([string]::IsNullOrEmpty($DataDir)) { return $null }
    try { Get-JavaLocate ([IO.Path]::Combine($DataDir, 'tools', "java-$major")) } catch { $null }
}

# PowerShell .NET hatalarını MethodInvocationException içine sarar: asıl hata (C# sürümündeki metin)
function Get-JavaError($e) {
    while ($e -is [System.Management.Automation.MethodInvocationException] -and $null -ne $e.InnerException) { $e = $e.InnerException }
    $e
}
# Sunucu "böyle bir şey yok" dedi (4xx; 408 ve 429 hariç): tekrar denemek boşuna
function Test-JavaPermanent($e) {
    if ($e -isnot [Net.WebException] -or $e.Status -ne [Net.WebExceptionStatus]::ProtocolError -or $null -eq $e.Response) { return $false }
    $code = [int]$e.Response.StatusCode
    $code -ge 400 -and $code -lt 500 -and $code -ne 408 -and $code -ne 429
}
# İstek: SyHost'u tanıtan User-Agent, yönlendirmeler izlenir, sıkıştırma kapalı (karma baytı baytına doğrulansın).
# Başlıklar 100 sn içinde gelmeli; sonra 60 sn hiç veri gelmezse bağlantı kopmuş sayılır.
function New-JavaRequest([string]$url) {
    $r = [Net.HttpWebRequest]::Create($url)
    $r.UserAgent = 'SyHost/1.0 (+https://github.com/sykait/SyHost)'
    $r.AllowAutoRedirect = $true; $r.MaximumAutomaticRedirections = 10
    $r.AutomaticDecompression = [Net.DecompressionMethods]::None
    $r.Timeout = 100000; $r.ReadWriteTimeout = 60000
    $r
}
function Get-JavaText([string]$url) {
    $resp = (New-JavaRequest $url).GetResponse()
    try { $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8); try { $sr.ReadToEnd() } finally { $sr.Dispose() } }
    finally { $resp.Close() }
}
function Get-JavaStr($o, [string]$n) { $p = $o.PSObject.Properties[$n]; if ($null -ne $p -and $p.Value -is [string]) { $p.Value } else { $null } }
# assets API'sindeki package.checksum (zip'in SHA-256'sı); ulaşılamazsa $null
function Get-JavaChecksum([int]$major) {
    try {
        $doc = ConvertFrom-Json (Get-JavaText "https://api.adoptium.net/v3/assets/latest/$major/hotspot?architecture=x64&image_type=jre&os=windows&vendor=eclipse")
        if ($doc -isnot [array]) { return $null }
        foreach ($rel in $doc) {
            if ($rel -isnot [System.Management.Automation.PSCustomObject]) { continue }
            $b = $rel.PSObject.Properties['binary']
            if ($null -eq $b -or $b.Value -isnot [System.Management.Automation.PSCustomObject]) { continue }
            $b = $b.Value
            if (-not ((Get-JavaStr $b 'os') -eq 'windows' -and (Get-JavaStr $b 'architecture') -eq 'x64' -and (Get-JavaStr $b 'image_type') -eq 'jre')) { continue }
            $pk = $b.PSObject.Properties['package']
            if ($null -eq $pk -or $pk.Value -isnot [System.Management.Automation.PSCustomObject]) { continue }
            $sum = Get-JavaStr $pk.Value 'checksum'
            if ($null -ne $sum -and $sum -match '^[0-9a-fA-F]{64}$') { return $sum }
        }
    } catch {}
    $null
}
# İlerleme satırı (dile bağlı değil): "OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11.zip  ·  23 / 48 MB"
function Format-JavaProgress([string]$name, [long]$got, [long]$total) {
    $name + '  ·  ' + ($got -shr 20) + $(if ($total -gt 0) { ' / ' + ($total -shr 20) } else { '' }) + ' MB'
}
# Adresi dosyaya indirir (en çok 1 GB), inerken SHA-256'sını hesaplar ve döner. İlerleme en çok saniyede 5 kez.
function Save-JavaFile([string]$url, [string]$path, [scriptblock]$OnDetail) {
    $resp = (New-JavaRequest $url).GetResponse()
    try {
        $length = $resp.ContentLength   # bilinmiyorsa -1
        # Dosya adı: GitHub'ın son adresinde ad yerine bir kimlik durur; asıl ad Content-Disposition'da
        $name = $null
        $cd = $resp.Headers['Content-Disposition']
        if ($cd) {
            $m = [regex]::Match($cd, 'filename\*?\s*=\s*(?:[\w-]+''[\w-]*'')?"?([^";]+)"?', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($m.Success) { $name = [Uri]::UnescapeDataString($m.Groups[1].Value.Trim()) }
        }
        if (-not $name) { $name = [Uri]::UnescapeDataString([IO.Path]::GetFileName($resp.ResponseUri.AbsolutePath)) }
        $tick = [Diagnostics.Stopwatch]::StartNew()
        if ($OnDetail) { $null = & $OnDetail (Format-JavaProgress $name 0 $length) }
        $sha = [Security.Cryptography.SHA256]::Create()
        $body = $resp.GetResponseStream()
        $fs = New-Object IO.FileStream($path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 65536)
        try {
            $buf = New-Object byte[] 65536
            $total = [long]0
            while (($n = $body.Read($buf, 0, $buf.Length)) -gt 0) {
                $total += $n
                if ($total -gt 1GB) { throw (New-Object IO.InvalidDataException 'The download is larger than expected.') }
                [void]$sha.TransformBlock($buf, 0, $n, $null, 0)
                $fs.Write($buf, 0, $n)
                if ($OnDetail -and $tick.ElapsedMilliseconds -ge 200) { $tick.Restart(); $null = & $OnDetail (Format-JavaProgress $name $total $length) }
            }
            [void]$sha.TransformFinalBlock($buf, 0, 0)
            if ($OnDetail) { $null = & $OnDetail (Format-JavaProgress $name $total $length) }
            ([BitConverter]::ToString($sha.Hash) -replace '-', '').ToLowerInvariant()
        } finally { $fs.Dispose(); $body.Dispose(); $sha.Dispose() }
    } finally { $resp.Close() }
}
# java.exe -version çalışıyor mu? Sorun yoksa $null, varsa nedeni.
function Test-JavaRuns([string]$exe, [int]$major) {
    if (-not $exe) { return 'java.exe not found after extracting' }
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = '-version'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    # Hiç başlatılamıyorsa (ör. güvenlik yazılımı engelledi) bu da bir neden: çalışmayan kopya yerinde kalmasın
    try { $p = [Diagnostics.Process]::Start($psi) } catch { return (Get-JavaError $_.Exception).Message }
    try {
        $err = $p.StandardError.ReadToEndAsync(); $out = $p.StandardOutput.ReadToEndAsync()
        if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch {}; return 'java -version did not finish' }
        $text = $err.Result + $out.Result
        if ($p.ExitCode -ne 0) { return ('java -version exited with code {0}: {1}' -f $p.ExitCode, $text.Trim()) }
        # openjdk version "21.0.5" / "1.8.0_432"
        $m = [regex]::Match($text, 'version "(\d+)(?:\.(\d+))?')
        $v = 0
        if ($m.Success -and [int]::TryParse($m.Groups[1].Value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
            if ($v -eq 1 -and $m.Groups[2].Success) { [void][int]::TryParse($m.Groups[2].Value, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) }
            if ($v -ne $major) { return "expected Java $major but the archive has Java $v" }
        }
        $null
    } finally { $p.Dispose() }
}
function Remove-JavaFile([string]$path) { try { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } } catch {} }
function Remove-JavaDir([string]$dir) {
    for ($i = 0; $i -lt 5; $i++) {
        try { if (-not [IO.Directory]::Exists($dir)) { return }; [IO.Directory]::Delete($dir, $true); return } catch { Start-Sleep -Milliseconds 300 }
    }
}
# Virüs tarayıcısı yeni açılan dosyaları kısa süre kilitleyebilir: taşımayı birkaç kez dene
function Move-JavaDir([string]$from, [string]$to) {
    for ($i = 0; ; $i++) {
        try { [IO.Directory]::Move($from, $to); return }
        catch {
            $e = Get-JavaError $_.Exception
            if ($i -lt 10 -and ($e -is [IO.IOException] -or $e -is [UnauthorizedAccessException])) { Start-Sleep -Milliseconds 300 } else { throw $e }
        }
    }
}
# Önceki yarım kalmış denemelerin artıkları: java-N.xxxx.zip / .tmp / .old
function Clear-JavaLeftovers([string]$tools, [int]$major) {
    try {
        foreach ($f in [IO.Directory]::GetFiles($tools, "java-$major.*.zip")) { Remove-JavaFile $f }
        foreach ($d in [IO.Directory]::GetDirectories($tools, "java-$major.*.tmp")) { Remove-JavaDir $d }
        foreach ($d in [IO.Directory]::GetDirectories($tools, "java-$major.*.old")) { Remove-JavaDir $d }
    } catch {}
}
# Java'yı Data\tools\java-N içine indirir, java.exe yolunu döner (olmazsa nedeniyle hata fırlatır)
function Install-Java([int]$major, [scriptblock]$OnDetail, [string]$HeadText) {
    $head = if ($HeadText) { if ($HeadText.Contains('{0}')) { $HeadText -f $major } else { $HeadText } }
            elseif (Get-Command L -CommandType Function -ErrorAction SilentlyContinue) { L 'Java {0} indiriliyor...' $major }
            else { 'Java {0} indiriliyor...' -f $major }
    if ($OnDetail) { $null = & $OnDetail $head }
    if ([string]::IsNullOrEmpty($DataDir)) { throw (New-Object InvalidOperationException 'Install-Java: $DataDir is not set.') }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tools = [IO.Path]::Combine([IO.Path]::GetFullPath($DataDir), 'tools')
    [void][IO.Directory]::CreateDirectory($tools)
    $final = [IO.Path]::Combine($tools, "java-$major")
    Clear-JavaLeftovers $tools $major
    $last = $null
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        if ($attempt -gt 0) { Start-Sleep -Milliseconds (2000 * $attempt) }
        $id = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $zip = [IO.Path]::Combine($tools, "java-$major.$id.zip")
        $tmp = [IO.Path]::Combine($tools, "java-$major.$id.tmp")
        try {
            # Adoptium'un bildirdiği SHA-256 (ulaşılamazsa $null: o zaman zip'in açılması ve java -version yeter)
            $sum = Get-JavaChecksum $major
            $hash = Save-JavaFile "https://api.adoptium.net/v3/binary/latest/$major/ga/windows/x64/jre/hotspot/normal/eclipse" $zip $OnDetail
            # Tutmazsa bir kez daha sor: iki istek arasında yeni sürüm çıkmış olabilir
            if ($sum -and $sum -ne $hash -and (Get-JavaChecksum $major) -ne $hash) { throw (New-Object IO.InvalidDataException "The Java $major archive does not match its SHA-256 checksum.") }
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
            if (-not (Get-JavaLocate $tmp)) { throw (New-Object IO.InvalidDataException "java.exe is missing from the Java $major archive.") }
            Remove-JavaFile $zip
            # Yarım kalmış eski klasörü kenara al, yenisini tek adımda yerine koy
            if ([IO.Directory]::Exists($final)) {
                $old = [IO.Path]::Combine($tools, "java-$major.$id.old")
                Move-JavaDir $final $old
                Remove-JavaDir $old
            }
            Move-JavaDir $tmp $final
            $exe = Get-JavaLocate $final
            $why = Test-JavaRuns $exe $major
            if ($why) {
                # Çalışmayan Java "bulunmuş" sayılmasın: silinemezse en azından adı değişsin
                Remove-JavaDir $final
                if ([IO.Directory]::Exists($final)) { $bad = [IO.Path]::Combine($tools, "java-$major.$id.old"); try { Move-JavaDir $final $bad; Remove-JavaDir $bad } catch {} }
                throw (New-Object IO.InvalidDataException $why)
            }
            return $exe
        } catch {
            $last = Get-JavaError $_.Exception
            if (Test-JavaPermanent $last) { break }   # böyle bir sürüm yok: tekrar denemek boşuna
        } finally {
            Remove-JavaFile $zip
            Remove-JavaDir $tmp
        }
    }
    $msg = "Java $major could not be downloaded: " + $(if ($null -ne $last) { $last.Message } else { '' })
    throw (New-Object IO.IOException -ArgumentList $msg, ([Exception]$last))
}
