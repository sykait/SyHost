// =====================================================================
//  SyHost - pano
//  PowerShell'deki Set-Clipboard -Value'nun karşılığı: WinForms olmadan
//  doğrudan Windows API ile metni panoya (CF_UNICODETEXT) koyar.
// =====================================================================
using System.Runtime.InteropServices;

namespace SyHost;

static unsafe partial class Clipboard
{
    const uint CF_UNICODETEXT = 13;
    const uint GMEM_MOVEABLE = 0x0002;

    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool OpenClipboard(nint owner);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool CloseClipboard();
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool EmptyClipboard();
    [LibraryImport("user32.dll")] private static partial nint SetClipboardData(uint format, nint mem);
    [LibraryImport("kernel32.dll")] private static partial nint GlobalAlloc(uint flags, nuint bytes);
    [LibraryImport("kernel32.dll")] private static partial nint GlobalLock(nint mem);
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GlobalUnlock(nint mem);
    [LibraryImport("kernel32.dll")] private static partial nint GlobalFree(nint mem);

    /// <summary>
    /// Metni panoya koy. owner: panonun sahibi olacak pencere (SyHost'ta konsol penceresi).
    /// Pano o an başka bir programda açıksa, Set-Clipboard'un (WinForms) yaptığı gibi
    /// 100 ms arayla 10 kez dener. Başarılıysa true.
    /// </summary>
    public static bool SetText(string text, nint owner)
    {
        text ??= "";
        for (int i = 1; !OpenClipboard(owner); i++)
        {
            if (i >= 10) return false;
            Thread.Sleep(100);
        }
        nint mem = 0;
        try
        {
            if (!EmptyClipboard()) return false;
            mem = GlobalAlloc(GMEM_MOVEABLE, (nuint)((text.Length + 1) * sizeof(char)));
            if (mem == 0) return false;
            char* dst = (char*)GlobalLock(mem);
            if (dst == null) return false;
            try
            {
                text.AsSpan().CopyTo(new Span<char>(dst, text.Length));
                dst[text.Length] = '\0';
            }
            finally { GlobalUnlock(mem); }
            if (SetClipboardData(CF_UNICODETEXT, mem) == 0) return false;
            mem = 0;   // başarılı: bellek artık Windows'un, serbest bırakılmaz
            return true;
        }
        finally
        {
            if (mem != 0) GlobalFree(mem);
            CloseClipboard();
        }
    }
}
