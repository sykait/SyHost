// =====================================================================
//  SyHost - Terminal sürümünün başlatıcısı (SyHost.exe)
//  PowerShell uygulamasını (legacy\src) içinde taşır ve klasik konsol penceresinde (conhost) açar:
//    kuruluysa (yanında Data var)       gizli App klasörüne çıkarır (yalnızca değişince), oradan açar
//    kurulu değilse (ör. İndirilenler)  %TEMP%'te geçici bir klasöre çıkarır, SyHost kapanınca siler
//  Uygulama kendini yeniden açarken (kurulumdan sonra, dil değişince) bu exe'yi kullanır (-Exe).
//
//  Gizli test kancası: SYHOST_LAUNCHER_LOG=<dosya> verilirse kararlar o dosyaya yazılır; uyarı
//  pencereleri açılmaz (metinleri dosyaya yazılır) ve açık SyHost penceresi öne getirilmez.
//  Gizli öz denetim: SyHost.exe --selftest extract <boş klasör>  gömülü uygulamayı oraya çıkarır.
// =====================================================================
using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace SyHost;

static class Program
{
    const string DataName = "Data";   // Portable.DataName

    static int Main(string[] args)
    {
        // Öz denetim hiçbir zaman uygulamayı açmaz (C# sürümünün denetimleri bu exe'de yok: 2 döner)
        if (args.Length >= 1 && args[0] == "--selftest")
            return args.Length >= 3 && args[1] == "extract" ? SelfTestExtract(args[2]) : 2;
        // Kaldır ekranı bu exe'yi yönetici olarak yalnızca bu anahtarla açar (0.5.0'ın sistem yazı tipi).
        // Tek kopya kilidinden önce: açık SyHost'un penceresini öne getirip "oldu" demesin. (C#: Program.cs)
        if (args.Length == 1 && args[0] == OldSystemFont.Arg)
            return OldSystemFont.Run();

        string root = null;
        bool installed = false;
        try
        {
            string exe = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exe)) throw new InvalidOperationException("The path of SyHost.exe is unknown.");
            TestLog.Write("launch " + exe + (args.Length > 0 ? " " + string.Join(' ', args) : ""));

            // 1) Tek kopya: SyHost açıksa (iki sürüm aynı kilidi kullanır) penceresini öne getir, hiçbir dosyaya dokunma
            string title = Title();
            if (Win.MutexExists(MutexName(title)))
            {
                Focus(title);
                return 0;
            }

            // 2) SyHost klasörü exe'nin klasörüdür; Data içinde SyHost'un ayar ya da sunucu listesi varsa orada kurulu
            //    (C# Portable.IsInstalled ile aynı kural: ilgisiz bir Data klasörü kurulum sayılmaz)
            root = Path.GetDirectoryName(exe);
            installed = File.Exists(Path.Combine(root, DataName, "ayarlar.json")) || File.Exists(Path.Combine(root, DataName, "sunucular.json"));

            // 3) Kurulu klasöre yazılamıyorsa (ör. Program Files'a taşınmış) sessizce kapanma: C# sürümüyle aynı uyarı
            if (installed && !CanWrite(Path.Combine(root, DataName)))
            {
                Lang.Code = UiLanguage();
                Alert(Lang.L("SyHost bu klasöre yazamıyor:\n{0}\n\nSyHost klasörünü içindekilerle birlikte (SyHost.exe, Servers ve Data) yazılabilir bir yere taşı (ör. {1}) ve SyHost.exe'yi oradan aç.", root, DefaultRoot()), Win.MB_ICONWARNING);
                return 1;
            }

            bool noSplash = Array.IndexOf(args, "--no-splash") >= 0;
            Payload.CleanStaleTemps();
            if (installed)
            {
                // 4) Kurulu: App bu exe'nin içindekiyle aynı olsun, oradan aç
                TestLog.Write("installed " + root);
                string app = Payload.Install(root);
                Run(app, root, exe, noSplash, untilExit: false);
            }
            else
            {
                // 5) Kurulum ekranı (ör. İndirilenler'den açıldı): exe'nin yanına hiçbir şey yazılmaz.
                //    Geçici klasör SyHost kapanana kadar durur, sonra silinir.
                TestLog.Write("setup " + root);
                using var tmp = Payload.ExtractTemp();
                Run(tmp.Dir, root, exe, noSplash, untilExit: true);
            }
            return 0;
        }
        catch (Exception e)
        {
            TestLog.Write("error " + e.GetType().Name + ": " + e.Message);
            Fail(e.Message, installed ? root : null);
            return 1;
        }
    }

    // ---------- PowerShell'i aç ----------

    /// <summary>conhost içinde: powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File App\src\SyHost.ps1 -Root ... -Exe ...</summary>
    static void Run(string app, string root, string exe, bool noSplash, bool untilExit)
    {
        string sys = Environment.SystemDirectory;
        // conhost'u açıkça başlat: pencere gizleme, küçük mod ve taşıma Windows Terminal'de çalışmaz.
        // powershell.exe tam yoluyla: yalın ad, conhost'un çalışma klasöründe (ör. İndirilenler) de aranırdı.
        string conhost = Path.Combine(sys, "conhost.exe");
        string powershell = Path.Combine(sys, @"WindowsPowerShell\v1.0\powershell.exe");
        foreach (string f in new[] { conhost, powershell })
            if (!File.Exists(f)) throw new FileNotFoundException("Windows component not found: " + f);

        string arguments = PowerShellArguments(powershell, Path.Combine(app, "src", "SyHost.ps1"), root, exe, noSplash, out string workDir);
        TestLog.Write("start " + arguments);
        // ShellExecute (C# sürümündeki Launch gibi): conhost bizim boru/konsol tutamaçlarımızı devralırsa
        // kendi penceresini açmaz. Çalışma klasörü SyHost klasörü (C# sürümüyle aynı; yolda % varsa bkz. PowerShellArguments).
        var psi = new ProcessStartInfo(conhost, arguments) { UseShellExecute = true, WorkingDirectory = workDir };
        Win.AllowSetForegroundWindow(uint.MaxValue);   // açılan pencere öne gelebilsin (ASFW_ANY)
        using Process host = Process.Start(psi) ?? throw new InvalidOperationException("conhost.exe did not start.");
        Watch(host, untilExit);
    }

    /// <summary>
    /// powershell.exe'nin komut satırı. Betikleri bu exe kendisi yazdığı için (internetten gelmiş işaretleri yok)
    /// RemoteSigned yeter; Bypass kullanılmaz.
    /// conhost istemcinin komut satırını yeniden ayrıştırır: tırnakları kendi kurar ve %AD% kalıplarını ortam
    /// değişkeniyle değiştirir. Bu yüzden sürücü kökü "D:\." olarak verilir (kapanış tırnağından önce \ kalmasın).
    /// Yollardan birinde % varsa yollar komut satırına hiç yazılmaz: betik çalışma klasörüne göre (göreli) verilir,
    /// SyHost klasörü ile exe veri olarak SYHOST_LAUNCH_ROOT ve SYHOST_LAUNCH_EXE'de geçer (SyHost.ps1 okur ve siler).
    /// Kuruluysa çalışma klasörü yine SyHost klasörüdür (App\src\SyHost.ps1), kurulum ekranında geçici App klasörü.
    /// </summary>
    static string PowerShellArguments(string powershell, string ps1, string root, string exe, bool noSplash, out string workDir)
    {
        string head = "\"" + powershell + "\" -NoProfile -ExecutionPolicy RemoteSigned ";
        string tail = noSplash ? " -NoSplash" : "";
        if ((ps1 + root + exe).Contains('%'))
        {
            Environment.SetEnvironmentVariable("SYHOST_LAUNCH_ROOT", root);
            Environment.SetEnvironmentVariable("SYHOST_LAUNCH_EXE", exe);
            string app = Path.GetDirectoryName(Path.GetDirectoryName(ps1));   // <App>\src\SyHost.ps1 -> <App>
            bool underRoot = ps1.StartsWith(root.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);
            workDir = underRoot ? root : app;
            return head + "-File \"" + Path.GetRelativePath(workDir, ps1) + "\"" + tail;
        }
        workDir = root;
        string rootArg = root.EndsWith('\\') ? root + "." : root;
        return head + "-File \"" + ps1 + "\" -Root \"" + rootArg + "\" -Exe \"" + exe + "\"" + tail;
    }

    // PowerShell açılışta hatayla kapanırsa (ör. betikler bilgisayarda kuralla engelli, App bozuk) kullanıcı yalnızca
    // bir an yanıp sönen pencere görürdü. conhost istemcinin çıkış kodunu vermez (hep 0), PowerShell'i kendimiz izleriz.
    const int EarlyMs = 10000;
    const uint StatusControlCExit = 0xC000013A;   // konsol penceresi kapatıldı
    const uint KilledExit = 0xFFFFFFFF;           // Process.Kill / Stop-Process

    static void Watch(Process host, bool untilExit)
    {
        var sw = Stopwatch.StartNew();
        uint hostId = (uint)host.Id;
        long hostStart = Win.StartTime(hostId);
        Win.ProcessHandle ps = null;
        try
        {
            while (sw.ElapsedMilliseconds < 5000)
            {
                uint pid = Win.FindChild(hostId, hostStart, "powershell.exe");
                if (pid != 0 && (ps = Win.ProcessHandle.Open(pid)) != null) break;
                if (host.WaitForExit(20)) break;
            }
            if (ps == null)
            {
                if (host.HasExited) throw new InvalidOperationException("Windows PowerShell did not start.");
                TestLog.Write("powershell not found");
            }
            else
            {
                TestLog.Write("powershell " + ps.Id);
                if (ps.Wait(EarlyMs - (int)sw.ElapsedMilliseconds))
                {
                    uint code = ps.ExitCode;
                    TestLog.Write("powershell exited early, code " + code.ToString(CultureInfo.InvariantCulture));
                    if (code != 0 && code != StatusControlCExit && code != KilledExit)
                        throw new InvalidOperationException(string.Format(CultureInfo.InvariantCulture,
                            "Windows PowerShell closed right after starting (exit code {0}, 0x{1:X8}).", (int)code, code));
                }
            }
        }
        finally { ps?.Dispose(); }
        if (untilExit)
        {
            host.WaitForExit();
            TestLog.Write("console closed");
        }
    }

    // ---------- Pencereler ----------

    /// <summary>Açık SyHost penceresini öne getir (C# Native.FocusWindow, SyHost.ps1'deki ikinci kopya).</summary>
    static void Focus(string title)
    {
        nint h = Win.FindWindow("ConsoleWindowClass", title);
        TestLog.Write("focus " + title + " 0x" + h.ToString("X"));
        if (h == 0 || TestLog.On) return;
        Win.ShowWindow(h, 9);
        Win.ShowWindow(h, 5);
        Win.SetForegroundWindow(h);
    }

    /// <summary>Konsol açılmadan önceki düz Windows uyarısı (C# Portable.Alert).</summary>
    static void Alert(string text, uint icon)
    {
        if (TestLog.On) { TestLog.Write("alert " + text.Replace("\n", "\\n")); return; }
        Win.MessageBox(0, text, "SyHost", icon | Win.MB_SETFOREGROUND);
    }

    /// <summary>Başlatıcı açamadı: kısa, kullanıcının dilinde bir ileti ve sebep. Kuruluysa hata.log'a da yazılır.</summary>
    static void Fail(string reason, string root)
    {
        if (root != null)
        {
            // SyHost.ps1'deki hata.log biçimi: [tarih] ileti
            try { File.AppendAllText(Path.Combine(root, DataName, "hata.log"), "[" + DateTime.Now + "] SyHost.exe: " + reason + Environment.NewLine, new UTF8Encoding(false)); }
            catch { }
        }
        Lang.Code = UiLanguage();
        Alert(Lang.L("SyHost bir hatayla karşılaştı:") + "\n\n" + reason, Win.MB_ICONERROR);
    }

    // ---------- Ana sürümle aynı kurallar ----------

    // C# App.Title ve SyHost.ps1 $Title: testler pencere adını ve tek kopya kilidini değiştirebilir
    static string Title() => Environment.GetEnvironmentVariable("SYHOST_TEST_TITLE") is { Length: > 0 } t ? t : "SyHost";

    // SyHost.ps1 $MutexName ve C# Program.cs ile aynı: 'SyHost' karşılaştırması büyük-küçük harfe duyarlı
    static string MutexName(string title) =>
        @"Local\SyHostSunucuMerkezi" + (string.Equals(title, "SyHost", StringComparison.Ordinal) ? "" : "-" + title);

    // src\SyHost\Setup\Portable.cs: UiLanguage (Portable.cs başka sınıflara bağlı olduğu için tek başına derlenmez)
    static string UiLanguage()
    {
        string two = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
        return two == "tr" ? "tr" : two == "ja" ? "ja" : "en";
    }

    // src\SyHost\Setup\Portable.cs: DefaultRoot
    static string DefaultRoot()
    {
        string t = Environment.GetEnvironmentVariable("SYHOST_DEFAULT_ROOT");
        return !string.IsNullOrEmpty(t) ? t : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "SyHost");
    }

    // src\SyHost\Setup\Portable.cs: CanWrite
    static bool CanWrite(string dir)
    {
        try
        {
            Directory.CreateDirectory(dir);
            string f = Path.Combine(dir, ".syhost-yazma-denemesi-" + Guid.NewGuid().ToString("N"));
            File.WriteAllText(f, "x");
            File.Delete(f);
            return true;
        }
        catch { return false; }
    }

    // ---------- Gizli öz denetim ----------

    /// <summary>--selftest extract &lt;klasör&gt;: gömülü uygulamayı boş bir klasöre çıkar ve güncel sayıldığını denetle.</summary>
    static int SelfTestExtract(string dir)
    {
        try
        {
            if (Directory.Exists(dir) && Directory.EnumerateFileSystemEntries(dir).Any()) throw new IOException("The folder is not empty: " + dir);
            Directory.CreateDirectory(dir);
            Payload.ExtractTo(dir);
            return Payload.IsCurrent(dir) ? 0 : 2;
        }
        catch (Exception e)
        {
            try { Console.Error.WriteLine(e.Message); } catch { }
            return 1;
        }
    }
}

/// <summary>Gizli test kancası: SYHOST_LAUNCHER_LOG dosyasına kararları yazar.</summary>
static class TestLog
{
    static readonly string LogFile = Environment.GetEnvironmentVariable("SYHOST_LAUNCHER_LOG");

    public static bool On => !string.IsNullOrEmpty(LogFile);

    public static void Write(string line)
    {
        if (!On) return;
        string text = DateTime.Now.ToString("HH:mm:ss.fff", CultureInfo.InvariantCulture) + " [" + Environment.ProcessId.ToString(CultureInfo.InvariantCulture) + "] " + line + Environment.NewLine;
        for (int i = 0; i < 50; i++)
        {
            try { File.AppendAllText(LogFile, text, new UTF8Encoding(false)); return; }
            catch (IOException) { Thread.Sleep(10); }
            catch { return; }
        }
    }
}
