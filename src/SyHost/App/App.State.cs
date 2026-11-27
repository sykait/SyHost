// =====================================================================
//  SyHost - uygulamanın bütün durumu
//  legacy/src/SyHost.ps1'deki betik değişkenlerinin birebir karşılığı.
//  Adlar PowerShell'dekiyle aynı ($HomeSel -> HomeSel), böylece iki sürüm
//  yan yana okunabilir.
// =====================================================================
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.RegularExpressions;

namespace SyHost;

sealed partial class App
{
    // ---------- Sabitler ----------
    /// <summary>Pencere başlığı. Testler (SYHOST_TEST_TITLE) paralel çalışan kopyaları ayırmak için değiştirebilir.</summary>
    public static readonly string Title = Environment.GetEnvironmentVariable("SYHOST_TEST_TITLE") is { Length: > 0 } t ? t : "SyHost";
    public static readonly string Version = typeof(App).Assembly.GetName().Version is { } v ? $"{v.Major}.{v.Minor}.{v.Build}" : "1.0.0";
    /// <summary>Başlıkta sürümün yanında görünen etiket. Terminal sürümünde "Terminal" yazar.</summary>
    public string Edition = "C#";
    public string VersionText = Version;

    const string E = "\u001b";
    const string R = "\u001b[0m";
    const string Bo = "\u001b[1m";

    // ---------- Yollar (taşınabilir: hepsi SyHost klasörünün içinde) ----------
    public string AppRoot;      // SyHost.exe'nin bulunduğu klasör
    public string Data;         // AppRoot\Data (gizli)
    public string CfgFile;      // Data\ayarlar.json
    public string ServersFile;  // Data\sunucular.json
    public string WinFile;      // Data\pencere.json
    public string ErrorLog;     // Data\hata.log

    // ---------- Ayarlar ----------
    public Settings Cfg;
    public Dictionary<string, Pack> Packs;
    public static readonly string[] PackKeys = { "dusuk", "normal", "yuksek" };
    static readonly Dictionary<string, string> PackNameKey = new(StringComparer.OrdinalIgnoreCase) { ["dusuk"] = "DÜŞÜK", ["normal"] = "NORMAL", ["yuksek"] = "YÜKSEK" };
    static readonly Dictionary<string, string> PackDescKey = new(StringComparer.OrdinalIgnoreCase)
    {
        ["dusuk"] = "Ağır bir oyun oynarken. Sistemini en az yoran ayar.",
        ["normal"] = "Günlük kullanım. 2-5 kişi için en dengeli ayar.",
        ["yuksek"] = "Dev fabrikalar ve hızlı keşif için tam güç.",
    };
    public int MaxPlayers = 5;
    public int Threads = Environment.ProcessorCount;
    public double TotalRam;
    public bool HasFriendAddr;
    public string FriendAddr = "";

    public List<ServerEntry> Servers = new();

    // ---------- Renkler ve metin ----------
    public readonly Palette c = new();
    Dictionary<string, string> PackColor;
    Dictionary<string, string> PrioTr;
    static readonly Dictionary<string, string> LoaderName = new(StringComparer.OrdinalIgnoreCase) { ["neoforge"] = "NeoForge", ["forge"] = "Forge", ["fabric"] = "Fabric", ["quilt"] = "Quilt" };

    static readonly Regex AnsiRx = new("\u001b\\[[0-9;?]*[A-Za-z]", RegexOptions.Compiled);
    // Japonca/Çince gibi geniş karakterler ekranda iki sütun kaplar
    static readonly Regex WideRx = new("[\u1100-\u115F\u2E80-\u303E\u3041-\u33FF\u3400-\u4DBF\u4E00-\u9FFF\uA000-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6]", RegexOptions.Compiled);

    // ---------- Animasyon ----------
    public readonly Stopwatch Clock = Stopwatch.StartNew();
    const string SpinFrames = "\u28FE\u28FD\u28FB\u28BF\u287F\u28DF\u28EF\u28F7";
    static readonly string[] PulseFrames = { "\u2219", "\u2022", "\u25C9", "\u2B24", "\u25C9", "\u2022" };
    string[] Verbs;

    // ---------- Logo ----------
    static readonly Dictionary<char, string[]> LogoFont = new()
    {
        ['S'] = new[] { "███████╗", "██╔════╝", "███████╗", "╚════██║", "███████║", "╚══════╝" },
        ['Y'] = new[] { "██╗   ██╗", "╚██╗ ██╔╝", " ╚████╔╝ ", "  ╚██╔╝  ", "   ██║   ", "   ╚═╝   " },
        ['H'] = new[] { "██╗  ██╗", "██║  ██║", "███████║", "██╔══██║", "██║  ██║", "╚═╝  ╚═╝" },
        ['O'] = new[] { " ██████╗ ", "██╔═══██╗", "██║   ██║", "██║   ██║", "╚██████╔╝", " ╚═════╝ " },
        ['T'] = new[] { "████████╗", "╚══██╔══╝", "   ██║   ", "   ██║   ", "   ██║   ", "   ╚═╝   " },
    };
    static readonly string[] LogoPlain = BuildLogoPlain();
    static readonly int LogoW = LogoPlain[0].Length;
    static readonly char[] LogoLetters = { 'S', 'Y', 'H', 'O', 'S', 'T' };
    static string[] BuildLogoPlain()
    {
        var rows = new string[6];
        for (int row = 0; row < 6; row++)
        {
            var sb = new System.Text.StringBuilder();
            foreach (char ch in "SYHOST") sb.Append(LogoFont[ch][row]);
            rows[row] = sb.ToString();
        }
        return rows;
    }

    public Random Rnd = new();
    double GlitchUntil = 0.0, GlitchNext = 4.0;
    Dictionary<int, int> GlitchRows = new();

    // ---------- Durum ----------
    public string Screen = "splash";            // splash | home | wizard | server | outro | firstrun | settings | uninstall
    public double SplashStart = 0.0;
    public int HomeSel = 0;
    public string HomeMode = "list";
    public string HomeMsg = "";
    public DateTime HomeMsgUntil = DateTime.MinValue;
    public Dictionary<string, string> WorldSizeCache = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, int> ModCountCache = new(StringComparer.OrdinalIgnoreCase);
    public ServerEntry Cur;
    public ServerProcess S;
    public string Status = "KAPALI";
    Dictionary<string, (string Col, string Text)> StatusLook;
    public DateTime? StartTime;
    public bool WasRunning, StopRequested;
    public string AfterStop;
    public DateTime? AutoRestartAt, StopSentAt;
    public SortedSet<string> Players = new(StringComparer.OrdinalIgnoreCase);
    public int LoadedRamMax;
    public bool RamPending;
    public List<LogEntry> Log = new();
    public int Scroll = 0;
    public string Mode = "log";
    public string ActivePack = "normal";
    public int PackSel = 1;
    public string InputText = "";
    public List<string> History = new();
    public int HistIdx = -1;
    public bool Dirty = true;
    public DateTime LastRender = DateTime.MinValue;
    public string LastSize = "";
    public bool WasVisible = true, HideTipShown;
    public string[] PrevFrame = Array.Empty<string>();
    public double RamNow, CpuNow, LastCpuMs;
    public DateTime LastStat = DateTime.Now;
    public double SysFree;
    public DateTime LastSlow = DateTime.MinValue;
    public string BackupStage;
    public Task<string> BackupTask;
    public string BackupDst;
    public DateTime? BackupSince;
    public DateTime LastBackup = DateTime.Now;
    public bool Detail;
    public DateTime ReplyUntil = DateTime.MinValue;
    public int Stage = 0, StopPhase = 0;
    public DateTime? ClosingSince, ShutdownStopAt, FinishAt;
    public string AfterClose = "home";
    public int ExpectedStart = 35, ModCount = 0;
    public List<DateTime> CrashTimes = new();
    public bool Quit, RestartApp;
    public WizardState Wiz;
    public bool ShowLogo;

    // ---------- Pencere modu ----------
    public WinState Win = new();
    public string UiMode = "buyuk";
    static readonly int[] BigSize = { 130, 42 };
    static readonly int[] MiniSize = { 54, 15 };
    readonly Dictionary<string, DateTime> LastPress = new(StringComparer.OrdinalIgnoreCase);

    // ---------- Gökyüzü ----------
    public List<Meteor> Meteors = new();
    public Dictionary<int, Dictionary<int, string>> MeteorRows = new();
    public double MeteorLastT = 0.0, MeteorNextSpawn = 0.0;
    public Dictionary<int, List<(int Col, double Seed)>> Stars = new();
    public string StarsSize = "";
    public bool TwinkleOn;

    public const double SplashLen = 2.6;
    public double OutroStart = 0.0;
    public const double OutroLen = 2.0;

    // ---------- Sunucu ekranı ----------
    Dictionary<int, string> StageNames;
    Dictionary<string, (string Label, string C1, string C2)> Badge;
    /// <summary>Konsoldaki rozet sütununun genişliği: dilin en geniş rozeti, en az 6 (Japonca 8).</summary>
    int BadgeW = 6;
    static readonly string[] BuiltinsTr = { "yardim", "baslat", "durdur", "yeniden", "paket", "yedek", "oyuncular", "adres", "kopyala", "gizle", "kucuk", "buyuk", "ustte", "detay", "sade", "temizle", "klasor", "zorla", "menu", "cikis" };
    static readonly string[] BuiltinsEn = { "help", "start", "stop", "restart", "pack", "backup", "players", "address", "copy", "hide", "mini", "full", "pin", "detail", "simple", "clear", "folder", "force", "menu", "exit" };
    string[] Builtins;
    static readonly string[] PlayerCmds = { "op", "deop", "kick", "ban", "pardon", "tp", "msg", "tell", "gamemode", "give", "kill", "whitelist" };
    static readonly string[] MiniKinds = { "join", "leave", "chat", "panel", "ok", "error", "cmd" };

    const string JvmBase = "-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1";
    static readonly Regex LineRx = new(@"^\[(\d\d:\d\d:\d\d)\] \[(.+?)/([A-Z]+)\] \[(.*?)\]: ?(.*)$", RegexOptions.Compiled);
    static readonly Regex LineRx2 = new(@"^\[(\d\d:\d\d:\d\d)\] \[(.+?)/([A-Z]+)\]: ?(.*)$", RegexOptions.Compiled);

    // ---------- playit (sadece SyHost açıkken) ----------
    public ServerProcess Pl;
    public string PlayitExe;
    public string PlayitSecret;

    // ---------- Test modu (iki sürümün ekranını karakter karakter karşılaştırmak için) ----------
    public bool TestMode;
    public double TestT;
    public DateTime TestNow;
    public bool? TestJavaFound;
    public bool? TestPlayitOn;
}

/// <summary>Renk paleti ($c). Alan adları PowerShell'dekiyle aynı.</summary>
sealed class Palette
{
    static string Rgb(int r, int g, int b) => $"\u001b[38;2;{r};{g};{b}m";
    public readonly string brass = Rgb(239, 55, 66), copper = Rgb(160, 28, 40), text = Rgb(240, 240, 240), soft = Rgb(165, 165, 170);
    public readonly string dim = Rgb(110, 110, 116), dark = Rgb(58, 58, 64), green = Rgb(120, 220, 140), yellow = Rgb(255, 135, 135);
    public readonly string red = Rgb(255, 70, 80), cyan = Rgb(255, 255, 255), blue = Rgb(220, 220, 225), orange = Rgb(220, 60, 70), violet = Rgb(255, 160, 165);
}

/// <summary>Konsol kaydındaki bir satır (Add-Log).</summary>
sealed class LogEntry
{
    public string T;   // saat
    public string K;   // tür: info warn error panel ok join leave chat cmd
    public string M;   // mesaj
    public bool V;     // sade görünümde görünür mü
}

/// <summary>Gökyüzündeki kayan yıldız.</summary>
sealed class Meteor
{
    public double x, y, vx, vy, age, life;
    public int len;
}

/// <summary>Bir .mrpack paketinden okunan bilgiler (Read-Pack).</summary>
sealed class PackInfo
{
    public string Path, Name, Version, Mc, Loader, LoaderVer;
    public int Java, Mods, ClientOnly;
    public List<string> Saves = new();
    public double SizeMb;
}

/// <summary>Kurulum adımı (adı ve durumu: 0 bekliyor, 1 sürüyor, 2 bitti, 3 hata).</summary>
sealed class InstallStep
{
    public string N;
    public volatile int S;
}

/// <summary>Arka planda süren kurulumla ekran arasında paylaşılan bilgiler ($sync).</summary>
sealed class InstallSync
{
    public List<InstallStep> Steps = new();
    public volatile int Pct;
    public volatile string Count = "";
    public volatile string Detail = "";
    public volatile bool Done;
    public volatile string Error;
    public volatile InstallResult Result;
    public volatile List<string> Failed = new();
}

sealed class InstallResult
{
    public string mc, loader, loaderSurum, baslat;
    public int java;
}

/// <summary>Sunucu kurulum sihirbazı ($Wiz).</summary>
sealed class WizardState
{
    public string Step = "isim";    // isim | dunya | onay | kurulum | bitti | hata
    public PackInfo Info;
    public string Name;
    public int WorldSel;
    public InstallSync Sync;
    public Task Job;
    public string Target;
    public DateTime StartedAt;
}
