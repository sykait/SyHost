// =====================================================================
//  SyHost - sunucu kontrolü (çizim yok)
//  legacy/src/SyHost.ps1: sunucu listesi (93-108), paketler (395-421),
//  playit (423-435), sunucu kontrolü ve yedek (437-561),
//  ekranlar arası geçiş (563-602). Satır satır aynı sıra, aynı metinler.
// =====================================================================
using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace SyHost;

sealed partial class App
{
    // PowerShell'in -match / switch -Regex / -split işleçleri gibi: büyük-küçük harf duyarsız.
    // Çalışma anında kurulur, böylece PowerShell gibi bilgisayarın kültürünü kullanır
    // (tr-TR'de 'I' ile 'i' eşleşmez; Minecraft'ın kendi metinleri zaten küçük harfli).
    static readonly Regex SrvRxPackLow = new(@"^(dusuk|low|eco|1|低)$", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxPackNormal = new(@"^(normal|orta|2|標準)$", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxPackHigh = new(@"^(yuksek|high|max|3|高)$", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxVoiceHost = new(@"(?m)^voice_host=(.*)$", RegexOptions.IgnoreCase);
    // [regex]::Replace bir işleç değil, .NET çağrısı: büyük-küçük harf duyarlı
    static readonly Regex SrvRxVoiceHostLine = new(@"(?m)^voice_host=.*$");
    static readonly Regex SrvRxStarting = new(@"^Starting minecraft server version", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxPreparing = new(@"Preparing (level|start region|spawn)", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxStopping = new(@"^Stopping the server", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxSaving = new(@"Saving (worlds|chunks|players)", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxAllSaved = new(@"All (dimensions|chunks) are saved", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxDone = new(@"^Done \(([\d\.,]+)s\)!", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxJoined = new(@"^(\S{1,16}) joined the game$", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxLeft = new(@"^(\S{1,16}) left the game$", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxChat = new(@"^<([^>]+)> (.*)$", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxList = new(@"There are (\d+) of a max of (\d+) players online:?\s*(.*)$", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxSavedGame = new(@"^Saved the game", RegexOptions.IgnoreCase);
    static readonly Regex SrvRxComma = new(@",\s*", RegexOptions.IgnoreCase);

    // ---------- Sunucu listesi (93-108) ----------
    private partial void LoadServers()
    {
        Servers.Clear();
        if (!File.Exists(ServersFile)) return;
        List<ServerEntry> data;
        try { data = Json.ParseServers(SrvReadText(ServersFile)); }
        catch
        {
            // Bozuk liste: kenara al, boş listeyle devam et (veri kaybolmasın)
            try { File.Copy(ServersFile, ServersFile + ".bozuk", true); } catch { }
            return;
        }
        foreach (var sv in data)
        {
            if (sv == null) continue;
            if (string.IsNullOrEmpty(sv.paket)) sv.paket = "normal";
            // Bellekte her zaman mutlak yol
            sv.klasor = FromStoredPath(sv.klasor);
            Servers.Add(sv);
        }
    }

    // Dosyayı oku; başka bir program (ör. eşitleme, virüs tarayıcı) bir anlığına kilitlediyse birkaç kez dene
    static string SrvReadText(string path)
    {
        for (int i = 0; ; i++)
        {
            try { return Json.ReadText(path); }
            catch (IOException) when (i < 4) { Thread.Sleep(50); }
        }
    }

    private partial void SaveServers()
    {
        // Bellektekilere dokunmadan kopyala. JSON'a yazıp geri okumak bütün alanları
        // (tanınmayan alanlar dahil) taşır; ServerEntry'ye alan eklense de kaybolmaz.
        var copy = Json.ParseServers(Json.WriteServers(Servers));
        for (int i = 0; i < copy.Count && i < Servers.Count; i++)
            if (copy[i] != null && Servers[i] != null) copy[i].klasor = ToStoredPath(Servers[i].klasor);
        string json = Json.WriteServers(copy);
        for (int i = 0; ; i++)
        {
            try { Json.WriteText(ServersFile, json); return; }
            catch (Exception ex) when (i < 2 && ex is IOException or UnauthorizedAccessException) { Thread.Sleep(60); }
            catch (Exception ex)
            {
                // Kayıt yazılamadı: paneli çökertme (sunucu açık olabilir). Bellekteki liste doğru,
                // bir sonraki kayıtta yine yazılır. Ayrıntı hata.log'da.
                SrvLogError("sunucular.json yazılamadı", ex);
                return;
            }
        }
    }

    void SrvLogError(string what, Exception ex)
    {
        try { File.AppendAllText(ErrorLog, $"[{DateTime.Now}] {what}: {ex}{Environment.NewLine}", Json.Utf8NoBom); } catch { }
    }

    // ---------- Paketler (395-421) ----------
    private partial long GetMask(int n)
    {
        if (n <= 0 || n >= Threads) n = Threads;
        long m = 0;
        for (int i = Threads - n; i < Threads; i++) m |= 1L << i;
        return m;
    }

    private partial void ApplyPackLive()
    {
        if (!(S != null && S.Running)) return;
        Packs.TryGetValue(ActivePack ?? "", out Pack p);
        try { if (Enum.TryParse(p?.oncelik, true, out ProcessPriorityClass prio)) S.P.PriorityClass = prio; } catch { }
        try { S.P.ProcessorAffinity = (nint)GetMask(p?.cekirdek ?? 0); } catch { }
    }

    private partial void SetPack(string name)
    {
        string n = Norm(name);
        string key = SrvRxPackLow.IsMatch(n) ? "dusuk" : SrvRxPackNormal.IsMatch(n) ? "normal" : SrvRxPackHigh.IsMatch(n) ? "yuksek" : null;
        if (key == null) { AddLog("warn", Lang.L("Böyle bir paket yok: '{0}'. Seçenekler: dusuk, normal, yuksek", name)); return; }
        ActivePack = key;
        PackSel = Array.IndexOf(PackKeys, key);
        if (Cur != null) { Cur.paket = key; SaveServers(); }
        Pack p = Packs[key];
        ApplyPackLive();
        AddLog("ok", Lang.L("Paket: {0}  ·  RAM {1}-{2} GB  ·  {3} çekirdek  ·  öncelik {4}", PackName(key), p.ramMin, p.ramMax, Math.Min(p.cekirdek, Threads), SrvPrioText(p.oncelik)));
        if (S != null && S.Running)
        {
            if (p.ramMax != LoadedRamMax) { RamPending = true; AddLog("panel", Lang.L("Çekirdek ve öncelik hemen uygulandı. RAM değişikliği için 'yeniden' yaz.")); }
            else RamPending = false;
        }
    }

    // $PrioTr[$p.oncelik]: tabloda yoksa boş
    string SrvPrioText(string oncelik) => oncelik != null && PrioTr.TryGetValue(oncelik, out string t) ? t : null;

    // Paket adının tablodaki yazılışı ('NORMAL' -> 'normal'); yoksa null
    static string SrvPackKey(string name)
    {
        foreach (string k in PackKeys) if (Ps.Eq(k, name)) return k;
        return null;
    }

    // Açık paketin ayarları (paket adı tabloda yoksa 'normal')
    Pack SrvActivePack() => Packs.TryGetValue(ActivePack ?? "", out Pack p) ? p : Packs["normal"];

    // ---------- playit (423-435): sadece SyHost açıkken ----------
    // Ajan, tünelleri çalıştıran playitd'dir (playit 2.x). Önce SyHost'un kendi indirdiği taşınabilir
    // kopya (Data\tools\playit\playitd.exe), yoksa bilgisayara kurulu olan. Servis, tepsi simgesi,
    // Windows açılışında başlama yok: SyHost'un alt süreci olarak çalışır, SyHost kapanınca kapanır.
    const string SrvPlayitInstalled = @"C:\Program Files\playit_gg\bin\playitd.exe";
    // Kurulu playit servisinin borusu (\\.\pipe\playitd-system) ile çakışmasın; bu boruya yalnız bu kullanıcı bağlanabilir
    const string SrvPlayitPipe = @"\\.\pipe\syhost-playit";

    private partial void StartPlayit()
    {
        if (!Cfg.playitKullan) return;
        if (Pl != null && Pl.Running) return;
        PlayitExe = SrvFindPlayit();
        // Ajan ya da anahtar yoksa playit'i bu oturum için kapat (dosyaya yazılmaz)
        if (PlayitExe == null || !File.Exists(PlayitSecret)) { HasFriendAddr = false; return; }   // ayar dosyadaki gibi kalır; program gelince yeniden denenir
        string dir = Path.GetDirectoryName(PlayitSecret);
        Pl = new ServerProcess();
        try { Pl.Start(PlayitExe, $"--secret-path \"{PlayitSecret}\" --socket-path {SrvPlayitPipe} --log-path \"{Path.Combine(dir, "playit.log")}\"", dir); } catch { }
    }

    string SrvFindPlayit()
    {
        string tools = Path.Combine(Data, "tools", "playit");
        // playit.exe de kabul edilir (playitd o adla kaydedildiyse); ama gerçek playit komut satırı
        // aracı tünel çalıştıramaz (--secret-path almaz), onu atla
        foreach (string exe in new[] { Path.Combine(tools, "playitd.exe"), Path.Combine(tools, "playit.exe"), SrvPlayitInstalled })
            if (File.Exists(exe) && !SrvIsPlayitCli(exe)) return exe;
        return null;
    }

    static bool SrvIsPlayitCli(string exe)
    {
        try { return string.Equals(FileVersionInfo.GetVersionInfo(exe).ProductName, "playit-cli", StringComparison.OrdinalIgnoreCase); }
        catch { return false; }
    }

    private partial void StopPlayit()
    {
        if (Pl != null && Pl.Running) { try { Pl.P.Kill(); } catch { } }
    }

    // ---------- Sunucu kontrolü (437-484) ----------
    private partial int GetModCount(string dir)
    {
        // Get-ChildItem mods -Filter *.jar: gizli olanlar sayılmaz, klasör yoksa 0
        try
        {
            var opts = new EnumerationOptions { AttributesToSkip = FileAttributes.Hidden, IgnoreInaccessible = true, MatchType = MatchType.Win32, RecurseSubdirectories = false };
            int n = 0;
            foreach (var _ in new DirectoryInfo(Path.Combine(dir, "mods")).EnumerateFileSystemInfos("*.jar", opts)) n++;
            return n;
        }
        catch { return 0; }
    }

    private partial void EnsureVoiceHost()
    {
        if (string.IsNullOrEmpty(Cfg.sesAdresi) || !Cfg.playitKullan) return;
        try
        {
            string vp = Path.Combine(Cur.klasor, @"config\voicechat\voicechat-server.properties");
            if (!File.Exists(vp)) return;
            string txt = File.ReadAllText(vp);
            Match m = SrvRxVoiceHost.Match(txt);
            if (m.Success && !Ps.Eq(m.Groups[1].Value.Trim(), Cfg.sesAdresi))
            {
                txt = SrvRxVoiceHostLine.Replace(txt, "voice_host=" + Cfg.sesAdresi);
                File.WriteAllText(vp, txt, Json.Utf8NoBom);
            }
        }
        catch { }   // ses ayarı yazılamasa da sunucu açılsın
    }

    private partial void StartServer()
    {
        if (S != null && S.Running) { AddLog("panel", Lang.L("Sunucu zaten açık.")); return; }
        if (Cur == null) return;
        string dir = Cur.klasor;
        if (!SrvExists(SrvJoin(dir, "mods")) && !SrvExists(dir)) { AddLog("error", Lang.L("Sunucu klasörü bulunamadı: {0}  (taşındı ya da silindi)", dir)); return; }
        List<int> other = OtherServerPids();
        if (other.Count > 0) { AddLog("error", Lang.L("Başka bir sunucu zaten çalışıyor (PID {0}). Önce onu kapat ya da 'zorla' yaz.", other[0])); return; }
        string java;
        try { java = FindJava(Cur.java); } catch { java = null; }   // Find-Java hata vermez, "bulunamadı" sayılır
        if (string.IsNullOrEmpty(java)) { AddLog("error", Lang.L("Java {0} bulunamadı. Sunucuyu yeniden kurman gerekebilir.", Cur.java)); return; }
        string eula = Path.Combine(dir, "eula.txt");
        // Set-Content -Encoding ASCII: satır sonu CRLF
        try { if (!File.Exists(eula) || !File.ReadAllText(eula).Contains("eula=true", StringComparison.OrdinalIgnoreCase)) File.WriteAllText(eula, "eula=true\r\n", Encoding.ASCII); } catch { }
        EnsureVoiceHost();
        Pack p = SrvActivePack();
        string gc = p.ramMax >= 12 ? "-XX:G1NewSizePercent=40 -XX:G1MaxNewSizePercent=50 -XX:G1HeapRegionSize=16M" : "-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M";
        string jargs = "-Xms" + Ps.S(p.ramMin) + "G -Xmx" + Ps.S(p.ramMax) + "G " + JvmBase + " " + gc + " -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 -Dsyhost=1 " + Cur.baslat;
        S = new ServerProcess();
        try { S.Start(java, jargs, dir); } catch (Exception ex) { AddLog("error", Lang.L("Sunucu başlatılamadı: {0}", ex.Message)); return; }
        CloseGuard.Current = S;
        ApplyPackLive();
        Status = "BASLIYOR"; StartTime = Now(); Players.Clear();
        LoadedRamMax = p.ramMax; RamPending = false; StopRequested = false; AutoRestartAt = null;
        LastCpuMs = 0; WasRunning = true; Stage = 1; StopPhase = 0;
        Cur.sonAcilis = Now().ToString("yyyy-MM-dd HH:mm"); SaveServers();
        AddLog("panel", Lang.L("Sunucu başlatılıyor...  paket {0} · RAM {1}-{2} GB", PackName(ActivePack), p.ramMin, p.ramMax));
    }

    // Test-Path: dosya ya da klasör var mı (yol boşsa ya da geçersizse yok sayılır)
    static bool SrvExists(string p)
    {
        if (string.IsNullOrEmpty(p)) return false;
        try { return File.Exists(p) || Directory.Exists(p); } catch { return false; }
    }

    static string SrvJoin(string dir, string name)
    {
        if (string.IsNullOrEmpty(dir)) return null;
        try { return Path.Combine(dir, name); } catch { return null; }
    }

    private partial void StopServer(string then)
    {
        if (!(S != null && S.Running))
        {
            if (Ps.Eq(then, "close")) FinishAt = Now().AddMilliseconds(700);
            else if (Ps.Eq(then, "restart")) StartServer();
            else AddLog("panel", Lang.L("Sunucu zaten kapalı."));
            return;
        }
        AfterStop = then; StopRequested = true; Status = "DURUYOR"; StopSentAt = Now(); StopPhase = 1;
        S.Send("stop");
        AddLog("panel", Lang.L("Sunucu durduruluyor, dünya kaydediliyor..."));
    }

    // ---------- Yedek (486-517) ----------
    private partial void StartBackup()
    {
        if (!string.IsNullOrEmpty(BackupStage)) { AddLog("warn", Lang.L("Zaten bir yedek alınıyor.")); return; }
        if (Cur == null) return;
        string dir;
        try { dir = Path.Combine(Cur.klasor, "yedekler"); Directory.CreateDirectory(dir); }
        catch (Exception ex)
        {
            // Klasör açılamadı (sürücü yok, izin yok): çökme yerine hatayı göster.
            // LastBackup ilerlesin ki otomatik yedek her turda yeniden denemesin.
            LastBackup = Now();
            AddLog("error", Lang.L("Yedek alınamadı: ") + ex.Message);
            return;
        }
        BackupDst = Path.Combine(dir, Ps.F("world-{0}.zip", Now().ToString("yyyy-MM-dd_HH-mm-ss")));
        LastBackup = Now();
        if (S != null && S.Running && Ps.Eq(Status, "ACIK"))
        {
            S.Send("save-off"); S.Send("save-all flush");
            BackupStage = "saving"; BackupSince = Now();
            AddLog("panel", Lang.L("Yedek: dünya diske kaydediliyor..."));
        }
        else BeginZip();
    }

    private partial void BeginZip()
    {
        string world = Cur == null ? null : SrvJoin(Cur.klasor, "world");
        if (!SrvExists(world))
        {
            AddLog("warn", Lang.L("Yedeklenecek dünya henüz yok (sunucu bir kez açılınca oluşur)."));
            if (S != null && S.Running) S.Send("save-on");
            BackupStage = null;
            return;
        }
        BackupTask = Backup.ZipAsync(world, BackupDst);
        BackupStage = "zipping";
        AddLog("panel", Lang.L("Yedek: sıkıştırılıyor (oyun devam edebilir)..."));
    }

    private partial void CheckBackup()
    {
        if (Ps.Eq(BackupStage, "saving") && BackupSince != null && (Now() - BackupSince.Value).TotalSeconds > 40) BeginZip();
        if (Ps.Eq(BackupStage, "zipping") && BackupTask != null && BackupTask.IsCompleted)
        {
            if (S != null && S.Running) S.Send("save-on");
            if (BackupTask.IsFaulted) AddLog("error", Lang.L("Yedek alınamadı: ") + BackupTask.Exception?.InnerException?.Message);
            else
            {
                try
                {
                    double mb = Math.Round(new FileInfo(BackupDst).Length / (1024.0 * 1024.0));
                    AddLog("ok", Lang.L("Yedek alındı: {0}  ({1} MB)", Path.GetFileName(BackupDst), mb));
                    RefreshFolderLook();   // ilk yedekte açılan yedekler klasörü de simgesini ve adını alsın
                    int keep = Cfg.saklanacakYedek;
                    if (keep > 0) SrvPruneBackups(Path.GetDirectoryName(BackupDst), keep);
                }
                catch (Exception ex) { AddLog("error", Lang.L("Yedek alınamadı: ") + ex.Message); }
            }
            BackupStage = null; BackupTask = null;
        }
    }

    // Get-ChildItem world-*.zip | Sort-Object Name -Descending | Select-Object -Skip $keep | Remove-Item -Force
    static void SrvPruneBackups(string dir, int keep)
    {
        try
        {
            var opts = new EnumerationOptions { AttributesToSkip = FileAttributes.Hidden, IgnoreInaccessible = true, MatchType = MatchType.Win32, RecurseSubdirectories = false };
            var items = new List<FileSystemInfo>(new DirectoryInfo(dir).EnumerateFileSystemInfos("world-*.zip", opts));
            items.Sort((a, b) => StringComparer.CurrentCultureIgnoreCase.Compare(b.Name, a.Name));
            for (int i = keep; i < items.Count; i++)
            {
                if (items[i] is not FileInfo f) continue;
                try { if (f.IsReadOnly) f.IsReadOnly = false; f.Delete(); } catch { }
            }
        }
        catch { }
    }

    // ---------- Sunucu çıktısı (519-561) ----------
    private partial void AddServerLine(string raw)
    {
        raw = AnsiRx.Replace(raw ?? "", "");
        string t, lvl, msg;
        Match m = LineRx.Match(raw);
        if (m.Success) { t = m.Groups[1].Value; lvl = m.Groups[3].Value; msg = m.Groups[5].Value; }
        else
        {
            Match m2 = LineRx2.Match(raw);
            if (m2.Success) { t = m2.Groups[1].Value; lvl = m2.Groups[3].Value; msg = m2.Groups[4].Value; }
            else { t = null; lvl = raw.StartsWith("[STDERR]", StringComparison.Ordinal) ? "ERROR" : "INFO"; msg = raw; }
        }
        string kind = Ps.Eq(lvl, "WARN") ? "warn" : Ps.In(lvl, "ERROR", "FATAL") ? "error" : "info";

        if (Ps.Eq(Status, "BASLIYOR"))
        {
            if (Stage < 2) Stage = 2;
            if (SrvRxStarting.IsMatch(msg) && Stage < 3) Stage = 3;
            else if (SrvRxPreparing.IsMatch(msg) && Stage < 4) Stage = 4;
        }
        if (SrvRxStopping.IsMatch(msg)) StopPhase = Math.Max(StopPhase, 1);
        else if (SrvRxSaving.IsMatch(msg)) StopPhase = Math.Max(StopPhase, 2);
        else if (SrvRxAllSaved.IsMatch(msg)) StopPhase = Math.Max(StopPhase, 3);

        if (SrvRxDone.IsMatch(msg))
        {
            Status = "ACIK";
            if (StartTime != null)
            {
                ExpectedStart = (int)Math.Ceiling((Now() - StartTime.Value).TotalSeconds);
                if (Cur != null) { Cur.sonBaslatmaSn = ExpectedStart; SaveServers(); }
            }
            AddLog("info", msg, t, false);
            if (HasFriendAddr) AddLog("ok", Lang.L("Sunucu hazır! ({0} sn)  Arkadaşların şu adresle girebilir: {1}", ExpectedStart, FriendAddr));
            else AddLog("ok", Lang.L("Sunucu hazır! ({0} sn)  Bu bilgisayardan 'localhost' ile girebilirsin.", ExpectedStart));
            Tray.Balloon(Lang.L("{0} açık", Cur?.ad), Lang.L("Arkadaşların artık girebilir."));
            return;
        }
        Match mm;
        if ((mm = SrvRxJoined.Match(msg)).Success) { Players.Add(mm.Groups[1].Value); kind = "join"; msg = Lang.L("{0} oyuna katıldı", mm.Groups[1].Value); }
        else if ((mm = SrvRxLeft.Match(msg)).Success) { Players.Remove(mm.Groups[1].Value); kind = "leave"; msg = Lang.L("{0} oyundan ayrıldı", mm.Groups[1].Value); }
        else if (SrvRxChat.IsMatch(msg)) kind = "chat";
        else if ((mm = SrvRxList.Match(msg)).Success)
        {
            Players.Clear();
            foreach (string n in SrvRxComma.Split(mm.Groups[3].Value)) { if (n.Trim().Length > 0) Players.Add(n.Trim()); }
            msg = Lang.L("Çevrimiçi: {0}/{1}", mm.Groups[1].Value, mm.Groups[2].Value) + (Players.Count > 0 ? "  ·  " + string.Join(", ", Players) : "");
            kind = "ok";
        }
        else if (SrvRxSavedGame.IsMatch(msg) && Ps.Eq(BackupStage, "saving")) { AddLog("info", msg, t, false); BeginZip(); return; }
        else if (SrvRxStopping.IsMatch(msg)) Status = "DURUYOR";
        bool vis = Ps.In(kind, "join", "leave", "chat", "ok") || (Ps.Eq(kind, "error") && Ps.Eq(Status, "ACIK")) || Now() < ReplyUntil;
        AddLog(kind, msg, t, vis);
    }

    // ---------- Ekranlar arası geçiş (563-602) ----------
    private partial void EnterServer(ServerEntry srv)
    {
        Cur = srv;
        Log.Clear(); Scroll = 0; Mode = "log"; InputText = "";
        // PowerShell 'NORMAL' gibi büyük harfli bir değeri olduğu gibi tutup PackSel'i -1 yapardı; tablodaki yazılışı kullan
        ActivePack = SrvPackKey(srv.paket) ?? "normal";
        PackSel = Array.IndexOf(PackKeys, ActivePack);
        ExpectedStart = srv.sonBaslatmaSn is int sn && sn != 0 ? Math.Max(10, sn) : 45;
        ModCount = GetModCount(srv.klasor);
        Status = "KAPALI"; WasRunning = false; Players.Clear(); LastBackup = Now();
        AutoRestartAt = null; StopSentAt = null; RamNow = 0; CpuNow = 0; Detail = false;
        CrashTimes.Clear();
        Screen = "server";
        if (Ps.Eq(Win.mod, "kucuk") && !Ps.Eq(UiMode, "kucuk")) SetUiMode("kucuk", NoSave: true); else ResetFrame();
        AddLog("panel", Lang.L("{0} açılıyor. Kapatmak için F10, nasıl kullanılır için F1.", srv.ad));
        StartServer();
    }

    private partial void GoHome()
    {
        Screen = "home"; Mode = "log"; HomeMode = "list";
        S = null; Status = "KAPALI"; FinishAt = null; ShutdownStopAt = null; AutoRestartAt = null; StopSentAt = null;
        CrashTimes.Clear();
        ModCountCache.Clear(); WorldSizeCache.Clear();
        if (Ps.Eq(UiMode, "kucuk")) { SetUiMode("buyuk", NoSave: true); Win.mod = "kucuk"; } else ResetFrame();
    }

    private partial void BeginShutdown(string after)
    {
        if (Ps.Eq(Mode, "closing")) return;
        AfterClose = after;
        Mode = "closing"; ClosingSince = Now();
        if (!TestMode) Native.Show();
        if (S != null && S.Running)
        {
            if (Ps.Eq(Status, "ACIK") && Players.Count > 0)
            {
                S.Send("say " + Lang.L("Sunucu kapaniyor, dunya kaydediliyor. Gorusuruz!"));
                ShutdownStopAt = Now().AddSeconds(3);
            }
            else ShutdownStopAt = Now();
        }
        else { ShutdownStopAt = null; FinishAt = Now().AddMilliseconds(700); }
        Dirty = true;
    }

    private partial void HidePanel()
    {
        if (!TestMode) Native.Hide();
        if (!HideTipShown)
        {
            Tray.Balloon(Lang.L("SyHost gizlendi"), Lang.L("Sunucu çalışmaya devam ediyor. Geri getirmek için Ctrl+Alt+G ya da saat yanındaki simge."));
            HideTipShown = true;
        }
    }

    // ---------- Çalışan başka sunucular (456 ve 892. satırlar) ----------
    private partial List<int> OtherServerPids()
    {
        var list = new List<int>();
        int own = -1;
        try { if (S != null && S.P != null && S.Running) own = S.P.Id; } catch { }
        Process[] procs;
        try { procs = Process.GetProcessesByName("java"); } catch { return list; }
        foreach (Process pr in procs)
        {
            using (pr)
            {
                int id;
                try { id = pr.Id; } catch { continue; }
                if (id == own) continue;
                string cl = ProcessQuery.CommandLine(id);
                if (cl != null && cl.Contains("nogui", StringComparison.OrdinalIgnoreCase)) list.Add(id);
            }
        }
        return list;
    }
}
