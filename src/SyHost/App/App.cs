// =====================================================================
//  SyHost - açılış, ana döngü ve test modu
//  legacy/src/SyHost.ps1: üst kısım (ayarlar, 51-110) ve "Başlangıç" (1769-1904)
// =====================================================================
using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace SyHost;

sealed partial class App
{
    public App(string root, bool testMode = false)
    {
        TestMode = testMode;
        AppRoot = Path.GetFullPath(root);
        Data = Path.Combine(AppRoot, "Data");
        CfgFile = Path.Combine(Data, "ayarlar.json");
        ServersFile = Path.Combine(Data, "sunucular.json");
        WinFile = Path.Combine(Data, "pencere.json");
        ErrorLog = Path.Combine(Data, "hata.log");
        PlayitSecret = Path.Combine(Data, "playit.toml");
    }

    /// <summary>Exe'nin içindeki bir dosyayı oku (Assets klasöründen gömülü).</summary>
    public static byte[] Asset(string name)
    {
        using var s = typeof(App).Assembly.GetManifestResourceStream(name);
        if (s == null) return null;
        using var ms = new MemoryStream();
        s.CopyTo(ms);
        return ms.ToArray();
    }

    // ---------- Ayarlar (SyHost.ps1 51-110) ----------
    public void LoadConfig()
    {
        if (SetupMode)
        {
            // Henüz kurulmadı: diske hiçbir şey yazma, Windows'un dilini öner
            Cfg = Json.ParseSettings(Encoding.UTF8.GetString(Asset("default-settings.json")));
            Cfg.dil = Portable.UiLanguage();
        }
        else
        {
            Directory.CreateDirectory(Data);
            if (!File.Exists(CfgFile)) Json.WriteText(CfgFile, Encoding.UTF8.GetString(Asset("default-settings.json")));
            try { Cfg = Json.ReadSettings(CfgFile); }
            catch
            {
                // Bozuk ayar dosyası: kenara al, varsayılanla devam et (veri kaybolmasın)
                try { File.Copy(CfgFile, CfgFile + ".bozuk", true); } catch { }
                Cfg = Json.ParseSettings(Encoding.UTF8.GetString(Asset("default-settings.json")));
            }
        }
        Cfg.arkadasAdresi ??= ""; Cfg.sesAdresi ??= "";
        Cfg.sunucuKokKlasoru = ResolveRootDir(Cfg.sunucuKokKlasoru);
        // Dil: en (varsayılan), tr, ja
        Lang.Code = Lang.Has(Cfg.dil ?? "") ? Cfg.dil : "en";
        if (Cfg.paketler == null || !Cfg.paketler.ContainsKey("dusuk") || !Cfg.paketler.ContainsKey("normal") || !Cfg.paketler.ContainsKey("yuksek"))
        {
            var def = Json.ParseSettings(Encoding.UTF8.GetString(Asset("default-settings.json")));
            Cfg.paketler ??= new Dictionary<string, Pack>(StringComparer.OrdinalIgnoreCase);
            foreach (var kv in def.paketler) if (!Cfg.paketler.ContainsKey(kv.Key)) Cfg.paketler[kv.Key] = kv.Value;
        }
        Cfg.paketler = new Dictionary<string, Pack>(Cfg.paketler, StringComparer.OrdinalIgnoreCase);
        var mem = Native.Memory();
        // İlk açılışta paketleri bu bilgisayarın RAM'ine ve çekirdek sayısına göre ayarla
        if (Cfg.paketlerAyarlandi == null)
        {
            int totGb = (int)Math.Floor(mem.Total / (1024.0 * 1024 * 1024));
            int thr = Environment.ProcessorCount;
            static int Clamp(double v, int lo, int hi) => Ps.Int(Math.Max(lo, Math.Min(hi, Math.Round(v))));
            var plan = new Dictionary<string, int[]>
            {
                ["dusuk"] = new[] { Clamp(totGb * 0.2, 3, 8), 2, Math.Max(2, Ps.Int(thr / 4.0)) },
                ["normal"] = new[] { Clamp(totGb * 0.33, 4, 12), 4, Math.Max(2, Ps.Int(thr / 2.0)) },
                ["yuksek"] = new[] { Clamp(totGb * 0.5, 5, 20), 6, thr },
            };
            foreach (string pk in PackKeys)
            {
                int mx = plan[pk][0];
                Cfg.paketler[pk].ramMax = mx;
                Cfg.paketler[pk].ramMin = Math.Max(2, mx - plan[pk][1]);
                Cfg.paketler[pk].cekirdek = plan[pk][2];
            }
            Cfg.paketlerAyarlandi = true;
            if (!SetupMode) SaveConfig();
        }
        Packs = Cfg.paketler;
        MaxPlayers = Cfg.maksOyuncu != 0 ? Cfg.maksOyuncu : 5;
        Threads = Environment.ProcessorCount;
        TotalRam = mem.Total;
        HasFriendAddr = !string.IsNullOrEmpty(Cfg.arkadasAdresi) && Cfg.playitKullan;
        if (!SetupMode && File.Exists(WinFile)) { try { Win = Json.ParseWin(Json.ReadText(WinFile)) ?? new WinState(); } catch { Win = new WinState(); } }
    }

    /// <summary>Açılışta: eski verileri taşı, taşınmış klasörün kısayollarını düzelt, klasör görünümünü uygula.</summary>
    void PortableStartup()
    {
        if (SetupMode) { NextAfterSplash = "firstrun"; return; }
        // 0.5.0'dan kalan veriler: bu Data henüz boşsa bir kez kopyala
        if (Migration.HasLegacyData() && Migration.DataIsFresh(Data))
        {
            string moved = Migration.MovedTo();
            bool here = moved != null && string.Equals(Path.GetFullPath(moved).TrimEnd('\\'), AppRoot.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
            if (moved == null || here)
            {
                try { FrMigrated = Migration.Copy(Data, AppRoot, Cfg.dil); LoadConfig(); } catch { }
            }
            else FrMovedTo = moved;
        }
        LoadServers();
        // Klasör taşındıysa eski yeri gösteren kısayolları buraya çevir
        try { if (Shortcuts.FixMoved(ExePath, Lang.L("SyHost - modlu Minecraft sunucu merkezi")) > 0) ShowHomeMsg(Lang.L("Kısayollar yeni yere güncellendi.")); } catch { }
        string root = AppRoot, lang = Lang.Code;
        var dirs = Servers.Select(s => s.klasor).ToList();
        Task.Run(() => FolderLook.Apply(root, lang, dirs));
        NextAfterSplash = (Cfg.kurulumTamam == false || FrMigrated != null || FrMovedTo != null) ? "firstrun" : "home";
    }

    /// <summary>sunucuKokKlasoru: boşsa SyHost klasöründeki Servers, göreliyse SyHost klasörüne göre.</summary>
    string ResolveRootDir(string v)
    {
        v = Environment.ExpandEnvironmentVariables(v ?? "").Trim();
        if (v.Length == 0) return Path.Combine(AppRoot, "Servers");
        if (!Path.IsPathRooted(v)) return Path.GetFullPath(Path.Combine(AppRoot, v));
        return v;
    }

    /// <summary>Ayarları kaydet. Sunucu kök klasörü SyHost klasörünün içindeyse göreli yazılır.</summary>
    public void SaveConfig()
    {
        string abs = Cfg.sunucuKokKlasoru;
        Cfg.sunucuKokKlasoru = ToStoredPath(abs);
        try { Json.WriteText(CfgFile, Json.WriteSettings(Cfg)); }
        finally { Cfg.sunucuKokKlasoru = abs; }
    }

    /// <summary>SyHost klasörünün içindeki yol göreli ("Servers\Ad"), dışındaki mutlak kalır.</summary>
    public string ToStoredPath(string abs)
    {
        if (string.IsNullOrEmpty(abs)) return abs;
        try
        {
            string full = Path.GetFullPath(abs).TrimEnd('\\');
            string root = AppRoot.TrimEnd('\\') + "\\";
            if (full.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return full.Substring(root.Length);
            if (string.Equals(full, AppRoot.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) return ".";
            return full;
        }
        catch { return abs; }
    }

    /// <summary>Dosyadaki yolu mutlak yola çevir (göreliyse SyHost klasörüne göre).</summary>
    public string FromStoredPath(string stored)
    {
        if (string.IsNullOrEmpty(stored)) return stored;
        string v = Environment.ExpandEnvironmentVariables(stored);
        try { return Path.IsPathRooted(v) ? v : Path.GetFullPath(Path.Combine(AppRoot, v)); } catch { return v; }
    }

    /// <summary>Dile bağlı tablolar (PowerShell'de açılışta L ile hesaplananlar).</summary>
    public void InitTables()
    {
        FriendAddr = HasFriendAddr ? Cfg.arkadasAdresi : Lang.L("henüz yok");
        PackColor = new(StringComparer.OrdinalIgnoreCase) { ["dusuk"] = Rgb(235, 235, 235), ["normal"] = Rgb(239, 55, 66), ["yuksek"] = Rgb(255, 30, 45) };
        PrioTr = new(StringComparer.OrdinalIgnoreCase) { ["Normal"] = Lang.L("Normal"), ["AboveNormal"] = Lang.L("Normal Üstü"), ["High"] = Lang.L("Yüksek"), ["BelowNormal"] = Lang.L("Düşük"), ["Idle"] = Lang.L("En Düşük") };
        Verbs = new[] { Lang.L("Dişliler hizalanıyor"), Lang.L("Çarklar yağlanıyor"), Lang.L("Pirinç parlatılıyor"), Lang.L("Redstone ısıtılıyor"), Lang.L("Chunk'lar örülüyor"),
            Lang.L("Creeper'lar sakinleştiriliyor"), Lang.L("Köylüler pazarlığa hazırlanıyor"), Lang.L("Elmaslar sayılıyor"), Lang.L("Su çarkı çevriliyor"),
            Lang.L("Biyomlar boyanıyor"), Lang.L("Ender incileri cilalanıyor"), Lang.L("Mekanik presler ayarlanıyor"), Lang.L("Trenler raya oturtuluyor"), Lang.L("Rüzgar değirmeni kuruluyor") };
        StatusLook = new(StringComparer.OrdinalIgnoreCase) { ["KAPALI"] = (c.red, Lang.L("KAPALI")), ["BASLIYOR"] = (c.yellow, Lang.L("AÇILIYOR")), ["ACIK"] = (c.green, Lang.L("AÇIK")), ["DURUYOR"] = (c.orange, Lang.L("KAPANIYOR")) };
        StageNames = new() { [0] = Lang.L("Java açılıyor"), [1] = Lang.L("Java açılıyor"), [2] = Lang.L("Modlar yükleniyor"), [3] = Lang.L("Sunucu ayarları yükleniyor"), [4] = Lang.L("Dünya hazırlanıyor") };
        Badge = new(StringComparer.OrdinalIgnoreCase)
        {
            ["info"] = (Lang.L("BİLGİ"), c.dim, c.soft), ["warn"] = (Lang.L("UYARI"), c.yellow, Rgb(253, 230, 138)), ["error"] = (Lang.L("HATA"), c.red, Rgb(254, 202, 202)),
            ["panel"] = ("SYHOST", c.brass, c.brass), ["ok"] = ("SYHOST", c.green, Rgb(187, 247, 208)), ["join"] = (Lang.L("GİRİŞ"), c.green, c.green),
            ["leave"] = (Lang.L("ÇIKIŞ"), c.orange, c.orange), ["chat"] = (Lang.L("SOHBET"), c.cyan, c.cyan), ["cmd"] = (Lang.L("KOMUT"), c.violet, c.violet),
        };
        Builtins = Lang.Code == "tr" ? BuiltinsTr : BuiltinsEn;
    }

    // ---------- Başlangıç ve ana döngü (SyHost.ps1 1769-1904) ----------
    public void Run()
    {
        Console.Title = Title;
        Console.OutputEncoding = new UTF8Encoding(false);
        Console.InputEncoding = new UTF8Encoding(false);
        try { Console.TreatControlCAsInput = true; } catch { }
        try { Process.GetCurrentProcess().PriorityClass = ProcessPriorityClass.High; } catch { }
        Native.DpiAware();
        LoadConfig();
        Native.SetFont(Fonts.Face, (short)(Cfg.yaziTipiBoyutu != 0 ? Cfg.yaziTipiBoyutu : 16));
        PortableStartup();
        InitTables();

        Native.PrepareConsole();
        Native.DisableCloseButton();
        Native.SetWindowIcon();
        CloseGuard.Install();
        Tray.Start(Title);
        Native.MakeOpaque();
        SetUiMode("buyuk", NoSave: true);
        SplashStart = NoSplash ? T() - SplashLen - 1 : T();
        StartPlayit();
        SysFree = Native.Memory().Avail;

        try
        {
            while (!Quit)
            {
                DateTime now = Now();

                if (Screen == "splash" && (T() - SplashStart) > SplashLen) AfterSplash();
                FrPoll();
                if (Screen == "outro" && (T() - OutroStart) > OutroLen) { Quit = true; break; }

                // Tepsi menüsü ve kısayollar
                while (Tray.Actions.TryDequeue(out string a))
                {
                    switch (a)
                    {
                        case "mini": ToggleUiMode(); break;
                        case "quit":
                            if (Screen == "server") BeginShutdown("quit");
                            else if (Screen == "wizard" && Wiz != null && Wiz.Step == "kurulum") Tray.Balloon(Lang.L("Kurulum sürüyor"), Lang.L("Kurulum bitince kapatabilirsin."));
                            else if (Screen != "outro") StartOutro();
                            break;
                        case "restart":
                            if (Screen == "server") { AddLog("panel", Lang.L("Yeniden başlatılıyor...")); StopServer("restart"); }
                            break;
                    }
                }

                // Sunucu çıktısı
                if (S != null) { int n = 0; while (n < 400 && S.Out.TryDequeue(out string line)) { AddServerLine(line); n++; } }

                // Sunucu kapandı mı?
                if (WasRunning && !(S != null && S.Running))
                {
                    while (S != null && S.Out.TryDequeue(out string line)) AddServerLine(line);
                    object code = "?"; try { code = S.P.ExitCode; } catch { }
                    Status = "KAPALI"; Players.Clear(); WasRunning = false; RamNow = 0; CpuNow = 0;
                    if (StopRequested) AddLog("ok", Lang.L("Sunucu durdu, dünya kaydedildi."));
                    else
                    {
                        AddLog("error", Lang.L("Sunucu beklenmedik şekilde kapandı (kod {0}).", code));
                        Tray.Balloon(Lang.L("{0} kapandı", Cur?.ad), Lang.L("Beklenmedik bir kapanma oldu."));
                        CrashTimes.Add(now);
                        while (CrashTimes.Count > 0 && (now - CrashTimes[0]).TotalMinutes > 10) CrashTimes.RemoveAt(0);
                        if (CrashTimes.Count >= 3)
                            AddLog("error", Lang.L("Sunucu son 10 dakikada {0} kez çöktü, otomatik yeniden başlatma durduruldu. F5 ile ayrıntılara bakabilirsin.", CrashTimes.Count));
                        else if (Cfg.cokerseYenidenBaslat && Mode != "closing" && Screen == "server")
                        {
                            AutoRestartAt = now.AddSeconds(10);
                            AddLog("panel", Lang.L("10 saniye içinde otomatik yeniden başlatılacak... (iptal: durdur)"));
                        }
                    }
                    string then = AfterStop; AfterStop = null; StopRequested = false;
                    if (then == "restart") StartServer(); else if (then == "close") FinishAt = now.AddMilliseconds(1200);
                }
                if (AutoRestartAt != null && now >= AutoRestartAt) { AutoRestartAt = null; if (Screen == "server" && Mode != "closing") StartServer(); }

                // Kapatma adımları
                if (ShutdownStopAt != null && now >= ShutdownStopAt) { ShutdownStopAt = null; StopServer("close"); }
                if (Mode == "closing" && StopSentAt != null && S != null && S.Running && (now - StopSentAt.Value).TotalSeconds > 60)
                {
                    AddLog("warn", Lang.L("Sunucu 60 sn içinde kapanmadı, zorla kapatılıyor.")); StopRequested = true; try { S.P.Kill(); } catch { }
                }
                if (FinishAt != null && now >= FinishAt)
                {
                    FinishAt = null;
                    if (AfterClose == "quit") StartOutro(); else GoHome();
                }
                if (Mode != "closing" && Status == "DURUYOR" && StopSentAt != null && (now - StopSentAt.Value).TotalSeconds > 120 && S != null && S.Running)
                {
                    AddLog("warn", Lang.L("Sunucu 2 dakikadır kapanmıyor. Zorla kapatmak için 'zorla' yaz.")); StopSentAt = null;
                }

                // Yedek ve kurulum
                CheckBackup();
                if (Screen == "server")
                {
                    double autoH = Cfg.otomatikYedekSaat;
                    if (autoH > 0 && Status == "ACIK" && BackupStage == null && (now - LastBackup).TotalHours >= autoH) { AddLog("panel", Lang.L("Otomatik yedek zamanı.")); StartBackup(); }
                }
                CheckInstall();

                // Klavye
                if (Native.Visible) { while (Console.KeyAvailable) HandleKey(Console.ReadKey(true)); }

                // İstatistikler
                if ((now - LastStat).TotalMilliseconds >= 1000)
                {
                    if (S != null && S.Running)
                    {
                        try
                        {
                            S.P.Refresh(); RamNow = S.P.WorkingSet64;
                            double cpuMs = S.P.TotalProcessorTime.TotalMilliseconds;
                            if (LastCpuMs > 0) CpuNow = Math.Min(100, Ps.Int((cpuMs - LastCpuMs) / (now - LastStat).TotalMilliseconds / Threads * 100));   // PowerShell: Int32 Min
                            LastCpuMs = cpuMs;
                        }
                        catch { }
                    }
                    SysFree = Native.Memory().Avail;
                    if ((now - LastSlow).TotalSeconds >= 10)
                    {
                        LastSlow = now;
                        Native.MakeOpaque();
                        if (Pl != null) { while (Pl.Out.TryDequeue(out _)) { } }
                        if (Cfg.playitKullan && !PlayitOn()) StartPlayit();
                        string tip = Screen == "server" ? Lang.L("SyHost · {0} · {1} · {2}/{3}", Cur?.ad, StatusLook[Status].Text, Players.Count, MaxPlayers) : Lang.L("SyHost · ana menü");
                        Tray.SetText(tip);
                    }
                    LastStat = now; Dirty = true;
                }

                // Çiz
                bool vis = Native.Visible;
                string size = Console.WindowWidth + "x" + Console.WindowHeight;
                if (size != LastSize) { LastSize = size; ResetFrame(); }
                if (vis && !WasVisible) ResetFrame();
                WasVisible = vis;
                bool anim = Animating();
                int interval = anim ? 60 : 40;
                if (vis && (Dirty || anim) && (now - LastRender).TotalMilliseconds >= interval) { Render(); Dirty = false; LastRender = now; }

                Thread.Sleep(20);
            }
        }
        catch (Exception ex)
        {
            string msg = ex.ToString();
            try { File.AppendAllText(ErrorLog, $"[{DateTime.Now}] {msg}{Environment.NewLine}", Json.Utf8NoBom); } catch { }
            Native.Show();
            Console.Write(E + "[0m" + E + "[2J" + E + "[H" + E + "[?25h");
            Console.ForegroundColor = ConsoleColor.Red; Console.WriteLine(Lang.L("SyHost bir hatayla karşılaştı:")); Console.ResetColor();
            Console.WriteLine(msg);
            if (S != null && S.Running) { Console.ForegroundColor = ConsoleColor.Yellow; Console.WriteLine(Lang.L("Sunucu güvenle durduruluyor...")); Console.ResetColor(); S.Send("stop"); try { S.P.WaitForExit(60000); } catch { } }
            Console.WriteLine(Lang.L("Ayrıntı: {0}", ErrorLog));
            Console.Write(Lang.L("Kapatmak için Enter") + ": ");
            try { Console.ReadLine(); } catch { }
        }
        finally
        {
            SaveWinState();
            if (S != null && S.Running) { S.Send("stop"); try { S.P.WaitForExit(60000); } catch { } }
            if (S != null && S.Running) { try { S.P.Kill(); } catch { } }
            StopPlayit();
            Tray.Close();
        }
    }

    // ---------- Test modu: tek bir kareyi dosyaya yaz ----------
    /// <summary>
    /// SyHost.exe --frame senaryo.json çıktı.txt --root klasör
    /// Senaryodaki durumu kurar, saati dondurur, bir kare çizer ve satırları dosyaya yazar.
    /// Aynı senaryo Terminal sürümünde de çalıştırılır; iki çıktı karakter karakter aynı olmalıdır.
    /// </summary>
    public static int RunFrameTest(string scenarioPath, string outPath, string root)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(scenarioPath, Encoding.UTF8), new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip });
        var sc = doc.RootElement;
        var app = new App(root, testMode: true);
        app.LoadConfig();
        app.LoadServers();
        app.InitTables();
        int w = sc.GetProperty("w").GetInt32(), h = sc.GetProperty("h").GetInt32();
        app.ApplyScenario(sc);
        string[] frame = app.BuildFrame(w, h, out bool showCursor, out int cursorCol);
        var sb = new StringBuilder();
        foreach (string line in frame) sb.Append(line).Append('\n');
        sb.Append("#cursor ").Append(showCursor ? "on " : "off ").Append(cursorCol).Append('\n');
        File.WriteAllText(outPath, sb.ToString(), Json.Utf8NoBom);
        return 0;
    }

    void ApplyScenario(JsonElement sc)
    {
        static bool Has(JsonElement e, string n, out JsonElement v) => e.TryGetProperty(n, out v) && v.ValueKind != JsonValueKind.Null;
        static DateTime Dt(JsonElement v) => DateTime.ParseExact(v.GetString(), "yyyy-MM-dd HH:mm:ss", Ps.Inv);
        TestT = sc.GetProperty("t").GetDouble();
        TestNow = Dt(sc.GetProperty("now"));
        if (Has(sc, "version", out var ver)) VersionText = ver.GetString();
        if (Has(sc, "edition", out var ed)) Edition = ed.GetString();
        var st = sc.TryGetProperty("state", out var s0) ? s0 : default;
        if (st.ValueKind != JsonValueKind.Object) return;

        if (Has(st, "screen", out var v)) Screen = v.GetString();
        if (Has(st, "splashStart", out v)) SplashStart = v.GetDouble();
        if (Has(st, "outroStart", out v)) OutroStart = v.GetDouble();
        // Rastgelelik kapalı: glitch ve yeni meteor yok, yalnızca senaryodakiler
        GlitchNext = 1e9; GlitchUntil = 0;
        if (Has(st, "glitch", out v))
        {
            GlitchUntil = v.GetProperty("until").GetDouble();
            GlitchNext = v.TryGetProperty("next", out var gn) ? gn.GetDouble() : 1e9;
            GlitchRows = new Dictionary<int, int>();
            foreach (var p in v.GetProperty("rows").EnumerateObject()) GlitchRows[int.Parse(p.Name, Ps.Inv)] = p.Value.GetInt32();
        }
        MeteorNextSpawn = Has(st, "meteorNextSpawn", out v) ? v.GetDouble() : 1e9;
        MeteorLastT = TestT;
        int w = sc.GetProperty("w").GetInt32(), h = sc.GetProperty("h").GetInt32();
        StarsSize = w + "," + h;
        Stars = new Dictionary<int, List<(int, double)>>();
        if (Has(st, "stars", out v))
        {
            foreach (var s in v.EnumerateArray())
            {
                int row = s[0].GetInt32();
                if (!Stars.ContainsKey(row)) Stars[row] = new List<(int, double)>();
                Stars[row].Add((s[1].GetInt32(), s[2].GetDouble()));
            }
        }
        Meteors = new List<Meteor>();
        if (Has(st, "meteors", out v))
        {
            foreach (var m in v.EnumerateArray())
                Meteors.Add(new Meteor { x = m.GetProperty("x").GetDouble(), y = m.GetProperty("y").GetDouble(), vx = m.GetProperty("vx").GetDouble(), vy = m.GetProperty("vy").GetDouble(), len = m.GetProperty("len").GetInt32(), age = m.GetProperty("age").GetDouble(), life = m.GetProperty("life").GetDouble() });
        }

        if (Has(st, "homeSel", out v)) HomeSel = v.GetInt32();
        if (Has(st, "homeMode", out v)) HomeMode = v.GetString();
        if (Has(st, "homeMsg", out v)) HomeMsg = v.GetString();
        if (Has(st, "homeMsgUntil", out v)) HomeMsgUntil = Dt(v);
        if (Has(st, "modCounts", out v)) foreach (var p in v.EnumerateObject()) ModCountCache[p.Name] = p.Value.GetInt32();
        if (Has(st, "worldSizes", out v)) foreach (var p in v.EnumerateObject()) WorldSizeCache[p.Name] = p.Value.GetString();
        if (Has(st, "sysFree", out v)) SysFree = v.GetDouble();
        if (Has(st, "totalRam", out v)) TotalRam = v.GetDouble();
        if (Has(st, "threads", out v)) Threads = v.GetInt32();
        if (Has(st, "javaFound", out v)) TestJavaFound = v.GetBoolean();
        TestPlayitOn = Has(st, "playitOn", out v) && v.GetBoolean();

        // Sunucu ekranı
        if (Has(st, "cur", out v)) Cur = Servers.Find(x => x.id == v.GetString());
        if (Has(st, "status", out v)) Status = v.GetString();
        if (Has(st, "mode", out v)) Mode = v.GetString();
        if (Has(st, "uiMode", out v)) UiMode = v.GetString();
        if (Has(st, "detail", out v)) Detail = v.GetBoolean();
        if (Has(st, "scroll", out v)) Scroll = v.GetInt32();
        if (Has(st, "running", out v)) S = new ServerProcess { FakeRunning = v.GetBoolean() };
        if (Has(st, "startTime", out v)) StartTime = Dt(v);
        if (Has(st, "players", out v)) foreach (var p in v.EnumerateArray()) Players.Add(p.GetString());
        if (Has(st, "ramNow", out v)) RamNow = v.GetDouble();
        if (Has(st, "cpuNow", out v)) CpuNow = v.GetDouble();
        if (Has(st, "loadedRamMax", out v)) LoadedRamMax = v.GetInt32();
        if (Has(st, "ramPending", out v)) RamPending = v.GetBoolean();
        if (Has(st, "activePack", out v)) ActivePack = v.GetString();
        if (Has(st, "packSel", out v)) PackSel = v.GetInt32();
        if (Has(st, "stage", out v)) Stage = v.GetInt32();
        if (Has(st, "stopPhase", out v)) StopPhase = v.GetInt32();
        if (Has(st, "expectedStart", out v)) ExpectedStart = v.GetInt32();
        if (Has(st, "modCount", out v)) ModCount = v.GetInt32();
        if (Has(st, "backupStage", out v)) BackupStage = v.GetString();
        if (Has(st, "autoRestartAt", out v)) AutoRestartAt = Dt(v);
        if (Has(st, "closingSince", out v)) ClosingSince = Dt(v);
        if (Has(st, "shutdownStopAt", out v)) ShutdownStopAt = Dt(v);
        if (Has(st, "finishAt", out v)) FinishAt = Dt(v);
        if (Has(st, "afterClose", out v)) AfterClose = v.GetString();
        if (Has(st, "inputText", out v)) InputText = v.GetString();
        if (Has(st, "winUstte", out v)) Win.ustte = v.GetBoolean();
        if (Has(st, "log", out v))
            foreach (var e in v.EnumerateArray())
                Log.Add(new LogEntry { T = e.GetProperty("T").GetString(), K = e.GetProperty("K").GetString(), M = e.GetProperty("M").GetString(), V = e.GetProperty("V").GetBoolean() });

        // Sihirbaz
        if (Has(st, "wizard", out var wz))
        {
            var i = wz.GetProperty("info");
            var info = new PackInfo
            {
                Path = i.GetProperty("Path").GetString(), Name = i.GetProperty("Name").GetString(), Version = i.GetProperty("Version").GetString(),
                Mc = i.GetProperty("Mc").GetString(), Loader = i.GetProperty("Loader").GetString(), LoaderVer = i.GetProperty("LoaderVer").GetString(),
                Java = i.GetProperty("Java").GetInt32(), Mods = i.GetProperty("Mods").GetInt32(), ClientOnly = i.GetProperty("ClientOnly").GetInt32(),
                SizeMb = i.GetProperty("SizeMb").GetDouble(),
            };
            foreach (var sv in i.GetProperty("Saves").EnumerateArray()) info.Saves.Add(sv.GetString());
            Wiz = new WizardState { Step = wz.GetProperty("step").GetString(), Info = info, Name = wz.GetProperty("name").GetString(), WorldSel = wz.GetProperty("worldSel").GetInt32() };
            if (Has(wz, "target", out v)) Wiz.Target = v.GetString();
            if (Has(wz, "startedAt", out v)) Wiz.StartedAt = Dt(v);
            if (Has(wz, "sync", out var sy))
            {
                var sync = new InstallSync();
                var names = InstallStepNames(info);
                int k = 0;
                foreach (var stv in sy.GetProperty("steps").EnumerateArray()) { sync.Steps.Add(new InstallStep { N = k < names.Count ? names[k] : "", S = stv.GetInt32() }); k++; }
                if (Has(sy, "pct", out v)) sync.Pct = v.GetInt32();
                if (Has(sy, "count", out v)) sync.Count = v.GetString();
                if (Has(sy, "detail", out v)) sync.Detail = v.GetString();
                if (Has(sy, "error", out v)) sync.Error = v.GetString();
                if (Has(sy, "failed", out v)) { var f = new List<string>(); foreach (var x in v.EnumerateArray()) f.Add(x.GetString()); sync.Failed = f; }
                Wiz.Sync = sync;
            }
        }
    }
}
