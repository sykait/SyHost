# =====================================================================
#  SyHost - ilk açılış ekranı (Terminal sürümü)
#  C# karşılığı: src\SyHost\App\App.FirstRun.cs ve App.PlayitSetup.cs; iki sürüm aynı kareyi çizer.
#  1. aşama (SyHost henüz kurulu değil, ör. İndirilenler'den açıldı):
#       Dil  ›  Konum   → seçilen klasöre kurulur ve oradan yeniden açılır
#  2. aşama (kurulu, ilk açılış):
#       Eski veriler  ›  Sistem  ›  Java  ›  Arkadaşlar  ›  Yazı tipi  ›  Kısayollar  ›  Hazır
#  Ayarlar ekranı tek bir adımı (ör. Arkadaşlar, Java) yeniden çalıştırmak için de bunu kullanır.
#  Görünüm ana menü ve sihirbazla aynı: logo + bilgi sütunu, adım çubuğu, parlayan çizgi,
#  nabız gibi atan seçim vurgusu, boş satırlarda kayan yıldızlar.
#  Uzun işler (Java ve playit indirme, playit hesabını bağlama) ayrı bir PowerShell çalışma alanında
#  koşar ve ekranla yalnızca $Fr.Sync üzerinden konuşur: ekran hiçbir zaman donmaz.
# =====================================================================

# Adımların adı: adım çubuğundaki kısa ad ve çizgideki başlık
$FrStepNames = @{
    dil = @('Dil', 'DİL'); konum = @('Konum', 'KURULUM YERİ'); tasima = @('Eski veriler', 'ESKİ VERİLER'); sistem = @('Sistem', 'SİSTEM')
    java = @('Java', 'JAVA'); arkadas = @('Arkadaşlar', 'ARKADAŞ BAĞLANTISI'); yazi = @('Yazı tipi', 'YAZI TİPİ'); kisayol = @('Kısayollar', 'KISAYOLLAR'); bitti = @('Hazır', 'HAZIR')
}
# playit tünel adresi: bir-sey.joinmc.link ya da xxx.tun.ply.gg:12345 (C#: AddrRx, büyük-küçük harfe duyarlı)
$AddrRx = New-Object regex '^[\w\.-]+\.\w+(:\d+)?$'
# Test modunda (ve testlerde) tarayıcı açılmaz
$FrNoBrowser = [bool]$TestFrame
# Java adımında her karede Java aranmasın (PowerShell'de yavaş): en fazla saniyede bir, iş bitince hemen
$FrJavaCache = $null; $FrJavaAt = [DateTime]::MinValue

# Ayar alanını yaz (dosyada yoksa eklenir, varsa yeri değişmez)
function Set-FrCfg([string]$name, $value) {
    if ($null -ne $Cfg.PSObject.Properties[$name]) { $Cfg.$name = $value } else { $Cfg | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
}
# Hatanın kullanıcıya gösterilecek metni (C#: e.Message; PowerShell'in "Exception calling ..." sarmalayıcısı açılır)
function Get-FrErrorText($e) {
    while ($null -ne $e.InnerException -and ($e -is [System.Management.Automation.MethodInvocationException] -or $e -is [System.Reflection.TargetInvocationException] -or $e -is [AggregateException])) { $e = $e.InnerException }
    $e.Message
}

# Açılış animasyonu bitince: kurulum gerekiyorsa ilk açılış, yoksa ana menü
function After-Splash {
    $script:Screen = $NextAfterSplash
    if ($Screen -eq 'firstrun' -and $null -eq $Fr) { Start-FirstRun $null }
    Reset-Frame
}

# İlk açılışı başlat. $only: yalnızca bu adım (Ayarlar'dan), boş: tam akış
function Start-FirstRun([string]$only) {
    $script:Fr = New-FirstRunState
    $Fr.ReturnTo = if ($only) { 'settings' } else { $null }
    if ($only) { $Fr.Steps.Add($only) }
    elseif ($SetupMode) {
        $Fr.Steps.Add('dil')
        $exe = $ExePath
        $oi = Find-OtherInstall $exe
        $Fr.OtherInstall = if ($oi) { [string]$oi } else { $null }
        $ownFolder = (Test-OwnEmptyFolder $AppRoot $exe) -and -not (Test-InOneDrive $AppRoot) -and (Test-CanWrite $AppRoot)
        $Fr.Target = if ($ownFolder) { $AppRoot } else { [string](Get-DefaultRoot) }
        if (-not $ownFolder -or $null -ne $Fr.OtherInstall) { $Fr.Steps.Add('konum') }
    } else {
        if ($null -ne $FrMigrated -or $null -ne $FrMovedTo) { $Fr.Steps.Add('tasima') }
        foreach ($st in 'sistem', 'java', 'arkadas', 'yazi', 'kisayol', 'bitti') { $Fr.Steps.Add($st) }
    }
    FrEnterStep
    $script:Screen = 'firstrun'
}

function FrStep { $Fr.Steps[$Fr.Index] }

# Adıma girerken başlangıç seçimi ve notu hazırla
function FrEnterStep {
    $Fr.Sel = 0; $Fr.Note = $null; $Fr.Confirm = $false
    $script:FrJavaAt = [DateTime]::MinValue
    switch -CaseSensitive (FrStep) {
        'dil' { $Fr.Sel = [Math]::Max(0, [Array]::IndexOf(@($Languages.Keys), $LangCode)) }
        'konum' { FrCheckTarget }
        'arkadas' { $Fr.Phase = 'soru'; $Fr.Sel = 0 }
        'kisayol' {
            $Fr.Desk = if ($null -ne $Cfg.kisayolMasaustu) { [bool]$Cfg.kisayolMasaustu } else { $true }
            $Fr.Start = if ($null -ne $Cfg.kisayolBaslat) { [bool]$Cfg.kisayolBaslat } else { $true }
            if ((Get-LinkState (Get-ShortcutLocations)[0] $ExePath) -eq 'OtherLive') { $Fr.Note = L "Masaüstündeki SyHost kısayolu başka bir SyHost'u açıyor; yenisiyle değiştirilecek."; $Fr.NoteCol = $c.yellow }
        }
    }
    $script:Dirty = $true
}

function FrNext {
    if ($Fr.Index -lt $Fr.Steps.Count - 1) { $Fr.Index++; FrEnterStep; return }
    # Akış bitti
    if ($null -ne $Fr.ReturnTo) { $script:Fr = $null; $script:Screen = 'settings'; Reset-Frame; return }
    # 1. aşama konum adımı olmadan bitti (exe kendi boş klasöründe): SyHost buraya kurulur ve buradan yeniden açılır
    if ($SetupMode) { FrInstall 'target'; return }
    Set-FrCfg 'kurulumTamam' $true
    Save-Config
    $script:Fr = $null; $script:Screen = 'home'; Reset-Frame
}

function FrBack {
    if ($null -ne $Fr.ReturnTo) { $script:Fr = $null; $script:Screen = 'settings'; Reset-Frame; return }
    if ($Fr.Index -gt 0) { $Fr.Index--; FrEnterStep }
}

# ---------- Konum ----------
# Seçili kurulum yerini denetle: yazılabilir mi, OneDrive mı, orada SyHost var mı
function FrCheckTarget {
    $Fr.Note = $null; $Fr.Confirm = $false
    if ($Fr.Sel -eq 0 -and $null -ne $Fr.OtherInstall) { $Fr.Note = FrUpdateNote $Fr.OtherInstall; return }
    $t = $Fr.Target
    if (Test-Installed $t) { $Fr.Note = L 'Burada zaten SyHost var; güncellenip açılacak.'; $Fr.NoteCol = $c.green }
    elseif (Test-InOneDrive $t) { $Fr.Note = L 'Bu klasör OneDrive ile eşitleniyor. Sunucu dosyaları büyük ve sürekli değişir; OneDrive dışında bir yer önerilir.'; $Fr.NoteCol = $c.yellow }
}

function FrUpdateNote([string]$root) {
    $newer = FrNewerVersion ([IO.Path]::Combine($root, 'SyHost.exe'))
    if ($null -ne $newer) { $Fr.NoteCol = $c.yellow; return (L 'Oradaki SyHost daha yeni ({0}); yalnızca açılacak.' $newer) }
    $Fr.NoteCol = $c.green
    L 'Burada zaten SyHost var; güncellenip açılacak.'
}

# Hedefteki SyHost.exe bizden yeniyse sürümü ("1.2.0"), değilse $null
function FrNewerVersion([string]$exe) {
    try {
        $theirs = Get-ExeVersion $exe
        $ours = [version]$Version
        if ($null -ne $theirs -and ([version]$theirs) -gt (New-Object Version $ours.Major, $ours.Minor, ([Math]::Max(0, $ours.Build)), 0)) {
            $theirs = [version]$theirs
            return "$($theirs.Major).$($theirs.Minor).$($theirs.Build)"
        }
    } catch {}
    $null
}

# Konum seçenekleri: @(görünen ad, tür) — tür: update | target | pick
function FrLocationOptions {
    $o = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Fr.OtherInstall) { $o.Add(@((L "Bilgisayardaki SyHost'u güncelle: {0}" $Fr.OtherInstall), 'update')) }
    $o.Add(@($Fr.Target, 'target'))
    $o.Add(@((L 'Başka bir klasör seç...'), 'pick'))
    , $o
}

# Konumu onayla: kur ya da güncelle, sonra yeni yerden aç
function FrInstall([string]$kind) {
    $exe = $ExePath
    try {
        if ($kind -ceq 'update') {
            $target = [IO.Path]::Combine($Fr.OtherInstall, 'SyHost.exe')
            if ($null -eq (FrNewerVersion $target)) { $null = Copy-SyHostExe $exe $target }
            $script:LaunchAfterExit = $target
        } else {
            $root = $Fr.Target
            if (-not (Test-CanWrite $root)) { $Fr.Note = L 'Bu klasöre yazılamıyor. Başka bir yer seç.'; $Fr.NoteCol = $c.red; return }
            $null = Install-SyHostTo $root $exe $LangCode
            $null = Set-FolderLook $root $LangCode @()
            $script:LaunchAfterExit = [IO.Path]::Combine($root, 'SyHost.exe')
        }
        $script:Quit = $true
    } catch [System.IO.IOException] {
        $Fr.Note = L 'SyHost orada açık. Önce onu kapat, sonra tekrar dene.'; $Fr.NoteCol = $c.red
    } catch {
        $Fr.Note = Get-FrErrorText $_.Exception; $Fr.NoteCol = $c.red
    }
    $script:Dirty = $true
}

# Klasör boş mu? (C#: !Directory.EnumerateFileSystemEntries(dir).Any())
function Test-FrEmptyDir([string]$dir) {
    foreach ($e in [IO.Directory]::EnumerateFileSystemEntries($dir)) { return $false }
    $true
}

# ---------- Arka plan işleri (indirme vb.) ----------
# İş ayrı bir çalışma alanında koşar; ekranla yalnızca $sync (= $Fr.Sync) üzerinden konuşur:
#   Done bitti mi, Text ekrandaki ilerleme yazısı, Error hata metni ($null: hata yok),
#   Proc çalışan playit komutu (Esc onu kapatır), Cancel Esc'e basıldı, Code playit eşleştirme kodu.
# $ctx: yollar ve önceden çevrilmiş metinler (bu çalışma alanında L ve ayarlar yok).
$FrJobScript = {
    param($sync, [string]$kind, $ctx)
    $ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
    # GitHub ve Adoptium TLS 1.2 ister; Windows PowerShell 5.1 bunu her zaman kendiliğinden açmaz
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
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
    function New-FrRequest([string]$url) {
        $rq = [Net.WebRequest]::Create($url)
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
            try { $s.CopyTo($f) } finally { $f.Dispose(); $s.Dispose() }
        } finally { $rs.Dispose() }
    }

    # playit'in iki programını indir (GitHub'daki son sürüm, Windows x64, imzalı)
    function PlayitDownload {
        $sync.Text = $tt.dl
        $doc = ConvertFrom-Json (Get-FrText 'https://api.github.com/repos/playit-cloud/playit-agent/releases/latest')
        $urls = @{}
        foreach ($a in @($doc.assets)) { $urls[[string]$a.name] = $a.browser_download_url }
        [void][IO.Directory]::CreateDirectory($ctx.ToolDir)
        foreach ($pair in @(@('playitd-windows-x86_64', 'playitd.exe'), @('playit-windows-x86_64', 'playit.exe'))) {
            $asset = $pair[0]
            $url = if ($urls.ContainsKey($asset + '-signed.exe')) { $urls[$asset + '-signed.exe'] } elseif ($urls.ContainsKey($asset + '.exe')) { $urls[$asset + '.exe'] } else { $null }
            if ($null -eq $url) { throw $tt.dlFail }
            $dst = [IO.Path]::Combine($ctx.ToolDir, $pair[1]); $tmp = $dst + '.indiriliyor'
            Save-FrFile ([string]$url) $tmp
            Move-Over $tmp $dst
        }
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
        if ($url.StartsWith('http', [StringComparison]::OrdinalIgnoreCase) -and -not $ctx.NoBrowser -and -not $sync.Cancel) { try { [void][Diagnostics.Process]::Start($url) } catch {} }
        $sync.Text = $tt.waiting
        $outp = PlayitRun ('claim exchange ' + $code + ' --wait 600') 620000
        $m = [regex]::Match($outp, '([0-9a-f]{64})')
        if (-not $m.Success) { throw $tt.claimFail }
        [IO.File]::WriteAllText($ctx.Secret, 'secret_key = "' + $m.Groups[1].Value + '"' + "`n", (New-Object Text.UTF8Encoding $false))
    }

    try {
        switch -CaseSensitive ($kind) {
            'java' {
                # Java'nın indirilmesi Portable.ps1'deki Install-Java'dır ($JavaFuncs). L burada da çalışsın diye
                # ana betiğin metin tablosu ve L'si de getirilir; ilk satır ($ctx.Head) zaten başlıkta yazar.
                $TextTable = $ctx.TextTable; $LangCode = $ctx.LangCode
                ${function:L} = [scriptblock]::Create($ctx.LFunc)
                $DataDir = $ctx.Data
                . ([scriptblock]::Create($ctx.JavaFuncs))
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
}

# Arka plan işini başlat: java | download | claim
function FrRun([string]$kind) {
    $sy = $Fr.Sync
    $sy.Done = $false; $sy.Error = $null; $sy.Text = ''; $sy.Cancel = $false; $sy.Proc = $null
    $ctx = @{
        Data = $Data; Secret = $PlayitSecret; ToolDir = $PlayitToolDir; Cli = (PlayitCliExe); NoBrowser = $FrNoBrowser
        Texts = @{ dl = (L 'playit indiriliyor...'); dlFail = (L 'playit kurulamadı, bu adım atlanıyor.'); claimFail = (L 'playit bağlantısı tamamlanmadı. Tekrar deneyebilirsin.'); waiting = (L 'Tarayıcıda onaylamanı bekliyorum (en fazla 10 dakika)...') }
        Head = (L 'Java {0} indiriliyor...' 21); JavaFuncs = $(if ($JavaFuncs) { $JavaFuncs.ToString() } else { '' })
        TextTable = $TextTable; LangCode = $LangCode; LFunc = ${function:L}.ToString()
    }
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript($FrJobScript.ToString()).AddArgument($sy).AddArgument($kind).AddArgument($ctx)
        $Fr.Job = [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
    } catch {
        # Çalışma alanı açılamadı: iş hemen hatayla biter (Fr-Poll gösterir)
        $sy.Error = Get-FrErrorText $_.Exception; $sy.Done = $true; $Fr.Job = 'hata'
    }
}

function FrBusy { [bool]($null -ne $Fr -and $null -ne $Fr.Job -and -not $Fr.Sync.Done) }

# Her turda: biten işin sonucunu uygula
function Fr-Poll {
    if ($null -eq $Fr -or $null -eq $Fr.Job -or -not $Fr.Sync.Done) { return }
    $job = $Fr.Job; $Fr.Job = $null
    if ($job -isnot [string]) { try { [void]$job.PS.EndInvoke($job.Handle) } catch {}; try { $job.PS.Dispose() } catch {} }
    if ($null -ne $Fr.Sync.Code) { $Fr.Code = $Fr.Sync.Code }
    $script:FrJavaAt = [DateTime]::MinValue
    $script:Dirty = $true
    switch -CaseSensitive (FrStep) {
        'java' { if ($null -ne $Fr.Sync.Error) { $Fr.Note = L 'Java 21 indirilemedi: {0}' $Fr.Sync.Error; $Fr.NoteCol = $c.red } }
        'arkadas' { PlayitJobDone }
    }
}

# ---------- Tuşlar ----------
# Not: bu işleyicinin çıktısı ana döngüde ekrana yazılır; arka uç işlevlerinin dönüşleri $null = ile yutulur.
function Handle-FirstRunKey([ConsoleKeyInfo]$k, [bool]$ctrl) {
    if ($null -eq $Fr) { $script:Screen = 'home'; Reset-Frame; return }
    if (FrBusy) { if ($k.Key -eq 'Escape' -and (FrStep) -ceq 'arkadas') { PlayitCancel }; return }
    # F10: SyHost'tan çık (kurulum yarıda kalırsa bir sonraki açılışta kaldığı yerden devam eder)
    if ($k.Key -eq 'F10' -and $null -eq $Fr.ReturnTo) { if (Allow 'F10') { Start-Outro }; return }
    switch -CaseSensitive (FrStep) {
        'dil' {
            if ($k.Key -eq 'UpArrow' -or $k.Key -eq 'DownArrow') {
                $n = $Languages.Count
                $Fr.Sel = ($Fr.Sel + $(if ($k.Key -eq 'UpArrow') { $n - 1 } else { 1 })) % $n
                $script:LangCode = @($Languages.Keys)[$Fr.Sel]   # seçim anında bütün ekran o dile geçer
                Init-Tables
            } elseif ($k.Key -eq 'Enter') {
                $Cfg.dil = $LangCode
                if (-not $SetupMode) { Save-Config }
                FrNext
            }
            return
        }

        'konum' {
            $opts = FrLocationOptions
            if ($k.Key -eq 'UpArrow') { $Fr.Sel = ($Fr.Sel + $opts.Count - 1) % $opts.Count; FrCheckTarget }
            elseif ($k.Key -eq 'DownArrow') { $Fr.Sel = ($Fr.Sel + 1) % $opts.Count; FrCheckTarget }
            elseif ($k.Key -eq 'Escape') { FrBack }
            elseif ($k.Key -eq 'Enter') {
                $kind = [string]$opts[$Fr.Sel][1]
                if ($kind -ceq 'pick') {
                    $start = if ([IO.Directory]::Exists($Fr.Target)) { $Fr.Target } else { [IO.Path]::GetDirectoryName($Fr.Target) }
                    $picked = if ($TestFrame) { $null } else { Pick-Folder (L "SyHost'un kurulacağı klasörü seç") $start }   # test modunda pencere açılmaz
                    Reset-Frame
                    if (-not [string]::IsNullOrEmpty($picked)) {
                        # Dolu bir klasörü kirletmemek için içine "SyHost" klasörü açılır
                        $empty = Test-FrEmptyDir $picked
                        $Fr.Target = if ($empty -or [string]::Equals([IO.Path]::GetFileName($picked.TrimEnd('\')), 'SyHost', [StringComparison]::OrdinalIgnoreCase) -or (Test-Installed $picked)) { [string]$picked } else { [IO.Path]::Combine($picked, 'SyHost') }
                        $Fr.Sel = if ($null -ne $Fr.OtherInstall) { 1 } else { 0 }
                        FrCheckTarget
                    }
                    return
                }
                if ($kind -ceq 'target' -and (Test-InOneDrive $Fr.Target) -and -not $Fr.Confirm) { $Fr.Confirm = $true; $Fr.Note = L "Yine de buraya kurmak için tekrar Enter'a bas."; $Fr.NoteCol = $c.yellow; return }
                FrInstall $kind
            }
            return
        }

        'tasima' {
            if ($null -ne $FrMovedTo -and $null -eq $FrMigrated) {
                if ($k.Key -eq 'UpArrow' -or $k.Key -eq 'DownArrow') { $Fr.Sel = 1 - $Fr.Sel }
                elseif ($k.Key -eq 'Enter') {
                    if ($Fr.Sel -eq 0) { Do-Migrate }
                    elseif (-not [IO.File]::Exists($ServersFile)) { Write-TextFile $ServersFile '[]' }   # kararı hatırla: bir daha sorma
                    $script:FrMovedTo = $null
                    FrNext
                }
                return
            }
            if ($k.Key -eq 'Enter') { FrNext }
            return
        }

        'sistem' {
            if ($k.Key -eq 'Enter') { FrNext }
            elseif ($k.Key -eq 'Escape') { FrBack }
            return
        }

        'java' {
            $have = $null -ne (Find-Java 21)
            if ($have) { if ($k.Key -eq 'Enter') { FrNext } elseif ($k.Key -eq 'Escape') { FrBack }; return }
            if ($k.Key -eq 'UpArrow' -or $k.Key -eq 'DownArrow') { $Fr.Sel = 1 - $Fr.Sel }
            elseif ($k.Key -eq 'Escape') { FrBack }
            elseif ($k.Key -eq 'Enter') {
                if ($Fr.Sel -eq 1) { FrNext; return }
                $Fr.Note = $null
                # Başlık zaten "Java 21 indiriliyor..." der; altta yalnızca ilerleme (dosya adı ve MB) görünür
                FrRun 'java'
            }
            return
        }

        'arkadas' { PlayitKey $k; return }

        'yazi' {
            if ($k.Key -eq 'Escape') { FrBack; return }
            if ($k.Key -ne 'Enter') { return }
            # Kurulamadıysa (Confirm) Enter devam eder. Test modunda gerçek yazı tipine dokunulmaz: kurulamamış sayılır.
            if (-not $Fr.Confirm -and -not (FontOk)) {
                if (-not $TestFrame -and (Install-FontPerUser)) {
                    Set-FrCfg 'yaziTipiKuruldu' $true; Save-Config
                    [void][SyHost.Native]::SetFont('Cascadia Mono', [int16]$(if ($Cfg.yaziTipiBoyutu) { $Cfg.yaziTipiBoyutu } else { 16 }))
                    Reset-Frame
                } else { $Fr.Note = L 'Yazı tipi kurulamadı. SyHost yine çalışır, bazı semboller farklı görünebilir.'; $Fr.NoteCol = $c.yellow; $Fr.Confirm = $true; return }
            }
            FrNext
            return
        }

        'kisayol' {
            if ($k.Key -eq 'UpArrow' -or $k.Key -eq 'DownArrow') { $Fr.Sel = 1 - $Fr.Sel }
            elseif ($k.Key -eq 'Spacebar') { if ($Fr.Sel -eq 0) { $Fr.Desk = -not $Fr.Desk } else { $Fr.Start = -not $Fr.Start } }
            elseif ($k.Key -eq 'Escape') { FrBack }
            elseif ($k.Key -eq 'Enter') {
                $null = Apply-Shortcuts $Fr.Desk $Fr.Start   # tuş işleyicisinin çıktısı ekrana yazılırdı
                FrNext
            }
            return
        }

        'bitti' {
            if ($k.Key -eq 'Enter') { FrNext }
            return
        }
    }
}

# Eski verileri şimdi kopyala (kullanıcı "buraya da kopyala" dediyse)
function Do-Migrate {
    try {
        $script:FrMigrated = Copy-LegacyData $Data $AppRoot $LangCode
        Load-Config; Load-Servers; Init-Tables
    } catch {}
}

# ---------- Çizim ----------
# Logo ve sağında bilgi sütunu (ana menüdeki gibi)
function Setup-Header([int]$W, [string[]]$info) {
    $rows = New-Object System.Collections.Generic.List[string]
    $rows.Add('')
    $logo = Render-Logo 1.0 (Logo-Shine)
    for ($i = 0; $i -lt 6; $i++) { $rows.Add('    ' + $logo[$i] + $(if ($W -ge $LogoW + 52) { '        ' + $info[$i] } else { '' })) }
    $rows.Add('')
    , $rows
}

function Check-Row([string]$text) { '  ' + $c.green + $Bo + '✓' + $R + '  ' + $c.text + $text + $R }
function Warn-Row([string]$text) { '  ' + $c.yellow + $Bo + '!' + $R + '  ' + $c.soft + $text + $R }
function Soft-Row([string]$text) { '  ' + $c.soft + $text + $R }

# Seçenek satırı: seçiliyse ❯ ve nabız gibi atan zemin
function Option-Row([string]$text, [bool]$s, [int]$W) {
    $line = '   ' + $(if ($s) { $c.brass + $Bo + '❯ ' + $c.text } else { '  ' + $c.soft }) + $text + $R
    if ($s) { SelLine $line $W } else { $line }
}

# Java adımı için Java 21 (her karede diske gidilmesin diye en fazla saniyede bir aranır)
function FrJava {
    $now = [DateTime]::UtcNow
    if (($now - $script:FrJavaAt).TotalMilliseconds -ge 1000) { $script:FrJavaCache = Find-Java 21; $script:FrJavaAt = $now }
    $script:FrJavaCache
}

function Render-FirstRun([int]$W, [int]$H) {
    if ($null -eq $Fr) { Start-FirstRun $null }
    $step = FrStep
    $info = @(
        ($Bo + $c.brass + $(if ($SetupMode -and $Fr.Index -eq 0) { L 'HOŞ GELDİN' } else { L 'KURULUM' }) + $R),
        (VersionLine),
        ($c.dark + ('─' * 38) + $R),
        ($c.soft + (L 'Adım {0}/{1}' ($Fr.Index + 1) $Fr.Steps.Count) + $c.dark + '  ·  ' + $R + $c.text + (L $FrStepNames[$step][0]) + $R),
        ($c.dim + (L 'Birkaç adımda her şey hazır.') + $R),
        ''
    )
    $rows = Setup-Header $W $info

    # Adım çubuğu (sihirbazdaki gibi)
    if ($Fr.Steps.Count -gt 1) {
        $bar = '  '
        for ($i = 0; $i -lt $Fr.Steps.Count; $i++) {
            $col = if ($i -lt $Fr.Index) { $c.green } elseif ($i -eq $Fr.Index) { $c.brass + $Bo } else { $c.dark }
            $bar += $col + ($i + 1) + ' ' + (L $FrStepNames[$Fr.Steps[$i]][0]) + $R + $c.dark + $(if ($i -lt $Fr.Steps.Count - 1) { '  ›  ' } else { '' }) + $R
        }
        $rows.Add($bar)
        $rows.Add('')
    }
    $rows.Add((Rule (L $FrStepNames[$step][1]) $W))
    $rows.Add('')

    $keys = ''
    switch -CaseSensitive ($step) {
        'dil' {
            $codes = @($Languages.Keys)
            for ($i = 0; $i -lt $codes.Count; $i++) { $rows.Add((Option-Row $Languages[$codes[$i]] ($i -eq $Fr.Sel) $W)) }
            $rows.Add('')
            $rows.Add('  ' + $c.dim + (L "Dil daha sonra Ayarlar'dan değiştirilebilir.") + $R)
            # Kurulum (konum adımı olmadan) başarısız olduysa nedeni
            if ($null -ne $Fr.Note) { $rows.Add(''); foreach ($l in (WordWrap $Fr.Note ($W - 8))) { $rows.Add('  ' + $Fr.NoteCol + $l + $R) } }
            $keys = (Key '↑↓' (L 'seç')) + (Key 'Enter' (L 'devam'))
        }

        'konum' {
            $rows.Add('  ' + $c.soft + (L 'SyHost nereye kurulsun? Ayarların ve sunucuların bu klasörde durur.') + $R)
            $rows.Add('')
            $opts = FrLocationOptions
            for ($i = 0; $i -lt $opts.Count; $i++) {
                $s = $i -eq $Fr.Sel
                $label = [string]$opts[$i][0]
                $extra = if ([string]$opts[$i][1] -ceq 'target' -and [string]::Equals($Fr.Target, [string](DefaultRootShown), [StringComparison]::OrdinalIgnoreCase)) { $c.green + '   ' + (L 'önerilen') + $R } else { '' }
                $line = '   ' + $(if ($s) { $c.brass + $Bo + '❯ ' + $c.text } else { '  ' + $c.soft }) + $label + $R + $extra
                $rows.Add($(if ($s) { SelLine $line $W } else { $line }))
            }
            $rows.Add('')
            if ($null -ne $Fr.Note) { foreach ($l in (WordWrap $Fr.Note ($W - 8))) { $rows.Add('  ' + $Fr.NoteCol + $l + $R) } }
            $keys = (Key '↑↓' (L 'seç')) + (Key 'Enter' (L 'kur')) + $(if ($Fr.Index -gt 0) { Key 'Esc' (L 'geri') } else { '' })
        }

        'tasima' {
            if ($null -ne $FrMigrated) {
                $rows.Add((Check-Row (L 'Eski ayarların taşındı')))
                $rows.Add('')
                $rows.Add('     ' + $c.soft + (L '{0} sunucu ve ayarların bu klasöre kopyalandı.' $FrMigrated.Servers) + $R)
                if ($FrMigrated.Playit) { $rows.Add('     ' + $c.soft + (L 'playit bağlantın da taşındı.') + $R) }
                $rows.Add('     ' + $c.dim + (L 'Eski klasör silinmedi: {0}' (LegacyDirShown)) + $R)
                $keys = Key 'Enter' (L 'devam')
            } else {
                $rows.Add((Warn-Row (L 'Eski verilerin daha önce şuraya taşınmış: {0}' $FrMovedTo)))
                $rows.Add('     ' + $c.dim + (L 'İki SyHost aynı playit bağlantısını kullanırsa birbirini bozar.') + $R)
                $rows.Add('')
                $o = @((L 'Buraya da kopyala'), (L 'Kopyalama, temiz başla'))
                for ($i = 0; $i -lt 2; $i++) { $rows.Add((Option-Row $o[$i] ($i -eq $Fr.Sel) $W)) }
                $keys = (Key '↑↓' (L 'seç')) + (Key 'Enter' (L 'devam'))
            }
        }

        'sistem' {
            $os = [Environment]::OSVersion.Version; $build = OsBuild
            if ($os.Major -lt 10) { $rows.Add('  ' + $c.red + $Bo + 'x' + $R + '  ' + $c.red + (L 'SyHost Windows 10 veya 11 ister.') + $R) }
            else { $rows.Add((Check-Row ('Windows ' + $(if ($build -ge 22000) { '11' } else { '10' }) + ' (' + $build + ')'))) }
            $ramGb = [int][Math]::Round($TotalRam / 1073741824.0)
            $rows.Add((Check-Row (L '{0} GB RAM, {1} çekirdek' $ramGb $Threads)))
            if ($ramGb -lt 8) { $rows.Add((Warn-Row (L 'Modlu sunucular için en az 8 GB RAM önerilir.'))) }
            $rows.Add((Check-Row (L 'SyHost klasörü: {0}' $AppRoot)))
            $keys = (Key 'Enter' (L 'devam')) + (Key 'Esc' (L 'geri'))
        }

        'java' {
            $j = FrJava
            if (FrBusy) {
                $rows.Add('  ' + $c.brass + (Spin) + $R + '  ' + (Shimmer (L 'Java {0} indiriliyor...' 21) @(229, 231, 235) @(255, 70, 80)))
                if (-not [string]::IsNullOrEmpty($Fr.Sync.Text)) { $rows.Add('     ' + $c.dim + $Fr.Sync.Text + $R) }
            } elseif ($null -ne $j) {
                $own = if ($null -ne $TestJavaOwn) { [bool]$TestJavaOwn } else { [bool](Test-Inside $j $AppRoot) }
                $rows.Add((Check-Row ((L 'Java 21 hazır') + $c.dim + $(if ($own) { L ' (SyHost klasöründe)' } else { L ' (bilgisayarında kurulu)' }))))
                $rows.Add('')
                $rows.Add('  ' + $c.dim + (L 'Eski paketlerin istediği Java 8 ve 17 gerekince kendiliğinden iner.') + $R)
                $keys = (Key 'Enter' (L 'devam')) + (Key 'Esc' (L 'geri'))
            } else {
                foreach ($l in (WordWrap (L 'Çoğu modpack Java 21 ister. Şimdi indirilsin mi? Yaklaşık 50 MB, yalnızca SyHost klasörüne iner.') ($W - 8))) { $rows.Add('  ' + $c.soft + $l + $R) }
                $rows.Add('')
                $o = @((L 'İndir'), (L 'Sonra (sunucu kurarken iner)'))
                for ($i = 0; $i -lt 2; $i++) { $rows.Add((Option-Row $o[$i] ($i -eq $Fr.Sel) $W)) }
                if ($null -ne $Fr.Note) { $rows.Add(''); $rows.Add('  ' + $Fr.NoteCol + $Fr.Note + $R) }
                $keys = (Key '↑↓' (L 'seç')) + (Key 'Enter' (L 'devam')) + (Key 'Esc' (L 'geri'))
            }
        }

        'arkadas' { $keys = Render-PlayitStep $rows $W }

        'yazi' {
            $fontOk = FontOk
            if ($fontOk) { $rows.Add((Check-Row (L 'Cascadia Mono yazı tipi hazır'))) }
            else { foreach ($l in (WordWrap (L 'Logonun ve animasyonların doğru görünmesi için Cascadia Mono yazı tipi yalnızca senin kullanıcına kurulacak (yönetici izni gerekmez).') ($W - 8))) { $rows.Add('  ' + $c.soft + $l + $R) } }
            if ($null -ne $Fr.Note) { $rows.Add(''); $rows.Add('  ' + $Fr.NoteCol + $Fr.Note + $R) }
            $keys = (Key 'Enter' $(if ($fontOk -or $Fr.Confirm) { L 'devam' } else { L 'kur' })) + (Key 'Esc' (L 'geri'))
        }

        'kisayol' {
            $o = @(@((L 'Masaüstüne kısayol'), [bool]$Fr.Desk), @((L 'Başlat menüsüne kısayol'), [bool]$Fr.Start))
            for ($i = 0; $i -lt 2; $i++) {
                $s = $i -eq $Fr.Sel
                $box = if ($o[$i][1]) { $c.brass + $Bo + '■' + $R } else { $c.dark + '□' + $R }
                $line = '   ' + $(if ($s) { $c.brass + $Bo + '❯ ' } else { '  ' }) + $R + $box + ' ' + $(if ($s) { $c.text } else { $c.soft }) + $o[$i][0] + $R
                $rows.Add($(if ($s) { SelLine $line $W } else { $line }))
            }
            $rows.Add('')
            if ($null -ne $Fr.Note) { foreach ($l in (WordWrap $Fr.Note ($W - 8))) { $rows.Add('  ' + $Fr.NoteCol + $l + $R) } }
            $keys = (Key '↑↓' (L 'seç')) + (Key (L 'Boşluk') (L 'aç/kapat')) + (Key 'Enter' (L 'uygula')) + (Key 'Esc' (L 'geri'))
        }

        'bitti' {
            $rows.Add('  ' + $c.green + $Bo + '✓  ' + (L 'Her şey hazır!') + $R)
            $rows.Add('')
            foreach ($l in (WordWrap (L 'Sunucu eklemek için ana menüde "Yeni sunucu ekle"yi seç ve bir Modrinth paketi (.mrpack) aç.') ($W - 8))) { $rows.Add('  ' + $c.soft + $l + $R) }
            $rows.Add('  ' + $c.dim + (L 'Ayarlara her zaman F9 ile ulaşabilirsin.') + $R)
            $rows.Add('')
            $rows.Add('  ' + (Pill '240;240;240' '18;18;20' 'Enter') + $c.text + (L ' Başla') + $R)
        }
    }

    # Boş satırlara gökyüzü, altta tuşlar (ana menüdeki gibi)
    while ($rows.Count -lt $H - 2) { $rows.Add('') }
    Update-Sky $W $H 0.07 1 $false 0.75
    for ($r1 = 0; $r1 -lt $rows.Count; $r1++) { if ($rows[$r1] -eq '') { $rows[$r1] = Sky-Seg $r1 0 $W } }
    $rows.Add($c.dark + ('─' * $W) + $R)
    $rows.Add(' ' + $keys)
    , $rows
}

# =====================================================================
#  Arkadaş bağlantısı (playit.gg): soru → (indir) → bağla (tarayıcıda onay) → tünel adresleri → hazır
#  playit hiçbir yere kurulmaz: tek exe'lik iki program Data\tools\playit içine iner ve yalnızca
#  SyHost açıkken çalışır. Eski sürümün Program Files'taki playit'i varsa o da kullanılabilir.
#  playitd.exe tünelleri çalıştırır (Start-Playit), playit.exe yalnızca hesap bağlama aracıdır.
# =====================================================================

# Hesap bağlama komutlarını çalıştıracak playit aracı ($null: yok)
function PlayitCliExe {
    $own = [IO.Path]::Combine($PlayitToolDir, 'playit.exe')
    if ([IO.File]::Exists($own)) { return $own }
    $legacy = [IO.Path]::Combine($PlayitLegacyBin, 'playit.exe')
    if ([IO.File]::Exists($legacy)) { return $legacy }
    $null
}

# Tünelleri çalıştıracak program var mı?
function PlayitDaemonAvailable { [IO.File]::Exists([IO.Path]::Combine($PlayitToolDir, 'playitd.exe')) -or [IO.File]::Exists([IO.Path]::Combine($PlayitLegacyBin, 'playitd.exe')) }

# Bağlantı zaten kurulu mu (anahtar, adres ve program var)? Test modunda senaryo söyler.
function PlayitReady {
    if ($null -ne $TestPlayitReady) { return [bool]$TestPlayitReady }
    [bool]($Cfg.playitKullan -and [IO.File]::Exists($PlayitSecret) -and -not [string]::IsNullOrEmpty($Cfg.arkadasAdresi) -and (PlayitDaemonAvailable))
}

# Esc: çalışan playit komutunu kapat (sıradakiler de başlamaz), soruya dön
function PlayitCancel {
    $Fr.Sync.Cancel = $true
    try { $p = $Fr.Sync.Proc; if ($null -ne $p) { $p.Kill() } } catch {}
    $Fr.Phase = 'soru'; $Fr.Note = L 'playit bağlantısı tamamlanmadı. Tekrar deneyebilirsin.'; $Fr.NoteCol = $c.yellow
}

# Arka plandaki playit işi bitince sonraki aşamaya geç
function PlayitJobDone {
    if ($null -ne $Fr.Sync.Error) {
        $Fr.Phase = 'soru'; $Fr.Note = $Fr.Sync.Error; $Fr.NoteCol = $c.red
        return
    }
    if ($Fr.Phase -ceq 'indir') { $Fr.Phase = 'bagla'; FrRun 'claim'; return }
    if ($Fr.Phase -ceq 'bagla') {
        $Fr.Phase = 'adres'; $Fr.Field = 0
        $Fr.McAddr = if ($null -ne $Cfg.arkadasAdresi) { [string]$Cfg.arkadasAdresi } else { '' }
        $Fr.VoiceAddr = if ($null -ne $Cfg.sesAdresi) { [string]$Cfg.sesAdresi } else { '' }
        if (-not $FrNoBrowser) { try { Start-Process 'https://playit.gg/account/tunnels' } catch {} }
    }
}

function PlayitKey([ConsoleKeyInfo]$k) {
    switch -CaseSensitive ($Fr.Phase) {
        'soru' {
            if ($k.Key -eq 'UpArrow' -or $k.Key -eq 'DownArrow') { $Fr.Sel = 1 - $Fr.Sel; return }
            if ($k.Key -eq 'Escape') { FrBack; return }
            if ($k.Key -ne 'Enter') { return }
            $Fr.Note = $null
            if (PlayitReady) {
                if ($Fr.Sel -eq 0) { FrNext; return }
                $Fr.Phase = 'bagla'; FrRun 'claim'; return   # yeniden bağla
            }
            if ($Fr.Sel -eq 1) {
                # Şimdilik hayır: sunucuya bu bilgisayardan ve aynı evdeki ağdan girilebilir
                Set-FrCfg 'playitKullan' $false; Save-Config; $script:HasFriendAddr = $false; $script:FriendAddr = L 'henüz yok'
                FrNext; return
            }
            if ($null -eq (PlayitCliExe) -or -not (PlayitDaemonAvailable)) { $Fr.Phase = 'indir'; FrRun 'download' }
            else { $Fr.Phase = 'bagla'; FrRun 'claim' }
            return
        }

        'adres' {
            # Yazılan alan: 0 Minecraft adresi, 1 sesli sohbet adresi (C#: ref val)
            $mc = $Fr.Field -eq 0
            $val = if ($mc) { [string]$Fr.McAddr } else { [string]$Fr.VoiceAddr }
            if ($k.Key -eq 'Backspace') { if ($val.Length -gt 0) { $val = $val.Substring(0, $val.Length - 1); if ($mc) { $Fr.McAddr = $val } else { $Fr.VoiceAddr = $val } }; return }
            if ($k.Key -eq 'Escape') { if ($Fr.Field -eq 1) { $Fr.Field = 0 } else { $Fr.Phase = 'soru' }; return }
            if ($k.Key -eq 'Enter') {
                $val = $val.Trim(); if ($mc) { $Fr.McAddr = $val } else { $Fr.VoiceAddr = $val }
                if ($Fr.Field -eq 0) {
                    if (-not $AddrRx.IsMatch($Fr.McAddr)) { $Fr.Note = L 'Adres anlaşılamadı. Örnek: bir-sey.joinmc.link'; $Fr.NoteCol = $c.yellow; return }
                    $Fr.Note = $null; $Fr.Field = 1; return
                }
                if ($Fr.VoiceAddr.Length -gt 0 -and -not $AddrRx.IsMatch($Fr.VoiceAddr)) { $Fr.Note = L 'Sesli sohbet adresi anlaşılamadı, boş bırakıldı.'; $Fr.NoteCol = $c.yellow; $Fr.VoiceAddr = '' }
                Set-FrCfg 'arkadasAdresi' $Fr.McAddr; Set-FrCfg 'sesAdresi' $Fr.VoiceAddr; Set-FrCfg 'playitKullan' $true
                Save-Config
                $script:HasFriendAddr = $true; $script:FriendAddr = $Fr.McAddr
                Stop-Playit; Start-Playit
                $Fr.Phase = 'hazir'
                return
            }
            if ([int]$k.KeyChar -ge 32 -and $val.Length -lt 120) { $val += $k.KeyChar; if ($mc) { $Fr.McAddr = $val } else { $Fr.VoiceAddr = $val } }
            return
        }

        'hazir' {
            if ($k.Key -eq 'Enter') { FrNext }
            return
        }
    }
}

# Arkadaş adımını çiz (satırları $rows'a ekler), alttaki tuş satırını döndürür
function Render-PlayitStep($rows, [int]$W) {
    $ph = $Fr.Phase
    if ($ph -ceq 'indir' -or $ph -ceq 'bagla') {
        if ($ph -ceq 'bagla') {
            $rows.Add('  ' + $c.text + $Bo + (L 'playit hesabına bağlanma') + $R)
            $rows.Add((Soft-Row (L '1. Birazdan tarayıcıda playit.gg açılacak.')))
            $rows.Add((Soft-Row (L '2. Hesabın yoksa bedava oluştur (Create Account), varsa giriş yap.')))
            $rows.Add((Soft-Row (L '3. Çıkan sayfada bu bilgisayarı onayla (Continue / Add Agent).')))
            $rows.Add('')
        }
        $rows.Add('  ' + $c.brass + (Spin) + $R + '  ' + (Shimmer $(if ([string]::IsNullOrEmpty($Fr.Sync.Text)) { L 'playit indiriliyor...' } else { [string]$Fr.Sync.Text }) @(229, 231, 235) @(255, 70, 80)))
        if ($ph -ceq 'bagla') { return (Key 'Esc' (L 'iptal')) }
        return ''
    }
    if ($ph -ceq 'adres') {
        $rows.Add('  ' + $c.text + $Bo + (L 'Arkadaşlarının bağlanacağı adres') + $R)
        $rows.Add((Soft-Row (L '1. Birazdan playit.gg tünel sayfası açılacak.')))
        $rows.Add((Soft-Row (L '2. "Add Tunnel" > "Minecraft Java" seç > Continue > bölge "Automatic (Free)" > Create Tunnel.')))
        $rows.Add((Soft-Row (L '3. Sesli sohbet modu kullanıyorsan bir tane de "MC: Simple Voice Chat" tüneli oluştur.')))
        $rows.Add((Soft-Row (L '4. Tünellerin adreslerini aşağıya yapıştır (sağ tık = yapıştır).')))
        $rows.Add('')
        $caret = if ([int]((T) * 2) % 2 -eq 0) { $c.brass + '▌' } else { ' ' }
        $f = @(
            @((L 'Minecraft adresi'), (L '(ör. bir-sey.joinmc.link veya xxx.tun.ply.gg)'), [string]$Fr.McAddr),
            @((L 'Sesli sohbet adresi'), (L '(yoksa boş bırakıp Enter)'), [string]$Fr.VoiceAddr)
        )
        for ($i = 0; $i -lt 2; $i++) {
            $s = $i -eq $Fr.Field
            $rows.Add('  ' + $(if ($s) { $c.text + $Bo } else { $c.soft }) + $f[$i][0] + $R + '  ' + $c.dim + $f[$i][1] + $R)
            $rows.Add('  ' + $(if ($s) { $c.brass + $Bo + '❯ ' } else { $c.dark + '  ' }) + $R + $Bo + $c.text + $f[$i][2] + $R + $(if ($s) { $caret } else { '' }) + $R)
        }
        if ($null -ne $Fr.Note) { $rows.Add(''); $rows.Add('  ' + $Fr.NoteCol + $Fr.Note + $R) }
        return (Key 'Enter' (L 'devam')) + (Key 'Esc' (L 'geri'))
    }
    if ($ph -ceq 'hazir') {
        $rows.Add((Check-Row (L 'Arkadaş adresi kaydedildi: {0}' $Cfg.arkadasAdresi)))
        if (-not [string]::IsNullOrEmpty($Cfg.sesAdresi)) { $rows.Add((Check-Row (L 'Sesli sohbet:  {0}  (otomatik)' $Cfg.sesAdresi))) }
        $rows.Add('')
        $rows.Add('  ' + $c.dim + (L "SyHost playit'i sadece kendisi açıkken çalıştırır, bilgisayarın açılışında başlamaz.") + $R)
        return (Key 'Enter' (L 'devam'))
    }
    # soru
    if (PlayitReady) {
        $rows.Add((Check-Row (L 'Arkadaş bağlantısı hazır: {0}' $Cfg.arkadasAdresi)))
        $rows.Add('')
        $opts = @((L 'Devam'), (L 'Yeniden bağla'))
    } else {
        $rows.Add((Soft-Row (L 'Çoğu ev internetinde (CGNAT) arkadaşların doğrudan bağlanamaz.')))
        $rows.Add((Soft-Row (L 'playit.gg bunu bedava çözer ve sana sabit bir adres verir (ör. bir-sey.joinmc.link).')))
        $rows.Add((Soft-Row (L "SyHost playit'i sadece kendisi açıkken çalıştırır, bilgisayarın açılışında başlamaz.")))
        $rows.Add('')
        $rows.Add('  ' + $c.text + $Bo + (L 'Arkadaşların internetten bağlanabilsin mi?') + $R)
        $opts = @((L 'Evet, bağlantıyı kur'), (L 'Şimdilik hayır'))
    }
    for ($i = 0; $i -lt $opts.Count; $i++) { $rows.Add((Option-Row $opts[$i] ($i -eq $Fr.Sel) $W)) }
    if ($null -ne $Fr.Note) { $rows.Add(''); foreach ($l in (WordWrap $Fr.Note ($W - 8))) { $rows.Add('  ' + $Fr.NoteCol + $l + $R) } }
    (Key '↑↓' (L 'seç')) + (Key 'Enter' (L 'devam')) + (Key 'Esc' (L 'geri'))
}
