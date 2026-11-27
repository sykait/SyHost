// =====================================================================
//  SyHost - başlatıcının Windows ile konuşan küçük yardımcıları
//  (pencere, uyarı kutusu, tek kopya kilidi ve süreç izleme)
// =====================================================================
using System.Runtime.InteropServices;

namespace SyHost;

static unsafe partial class Win
{
    public const uint MB_ICONERROR = 0x10, MB_ICONWARNING = 0x30, MB_SETFOREGROUND = 0x10000;
    const uint SYNCHRONIZE = 0x00100000, PROCESS_QUERY_LIMITED_INFORMATION = 0x1000, TH32CS_SNAPPROCESS = 0x2;

    [LibraryImport("user32.dll", EntryPoint = "MessageBoxW", StringMarshalling = StringMarshalling.Utf16)]
    public static partial int MessageBox(nint h, string text, string caption, uint type);
    [LibraryImport("user32.dll", EntryPoint = "FindWindowW", StringMarshalling = StringMarshalling.Utf16)]
    public static partial nint FindWindow(string cls, string title);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool ShowWindow(nint h, int cmd);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool SetForegroundWindow(nint h);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool AllowSetForegroundWindow(uint pid);

    [LibraryImport("kernel32.dll")] private static partial nint CreateToolhelp32Snapshot(uint flags, uint pid);
    [LibraryImport("kernel32.dll", EntryPoint = "Process32FirstW")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool Process32First(nint snap, PROCESSENTRY32W* e);
    [LibraryImport("kernel32.dll", EntryPoint = "Process32NextW")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool Process32Next(nint snap, PROCESSENTRY32W* e);
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool CloseHandle(nint h);
    [LibraryImport("kernel32.dll")] private static partial nint OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint pid);
    [LibraryImport("kernel32.dll")] private static partial uint WaitForSingleObject(nint h, uint ms);
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GetExitCodeProcess(nint h, out uint code);
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GetProcessTimes(nint h, out long creation, out long exit, out long kernel, out long user);

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESSENTRY32W
    {
        public uint dwSize, cntUsage, th32ProcessID;
        public nuint th32DefaultHeapID;
        public uint th32ModuleID, cntThreads, th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;
        public fixed char szExeFile[260];
    }

    /// <summary>Bu adla bir mutex var mı? (SyHost açıkken iki sürüm de onu tutar.)</summary>
    public static bool MutexExists(string name)
    {
        try
        {
            if (!Mutex.TryOpenExisting(name, out Mutex m)) return false;
            m.Dispose();
            return true;
        }
        catch (UnauthorizedAccessException) { return true; }   // var ama açılamıyor (ör. yönetici olarak açılmış bir SyHost)
        catch { return false; }
    }

    /// <summary>Sürecin başlama zamanı (FILETIME, UTC); okunamazsa 0.</summary>
    public static long StartTime(uint pid)
    {
        nint h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (h == 0) return 0;
        try { return GetProcessTimes(h, out long c, out _, out _, out _) ? c : 0; }
        finally { CloseHandle(h); }
    }

    /// <summary>
    /// parent'ın başlattığı, adı name olan süreç (yoksa 0). Süreç kimlikleri yeniden kullanılabildiği için
    /// parent'tan önce başlamış olanlar sayılmaz.
    /// </summary>
    public static uint FindChild(uint parent, long parentStart, string name)
    {
        nint snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snap == -1 || snap == 0) return 0;
        try
        {
            var e = new PROCESSENTRY32W { dwSize = (uint)sizeof(PROCESSENTRY32W) };
            for (bool ok = Process32First(snap, &e); ok; ok = Process32Next(snap, &e))
            {
                if (e.th32ParentProcessID != parent) continue;
                if (!new string(e.szExeFile).Equals(name, StringComparison.OrdinalIgnoreCase)) continue;
                long start = StartTime(e.th32ProcessID);
                if (start != 0 && parentStart != 0 && start < parentStart) continue;
                return e.th32ProcessID;
            }
        }
        finally { CloseHandle(snap); }
        return 0;
    }

    /// <summary>Beklenebilen ve çıkış kodu okunabilen süreç tutamacı.</summary>
    public sealed class ProcessHandle : IDisposable
    {
        nint h;
        public readonly uint Id;

        ProcessHandle(nint h, uint id) { this.h = h; Id = id; }

        public static ProcessHandle Open(uint pid)
        {
            nint h = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            return h == 0 ? null : new ProcessHandle(h, pid);
        }

        /// <summary>En çok ms milisaniye bekle; süreç kapandıysa true.</summary>
        public bool Wait(int ms) => WaitForSingleObject(h, (uint)Math.Max(0, ms)) == 0;

        public uint ExitCode => GetExitCodeProcess(h, out uint c) ? c : 0;

        public void Dispose()
        {
            if (h != 0) { CloseHandle(h); h = 0; }
        }
    }
}
