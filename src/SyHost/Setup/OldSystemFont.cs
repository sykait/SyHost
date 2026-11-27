// =====================================================================
//  SyHost - 0.5.0'ın sisteme kurduğu yazı tipini kaldırma (yönetici izniyle)
//  0.5.0 Cascadia Mono'yu C:\Windows\Fonts'a ve HKLM'e kurardı. Kaldır ekranındaki "Eski kurulumun
//  sisteme koyduğu yazı tipi" satırı SyHost.exe'yi yalnızca bu anahtarla (--remove-old-system-font)
//  yönetici olarak açar: Windows izin penceresinde SyHost görünür, PowerShell ya da gizli pencere yoktur.
//  Komut satırından hiçbir yol ya da komut okunmaz; başka bir program bu kapıdan bir şey çalıştıramaz.
//  Yalnızca 0.5.0'ın yazdığı kayıt değerleri silinir (değeri bu dosyayı gösteriyorsa): Windows'un ya da
//  başka bir programın kendi Cascadia kaydına dokunulmaz.
//  Çıkış kodu: 0 hepsi kaldırıldı, 1 bir şey kaldı (ör. dosya kullanımda; oturum kapanınca silinebilir).
//  İki exe'de de derlenir: ana sürüm ve Terminal sürümünün başlatıcısı (SyHost.Terminal.csproj).
// =====================================================================
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace SyHost;

static partial class OldSystemFont
{
    public const string Arg = "--remove-old-system-font";
    const string RegPath = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts";
    static readonly (string File, string Value)[] Files =
    {
        ("CascadiaMono-Regular.ttf", "Cascadia Mono Regular (TrueType)"),
        ("CascadiaMono-Bold.ttf", "Cascadia Mono Bold (TrueType)"),
    };

    /// <summary>Yönetici olarak açılmış SyHost.exe'de çalışır: 0 hepsi kaldırıldı, 1 bir şey kaldı.</summary>
    public static int Run()
    {
        bool left = false;
        string dir = Environment.GetFolderPath(Environment.SpecialFolder.Fonts);
        try
        {
            using var k = Registry.LocalMachine.OpenSubKey(RegPath, true);
            foreach (var (file, value) in Files)
            {
                if (k?.GetValue(value) is not string v) continue;
                string path = Path.Combine(dir, file);
                if (v.Equals(file, StringComparison.OrdinalIgnoreCase) || v.Equals(path, StringComparison.OrdinalIgnoreCase)) k.DeleteValue(value, false);
            }
        }
        catch { left = true; }
        foreach (var (file, _) in Files)
        {
            string path = Path.Combine(dir, file);
            if (!File.Exists(path)) continue;
            for (int i = 0; i < 8 && RemoveFontResourceW(path); i++) { }
            try { File.SetAttributes(path, FileAttributes.Normal); File.Delete(path); }
            catch { left = true; }
        }
        try { SendMessageTimeoutW(0xffff, 0x001D, 0, 0, 2, 1000, out _); } catch { }   // WM_FONTCHANGE
        return left ? 1 : 0;
    }

    [LibraryImport("gdi32.dll", StringMarshalling = StringMarshalling.Utf16)] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool RemoveFontResourceW(string file);
    [LibraryImport("user32.dll")] private static partial nint SendMessageTimeoutW(nint h, uint msg, nint w, nint l, uint flags, uint timeout, out nint result);
}
