// =====================================================================
//  SyHost - Cascadia Mono yazı tipi
//  Logonun ve animasyonların doğru görünmesi için gerekir. Bilgisayarda yoksa
//  yönetici izni istemeden YALNIZCA bu kullanıcıya kurulur
//  (%LOCALAPPDATA%\Microsoft\Windows\Fonts + HKCU). Konsol bunu kabul ediyor
//  (denendi: SetCurrentConsoleFontEx ile Cascadia ailesi kullanıcıya kurulu
//  hâlde seçilebiliyor). Kaldırırken yalnızca SyHost'un kurduğu dosyalar silinir.
//  Yazı tipi lisansı: SIL Open Font License 1.1 (exe içinde fonts\OFL.txt).
// =====================================================================
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace SyHost;

static partial class Fonts
{
    public const string Face = "Cascadia Mono";
    const string RegPath = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts";
    static readonly (string File, string Value)[] Files =
    {
        ("CascadiaMono-Regular.ttf", "Cascadia Mono Regular (TrueType)"),
        ("CascadiaMono-Bold.ttf", "Cascadia Mono Bold (TrueType)"),
    };

    static string UserFontDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\Windows\Fonts");
    static string OurFile(string f) => Path.Combine(UserFontDir, "SyHost-" + f);

    /// <summary>Cascadia Mono bu bilgisayarda (sistemde ya da kullanıcıda) kurulu mu?</summary>
    public static bool IsAvailable()
    {
        return HasValue(Registry.LocalMachine) || HasValue(Registry.CurrentUser);
        static bool HasValue(RegistryKey hive)
        {
            try
            {
                using var k = hive.OpenSubKey(RegPath);
                if (k == null) return false;
                foreach (string n in k.GetValueNames()) if (n.StartsWith(Face + " ", StringComparison.OrdinalIgnoreCase) || n.Equals(Face, StringComparison.OrdinalIgnoreCase)) return true;
            }
            catch { }
            return false;
        }
    }

    /// <summary>SyHost'un kendi kurduğu kullanıcı yazı tipi duruyor mu?</summary>
    public static bool InstalledBySyHost() => File.Exists(OurFile(Files[0].File));

    /// <summary>Yazı tipini yalnızca bu kullanıcıya kur (yönetici izni gerekmez).</summary>
    public static bool InstallPerUser()
    {
        try
        {
            Directory.CreateDirectory(UserFontDir);
            using var k = Registry.CurrentUser.CreateSubKey(RegPath);
            foreach (var (file, value) in Files)
            {
                byte[] b = App.Asset("fonts\\" + file);
                if (b == null) return false;
                string path = OurFile(file);
                if (!File.Exists(path) || new FileInfo(path).Length != b.Length) File.WriteAllBytes(path, b);
                k.SetValue(value, path, RegistryValueKind.String);
                AddFontResourceW(path);
            }
            Broadcast();
            return IsAvailable();
        }
        catch { return false; }
    }

    /// <summary>SyHost'un kurduğu kullanıcı yazı tipini kaldır.</summary>
    public static bool UninstallPerUser()
    {
        bool ok = true;
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(RegPath, true);
            foreach (var (file, value) in Files)
            {
                string path = OurFile(file);
                for (int i = 0; i < 8 && RemoveFontResourceW(path); i++) { }
                try
                {
                    if (k != null && k.GetValue(value) is string v && v.Equals(path, StringComparison.OrdinalIgnoreCase)) k.DeleteValue(value, false);
                }
                catch { ok = false; }
            }
            Broadcast();
            foreach (var (file, _) in Files)
            {
                string path = OurFile(file);
                for (int i = 0; i < 10 && File.Exists(path); i++) { try { File.Delete(path); } catch { Thread.Sleep(300); } }
                if (File.Exists(path)) ok = false;
            }
        }
        catch { ok = false; }
        return ok;
    }

    static void Broadcast() { try { SendMessageTimeoutW(0xffff, 0x001D, 0, 0, 2, 1000, out _); } catch { } }

    [LibraryImport("gdi32.dll", StringMarshalling = StringMarshalling.Utf16)] private static partial int AddFontResourceW(string file);
    [LibraryImport("gdi32.dll", StringMarshalling = StringMarshalling.Utf16)] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool RemoveFontResourceW(string file);
    [LibraryImport("user32.dll")] private static partial nint SendMessageTimeoutW(nint h, uint msg, nint w, nint l, uint flags, uint timeout, out nint result);
}
