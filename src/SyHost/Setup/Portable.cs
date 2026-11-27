// =====================================================================
//  SyHost - taşınabilir klasör
//  Her şey SyHost klasörünün içinde durur:
//    SyHost\SyHost.exe       görünen tek dosya
//    SyHost\Servers\         yeni sunucuların varsayılan yeri
//    SyHost\Data\  (gizli)   ayarlar, sunucu listesi, playit anahtarı, indirilen Java ve playit
//  Klasör istenen yere taşınabilir; yollar SyHost klasörüne göre hesaplanır.
// =====================================================================
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace SyHost;

static unsafe partial class Portable
{
    public const string DataName = "Data";
    public const string ServersName = "Servers";
    public const string ExeName = "SyHost.exe";

    /// <summary>Önerilen kurulum yeri: C:\Users\&lt;ad&gt;\SyHost (OneDrive'a eşitlenmez).</summary>
    public static string DefaultRoot()
    {
        // Testler varsayılan yeri bir test klasörüne yönlendirebilir
        string t = Environment.GetEnvironmentVariable("SYHOST_DEFAULT_ROOT");
        return !string.IsNullOrEmpty(t) ? t : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "SyHost");
    }

    /// <summary>Bu klasörde kurulu bir SyHost var mı (Data klasörü)?</summary>
    /// <remarks>Yalnızca "Data" klasörü yetmez: ilgisiz bir Data klasörü olan her yer kurulu sayılırdı
    /// (ve o klasör gizlenirdi). SyHost'un kendi dosyalarından biri aranır.</remarks>
    public static bool IsInstalled(string root)
    {
        try { string d = Path.Combine(root, DataName); return File.Exists(Path.Combine(d, "ayarlar.json")) || File.Exists(Path.Combine(d, "sunucular.json")); }
        catch { return false; }
    }

    /// <summary>Windows'un dili: Türkçe ve Japonca dışındakiler için İngilizce.</summary>
    public static string UiLanguage()
    {
        string two = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
        return two == "tr" ? "tr" : two == "ja" ? "ja" : "en";
    }

    /// <summary>
    /// Exe kendi boş klasöründe mi? (yanında yalnızca kendisi var). İndirilenler, Masaüstü, Belgeler,
    /// kullanıcı klasörü ve sürücü kökleri her zaman "boş değil" sayılır: oraya Data/Servers açılmaz.
    /// </summary>
    public static bool IsOwnEmptyFolder(string dir, string exe)
    {
        try
        {
            string full = Path.GetFullPath(dir).TrimEnd('\\');
            if (Path.GetPathRoot(full).TrimEnd('\\').Equals(full, StringComparison.OrdinalIgnoreCase)) return false;
            foreach (string special in SpecialFolders())
                if (!string.IsNullOrEmpty(special) && full.Equals(special.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) return false;
            foreach (string e in Directory.EnumerateFileSystemEntries(full))
            {
                string name = Path.GetFileName(e);
                if (e.Equals(exe, StringComparison.OrdinalIgnoreCase)) continue;
                if (name.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase) || name.Equals("Thumbs.db", StringComparison.OrdinalIgnoreCase)) continue;
                return false;
            }
            return true;
        }
        catch { return false; }
    }

    static IEnumerable<string> SpecialFolders()
    {
        yield return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        yield return Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        yield return Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        yield return Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        yield return Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        yield return Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        yield return Downloads();
    }

    [LibraryImport("shell32.dll")] private static partial int SHGetKnownFolderPath(Guid* id, uint flags, nint token, char** path);
    [LibraryImport("ole32.dll")] private static partial void CoTaskMemFree(void* p);

    /// <summary>İndirilenler klasörü.</summary>
    public static string Downloads()
    {
        var id = new Guid("374DE290-123F-4565-9164-39C4925E467B");
        char* p = null;
        try { if (SHGetKnownFolderPath(&id, 0, 0, &p) == 0 && p != null) return new string(p); }
        catch { }
        finally { if (p != null) CoTaskMemFree(p); }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    }

    /// <summary>Yol OneDrive ile eşitlenen bir klasörde mi?</summary>
    public static bool IsInOneDrive(string path)
    {
        try
        {
            string full = Path.GetFullPath(path).TrimEnd('\\') + "\\";
            foreach (string v in new[] { "OneDrive", "OneDriveConsumer", "OneDriveCommercial" })
            {
                string root = Environment.GetEnvironmentVariable(v);
                if (!string.IsNullOrEmpty(root) && full.StartsWith(root.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase)) return true;
            }
            return System.Text.RegularExpressions.Regex.IsMatch(full, @"\\OneDrive( - [^\\]+)?\\", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        }
        catch { return false; }
    }

    /// <summary>Klasöre yazılabiliyor mu? (Program Files gibi yerlerde hayır.)</summary>
    public static bool CanWrite(string dir)
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

    /// <summary>
    /// SyHost'u bu klasöre kur ya da güncelle: exe'yi kopyalar, Data ve Servers'ı açar, ilk ayarları yazar.
    /// Data ve Servers içindeki dosyalara asla dokunmaz.
    /// </summary>
    public static void InstallTo(string root, string sourceExe, string lang)
    {
        Directory.CreateDirectory(root);
        string data = Path.Combine(root, DataName);
        Directory.CreateDirectory(data);
        Directory.CreateDirectory(Path.Combine(root, ServersName));
        string target = Path.Combine(root, ExeName);
        if (!string.Equals(Path.GetFullPath(sourceExe), Path.GetFullPath(target), StringComparison.OrdinalIgnoreCase))
            CopyExe(sourceExe, target);
        string cfg = Path.Combine(data, "ayarlar.json");
        if (!File.Exists(cfg))
        {
            var s = Json.ParseSettings(Encoding.UTF8.GetString(App.Asset("default-settings.json")));
            s.dil = lang;
            s.kurulumTamam = false;
            Json.WriteText(cfg, Json.WriteSettings(s));
        }
        HideDir(data);
    }

    /// <summary>Exe'yi kopyala: önce geçici dosyaya, sonra yerine (yarım dosya kalmasın).</summary>
    public static void CopyExe(string source, string target)
    {
        string tmp = target + ".yeni";
        File.Copy(source, tmp, true);
        try { File.Move(tmp, target, true); }
        catch { try { File.Delete(tmp); } catch { } throw; }   // hedef açıksa yanında yarım kopya kalmasın
    }

    public static void HideDir(string dir)
    {
        try
        {
            var di = new DirectoryInfo(dir);
            if ((di.Attributes & FileAttributes.Hidden) == 0) di.Attributes |= FileAttributes.Hidden;
        }
        catch { }
    }

    /// <summary>Bir yol SyHost klasörünün içinde mi?</summary>
    public static bool IsInside(string path, string root)
    {
        try
        {
            string p = Path.GetFullPath(path).TrimEnd('\\') + "\\";
            string r = Path.GetFullPath(root).TrimEnd('\\') + "\\";
            return p.StartsWith(r, StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    [LibraryImport("user32.dll", EntryPoint = "MessageBoxW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int MessageBox(nint h, string text, string caption, uint type);

    /// <summary>Konsol açılmadan önce gösterilen düz Windows uyarısı (ör. klasöre yazılamıyor).</summary>
    public static void Alert(string text) => MessageBox(Native.GetConsoleWindow(), text, "SyHost", 0x30 | 0x10000);
}
