// =====================================================================
//  SyHost - ayar dosyaları
//  ayarlar.json, sunucular.json ve pencere.json Terminal sürümüyle ortak.
//  Alan adları dosyadaki anahtarlarla aynı (Türkçe, küçük harfle başlar).
//  Tanınmayan alanlar Extra'da saklanır, dosya yeniden yazılınca kaybolmaz.
//  Dosyalar UTF-8 (BOM'suz) yazılır.
// =====================================================================
#pragma warning disable IDE1006 // alan adları JSON anahtarlarıyla aynı kalsın
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SyHost;

/// <summary>ayarlar.json</summary>
public sealed class Settings
{
    public string dil { get; set; }
    public string sunucuKokKlasoru { get; set; }
    public string arkadasAdresi { get; set; } = "";
    public string sesAdresi { get; set; } = "";
    public bool playitKullan { get; set; }
    public int maksOyuncu { get; set; } = 5;
    public bool cokerseYenidenBaslat { get; set; } = true;
    public double otomatikYedekSaat { get; set; } = 3;
    public int saklanacakYedek { get; set; } = 10;
    public int yaziTipiBoyutu { get; set; } = 16;
    public Dictionary<string, Pack> paketler { get; set; }
    public bool? paketlerAyarlandi { get; set; }
    [JsonExtensionData] public Dictionary<string, JsonElement> Extra { get; set; }
}

/// <summary>Performans paketi (dusuk / normal / yuksek).</summary>
public sealed class Pack
{
    public string ad { get; set; }
    public int ramMin { get; set; }
    public int ramMax { get; set; }
    public int cekirdek { get; set; }
    public string oncelik { get; set; }
    public string aciklama { get; set; }
    [JsonExtensionData] public Dictionary<string, JsonElement> Extra { get; set; }
}

/// <summary>sunucular.json içindeki bir sunucu.</summary>
public sealed class ServerEntry
{
    public string id { get; set; }
    public string ad { get; set; }
    /// <summary>Dosyada: SyHost klasörünün içindeyse göreli (Servers\Ad), dışındaysa mutlak yol.
    /// Bellekte her zaman mutlak yol tutulur (okurken çözülür, yazarken çevrilir).</summary>
    public string klasor { get; set; }
    public string mc { get; set; }
    public string loader { get; set; }
    public string loaderSurum { get; set; }
    public int java { get; set; }
    public string baslat { get; set; }
    public string paket { get; set; }
    public string eklenme { get; set; }
    public string sonAcilis { get; set; }
    public int? sonBaslatmaSn { get; set; }
    [JsonExtensionData] public Dictionary<string, JsonElement> Extra { get; set; }
}

/// <summary>pencere.json: pencerenin konumu ve modu.</summary>
public sealed class WinState
{
    public string mod { get; set; } = "buyuk";
    public int? buyukX { get; set; }
    public int? buyukY { get; set; }
    public int? kucukX { get; set; }
    public int? kucukY { get; set; }
    public bool ustte { get; set; } = true;
    [JsonExtensionData] public Dictionary<string, JsonElement> Extra { get; set; }
}

[JsonSourceGenerationOptions(WriteIndented = true, PropertyNameCaseInsensitive = true, NumberHandling = JsonNumberHandling.AllowReadingFromString)]
[JsonSerializable(typeof(Settings))]
[JsonSerializable(typeof(List<ServerEntry>))]
[JsonSerializable(typeof(WinState))]
[JsonSerializable(typeof(Dictionary<string, string>))]
[JsonSerializable(typeof(JsonElement))]
internal partial class JsonCtx : JsonSerializerContext { }

/// <summary>JSON okuma/yazma: Türkçe ve Japonca harfler kaçışsız, UTF-8 BOM'suz.</summary>
static class Json
{
    static readonly JsonCtx Ctx = new(new JsonSerializerOptions
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        NumberHandling = JsonNumberHandling.AllowReadingFromString,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    });
    public static readonly UTF8Encoding Utf8NoBom = new(false);

    public static Settings ReadSettings(string path) => JsonSerializer.Deserialize(ReadText(path), Ctx.Settings);
    public static Settings ParseSettings(string json) => JsonSerializer.Deserialize(json, Ctx.Settings);
    public static string WriteSettings(Settings s) => JsonSerializer.Serialize(s, Ctx.Settings);

    public static List<ServerEntry> ParseServers(string json)
    {
        json = json?.Trim();
        if (string.IsNullOrEmpty(json)) return new List<ServerEntry>();
        // Terminal sürümü tek sunucuyu bazen dizi olmadan yazmış olabilir
        if (json.StartsWith("{")) json = "[" + json + "]";
        return JsonSerializer.Deserialize(json, Ctx.ListServerEntry) ?? new List<ServerEntry>();
    }
    public static string WriteServers(List<ServerEntry> list) => JsonSerializer.Serialize(list, Ctx.ListServerEntry);

    public static WinState ParseWin(string json) => JsonSerializer.Deserialize(json, Ctx.WinState);
    public static string WriteWin(WinState w) => JsonSerializer.Serialize(w, Ctx.WinState);

    /// <summary>Dosyayı oku (BOM'lu ya da BOM'suz UTF-8).</summary>
    public static string ReadText(string path) => File.ReadAllText(path, Encoding.UTF8);

    /// <summary>Dosyayı güvenli yaz: önce geçici dosyaya, sonra yerine taşı (yarım kalan dosya olmaz).</summary>
    public static void WriteText(string path, string text)
    {
        string tmp = path + ".tmp";
        File.WriteAllText(tmp, text, Utf8NoBom);
        File.Move(tmp, path, true);
    }
}
