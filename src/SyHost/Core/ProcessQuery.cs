// =====================================================================
//  SyHost - başka süreçlerin komut satırı
//  PowerShell sürümü bunu WMI ile okur (Get-CimInstance Win32_Process).
//  Burada doğrudan NtQueryInformationProcess (ProcessCommandLineInformation = 60):
//  tek exe (NativeAOT) uyumlu, WMI'ye göre çok hızlı ve yönetici izni istemez
//  (PROCESS_QUERY_LIMITED_INFORMATION yeterli, yükseltilmiş süreçlerde bile).
// =====================================================================
using System.Runtime.InteropServices;

namespace SyHost;

static unsafe partial class ProcessQuery
{
    [LibraryImport("kernel32.dll")] private static partial nint OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint pid);
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool CloseHandle(nint h);
    [LibraryImport("ntdll.dll")] private static partial int NtQueryInformationProcess(nint h, int infoClass, void* info, uint len, uint* retLen);

    const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    const int ProcessCommandLineInformation = 60;
    const int STATUS_BUFFER_OVERFLOW = unchecked((int)0x80000005);
    const int STATUS_INFO_LENGTH_MISMATCH = unchecked((int)0xC0000004);
    const int STATUS_BUFFER_TOO_SMALL = unchecked((int)0xC0000023);

    // Çıktının başı bir UNICODE_STRING; Buffer aynı tamponun içini gösterir
    [StructLayout(LayoutKind.Sequential)]
    struct UNICODE_STRING { public ushort Length, MaximumLength; public char* Buffer; }

    /// <summary>Sürecin komut satırı. Okunamazsa (süreç kapandı, izin yok) null.</summary>
    public static string CommandLine(int pid)
    {
        if (pid <= 0) return null;
        nint h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, (uint)pid);
        if (h == 0) return null;
        try
        {
            uint size = 2048;
            for (int attempt = 0; attempt < 4; attempt++)
            {
                void* buf = NativeMemory.Alloc(size);
                try
                {
                    uint need = 0;
                    int st = NtQueryInformationProcess(h, ProcessCommandLineInformation, buf, size, &need);
                    if (st >= 0)
                    {
                        var us = (UNICODE_STRING*)buf;
                        return us->Buffer == null ? "" : new string(us->Buffer, 0, us->Length / 2);
                    }
                    // Tampon küçük geldiyse gereken boyutla bir kez daha dene (komut satırı en fazla 32767 karakter)
                    bool small = st == STATUS_INFO_LENGTH_MISMATCH || st == STATUS_BUFFER_TOO_SMALL || st == STATUS_BUFFER_OVERFLOW;
                    if (!small || need <= size || need > (1u << 20)) return null;
                    size = need;
                }
                finally { NativeMemory.Free(buf); }
            }
            return null;
        }
        finally { CloseHandle(h); }
    }
}
