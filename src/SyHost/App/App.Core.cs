// =====================================================================
//  SyHost - ortak çizim araçları, animasyonlar, logo, gökyüzü,
//  açılış/kapanış ekranları, pencere modu ve kare çizimi.
//  legacy/src/SyHost.ps1'deki aynı adlı fonksiyonların birebir karşılığı.
// =====================================================================
using System.Text;

namespace SyHost;

sealed partial class App
{
    // ---------- Renkler ve metin ----------
    static string Rgb(int cr, int cg, int cb) => $"{E}[38;2;{cr};{cg};{cb}m";

    static int CharW(char ch) => (ch >= 0x1100 && WideRx.IsMatch(ch.ToString())) ? 2 : 1;

    static int VLen(string str)
    {
        string plain = AnsiRx.Replace(str ?? "", "");
        return plain.Length + WideRx.Matches(plain).Count;
    }

    static string Cut(string str, int w)
    {
        var sb = new StringBuilder(); int n = 0, i = 0;
        while (i < str.Length && n < w)
        {
            if (str[i] == '\u001b')
            {
                var m = AnsiRx.Match(str, i);
                if (m.Success && m.Index == i) { sb.Append(m.Value); i += m.Length; continue; }
            }
            int cw = CharW(str[i]);
            if (n + cw > w) break;
            sb.Append(str[i]); n += cw; i++;
        }
        sb.Append(R);
        if (n < w) sb.Append(' ', w - n);
        return sb.ToString();
    }

    static string PadV(string str, int w)
    {
        str ??= "";
        int l = VLen(str);
        if (l < w) return str + R + Ps.Rep(" ", w - l);
        if (l > w) return Cut(str, w);
        return str + R;
    }

    static List<string> WordWrap(string text, int w)
    {
        text ??= "";
        if (WideRx.IsMatch(text)) return WordWrapWide(text, w);
        var outp = new List<string>(); string line = "";
        foreach (string word in text.Split(' '))
        {
            if (line.Length == 0) line = word;
            else if (line.Length + 1 + word.Length <= w) line += " " + word;
            else { outp.Add(line); line = word; }
        }
        if (line.Length > 0) outp.Add(line);
        return outp;
    }

    // Kapanış noktalaması satır başına düşmez, önündeki karaktere yapışır
    const string WideClosers = "、。，．）」』】〉》！？：；ー";

    /// <summary>
    /// Geniş (Japonca vb.) karakter içeren metni ekran genişliğine göre böl: kelimeler boşluktan,
    /// geniş karakterler tek tek bölünebilir (Japoncada kelime arası boşluk yok). Genişlik sütun sayısıdır.
    /// </summary>
    static List<string> WordWrapWide(string text, int w)
    {
        var outp = new List<string>(); var line = new StringBuilder(); int lw = 0, i = 0; bool space = false;
        while (i < text.Length)
        {
            char ch = text[i];
            if (ch == ' ') { space = true; i++; continue; }
            int s = i;
            if (CharW(ch) == 2) { i++; while (i < text.Length && WideClosers.IndexOf(text[i]) >= 0) i++; }
            else { while (i < text.Length && text[i] != ' ' && CharW(text[i]) == 1) i++; }
            string seg = text.Substring(s, i - s);
            int sw = VLen(seg);
            if (lw > 0 && lw + (space ? 1 : 0) + sw > w) { outp.Add(line.ToString()); line.Clear(); lw = 0; }
            else if (lw > 0 && space) { line.Append(' '); lw++; }
            line.Append(seg); lw += sw; space = false;
        }
        if (lw > 0) outp.Add(line.ToString());
        return outp;
    }

    /// <summary>Düz metni tam w sütuna sığdır: uzunsa kes (geniş karakter yarıda kalmaz), kısaysa boşlukla doldur.</summary>
    static string FitV(string s, int w)
    {
        s ??= "";
        var sb = new StringBuilder(); int n = 0;
        foreach (char ch in s) { int cw = CharW(ch); if (n + cw > w) break; sb.Append(ch); n += cw; }
        return sb.Append(' ', w - n).ToString();
    }

    /// <summary>Düz metnin sondan en çok w sütunluk kısmı (yazılan komutun görünen yeri).</summary>
    static string TailByWidth(string s, int w)
    {
        s ??= ""; int n = 0, i = s.Length;
        while (i > 0) { int cw = CharW(s[i - 1]); if (n + cw > w) break; n += cw; i--; }
        return s.Substring(i);
    }

    /// <summary>Düz metni en çok w sütunluk parçalara böl (geniş karakter 2 sütun).</summary>
    static List<string> SplitByWidth(string s, int w)
    {
        var outp = new List<string>(); var sb = new StringBuilder(); int n = 0;
        foreach (char ch in s ?? "")
        {
            int cw = CharW(ch);
            if (n + cw > w && n > 0) { outp.Add(sb.ToString()); sb.Clear(); n = 0; }
            sb.Append(ch); n += cw;
        }
        if (sb.Length > 0) outp.Add(sb.ToString());
        return outp;
    }

    static string Pill(string bg, string fg, string text) => $"{E}[48;2;{bg}m{E}[38;2;{fg}m{E}[1m {text} {R}";

    static readonly System.Globalization.CultureInfo TrCulture = System.Globalization.CultureInfo.GetCultureInfo("tr-TR");
    static string Norm(string str)
    {
        str = (str ?? "").ToLower(TrCulture);
        return str.Replace('ı', 'i').Replace('ş', 's').Replace('ğ', 'g').Replace('ü', 'u').Replace('ö', 'o').Replace('ç', 'c');
    }

    // ---------- Zaman (test modunda dondurulur) ----------
    public double T() => TestMode ? TestT : Clock.Elapsed.TotalSeconds;
    public DateTime Now() => TestMode ? TestNow : DateTime.Now;

    // ---------- Animasyon araçları ----------
    string Spin(double speed = 12) => SpinFrames[Ps.Int(T() * speed) % SpinFrames.Length].ToString();

    string Pulse() => PulseFrames[Ps.Int(T() * 7) % PulseFrames.Length];

    // Parıltı: metnin üzerinden ışık geçer
    string Shimmer(string text, int[] bas, int[] hi, double speed = 16, double width = 4)
    {
        int len = text.Length;
        if (len == 0) return "";
        double center = ((T() * speed) % (len + 14)) - 7;
        var sb = new StringBuilder();
        for (int i = 0; i < len; i++)
        {
            double k = Math.Max(0.0, 1.0 - Math.Abs(i - center) / width);
            int cr = Ps.Int(bas[0] + (hi[0] - bas[0]) * k), cg = Ps.Int(bas[1] + (hi[1] - bas[1]) * k), cb = Ps.Int(bas[2] + (hi[2] - bas[2]) * k);
            sb.Append(E).Append("[38;2;").Append(cr).Append(';').Append(cg).Append(';').Append(cb).Append('m').Append(text[i]);
        }
        sb.Append(R);
        return sb.ToString();
    }

    string Verb() => Verbs[Ps.Int(T() / 2.6) % Verbs.Length];

    string BarP(double pct, int w)
    {
        if (pct < 0) pct = 0; if (pct > 100) pct = 100;
        int fill = Ps.Int(Math.Round(pct / 100 * w));
        var sb = new StringBuilder();
        int head = Ps.Int(T() * 14) % Math.Max(1, w + 6);
        for (int i = 0; i < w; i++)
        {
            if (i < fill)
            {
                double k = Math.Max(0.0, 1.0 - Math.Abs(i - head) / 3.0);
                int cr = Ps.Int(200 + 55 * k), cg = Ps.Int(30 + 225 * k), cb = Ps.Int(42 + 213 * k);
                sb.Append(E).Append("[38;2;").Append(cr).Append(';').Append(cg).Append(';').Append(cb).Append("m▰");
            }
            else sb.Append(c.dark).Append('▱');
        }
        sb.Append(R);
        return sb.ToString();
    }

    string Bar(double f, int w)
    {
        if (f < 0) f = 0; if (f > 1) f = 1;
        int n = Ps.Int(Math.Round(f * w));
        string col = f < 0.6 ? c.green : f < 0.85 ? c.yellow : c.red;
        return col + Ps.Rep("█", n) + c.dark + Ps.Rep("░", w - n) + R;
    }

    // ---------- Logo: kırmızı-beyaz dalga sürekli akar, ara ara parlar ve "glitch" yapar ----------
    List<string> RenderLogo(double reveal = 1.0, double shine = -100)
    {
        var rows = new List<string>();
        double now = T();
        if (now > GlitchNext)
        {
            GlitchUntil = now + 0.18; GlitchNext = now + 3.5 + Rnd.NextDouble() * 4; GlitchRows = new Dictionary<int, int>();
            for (int gr = 0; gr <= 5; gr++) if (Rnd.NextDouble() < 0.45) GlitchRows[gr] = Rnd.Next(-3, 4);
        }
        bool glitch = now < GlitchUntil;
        double edge = reveal * (LogoW + 4);
        for (int r0 = 0; r0 < 6; r0++)
        {
            var sb = new StringBuilder(); string line = LogoPlain[r0];
            int shift = glitch && GlitchRows.ContainsKey(r0) ? GlitchRows[r0] : 0;
            if (shift > 0) sb.Append(' ', shift);
            int startI = shift < 0 ? -shift : 0;
            for (int i = startI; i < line.Length; i++)
            {
                char ch = line[i];
                if (ch == ' ' || i > edge) { sb.Append(' '); continue; }
                // akan dalga: 0..1
                double wave = (Math.Sin((i / 7.0) - now * 2.6 + r0 * 0.35) + 1) / 2;
                double cr, cg, cb;
                if (ch == '█') { cr = 175 + 80 * wave; cg = 18 + 70 * Math.Pow(wave, 3); cb = 30 + 70 * Math.Pow(wave, 3); }
                else { cr = 70 + 40 * wave; cg = 14; cb = 20; }
                double k = 0.0;
                if (edge - i < 3 && reveal < 1) k = 1 - (edge - i) / 3;
                double d = Math.Abs((i - r0 * 0.8) - shine); if (d < 5) k = Math.Max(k, 1 - d / 5);
                if (glitch && GlitchRows.ContainsKey(r0)) k = Math.Max(k, 0.55);
                int ir = Ps.Int(cr + (255 - cr) * k), ig = Ps.Int(cg + (255 - cg) * k), ib = Ps.Int(cb + (255 - cb) * k);
                sb.Append(E).Append("[38;2;").Append(ir).Append(';').Append(ig).Append(';').Append(ib).Append('m').Append(ch);
            }
            sb.Append(R); rows.Add(sb.ToString());
        }
        return rows;
    }

    double LogoShine() { double p = T() % 4.5; if (p < 1.3) return (p / 1.3) * (LogoW + 16) - 8; return -100; }

    // ---------- Çizim: ortak ----------
    List<string> Card(string title, IList<string> lines, int w)
    {
        string bc = c.dark;
        string top = bc + "╭─ " + R + Bo + c.brass + title + R + " " + bc + Ps.Rep("─", Math.Max(0, w - VLen(title) - 5)) + "╮" + R;
        var outp = new List<string> { top };
        foreach (string l in lines) outp.Add(bc + "│" + R + " " + PadV(l, w - 4) + " " + bc + "│" + R);
        outp.Add(bc + "╰" + Ps.Rep("─", w - 2) + "╯" + R);
        return outp;
    }

    static string FmtDur(TimeSpan t) => Ps.F("{0:00}:{1:00}:{2:00}", (int)Math.Floor(t.TotalHours), t.Minutes, t.Seconds);

    string FmtWhen(string when)
    {
        if (string.IsNullOrEmpty(when)) return Lang.L("hiç açılmadı");
        DateTime d;
        try { d = DateTime.ParseExact(when, "yyyy-MM-dd HH:mm", null); } catch { return when; }
        if (d.Date == Now().Date) return Lang.L("bugün ") + d.ToString("HH:mm");
        if (d.Date == Now().Date.AddDays(-1)) return Lang.L("dün ") + d.ToString("HH:mm");
        return d.ToString("dd.MM.yyyy");
    }

    string Rule(string label, int W, string extra = "")
    {
        extra ??= "";
        int n = Math.Max(0, W - VLen(label) - 4 - VLen(extra));
        double pos = ((T() * 38) % Math.Max(1, n + 24)) - 12;
        var sb = new StringBuilder();
        for (int i = 0; i < n; i++)
        {
            double k = Math.Max(0.0, 1.0 - Math.Abs(i - pos) / 10.0);
            int cr = Ps.Int(58 + 197 * k), cg = Ps.Int(58 - 18 * k), cb = Ps.Int(64 - 14 * k);
            sb.Append(E).Append("[38;2;").Append(cr).Append(';').Append(cg).Append(';').Append(cb).Append("m─");
        }
        return c.dark + "── " + R + Bo + Shimmer(label, new[] { 239, 55, 66 }, new[] { 255, 255, 255 }, 9, 3) + R + " " + sb.ToString() + R + extra;
    }

    string Key(string key, string what) => c.brass + key + R + c.dim + " " + what + "  " + R;

    // ---------- Çizim: açılış ----------
    // Tek bir logo satırını renklendir: k = beyazlık (0..1), fade = karartma (0..1)
    string ColorLogoLine(string line, int r0, double k, double fade = 0)
    {
        var sb = new StringBuilder();
        double now = T();
        for (int i = 0; i < line.Length; i++)
        {
            char ch = line[i];
            if (ch == ' ') { sb.Append(' '); continue; }
            double wave = (Math.Sin((i / 7.0) - now * 2.6 + r0 * 0.35) + 1) / 2;
            double cr, cg, cb;
            if (ch == '█') { cr = 175 + 80 * wave; cg = 18 + 70 * Math.Pow(wave, 3); cb = 30 + 70 * Math.Pow(wave, 3); }
            else { cr = 70 + 40 * wave; cg = 14; cb = 20; }
            cr = cr + (255 - cr) * k; cg = cg + (255 - cg) * k; cb = cb + (255 - cb) * k;
            int ir = Ps.Int(cr + (24 - cr) * fade), ig = Ps.Int(cg + (24 - cg) * fade), ib = Ps.Int(cb + (28 - cb) * fade);
            sb.Append(E).Append("[38;2;").Append(ir).Append(';').Append(ig).Append(';').Append(ib).Append('m').Append(ch);
        }
        sb.Append(R);
        return sb.ToString();
    }

    List<string> RenderLogoDrop(double el)
    {
        var rows = new List<string>();
        double landAll = 5 * 0.11 + 0.38;
        double flash = el > landAll ? Math.Max(0.0, 1.0 - (el - landAll) / 0.45) : 0.0;
        double shine = (el > landAll + 0.25 && el < landAll + 1.4) ? ((el - landAll - 0.25) / 1.15) * (LogoW + 16) - 8 : -100;
        for (int r0 = 0; r0 < 6; r0++)
        {
            var line = new StringBuilder();
            var ks = new List<double>();
            for (int L = 0; L < 6; L++)
            {
                string[] glyph = LogoFont[LogoLetters[L]]; int wd = glyph[0].Length;
                double pp = Math.Min(1.0, Math.Max(0.0, (el - L * 0.11) / 0.38));
                double ease = 1 - Math.Pow(1 - pp, 3);
                int off = Ps.Int(Math.Round((1 - ease) * 7));
                int src = r0 - off;
                string seg = (pp > 0 && src >= 0 && src <= 5) ? glyph[src] : Ps.Rep(" ", wd);
                // harf inerken beyaz, indikten sonra kırmızıya döner
                double land = Math.Max(0.0, 1.0 - Math.Max(0.0, el - (L * 0.11 + 0.38)) / 0.3);
                double kk = pp < 1 ? 0.85 : 0.85 * land;
                for (int q = 0; q < wd; q++) ks.Add(kk);
                line.Append(seg);
            }
            var sb = new StringBuilder();
            double now = T();
            string ln = line.ToString();
            for (int i = 0; i < ln.Length; i++)
            {
                char ch = ln[i];
                if (ch == ' ') { sb.Append(' '); continue; }
                double wave = (Math.Sin((i / 7.0) - now * 2.6 + r0 * 0.35) + 1) / 2;
                double cr, cg, cb;
                if (ch == '█') { cr = 175 + 80 * wave; cg = 18 + 70 * Math.Pow(wave, 3); cb = 30 + 70 * Math.Pow(wave, 3); }
                else { cr = 70 + 40 * wave; cg = 14; cb = 20; }
                double k = Math.Max(ks[i], flash * 0.7);
                double d = Math.Abs((i - r0 * 0.8) - shine); if (d < 5) k = Math.Max(k, 1 - d / 5);
                int ir = Ps.Int(cr + (255 - cr) * k), ig = Ps.Int(cg + (255 - cg) * k), ib = Ps.Int(cb + (255 - cb) * k);
                sb.Append(E).Append("[38;2;").Append(ir).Append(';').Append(ig).Append(';').Append(ib).Append('m').Append(ch);
            }
            sb.Append(R); rows.Add(sb.ToString());
        }
        return rows;
    }

    // ---------- Gökyüzü: rastgele kayan yıldızlar (meteorlar) + hafif yanıp sönen yıldızlar ----------
    void UpdateSky(int W, int H, double perSec, int maxN, bool twinkle, double bright = 1.0)
    {
        double now = T();
        double dt = Math.Min(0.15, Math.Max(0.0, now - MeteorLastT)); MeteorLastT = now;
        TwinkleOn = twinkle;
        // arka plandaki yıldızlar (ekran boyutu değişince yeniden dağıt)
        string size = W + "," + H;
        if (twinkle && StarsSize != size)
        {
            Stars = new Dictionary<int, List<(int, double)>>(); StarsSize = size;
            int count = Ps.Int(W * H * 0.010);
            for (int i = 0; i < count; i++)
            {
                int ry = Rnd.Next(0, H);
                if (!Stars.ContainsKey(ry)) Stars[ry] = new List<(int, double)>();
                int col = Rnd.Next(0, W);
                Stars[ry].Add((col, Rnd.NextDouble() * 100));
            }
        }
        // yeni meteor: rastgele aralıklarla (üstel dağılım)
        if (perSec > 0 && now >= MeteorNextSpawn)
        {
            if (Meteors.Count < maxN)
            {
                int dir = Rnd.NextDouble() < 0.7 ? -1 : 1;
                double vy = 7 + Rnd.NextDouble() * 9;
                var m = new Meteor();
                m.x = Rnd.Next(Ps.Int(W * 0.1), W + 10);
                m.y = Rnd.Next(-2, Ps.Int(Math.Max(1, H * 0.45)));
                m.vx = dir * vy * (1.8 + Rnd.NextDouble() * 1.2); m.vy = vy; m.len = Rnd.Next(5, 12);
                m.age = 0.0; m.life = 0.7 + Rnd.NextDouble() * 1.1;
                Meteors.Add(m);
                if (dir > 0) m.x = Rnd.Next(-10, Ps.Int(W * 0.9));
            }
            MeteorNextSpawn = now + (-Math.Log(1 - Rnd.NextDouble() * 0.999)) / perSec;
        }
        // hareket ettir, ömrü bitenleri sil
        for (int i = Meteors.Count - 1; i >= 0; i--)
        {
            var m = Meteors[i];
            m.x += m.vx * dt; m.y += m.vy * dt; m.age += dt;
            if (m.age > m.life || m.y > H + m.len || m.x < -20 || m.x > W + 20) Meteors.RemoveAt(i);
        }
        // hücrelere dök: kafa beyaz, kuyruk kırmızıdan karanlığa
        var rowsMap = new Dictionary<int, Dictionary<int, string>>();
        foreach (var m in Meteors)
        {
            double fade = 1.0 - Math.Max(0.0, (m.age - m.life * 0.6) / (m.life * 0.4));
            fade = Math.Min(fade, Math.Min(1.0, m.age / 0.12)) * bright;
            double sx = m.vx < 0 ? 1.0 : -1.0;
            double sy = -Math.Abs(m.vy / m.vx);
            for (int k = m.len; k >= 0; k--)
            {
                int col = Ps.Int(Math.Round(m.x + sx * k)), row = Ps.Int(Math.Round(m.y + sy * k));
                if (row < 0 || row >= H || col < 0 || col >= W) continue;
                double t = k / (double)m.len;
                double cr, cg, cb;
                if (t < 0.15) { cr = 255; cg = 235; cb = 230; }
                else if (t < 0.5) { double q = (t - 0.15) / 0.35; cr = 255 - 20 * q; cg = 235 - 190 * q; cb = 230 - 175 * q; }
                else { double q = (t - 0.5) / 0.5; cr = 235 - 170 * q; cg = 45 - 30 * q; cb = 55 - 35 * q; }
                int ir = Ps.Int(12 + (cr - 12) * fade), ig = Ps.Int(12 + (cg - 12) * fade), ib = Ps.Int(12 + (cb - 12) * fade);
                string ch = k == 0 ? "●" : t < 0.35 ? "•" : "·";
                if (!rowsMap.ContainsKey(row)) rowsMap[row] = new Dictionary<int, string>();
                rowsMap[row][col] = $"{E}[38;2;{ir};{ig};{ib}m{ch}";
            }
        }
        MeteorRows = rowsMap;
    }

    // Bir satırın [x0, x1) aralığındaki gökyüzü parçası
    string SkySeg(int row, int x0, int x1)
    {
        if (x1 <= x0) return "";
        var marks = new SortedDictionary<int, string>();
        if (TwinkleOn && Stars.TryGetValue(row, out var list))
        {
            double now = T();
            foreach (var sv in list)
            {
                int col = sv.Col; double seed = sv.Seed;
                if (col < x0 || col >= x1) continue;
                double b = (Math.Sin(now * (0.8 + (seed % 7) * 0.25) + seed) + 1) / 2;
                if (b > 0.45) { int v = Ps.Int(40 + 70 * (b - 0.45) / 0.55); marks[col] = $"{E}[38;2;{v + 20};{Ps.Int(v * 0.35)};{Ps.Int(v * 0.4)}m·"; }
            }
        }
        if (MeteorRows.TryGetValue(row, out var mr)) { foreach (var kv in mr) if (kv.Key >= x0 && kv.Key < x1) marks[kv.Key] = kv.Value; }
        if (marks.Count == 0) return Ps.Rep(" ", x1 - x0);
        var sb = new StringBuilder(); int pos = x0;
        foreach (var kv in marks) { if (kv.Key > pos) sb.Append(' ', kv.Key - pos); sb.Append(kv.Value); pos = kv.Key + 1; }
        if (pos < x1) sb.Append(R).Append(' ', x1 - pos);
        sb.Append(R);
        return sb.ToString();
    }

    string SkyRow(int row, int W, string text, int col)
    {
        if (string.IsNullOrEmpty(text)) return SkySeg(row, 0, W);
        int len = VLen(text);
        return SkySeg(row, 0, col) + text + R + SkySeg(row, col + len, W);
    }

    List<string> RenderSplash(int W, int H)
    {
        var rows = new List<string>();
        double el = T() - SplashStart;
        int top = Ps.Int(Math.Max(1, (H - 14) / 2.0));
        UpdateSky(W, H, 2.6, 6, true);
        // içerik: satır -> (metin, başlangıç sütunu)
        var items = new Dictionary<int, (string Text, int Col)>();
        int lc = Ps.Int(Math.Max(0, (W - LogoW) / 2.0));
        int li = 0; foreach (string l in RenderLogoDrop(el)) { items[top + li] = (l, lc); li++; }
        string tag = Lang.L("modlu Minecraft sunucu merkezi");
        string typed = tag.Substring(0, Ps.Int(Math.Min(tag.Length, Math.Max(0, (el - 1.0) * 34))));
        string caret = (el > 0.9 && (typed.Length < tag.Length || Ps.Int(T() * 3) % 2 == 0)) ? c.brass + "▌" : " ";
        int tc = Ps.Int(Math.Max(0, (W - VLen(tag)) / 2.0));   // ekran genişliğine göre (Japonca 2 sütun)
        items[top + 7] = (c.text + typed + caret + Ps.Rep(" ", VLen(tag) - VLen(typed)), tc);
        // PowerShell 5.1: [Math]::Min(100, <ondalık>) Int32 sürümünü seçer, ondalık önce [int]e yuvarlanır
        double pct = Math.Min(100, Ps.Int(el / (SplashLen - 0.2) * 100));
        items[top + 9] = (BarP(pct, 30), Ps.Int(Math.Max(0, (W - 30) / 2.0)));
        string word = pct < 100 ? Lang.L("hazırlanıyor") : Lang.L("hazır       ");
        items[top + 10] = (c.brass + (pct < 100 ? Spin() : "✓") + R + " " + Shimmer(word, new[] { 120, 120, 126 }, new[] { 255, 255, 255 }), Ps.Int(Math.Max(0, (W - 16) / 2.0)));
        for (int r1 = 0; r1 < H; r1++)
        {
            if (items.TryGetValue(r1, out var it)) rows.Add(SkyRow(r1, W, it.Text, it.Col));
            else rows.Add(SkySeg(r1, 0, W));
        }
        return rows;
    }

    // ---------- Kapanış: logo kıvılcımlara dağılır ----------
    void StartOutro()
    {
        if (!TestMode && !Native.Visible) { Quit = true; return; }
        Screen = "outro"; OutroStart = T();
        ResetFrame();
    }

    static double Noise(int x, int y) { double v = Math.Sin(x * 12.9898 + y * 78.233) * 43758.5453; return v - Math.Floor(v); }

    List<string> RenderOutro(int W, int H)
    {
        var rows = new List<string>();
        double el = T() - OutroStart;
        double p = Math.Min(1.0, el / (OutroLen - 0.35));
        int top = Ps.Int(Math.Max(1, (H - 12) / 2.0));
        for (int i = 0; i < top; i++) rows.Add("");
        string pad = Ps.Rep(" ", Ps.Int(Math.Max(0, (W - LogoW) / 2.0)));
        for (int r0 = 0; r0 < 6; r0++)
        {
            string src = LogoPlain[r0]; var chars = new char[src.Length];
            for (int i = 0; i < src.Length; i++)
            {
                double n = Noise(i, r0);
                // önce sağdan sola bir dalga, sonra rastgele dağılma
                double thr = p * 1.25 - (1 - i / (double)LogoW) * 0.25;
                if (src[i] == ' ' || n < thr) chars[i] = ' ';
                else if (n < thr + 0.08) chars[i] = '·';
                else chars[i] = src[i];
            }
            string line = new string(chars);
            double flash = Math.Max(0.0, 1.0 - el / 0.25) * 0.8;
            rows.Add(pad + ColorLogoLine(line, r0, flash, Math.Min(1.0, p * 0.9)));
        }
        rows.Add("");
        string msg = Lang.L("görüşürüz");
        double fade = Math.Min(1.0, Math.Max(0.0, (el - 0.9) / 0.7));
        int bas = Ps.Int(240 - 200 * fade);
        rows.Add(Ps.Rep(" ", Ps.Int(Math.Max(0, (W - VLen(msg)) / 2.0))) + Shimmer(msg, new[] { bas, bas, bas }, new[] { 255, Ps.Int(70 + 150 * fade), Ps.Int(80 + 140 * fade) }, 14, 3));
        rows.Add("");
        rows.Add(Ps.Rep(" ", Ps.Int(Math.Max(0, (W - 22) / 2.0))) + c.dark + Lang.L("sunucular kapalı · ") + c.copper + "■" + R);
        return rows;
    }

    // ---------- Pencere modu ----------
    void SetConsoleSize(int w, int h)
    {
        try
        {
            w = Math.Min(w, Console.LargestWindowWidth); h = Math.Min(h, Console.LargestWindowHeight);
            Console.SetWindowSize(1, 1); Console.SetBufferSize(w, h); Console.SetWindowSize(w, h);
        }
        catch { }
    }

    void SaveWinState()
    {
        if (TestMode || SetupMode) return;   // kurulmadan önce diske bir şey yazılmaz (yandaki ilgisiz bir Data klasörüne de)
        try
        {
            int[] rc = Native.GetRect();
            if (Native.Visible && rc[2] > 100)
            {
                if (UiMode == "kucuk") { Win.kucukX = rc[0]; Win.kucukY = rc[1]; } else { Win.buyukX = rc[0]; Win.buyukY = rc[1]; }
            }
            if (Screen == "server") Win.mod = UiMode;
            Json.WriteText(WinFile, Json.WriteWin(Win));
        }
        catch { }
    }

    int[] WaitWinRect()
    {
        int[] prev = Native.GetRect();
        for (int i = 0; i < 20; i++)
        {
            Thread.Sleep(40);
            int[] cur2 = Native.GetRect();
            if (cur2[2] == prev[2] && cur2[3] == prev[3] && i >= 2) return cur2;
            prev = cur2;
        }
        return prev;
    }

    void ResetFrame()
    {
        PrevFrame = Array.Empty<string>();
        if (!TestMode) Console.Write(E + "[2J");
        Dirty = true;
    }

    void SetUiMode(string m, bool NoSave = false)
    {
        if (!NoSave) SaveWinState();
        UiMode = m;
        if (TestMode) return;
        if (m == "kucuk")
        {
            if (!Ps.In(Mode, "log", "kapat", "closing")) Mode = "log";
            SetConsoleSize(MiniSize[0], MiniSize[1]);
            int[] rc = WaitWinRect();
            if (Win.kucukX != null && Native.OnAnyScreen(Win.kucukX.Value, Win.kucukY ?? 0)) Native.MoveTo(Win.kucukX.Value, Win.kucukY ?? 0);
            else { int[] wa = Native.WorkArea(); Native.MoveTo(wa[0] + wa[2] - rc[2] - 12, wa[1] + wa[3] - rc[3] - 12); }
            Native.SetTopMost(Win.ustte);
        }
        else
        {
            Native.SetTopMost(false);
            SetConsoleSize(BigSize[0], BigSize[1]);
            if (Win.buyukX != null && Native.OnAnyScreen(Win.buyukX.Value, Win.buyukY ?? 0)) Native.MoveTo(Win.buyukX.Value, Win.buyukY ?? 0);
            else { int[] rc = WaitWinRect(); int[] wa = Native.WorkArea(); Native.MoveTo(wa[0] + Ps.Int((wa[2] - rc[2]) / 2.0), wa[1] + Ps.Int((wa[3] - rc[3]) / 2.0)); }
        }
        ResetFrame(); LastSize = "";
        if (!NoSave) SaveWinState();
    }

    // Tuş basılı tutulunca art arda tetiklenmesin
    bool Allow(string key, int ms = 1000)
    {
        DateTime now = Now();
        if (LastPress.TryGetValue(key, out var last) && (now - last).TotalMilliseconds < ms) return false;
        LastPress[key] = now;
        return true;
    }

    static void ClearKeyBuffer() { try { while (Console.KeyAvailable) Console.ReadKey(true); } catch { } }

    void ToggleUiMode()
    {
        if (Screen != "server") return;
        if (!Allow("mini", 1000)) { ClearKeyBuffer(); return; }
        if (!Native.Visible) Native.Show();
        if (UiMode == "kucuk") SetUiMode("buyuk"); else SetUiMode("kucuk");
        ClearKeyBuffer();
        LastPress["mini"] = Now();
    }

    // ---------- Konsol kaydı ----------
    void AddLog(string kind, string msg, string time = null, bool vis = true)
    {
        if (string.IsNullOrEmpty(time)) time = Now().ToString("HH:mm:ss");
        Log.Add(new LogEntry { T = time, K = kind, M = msg, V = vis });
        if (Log.Count > 4000) Log.RemoveRange(0, 1000);
        if (Scroll > 0 && (vis || Detail)) Scroll++;
        Dirty = true;
    }

    void ShowHomeMsg(string msg) { HomeMsg = msg; HomeMsgUntil = Now().AddSeconds(6); Dirty = true; }

    string PackName(string k) => Lang.L(PackNameKey[k]);
    string PackDesc(string k) => Lang.L(PackDescKey[k]);

    // ---------- Çizim: kare ----------
    /// <summary>Bir kareyi hazırla: her satır tam W genişliğinde. Test modunda dosyaya yazılan şey de budur.</summary>
    string[] BuildFrame(int W, int H, out bool showCursor, out int cursorCol)
    {
        showCursor = false; cursorCol = 1;
        List<string> rows;
        switch (Screen)
        {
            case "splash": rows = RenderSplash(W, H); break;
            case "outro": rows = RenderOutro(W, H); break;
            case "home": rows = RenderHome(W, H); break;
            case "wizard": rows = RenderWizard(W, H); break;
            case "firstrun": rows = RenderFirstRun(W, H); break;
            case "settings": rows = RenderSettings(W, H); break;
            case "uninstall": rows = RenderUninstall(W, H); break;
            default:
            {
                rows = RenderServer(W, H);
                string promptCol = (S != null && S.Running) ? c.green : c.red;
                string prompt = " " + promptCol + Bo + "❯" + R + " ";
                int maxIn = W - 4;
                string shown = TailByWidth(InputText, maxIn);   // sığmayan baş kısım görünmez (geniş karakter 2 sütun)
                if (Mode == "closing") rows.Add("");
                else if (shown.Length == 0) rows.Add(prompt + c.dark + Lang.L("komut yaz... (F1 yardım)") + R);
                else rows.Add(prompt + c.text + shown + R);
                showCursor = Mode != "closing"; cursorCol = 4 + VLen(shown);
                break;
            }
        }
        var frame = new string[H];
        for (int i = 0; i < H; i++) frame[i] = i < rows.Count ? PadV(rows[i], W) : Ps.Rep(" ", W);
        return frame;
    }

    void Render()
    {
        int W = Console.WindowWidth - 1, H = Console.WindowHeight;
        try { if (Console.BufferHeight != H || Console.BufferWidth != W + 1) Console.SetBufferSize(W + 1, H); } catch { }
        string[] newFrame = BuildFrame(W, H, out bool showCursor, out int cursorCol);
        var sb = new StringBuilder();
        sb.Append(E).Append("[?25l");
        for (int i = 0; i < H; i++)
        {
            if (i >= PrevFrame.Length || PrevFrame[i] != newFrame[i]) sb.Append(E).Append('[').Append(i + 1).Append(";1H").Append(newFrame[i]);
        }
        PrevFrame = newFrame;
        if (showCursor) sb.Append(E).Append('[').Append(H).Append(';').Append(cursorCol).Append('H').Append(E).Append("[?25h");
        Console.Write(sb.ToString());
    }

    bool Animating()
    {
        if (Ps.In(Screen, "splash", "wizard", "home", "outro", "firstrun", "settings", "uninstall")) return true;
        if (Screen == "server" && UiMode == "buyuk") return true;
        if (Screen == "server" && (Ps.In(Status, "BASLIYOR", "DURUYOR") || Ps.In(Mode, "closing", "kapat") || BackupStage != null)) return true;
        return false;
    }
}
