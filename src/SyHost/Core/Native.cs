// =====================================================================
//  SyHost - Windows ile konuşan yardımcılar
//  legacy/src/SyHost.Core.cs'in tek exe (NativeAOT) uyumlu karşılığı:
//  WinForms yerine doğrudan Windows API kullanır.
// =====================================================================
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;

namespace SyHost;

static unsafe partial class Native
{
    // ---------- kernel32 / user32 ----------
    [LibraryImport("kernel32.dll")] internal static partial nint GetConsoleWindow();
    [LibraryImport("kernel32.dll")] private static partial nint GetStdHandle(int n);
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GetConsoleMode(nint h, out uint m);
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetConsoleMode(nint h, uint m);
    [LibraryImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetCurrentConsoleFontEx(nint h, [MarshalAs(UnmanagedType.Bool)] bool max, CONSOLE_FONT_INFOEX* f);
    [LibraryImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GetCurrentConsoleFontEx(nint h, [MarshalAs(UnmanagedType.Bool)] bool max, CONSOLE_FONT_INFOEX* f);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static partial bool ShowWindow(nint h, int cmd);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static partial bool SetForegroundWindow(nint h);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static partial bool IsWindowVisible(nint h);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static partial bool IsIconic(nint h);
    [LibraryImport("user32.dll")] private static partial nint GetSystemMenu(nint h, [MarshalAs(UnmanagedType.Bool)] bool revert);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DeleteMenu(nint m, uint pos, uint flags);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DrawMenuBar(nint h);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GetWindowRect(nint h, out RECT r);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetWindowPos(nint h, nint after, int x, int y, int cx, int cy, uint flags);
    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongW")] private static partial int GetWindowLong(nint h, int i);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetLayeredWindowAttributes(nint h, uint key, byte alpha, uint flags);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetProcessDpiAwarenessContext(nint v);
    [LibraryImport("user32.dll")] private static partial nint MonitorFromWindow(nint h, uint flags);
    [LibraryImport("user32.dll")] private static partial nint MonitorFromPoint(POINT pt, uint flags);
    [LibraryImport("user32.dll", EntryPoint = "GetMonitorInfoW")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GetMonitorInfo(nint m, MONITORINFO* mi);
    [LibraryImport("user32.dll", EntryPoint = "GetClassNameW")] private static partial int GetClassName(nint h, char* buf, int max);
    [LibraryImport("user32.dll", EntryPoint = "FindWindowW", StringMarshalling = StringMarshalling.Utf16)] internal static partial nint FindWindow(string cls, string title);
    [LibraryImport("user32.dll", EntryPoint = "SendMessageW")] internal static partial nint SendMessage(nint h, uint msg, nint w, nint l);
    [LibraryImport("shell32.dll", EntryPoint = "ExtractIconExW", StringMarshalling = StringMarshalling.Utf16)] private static partial uint ExtractIconEx(string file, int index, nint* large, nint* small, uint n);
    [LibraryImport("comdlg32.dll", EntryPoint = "GetOpenFileNameW")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GetOpenFileName(OPENFILENAMEW* ofn);

    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public uint cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; }

    [StructLayout(LayoutKind.Sequential)]
    struct CONSOLE_FONT_INFOEX
    {
        public uint cbSize; public uint nFont; public short X; public short Y;
        public uint FontFamily; public uint FontWeight;
        public fixed char FaceName[32];
    }

    [StructLayout(LayoutKind.Sequential)]
    struct OPENFILENAMEW
    {
        public uint lStructSize; public nint hwndOwner; public nint hInstance;
        public char* lpstrFilter; public char* lpstrCustomFilter; public uint nMaxCustFilter; public uint nFilterIndex;
        public char* lpstrFile; public uint nMaxFile; public char* lpstrFileTitle; public uint nMaxFileTitle;
        public char* lpstrInitialDir; public char* lpstrTitle; public uint Flags;
        public ushort nFileOffset; public ushort nFileExtension; public char* lpstrDefExt;
        public nint lCustData; public nint lpfnHook; public char* lpTemplateName;
        public nint pvReserved; public uint dwReserved; public uint FlagsEx;
    }

    public static nint Hwnd => GetConsoleWindow();

    [StructLayout(LayoutKind.Sequential)]
    struct MEMORYSTATUSEX
    {
        public uint dwLength, dwMemoryLoad;
        public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
    }
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GlobalMemoryStatusEx(MEMORYSTATUSEX* m);

    /// <summary>Toplam ve boş fiziksel bellek (bayt).</summary>
    public static (double Total, double Avail) Memory()
    {
        var m = new MEMORYSTATUSEX { dwLength = (uint)sizeof(MEMORYSTATUSEX) };
        if (!GlobalMemoryStatusEx(&m)) return (0, 0);
        return (m.ullTotalPhys, m.ullAvailPhys);
    }

    /// <summary>Konsol yazı tipini ayarla (ör. Cascadia Mono, 16).</summary>
    public static bool SetFont(string face, short size)
    {
        var f = new CONSOLE_FONT_INFOEX { cbSize = (uint)sizeof(CONSOLE_FONT_INFOEX), X = 0, Y = size, FontFamily = 54, FontWeight = 400 };
        int n = Math.Min(face.Length, 31);
        for (int i = 0; i < n; i++) f.FaceName[i] = face[i];
        f.FaceName[n] = '\0';
        return SetCurrentConsoleFontEx(GetStdHandle(-11), false, &f);
    }

    /// <summary>Konsolun şu an kullandığı yazı tipinin adı.</summary>
    public static string GetFontFace()
    {
        var f = new CONSOLE_FONT_INFOEX { cbSize = (uint)sizeof(CONSOLE_FONT_INFOEX) };
        if (!GetCurrentConsoleFontEx(GetStdHandle(-11), false, &f)) return "";
        return new string(f.FaceName);
    }

    // Ekran ölçeklemesinde (125%/150%) konumlar doğru hesaplansın
    public static void DpiAware() { try { SetProcessDpiAwarenessContext(-4); } catch { } }

    public static void PrepareConsole()
    {
        // Renkli çizim (VT) aç
        nint o = GetStdHandle(-11);
        if (GetConsoleMode(o, out uint m)) SetConsoleMode(o, m | 0x0004);
        // QuickEdit kapat: pencereye tıklayınca panel donmasın
        nint i = GetStdHandle(-10);
        if (GetConsoleMode(i, out m)) SetConsoleMode(i, (m & ~0x0040u) | 0x0080u);
    }

    // X tuşunu kaldır: kapatma her zaman sunucuyu düzgün durdurarak yapılsın
    public static void DisableCloseButton()
    {
        nint h = GetConsoleWindow();
        nint menu = GetSystemMenu(h, false);
        if (menu != 0) { DeleteMenu(menu, 0xF060, 0); DrawMenuBar(h); }
    }

    public static void Hide() => ShowWindow(GetConsoleWindow(), 0);

    public static void Show()
    {
        nint h = GetConsoleWindow();
        ShowWindow(h, IsIconic(h) ? 9 : 5);
        SetForegroundWindow(h);
    }

    public static bool Visible { get { nint h = GetConsoleWindow(); return IsWindowVisible(h) && !IsIconic(h); } }

    // x, y, genişlik, yükseklik
    public static int[] GetRect()
    {
        GetWindowRect(GetConsoleWindow(), out RECT r);
        return new[] { r.L, r.T, r.R - r.L, r.B - r.T };
    }

    public static void MoveTo(int x, int y) => SetWindowPos(GetConsoleWindow(), 0, x, y, 0, 0, 0x0001 | 0x0004 | 0x0010);

    public static void SetTopMost(bool on) => SetWindowPos(GetConsoleWindow(), on ? -1 : -2, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);

    /// <summary>Pencerenin bulunduğu ekranın görev çubuğu hariç alanı: x, y, genişlik, yükseklik.</summary>
    public static int[] WorkArea()
    {
        nint mon = MonitorFromWindow(GetConsoleWindow(), 2);
        var mi = new MONITORINFO { cbSize = (uint)sizeof(MONITORINFO) };
        if (mon == 0 || !GetMonitorInfo(mon, &mi)) return new[] { 0, 0, 1920, 1040 };
        return new[] { mi.rcWork.L, mi.rcWork.T, mi.rcWork.R - mi.rcWork.L, mi.rcWork.B - mi.rcWork.T };
    }

    /// <summary>Kaydedilmiş konum hâlâ bir ekranın çalışma alanında mı?</summary>
    public static bool OnAnyScreen(int x, int y)
    {
        var pt = new POINT { X = x + 40, Y = y + 10 };
        nint mon = MonitorFromPoint(pt, 0);
        if (mon == 0) return false;
        var mi = new MONITORINFO { cbSize = (uint)sizeof(MONITORINFO) };
        if (!GetMonitorInfo(mon, &mi)) return false;
        return pt.X >= mi.rcWork.L && pt.X < mi.rcWork.R && pt.Y >= mi.rcWork.T && pt.Y < mi.rcWork.B;
    }

    // Pencere saydam yapılmışsa tam opak yap
    public static void MakeOpaque()
    {
        nint h = GetConsoleWindow();
        if ((GetWindowLong(h, -20) & 0x80000) != 0) SetLayeredWindowAttributes(h, 0, 255, 2);
    }

    /// <summary>Bu süreç gerçek bir konsol penceresinde (conhost) mi çalışıyor? Windows Terminal'de false.</summary>
    public static bool IsConhost()
    {
        nint h = GetConsoleWindow();
        if (h == 0) return false;
        char* buf = stackalloc char[64];
        int n = GetClassName(h, buf, 64);
        return n > 0 && new string(buf, 0, n) == "ConsoleWindowClass";
    }

    /// <summary>Konsol penceresine ve görev çubuğuna SyHost simgesini koy.</summary>
    public static void SetWindowIcon()
    {
        try
        {
            string exe = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exe)) return;
            nint large = 0, small = 0;
            if (ExtractIconEx(exe, 0, &large, &small, 1) == 0) return;
            nint h = GetConsoleWindow();
            if (large != 0) SendMessage(h, 0x0080, 1, large);   // WM_SETICON, ICON_BIG
            if (small != 0) SendMessage(h, 0x0080, 0, small);   // WM_SETICON, ICON_SMALL
        }
        catch { }
    }

    /// <summary>Açık bir SyHost penceresini öne getir (ikinci kopya açılınca).</summary>
    public static bool FocusWindow(string title)
    {
        nint h = FindWindow("ConsoleWindowClass", title);
        if (h == 0) return false;
        ShowWindow(h, 9); ShowWindow(h, 5); SetForegroundWindow(h);
        return true;
    }

    /// <summary>Dosya seçme penceresi. filter WinForms biçiminde: "Açıklama (*.mrpack)|*.mrpack".</summary>
    public static string PickFile(string title, string filter)
    {
        string result = null;
        var t = new Thread(() =>
        {
            string flt = filter.Replace('|', '\0') + "\0\0";
            var file = new char[4096];
            string init = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
            fixed (char* pFlt = flt) fixed (char* pFile = file) fixed (char* pTitle = title + "\0") fixed (char* pInit = init + "\0")
            {
                var o = new OPENFILENAMEW
                {
                    lStructSize = (uint)sizeof(OPENFILENAMEW), hwndOwner = GetConsoleWindow(),
                    lpstrFilter = pFlt, nFilterIndex = 1, lpstrFile = pFile, nMaxFile = (uint)file.Length,
                    lpstrInitialDir = pInit, lpstrTitle = pTitle,
                    Flags = 0x1000 | 0x800 | 0x80000 | 0x8 | 0x4,   // dosya var olmalı, yol var olmalı, explorer, klasörü değiştirme, salt okunuru gizle
                };
                if (GetOpenFileName(&o)) result = new string(pFile);
            }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();
        return result;
    }
}

// Panel kapanırsa (zorla bile) sunucu yetim kalmasın
static unsafe partial class JobGuard
{
    [LibraryImport("kernel32.dll", EntryPoint = "CreateJobObjectW")] private static partial nint CreateJobObject(nint a, nint name);
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetInformationJobObject(nint j, int cls, void* info, uint len);
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool AssignProcessToJobObject(nint j, nint p);

    [StructLayout(LayoutKind.Sequential)] struct BASIC { public long a, b; public uint LimitFlags; public nuint c, d; public uint e; public nuint f; public uint g, h; }
    [StructLayout(LayoutKind.Sequential)] struct IOC { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)] struct EXT { public BASIC B; public IOC I; public nuint p, j, pp, jp; }

    static nint job;
    static readonly object gate = new();

    public static void Add(Process p)
    {
        lock (gate)
        {
            if (job == 0)
            {
                job = CreateJobObject(0, 0);
                var e = new EXT();
                e.B.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE
                SetInformationJobObject(job, 9, &e, (uint)sizeof(EXT));
            }
            AssignProcessToJobObject(job, p.Handle);
        }
    }

    /// <summary>
    /// Pencere görev çubuğundan kapatılırken ya da oturum kapanırken Windows SyHost'u birkaç saniyede sonlandırır;
    /// o an "kapanınca öldür" kuralı sunucuyu dünyayı kaydederken öldürürdü. Sunucuya "stop" gönderildikten sonra
    /// kural kaldırılır: sunucu kaydı kendisi bitirip kapanır.
    /// </summary>
    public static void LetChildrenFinish()
    {
        lock (gate)
        {
            if (job == 0) return;
            var e = new EXT();   // LimitFlags = 0: iş kapanınca süreçler yaşamaya devam eder
            SetInformationJobObject(job, 9, &e, (uint)sizeof(EXT));
        }
    }
}

/// <summary>Sunucu (ya da playit) süreci: çıktısını kuyruğa yazar, komut gönderir.</summary>
sealed class ServerProcess
{
    public Process P;
    public readonly ConcurrentQueue<string> Out = new();
    StreamWriter input;
    /// <summary>Test modunda süreç olmadan "çalışıyor" gibi davranmak için.</summary>
    public bool? FakeRunning;

    public bool Running
    {
        get
        {
            if (FakeRunning.HasValue) return FakeRunning.Value;
            try { return P != null && !P.HasExited; } catch { return false; }
        }
    }

    public void Start(string exe, string args, string dir)
    {
        var psi = new ProcessStartInfo(exe, args)
        {
            WorkingDirectory = dir,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            // BOM'lu girdi ilk komutun başına görünmez bir karakter ekler; engelle
            StandardInputEncoding = new UTF8Encoding(false),
        };
        P = new Process { StartInfo = psi };
        P.OutputDataReceived += (s, e) => { if (e.Data != null) Out.Enqueue(e.Data); };
        P.ErrorDataReceived += (s, e) => { if (e.Data != null) Out.Enqueue("[STDERR] " + e.Data); };
        P.Start();
        input = P.StandardInput;
        input.AutoFlush = true;
        input.NewLine = "\n";
        P.BeginOutputReadLine();
        P.BeginErrorReadLine();
        try { JobGuard.Add(P); } catch { }
    }

    public void Send(string line)
    {
        if (!Running || input == null) return;
        try { input.WriteLine(line); } catch { }
    }
}

// Windows kapanırken / oturum kapanırken sunucuyu kaydedip durdur
static unsafe partial class CloseGuard
{
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetConsoleCtrlHandler(delegate* unmanaged<uint, int> h, [MarshalAs(UnmanagedType.Bool)] bool add);
    public static volatile ServerProcess Current;
    /// <summary>playit: SyHost kapanırken hemen kapatılır (yalnızca SyHost açıkken çalışır).</summary>
    public static volatile ServerProcess Playit;

    public static void Install() => SetConsoleCtrlHandler(&Handler, true);

    [UnmanagedCallersOnly]
    static int Handler(uint t)
    {
        if (t == 0 || t == 1) return 1; // Ctrl+C / Ctrl+Break: yok say
        SaveAndRelease();
        return 0;
    }

    /// <summary>
    /// Windows SyHost'u kapatıyor (pencere kapatma, oturum kapanması): playit'i kapat, sunucuya "stop" gönder ve
    /// SyHost sonlandırılsa da sunucunun kaydı bitirebilmesi için onu iş nesnesinden serbest bırak.
    /// </summary>
    public static void SaveAndRelease()
    {
        try { var p = Playit; if (p != null && p.Running) p.P.Kill(); } catch { }
        var s = Current;
        if (s != null && s.Running)
        {
            s.Send("stop");
            JobGuard.LetChildrenFinish();
            try { s.P.WaitForExit(25000); } catch { }
        }
    }
}

static class Backup
{
    // Sunucu açıkken de çalışır (dosyalar paylaşımlı okunur)
    public static Task<string> ZipAsync(string src, string dst)
    {
        return Task.Run(() =>
        {
            string tmp = dst + ".tmp";
            using (var fs = new FileStream(tmp, FileMode.Create))
            using (var zip = new ZipArchive(fs, ZipArchiveMode.Create))
            {
                int cut = src.TrimEnd('\\').Length + 1;
                foreach (string file in Directory.EnumerateFiles(src, "*", SearchOption.AllDirectories))
                {
                    if (file.EndsWith("session.lock", StringComparison.OrdinalIgnoreCase)) continue;
                    string rel = file.Substring(cut).Replace('\\', '/');
                    try
                    {
                        using var inp = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                        var entry = zip.CreateEntry(rel, CompressionLevel.Fastest);
                        using var outp = entry.Open();
                        inp.CopyTo(outp);
                    }
                    catch { }
                }
            }
            if (File.Exists(dst)) File.Delete(dst);
            File.Move(tmp, dst);
            return dst;
        });
    }
}
