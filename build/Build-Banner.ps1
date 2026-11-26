# =====================================================================
#  SyHost - README afişi ve GitHub sosyal önizleme görseli
#    build\Build-Banner.ps1                        docs\images\banner.png (1600x480) + social-preview.png (1280x640)
#    build\Build-Banner.ps1 -OutDir D:\deneme      başka bir klasöre yazar
#    build\Build-Banner.ps1 -Background sanat.png  çizilen gökyüzü yerine hazır bir arka plan kullanır
#  Gerekenler: Windows PowerShell 5.1 (System.Drawing). Tüm rastgelelik sabit tohumludur:
#  aynı girdilerle her çalıştırmada aynı PNG çıkar.
# =====================================================================
[CmdletBinding()]
param(
    [string]$OutDir,
    [string]$Background,          # isteğe bağlı: hazır arka plan (kapla-kırp ile yerleşir)
    [double]$FocusY = 0.6,        # hazır arka planda dikey kırpma noktası (0 üst, 1 alt)
    [string]$Version              # boşsa src\SyHost\SyHost.csproj içindeki sürümden (ör. 1.0)
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $Repo 'docs\images' }
Add-Type -AssemblyName System.Drawing

if (-not $Version) {
    $Version = '1.0'
    $csproj = Join-Path $Repo 'src\SyHost\SyHost.csproj'
    if (Test-Path $csproj) {
        $vm = [regex]::Match([IO.File]::ReadAllText($csproj), '<Version>(\d+)\.(\d+)')
        if ($vm.Success) { $Version = $vm.Groups[1].Value + '.' + $vm.Groups[2].Value }
    }
}
$Version = $Version.TrimStart('v', 'V')

# ---------- Piksel işleri: kayan noktalı tuval, ışıma, bulanıklık, titreşimli (dither) PNG ----------
$ArtCode = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace SyHostBanner
{
    public sealed class Canvas
    {
        public readonly int W;
        public readonly int H;
        public readonly float[] R;
        public readonly float[] G;
        public readonly float[] B;
        public Canvas(int w, int h) { W = w; H = h; R = new float[w * h]; G = new float[w * h]; B = new float[w * h]; }
    }

    // Sabit tohumlu xorshift32: her makinede aynı sayı dizisi
    public sealed class Rng
    {
        private uint s;
        public Rng(uint seed) { s = seed == 0 ? 0x9E3779B9u : seed; for (int i = 0; i < 4; i++) Next(); }
        public uint Next() { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return s; }
        public double D() { return (Next() >> 8) / 16777216.0; }
        public double Range(double a, double b) { return a + (b - a) * D(); }
        public int Int(int a, int bExclusive) { return a + (int)(D() * (bExclusive - a)); }
    }

    public static class Art
    {
        static void Add(Canvas c, int x, int y, double r, double g, double b)
        {
            if (x < 0 || y < 0 || x >= c.W || y >= c.H) return;
            int i = y * c.W + x; c.R[i] += (float)r; c.G[i] += (float)g; c.B[i] += (float)b;
        }

        // Dikey geçiş: stops = y, r, g, b, y, r, g, b ... (y artan)
        public static void Gradient(Canvas c, double[] stops)
        {
            int n = stops.Length / 4;
            for (int y = 0; y < c.H; y++)
            {
                double yy = y + 0.5, r, g, b;
                if (yy <= stops[0]) { r = stops[1]; g = stops[2]; b = stops[3]; }
                else if (yy >= stops[(n - 1) * 4]) { int k = (n - 1) * 4; r = stops[k + 1]; g = stops[k + 2]; b = stops[k + 3]; }
                else
                {
                    int k = 0;
                    while (k < n - 2 && yy > stops[(k + 1) * 4]) k++;
                    int a = k * 4, e = (k + 1) * 4;
                    double t = (yy - stops[a]) / (stops[e] - stops[a]);
                    t = t * t * (3 - 2 * t);
                    r = stops[a + 1] + (stops[e + 1] - stops[a + 1]) * t;
                    g = stops[a + 2] + (stops[e + 2] - stops[a + 2]) * t;
                    b = stops[a + 3] + (stops[e + 3] - stops[a + 3]) * t;
                }
                for (int x = 0; x < c.W; x++) { int i = y * c.W + x; c.R[i] = (float)r; c.G[i] = (float)g; c.B[i] = (float)b; }
            }
        }

        // Elips biçimli yumuşak ışık (ekleyerek)
        public static void Glow(Canvas c, double cx, double cy, double rx, double ry, double r, double g, double b, double k)
        {
            int x0 = Math.Max(0, (int)Math.Floor(cx - rx * 2)), x1 = Math.Min(c.W, (int)Math.Ceiling(cx + rx * 2));
            int y0 = Math.Max(0, (int)Math.Floor(cy - ry * 2)), y1 = Math.Min(c.H, (int)Math.Ceiling(cy + ry * 2));
            for (int y = y0; y < y1; y++)
            {
                double dy = (y + 0.5 - cy) / ry;
                for (int x = x0; x < x1; x++)
                {
                    double dx = (x + 0.5 - cx) / rx;
                    double f = Math.Exp(-2.0 * (dx * dx + dy * dy)) * k;
                    if (f < 0.0005) continue;
                    int i = y * c.W + x;
                    c.R[i] += (float)(r * f); c.G[i] += (float)(g * f); c.B[i] += (float)(b * f);
                }
            }
        }

        // Kenarlara doğru hafif kararma
        public static void Vignette(Canvas c, double strength)
        {
            double cx = c.W / 2.0, cy = c.H / 2.0;
            for (int y = 0; y < c.H; y++)
            {
                double dy = (y + 0.5 - cy) / cy;
                for (int x = 0; x < c.W; x++)
                {
                    double dx = (x + 0.5 - cx) / cx;
                    double t = (dx * dx * 0.7 + dy * dy - 0.35) / 1.35;
                    if (t <= 0) continue;
                    if (t > 1) t = 1;
                    float f = (float)(1 - strength * t * t * (3 - 2 * t));
                    int i = y * c.W + x; c.R[i] *= f; c.G[i] *= f; c.B[i] *= f;
                }
            }
        }

        // Dikdörtgen (saydamlıkla karıştırarak)
        public static void Rect(Canvas c, int x0, int y0, int x1, int y1, double r, double g, double b, double a)
        {
            x0 = Math.Max(0, x0); y0 = Math.Max(0, y0); x1 = Math.Min(c.W, x1); y1 = Math.Min(c.H, y1);
            float ia = (float)(1 - a), fr = (float)(r * a), fg = (float)(g * a), fb = (float)(b * a);
            for (int y = y0; y < y1; y++)
                for (int x = x0; x < x1; x++)
                {
                    int i = y * c.W + x;
                    c.R[i] = c.R[i] * ia + fr; c.G[i] = c.G[i] * ia + fg; c.B[i] = c.B[i] * ia + fb;
                }
        }

        // Satır satır değişen saydamlıkla renk (sis bandı)
        public static void Haze(Canvas c, int y0, int y1, double r, double g, double b, double a0, double a1)
        {
            for (int y = Math.Max(0, y0); y < Math.Min(c.H, y1); y++)
            {
                double t = y1 == y0 ? 0 : (y + 0.5 - y0) / (y1 - y0);
                double a = a0 + (a1 - a0) * t;
                float ia = (float)(1 - a), fr = (float)(r * a), fg = (float)(g * a), fb = (float)(b * a);
                for (int x = 0; x < c.W; x++)
                {
                    int i = y * c.W + x;
                    c.R[i] = c.R[i] * ia + fr; c.G[i] = c.G[i] * ia + fg; c.B[i] = c.B[i] * ia + fb;
                }
            }
        }

        // Yumuşak nokta (yıldız, led parıltısı)
        public static void Dot(Canvas c, double x, double y, double sigma, double r, double g, double b, double k)
        {
            double rad = sigma * 3.5 + 1;
            int x0 = Math.Max(0, (int)Math.Floor(x - rad)), x1 = Math.Min(c.W, (int)Math.Ceiling(x + rad));
            int y0 = Math.Max(0, (int)Math.Floor(y - rad)), y1 = Math.Min(c.H, (int)Math.Ceiling(y + rad));
            double inv = 1.0 / (2 * sigma * sigma);
            for (int yy = y0; yy < y1; yy++)
                for (int xx = x0; xx < x1; xx++)
                {
                    double dx = xx + 0.5 - x, dy = yy + 0.5 - y;
                    double f = k * Math.Exp(-(dx * dx + dy * dy) * inv);
                    if (f < 0.002) continue;
                    int i = yy * c.W + xx;
                    c.R[i] += (float)(r * f); c.G[i] += (float)(g * f); c.B[i] += (float)(b * f);
                }
        }

        // Parlak yıldızın dört kollu ışını
        public static void Spikes(Canvas c, double x, double y, double len, double r, double g, double b, double k)
        {
            int L = (int)Math.Ceiling(len), cx = (int)Math.Floor(x), cy = (int)Math.Floor(y);
            for (int d = 1; d <= L; d++)
            {
                double f = k * Math.Exp(-d / (len * 0.3));
                Add(c, cx + d, cy, r * f, g * f, b * f); Add(c, cx - d, cy, r * f, g * f, b * f);
                Add(c, cx, cy + d, r * f, g * f, b * f); Add(c, cx, cy - d, r * f, g * f, b * f);
            }
        }

        // Kayan yıldız: baş beyaz, kuyruk kırmızıdan karanlığa (uygulamadaki gökyüzüyle aynı renkler)
        public static void Meteor(Canvas c, double hx, double hy, double tx, double ty, double width, double k)
        {
            double vx = tx - hx, vy = ty - hy, len = Math.Sqrt(vx * vx + vy * vy);
            if (len < 1) return;
            double ux = vx / len, uy = vy / len, pad = width * 4 + 2;
            int x0 = Math.Max(0, (int)Math.Floor(Math.Min(hx, tx) - pad)), x1 = Math.Min(c.W, (int)Math.Ceiling(Math.Max(hx, tx) + pad));
            int y0 = Math.Max(0, (int)Math.Floor(Math.Min(hy, ty) - pad)), y1 = Math.Min(c.H, (int)Math.Ceiling(Math.Max(hy, ty) + pad));
            for (int y = y0; y < y1; y++)
                for (int x = x0; x < x1; x++)
                {
                    double px = x + 0.5 - hx, py = y + 0.5 - hy;
                    double along = px * ux + py * uy, t = along / len, f;
                    if (t > 1) continue;
                    if (t < 0) { double d2 = px * px + py * py; f = Math.Exp(-d2 / (width * width) * 1.6); t = 0; }
                    else
                    {
                        double across = px * uy - py * ux, w = width * (1 - 0.72 * t);
                        f = Math.Exp(-(across * across) / (w * w) * 1.6) * Math.Pow(1 - t, 1.25);
                    }
                    if (f < 0.002) continue;
                    double cr, cg, cb;
                    if (t < 0.15) { cr = 255; cg = 235; cb = 230; }
                    else if (t < 0.5) { double q = (t - 0.15) / 0.35; cr = 255 - 20 * q; cg = 235 - 190 * q; cb = 230 - 175 * q; }
                    else { double q = (t - 0.5) / 0.5; cr = 235 - 170 * q; cg = 45 - 30 * q; cb = 55 - 35 * q; }
                    f *= k;
                    int i = y * c.W + x;
                    c.R[i] += (float)(cr * f); c.G[i] += (float)(cg * f); c.B[i] += (float)(cb * f);
                }
            Dot(c, hx, hy, width * 0.85, 255, 242, 238, k * 0.85);
            Dot(c, hx, hy, width * 4.5, 239, 55, 66, k * 0.07);
        }

        // Dikdörtgenlerin (logo blokları) bulanık ışıltısı: rects = x0, y0, x1, y1, ...
        public static void RectGlow(Canvas c, int[] rects, int radius, double r, double g, double b, double k)
        {
            float[] m = new float[c.W * c.H];
            for (int n = 0; n + 3 < rects.Length; n += 4)
                for (int y = Math.Max(0, rects[n + 1]); y < Math.Min(c.H, rects[n + 3]); y++)
                    for (int x = Math.Max(0, rects[n]); x < Math.Min(c.W, rects[n + 2]); x++) m[y * c.W + x] = 1f;
            for (int p = 0; p < 3; p++) { BoxBlurH(m, c.W, c.H, radius); BoxBlurV(m, c.W, c.H, radius); }
            for (int i = 0; i < m.Length; i++)
            {
                double f = m[i] * k;
                if (f < 0.0005) continue;
                c.R[i] += (float)(r * f); c.G[i] += (float)(g * f); c.B[i] += (float)(b * f);
            }
        }

        static void BoxBlurH(float[] m, int w, int h, int r)
        {
            float[] tmp = new float[w]; double win = 2 * r + 1;
            for (int y = 0; y < h; y++)
            {
                int row = y * w; double acc = 0;
                for (int x = 0; x <= r && x < w; x++) acc += m[row + x];
                for (int x = 0; x < w; x++)
                {
                    tmp[x] = (float)(acc / win);
                    int xo = x - r, xi = x + r + 1;
                    if (xo >= 0) acc -= m[row + xo];
                    if (xi < w) acc += m[row + xi];
                }
                Array.Copy(tmp, 0, m, row, w);
            }
        }

        static void BoxBlurV(float[] m, int w, int h, int r)
        {
            float[] tmp = new float[h]; double win = 2 * r + 1;
            for (int x = 0; x < w; x++)
            {
                double acc = 0;
                for (int y = 0; y <= r && y < h; y++) acc += m[y * w + x];
                for (int y = 0; y < h; y++)
                {
                    tmp[y] = (float)(acc / win);
                    int yo = y - r, yi = y + r + 1;
                    if (yo >= 0) acc -= m[yo * w + x];
                    if (yi < h) acc += m[yi * w + x];
                }
                for (int y = 0; y < h; y++) m[y * w + x] = tmp[y];
            }
        }

        // Hazır bir resmi tuvale al (24 bit, tuvalle aynı boyutta)
        public static void Load(Canvas c, Bitmap bmp, double gain)
        {
            BitmapData d = bmp.LockBits(new Rectangle(0, 0, c.W, c.H), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            byte[] row = new byte[d.Stride];
            for (int y = 0; y < c.H; y++)
            {
                Marshal.Copy(new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), row, 0, d.Stride);
                for (int x = 0; x < c.W; x++)
                {
                    int i = y * c.W + x;
                    c.B[i] = (float)(row[x * 3] * gain); c.G[i] = (float)(row[x * 3 + 1] * gain); c.R[i] = (float)(row[x * 3 + 2] * gain);
                }
            }
            bmp.UnlockBits(d);
        }

        // 8x8 Bayer titreşimi: koyu geçişlerde bantlaşma olmasın
        static readonly int[] Bayer8 = {
             0, 32,  8, 40,  2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26,
            12, 44,  4, 36, 14, 46,  6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
             3, 35, 11, 43,  1, 33,  9, 41, 51, 19, 59, 27, 49, 17, 57, 25,
            15, 47,  7, 39, 13, 45,  5, 37, 63, 31, 55, 23, 61, 29, 53, 21 };

        static byte Q(double v) { int n = (int)Math.Floor(v + 0.5); return (byte)(n < 0 ? 0 : (n > 255 ? 255 : n)); }

        public static Bitmap ToBitmap(Canvas c)
        {
            Bitmap bmp = new Bitmap(c.W, c.H, PixelFormat.Format24bppRgb);
            BitmapData d = bmp.LockBits(new Rectangle(0, 0, c.W, c.H), ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
            byte[] row = new byte[d.Stride];
            for (int y = 0; y < c.H; y++)
            {
                for (int x = 0; x < c.W; x++)
                {
                    int i = y * c.W + x;
                    double th = (Bayer8[(y & 7) * 8 + (x & 7)] + 0.5) / 64.0 - 0.5;
                    row[x * 3] = Q(c.B[i] + th); row[x * 3 + 1] = Q(c.G[i] + th); row[x * 3 + 2] = Q(c.R[i] + th);
                }
                Marshal.Copy(row, 0, new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), d.Stride);
            }
            bmp.UnlockBits(d);
            return bmp;
        }
    }
}
'@
if (-not ('SyHostBanner.Art' -as [type])) { Add-Type -TypeDefinition $ArtCode -ReferencedAssemblies System.Drawing }

# ---------- Logo: legacy\src\SyHost.ps1 içindeki blok yazı tipinin birebir kopyası ----------
$Font = @{
    'S' = @('███████╗', '██╔════╝', '███████╗', '╚════██║', '███████║', '╚══════╝')
    'Y' = @('██╗   ██╗', '╚██╗ ██╔╝', ' ╚████╔╝ ', '  ╚██╔╝  ', '   ██║   ', '   ╚═╝   ')
    'H' = @('██╗  ██╗', '██║  ██║', '███████║', '██╔══██║', '██║  ██║', '╚═╝  ╚═╝')
    'O' = @(' ██████╗ ', '██╔═══██╗', '██║   ██║', '██║   ██║', '╚██████╔╝', ' ╚═════╝ ')
    'T' = @('████████╗', '╚══██╔══╝', '   ██║   ', '   ██║   ', '   ██║   ', '   ╚═╝   ')
}
# Uygulamadaki logo değişmişse afiş de değişmeli: kopya eskimişse dur
$legacySrc = Join-Path $Repo 'legacy\src\SyHost.ps1'
if (Test-Path $legacySrc) {
    $src = [IO.File]::ReadAllText($legacySrc, [Text.Encoding]::UTF8)
    foreach ($k in 'S', 'Y', 'H', 'O', 'T') {
        $fm = [regex]::Match($src, "(?m)^\s*'$k' = @\((.+)\)\s*$")
        $rowsSrc = @([regex]::Matches($fm.Groups[1].Value, "'([^']*)'") | ForEach-Object { $_.Groups[1].Value })
        if (-not $fm.Success -or ($rowsSrc -join '|') -cne ($Font[$k] -join '|')) {
            throw "Logo yazı tipi legacy\src\SyHost.ps1 ile aynı değil ('$k'). Önce bu dosyadaki kopyayı eşitleyin."
        }
    }
}
$LogoPlain = 0..5 | ForEach-Object { $row = $_; ('SYHOST'.ToCharArray() | ForEach-Object { $Font[[string]$_][$row] }) -join '' }
$LogoW = $LogoPlain[0].Length

# ---------- Yazı tipi: uygulamanın kurduğu Cascadia Mono ----------
$Pfc = New-Object Drawing.Text.PrivateFontCollection
foreach ($ff in 'CascadiaMono-Regular.ttf', 'CascadiaMono-Bold.ttf') {
    $fp = Join-Path $Repo "legacy\fonts\$ff"
    if (Test-Path $fp) { $Pfc.AddFontFile($fp) }
}
if ($Pfc.Families.Count -gt 0) { $Family = $Pfc.Families[0] }
else { Write-Warning 'legacy\fonts\CascadiaMono-*.ttf bulunamadı, Consolas kullanılıyor (çıktı farklı olur).'; $Family = New-Object Drawing.FontFamily 'Consolas' }

# ---------- Yardımcılar ----------
function New-Color([double[]]$rgb, [int]$a = 255) { [Drawing.Color]::FromArgb($a, [int]$rgb[0], [int]$rgb[1], [int]$rgb[2]) }

# Yazıyı taban çizgisine göre yol olarak üretir (ipucu yok, her boyutta aynı biçim)
function New-TextPath([string]$text, [Drawing.FontStyle]$style, [double]$px, [double]$x, [double]$baseline) {
    $asc = $px * $Family.GetCellAscent($style) / $Family.GetEmHeight($style)
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddString($text, $Family, [int]$style, [single]$px, (New-Object Drawing.PointF([single]$x, [single]($baseline - $asc))), [Drawing.StringFormat]::GenericTypographic)
    , $path
}
# Tek aralıklı yazı tipinde bir karakterin genişliği (█ hücreyi tam doldurur)
function Get-Advance([double]$px) { $p = New-TextPath ([string][char]0x2588) ([Drawing.FontStyle]::Regular) $px 0 0; $b = $p.GetBounds(); $p.Dispose(); [double]$b.Width }
function Get-CapHeight([Drawing.FontStyle]$style, [double]$px) { $p = New-TextPath 'H' $style $px 0 0; $b = $p.GetBounds(); $p.Dispose(); [double]$b.Height }

function New-RoundRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = [single](2 * $r)
    $p.AddArc([single]$x, [single]$y, $d, $d, 180, 90)
    $p.AddArc([single]($x + $w - 2 * $r), [single]$y, $d, $d, 270, 90)
    $p.AddArc([single]($x + $w - 2 * $r), [single]($y + $h - 2 * $r), $d, $d, 0, 90)
    $p.AddArc([single]$x, [single]($y + $h - 2 * $r), $d, $d, 90, 90)
    $p.CloseFigure()
    , $p
}

# Bir logo hücresindeki karakterin dikdörtgenleri (hücreye göre x0, y0, x1, y1).
# Çift çizgili gölge karakterleri terminaldeki gibi iki ince çizgiyle çizilir.
function Add-GlyphRects([System.Collections.Generic.List[int]]$out, [char]$chr, [int]$cw, [int]$ch, [int]$t, [int]$gap) {
    $a = [int][Math]::Floor(($ch - (2 * $t + $gap)) / 2); $b = [int][Math]::Floor(($cw - (2 * $t + $gap)) / 2)
    $h1a = $a; $h1b = $a + $t; $h2a = $a + $t + $gap; $h2b = $h2a + $t
    $v1a = $b; $v1b = $b + $t; $v2a = $b + $t + $gap; $v2b = $v2a + $t
    $r = switch ([int]$chr) {
        0x2588 { 0, 0, $cw, $ch }                                                         # █
        0x2550 { 0, $h1a, $cw, $h1b, 0, $h2a, $cw, $h2b }                                   # ═
        0x2551 { $v1a, 0, $v1b, $ch, $v2a, 0, $v2b, $ch }                                   # ║
        0x2557 { 0, $h1a, $v2b, $h1b, $v2a, $h1a, $v2b, $ch, 0, $h2a, $v1b, $h2b, $v1a, $h2a, $v1b, $ch }   # ╗
        0x2554 { $v1a, $h1a, $cw, $h1b, $v1a, $h1a, $v1b, $ch, $v2a, $h2a, $cw, $h2b, $v2a, $h2a, $v2b, $ch } # ╔
        0x255D { 0, $h2a, $v2b, $h2b, $v2a, 0, $v2b, $h2b, 0, $h1a, $v1b, $h1b, $v1a, 0, $v1b, $h1b }       # ╝
        0x255A { $v1a, $h2a, $cw, $h2b, $v1a, 0, $v1b, $h2b, $v2a, $h1a, $cw, $h1b, $v2a, 0, $v2b, $h1b }   # ╚
        default { throw "Logo için çizimi tanımlanmamış karakter: $chr" }
    }
    foreach ($v in $r) { $out.Add([int]$v) }
}

# Logoyu uygulamadaki renk dalgasının durmuş bir karesiyle çizer (Render-Logo ile aynı formül):
# her hücre tek renk, dolu bloklar parlak kırmızı, gölge çizgileri koyu kırmızı.
function Draw-Logo([Drawing.Graphics]$g, [int]$x0, [int]$y0, [int]$cw, [int]$ch, [double]$now) {
    $t = [Math]::Max(1, [int][Math]::Round($cw / 6.5)); $gap = $t
    $brush = New-Object Drawing.SolidBrush ([Drawing.Color]::Black)
    for ($r0 = 0; $r0 -lt 6; $r0++) {
        $line = $LogoPlain[$r0]
        for ($i = 0; $i -lt $line.Length; $i++) {
            $chr = $line[$i]
            if ($chr -eq ' ') { continue }
            $wave = ([Math]::Sin(($i / 7.0) - $now * 2.6 + $r0 * 0.35) + 1) / 2
            if ($chr -eq [char]0x2588) { $cr = 175 + 80 * $wave; $cg = 18 + 70 * [Math]::Pow($wave, 3); $cb = 30 + 70 * [Math]::Pow($wave, 3) }
            else { $cr = 70 + 40 * $wave; $cg = 14; $cb = 20 }
            $brush.Color = [Drawing.Color]::FromArgb([int]$cr, [int]$cg, [int]$cb)
            $rl = New-Object System.Collections.Generic.List[int]
            Add-GlyphRects $rl $chr $cw $ch $t $gap
            $x = $x0 + $i * $cw; $y = $y0 + $r0 * $ch
            for ($n = 0; $n -lt $rl.Count; $n += 4) {
                $g.FillRectangle($brush, $x + $rl[$n], $y + $rl[$n + 1], $rl[$n + 2] - $rl[$n], $rl[$n + 3] - $rl[$n + 1])
            }
        }
    }
    $brush.Dispose()
}
# Dolu blokların mutlak dikdörtgenleri (logonun arkasındaki ışıltı için)
function Get-LogoBlocks([int]$x0, [int]$y0, [int]$cw, [int]$ch) {
    $blocks = New-Object System.Collections.Generic.List[int]
    for ($r0 = 0; $r0 -lt 6; $r0++) {
        $line = $LogoPlain[$r0]
        for ($i = 0; $i -lt $line.Length; $i++) {
            if ($line[$i] -ne [char]0x2588) { continue }
            $x = $x0 + $i * $cw; $y = $y0 + $r0 * $ch
            $blocks.Add($x); $blocks.Add($y); $blocks.Add($x + $cw); $blocks.Add($y + $ch)
        }
    }
    , $blocks.ToArray()
}

# ---------- Gökyüzü: koyu gece, ufukta kırmızı ışık, yıldızlar ----------
function Add-Sky($cv, [int]$W, [int]$H, [int]$horizonY, [double[]]$keep, [uint32]$seed) {
    [SyHostBanner.Art]::Gradient($cv, [double[]]@(0, 9, 7, 8, ($horizonY * 0.45), 14, 11, 12, $horizonY, 34, 11, 16, $H, 34, 11, 16))
    [SyHostBanner.Art]::Glow($cv, $W * 0.5, $horizonY + $H * 0.08, $W * 0.62, $H * 0.46, 120, 10, 20, 0.62)
    [SyHostBanner.Art]::Glow($cv, $W * 0.5, $horizonY + 6, $W * 0.24, $H * 0.11, 239, 55, 66, 0.16)
    # logonun arkasında çok hafif bir aydınlık
    [SyHostBanner.Art]::Glow($cv, ($keep[0] + $keep[2]) / 2, ($keep[1] + $keep[3]) / 2, ($keep[2] - $keep[0]) * 0.62, ($keep[3] - $keep[1]) * 0.9, 120, 10, 20, 0.16)
    $rng = [SyHostBanner.Rng]::new($seed)
    $count = [int]($W * $horizonY / 1900)
    for ($n = 0; $n -lt $count; $n++) {
        $x = $rng.Range(0, $W); $y = $rng.Range(0, $horizonY - 8)
        $kind = $rng.D(); $size = $rng.D(); $bright = $rng.D()
        if ($rng.D() -lt 0.55 * [Math]::Pow($y / $horizonY, 2)) { continue }   # ufka yakın yıldızlar seyrek
        if ($x -gt $keep[0] - 14 -and $x -lt $keep[2] + 14 -and $y -gt $keep[1] - 14 -and $y -lt $keep[3] + 14) { continue }
        if ($kind -lt 0.72) {
            # uygulamadaki gibi tozlu kırmızı yıldız
            $v = 40 + 70 * $bright
            [SyHostBanner.Art]::Dot($cv, $x, $y, 0.42 + 0.35 * $size, $v + 20, $v * 0.35, $v * 0.4, 1.7)
        } else {
            [SyHostBanner.Art]::Dot($cv, $x, $y, 0.38 + 0.3 * $size, 240, 232, 236, 0.25 + 0.55 * $bright)
        }
    }
    # birkaç parlak yıldız
    for ($n = 0; $n -lt [int]($W / 260); $n++) {
        $x = $rng.Range($W * 0.03, $W * 0.97); $y = $rng.Range($horizonY * 0.06, $horizonY * 0.7)
        if ($x -gt $keep[0] - 30 -and $x -lt $keep[2] + 30 -and $y -gt $keep[1] - 30 -and $y -lt $keep[3] + 30) { continue }
        [SyHostBanner.Art]::Dot($cv, $x, $y, 0.75, 255, 240, 240, 0.9)
        [SyHostBanner.Art]::Dot($cv, $x, $y, 3.2, 239, 55, 66, 0.10)
        [SyHostBanner.Art]::Spikes($cv, $x, $y, 6.0, 255, 210, 215, 0.35)
    }
}

# ---------- Ufuk: bloklu tepeler, kare çam ve meşe ağaçları, ledli sunucu blokları ----------
# Ağaç biçimleri: her # küçük bir blok
$TreeShapes = @(
    @('...#...', '..###..', '..###..', '.#####.', '.#####.', '#######', '...#...'),   # uzun çam
    @('..#..', '.###.', '.###.', '#####', '..#..'),                                  # kısa çam
    @('.###.', '#####', '#####', '..#..')                                            # meşe
)

function Add-Horizon($cv, [int]$W, [int]$H, [int]$horizonY, [double]$s, [double[]]$keep, [uint32]$seed) {
    $rng = [SyHostBanner.Rng]::new($seed)
    $mid = $W / 2.0
    $layers = @(
        # uzak tepeler: sisli, gökyüzüne yakın ton
        @{ U = [int](12 * $s); Ground = $horizonY + [int](30 * $s); Amp = 7; F = 0.16; Col = @(44, 12, 18); Rim = @(170, 30, 44); RimA = 0.40; Trees = 0.0; Valley = 0.75 },
        # orta katman: çamlı basamaklı arazi
        @{ U = [int](14 * $s); Ground = $horizonY + [int](58 * $s); Amp = 4; F = 0.27; Col = @(24, 9, 13); Rim = @(200, 36, 50); RimA = 0.45; Trees = 0.2; Valley = 0.8 },
        # ön plan: en koyu
        @{ U = [int](20 * $s); Ground = $H + [int](6 * $s); Amp = 2; F = 0.35; Col = @(11, 7, 9); Rim = @(239, 55, 66); RimA = 0.30; Trees = 0.0; Valley = 0.6 }
    )
    for ($li = 0; $li -lt $layers.Count; $li++) {
        $L = $layers[$li]; $u = $L.U
        $p1 = $rng.Range(0, 6.28); $p2 = $rng.Range(0, 6.28); $p3 = $rng.Range(0, 6.28)
        $cols = [int][Math]::Ceiling($W / $u) + 2
        $off = $rng.Int(0, $u)
        $tops = New-Object int[] $cols
        for ($j = 0; $j -lt $cols; $j++) {
            $xc = $j * $u - $off + $u / 2.0
            $n = 0.5 + 0.5 * (0.55 * [Math]::Sin($j * $L.F + $p1) + 0.3 * [Math]::Sin($j * $L.F * 0.37 + $p2) + 0.15 * [Math]::Sin($j * $L.F * 2.3 + $p3))
            $valley = 1 - $L.Valley * [Math]::Exp(-[Math]::Pow(($xc - $mid) / ($W * 0.2), 2))
            $tops[$j] = $L.Ground - (1 + [int][Math]::Round($L.Amp * $n * $valley)) * $u
        }
        for ($j = 0; $j -lt $cols; $j++) {
            $x = $j * $u - $off
            [SyHostBanner.Art]::Rect($cv, $x, $tops[$j], $x + $u, $H, $L.Col[0], $L.Col[1], $L.Col[2], 1.0)
        }
        # kenar ışığı: üst yüzler ve ortadaki ışığa bakan basamak kenarları
        for ($j = 0; $j -lt $cols; $j++) {
            $x = $j * $u - $off; $xc = $x + $u / 2.0
            [SyHostBanner.Art]::Rect($cv, $x, $tops[$j], $x + $u, $tops[$j] + 1, $L.Rim[0], $L.Rim[1], $L.Rim[2], $L.RimA)
            if ($j -gt 0 -and $tops[$j] -lt $tops[$j - 1] -and $xc -gt $mid) {
                [SyHostBanner.Art]::Rect($cv, $x, $tops[$j], $x + 1, $tops[$j - 1], $L.Rim[0], $L.Rim[1], $L.Rim[2], $L.RimA * 0.6)
            }
            if ($j -lt $cols - 1 -and $tops[$j] -lt $tops[$j + 1] -and $xc -lt $mid) {
                [SyHostBanner.Art]::Rect($cv, $x + $u - 1, $tops[$j], $x + $u, $tops[$j + 1], $L.Rim[0], $L.Rim[1], $L.Rim[2], $L.RimA * 0.6)
            }
        }
        # ağaçlar: ortadaki yazının altı boş kalsın
        if ($L.Trees -gt 0) {
            $q = [Math]::Max(3, [int][Math]::Round($u / 3.0))
            for ($j = 1; $j -lt $cols - 1; $j++) {
                if ($rng.D() -ge $L.Trees) { continue }
                $shape = $TreeShapes[[Math]::Min(2, [int]($rng.D() * 3.6))]
                $sw = $shape[0].Length
                $x = $j * $u - $off + [int](($u - $sw * $q) / 2)
                if ([Math]::Abs($x + $sw * $q / 2.0 - $mid) -lt $W * 0.14) { continue }
                $baseY = $tops[$j]; $rows = $shape.Count
                for ($ry = 0; $ry -lt $rows; $ry++) {
                    for ($rx = 0; $rx -lt $sw; $rx++) {
                        if ($shape[$ry][$rx] -ne '#') { continue }
                        $yy = $baseY - ($rows - $ry) * $q
                        [SyHostBanner.Art]::Rect($cv, $x + $rx * $q, $yy, $x + ($rx + 1) * $q, $yy + $q, $L.Col[0], $L.Col[1], $L.Col[2], 1.0)
                        # her basamağın üstüne ince ışık
                        if ($ry -eq 0 -or $shape[$ry - 1][$rx] -ne '#') {
                            [SyHostBanner.Art]::Rect($cv, $x + $rx * $q, $yy, $x + ($rx + 1) * $q, $yy + 1, $L.Rim[0], $L.Rim[1], $L.Rim[2], $L.RimA * 0.7)
                        }
                    }
                }
                $j += 2
            }
        }
        # katmanlar arasında sis: derinlik
        if ($li -eq 0) { [SyHostBanner.Art]::Haze($cv, $horizonY - [int](40 * $s), $L.Ground + [int](12 * $s), 80, 14, 22, 0.0, 0.30) }
        if ($li -eq 1) { [SyHostBanner.Art]::Haze($cv, $L.Ground - [int](30 * $s), $L.Ground + [int](20 * $s), 60, 12, 18, 0.0, 0.18) }
    }

    # ön planda üst üste dizilmiş sunucu blokları: ek çizgileri, ön panelde kırmızı ve beyaz ledler
    $u = [int](18 * $s)
    $stacks = @(
        @{ X = 0.03; Wb = 2; Hb = 4; Mast = $true }, @{ X = 0.105; Wb = 1; Hb = 2 }, @{ X = 0.15; Wb = 2; Hb = 3 },
        @{ X = 0.805; Wb = 2; Hb = 3 }, @{ X = 0.87; Wb = 2; Hb = 5; Mast = $true }, @{ X = 0.945; Wb = 1; Hb = 2 }
    )
    foreach ($st in $stacks) {
        $x0 = [int]($W * $st.X); $y0 = $H - $st.Hb * $u
        $lightLeft = ($x0 + $st.Wb * $u / 2.0) -gt $mid
        for ($by = 0; $by -lt $st.Hb; $by++) {
            for ($bx = 0; $bx -lt $st.Wb; $bx++) {
                $cx0 = $x0 + $bx * $u; $cy0 = $y0 + $by * $u
                [SyHostBanner.Art]::Rect($cv, $cx0, $cy0, $cx0 + $u, $cy0 + $u, 15, 10, 12, 1.0)
                [SyHostBanner.Art]::Rect($cv, $cx0 + $u - 1, $cy0, $cx0 + $u, $cy0 + $u, 6, 4, 5, 1.0)
                [SyHostBanner.Art]::Rect($cv, $cx0, $cy0 + $u - 1, $cx0 + $u, $cy0 + $u, 6, 4, 5, 1.0)
                # ön panel: bir sıra led ve bir yuva çizgisi
                $ledY = $cy0 + [int][Math]::Round($u * 0.3); $ls = [Math]::Max(2, [int][Math]::Round(2 * $s))
                for ($k = 0; $k -lt 3; $k++) {
                    $lx = $cx0 + [int][Math]::Round($u * 0.2) + $k * [int][Math]::Round($u * 0.2)
                    $roll = $rng.D()
                    if ($roll -lt 0.3) { [SyHostBanner.Art]::Rect($cv, $lx, $ledY, $lx + $ls, $ledY + $ls, 40, 14, 18, 1.0); continue }
                    if ($roll -lt 0.85) { $lc = @(239, 55, 66) } else { $lc = @(255, 244, 244) }
                    $lk = 0.65 + 0.35 * $rng.D()
                    [SyHostBanner.Art]::Rect($cv, $lx, $ledY, $lx + $ls, $ledY + $ls, $lc[0], $lc[1], $lc[2], $lk)
                    [SyHostBanner.Art]::Dot($cv, $lx + $ls / 2.0, $ledY + $ls / 2.0, 2.4 * $s, $lc[0], $lc[1], $lc[2], 0.09 * $lk)
                }
                $slotY = $cy0 + [int][Math]::Round($u * 0.64)
                [SyHostBanner.Art]::Rect($cv, $cx0 + [int]($u * 0.18), $slotY, $cx0 + $u - [int]($u * 0.18), $slotY + 1, 30, 13, 17, 1.0)
            }
        }
        # üst kenar ve ışığa bakan yan kenar
        [SyHostBanner.Art]::Rect($cv, $x0, $y0, $x0 + $st.Wb * $u, $y0 + 1, 239, 55, 66, 0.5)
        if ($lightLeft) { [SyHostBanner.Art]::Rect($cv, $x0, $y0, $x0 + 1, $H, 239, 55, 66, 0.22) }
        else { [SyHostBanner.Art]::Rect($cv, $x0 + $st.Wb * $u - 1, $y0, $x0 + $st.Wb * $u, $H, 239, 55, 66, 0.22) }
        # anten ve tepesinde kırmızı ışık
        if ($st.Mast) {
            $mx = $x0 + [int]($st.Wb * $u / 2) - 1; $mh = [int](16 * $s)
            [SyHostBanner.Art]::Rect($cv, $mx, $y0 - $mh, $mx + 2, $y0, 18, 11, 13, 1.0)
            [SyHostBanner.Art]::Rect($cv, $mx - 1, $y0 - $mh - 3, $mx + 3, $y0 - $mh, 255, 70, 80, 1.0)
            [SyHostBanner.Art]::Dot($cv, $mx + 1, $y0 - $mh - 1.5, 4.5 * $s, 239, 55, 66, 0.45)
            [SyHostBanner.Art]::Dot($cv, $mx + 1, $y0 - $mh - 1.5, 14 * $s, 239, 55, 66, 0.06)
        }
    }
}

# ---------- Tek bir görseli üretir ----------
function Build-Image([hashtable]$o) {
    $W = $o.W; $H = $o.H; $cw = $o.Cell; $ch = 2 * $cw
    $logoW = $LogoW * $cw; $logoH = 6 * $ch
    $lx = [int][Math]::Floor(($W - $logoW) / 2); $ly = $o.LogoY
    $tagPx = $o.TagPx
    $capTag = Get-CapHeight ([Drawing.FontStyle]::Regular) $tagPx
    $tagBase = $ly + $logoH + $o.TagGap + $capTag
    $keep = [double[]]@($lx, $ly, ($lx + $logoW), ($tagBase + $tagPx * 0.3))

    $cv = [SyHostBanner.Canvas]::new($W, $H)
    if ($Background) {
        $src = [Drawing.Image]::FromFile((Resolve-Path $Background).Path)
        $scale = [Math]::Max($W / $src.Width, $H / $src.Height)
        $sw = $W / $scale; $sh = $H / $scale
        $tmp = New-Object Drawing.Bitmap $W, $H, ([Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $tg = [Drawing.Graphics]::FromImage($tmp)
        $tg.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $tg.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $tg.DrawImage($src, (New-Object Drawing.Rectangle 0, 0, $W, $H), [single](($src.Width - $sw) / 2), [single](($src.Height - $sh) * $FocusY), [single]$sw, [single]$sh, [Drawing.GraphicsUnit]::Pixel)
        $tg.Dispose(); $src.Dispose()
        [SyHostBanner.Art]::Load($cv, $tmp, 0.92)
        $tmp.Dispose()
    } else {
        Add-Sky $cv $W $H $o.HorizonY $keep $o.Seed
        foreach ($m in $o.Meteors) { [SyHostBanner.Art]::Meteor($cv, $m[0], $m[1], $m[0] + $m[2] * [Math]::Cos($m[3] * [Math]::PI / 180), $m[1] - $m[2] * [Math]::Sin($m[3] * [Math]::PI / 180), $m[4], $m[5]) }
        Add-Horizon $cv $W $H $o.HorizonY $o.Scale $keep ($o.Seed + 7)
    }
    [SyHostBanner.Art]::Vignette($cv, 0.35)
    [SyHostBanner.Art]::RectGlow($cv, (Get-LogoBlocks $lx $ly $cw $ch), [int]($cw * 1.6), 239, 55, 66, 0.26)

    $bmp = [SyHostBanner.Art]::ToBitmap($cv)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::None
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::None
    Draw-Logo $g $lx $ly $cw $ch $o.LogoTime

    # slogan + yanıp sönen imleç (açılış ekranındaki gibi) + sürüm çipi
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $tagline = 'Modded Minecraft server hub'
    $adv = Get-Advance $tagPx
    $tagW = $tagline.Length * $adv
    $chipPx = $o.ChipPx
    $chipText = 'v' + $Version
    $chipH = [Math]::Round($chipPx * 1.75); $chipPad = [Math]::Round($chipPx * 0.75)
    $chipW = $chipText.Length * (Get-Advance $chipPx) + 2 * $chipPad
    $gapChip = [Math]::Round($tagPx * 1.1)
    $caretW = $adv * 0.5
    $rowW = $tagW + $caretW + $gapChip + $chipW
    $tx = [Math]::Round(($W - $rowW) / 2)
    $p = New-TextPath $tagline ([Drawing.FontStyle]::Regular) $tagPx $tx $tagBase
    $br = New-Object Drawing.SolidBrush (New-Color @(236, 236, 238))
    $g.FillPath($br, $p); $p.Dispose(); $br.Dispose()
    # imleç: ▌ (yarım blok), yazının cap yüksekliğinden biraz uzun
    $cTop = $tagBase - $capTag - $tagPx * 0.08; $cBot = $tagBase + $tagPx * 0.12
    $br = New-Object Drawing.SolidBrush (New-Color @(239, 55, 66))
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::None
    $g.FillRectangle($br, [int]($tx + $tagW + $adv * 0.12), [int]$cTop, [int][Math]::Round($caretW), [int]($cBot - $cTop))
    $br.Dispose()
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $cx = $tx + $tagW + $caretW + $gapChip
    $cy = $tagBase - $capTag / 2 - $chipH / 2
    $rr = New-RoundRect $cx $cy $chipW $chipH ($chipH / 2)
    $br = New-Object Drawing.SolidBrush (New-Color @(200, 30, 45))
    $g.FillPath($br, $rr); $br.Dispose(); $rr.Dispose()
    $capChip = Get-CapHeight ([Drawing.FontStyle]::Bold) $chipPx
    $p = New-TextPath $chipText ([Drawing.FontStyle]::Bold) $chipPx ($cx + $chipPad) ($cy + $chipH / 2 + $capChip / 2)
    $br = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
    $g.FillPath($br, $p); $p.Dispose(); $br.Dispose()
    $g.Dispose()

    $out = Join-Path $OutDir $o.Name
    $bmp.Save($out, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $kb = [Math]::Round((Get-Item $out).Length / 1KB)
    Write-Host ("{0}  {1}x{2}  {3} KB" -f $out, $W, $H, $kb) -ForegroundColor Green
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
# Kayan yıldızlar: x, y (baş), uzunluk, açı (derece, kuyruk sağ yukarı), kalınlık, parlaklık
$Images = @(
    @{ Name = 'banner.png'; W = 1600; H = 480; Cell = 14; LogoY = 80; TagPx = 32; TagGap = 34; ChipPx = 18; HorizonY = 396; Scale = 1.0; Seed = 1907; LogoTime = 1.1
       Meteors = @(@(246, 170, 215, 27, 1.7, 1.0), @(1352, 118, 180, 30, 1.5, 0.85), @(1492, 262, 92, 26, 1.1, 0.55), @(118, 300, 70, 28, 1.0, 0.4), @(905, 38, 104, 24, 1.0, 0.45)) },
    @{ Name = 'social-preview.png'; W = 1280; H = 640; Cell = 15; LogoY = 146; TagPx = 36; TagGap = 40; ChipPx = 20; HorizonY = 520; Scale = 1.2; Seed = 2203; LogoTime = 1.1
       Meteors = @(@(196, 150, 230, 28, 1.7, 1.0), @(1090, 104, 170, 30, 1.5, 0.85), @(1180, 330, 90, 26, 1.1, 0.5), @(120, 420, 64, 28, 1.0, 0.4), @(720, 70, 100, 24, 1.0, 0.45)) }
)
foreach ($img in $Images) { Build-Image $img }
