// =====================================================================
//  PowerShell davranışını birebir taklit eden küçük yardımcılar.
//  Terminal sürümü (PowerShell 5.1) ile karakteri karakterine aynı ekranı
//  üretmek için şart. Port ederken PowerShell ifadesinin karşılığı:
//    [int]x            -> Ps.Int(x)      (en yakın çifte yuvarlar: 2.5 -> 2, 3.5 -> 4)
//    $a / $b           -> (double)a / b  (PowerShell bölmesi hep ondalıklıdır)
//    "...$x..."        -> Ps.S(x)        (sayıyı kültürden bağımsız yazar: 1.5)
//    '...' -f a, b     -> Ps.F(...)      (bilgisayarın kültürüyle yazar: 1,5)
//    ' ' * n           -> Ps.Rep(" ", n)
//    -eq / -ne (metin) -> Ps.Eq(a, b)    (büyük-küçük harf duyarsız)
// =====================================================================
using System.Globalization;

namespace SyHost;

static class Ps
{
    public static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    /// <summary>PowerShell [int] dönüşümü: banker yuvarlaması (MidpointRounding.ToEven).</summary>
    public static int Int(double x) => checked((int)Math.Round(x, MidpointRounding.ToEven));

    /// <summary>PowerShell [long] dönüşümü.</summary>
    public static long Long(double x) => checked((long)Math.Round(x, MidpointRounding.ToEven));

    /// <summary>' ' * n : n sıfır ya da eksiyse boş metin.</summary>
    public static string Rep(string s, int n)
    {
        if (n <= 0 || string.IsNullOrEmpty(s)) return "";
        if (s.Length == 1) return new string(s[0], n);
        var sb = new System.Text.StringBuilder(s.Length * n);
        for (int i = 0; i < n; i++) sb.Append(s);
        return sb.ToString();
    }

    /// <summary>' ' * 3.7 gibi ondalıklı tekrar sayısı: PowerShell önce [int]'e çevirir.</summary>
    public static string Rep(string s, double n) => Rep(s, Int(n));

    public static string Rep(char c, int n) => n <= 0 ? "" : new string(c, n);

    /// <summary>"$x" içindeki ondalık sayı: Windows PowerShell 5.1 (.NET Framework) "G" = 15 basamak, kültürden bağımsız.</summary>
    public static string S(double x) => x.ToString("G15", Inv);

    public static string S(int x) => x.ToString(Inv);

    public static string S(long x) => x.ToString(Inv);

    /// <summary>
    /// '...' -f args: bilgisayarın kültürüyle biçimlendirir. Biçimsiz {0} içindeki ondalık sayılar
    /// .NET Framework gibi 15 basamakla yazılır.
    /// </summary>
    public static string F(string fmt, params object[] args)
    {
        if (args != null)
        {
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] is double d) args[i] = new PsDouble(d);
                else if (args[i] is float f) args[i] = new PsDouble(f);
            }
        }
        return string.Format(CultureInfo.CurrentCulture, fmt, args ?? Array.Empty<object>());
    }

    /// <summary>PowerShell -eq (metin): büyük-küçük harf duyarsız.</summary>
    public static bool Eq(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

    /// <summary>PowerShell -in / -contains (metin).</summary>
    public static bool In(string a, params string[] set)
    {
        foreach (var s in set) if (Eq(a, s)) return true;
        return false;
    }

    /// <summary>PowerShell doğruluk değeri: null, boş metin, 0 ve false yanlıştır.</summary>
    public static bool Truthy(object o) => o switch
    {
        null => false,
        bool b => b,
        string s => s.Length > 0,
        int i => i != 0,
        long l => l != 0,
        double d => d != 0,
        System.Collections.ICollection c => c.Count > 0,
        _ => true
    };

    readonly struct PsDouble : IFormattable
    {
        readonly double v;
        public PsDouble(double v) { this.v = v; }
        public string ToString(string format, IFormatProvider provider)
            => string.IsNullOrEmpty(format) ? v.ToString("G15", provider) : v.ToString(format, provider);
        public override string ToString() => v.ToString("G15", CultureInfo.CurrentCulture);
    }
}
