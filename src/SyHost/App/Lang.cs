// =====================================================================
//  SyHost - Dil / Language / 言語
//  Metinler Türkçe anahtarla yazılır: L("Sunucu açılıyor"). Seçili dil
//  İngilizce ya da Japonca ise tablodaki karşılığı döner.
//  Yeni ekranların metinleri ayrı dosyalarda AddXxx() içinde eklenir.
// =====================================================================
namespace SyHost;

static partial class Lang
{
    /// <summary>Desteklenen diller, sırası L tuşuyla dolaşılan sıradır (en → tr → ja).</summary>
    public static readonly (string Code, string Name)[] Languages =
    {
        ("en", "English"),
        ("tr", "Türkçe"),
        ("ja", "日本語"),
    };

    /// <summary>Seçili dil: en (varsayılan), tr, ja.</summary>
    public static string Code = "en";

    // Anahtar büyük-küçük harfe duyarlı: Terminal sürümündeki "NORMAL"/"Normal" çakışması burada olmaz
    static readonly Dictionary<string, (string En, string Ja)> Table = new(StringComparer.Ordinal);

    static Lang()
    {
        AddCore();
        AddFirstRun();
        AddSettings();
        AddUninstall();
        AddPortable();
        AddExtra();
    }

    // Yeni ekranların metinleri (her biri kendi dosyasında)
    static partial void AddFirstRun();
    static partial void AddSettings();
    static partial void AddUninstall();
    static partial void AddPortable();
    static partial void AddExtra();

    static void Tx(string tr, string en, string ja) => Table[tr] = (en, ja);

    /// <summary>Bu kodla bir dil var mı?</summary>
    public static bool Has(string code)
    {
        foreach (var l in Languages) if (l.Code == code) return true;
        return false;
    }

    /// <summary>Dilin görünen adı (English, Türkçe, 日本語).</summary>
    public static string NameOf(string code)
    {
        foreach (var l in Languages) if (l.Code == code) return l.Name;
        return code;
    }

    /// <summary>Metni seçili dile çevir. {0} {1} gibi yer tutucular ek argümanlarla doldurulur.</summary>
    public static string L(string key, params object[] args)
    {
        string t = key;
        if (Code != "tr" && key != null && Table.TryGetValue(key, out var e))
        {
            t = Code == "ja" ? e.Ja : e.En;
            if (string.IsNullOrEmpty(t)) t = e.En;
        }
        if (args != null && args.Length > 0) return Ps.F(t, args);
        return t;
    }

    /// <summary>Belirli bir dildeki karşılık (dil ekranında her dili kendi adıyla göstermek için).</summary>
    public static string In(string code, string key)
    {
        if (code == "tr" || key == null || !Table.TryGetValue(key, out var e)) return key;
        string t = code == "ja" ? e.Ja : e.En;
        return string.IsNullOrEmpty(t) ? e.En : t;
    }

    /// <summary>Tablodaki bütün anahtarlar (üç dilin eksiksiz olduğunu denetleyen test için).</summary>
    public static IEnumerable<KeyValuePair<string, (string En, string Ja)>> All => Table;
}
