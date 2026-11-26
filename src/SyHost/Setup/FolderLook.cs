// =====================================================================
//  SyHost - klasörlerin Explorer'daki görünümü
//  desktop.ini ile her klasöre kendi simgesi ve seçilen dilde adı verilir.
//  Diskteki ad hiç değişmez ("Servers"), yalnızca görünen ad değişir; böylece
//  dil değişince hiçbir yol bozulmaz. Simge yolları görelidir: klasör taşınsa
//  da simgeler yerinde kalır. Her açılışta yeniden yazılır (taşıma ve dil
//  değişikliği kendiliğinden düzelir). Yalnızca SyHost klasörünün İÇİNE yazılır.
// =====================================================================
using System.Runtime.InteropServices;
using System.Text;

namespace SyHost;

static partial class FolderLook
{
    // Exe'ye gömülü simgeler (Assets\icons\*.ico) Data\icons içine çıkarılır
    static readonly string[] IconNames = { "folder-syhost.ico", "folder-servers.ico", "folder-server.ico", "folder-backups.ico" };

    /// <summary>SyHost klasörünün ve içindeki sunucu klasörlerinin görünümünü uygula.</summary>
    public static void Apply(string root, string lang, IEnumerable<string> serverDirs)
    {
        try
        {
            string data = Path.Combine(root, Portable.DataName);
            string icons = Path.Combine(data, "icons");
            Directory.CreateDirectory(icons);
            foreach (string n in IconNames) ExtractIcon(n, Path.Combine(icons, n));
            Portable.HideDir(data);

            Write(root, Path.Combine(icons, "folder-syhost.ico"), null);
            string servers = Path.Combine(root, Portable.ServersName);
            if (Directory.Exists(servers)) Write(servers, Path.Combine(icons, "folder-servers.ico"), Lang.In(lang, "Sunucular"));
            foreach (string dir in serverDirs ?? Enumerable.Empty<string>())
            {
                if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir) || !Portable.IsInside(dir, root)) continue;
                Write(dir, Path.Combine(icons, "folder-server.ico"), null);
                string bak = Path.Combine(dir, "yedekler");
                if (Directory.Exists(bak)) Write(bak, Path.Combine(icons, "folder-backups.ico"), Lang.In(lang, "Yedekler"));
            }
        }
        catch { }
    }

    static void ExtractIcon(string name, string path)
    {
        try
        {
            byte[] b = App.Asset("icons\\" + name) ?? App.Asset("icons/" + name);
            if (b == null) return;
            if (File.Exists(path) && new FileInfo(path).Length == b.Length) return;
            File.WriteAllBytes(path, b);
        }
        catch { }
    }

    /// <summary>Bir klasörün desktop.ini'sini yaz (değişmediyse dokunma).</summary>
    static void Write(string dir, string iconFile, string displayName)
    {
        try
        {
            bool hasIcon = File.Exists(iconFile);
            if (!hasIcon && string.IsNullOrEmpty(displayName)) return;
            var sb = new StringBuilder();
            sb.Append("[.ShellClassInfo]\r\n");
            if (!string.IsNullOrEmpty(displayName)) sb.Append("LocalizedResourceName=").Append(displayName).Append("\r\n");
            if (hasIcon) sb.Append("IconResource=").Append(Path.GetRelativePath(dir, iconFile)).Append(",0\r\n");
            string ini = Path.Combine(dir, "desktop.ini");
            string text = sb.ToString();
            if (File.Exists(ini))
            {
                try { if (File.ReadAllText(ini, Encoding.Unicode) == text) { EnsureAttributes(dir, ini); return; } } catch { }
                File.SetAttributes(ini, FileAttributes.Normal);
            }
            File.WriteAllText(ini, text, Encoding.Unicode);   // UTF-16 + BOM: Japonca adlar için şart
            EnsureAttributes(dir, ini);
            SHChangeNotify(0x00001000, 0x0005 | 0x1000, dir, 0);   // SHCNE_UPDATEDIR, SHCNF_PATHW | SHCNF_FLUSHNOWAIT
        }
        catch { }
    }

    static void EnsureAttributes(string dir, string ini)
    {
        File.SetAttributes(ini, FileAttributes.Hidden | FileAttributes.System);
        var di = new DirectoryInfo(dir);
        if ((di.Attributes & FileAttributes.ReadOnly) == 0) di.Attributes |= FileAttributes.ReadOnly;   // Explorer desktop.ini'yi ancak böyle okur
    }

    [LibraryImport("shell32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial void SHChangeNotify(int eventId, uint flags, string item1, nint item2);
}
