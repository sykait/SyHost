# =====================================================================
#  SyHost - kurulum: indirme ve yükleyici yardımcıları (Terminal sürümü)
#  C# Core/Installer.cs'teki indirme (Fetch, FetchVerified, DownloadAll), GetText ve RunToLog yardımcılarının karşılıkları.
#  Arka plandaki kurulum işi (InstallJob.ps1) ve modları paralel indiren iş parçacıkları (InstallModJob.ps1) bu
#  dosyayı nokta ile yükler; en üst düzeyinde yalnızca sabitler ve fonksiyon tanımları vardır. Yalnızca .NET
#  çağrıları kullanır (joker karakter yorumu yapan cmdlet yok: [ ] içeren adlar sorun olmaz); L burada yoktur.
#   - her indirme önce '<dosya>.<n>.part' dosyasına yazılır, SHA-1 / SHA-512 tutunca yerine taşınır
#   - yükleyici dosyaları ve Fabric bilgisi 3 kez denenir (4xx hatada, 408 ve 429 dışında, tekrar denenmez)
#   - mod yükleyicisi 15 dakika hiçbir şey yazmazsa kapatılır, SyHost kapanırsa onunla kapanır (JobGuard)
# =====================================================================
# Paralel indirmede her dosya için çalışan iş: bu klasördeki InstallModJob.ps1 (metinden kod üretilmez)
$InstModJob = Join-Path $PSScriptRoot 'InstallModJob.ps1'
$InstTries = 3                  # her iş 3 kez denenir
$InstAtOnce = 6                 # aynı anda inen dosya sayısı
$InstMaxFile = 4GB              # tek dosya için akıl sınırı (bitmeyen indirmeye karşı)
$InstSilenceMin = 15            # yükleyici bu kadar dakika hiçbir şey yazmazsa takılmış sayılır
$InstUserAgent = 'SyHost/1.0 (+https://github.com/sykait/SyHost)'
$InstBadChars = [char[]]('<>"|?*' + [string]::new([char[]](0..31)))

# PowerShell'in .NET çağrısı sarmalını ('Exception calling "X" with "1" argument(s): ...') aç: asıl hata
function Inst-BaseError($ex) {
    while ($ex -is [Management.Automation.ExtendedTypeSystemException] -and $ex.InnerException) { $ex = $ex.InnerException }
    $ex
}
# Ağ hatası: asıl hata; sunucu hata kodu döndürdüyse kodu Data['SyHostCode']'a yazılır, yanıt kapatılır
# (kapatılmazsa bağlantı boşa çıkmaz). Metin .NET Framework'ün: "The remote server returned an error: (404) Not Found."
function Inst-NetError($ex) {
    $ex = Inst-BaseError $ex
    if ($ex -is [Net.WebException] -and $ex.Response) {
        try { $ex.Data['SyHostCode'] = [int]$ex.Response.StatusCode } catch {}
        try { $ex.Response.Close() } catch {}
    }
    $ex
}
# Tekrar denemek boşuna mı (4xx: dosya yok, yasak...; 408 ve 429 hariç)
function Inst-Permanent($ex) {
    if ($ex -isnot [Net.WebException] -or $null -eq $ex.Data['SyHostCode']) { return $false }
    $code = [int]$ex.Data['SyHostCode']
    $code -ge 400 -and $code -lt 500 -and $code -ne 408 -and $code -ne 429
}
function Inst-Delete([string]$path) { try { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } } catch {} }

function Inst-Request([string]$url) {
    if ($url -notmatch '^https?://') { throw (New-Object NotSupportedException ('Only http and https downloads are supported: ' + $url)) }
    $req = [Net.WebRequest]::Create($url)
    $req.UserAgent = $InstUserAgent
    $req.Timeout = 100000             # yanıt başlıkları 100 sn içinde gelmeli (.NET Framework varsayılanı)
    $req.ReadWriteTimeout = 60000     # sonra 60 sn hiç veri gelmezse bağlantı kopmuş sayılır
    $req.AllowAutoRedirect = $true; $req.MaximumAutomaticRedirections = 10
    $req.AutomaticDecompression = [Net.DecompressionMethods]::None   # dosyalar baytı baytına insin (karma doğrulaması)
    $req
}

# Tek deneme: adresi dosyaya indirir, inerken karmaları hesaplar. $max baytı aşan indirme kesilir.
function Inst-Fetch([string]$url, [string]$path, $hashes, [long]$max) {
    $resp = $null; $body = $null; $fs = $null
    try {
        $resp = (Inst-Request $url).GetResponse()
        $body = $resp.GetResponseStream()
        $fs = New-Object IO.FileStream($path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 65536)
        $buf = New-Object byte[] 65536
        [long]$total = 0
        while (($n = $body.Read($buf, 0, $buf.Length)) -gt 0) {
            $total += $n
            if ($max -gt 0 -and $total -gt $max) { throw (New-Object IO.InvalidDataException 'The download is larger than expected.') }
            foreach ($h in $hashes) { [void]$h.TransformBlock($buf, 0, $n, $null, 0) }
            $fs.Write($buf, 0, $n)
        }
        foreach ($h in $hashes) { [void]$h.TransformFinalBlock($buf, 0, 0) }
    } catch { throw (Inst-NetError $_.Exception) }
    finally {
        if ($fs) { $fs.Dispose() }
        if ($body) { $body.Dispose() }
        if ($resp) { $resp.Close() }
    }
}

function Inst-Hex($h) { [BitConverter]::ToString($h.Hash).Replace('-', '').ToLowerInvariant() }

# .part dosyasını yerine koy, varsa üzerine yaz (C#: File.Move(part, dst, true)); aynı yola iki kayıt varsa sırayla
function Inst-Move([string]$part, [string]$dst, $gate) {
    if ($gate) { [Threading.Monitor]::Enter($gate) }
    try {
        if ([IO.File]::Exists($dst)) {
            try { [IO.File]::Replace($part, $dst, $null, $true); return } catch { [IO.File]::Delete($dst) }
        }
        [IO.File]::Move($part, $dst)
    } finally { if ($gate) { [Threading.Monitor]::Exit($gate) } }
}

# 3 tur, her turda downloads[] içindeki her adres; karma tutunca dosya yerine konur (C# FetchVerified).
# Yarım ya da bozuk dosya hiç yerine geçmez. sha512'si olan dosya da kabul edilir (eskiden yalnızca sha1);
# adresi ya da karması olmayan hemen başarısız sayılır. Boyut sınırı: paketteki boyutun 2 katı + 1 MB.
function Inst-Verified($f, [string]$outp, $gate) {
    if ($f.Urls.Count -eq 0 -or (-not $f.Sha1 -and -not $f.Sha512)) { return $false }
    $part = $outp + '.' + $f.Index + '.part'
    [long]$max = if ($f.Size -gt 0) { [long]$f.Size * 2 + 1MB } else { $InstMaxFile }
    for ($round = 0; $round -lt $InstTries; $round++) {
        if ($round -gt 0) { [Threading.Thread]::Sleep(500 * $round) }   # geçici ağ sorununa kısa bir nefes
        foreach ($url in $f.Urls) {
            $h1 = $null; $h5 = $null
            try {
                $hs = New-Object System.Collections.Generic.List[Security.Cryptography.HashAlgorithm]
                if ($f.Sha1) { $h1 = [Security.Cryptography.SHA1]::Create(); $hs.Add($h1) }
                if ($f.Sha512) { $h5 = [Security.Cryptography.SHA512]::Create(); $hs.Add($h5) }
                Inst-Fetch $url $part $hs $max
                if ((-not $h1 -or (Inst-Hex $h1) -eq $f.Sha1) -and (-not $h5 -or (Inst-Hex $h5) -eq $f.Sha512)) {
                    Inst-Move $part $outp $gate
                    return $true
                }
            } catch {
            } finally {
                if ($h1) { $h1.Dispose() }
                if ($h5) { $h5.Dispose() }
            }
            Inst-Delete $part
        }
    }
    $false
}

# Bir yükleyici dosyasını indirir (C#: Installer.cs'teki karşılığı): 3 kez dener, yarım dosya bırakmaz; olmazsa son hatayı fırlatır
function Inst-SaveUrl([string]$url, [string]$path) {
    $part = $path + '.part'; $last = $null
    for ($i = 0; $i -lt $InstTries; $i++) {
        if ($i -gt 0) { [Threading.Thread]::Sleep(1500 * $i) }
        try {
            Inst-Fetch $url $part $null $InstMaxFile
            Inst-Move $part $path $null
            return
        } catch {
            $last = Inst-NetError $_.Exception
            Inst-Delete $part
            if (Inst-Permanent $last) { break }
        }
    }
    throw $last
}

# Metin indir (API yanıtları, C# GetText): 3 kez dener; olmazsa son hatayı fırlatır
function Inst-GetText([string]$url) {
    $last = $null
    for ($i = 0; $i -lt $InstTries; $i++) {
        if ($i -gt 0) { [Threading.Thread]::Sleep(1000 * $i) }
        $resp = $null
        try {
            $resp = (Inst-Request $url).GetResponse()
            $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
            try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
        } catch {
            $last = Inst-NetError $_.Exception
            if (Inst-Permanent $last) { break }
        } finally { if ($resp) { $resp.Close() } }
    }
    throw $last
}

# Pakette verilen göreli yol kök klasörün içinde kalıyorsa tam yolu, değilse $null (C# Inside).
# Eskiden yalnızca "kökle başlıyor mu" diye bakılırdı: '../Sunucu-kardes/x' kardeş klasöre yazabiliyordu.
# Sürücü ya da akış adı (':'), geçersiz karakter ya da tam yola çevrilemeyen yol da geçmez.
function Inst-Inside([string]$baseDir, [string]$rel, [string]$rootFull) {
    if ([string]::IsNullOrEmpty($rel)) { return $null }
    $r = $rel.Replace('/', '\')
    if ($r.IndexOf(':') -ge 0 -or $r.IndexOfAny($InstBadChars) -ge 0) { return $null }
    try { $p = [IO.Path]::GetFullPath($baseDir.TrimEnd('\') + '\' + $r.TrimStart('\')) } catch { return $null }
    $root = $rootFull.TrimEnd('\') + '\'
    if ($p.Length -gt $root.Length -and $p.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $p }
    $null
}
# Split-Path -Leaf gibi ($null'da hata vermez)
function Inst-Leaf([string]$p) { if (-not $p) { return '' }; $i = $p.LastIndexOfAny([char[]]'/\'); if ($i -ge 0) { $p.Substring($i + 1) } else { $p } }
# JSON değerinin metni (C# Text): metin olduğu gibi, null $null, diğerleri metne çevrilir
function Inst-JsonText($v) {
    if ($null -eq $v -or $v -is [string]) { return $v }
    if ($v -is [bool]) { if ($v) { return 'true' }; return 'false' }
    [string]$v
}

# Sunucuya inecek dosyalar (C# ServerFiles): env.server 'unsupported' değil, resourcepacks/shaderpacks değil.
# Her biri bir tablo (iş parçacıkları arasında güvenle okunur): Index, Path, Leaf, Sha1, Sha512, Size, Urls
function Inst-ServerFiles($index) {
    $list = New-Object System.Collections.Generic.List[object]
    if ($index -isnot [Management.Automation.PSCustomObject] -or $index.files -isnot [array]) { return , $list }
    foreach ($f in $index.files) {
        if ($f -isnot [Management.Automation.PSCustomObject]) { continue }
        $server = $null
        if ($f.env -is [Management.Automation.PSCustomObject]) { $server = Inst-JsonText $f.env.server }
        if ($server -eq 'unsupported') { continue }
        $path = Inst-JsonText $f.path
        if ([string]$path -match '^(resourcepacks|shaderpacks)/') { continue }
        $urls = New-Object System.Collections.Generic.List[string]
        $dl = $f.downloads
        $dlAll = if ($dl -is [array]) { $dl } elseif ($null -ne $dl) { , $dl } else { @() }
        foreach ($u in $dlAll) { $t = Inst-JsonText $u; if (-not [string]::IsNullOrWhiteSpace($t)) { $urls.Add($t) } }
        $sha1 = $null; $sha512 = $null
        if ($f.hashes -is [Management.Automation.PSCustomObject]) {
            $sha1 = Inst-JsonText $f.hashes.sha1; if (-not $sha1) { $sha1 = $null }
            $sha512 = Inst-JsonText $f.hashes.sha512; if (-not $sha512) { $sha512 = $null }
        }
        $size = [long]0
        if ($f.fileSize -is [int] -or $f.fileSize -is [long]) { $size = [long]$f.fileSize }
        $list.Add(@{ Index = $list.Count; Path = $path; Leaf = (Inst-Leaf $path); Sha1 = $sha1; Sha512 = $sha512; Size = $size; Urls = $urls.ToArray() })
    }
    , $list
}

# Paralel işlerden birinde beklenmedik hata: ilki saklanır, kurulum onunla durur (C# Parallel.ForEachAsync gibi)
function Inst-Fail($ctx, $ex) {
    [Threading.Monitor]::Enter($ctx.Gate)
    try { if (-not $ctx.Error) { $ctx.Error = Inst-BaseError $ex } } finally { [Threading.Monitor]::Exit($ctx.Gate) }
}

# Tek bir dosya (C# DownloadAll'daki iş). Ekranda hâlâ inen en son dosyanın adı görünür; % ve n/toplam dosyalar
# bittikçe ilerler. Kök klasörün dışına çıkan yol indirilmez ama sayılır (eskiden de öyleydi).
function Inst-ModJob($f, $ctx) {
    if ($ctx.Error) { return }   # başka bir dosyada beklenmedik hata: yenisine başlama
    $sync = $ctx.Sync; $gate = $ctx.Gate
    [Threading.Monitor]::Enter($gate)
    try { [void]$ctx.Running.Add($f.Index); $ctx.Shown = $f.Index; $sync.Detail = $f.Leaf } finally { [Threading.Monitor]::Exit($gate) }
    try {
        $outp = Inst-Inside $ctx.Target $f.Path $ctx.Full
        if ($outp) {
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outp))
            if (-not (Inst-Verified $f $outp $ctx.MoveGate)) { $ctx.Failed[$f.Index] = $true }
        }
    } catch { Inst-Fail $ctx $_.Exception }
    finally {
        [Threading.Monitor]::Enter($gate)
        try {
            $ctx.Running.Remove($f.Index)
            # Ekranda biten dosyanın adı kalmasın: hâlâ inen en son dosyayı göster
            if ($ctx.Shown -eq $f.Index -and $ctx.Running.Count -gt 0) { $ctx.Shown = $ctx.Running[$ctx.Running.Count - 1]; $sync.Detail = $ctx.Leaves[$ctx.Shown] }
            $ctx.Done = $ctx.Done + 1
            $sync.Pct = [int]($ctx.Done / [Math]::Max(1, $ctx.Total) * 100)
            $sync.Count = '' + $ctx.Done + '/' + $ctx.Total
        } finally { [Threading.Monitor]::Exit($gate) }
    }
}

# Dosyaları $InstAtOnce'ar $InstAtOnce'ar indirir (C# DownloadAll): her dosya kendi iş parçacığında (RunspacePool),
# havuz açılamazsa sırayla. İnemeyenlerin adlarını paketteki sırayla döner.
function Inst-AllMods($sync, $files, [string]$target, [string]$full) {
    $total = $files.Count
    $leaves = New-Object string[] $total
    for ($i = 0; $i -lt $total; $i++) { $leaves[$i] = $files[$i].Leaf }
    $ctx = [hashtable]::Synchronized(@{
        Sync = $sync; Gate = (New-Object object); MoveGate = (New-Object object); Running = (New-Object System.Collections.ArrayList)
        Failed = (New-Object bool[] $total); Leaves = $leaves; Total = $total; Done = 0; Shown = -1; Target = $target; Full = $full; Error = $null
    })
    if ($total -gt 0) { $sync.Count = '0/' + $total }
    $pool = $null
    if ($total -gt 1) { try { $pool = [runspacefactory]::CreateRunspacePool(1, $InstAtOnce); $pool.Open() } catch { $pool = $null } }
    if ($pool) {
        $jobs = New-Object System.Collections.Generic.List[object]
        try {
            foreach ($f in $files) {
                $ps = [powershell]::Create(); $ps.RunspacePool = $pool
                [void]$ps.AddCommand($InstModJob).AddArgument($f).AddArgument($ctx)
                $jobs.Add(@($ps, $ps.BeginInvoke()))
            }
            foreach ($j in $jobs) { try { [void]$j[0].EndInvoke($j[1]) } catch { Inst-Fail $ctx $_.Exception } }
        } finally {
            foreach ($j in $jobs) { try { $j[0].Dispose() } catch {} }
            try { $pool.Close() } catch {}
            try { $pool.Dispose() } catch {}
        }
    } else {
        foreach ($f in $files) { Inst-ModJob $f $ctx }
    }
    if ($ctx.Error) { throw $ctx.Error }
    if ($total -gt 0) { $sync.Detail = $leaves[$total - 1] }   # eskisi gibi son dosyanın adı kalır
    for ($i = 0; $i -lt $total; $i++) { if ($ctx.Failed[$i]) { $leaves[$i] } }
}

# Eskiden: (JSON cmdlet'iyle .../v2/versions/installer | Where-Object { $_.stable } | Select-Object -First 1).version
# Windows PowerShell 5.1 JSON dizisini boru hattına tek nesne olarak verdiği için bu satır bütün sürümleri boşlukla
# birleştirip adrese koyuyordu ve sunucu 400 dönüyordu. Burada amaçlanan yapılır: ilk kararlı sürüm (yoksa ilki).
function Inst-FabricVersion {
    $arr = ConvertFrom-Json (Inst-GetText 'https://meta.fabricmc.net/v2/versions/installer')
    $first = $null
    if ($arr -is [array]) {
        foreach ($v in $arr) {
            if ($v -isnot [Management.Automation.PSCustomObject]) { continue }
            $ver = Inst-JsonText $v.version
            if (-not $ver) { continue }
            if ($null -eq $first) { $first = $ver }
            if ($v.stable -is [bool] -and $v.stable) { return $ver }
        }
    }
    if ($null -ne $first) { $first } else { '' }
}

# Komut satırı (C# ArgumentList gibi): boşluk ya da tırnak içeren argüman tırnaklanır, ters bölüler korunur
function Inst-Args([string[]]$argv) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($a in $argv) {
        if ($a.Length -gt 0 -and $a.IndexOfAny([char[]]" `t`n`v`"") -lt 0) { $out.Add($a); continue }
        $sb = New-Object Text.StringBuilder
        [void]$sb.Append('"'); $bs = 0
        foreach ($ch in $a.ToCharArray()) {
            if ($ch -eq [char]'\') { $bs++; continue }
            if ($ch -eq [char]'"') { [void]$sb.Append([char]'\', 2 * $bs + 1).Append('"'); $bs = 0; continue }
            if ($bs) { [void]$sb.Append([char]'\', $bs); $bs = 0 }
            [void]$sb.Append($ch)
        }
        [void]$sb.Append([char]'\', 2 * $bs).Append('"')
        $out.Add($sb.ToString())
    }
    $out -join ' '
}

# Programı ve başlattıklarını kapat (C#: Kill(entireProcessTree: true))
function Inst-StopTree($p) {
    try {
        $k = New-Object Diagnostics.ProcessStartInfo ([IO.Path]::Combine([Environment]::SystemDirectory, 'taskkill.exe'))
        $k.Arguments = '/PID ' + $p.Id + ' /T /F'
        $k.UseShellExecute = $false; $k.CreateNoWindow = $true; $k.RedirectStandardOutput = $true; $k.RedirectStandardError = $true
        $kp = [Diagnostics.Process]::Start($k)
        [void]$kp.StandardOutput.ReadToEnd(); [void]$kp.StandardError.ReadToEnd()
        [void]$kp.WaitForExit(15000); $kp.Dispose()
    } catch {}
    try { if (-not $p.HasExited) { $p.Kill() } } catch {}
}

# Programı çalıştırır, çıktısını ve hatalarını geldikleri sırayla dosyaya yazar (her denemede baştan), çıkış kodunu
# döner (C# RunToLog). Latin1 baytı baytına geçirir: Java'nın yazdığı metin dosyaya aynen gider. $silenceMin dakika
# hiçbir şey yazmazsa takılmış sayılır ve kapatılır (eskiden sonsuza kadar beklenirdi). SyHost kapanırsa yetim
# kalmasın diye JobGuard'a eklenir.
function Inst-RunToLog([string]$exe, [string[]]$argv, [string]$dir, [string]$logPath, [double]$silenceMin = $InstSilenceMin) {
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $log = New-Object IO.StreamWriter($logPath, $false, $latin1)
    $p = $null
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo $exe
        $psi.Arguments = Inst-Args $argv
        $psi.WorkingDirectory = $dir
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = $latin1; $psi.StandardErrorEncoding = $latin1
        $p = New-Object Diagnostics.Process
        $p.StartInfo = $psi
        try { [void]$p.Start() }
        catch { $log.WriteLine('SyHost: could not start ' + $exe + ': ' + (Inst-BaseError $_.Exception).Message); return -1 }
        try { [SyHost.JobGuard]::Add($p) } catch {}
        $rd = @($p.StandardOutput, $p.StandardError)
        $tk = @($rd[0].ReadLineAsync(), $rd[1].ReadLineAsync())
        $quiet = [Diagnostics.Stopwatch]::StartNew(); $gone = $null
        while ($tk[0] -or $tk[1]) {
            [void][Threading.Tasks.Task]::WaitAny([Threading.Tasks.Task[]]@($tk | Where-Object { $_ }), 1000)
            for ($i = 0; $i -lt 2; $i++) {
                while ($tk[$i] -and $tk[$i].IsCompleted) {
                    $line = $null
                    try { $line = $tk[$i].Result } catch {}
                    if ($null -eq $line) { $tk[$i] = $null; break }
                    $log.WriteLine($line); $quiet.Restart()
                    $tk[$i] = $rd[$i].ReadLineAsync()
                }
            }
            if ($quiet.Elapsed.TotalMinutes -ge $silenceMin) {
                $log.WriteLine('SyHost: the installer wrote nothing for ' + [int][Math]::Floor($silenceMin) + ' minutes, stopping it.')
                Inst-StopTree $p
                break
            }
            # Program bitti ama çıktı boruları kapanmıyor (açık kalan bir alt süreç tutuyor): fazla bekleme
            if ($p.HasExited) { if (-not $gone) { $gone = [Diagnostics.Stopwatch]::StartNew() } elseif ($gone.Elapsed.TotalSeconds -ge 5) { break } }
        }
        [void]$p.WaitForExit(60000)
        $log.Flush()
        try { $p.ExitCode } catch { -1 }
    } finally {
        try { $log.Dispose() } catch {}
        if ($p) { try { $p.Dispose() } catch {} }
    }
}

# for ($try = 0; $try -lt 3 -and -not $ok; $try++) { & $java -jar $inst <bayrak> $target *> kurulum.log; $ok = ($LASTEXITCODE -eq 0) }
function Inst-RunInstaller([string]$java, [string]$jar, [string]$flag, [string]$target) {
    $log = [IO.Path]::Combine($target, 'kurulum.log')
    for ($t = 0; $t -lt $InstTries; $t++) {
        if ($t -gt 0) { [Threading.Thread]::Sleep(2000) }
        $code = @(Inst-RunToLog $java @('-jar', $jar, $flag, $target) $target $log)[-1]
        if ($code -eq 0) { return $true }
    }
    $false
}

# kurulum.log'a SyHost'un notu (ör. Java neden hazırlanamadı)
function Inst-Note([string]$target, [string]$text) {
    try { [IO.File]::AppendAllText([IO.Path]::Combine($target, 'kurulum.log'), 'SyHost: ' + $text + [Environment]::NewLine, (New-Object Text.UTF8Encoding $false)) } catch {}
}
function Inst-Chain($ex) {
    $parts = New-Object System.Collections.Generic.List[string]
    for ($e = $ex; $null -ne $e; $e = $e.InnerException) { $parts.Add([string]$e.Message) }
    if ($parts.Count) { $parts -join ' <- ' } else { 'not found after download' }
}
