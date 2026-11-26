// =====================================================================
//  SyHost - eski verilerin taşınması
//  0.5.0 ayarları, sunucu listesini ve playit anahtarını %LOCALAPPDATA%\SyHost'ta
//  tutuyordu. Yeni SyHost ilk açılışta bunları bir kez kendi Data klasörüne KOPYALAR.
//  - Eski klasör asla silinmez. İçine yalnızca "veriler şuraya taşındı" notu bırakılır.
//  - Not varken başka bir kopya açılırsa önce sorulur (aynı playit anahtarını iki kopya
//    kullanırsa aynı tünel için çakışırlar).
//  - Sunucu klasörlerine dokunulmaz, yolları aynen kalır.
//  Test için SYHOST_LEGACY_DATA ortam değişkeni eski klasörü bir kopyaya yönlendirir.
// =====================================================================
using System.Text;

namespace SyHost;

static class Migration
{
    public const string NoteName = "SyHost-TASINDI.txt";
    static readonly string[] Files = { "ayarlar.json", "sunucular.json", "pencere.json", "playit.toml", "playit.log" };

    /// <summary>Eski veri klasörü (0.5.0).</summary>
    public static string LegacyDir()
    {
        string t = Environment.GetEnvironmentVariable("SYHOST_LEGACY_DATA");
        return !string.IsNullOrEmpty(t) ? t : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SyHost");
    }

    /// <summary>Taşınacak eski veri var mı?</summary>
    public static bool HasLegacyData()
    {
        string d = LegacyDir();
        return File.Exists(Path.Combine(d, "sunucular.json")) || File.Exists(Path.Combine(d, "ayarlar.json"));
    }

    /// <summary>Bu Data klasörü henüz boş mu (sunucu listesi yok)?</summary>
    public static bool DataIsFresh(string dataDir) => !File.Exists(Path.Combine(dataDir, "sunucular.json"));

    /// <summary>Eski veriler daha önce başka bir yere taşınmışsa o yer (not dosyasından), yoksa null.</summary>
    public static string MovedTo()
    {
        try
        {
            string note = Path.Combine(LegacyDir(), NoteName);
            if (!File.Exists(note)) return null;
            foreach (string line in File.ReadAllLines(note, Encoding.UTF8))
                if (line.StartsWith("path=", StringComparison.Ordinal)) return line.Substring(5).Trim();
        }
        catch { }
        return "?";
    }

    public sealed class Result
    {
        public List<string> Copied = new();
        public int Servers;
        public bool Playit;
    }

    /// <summary>
    /// Eski verileri Data klasörüne kopyala. lang: ilk açılışta seçilen dil (ayarlara yazılır).
    /// Eski klasöre taşındığını anlatan not bırakılır.
    /// </summary>
    public static Result Copy(string dataDir, string root, string lang)
    {
        var r = new Result();
        string src = LegacyDir();
        Directory.CreateDirectory(dataDir);
        foreach (string f in Files)
        {
            string from = Path.Combine(src, f);
            if (!File.Exists(from)) continue;
            File.Copy(from, Path.Combine(dataDir, f), true);
            r.Copied.Add(f);
        }
        // Ayarlar: eski ayarlar korunur, yalnızca seçilen dil ve kurulum bilgisi eklenir
        string cfg = Path.Combine(dataDir, "ayarlar.json");
        if (File.Exists(cfg))
        {
            try
            {
                var s = Json.ReadSettings(cfg);
                if (!string.IsNullOrEmpty(lang)) s.dil = lang;
                s.kurulumTamam ??= false;
                Json.WriteText(cfg, Json.WriteSettings(s));
            }
            catch { }
        }
        try { r.Servers = Json.ParseServers(Json.ReadText(Path.Combine(dataDir, "sunucular.json"))).Count; } catch { }
        r.Playit = File.Exists(Path.Combine(dataDir, "playit.toml"));
        WriteNote(src, root);
        return r;
    }

    static void WriteNote(string legacy, string root)
    {
        try
        {
            string when = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
            var sb = new StringBuilder();
            sb.Append("path=").Append(root).Append("\r\n");
            sb.Append("date=").Append(when).Append("\r\n\r\n");
            sb.Append("Bu klasördeki SyHost verileri şuraya kopyalandı: ").Append(root).Append(" (").Append(when).Append(").\r\n");
            sb.Append("Yeni SyHost artık oradakileri kullanıyor. Bu klasörü silmek istersen SyHost'un Ayarlar > SyHost'u kaldır bölümünden silebilirsin.\r\n\r\n");
            sb.Append("The SyHost data in this folder was copied to: ").Append(root).Append(" (").Append(when).Append(").\r\n");
            sb.Append("The new SyHost uses that copy now. You can remove this folder from SyHost: Settings > Uninstall SyHost.\r\n\r\n");
            sb.Append("このフォルダーの SyHost データは次の場所にコピーされました: ").Append(root).Append("（").Append(when).Append("）。\r\n");
            sb.Append("新しい SyHost はそちらを使用しています。このフォルダーは SyHost の「設定」>「SyHost をアンインストール」から削除できます。\r\n");
            File.WriteAllText(Path.Combine(legacy, NoteName), sb.ToString(), new UTF8Encoding(true));
        }
        catch { }
    }
}
