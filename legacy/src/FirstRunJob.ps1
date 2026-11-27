# =====================================================================
#  SyHost - ilk açılışın arka plan işleri: java | download | claim (Terminal sürümü)
#  FrRun (FirstRun.ps1) bu dosyayı ayrı bir çalışma alanında çalıştırır; ekranla yalnızca $sync (= $Fr.Sync)
#  üzerinden konuşur: Done bitti mi, Text ekrandaki ilerleme yazısı, Error hata metni ($null: hata yok),
#  Proc çalışan playit komutu (Esc onu kapatır), Cancel Esc'e basıldı, Code playit eşleştirme kodu.
#  $ctx: yollar ve ana iş parçacığında çevrilmiş metinler (bu çalışma alanında ayarlar ve L yok).
#  Metinden kod üretilmez: Java yardımcıları bu klasördeki Java.ps1'den yüklenir. TLS 1.2 süreçte zaten açıktır.
# =====================================================================
param($sync, [string]$kind, $ctx)
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
$tt = $ctx.Texts

function Get-FrErrorText($e) {
    while ($null -ne $e.InnerException -and ($e -is [System.Management.Automation.MethodInvocationException] -or $e -is [System.Reflection.TargetInvocationException] -or $e -is [AggregateException])) { $e = $e.InnerException }
    $e.Message
}
# Son dolu satır (satırlar kırpılır, boşlar atlanır)
function LastLine([string]$s) {
    $lines = @(foreach ($ln in ($s -split "`n")) { $t = $ln.Trim(); if ($t.Length -gt 0) { $t } })
    if ($lines.Count -eq 0) { return '' }
    $lines[$lines.Count - 1]
}
# Geçici dosyayı yerine koy (C#: File.Move(tmp, dst, true))
function Move-Over([string]$from, [string]$to) {
    if (-not [IO.File]::Exists($to)) { [IO.File]::Move($from, $to); return }
    try { [IO.File]::Replace($from, $to, $null) } catch { [IO.File]::Copy($from, $to, $true); [IO.File]::Delete($from) }
}
# İndirilen playit dosyası için akıl sınırı (bugün ~8 MB; C#: PlayitMaxBytes)
$FrPlayitMaxBytes = 64MB
function New-FrRequest([string]$url) {
    # Yalnızca https: file:// ya da ftp:// gibi bir adres hiç açılmaz (C#: Uri.UriSchemeHttps)
    $u = $null
    if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$u) -or $u.Scheme -cne 'https') { throw $tt.dlFail }
    $rq = [Net.WebRequest]::Create($u)
    $rq.UserAgent = 'SyHost/1.0 (+https://github.com/sykait/SyHost)'
    $rq.Timeout = 300000; $rq.ReadWriteTimeout = 300000
    $rq
}
function Get-FrText([string]$url) {
    $rs = (New-FrRequest $url).GetResponse()
    try { $sr = New-Object IO.StreamReader($rs.GetResponseStream(), [Text.Encoding]::UTF8); try { $sr.ReadToEnd() } finally { $sr.Dispose() } } finally { $rs.Dispose() }
}
function Save-FrFile([string]$url, [string]$path) {
    $rs = (New-FrRequest $url).GetResponse()
    try {
        $s = $rs.GetResponseStream(); $f = [IO.File]::Create($path)
        try {
            $buf = New-Object byte[] 81920; $total = 0
            while (($n = $s.Read($buf, 0, $buf.Length)) -gt 0) {
                $total += $n
                if ($total -gt $FrPlayitMaxBytes) { throw $tt.dlFail }
                $f.Write($buf, 0, $n)
            }
        } finally { $f.Dispose(); $s.Dispose() }
    } finally { $rs.Dispose() }
}

# playit'in iki programını indir (GitHub'daki son sürüm, Windows x64). Yalnızca imzalı sürüm kabul edilir ve dosya
# yerine konmadan (hiç çalıştırılmadan) önce doğrulanır: GitHub'ın verdiği SHA-256 tutmalı ve Windows imzayı geçerli
# bulmalı. Tutmazsa dosya silinir, adım "kurulamadı" ile atlanır. (C#: App.PlayitSetup.cs PlayitDownload)
function PlayitDownload {
    $sync.Text = $tt.dl
    $doc = ConvertFrom-Json (Get-FrText 'https://api.github.com/repos/playit-cloud/playit-agent/releases/latest')
    $assets = @{}
    foreach ($a in @($doc.assets)) { $assets[[string]$a.name] = $a }
    [void][IO.Directory]::CreateDirectory($ctx.ToolDir)
    foreach ($pair in @(@('playitd-windows-x86_64-signed.exe', 'playitd.exe'), @('playit-windows-x86_64-signed.exe', 'playit.exe'))) {
        $a = $assets[$pair[0]]
        if ($null -eq $a) { throw $tt.dlFail }
        $dst = [IO.Path]::Combine($ctx.ToolDir, $pair[1]); $tmp = $dst + '.indiriliyor'
        try {
            Save-FrFile ([string]$a.browser_download_url) $tmp
            if (-not (Test-FrPlayitFile $tmp ([string]$a.digest))) { throw $tt.dlFail }
            Move-Over $tmp $dst
        } catch {
            try { [IO.File]::Delete($tmp) } catch {}
            throw
        }
    }
}
# İndirilen dosya GitHub'ın SHA-256'sıyla tutuyor mu (verdiyse) ve imzası geçerli mi? (C#: PlayitFileOk, Trust.IsSigned)
function Test-FrPlayitFile([string]$file, [string]$digest) {
    if ($digest) {
        if (-not $digest.StartsWith('sha256:', [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $fs = [IO.File]::OpenRead($file)
            try { $hex = [BitConverter]::ToString($sha.ComputeHash($fs)).Replace('-', '') } finally { $fs.Dispose() }
        } finally { $sha.Dispose() }
        if (-not [string]::Equals($hex, $digest.Substring(7), [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    (Get-AuthenticodeSignature -LiteralPath $file).Status -eq 'Valid'
}
# Hesap bağlama sayfası yalnızca playit.gg'nin kendi https adresiyse tarayıcıda açılır (C#: IsPlayitUrl)
function Test-FrPlayitUrl([string]$url) {
    $u = $null
    if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$u) -or $u.Scheme -cne 'https') { return $false }
    [string]::Equals($u.Host, 'playit.gg', [StringComparison]::OrdinalIgnoreCase) -or $u.Host.EndsWith('.playit.gg', [StringComparison]::OrdinalIgnoreCase)
}

# playit komutunu çalıştır, bütün çıktıyı (stdout ve stderr geliş sırasıyla) döndür.
# Çalışan süreç $sync.Proc'ta durur: Esc (PlayitCancel) onu kapatır. SyHost kapanırsa o da kapanır (JobGuard).
function PlayitRun([string]$arguments, [int]$timeoutMs) {
    if ($sync.Cancel) { throw $tt.claimFail }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = [string]$ctx.Cli; $psi.Arguments = $arguments
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $ctx.Data
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $sync.Proc = $p
        try { [SyHost.JobGuard]::Add($p) } catch {}
        if ($sync.Cancel) { try { $p.Kill() } catch {} }
        $sb = New-Object Text.StringBuilder
        $readers = @($p.StandardOutput, $p.StandardError)
        $reads = @($readers[0].ReadLineAsync(), $readers[1].ReadLineAsync())
        $sw = [Diagnostics.Stopwatch]::StartNew(); $killed = $false
        while ($null -ne $reads[0] -or $null -ne $reads[1]) {
            $live = New-Object System.Collections.Generic.List[System.Threading.Tasks.Task]; $which = New-Object System.Collections.Generic.List[int]
            for ($i = 0; $i -lt 2; $i++) { if ($null -ne $reads[$i]) { $live.Add($reads[$i]); $which.Add($i) } }
            $w = [System.Threading.Tasks.Task]::WaitAny($live.ToArray(), 100)
            if ($w -ge 0) {
                $i = $which[$w]; $line = $reads[$i].Result
                if ($null -eq $line) { $reads[$i] = $null } else { [void]$sb.AppendLine($line); $reads[$i] = $readers[$i].ReadLineAsync() }
            }
            if (-not $killed -and $sw.ElapsedMilliseconds -ge $timeoutMs) { $killed = $true; try { $p.Kill() } catch {} }
        }
        $p.WaitForExit()
        $sb.ToString()
    } finally { $sync.Proc = $null; $p.Dispose() }
}

# Tarayıcıda hesap bağlama: kod üret, sayfayı aç, onayı bekle, anahtarı yaz
function PlayitClaim {
    $code = LastLine (PlayitRun 'claim generate' 30000)
    if ([string]::IsNullOrWhiteSpace($code)) { throw $tt.claimFail }
    $sync.Code = $code
    $url = LastLine (PlayitRun ('claim url ' + $code + ' --name SyHost') 30000)
    if ((Test-FrPlayitUrl $url) -and -not $ctx.NoBrowser -and -not $sync.Cancel) { try { [void][Diagnostics.Process]::Start($url) } catch {} }
    $sync.Text = $tt.waiting
    $outp = PlayitRun ('claim exchange ' + $code + ' --wait 600') 620000
    $m = [regex]::Match($outp, '([0-9a-f]{64})')
    if (-not $m.Success) { throw $tt.claimFail }
    [IO.File]::WriteAllText($ctx.Secret, 'secret_key = "' + $m.Groups[1].Value + '"' + "`n", (New-Object Text.UTF8Encoding $false))
}

try {
    switch -CaseSensitive ($kind) {
        'java' {
            # Java'yı Java.ps1'deki Install-Java indirir (Portable sözleşmesi). Bu çalışma alanında L yoktur:
            # ilk satır ($ctx.Head, ana iş parçacığında çevrildi) -HeadText ile verilir ve başlıkta zaten yazar.
            $DataDir = $ctx.Data
            . (Join-Path $PSScriptRoot 'Java.ps1')
            $FrHead = $ctx.Head; $FrSync = $sync
            $onDetail = { param([string]$t) if ($t -cne $FrHead) { $FrSync.Text = $t } }.GetNewClosure()
            $jp = @{}
            $jc = Get-Command Install-Java -CommandType Function -ErrorAction SilentlyContinue
            if ($null -ne $jc -and $jc.Parameters.ContainsKey('HeadText')) { $jp['HeadText'] = $FrHead }
            [void](Install-Java 21 $onDetail @jp)
        }
        'download' { PlayitDownload }
        'claim' { PlayitClaim }
    }
} catch {
    $sync.Error = Get-FrErrorText $_.Exception
} finally {
    $sync.Proc = $null
    $sync.Done = $true
}
