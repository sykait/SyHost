// =====================================================================
//  SyHost - ilk açılış ekranı (Setup.ps1'in yerini alır)
//  1. aşama (SyHost henüz kurulu değil, ör. İndirilenler'den açıldı):
//       Dil  ›  Konum   → seçilen klasöre kurulur ve oradan yeniden açılır
//  2. aşama (kurulu, ilk açılış):
//       Eski veriler  ›  Sistem  ›  Java  ›  Arkadaşlar  ›  Yazı tipi  ›  Kısayollar  ›  Hazır
//  Ayarlar ekranı tek bir adımı (ör. Arkadaşlar, Java) yeniden çalıştırmak için de bunu kullanır.
//  Görünüm ana menü ve sihirbazla aynı: logo + bilgi sütunu, adım çubuğu, parlayan çizgi,
//  nabız gibi atan seçim vurgusu, boş satırlarda kayan yıldızlar.
// =====================================================================
using System.Diagnostics;

namespace SyHost;

sealed partial class App
{
    // ---------- Kurulum durumu ----------
    /// <summary>SyHost bu klasörde henüz kurulu değil (1. aşama: dil ve konum).</summary>
    public bool SetupMode;
    /// <summary>Program kapanınca açılacak SyHost.exe (kurulum ya da güncellemeden sonra).</summary>
    public string LaunchAfterExit;
    /// <summary>Kaldır: SyHost kapanınca klasörü sil.</summary>
    public bool DeleteRootAfterExit;
    /// <summary>Açılış animasyonundan sonra gidilecek ekran.</summary>
    public string NextAfterSplash = "home";
    /// <summary>Kurulumdan hemen sonra açılınca animasyon tekrar oynamasın.</summary>
    public bool NoSplash;
    /// <summary>Açılışta eski veriler kopyalandıysa sonucu; başka yere taşınmışsa o yer.</summary>
    Migration.Result FrMigrated;
    string FrMovedTo;

    FirstRunState Fr;
    /// <summary>Açılışta oluşan ana menü mesajı (Türkçe anahtar): ana menü ilk görününce gösterilir.</summary>
    string PendingHomeMsg;
    void ShowPendingHomeMsg() { if (PendingHomeMsg != null) { ShowHomeMsg(Lang.L(PendingHomeMsg)); PendingHomeMsg = null; } }

    // ---------- Test modunda sabitlenebilen sistem bilgileri (iki sürümün aynı çizdiğini ölçmek için) ----------
    public Dictionary<int, bool> TestJava;
    public bool? TestJavaOwn, TestFontOk, TestPlayitReady, TestDryRun;
    public Dictionary<string, Shortcuts.State> TestShortcut;
    public int? TestOsBuild;
    public string TestDefaultRoot, TestLegacyDir;

    bool FontOk() => TestFontOk ?? Fonts.IsAvailable();
    int OsBuild => TestOsBuild ?? Environment.OSVersion.Version.Build;
    string DefaultRootShown => TestDefaultRoot ?? Portable.DefaultRoot();
    string LegacyDirShown => TestLegacyDir ?? Migration.LegacyDir();
    bool DryRunShown => TestDryRun ?? Uninstall.DryRun;
    /// <summary>Kısayol durumu: 0 Masaüstü, 1 Başlat menüsü.</summary>
    Shortcuts.State ShortcutState(int i)
    {
        if (TestShortcut != null) return TestShortcut.TryGetValue(i == 0 ? "desktop" : "start", out var s) ? s : Shortcuts.State.Missing;
        return Shortcuts.StateOf(Shortcuts.Locations()[i], ExePath);
    }

    sealed class FirstRunState
    {
        public List<string> Steps = new();
        public int Index;
        public int Sel;
        public string ReturnTo;            // null: ilk açılış; "settings": Ayarlar'dan açılan tek adım
        public string Target;              // kurulum yeri
        public string OtherInstall;        // bilgisayardaki başka bir SyHost
        public string Note, NoteCol;       // adımın altındaki kısa not
        public bool Confirm;               // OneDrive uyarısından sonra ikinci Enter bekleniyor
        public Task Job;
        public volatile bool JobDone;
        public volatile string JobText = "";
        public volatile string JobError;
        public volatile bool Cancel;        // Esc: çalışan playit komutu kapatıldı, sıradakiler başlamasın
        public bool Desk = true, Start = true;
        public string Phase = "";           // arkadaş adımının alt aşaması: soru, indir, bagla, adres, hazir
        public string Code;                 // playit eşleştirme kodu
        public int Field;                   // 0: Minecraft adresi, 1: sesli sohbet adresi
        public string McAddr = "", VoiceAddr = "";
    }

    static readonly Dictionary<string, (string Label, string Title)> FrStepNames = new()
    {
        ["dil"] = ("Dil", "DİL"),
        ["konum"] = ("Konum", "KURULUM YERİ"),
        ["tasima"] = ("Eski veriler", "ESKİ VERİLER"),
        ["sistem"] = ("Sistem", "SİSTEM"),
        ["java"] = ("Java", "JAVA"),
        ["arkadas"] = ("Arkadaşlar", "ARKADAŞ BAĞLANTISI"),
        ["yazi"] = ("Yazı tipi", "YAZI TİPİ"),
        ["kisayol"] = ("Kısayollar", "KISAYOLLAR"),
        ["bitti"] = ("Hazır", "HAZIR"),
    };

    /// <summary>Açılış animasyonu bitince: kurulum gerekiyorsa ilk açılış, yoksa ana menü.</summary>
    void AfterSplash()
    {
        Screen = NextAfterSplash;
        if (Screen == "home") ShowPendingHomeMsg();
        if (Screen == "firstrun" && Fr == null) StartFirstRun(null);
        ResetFrame();
    }

    /// <summary>İlk açılışı başlat. only: yalnızca bu adım (Ayarlar'dan), null: tam akış.</summary>
    void StartFirstRun(string only)
    {
        Fr = new FirstRunState { ReturnTo = only == null ? null : "settings" };
        if (only != null) Fr.Steps.Add(only);
        else if (SetupMode)
        {
            Fr.Steps.Add("dil");
            string exe = Environment.ProcessPath;
            Fr.OtherInstall = Shortcuts.FindOtherInstall(exe);
            bool ownFolder = Portable.IsOwnEmptyFolder(AppRoot, exe) && !Portable.IsInOneDrive(AppRoot) && Portable.CanWrite(AppRoot);
            Fr.Target = ownFolder ? AppRoot : Portable.DefaultRoot();
            if (!ownFolder || Fr.OtherInstall != null) Fr.Steps.Add("konum");
        }
        else
        {
            if (FrMigrated != null || FrMovedTo != null) Fr.Steps.Add("tasima");
            Fr.Steps.AddRange(new[] { "sistem", "java", "arkadas", "yazi", "kisayol", "bitti" });
        }
        FrEnterStep();
        Screen = "firstrun";
    }

    string FrStep => Fr.Steps[Fr.Index];

    /// <summary>Adıma girerken başlangıç seçimi ve notu hazırla.</summary>
    void FrEnterStep()
    {
        Fr.Sel = 0; Fr.Note = null; Fr.Confirm = false;
        switch (FrStep)
        {
            case "dil":
                Fr.Sel = Math.Max(0, Array.FindIndex(Lang.Languages, l => l.Code == Lang.Code));
                break;
            case "konum":
                FrCheckTarget();
                break;
            case "arkadas":
                Fr.Phase = "soru";
                Fr.Sel = PlayitReady() ? 0 : 0;
                break;
            case "kisayol":
                Fr.Desk = Cfg.kisayolMasaustu ?? true; Fr.Start = Cfg.kisayolBaslat ?? true;
                if (Shortcuts.StateOf(Shortcuts.DesktopPath, ExePath) == Shortcuts.State.OtherLive)
                { Fr.Note = Lang.L("Masaüstündeki SyHost kısayolu başka bir SyHost'u açıyor; yenisiyle değiştirilecek."); Fr.NoteCol = c.yellow; }
                break;
        }
        Dirty = true;
    }

    void FrNext()
    {
        if (Fr.Index < Fr.Steps.Count - 1) { Fr.Index++; FrEnterStep(); return; }
        // Akış bitti
        if (Fr.ReturnTo != null) { Fr = null; Screen = "settings"; ResetFrame(); return; }
        // 1. aşama konum adımı olmadan bitti (exe kendi boş klasöründe): SyHost buraya kurulur ve buradan yeniden açılır
        if (SetupMode) { FrInstall("target"); return; }
        Cfg.kurulumTamam = true;
        SaveConfig();
        Fr = null; Screen = "home"; ShowPendingHomeMsg(); ResetFrame();
    }

    void FrBack()
    {
        if (Fr.ReturnTo != null) { Fr = null; Screen = "settings"; ResetFrame(); return; }
        if (Fr.Index > 0) { Fr.Index--; FrEnterStep(); }
    }

    public static string ExePath => Environment.ProcessPath;

    // ---------- Konum ----------
    /// <summary>Seçili kurulum yerini denetle: yazılabilir mi, OneDrive mı, orada SyHost var mı.</summary>
    void FrCheckTarget()
    {
        Fr.Note = null; Fr.Confirm = false;
        if (Fr.Sel == 0 && Fr.OtherInstall != null) { Fr.Note = FrUpdateNote(Fr.OtherInstall); return; }
        string t = Fr.Target;
        if (Portable.IsInstalled(t)) Fr.Note = FrUpdateNote(t);   // oradaki daha yeniyse yalnızca açılacağını söyler
        else if (Portable.IsInOneDrive(t)) { Fr.Note = Lang.L("Bu klasör OneDrive ile eşitleniyor. Sunucu dosyaları büyük ve sürekli değişir; OneDrive dışında bir yer önerilir."); Fr.NoteCol = c.yellow; }
    }

    string FrUpdateNote(string root)
    {
        string newer = FrNewerVersion(Path.Combine(root, Portable.ExeName));
        if (newer != null) { Fr.NoteCol = c.yellow; return Lang.L("Oradaki SyHost daha yeni ({0}); yalnızca açılacak.", newer); }
        Fr.NoteCol = c.green;
        return Lang.L("Burada zaten SyHost var; güncellenip açılacak.");
    }

    /// <summary>Hedefteki SyHost.exe bizden yeniyse sürümünü döner.</summary>
    static string FrNewerVersion(string exe)
    {
        try
        {
            var fv = FileVersionInfo.GetVersionInfo(exe);
            if (System.Version.TryParse(fv.FileVersion, out var theirs) && System.Version.TryParse(App.Version, out var ours) && theirs > new System.Version(ours.Major, ours.Minor, Math.Max(0, ours.Build), 0))
                return $"{theirs.Major}.{theirs.Minor}.{theirs.Build}";
        }
        catch { }
        return null;
    }

    List<(string Label, string Value)> FrLocationOptions()
    {
        var o = new List<(string, string)>();
        if (Fr.OtherInstall != null) o.Add((Lang.L("Bilgisayardaki SyHost'u güncelle: {0}", Fr.OtherInstall), "update"));
        o.Add((Fr.Target, "target"));
        o.Add((Lang.L("Başka bir klasör seç..."), "pick"));
        return o;
    }

    /// <summary>Konumu onayla: kur ya da güncelle, sonra yeni yerden aç.</summary>
    void FrInstall(string kind)
    {
        string exe = ExePath;
        try
        {
            if (kind == "update")
            {
                string target = Path.Combine(Fr.OtherInstall, Portable.ExeName);
                if (FrNewerVersion(target) == null) Portable.CopyExe(exe, target);
                LaunchAfterExit = target;
            }
            else
            {
                string root = Fr.Target;
                // Orada daha yeni bir SyHost varsa eskisiyle ezilmez: yalnızca o açılır
                string there = Path.Combine(root, Portable.ExeName);
                if (Portable.IsInstalled(root) && FrNewerVersion(there) != null) { LaunchAfterExit = there; Quit = true; Dirty = true; return; }
                if (!Portable.CanWrite(root)) { Fr.Note = Lang.L("Bu klasöre yazılamıyor. Başka bir yer seç."); Fr.NoteCol = c.red; return; }
                Portable.InstallTo(root, exe, Lang.Code);
                FolderLook.Apply(root, Lang.Code, Array.Empty<string>());
                LaunchAfterExit = Path.Combine(root, Portable.ExeName);
            }
            Quit = true;
        }
        catch (IOException)
        {
            Fr.Note = Lang.L("SyHost orada açık. Önce onu kapat, sonra tekrar dene."); Fr.NoteCol = c.red;
        }
        catch (Exception e)
        {
            Fr.Note = e.Message; Fr.NoteCol = c.red;
        }
        Dirty = true;
    }

    // ---------- Arka plan işleri (indirme vb.) ----------
    void FrRun(Action work)
    {
        Fr.JobDone = false; Fr.JobError = null; Fr.JobText = ""; Fr.Cancel = false;
        Fr.Job = Task.Run(() =>
        {
            try { work(); }
            catch (Exception e) { Fr.JobError = e.Message; }
            finally { Fr.JobDone = true; }
        });
    }

    bool FrBusy => Fr != null && Fr.Job != null && !Fr.JobDone;

    /// <summary>Her karede: biten işin sonucunu uygula.</summary>
    void FrPoll()
    {
        if (Fr == null || Fr.Job == null || !Fr.JobDone) return;
        Fr.Job = null;
        Dirty = true;
        switch (FrStep)
        {
            case "java":
                if (Fr.JobError != null) { Fr.Note = Lang.L("Java 21 indirilemedi: {0}", Fr.JobError); Fr.NoteCol = c.red; }
                break;
            case "arkadas":
                PlayitJobDone();
                break;
        }
    }

    // ---------- Tuşlar ----------
    private partial void HandleFirstRunKey(ConsoleKeyInfo k, bool ctrl)
    {
        if (Fr == null) { Screen = "home"; ResetFrame(); return; }
        if (FrBusy) { if (k.Key == ConsoleKey.Escape && FrStep == "arkadas") PlayitCancel(); return; }
        // F10: SyHost'tan çık (kurulum yarıda kalırsa bir sonraki açılışta kaldığı yerden devam eder)
        if (k.Key == ConsoleKey.F10 && Fr.ReturnTo == null) { if (Allow("F10")) StartOutro(); return; }
        switch (FrStep)
        {
            case "dil":
                if (k.Key == ConsoleKey.UpArrow || k.Key == ConsoleKey.DownArrow)
                {
                    int n = Lang.Languages.Length;
                    Fr.Sel = (Fr.Sel + (k.Key == ConsoleKey.UpArrow ? n - 1 : 1)) % n;
                    Lang.Code = Lang.Languages[Fr.Sel].Code;   // seçim anında bütün ekran o dile geçer
                    InitTables();
                }
                else if (k.Key == ConsoleKey.Enter)
                {
                    Cfg.dil = Lang.Code;
                    if (!SetupMode) SaveConfig();
                    FrNext();
                }
                return;

            case "konum":
            {
                var opts = FrLocationOptions();
                if (k.Key == ConsoleKey.UpArrow) { Fr.Sel = (Fr.Sel + opts.Count - 1) % opts.Count; FrCheckTarget(); }
                else if (k.Key == ConsoleKey.DownArrow) { Fr.Sel = (Fr.Sel + 1) % opts.Count; FrCheckTarget(); }
                else if (k.Key == ConsoleKey.Escape) FrBack();
                else if (k.Key == ConsoleKey.Enter)
                {
                    string kind = opts[Fr.Sel].Value;
                    if (kind == "pick")
                    {
                        string start = Directory.Exists(Fr.Target) ? Fr.Target : Path.GetDirectoryName(Fr.Target);
                        string picked = TestMode ? null : Native.PickFolder(Lang.L("SyHost'un kurulacağı klasörü seç"), start);   // test modunda pencere açılmaz
                        ResetFrame();
                        if (!string.IsNullOrEmpty(picked))
                        {
                            // Dolu bir klasörü kirletmemek için içine "SyHost" klasörü açılır
                            bool empty = !Directory.EnumerateFileSystemEntries(picked).Any();
                            Fr.Target = empty || Path.GetFileName(picked.TrimEnd('\\')).Equals("SyHost", StringComparison.OrdinalIgnoreCase) || Portable.IsInstalled(picked)
                                ? picked : Path.Combine(picked, "SyHost");
                            Fr.Sel = Fr.OtherInstall != null ? 1 : 0;
                            FrCheckTarget();
                        }
                        return;
                    }
                    if (kind == "target" && Portable.IsInOneDrive(Fr.Target) && !Fr.Confirm) { Fr.Confirm = true; Fr.Note = Lang.L("Yine de buraya kurmak için tekrar Enter'a bas."); Fr.NoteCol = c.yellow; return; }
                    FrInstall(kind);
                }
                return;
            }

            case "tasima":
                if (FrMovedTo != null && FrMigrated == null)
                {
                    if (k.Key == ConsoleKey.UpArrow || k.Key == ConsoleKey.DownArrow) Fr.Sel = 1 - Fr.Sel;
                    else if (k.Key == ConsoleKey.Enter)
                    {
                        if (Fr.Sel == 0) FrDoMigrate();
                        else if (!File.Exists(ServersFile)) Json.WriteText(ServersFile, "[]");   // kararı hatırla: bir daha sorma
                        FrMovedTo = null;
                        FrNext();
                    }
                    return;
                }
                if (k.Key == ConsoleKey.Enter) FrNext();
                return;

            case "sistem":
                if (k.Key == ConsoleKey.Enter) FrNext();
                else if (k.Key == ConsoleKey.Escape) FrBack();
                return;

            case "java":
            {
                bool have = FindJava(21) != null;
                if (have) { if (k.Key == ConsoleKey.Enter) FrNext(); else if (k.Key == ConsoleKey.Escape) FrBack(); return; }
                if (k.Key == ConsoleKey.UpArrow || k.Key == ConsoleKey.DownArrow) Fr.Sel = 1 - Fr.Sel;
                else if (k.Key == ConsoleKey.Escape) FrBack();
                else if (k.Key == ConsoleKey.Enter)
                {
                    if (Fr.Sel == 1) { FrNext(); return; }
                    Fr.Note = null;
                    // Başlık zaten "Java 21 indiriliyor..." der; altta yalnızca ilerleme (dosya adı ve MB) görünsün
                    string head = Lang.L("Java {0} indiriliyor...", 21);
                    FrRun(() => Java.Download(21, Data, t => { if (t != head) { Fr.JobText = t; Dirty = true; } }));
                }
                return;
            }

            case "arkadas":
                PlayitKey(k);
                return;

            case "yazi":
                if (k.Key == ConsoleKey.Escape) { FrBack(); return; }
                if (k.Key != ConsoleKey.Enter) return;
                // Kurulamadıysa (Confirm) Enter devam eder. Test modunda gerçek yazı tipine dokunulmaz: kurulamamış sayılır.
                if (!Fr.Confirm && !FontOk())
                {
                    if (!TestMode && Fonts.InstallPerUser())
                    {
                        Cfg.yaziTipiKuruldu = true; SaveConfig();
                        Native.SetFont(Fonts.Face, (short)(Cfg.yaziTipiBoyutu != 0 ? Cfg.yaziTipiBoyutu : 16));
                        ResetFrame();
                    }
                    else { Fr.Note = Lang.L("Yazı tipi kurulamadı. SyHost yine çalışır, bazı semboller farklı görünebilir."); Fr.NoteCol = c.yellow; Fr.Confirm = true; return; }
                }
                FrNext();
                return;

            case "kisayol":
                if (k.Key == ConsoleKey.UpArrow || k.Key == ConsoleKey.DownArrow) Fr.Sel = 1 - Fr.Sel;
                else if (k.Key == ConsoleKey.Spacebar) { if (Fr.Sel == 0) Fr.Desk = !Fr.Desk; else Fr.Start = !Fr.Start; }
                else if (k.Key == ConsoleKey.Escape) FrBack();
                else if (k.Key == ConsoleKey.Enter)
                {
                    ApplyShortcuts(Fr.Desk, Fr.Start);
                    FrNext();
                }
                return;

            case "bitti":
                if (k.Key == ConsoleKey.Enter) FrNext();
                return;
        }
    }

    /// <summary>Kısayolları istenen hâle getir: açıksa yaz (başka bir SyHost'unkini de değiştirir), kapalıysa bizimkini sil.</summary>
    /// <summary>Kısayollar yazılabilir mi: gerçek çalışmada evet; test modunda yalnızca SYHOST_SHORTCUT_DIR bir test klasörünü gösteriyorsa.</summary>
    bool ShortcutsWritable => !TestMode || !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("SYHOST_SHORTCUT_DIR"));

    void ApplyShortcuts(bool desk, bool start)
    {
        Cfg.kisayolMasaustu = desk; Cfg.kisayolBaslat = start; SaveConfig();
        if (!ShortcutsWritable) return;
        string desc = Lang.L("SyHost - modlu Minecraft sunucu merkezi");
        var locs = Shortcuts.Locations();
        bool[] want = { desk, start };
        for (int i = 0; i < locs.Length; i++)
        {
            try
            {
                if (want[i]) Shortcuts.Write(locs[i], ExePath, desc);
                else if (Shortcuts.StateOf(locs[i], ExePath) == Shortcuts.State.Ours) File.Delete(locs[i]);
            }
            catch { }
        }
    }

    /// <summary>Eski verileri şimdi kopyala (kullanıcı "buraya da kopyala" dediyse).</summary>
    void FrDoMigrate()
    {
        try
        {
            FrMigrated = Migration.Copy(Data, AppRoot, Lang.Code);
            LoadConfig(); LoadServers(); InitTables();
        }
        catch { }
    }

    // ---------- Çizim ----------
    /// <summary>Ana menüdeki seçili satır vurgusu (nabız gibi atan koyu kırmızı zemin).</summary>
    string SelLine(string line, int W)
    {
        double pulse = (Math.Sin(T() * 4) + 1) / 2;
        string hlBg = $"{E}[48;2;{Ps.Int(45 + 35 * pulse)};{Ps.Int(14 + 6 * pulse)};{Ps.Int(20 + 8 * pulse)}m";
        int vl = VLen(line);
        return hlBg + line.Replace(R, R + hlBg) + Ps.Rep(" ", Math.Max(0, W - 1 - vl)) + R;
    }

    /// <summary>Logo ve sağında bilgi sütunu (ana menüdeki gibi).</summary>
    List<string> SetupHeader(int W, string[] info)
    {
        var rows = new List<string> { "" };
        var logo = RenderLogo(1.0, LogoShine());
        for (int i = 0; i < 6; i++) rows.Add("    " + logo[i] + (W >= LogoW + 52 ? "        " + info[i] : ""));
        rows.Add("");
        return rows;
    }

    string VersionLine() => c.dim + "v" + VersionText + "  ·  " + Edition + "  ·  sykait" + R;

    /// <summary>Arayüz dilinin kurallarıyla büyük harf (Türkçede i → İ; İngilizce ve Japoncada i → I).</summary>
    static string Up(string s) => (s ?? "").ToUpper(System.Globalization.CultureInfo.GetCultureInfo(Lang.Code == "tr" ? "tr-TR" : "en-US"));

    string Check(string text) => "  " + c.green + Bo + "✓" + R + "  " + c.text + text + R;
    string Warn(string text) => "  " + c.yellow + Bo + "!" + R + "  " + c.soft + text + R;

    private partial List<string> RenderFirstRun(int W, int H)
    {
        if (Fr == null) StartFirstRun(null);
        string step = FrStep;
        var info = new[]
        {
            Bo + c.brass + (SetupMode && Fr.Index == 0 ? Lang.L("HOŞ GELDİN") : Lang.L("KURULUM")) + R,
            VersionLine(),
            c.dark + new string('─', 38) + R,
            c.soft + Lang.L("Adım {0}/{1}", Fr.Index + 1, Fr.Steps.Count) + c.dark + "  ·  " + R + c.text + Lang.L(FrStepNames[step].Label) + R,
            c.dim + Lang.L("Birkaç adımda her şey hazır.") + R,
            "",
        };
        var rows = SetupHeader(W, info);

        // Adım çubuğu (sihirbazdaki gibi)
        if (Fr.Steps.Count > 1)
        {
            string bar = "  ";
            for (int i = 0; i < Fr.Steps.Count; i++)
            {
                string col = i < Fr.Index ? c.green : i == Fr.Index ? c.brass + Bo : c.dark;
                bar += col + (i + 1) + " " + Lang.L(FrStepNames[Fr.Steps[i]].Label) + R + c.dark + (i < Fr.Steps.Count - 1 ? "  ›  " : "") + R;
            }
            rows.Add(bar);
            rows.Add("");
        }
        rows.Add(Rule(Lang.L(FrStepNames[step].Title), W));
        rows.Add("");

        string keys = "";
        switch (step)
        {
            case "dil":
                for (int i = 0; i < Lang.Languages.Length; i++)
                {
                    bool s = i == Fr.Sel;
                    string line = "   " + (s ? c.brass + Bo + "❯ " + c.text : "  " + c.soft) + Lang.Languages[i].Name + R;
                    rows.Add(s ? SelLine(line, W) : line);
                }
                rows.Add("");
                rows.Add("  " + c.dim + Lang.L("Dil daha sonra Ayarlar'dan değiştirilebilir.") + R);
                // Kurulum (konum adımı olmadan) başarısız olduysa nedeni
                if (Fr.Note != null) { rows.Add(""); foreach (string l in WordWrap(Fr.Note, W - 8)) rows.Add("  " + Fr.NoteCol + l + R); }
                keys = Key("↑↓", Lang.L("seç")) + Key("Enter", Lang.L("devam"));
                break;

            case "konum":
            {
                rows.Add("  " + c.soft + Lang.L("SyHost nereye kurulsun? Ayarların ve sunucuların bu klasörde durur.") + R);
                rows.Add("");
                var opts = FrLocationOptions();
                for (int i = 0; i < opts.Count; i++)
                {
                    bool s = i == Fr.Sel;
                    string label = opts[i].Label;
                    string extra = opts[i].Value == "target" && Fr.Target.Equals(DefaultRootShown, StringComparison.OrdinalIgnoreCase) ? c.green + "   " + Lang.L("önerilen") + R : "";
                    string line = "   " + (s ? c.brass + Bo + "❯ " + c.text : "  " + c.soft) + label + R + extra;
                    rows.Add(s ? SelLine(line, W) : line);
                }
                rows.Add("");
                if (Fr.Note != null) foreach (string l in WordWrap(Fr.Note, W - 8)) rows.Add("  " + Fr.NoteCol + l + R);
                keys = Key("↑↓", Lang.L("seç")) + Key("Enter", Lang.L("kur")) + (Fr.Index > 0 ? Key("Esc", Lang.L("geri")) : "");
                break;
            }

            case "tasima":
                if (FrMigrated != null)
                {
                    rows.Add(Check(Lang.L("Eski ayarların taşındı")));
                    rows.Add("");
                    rows.Add("     " + c.soft + Lang.L("{0} sunucu ve ayarların bu klasöre kopyalandı.", FrMigrated.Servers) + R);
                    if (FrMigrated.Playit) rows.Add("     " + c.soft + Lang.L("playit bağlantın da taşındı.") + R);
                    rows.Add("     " + c.dim + Lang.L("Eski klasör silinmedi: {0}", LegacyDirShown) + R);
                    keys = Key("Enter", Lang.L("devam"));
                }
                else
                {
                    rows.Add(Warn(Lang.L("Eski verilerin daha önce şuraya taşınmış: {0}", FrMovedTo)));
                    rows.Add("     " + c.dim + Lang.L("İki SyHost aynı playit bağlantısını kullanırsa birbirini bozar.") + R);
                    rows.Add("");
                    string[] o = { Lang.L("Buraya da kopyala"), Lang.L("Kopyalama, temiz başla") };
                    for (int i = 0; i < 2; i++)
                    {
                        bool s = i == Fr.Sel;
                        string line = "   " + (s ? c.brass + Bo + "❯ " + c.text : "  " + c.soft) + o[i] + R;
                        rows.Add(s ? SelLine(line, W) : line);
                    }
                    keys = Key("↑↓", Lang.L("seç")) + Key("Enter", Lang.L("devam"));
                }
                break;

            case "sistem":
            {
                var os = Environment.OSVersion.Version; int build = OsBuild;
                if (os.Major < 10) rows.Add("  " + c.red + Bo + "x" + R + "  " + c.red + Lang.L("SyHost Windows 10 veya 11 ister.") + R);
                else rows.Add(Check("Windows " + (build >= 22000 ? "11" : "10") + " (" + build + ")"));
                int ramGb = Ps.Int(Math.Round(TotalRam / 1073741824.0));
                rows.Add(Check(Lang.L("{0} GB RAM, {1} çekirdek", ramGb, Threads)));
                if (ramGb < 8) rows.Add(Warn(Lang.L("Modlu sunucular için en az 8 GB RAM önerilir.")));
                rows.Add(Check(Lang.L("SyHost klasörü: {0}", AppRoot)));
                keys = Key("Enter", Lang.L("devam")) + Key("Esc", Lang.L("geri"));
                break;
            }

            case "java":
            {
                string j = FindJava(21);
                if (FrBusy)
                {
                    rows.Add("  " + c.brass + Spin() + R + "  " + Shimmer(Lang.L("Java {0} indiriliyor...", 21), new[] { 229, 231, 235 }, new[] { 255, 70, 80 }));
                    if (!string.IsNullOrEmpty(Fr.JobText)) rows.Add("     " + c.dim + Fr.JobText + R);
                }
                else if (j != null)
                {
                    bool own = TestJavaOwn ?? Portable.IsInside(j, AppRoot);
                    rows.Add(Check(Lang.L("Java 21 hazır") + c.dim + (own ? Lang.L(" (SyHost klasöründe)") : Lang.L(" (bilgisayarında kurulu)"))));
                    rows.Add("");
                    rows.Add("  " + c.dim + Lang.L("Eski paketlerin istediği Java 8 ve 17 gerekince kendiliğinden iner.") + R);
                    keys = Key("Enter", Lang.L("devam")) + Key("Esc", Lang.L("geri"));
                }
                else
                {
                    foreach (string l in WordWrap(Lang.L("Çoğu modpack Java 21 ister. Şimdi indirilsin mi? Yaklaşık 50 MB, yalnızca SyHost klasörüne iner."), W - 8)) rows.Add("  " + c.soft + l + R);
                    rows.Add("");
                    string[] o = { Lang.L("İndir"), Lang.L("Sonra (sunucu kurarken iner)") };
                    for (int i = 0; i < 2; i++)
                    {
                        bool s = i == Fr.Sel;
                        string line = "   " + (s ? c.brass + Bo + "❯ " + c.text : "  " + c.soft) + o[i] + R;
                        rows.Add(s ? SelLine(line, W) : line);
                    }
                    if (Fr.Note != null) { rows.Add(""); rows.Add("  " + Fr.NoteCol + Fr.Note + R); }
                    keys = Key("↑↓", Lang.L("seç")) + Key("Enter", Lang.L("devam")) + Key("Esc", Lang.L("geri"));
                }
                break;
            }

            case "arkadas":
                keys = RenderPlayitStep(rows, W);
                break;

            case "yazi":
                if (FontOk()) rows.Add(Check(Lang.L("Cascadia Mono yazı tipi hazır")));
                else foreach (string l in WordWrap(Lang.L("Logonun ve animasyonların doğru görünmesi için Cascadia Mono yazı tipi yalnızca senin kullanıcına kurulacak (yönetici izni gerekmez)."), W - 8)) rows.Add("  " + c.soft + l + R);
                if (Fr.Note != null) { rows.Add(""); rows.Add("  " + Fr.NoteCol + Fr.Note + R); }
                keys = Key("Enter", FontOk() || Fr.Confirm ? Lang.L("devam") : Lang.L("kur")) + Key("Esc", Lang.L("geri"));
                break;

            case "kisayol":
            {
                (string Label, bool On)[] o = { (Lang.L("Masaüstüne kısayol"), Fr.Desk), (Lang.L("Başlat menüsüne kısayol"), Fr.Start) };
                for (int i = 0; i < 2; i++)
                {
                    bool s = i == Fr.Sel;
                    string box = o[i].On ? c.brass + Bo + "■" + R : c.dark + "□" + R;
                    string line = "   " + (s ? c.brass + Bo + "❯ " : "  ") + R + box + " " + (s ? c.text : c.soft) + o[i].Label + R;
                    rows.Add(s ? SelLine(line, W) : line);
                }
                rows.Add("");
                if (Fr.Note != null) foreach (string l in WordWrap(Fr.Note, W - 8)) rows.Add("  " + Fr.NoteCol + l + R);
                keys = Key("↑↓", Lang.L("seç")) + Key(Lang.L("Boşluk"), Lang.L("aç/kapat")) + Key("Enter", Lang.L("uygula")) + Key("Esc", Lang.L("geri"));
                break;
            }

            case "bitti":
                rows.Add("  " + c.green + Bo + "✓  " + Lang.L("Her şey hazır!") + R);
                rows.Add("");
                foreach (string l in WordWrap(Lang.L("Sunucu eklemek için ana menüde \"Yeni sunucu ekle\"yi seç ve bir Modrinth paketi (.mrpack) aç."), W - 8)) rows.Add("  " + c.soft + l + R);
                rows.Add("  " + c.dim + Lang.L("Ayarlara her zaman F9 ile ulaşabilirsin.") + R);
                rows.Add("");
                rows.Add("  " + Pill("240;240;240", "18;18;20", "Enter") + c.text + Lang.L(" Başla") + R);
                break;
        }

        // Boş satırlara gökyüzü, altta tuşlar (ana menüdeki gibi)
        while (rows.Count < H - 2) rows.Add("");
        UpdateSky(W, H, 0.07, 1, false, 0.75);
        for (int r1 = 0; r1 < rows.Count; r1++) if (rows[r1] == "") rows[r1] = SkySeg(r1, 0, W);
        rows.Add(c.dark + new string('─', W) + R);
        rows.Add(" " + keys);
        return rows;
    }
}
