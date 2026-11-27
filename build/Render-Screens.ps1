# =====================================================================
#  SyHost - README ekran görüntüleri
#    build\Render-Screens.ps1                          tests\parity\scenarios\docs-*.json -> docs\images\screens\<ad>-<dil>.png
#    build\Render-Screens.ps1 -Filter 'docs-home-*'    yalnızca adı uyan senaryolar
#    build\Render-Screens.ps1 -Scale 1.5 -NoFrame      daha küçük hücre, pencere çerçevesi olmadan
#  Her senaryo C# sürümünde tek bir kare olarak çizilir (dist\SyHost.exe --frame, parity testiyle
#  aynı çalışma klasörü düzeni) ve karenin metni PNG'ye dökülür:
#    - 24 bit ANSI renkleri (38;2 / 48;2), kalın yazı, sıfırlama; geri kalan kodlar yok sayılır
#    - yazı tipi depodaki Cascadia Mono (legacy\fonts, normal + kalın); Japonca gibi geniş karakterler
#      (uygulamanın kendi WideRx aralıkları) iki sütun kaplar ve Windows'taki Japonca yazı tipiyle çizilir
#    - kutu çizgileri, bloklar ve tarama (─ │ ═ ║ ╔ ╗ ╚ ╝ ╭ ╮ ╯ ╰ █ ▌ ░) Cascadia Mono'nun oranlarıyla
#      piksele oturan şekiller olarak çizilir: hücreler arasında dikiş kalmaz
#    - gri tonlu yumuşatma (ClearType renk saçağı yok), her hücre aynı piksel ızgarasında, harfler kendi satırında
#    - pencere, uygulamanın açtığı konsol gibi: kare genişliği + 1 sütun, arka plan konsolun varsayılan siyahı
#    - isteğe bağlı ince pencere çerçevesi: başlık "SyHost" ve uygulamanın simgesi, yuvarlak köşeler
#    - "12,6 GB" gibi boyutlarda ondalık ayırıcı senaryonun dilinden gelir (tr virgül, en/ja nokta);
#      SyHost bunu Windows'un bölge ayarıyla yazar, resimler her bilgisayarda aynı çıksın diye
#  Karenin son satırı (#cursor) resme girmez. Aynı girdilerle her çalıştırmada aynı PNG çıkar.
#  Senaryolar: tests\parity\scenarios\docs-*.json (parity testi iki sürümün bunları aynı çizdiğini de denetler).
#  Gerekenler: dist\SyHost.exe (build\Build.ps1 -Publish), Windows PowerShell 5.1 (System.Drawing).
# =====================================================================
[CmdletBinding()]
param(
    [string]$Filter = 'docs-*',
    [string]$Exe,
    [string]$OutDir,
    [string]$WorkRoot = (Join-Path ([IO.Path]::GetTempPath()) 'SyHost-screens'),
    [ValidateRange(1.0, 4.0)][double]$Scale = 2.0,   # 1 = konsolun %100 boyutu (16 piksellik yazı, 8x16 hücre)
    [switch]$NoFrame
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
if (-not $Exe) { $Exe = Join-Path $Repo 'dist\SyHost.exe' }
if (-not $OutDir) { $OutDir = Join-Path $Repo 'docs\images\screens' }
$ScenarioDir = Join-Path $Repo 'tests\parity\scenarios'
$FontRegular = Join-Path $Repo 'legacy\fonts\CascadiaMono-Regular.ttf'
$FontBold    = Join-Path $Repo 'legacy\fonts\CascadiaMono-Bold.ttf'
$IconFile    = Join-Path $Repo 'src\SyHost\Assets\SyHost.ico'
$Utf8 = New-Object Text.UTF8Encoding $false
if (-not (Test-Path -LiteralPath $Exe)) { throw "$Exe bulunamadı. Önce derle: build\Build.ps1 -Publish" }
$DefaultCfg = [IO.File]::ReadAllText((Join-Path $Repo 'legacy\config\default-settings.json'), [Text.Encoding]::UTF8)
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore

# ---------- Kare -> resim (C# 5: Windows PowerShell 5.1'in derleyicisi) ----------
$PainterCode = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;

namespace SyHostScreens
{
    // Ekrandaki bir hücre: karakter, renkler (0xRRGGBB, -1 = konsolun varsayılanı), kalın
    public sealed class Cell
    {
        public string Text;
        public int Fg = -1;
        public int Bg = -1;
        public bool Bold;
        public bool Wide;   // iki sütun kaplar
        public bool Tail;   // geniş karakterin ikinci sütunu
    }

    public static class Frame
    {
        // Konsolun varsayılan renk tablosu (Campbell): eski 16 renk kodları gelirse diye
        static readonly int[] Campbell = { 0x0C0C0C, 0xC50F1F, 0x13A10E, 0xC19C00, 0x0037DA, 0x881798, 0x3A96DD, 0xCCCCCC,
                                           0x767676, 0xE74856, 0x16C60C, 0xF9F1A5, 0x3B78FF, 0xB4009E, 0x61D6D6, 0xF2F2F2 };

        // Uygulamanın WideRx aralıkları (App.State.cs, SyHost.ps1): bu karakterler iki sütun kaplar
        public static bool IsWide(int cp)
        {
            return (cp >= 0x1100 && cp <= 0x115F) || (cp >= 0x2E80 && cp <= 0x303E) || (cp >= 0x3041 && cp <= 0x33FF)
                || (cp >= 0x3400 && cp <= 0x4DBF) || (cp >= 0x4E00 && cp <= 0x9FFF) || (cp >= 0xA000 && cp <= 0xA4CF)
                || (cp >= 0xAC00 && cp <= 0xD7A3) || (cp >= 0xF900 && cp <= 0xFAFF) || (cp >= 0xFE30 && cp <= 0xFE4F)
                || (cp >= 0xFF00 && cp <= 0xFF60) || (cp >= 0xFFE0 && cp <= 0xFFE6);
        }

        /// <summary>Kare satırlarını hücrelere çevir (her satır kendi renk durumuyla başlar, uygulama da öyle yazar).</summary>
        public static Cell[,] Parse(string[] lines, int cols, int rows)
        {
            Cell[,] cells = new Cell[rows, cols];
            for (int r = 0; r < rows; r++) for (int c = 0; c < cols; c++) cells[r, c] = new Cell();
            for (int r = 0; r < rows && r < lines.Length; r++)
            {
                string s = lines[r] ?? "";
                int fg = -1, bg = -1, col = 0, i = 0;
                bool bold = false;
                while (i < s.Length)
                {
                    char ch = s[i];
                    if (ch == '\u001b')
                    {
                        if (i + 1 < s.Length && s[i + 1] == '[')
                        {
                            int j = i + 2;
                            while (j < s.Length && !((s[j] >= 'A' && s[j] <= 'Z') || (s[j] >= 'a' && s[j] <= 'z'))) j++;
                            if (j >= s.Length) break;
                            if (s[j] == 'm') Sgr(s.Substring(i + 2, j - i - 2), ref fg, ref bg, ref bold);
                            i = j + 1;
                        }
                        else i++;
                        continue;
                    }
                    if (ch == '\r' || ch == '\n') { i++; continue; }
                    string text; int cp;
                    if (char.IsHighSurrogate(ch) && i + 1 < s.Length && char.IsLowSurrogate(s[i + 1])) { text = s.Substring(i, 2); cp = char.ConvertToUtf32(ch, s[i + 1]); i += 2; }
                    else { text = ch.ToString(); cp = ch; i++; }
                    bool wide = IsWide(cp);
                    int w = wide ? 2 : 1;
                    if (col + w > cols) { col += w; continue; }
                    Cell cell = cells[r, col];
                    cell.Text = text; cell.Fg = fg; cell.Bg = bg; cell.Bold = bold; cell.Wide = wide;
                    if (wide) { Cell tail = cells[r, col + 1]; tail.Tail = true; tail.Fg = fg; tail.Bg = bg; tail.Bold = bold; }
                    col += w;
                }
            }
            return cells;
        }

        static int Num(string s) { int v; return int.TryParse(s, out v) ? v : 0; }

        static void Sgr(string ps, ref int fg, ref int bg, ref bool bold)
        {
            string[] p = ps.Length == 0 ? new string[] { "0" } : ps.Split(';');
            for (int k = 0; k < p.Length; k++)
            {
                int v = Num(p[k]);
                if (v == 0) { fg = -1; bg = -1; bold = false; }
                else if (v == 1) bold = true;
                else if (v == 22) bold = false;
                else if (v == 39) fg = -1;
                else if (v == 49) bg = -1;
                else if (v >= 30 && v <= 37) fg = Campbell[v - 30];
                else if (v >= 90 && v <= 97) fg = Campbell[v - 90 + 8];
                else if (v >= 40 && v <= 47) bg = Campbell[v - 40];
                else if (v >= 100 && v <= 107) bg = Campbell[v - 100 + 8];
                else if ((v == 38 || v == 48) && k + 2 < p.Length && Num(p[k + 1]) == 2 && k + 4 < p.Length)
                {
                    int color = (Clamp(Num(p[k + 2])) << 16) | (Clamp(Num(p[k + 3])) << 8) | Clamp(Num(p[k + 4]));
                    if (v == 38) fg = color; else bg = color;
                    k += 4;
                }
                else if ((v == 38 || v == 48) && k + 2 < p.Length && Num(p[k + 1]) == 5)
                {
                    int n = Num(p[k + 2]), color;
                    if (n < 16) color = Campbell[n];
                    else if (n < 232) { n -= 16; int[] lv = { 0, 95, 135, 175, 215, 255 }; color = (lv[n / 36] << 16) | (lv[n / 6 % 6] << 8) | lv[n % 6]; }
                    else { int gr = 8 + (n - 232) * 10; color = (gr << 16) | (gr << 8) | gr; }
                    if (v == 38) fg = color; else bg = color;
                    k += 2;
                }
            }
        }

        static int Clamp(int v) { return v < 0 ? 0 : v > 255 ? 255 : v; }
    }

    public sealed class Painter : IDisposable
    {
        public readonly int CellW;
        public readonly int CellH;
        public int DefaultFg = 0xCCCCCC;      // konsolun varsayılan yazı rengi (Campbell)
        public int DefaultBg = 0x0C0C0C;      // konsolun varsayılan arka planı (Campbell)
        public int TitleBg = 0x202020;        // Windows 11 koyu başlık çubuğu
        public int TitleFg = 0xFFFFFF;
        public int ButtonFg = 0xE6E6E6;
        public int ButtonOff = 0x6A6A6A;      // SyHost kapatma düğmesini kapatır (sunucu düzgün kapansın diye): gri
        public int BorderColor = 0x3A3A3A;
        public readonly List<int> Unknown = new List<int>();   // Cascadia Mono'da olmayan dar karakterler

        readonly PrivateFontCollection pfc;
        readonly Font monoRegular, monoBold, jpRegular, jpBold;
        readonly HashSet<int> monoChars;
        readonly float monoDx, jpDy;
        readonly int stroke;
        readonly StringFormat fmt;
        readonly Dictionary<int, SolidBrush> brushes = new Dictionary<int, SolidBrush>();
        readonly Dictionary<string, float> jpAdvance = new Dictionary<string, float>();
        readonly Dictionary<int, TextureBrush> shades = new Dictionary<int, TextureBrush>();

        public Painter(string regularFile, string boldFile, int[] monoCodepoints, double advanceEm, string jpFamily, int cellH)
        {
            CellH = cellH;
            pfc = new PrivateFontCollection();
            pfc.AddFontFile(regularFile);
            pfc.AddFontFile(boldFile);
            FontFamily mono = pfc.Families[0];
            float emH = mono.GetEmHeight(FontStyle.Regular);
            float asc = mono.GetCellAscent(FontStyle.Regular), desc = mono.GetCellDescent(FontStyle.Regular);
            // Konsol gibi: yazı boyutu = hücre yüksekliği (ascent + descent), genişlik = harf aralığı
            float em = cellH * emH / (asc + desc);
            CellW = (int)Math.Round(em * advanceEm);
            monoRegular = new Font(mono, em, FontStyle.Regular, GraphicsUnit.Pixel);
            monoBold = new Font(mono, em, FontStyle.Bold, GraphicsUnit.Pixel);
            monoDx = (float)((CellW - em * advanceEm) / 2.0);
            fmt = (StringFormat)StringFormat.GenericTypographic.Clone();
            fmt.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces | StringFormatFlags.NoWrap | StringFormatFlags.NoClip;
            // Japonca: tam genişlikli harf iki hücreyi doldursun (konsoldaki gibi sık), kanjinin mürekkebi
            // hücrenin dikey ortasında; bütün geniş karakterler aynı taban çizgisini paylaşır
            FontFamily jp = new FontFamily(jpFamily);
            float jem = 1.8f * CellW;
            jpRegular = new Font(jp, jem, FontStyle.Regular, GraphicsUnit.Pixel);
            jpBold = new Font(jp, jem, FontStyle.Bold, GraphicsUnit.Pixel);
            RectangleF ink;
            using (GraphicsPath gp = new GraphicsPath())
            {
                gp.AddString("国", jp, (int)FontStyle.Regular, jem, PointF.Empty, fmt);
                ink = gp.GetBounds();
            }
            jpDy = (cellH - ink.Height) / 2f - ink.Y;
            monoChars = new HashSet<int>(monoCodepoints);
            // Cascadia Mono'nun ince çizgisi yazı boyunun ~%10'u (hücre yüksekliğinin ~%8.8'i)
            stroke = Math.Max(1, (int)Math.Round(cellH * 0.0884));
        }

        public void Dispose()
        {
            foreach (SolidBrush b in brushes.Values) b.Dispose();
            foreach (TextureBrush t in shades.Values) t.Dispose();
            monoRegular.Dispose(); monoBold.Dispose(); jpRegular.Dispose(); jpBold.Dispose();
            fmt.Dispose(); pfc.Dispose();
        }

        static Color ColorOf(int rgb) { return Color.FromArgb(255, (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255); }

        SolidBrush Brush(int rgb)
        {
            SolidBrush b;
            if (!brushes.TryGetValue(rgb, out b)) { b = new SolidBrush(ColorOf(rgb)); brushes[rgb] = b; }
            return b;
        }

        /// <summary>Hücreleri konsol penceresinin iç alanı olarak çiz.</summary>
        public Bitmap Paint(Cell[,] cells)
        {
            int rows = cells.GetLength(0), cols = cells.GetLength(1);
            Bitmap bmp = new Bitmap(cols * CellW, rows * CellH, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.Clear(ColorOf(DefaultBg));
                g.SmoothingMode = SmoothingMode.None;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.InterpolationMode = InterpolationMode.NearestNeighbor;   // ░ deseni piksel piksel
                g.CompositingQuality = CompositingQuality.HighQuality;
                for (int r = 0; r < rows; r++)
                    for (int c = 0; c < cols; c++)
                    {
                        Cell cell = cells[r, c];
                        if (cell.Bg >= 0 && cell.Bg != DefaultBg) g.FillRectangle(Brush(cell.Bg), c * CellW, r * CellH, CellW, CellH);
                    }
                for (int r = 0; r < rows; r++)
                {
                    // Harfler kendi satırının dışına taşmasın (konsol da satır satır kırpar)
                    g.SetClip(new Rectangle(0, r * CellH, cols * CellW, CellH));
                    for (int c = 0; c < cols; c++)
                    {
                        Cell cell = cells[r, c];
                        if (cell.Tail || cell.Text == null || cell.Text == " ") continue;
                        int fg = cell.Fg >= 0 ? cell.Fg : DefaultFg;
                        int x = c * CellW, y = r * CellH;
                        int cp = char.ConvertToUtf32(cell.Text, 0);
                        if (Builtin(g, cp, x, y, fg)) continue;
                        if (monoChars.Contains(cp))
                        {
                            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                            g.DrawString(cell.Text, cell.Bold ? monoBold : monoRegular, Brush(fg), x + monoDx, y, fmt);
                        }
                        else
                        {
                            if (!cell.Wide && !Unknown.Contains(cp)) Unknown.Add(cp);
                            Font f = cell.Bold ? jpBold : jpRegular;
                            float box = (cell.Wide ? 2 : 1) * CellW;
                            g.TextRenderingHint = TextRenderingHint.AntiAlias;
                            g.DrawString(cell.Text, f, Brush(fg), x + (box - JpAdvance(g, cell.Text, f)) / 2f, y + jpDy, fmt);
                        }
                    }
                }
                g.ResetClip();
            }
            return bmp;
        }

        float JpAdvance(Graphics g, string text, Font f)
        {
            string key = (f.Bold ? "b" : "r") + text;
            float a;
            if (!jpAdvance.TryGetValue(key, out a)) { a = g.MeasureString(text, f, PointF.Empty, fmt).Width; jpAdvance[key] = a; }
            return a;
        }

        static void Rect(Graphics g, Brush b, int x0, int y0, int x1, int y1)
        {
            if (x1 > x0 && y1 > y0) g.FillRectangle(b, x0, y0, x1 - x0, y1 - y0);
        }

        // Kutu çizgileri ve bloklar: hücreye tam oturan şekiller (yan yana gelince dikiş kalmaz)
        bool Builtin(Graphics g, int cp, int x, int y, int fg)
        {
            int w = CellW, h = CellH, t = stroke, d = 3 * t;
            int hy = y + (h - t) / 2, vx = x + (w - t) / 2;     // tek çizgi: yatay satırlar [hy, hy+t), dikey sütunlar [vx, vx+t)
            int dy = y + (h - d) / 2, dx = x + (w - d) / 2;     // çift çizgi: çizgi, boşluk, çizgi (eşit kalınlıkta)
            Brush b = Brush(fg);
            switch (cp)
            {
                case 0x2500: Rect(g, b, x, hy, x + w, hy + t); return true;                                                  // ─
                case 0x2502: Rect(g, b, vx, y, vx + t, y + h); return true;                                                  // │
                case 0x2550: Rect(g, b, x, dy, x + w, dy + t); Rect(g, b, x, dy + 2 * t, x + w, dy + d); return true;       // ═
                case 0x2551: Rect(g, b, dx, y, dx + t, y + h); Rect(g, b, dx + 2 * t, y, dx + d, y + h); return true;       // ║
                case 0x2554:                                                                                                  // ╔
                    Rect(g, b, dx, dy, x + w, dy + t); Rect(g, b, dx, dy, dx + t, y + h);
                    Rect(g, b, dx + 2 * t, dy + 2 * t, x + w, dy + d); Rect(g, b, dx + 2 * t, dy + 2 * t, dx + d, y + h);
                    return true;
                case 0x2557:                                                                                                  // ╗
                    Rect(g, b, x, dy, dx + d, dy + t); Rect(g, b, dx + 2 * t, dy, dx + d, y + h);
                    Rect(g, b, x, dy + 2 * t, dx + t, dy + d); Rect(g, b, dx, dy + 2 * t, dx + t, y + h);
                    return true;
                case 0x255A:                                                                                                  // ╚
                    Rect(g, b, dx, dy + 2 * t, x + w, dy + d); Rect(g, b, dx, y, dx + t, dy + d);
                    Rect(g, b, dx + 2 * t, dy, x + w, dy + t); Rect(g, b, dx + 2 * t, y, dx + d, dy + t);
                    return true;
                case 0x255D:                                                                                                  // ╝
                    Rect(g, b, x, dy + 2 * t, dx + d, dy + d); Rect(g, b, dx + 2 * t, y, dx + d, dy + d);
                    Rect(g, b, x, dy, dx + t, dy + t); Rect(g, b, dx, y, dx + t, dy + t);
                    return true;
                case 0x256D: Corner(g, fg, x, y, vx, hy, t, true, true); return true;                                        // ╭
                case 0x256E: Corner(g, fg, x, y, vx, hy, t, false, true); return true;                                       // ╮
                case 0x256F: Corner(g, fg, x, y, vx, hy, t, false, false); return true;                                      // ╯
                case 0x2570: Corner(g, fg, x, y, vx, hy, t, true, false); return true;                                       // ╰
                case 0x2591: Shade(g, fg, x, y); return true;                                                                // ░
                case 0x2588: Rect(g, b, x, y, x + w, y + h); return true;                                                    // █
                case 0x258C: Rect(g, b, x, y, x + w / 2, y + h); return true;                                                // ▌
                case 0x2590: Rect(g, b, x + w / 2, y, x + w, y + h); return true;                                            // ▐
                case 0x2580: Rect(g, b, x, y, x + w, y + h / 2); return true;                                                // ▀
                case 0x2584: Rect(g, b, x, y + h / 2, x + w, y + h); return true;                                            // ▄
            }
            return false;
        }

        // ░: Cascadia Mono'daki gibi ince çapraz taramalar; desen resmin köşesine hizalı, hücreden hücreye kesintisiz sürer
        void Shade(Graphics g, int fg, int x, int y)
        {
            TextureBrush tb;
            if (!shades.TryGetValue(fg, out tb))
            {
                int p = Math.Max(3, (int)Math.Round(CellW / 4.0)), lw = Math.Max(1, (int)Math.Round(CellW / 16.0));
                using (Bitmap tile = new Bitmap(p, p, PixelFormat.Format32bppArgb))
                {
                    Color col = Color.FromArgb(128, (fg >> 16) & 255, (fg >> 8) & 255, fg & 255);
                    for (int j = 0; j < p; j++) for (int i = 0; i < p; i++) if ((i + j) % p < lw) tile.SetPixel(i, j, col);
                    tb = new TextureBrush(tile, WrapMode.Tile);
                }
                shades[fg] = tb;
            }
            g.FillRectangle(tb, x, y, CellW, CellH);
        }

        // Yuvarlak köşe: hücrenin ortasından kenarına çeyrek yay, sonra dikey çizginin kalanı
        void Corner(Graphics g, int fg, int x, int y, int vx, int hy, int t, bool right, bool down)
        {
            float cx = vx + t / 2f, cy = hy + t / 2f;              // çizgilerin orta hatları
            float r = right ? (x + CellW) - cx : cx - x;           // yay hücre kenarında yatay çizgiye bağlanır
            float ox = right ? cx + r : cx - r, oy = down ? cy + r : cy - r;
            if (down) Rect(g, Brush(fg), vx, (int)Math.Round(cy + r), vx + t, y + CellH);
            else Rect(g, Brush(fg), vx, y, vx + t, (int)Math.Round(cy - r));
            float start = right ? (down ? 180f : 90f) : (down ? 270f : 0f);
            SmoothingMode sm = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen pen = new Pen(ColorOf(fg), t)) g.DrawArc(pen, ox - r, oy - r, 2 * r, 2 * r, start, 90f);
            g.SmoothingMode = sm;
        }

        /// <summary>İnce pencere çerçevesi: başlık çubuğu (simge, "SyHost", düğmeler), kenarlık, yuvarlak köşeler.</summary>
        public Bitmap Compose(Bitmap client, string title, Bitmap icon)
        {
            double ui = CellH / 16.0;   // %100 ölçekte konsolun 16 piksellik yazısına göre
            int b = Math.Max(1, (int)Math.Round(ui));
            int titleH = (int)Math.Round(31 * ui);
            int radius = (int)Math.Round(8 * ui);
            int W = client.Width + 2 * b, H = client.Height + titleH + 2 * b;
            Bitmap bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.Clear(ColorOf(BorderColor));
                g.SmoothingMode = SmoothingMode.None;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.FillRectangle(Brush(TitleBg), b, b, W - 2 * b, titleH);
                g.DrawImage(client, new Rectangle(b, b + titleH, client.Width, client.Height));
                int isz = (int)Math.Round(16 * ui);
                int ix = b + (int)Math.Round(9 * ui), iy = b + (titleH - isz) / 2;
                if (icon != null)
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.DrawImage(icon, new Rectangle(ix, iy, isz, isz));
                }
                using (Font tf = new Font("Segoe UI", (float)(12 * ui), FontStyle.Regular, GraphicsUnit.Pixel))
                {
                    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                    float th = tf.GetHeight(g);
                    g.DrawString(title, tf, Brush(TitleFg), ix + isz + (float)(8 * ui), b + (titleH - th) / 2f, fmt);
                }
                // Simge durumuna küçült, ekranı kapla, kapat (kapat gri: SyHost onu devre dışı bırakır)
                int bw = (int)Math.Round(46 * ui), gs = (int)Math.Round(10 * ui), lw = Math.Max(1, (int)Math.Round(ui));
                int midY = b + titleH / 2;
                int cxClose = W - b - bw / 2, cxMax = cxClose - bw, cxMin = cxMax - bw;
                Rect(g, Brush(ButtonFg), cxMin - gs / 2, midY, cxMin + gs / 2, midY + lw);
                Rect(g, Brush(ButtonFg), cxMax - gs / 2, midY - gs / 2, cxMax + gs / 2, midY - gs / 2 + lw);
                Rect(g, Brush(ButtonFg), cxMax - gs / 2, midY + gs / 2 - lw, cxMax + gs / 2, midY + gs / 2);
                Rect(g, Brush(ButtonFg), cxMax - gs / 2, midY - gs / 2, cxMax - gs / 2 + lw, midY + gs / 2);
                Rect(g, Brush(ButtonFg), cxMax + gs / 2 - lw, midY - gs / 2, cxMax + gs / 2, midY + gs / 2);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (Pen pen = new Pen(ColorOf(ButtonOff), lw))
                {
                    g.DrawLine(pen, cxClose - gs / 2f, midY - gs / 2f, cxClose + gs / 2f, midY + gs / 2f);
                    g.DrawLine(pen, cxClose - gs / 2f, midY + gs / 2f, cxClose + gs / 2f, midY - gs / 2f);
                }
            }
            RoundCorners(bmp, radius, b, TitleBg, DefaultBg, BorderColor);
            return bmp;
        }

        static double Unit(double v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

        // Köşeleri yuvarla: dış yayın dışı saydam, kenarlık bandı yay boyunca, içi başlık/konsol rengi (yumuşatılmış)
        static void RoundCorners(Bitmap bmp, int r, int b, int topColor, int bottomColor, int border)
        {
            BitmapData data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            try
            {
                int stride = data.Stride;
                byte[] px = new byte[stride * bmp.Height];
                Marshal.Copy(data.Scan0, px, 0, px.Length);
                for (int corner = 0; corner < 4; corner++)
                {
                    bool right = corner == 1 || corner == 3, bottom = corner >= 2;
                    int content = bottom ? bottomColor : topColor;
                    double ccx = right ? bmp.Width - r : r, ccy = bottom ? bmp.Height - r : r;
                    for (int j = 0; j < r; j++)
                        for (int i = 0; i < r; i++)
                        {
                            int x = right ? bmp.Width - r + i : i, y = bottom ? bmp.Height - r + j : j;
                            double ddx = x + 0.5 - ccx, ddy = y + 0.5 - ccy;
                            if ((right ? ddx < 0 : ddx > 0) || (bottom ? ddy < 0 : ddy > 0)) continue;
                            double dist = Math.Sqrt(ddx * ddx + ddy * ddy);
                            double aOut = Unit(r - dist + 0.5), aIn = Unit(r - b - dist + 0.5);
                            int o = y * stride + x * 4;
                            if (aOut <= 0) { px[o] = 0; px[o + 1] = 0; px[o + 2] = 0; px[o + 3] = 0; continue; }
                            for (int ch = 0; ch < 3; ch++)
                            {
                                int shift = ch * 8;   // BGRA: 0 mavi, 1 yeşil, 2 kırmızı
                                double v = (((content >> shift) & 255) * aIn + ((border >> shift) & 255) * (aOut - aIn)) / aOut;
                                px[o + ch] = (byte)Math.Round(v);
                            }
                            px[o + 3] = (byte)Math.Round(255 * aOut);
                        }
                }
                Marshal.Copy(px, 0, data.Scan0, px.Length);
            }
            finally { bmp.UnlockBits(data); }
        }
    }
}
'@
if (-not ('SyHostScreens.Painter' -as [type])) { Add-Type -TypeDefinition $PainterCode -ReferencedAssemblies System.Drawing }

# ---------- Yazı tipleri ----------
# Cascadia Mono'nun içerdiği karakterler (normal ve kalında ortak olanlar); olmayanlar Japonca yazı tipiyle çizilir
function Get-FontInfo([string]$file) {
    $gt = New-Object System.Windows.Media.GlyphTypeface ([Uri]$file)
    $map = $gt.CharacterToGlyphMap
    [pscustomobject]@{ Chars = [int[]]@($map.Keys); Advance = $gt.AdvanceWidths[$map[[int][char]'M']] }
}
$reg = Get-FontInfo $FontRegular
$boldSet = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($cp in (Get-FontInfo $FontBold).Chars) { [void]$boldSet.Add($cp) }
$monoChars = [int[]]@($reg.Chars | Where-Object { $boldSet.Contains($_) })
$installed = @((New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name })
$JpFamily = @('Yu Gothic UI', 'Yu Gothic', 'MS Gothic', 'Meiryo UI') | Where-Object { $installed -contains $_ } | Select-Object -First 1
if (-not $JpFamily) { Write-Warning 'Japonca yazı tipi bulunamadı (Yu Gothic UI / MS Gothic); geniş karakterler Segoe UI ile çizilecek.'; $JpFamily = 'Segoe UI' }

$CellH = [int][Math]::Round(16 * $Scale)
$Painter = New-Object SyHostScreens.Painter($FontRegular, $FontBold, $monoChars, [double]$reg.Advance, $JpFamily, $CellH)
$Icon = $null
if (-not $NoFrame) {
    $isz = $CellH   # %100 ölçekte 16 piksellik simge, hücre yüksekliğiyle aynı ölçekte büyür
    $ico = New-Object System.Drawing.Icon($IconFile, $isz, $isz)
    $Icon = $ico.ToBitmap(); $ico.Dispose()
}

# ---------- Senaryonun çalışma klasörü (Run-Parity.ps1 ile aynı düzen) ----------
function Write-Utf8([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $Utf8) }

function Merge-Json($dst, $src) {
    foreach ($p in $src.PSObject.Properties) {
        $cur = $dst.PSObject.Properties[$p.Name]
        if ($cur -and $cur.Value -is [System.Management.Automation.PSCustomObject] -and $p.Value -is [System.Management.Automation.PSCustomObject]) { Merge-Json $cur.Value $p.Value }
        else { $dst | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    }
}

function New-Workspace([string]$dir, $sc) {
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Force (Join-Path $dir 'cs\Data'), (Join-Path $dir 'localappdata') | Out-Null
    $cfg = $DefaultCfg | ConvertFrom-Json
    if ($null -ne $sc.cfg) { Merge-Json $cfg $sc.cfg }
    if ($null -ne $sc.lang) { $cfg | Add-Member -NotePropertyName dil -NotePropertyValue ([string]$sc.lang) -Force }
    $cfg | Add-Member -NotePropertyName paketlerAyarlandi -NotePropertyValue $true -Force
    Write-Utf8 (Join-Path $dir 'cs\Data\ayarlar.json') (ConvertTo-Json -InputObject $cfg -Depth 10)
    $srv = if ($null -eq $sc.servers) { '[]' } else { ConvertTo-Json -InputObject @($sc.servers) -Depth 10 }
    Write-Utf8 (Join-Path $dir 'cs\Data\sunucular.json') $srv
}

# SyHost.exe --frame: senaryonun durumunu kurar, saati dondurur, tek kare yazar. Yan etkiler senaryonun klasöründe kalır.
function Invoke-Frame([string]$file, [string]$dir, [string]$name) {
    $out = Join-Path $dir 'frame.txt'
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe
    $psi.Arguments = "--frame `"$file`" `"$out`" --root `"$(Join-Path $dir 'cs')`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $dir
    $psi.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $dir 'localappdata'   # gerçek kullanıcı verisine dokunmasın
    $psi.EnvironmentVariables['SYHOST_SHORTCUT_DIR'] = Join-Path $dir 'shortcuts'
    $psi.EnvironmentVariables['SYHOST_DEFAULT_ROOT'] = Join-Path $dir 'defaultroot'
    $psi.EnvironmentVariables['SYHOST_LEGACY_DATA'] = Join-Path $dir 'legacy'
    $psi.EnvironmentVariables['SYHOST_DRYRUN'] = '1'
    $psi.EnvironmentVariables['SYHOST_TEST_TITLE'] = 'SyHostScreens-' + $name
    $p = [Diagnostics.Process]::Start($psi)
    $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch {}; throw "${name}: SyHost.exe --frame 60 saniyede bitmedi" }
    $p.WaitForExit()
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $out)) { throw ("{0}: SyHost.exe --frame başarısız (kod {1}) {2}" -f $name, $p.ExitCode, ($so.Result + $se.Result).Trim()) }
    [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8)
}

# ---------- Çiz ----------
$files = @(Get-ChildItem -LiteralPath $ScenarioDir -Filter *.json | Where-Object { $_.BaseName -like $Filter } | Sort-Object Name)
if ($files.Count -eq 0) { throw "Senaryo bulunamadı: $ScenarioDir\$Filter.json" }
New-Item -ItemType Directory -Force $OutDir, $WorkRoot | Out-Null
Write-Host ("{0} senaryo · hücre {1}x{2} · Japonca: {3} · çıktı {4}" -f $files.Count, $Painter.CellW, $Painter.CellH, $JpFamily, $OutDir) -ForegroundColor DarkGray
$big = 0
try {
    foreach ($f in $files) {
        $sc = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $w = [int]$sc.w; $h = [int]$sc.h; $lang = [string]$sc.lang
        $dir = Join-Path $WorkRoot $f.BaseName
        New-Workspace $dir $sc
        $text = Invoke-Frame $f.FullName $dir $f.BaseName
        # Ondalık ayırıcı: SyHost "12,6 GB" gibi boyutları Windows'un bölge ayarıyla yazar. Resimler hangi
        # bilgisayarda çizilirse çizilsin aynı olsun ve dile uysun diye yalnızca bu boyutlarda dilin ayırıcısı kullanılır.
        $sep = if ($lang -eq 'tr') { ',' } else { '.' }
        $text = [regex]::Replace($text, '(?<=\d)[.,](?=\d( ?/ ?\d+)? GB)', $sep)
        $lines = $text -split "`n"
        if ($lines.Count -le $h -or -not $lines[$h].StartsWith('#cursor')) { throw "$($f.BaseName): kare $h satır değil" }
        # Konsol penceresi karenin bir sütun fazlası genişliktedir (SyHost son sütuna yazmaz)
        $cells = [SyHostScreens.Frame]::Parse([string[]]$lines[0..($h - 1)], $w + 1, $h)
        $client = $Painter.Paint($cells)
        $img = $client
        if (-not $NoFrame) { $img = $Painter.Compose($client, 'SyHost', $Icon); $client.Dispose() }
        $base = $f.BaseName -replace '^docs-', ''
        if ($lang -and $base -notlike "*-$lang") { $base = "$base-$lang" }
        $png = Join-Path $OutDir "$base.png"
        $img.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
        $kb = [int][Math]::Ceiling((Get-Item -LiteralPath $png).Length / 1KB)
        $color = if ($kb -gt 350) { $big++; 'Yellow' } else { 'Green' }
        Write-Host ('{0,-28} {1}x{2}  {3} KB' -f "$base.png", $img.Width, $img.Height, $kb) -ForegroundColor $color
        $img.Dispose()
    }
} finally {
    if ($Icon) { $Icon.Dispose() }
    if ($Painter.Unknown.Count) { Write-Warning ('Cascadia Mono''da olmayan karakterler Japonca yazı tipiyle çizildi: ' + (($Painter.Unknown | ForEach-Object { 'U+{0:X4}' -f $_ }) -join ' ')) }
    $Painter.Dispose()
}
if ($big) { Write-Warning "$big resim 350 KB'tan büyük." }
