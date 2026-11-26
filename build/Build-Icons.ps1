# =====================================================================
#  SyHost - simgeler: uygulama simgesi taslakları, klasör simgeleri ve Minecraft sunucu simgesi
#    build\Build-Icons.ps1              taslakları çizer, seçili tasarımı (varsayılan B) Assets'e kurar
#    build\Build-Icons.ps1 -Design A    başka bir taslağı kurar (A, B ya da C)
#    build\Build-Icons.ps1 -NoInstall   yalnızca taslaklar ve önizlemeler, Assets'e dokunmaz
#  Taslaklar : dist\icon-drafts\  drafts.png (karşılaştırma), titlebar.png (başlık çubuğu provası),
#              folders.png (klasörler), A\ B\ C\ (her taslağın .ico'su ve boyut boyut PNG'leri)
#  Kurulanlar: src\SyHost\Assets\SyHost.ico, Assets\icons\folder-*.ico, Assets\server-icon.png
#  Yalnızca Windows PowerShell 5.1 + System.Drawing. Rastgelelik, tarih ve sistem yazı tipi yok
#  (yazılar repodaki Cascadia Mono ile): her çalıştırmada aynı baytlar çıkar.
# =====================================================================
[CmdletBinding()]
param(
    # Varsayılan B: terminaldeki logonun blok S'si; her boyutta piksel ızgarasına tam oturur, 16 px'te en net okunan
    [ValidateSet('A', 'B', 'C')][string]$Design = 'B',
    [switch]$NoInstall,
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$Repo = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $Repo 'dist\icon-drafts' }
elseif (-not [IO.Path]::IsPathRooted($OutDir)) { $OutDir = Join-Path (Get-Location).Path $OutDir }
$Assets = Join-Path $Repo 'src\SyHost\Assets'

# .ico boyutları. 20 ve 40: %125 ekran ölçeğinde küçük (başlık çubuğu, tepsi) ve büyük simge
$Sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)

# ---------- Renkler ----------
function Col([int]$r, [int]$g, [int]$b, [int]$a = 255) { [Drawing.Color]::FromArgb($a, $r, $g, $b) }
function Alpha([Drawing.Color]$c, [int]$a) { [Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }
function Mix([Drawing.Color]$p, [Drawing.Color]$q, [double]$t) {
    Col ([int][Math]::Round($p.R + ($q.R - $p.R) * $t)) ([int][Math]::Round($p.G + ($q.G - $p.G) * $t)) ([int][Math]::Round($p.B + ($q.B - $p.B) * $t)) ([int][Math]::Round($p.A + ($q.A - $p.A) * $t))
}
$Brand  = Col 239 55 66      # #EF3742  logonun kırmızısı ($c.brass)
$Deep   = Col 120 10 20      # #780A14  koyu kırmızı (tepsi simgesindeki degradenin sonu)
$RimC   = Col 60 0 8         # tepsi simgesinin kenar çizgisi
$Ink    = Col 14 11 12       # #0E0B0C  SyHost'un neredeyse siyah dünyası
$Paper  = Col 243 243 243    # #F3F3F3  açık tema
$White  = Col 255 255 255
$Accent = Col 214 36 50      # beyaz şekillerin içindeki ışıklar, saat kolları

# ---------- Çizim yardımcıları ----------
function New-Canvas([int]$w, [int]$h) {
    $bmp = New-Object Drawing.Bitmap($w, $h, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bmp.SetResolution(96, 96)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    # Half: tam sayı koordinatlar piksel kenarına oturur, düz kenarlar bulanıklaşmaz
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAlias
    $g.Clear([Drawing.Color]::Transparent)
    $bmp, $g
}
function PtF([double]$x, [double]$y) { New-Object Drawing.PointF([single]$x, [single]$y) }
function RectF([double]$x, [double]$y, [double]$w, [double]$h) { New-Object Drawing.RectangleF([single]$x, [single]$y, [single]$w, [single]$h) }
function New-Path { New-Object Drawing.Drawing2D.GraphicsPath ([Drawing.Drawing2D.FillMode]::Winding) }
function Solid([Drawing.Color]$c) { New-Object Drawing.SolidBrush($c) }
function Grad([double]$x1, [double]$y1, [double]$x2, [double]$y2, [Drawing.Color]$c1, [Drawing.Color]$c2) {
    $b = New-Object Drawing.Drawing2D.LinearGradientBrush((PtF $x1 $y1), (PtF $x2 $y2), $c1, $c2)
    $b.WrapMode = [Drawing.Drawing2D.WrapMode]::TileFlipXY
    $b
}
function Sum($a) { $s = 0; foreach ($v in $a) { $s += $v }; $s }

# Köşeleri yuvarlatılmış dikdörtgen
function RRect([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $p = New-Path
    if ($r -le 0) { $p.AddRectangle((RectF $x $y $w $h)); return $p }
    $d = [single](2 * $r)
    $p.AddArc([single]$x, [single]$y, $d, $d, [single]180, [single]90)
    $p.AddArc([single]($x + $w - 2 * $r), [single]$y, $d, $d, [single]270, [single]90)
    $p.AddArc([single]($x + $w - 2 * $r), [single]($y + $h - 2 * $r), $d, $d, [single]0, [single]90)
    $p.AddArc([single]$x, [single]($y + $h - 2 * $r), $d, $d, [single]90, [single]90)
    $p.CloseFigure()
    $p
}
function Poly([double[]]$xy) {
    $p = New-Path
    $pts = New-Object 'Drawing.PointF[]' ([int]($xy.Count / 2))
    for ($i = 0; $i -lt $pts.Count; $i++) { $pts[$i] = PtF $xy[2 * $i] $xy[2 * $i + 1] }
    $p.AddPolygon($pts)
    $p
}
# Boş yollar GDI+'ta hata verir: yalnızca dolu olanları ekle ve boya
function Add-Path([Drawing.Drawing2D.GraphicsPath]$dst, [Drawing.Drawing2D.GraphicsPath]$src) { if ($src.PointCount -gt 0) { $dst.AddPath($src, $false) } }
function Fill($g, $brush, [Drawing.Drawing2D.GraphicsPath]$p) { if ($p.PointCount -gt 0) { $g.FillPath($brush, $p) }; $brush.Dispose() }
function Move-Path([Drawing.Drawing2D.GraphicsPath]$p, [double]$dx, [double]$dy) {
    $q = $p.Clone(); $m = New-Object Drawing.Drawing2D.Matrix
    $m.Translate([single]$dx, [single]$dy); $q.Transform($m); $m.Dispose()
    $q
}
# Logodaki ╗ ╝ gölgesi: şekli (dx,dy) yönünde süpürür, dolu bir uzantı çıkar
function Sweep-Path([Drawing.Drawing2D.GraphicsPath]$p, [int]$dx, [int]$dy) {
    $out = New-Path
    $n = [Math]::Max([Math]::Abs($dx), [Math]::Abs($dy))
    for ($k = 1; $k -le $n; $k++) {
        $q = Move-Path $p ([Math]::Round($dx * $k / $n)) ([Math]::Round($dy * $k / $n))
        Add-Path $out $q; $q.Dispose()
    }
    $out
}

# ---------- Piksel maskeleri ----------
# Her karakter bir hücre: '#' beyaz, '+' yarım beyaz, '-' hafif beyaz (eğri köşeler), 'o' vurgu rengi, '.' boş.
# Hücre boyu tek sayı ya da sütun/satır başına dizi olabilir (blok yazı tipindeki gibi).
function Edges($size, [int]$n, [double]$start) {
    $e = New-Object double[] ($n + 1); $e[0] = $start
    for ($i = 0; $i -lt $n; $i++) { $s = if ($size -is [array]) { $size[$i] } else { $size }; $e[$i + 1] = $e[$i] + $s }
    , $e
}
function Mask-Path([string[]]$mask, [double]$x, [double]$y, $cw, $ch, [string]$on) {
    $p = New-Path
    $xs = Edges $cw $mask[0].Length $x
    $ys = Edges $ch $mask.Count $y
    for ($r = 0; $r -lt $mask.Count; $r++) {
        $row = $mask[$r]; $c = 0
        while ($c -lt $row.Length) {
            if ($on.IndexOf($row[$c]) -ge 0) {
                $c0 = $c
                while ($c -lt $row.Length -and $on.IndexOf($row[$c]) -ge 0) { $c++ }
                $p.AddRectangle((RectF $xs[$c0] $ys[$r] ($xs[$c] - $xs[$c0]) ($ys[$r + 1] - $ys[$r])))
            } else { $c++ }
        }
    }
    $p
}
# Şekil = katmanlar (beyaz, yarım, hafif, vurgu) + gölgeyi düşüren gövde
function Mask-Shape([string[]]$mask, [double]$x, [double]$y, $cw = 1, $ch = 1) {
    @{
        Full = Mask-Path $mask $x $y $cw $ch '#'; Half = Mask-Path $mask $x $y $cw $ch '+'
        Soft = Mask-Path $mask $x $y $cw $ch '-'; Accent = Mask-Path $mask $x $y $cw $ch 'o'
        Body = Mask-Path $mask $x $y $cw $ch '#+o'
    }
}
function Path-Shape([Drawing.Drawing2D.GraphicsPath]$full, [Drawing.Drawing2D.GraphicsPath]$accent = $null) {
    if (-not $accent) { $accent = New-Path }
    $body = New-Path; Add-Path $body $full; Add-Path $body $accent
    @{ Full = $full; Half = (New-Path); Soft = (New-Path); Accent = $accent; Body = $body }
}

# Gölge biçimleri: 'block' logodaki gibi süpürülmüş koyu uzantı (dx, dy), 'soft' tepsi simgesindeki gibi kaydırılmış gölge
$BlockShadow = @{ 16 = @(1, 1); 20 = @(1, 1); 24 = @(1, 2); 32 = @(1, 2); 40 = @(1, 2); 48 = @(2, 3); 64 = @(2, 4); 128 = @(4, 8); 256 = @(8, 16) }
$SoftShadow = @{ 16 = 1; 20 = 1; 24 = 1; 32 = 1; 40 = 1; 48 = 1; 64 = 2; 128 = 3; 256 = 5 }
function Paint-Shape($g, $shape, [string]$style, $shadow) {
    if ($style -eq 'block') {
        Fill $g (Solid (Col 50 0 8 175)) (Sweep-Path $shape.Body $shadow[0] $shadow[1])
    } else {
        Fill $g (Solid (Alpha $RimC 120)) (Move-Path $shape.Body $shadow $shadow)
    }
    Fill $g (Solid $White) $shape.Full
    Fill $g (Solid (Alpha $White 150)) $shape.Half
    Fill $g (Solid (Alpha $White 70)) $shape.Soft
    Fill $g (Solid $Accent) $shape.Accent
}
# Maskeyi (gölgesiyle birlikte) bir merkeze yerleştir; konum tam piksele yuvarlanır
function Place-Mask($g, [string[]]$mask, [double]$cx, [double]$cy, [string]$style, $shadow, $cw = 1, $ch = 1) {
    $w = if ($cw -is [array]) { Sum $cw } else { $cw * $mask[0].Length }
    $h = if ($ch -is [array]) { Sum $ch } else { $ch * $mask.Count }
    if ($style -eq 'block') { $sx = $shadow[0]; $sy = $shadow[1] } else { $sx = $shadow; $sy = $shadow }
    $x = [Math]::Floor($cx - ($w + $sx) / 2 + 0.5); $y = [Math]::Floor($cy - ($h + $sy) / 2 + 0.5)
    Paint-Shape $g (Mask-Shape $mask $x $y $cw $ch) $style $shadow
}

# ---------- Ortak karo (A ve B): yuvarlak kare, degrade, üstte ince parıltı, koyu kenar ----------
# boyut -> kenar boşluğu, karo, köşe yarıçapı, kenar çizgisi, parıltı kalınlığı, kenar ve parıltı opaklığı
$TileGeo = @{
    16 = @(0, 16, 3, 1, 1, 110, 50); 20 = @(0, 20, 4, 1, 1, 120, 55); 24 = @(1, 22, 4.5, 1, 1, 130, 60); 32 = @(1, 30, 6, 1, 1.5, 150, 70)
    40 = @(1, 38, 8, 1.25, 2, 160, 75); 48 = @(2, 44, 9, 1.5, 2, 170, 80); 64 = @(2, 60, 12, 2, 3, 170, 80); 128 = @(4, 120, 25, 3, 5, 170, 80); 256 = @(8, 240, 50, 5, 9, 170, 80)
}
function Draw-Tile($g, [int]$size) {
    $t = $TileGeo[$size]; $m = $t[0]; $w = $t[1]; $r = $t[2]; $rw = $t[3]; $hw = $t[4]
    $g.FillPath((Grad ($m - 1) ($m - 1) ($m + $w + 1) ($m + $w + 1) $Brand $Deep), (RRect $m $m $w $w $r))
    # üst kenarda aşağı doğru sönen parıltı
    $in = RRect ($m + $rw) ($m + $rw) ($w - 2 * $rw) ($w - 2 * $rw) ([Math]::Max(0, $r - $rw))
    $hb = Grad 0 ($m + $rw) 0 ($m + $rw + 2 * $hw) (Alpha $White $t[6]) (Alpha $White 0)
    $g.SetClip((RectF 0 0 $size ($m + $rw + 2 * $hw)))
    $g.FillPath($hb, $in)
    $g.ResetClip()
    $pen = New-Object Drawing.Pen((Alpha $RimC $t[5]), [single]$rw)
    $g.DrawPath($pen, (RRect ($m + $rw / 2) ($m + $rw / 2) ($w - $rw) ($w - $rw) ($r - $rw / 2)))
}

# ---------- A: bugünkü tepsi simgesinin olgunlaşmış hali: kalın, yuvarlak S ----------
# Büyük boyutlar: iki elips yayından oluşan orta çizgi kalın kalemle genişletilir (yazı tipine bağlı değil)
function S-Curve([double]$x, [double]$y, [double]$w, [double]$h, [double]$t, [double]$term = 350) {
    $ax = ($w - $t) / 2; $ay = ($h - $t) / 4
    $cx = $x + $w / 2; $cy1 = $y + $t / 2 + $ay; $cy2 = $y + $t / 2 + 3 * $ay
    $c = New-Path
    $sw = $term - 90
    $c.AddArc([single]($cx - $ax), [single]($cy1 - $ay), [single](2 * $ax), [single](2 * $ay), [single]$term, [single](-$sw))
    $c.AddArc([single]($cx - $ax), [single]($cy2 - $ay), [single](2 * $ax), [single](2 * $ay), [single]270, [single]$sw)
    $pen = New-Object Drawing.Pen($White, [single]$t)
    $pen.StartCap = [Drawing.Drawing2D.LineCap]::Flat; $pen.EndCap = [Drawing.Drawing2D.LineCap]::Flat
    $c.Widen($pen); $c.FillMode = [Drawing.Drawing2D.FillMode]::Winding
    $c
}
# Küçük boyutlar elle, piksel piksel (180 derece döndürünce kendisiyle aynı)
$MaskS = @{
    'A10' = @(
        '.+####+.',
        '.######.',
        '##....##',
        '##......',
        '.#####..',
        '..#####.',
        '......##',
        '##....##',
        '.######.',
        '.+####+.')
    'A13' = @(
        '..+####+..',
        '.########.',
        '###....###',
        '###.......',
        '###+......',
        '+######+..',
        '.+######+.',
        '..+######+',
        '......+###',
        '.......###',
        '###....###',
        '.########.',
        '..+####+..')
    'A16' = @(
        '...+####+...',
        '.+########+.',
        '####+..+####',
        '###......###',
        '###.........',
        '####+.......',
        '+#######+...',
        '.+########+.',
        '.+########+.',
        '...+#######+',
        '.......+####',
        '.........###',
        '###......###',
        '####+..+####',
        '.+########+.',
        '...+####+...')
    # klasörlerdeki küçük S
    'A7' = @(
        '.####.',
        '##..##',
        '##....',
        '.####.',
        '....##',
        '##..##',
        '.####.')
    'A9' = @(
        '.#####.',
        '##...##',
        '##.....',
        '##.....',
        '.#####.',
        '.....##',
        '.....##',
        '##...##',
        '.#####.')
}
# boyut -> S kutusu (genişlik, yükseklik, kalınlık); konum karonun ortası
$GeoA = @{ 32 = @(16, 21, 4.6); 40 = @(20, 26, 5.6); 48 = @(24, 31, 6.8); 64 = @(32, 41, 9); 128 = @(62, 82, 17.5); 256 = @(124, 164, 35) }
function Draw-SmoothS($g, [int]$size, [double]$cx, [double]$cy) {
    $small = @{ 16 = 'A10'; 20 = 'A13'; 24 = 'A16' }
    if ($small.ContainsKey($size)) { Place-Mask $g $MaskS[$small[$size]] $cx $cy 'soft' $SoftShadow[$size]; return }
    $q = $GeoA[$size]
    $x = [Math]::Round($cx - $q[0] / 2); $y = [Math]::Floor($cy - $q[1] / 2)
    Paint-Shape $g (Path-Shape (S-Curve $x $y $q[0] $q[1] $q[2])) 'soft' $SoftShadow[$size]
}
function Draw-A($g, [int]$size) {
    Draw-Tile $g $size
    Draw-SmoothS $g $size ($size / 2) ($size / 2)
}

# ---------- B: logodaki blok yazı tipinin S'si, ███╗ gibi koyu gölgeli ----------
# Logodaki S 7 sütun x 5 satır hücredir (hücre 1:2). İki dış köşe hücresi oyuldu: tek başına "5" değil "S" okunsun.
$BlockS = @('.######', '##.....', '#######', '.....##', '######.')
# boyut -> sütun genişlikleri, satır yükseklikleri
$GeoB = @{
    16 = @(@(1, 1, 1, 1, 1, 1, 1), @(2, 2, 2, 2, 2))
    20 = @(@(2, 1, 1, 1, 1, 1, 2), @(3, 2, 3, 2, 3))
    24 = @(@(2, 1, 1, 2, 1, 1, 2), @(3, 3, 3, 3, 3))
    32 = @(@(2, 2, 2, 2, 2, 2, 2), @(4, 4, 4, 4, 4))
    40 = @(@(3, 2, 2, 3, 2, 2, 3), @(5, 5, 5, 5, 5))
    48 = @(@(3, 3, 3, 3, 3, 3, 3), @(6, 6, 6, 6, 6))
    64 = @(@(4, 4, 4, 4, 4, 4, 4), @(8, 8, 8, 8, 8))
    128 = @(@(8, 8, 8, 8, 8, 8, 8), @(16, 16, 16, 16, 16))
    256 = @(@(16, 16, 16, 16, 16, 16, 16), @(32, 32, 32, 32, 32))
}
function Draw-BlockS($g, $geo, [double]$cx, [double]$cy, $shadow) {
    Place-Mask $g $BlockS $cx $cy 'block' $shadow $geo[0] $geo[1]
}
function Draw-B($g, [int]$size) {
    Draw-Tile $g $size
    Draw-BlockS $g $GeoB[$size] ($size / 2) ($size / 2) $BlockShadow[$size]
}

# ---------- C: küp (Minecraft bloğu) silüeti üstünde kalın S ----------
# Küp genişliği 4'ün katı: 2:1 eğik kenarlar piksel basamaklarına tam oturur
$CubeW = @{ 16 = 16; 20 = 20; 24 = 24; 32 = 32; 40 = 40; 48 = 48; 64 = 64; 128 = 120; 256 = 240 }
function Draw-Cube($g, [int]$size) {
    $W = $CubeW[$size]; $o = ($size - $W) / 2; $q = $W / 4
    $top = Poly @(($o + 2 * $q), $o, ($o + $W), ($o + $q), ($o + 2 * $q), ($o + 2 * $q), $o, ($o + $q))
    $left = Poly @($o, ($o + $q), ($o + 2 * $q), ($o + 2 * $q), ($o + 2 * $q), ($o + $W), $o, ($o + 3 * $q))
    $right = Poly @(($o + 2 * $q), ($o + 2 * $q), ($o + $W), ($o + $q), ($o + $W), ($o + 3 * $q), ($o + 2 * $q), ($o + $W))
    # küçük boyutlarda kenarlar yumuşatılmaz: piksel merdiveni keskin kalır
    if ($size -le 32) { $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::None }
    $g.FillPath((Grad $o $o ($o + $W) ($o + 2 * $q) (Mix $Brand $White 0.14) $Brand), $top)
    $g.FillPath((Grad $o ($o + $q) ($o + 2 * $q) ($o + $W) (Col 214 38 52) (Col 172 22 36)), $left)
    $g.FillPath((Grad ($o + 2 * $q) ($o + $q) ($o + $W) ($o + $W) (Col 146 16 30) $Deep), $right)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
}
function Draw-C($g, [int]$size) {
    Draw-Cube $g $size
    Draw-SmoothS $g $size ($size / 2) ($size / 2)
}

# ---------- Klasörler ----------
# boyut -> x, üst, genişlik, alt, sekme genişliği, sekme yüksekliği, ön kapağın üstü, köşe yarıçapı
$FolderGeo = @{
    16 = @(0, 1, 16, 15, 6, 2, 5, 1); 20 = @(0, 2, 20, 18, 7, 2, 5, 1.5); 24 = @(1, 3, 22, 21, 8, 2, 7, 2); 32 = @(1, 4, 30, 28, 11, 3, 9, 2.5)
    40 = @(2, 5, 36, 35, 13, 3, 11, 3); 48 = @(2, 6, 44, 42, 16, 4, 13, 4); 64 = @(3, 8, 58, 56, 21, 5, 17, 5); 128 = @(6, 16, 116, 112, 42, 10, 34, 10); 256 = @(12, 32, 232, 224, 84, 20, 68, 20)
}
function Draw-Folder($g, [int]$s) {
    $f = $FolderGeo[$s]; $x = $f[0]; $y = $f[1]; $w = $f[2]; $bot = $f[3]; $tw = $f[4]; $th = $f[5]; $fy = $f[6]; $r = $f[7]
    $d = [single](2 * $r)
    $back = New-Path
    $back.AddArc([single]$x, [single]$y, $d, $d, [single]180, [single]90)
    $back.AddLine([single]($x + $r), [single]$y, [single]($x + $tw), [single]$y)
    $back.AddLine([single]($x + $tw), [single]$y, [single]($x + $tw + $th), [single]($y + $th))
    $back.AddArc([single]($x + $w - 2 * $r), [single]($y + $th), $d, $d, [single]270, [single]90)
    $back.AddArc([single]($x + $w - 2 * $r), [single]($bot - 2 * $r), $d, $d, [single]0, [single]90)
    $back.AddArc([single]$x, [single]($bot - 2 * $r), $d, $d, [single]90, [single]90)
    $back.CloseFigure()
    $g.FillPath((Grad 0 $y 0 $bot (Col 150 16 30) (Col 84 4 14)), $back)
    $front = RRect $x $fy $w ($bot - $fy) $r
    $g.FillPath((Grad $x $fy ($x + $w) $bot $Brand (Col 168 20 34)), $front)
    # ön kapağın üst kenarında ince ışık
    $hw = [Math]::Max(1, [Math]::Round($s / 64))
    $g.SetClip((RectF $x $fy $w $hw))
    $g.FillPath((Solid (Alpha $White 70)), $front)
    $g.ResetClip()
}
# Klasör işaretleri: küçük boyutlar elle, büyükler 11'lik ya da 14'lük maskenin tam katları
$Glyphs = @{
    'stack7' = @(
        '#########',
        '#o#######',
        '.........',
        '#########',
        '#o#######',
        '.........',
        '#########',
        '#o#######')
    'stack9' = @(
        '###########',
        '#o#o#######',
        '...........',
        '###########',
        '#o#o#######',
        '...........',
        '###########',
        '#o#o#######')
    'stack11' = @(
        '#############',
        '#o#o###.#.#.#',
        '#############',
        '.............',
        '#############',
        '#o#o###.#.#.#',
        '#############',
        '.............',
        '#############',
        '#o#o###.#.#.#',
        '#############')
    'stack14' = @(
        '################',
        '#oo#oo##.#.#.#.#',
        '#oo#oo##.#.#.#.#',
        '################',
        '................',
        '################',
        '#oo#oo##.#.#.#.#',
        '#oo#oo##.#.#.#.#',
        '################',
        '................',
        '################',
        '#oo#oo##.#.#.#.#',
        '#oo#oo##.#.#.#.#',
        '################')
    'server7' = @(
        '#########',
        '#o#o#####',
        '#o#o#####',
        '#########')
    'server9' = @(
        '###########',
        '#o#o###.#.#',
        '#o#o###.#.#',
        '###########')
    'server11' = @(
        '#############',
        '#############',
        '##o#o###.#.##',
        '##o#o###.#.##',
        '#############',
        '#############')
    'server14' = @(
        '################',
        '################',
        '##oo#oo##.#.#.##',
        '##oo#oo##.#.#.##',
        '################',
        '################')
    'clock7' = @(
        '..###..',
        '.#####.',
        '###o###',
        '###oo##',
        '#######',
        '.#####.',
        '..###..')
    'clock9' = @(
        '..#####..',
        '.#######.',
        '####o####',
        '####o####',
        '####ooo##',
        '#########',
        '#########',
        '.#######.',
        '..#####..')
    'clock11' = @(
        '...#####...',
        '.#########.',
        '.####o####.',
        '#####o#####',
        '#####o#####',
        '#####ooo###',
        '###########',
        '###########',
        '.#########.',
        '.#########.',
        '...#####...')
    'clock14' = @(
        '.....####.....',
        '...########...',
        '..##########..',
        '.#####oo#####.',
        '.#####oo#####.',
        '######oo######',
        '######oooooo##',
        '######oooooo##',
        '##############',
        '##############',
        '.############.',
        '..##########..',
        '...########...',
        '.....####.....')
}
# boyut -> (maske çözünürlüğü, büyütme)
$GlyphRes = @{ 16 = @(7, 1); 20 = @(9, 1); 24 = @(11, 1); 32 = @(14, 1); 40 = @(14, 1); 48 = @(11, 2); 64 = @(14, 2); 128 = @(14, 4); 256 = @(14, 8) }
# Klasör S'si: küçüklerde elle, büyüklerde tasarımın kendi S'si
$FolderBlockS = @{
    16 = @(@(1, 1, 1, 1, 1, 1, 1), @(1, 2, 1, 2, 1)); 20 = $GeoB[16]; 24 = $GeoB[16]; 32 = $GeoB[20]
    40 = @(@(2, 2, 1, 1, 1, 2, 2), @(3, 3, 3, 3, 3)); 48 = @(@(2, 2, 2, 2, 2, 2, 2), @(4, 4, 4, 4, 4)); 64 = @(@(3, 3, 3, 3, 3, 3, 3), @(6, 6, 6, 6, 6))
    128 = @(@(6, 6, 6, 6, 6, 6, 6), @(12, 12, 12, 12, 12)); 256 = @(@(12, 12, 12, 12, 12, 12, 12), @(24, 24, 24, 24, 24))
}
$FolderSmoothS = @{ 16 = 'A7'; 20 = 'A9'; 24 = 'A10'; 32 = 'A13' }
$FolderSmoothGeo = @{ 40 = @(12, 16, 3.6); 48 = @(16, 21, 4.6); 64 = @(20, 27, 5.8); 128 = @(42, 55, 12); 256 = @(84, 110, 24) }
function Folder-Center([int]$s) { $f = $FolderGeo[$s]; @(($f[0] + $f[2] / 2), (($f[6] + $f[3]) / 2)) }
function Folder-Shadow([int]$s, [string]$style) {
    if ($style -eq 'block') { $k = $GlyphRes[$s][1]; if ($s -le 40) { return , @(1, 1) }; return , @([int][Math]::Max(1, $k / 2), [int]$k) }
    $SoftShadow[$s]
}
function Draw-FolderIcon($g, [int]$s, [string]$kind, [string]$design) {
    Draw-Folder $g $s
    $c = Folder-Center $s; $cx = $c[0]; $cy = $c[1]
    $style = if ($design -eq 'B') { 'block' } else { 'soft' }
    $sh = Folder-Shadow $s $style
    if ($kind -eq 'syhost') {
        if ($design -eq 'B') {
            $geo = $FolderBlockS[$s]
            $bs = if ($s -le 40) { @(1, 1) } else { @([int][Math]::Max(1, $geo[0][0] / 2), [int]($geo[1][0] / 2)) }
            Draw-BlockS $g $geo $cx $cy $bs
        } elseif ($FolderSmoothS.ContainsKey($s)) {
            Place-Mask $g $MaskS[$FolderSmoothS[$s]] $cx $cy 'soft' $sh
        } else {
            $q = $FolderSmoothGeo[$s]
            Paint-Shape $g (Path-Shape (S-Curve ([Math]::Round($cx - $q[0] / 2)) ([Math]::Floor($cy - $q[1] / 2)) $q[0] $q[1] $q[2])) 'soft' $sh
        }
        return
    }
    $res = $GlyphRes[$s]
    $mask = $Glyphs["$kind$($res[0])"]
    if ($kind -eq 'clock' -and $style -eq 'soft' -and $s -ge 40) {
        # yumuşak tasarımlarda büyük saat gerçek daire
        $d = $mask.Count * $res[1]; $x = [Math]::Round($cx - $d / 2); $y = [Math]::Round($cy - $d / 2)
        $disc = New-Path; $disc.AddEllipse((RectF $x $y $d $d))
        $hw = [Math]::Max(2, [Math]::Round($d * 0.13)); $m = $d / 2
        $hands = New-Path
        Add-Path $hands (RRect ($x + $m - $hw / 2) ($y + $d * 0.2) $hw ($m - $d * 0.2 + $hw / 2) ($hw / 2))
        Add-Path $hands (RRect ($x + $m - $hw / 2) ($y + $m - $hw / 2) ($d * 0.3 + $hw / 2) $hw ($hw / 2))
        Paint-Shape $g (Path-Shape $disc $hands) 'soft' $sh
        return
    }
    Place-Mask $g $mask $cx $cy $style $sh $res[1] $res[1]
}

# ---------- Minecraft sunucu simgesi (64x64 PNG, çok oyunculu listede görünür) ----------
# Minecraft küçük resmi en yakın komşu ile büyütür: B'de tüm kenarlar tam piksel, yarım saydam köşe yok
function Draw-ServerIcon($g, [string]$design) {
    if ($design -ne 'B') { & "Draw-$design" $g 64; return }
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::None
    $g.FillPath((Grad -1 -1 65 65 $Brand $Deep), (RRect 0 0 64 64 10))
    $g.FillRectangle((Solid (Alpha $White 46)), 6, 2, 52, 2)
    $g.DrawPath((New-Object Drawing.Pen((Alpha $RimC 170), 2)), (RRect 1 1 62 62 9))
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    Draw-BlockS $g $GeoB[64] 32 32 @(2, 4)
}

# ---------- Kaydetme ----------
function Get-Bgra([Drawing.Bitmap]$bmp) {
    $rect = New-Object Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)
    $data = $bmp.LockBits($rect, [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $bytes = New-Object byte[] ($bmp.Width * 4 * $bmp.Height)
        for ($y = 0; $y -lt $bmp.Height; $y++) { [Runtime.InteropServices.Marshal]::Copy([IntPtr]($data.Scan0.ToInt64() + $y * $data.Stride), $bytes, $y * $bmp.Width * 4, $bmp.Width * 4) }
    } finally { $bmp.UnlockBits($data) }
    , $bytes
}
function Get-PngBytes([Drawing.Bitmap]$bmp) {
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    , $ms.ToArray()
}
# Klasik 32 bit BMP kaydı (alfa + AND maskesi): tepsi, başlık çubuğu ve eski API'ler için en güvenlisi
function Get-DibBytes([Drawing.Bitmap]$bmp) {
    $w = $bmp.Width; $h = $bmp.Height
    $px = Get-Bgra $bmp
    $stride = [int]([Math]::Floor(($w + 31) / 32) * 4)
    $ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter($ms)
    $bw.Write([int]40); $bw.Write([int]$w); $bw.Write([int]($h * 2)); $bw.Write([int16]1); $bw.Write([int16]32)
    $bw.Write([int]0); $bw.Write([int]($w * $h * 4 + $stride * $h)); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0)
    for ($y = $h - 1; $y -ge 0; $y--) { $bw.Write($px, $y * $w * 4, $w * 4) }
    $mask = New-Object byte[] ($stride * $h)
    for ($y = 0; $y -lt $h; $y++) {
        $row = ($h - 1 - $y) * $stride
        for ($x = 0; $x -lt $w; $x++) {
            if ($px[($y * $w + $x) * 4 + 3] -eq 0) { $mask[$row + ($x -shr 3)] = $mask[$row + ($x -shr 3)] -bor (0x80 -shr ($x -band 7)) }
        }
    }
    $bw.Write($mask); $bw.Flush()
    , $ms.ToArray()
}
# Çok boyutlu .ico: 48 ve altı BMP (her yerde güvenli), 64 ve üstü PNG sıkıştırmalı (256 zorunlu PNG)
function Save-Ico([string]$path, $frames) {
    $blobs = New-Object 'System.Collections.Generic.List[byte[]]'
    foreach ($f in $frames) { if ($f.Width -ge 64) { $blobs.Add((Get-PngBytes $f)) } else { $blobs.Add((Get-DibBytes $f)) } }
    $ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter($ms)
    $bw.Write([int16]0); $bw.Write([int16]1); $bw.Write([int16]$frames.Count)
    $off = 6 + 16 * $frames.Count
    for ($i = 0; $i -lt $frames.Count; $i++) {
        $s = $frames[$i].Width; $b = if ($s -ge 256) { 0 } else { $s }
        $bw.Write([byte]$b); $bw.Write([byte]$b); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([int16]1); $bw.Write([int16]32); $bw.Write([int]$blobs[$i].Length); $bw.Write([int]$off)
        $off += $blobs[$i].Length
    }
    foreach ($bl in $blobs) { $bw.Write($bl) }
    $bw.Flush()
    [IO.File]::WriteAllBytes($path, $ms.ToArray())
}
function Save-Png([Drawing.Bitmap]$bmp, [string]$path) { [IO.File]::WriteAllBytes($path, (Get-PngBytes $bmp)) }

# Bir çizim komutunu verilen boyutta boş tuvale uygula
function Render([scriptblock]$draw, [int]$size) {
    $bmp, $g = New-Canvas $size $size
    $null = & $draw $g $size
    $g.Dispose()
    $bmp
}
function Frame($frames, [int]$size) { foreach ($f in $frames) { if ($f.Width -eq $size) { return $f } } }

# ---------- Önizleme sayfaları için yardımcılar ----------
# Yazılar repodaki Cascadia Mono ile (sistemdeki yazı tiplerine bağlı kalmasın)
$FontSet = New-Object Drawing.Text.PrivateFontCollection
foreach ($fn in 'CascadiaMono-Regular.ttf', 'CascadiaMono-Bold.ttf') { $fp = Join-Path $Repo "legacy\fonts\$fn"; if (Test-Path $fp) { $FontSet.AddFontFile($fp) } }
$Mono = if ($FontSet.Families.Count) { $FontSet.Families[0] } else { [Drawing.FontFamily]::GenericMonospace }
function Text($g, [string]$s, [double]$x, [double]$y, [double]$px, [Drawing.Color]$c, [switch]$Bold, [double]$CenterW = 0, [double]$RightX = 0) {
    $st = if ($Bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $f = New-Object Drawing.Font($Mono, [single]$px, $st, [Drawing.GraphicsUnit]::Pixel)
    $b = Solid $c
    $sf = New-Object Drawing.StringFormat([Drawing.StringFormat]::GenericTypographic)
    $sf.FormatFlags = $sf.FormatFlags -bor [Drawing.StringFormatFlags]::NoWrap
    if ($CenterW -gt 0) { $sf.Alignment = [Drawing.StringAlignment]::Center; $g.DrawString($s, $f, $b, (RectF $x $y $CenterW ($px * 2)), $sf) }
    elseif ($RightX -gt 0) { $sf.Alignment = [Drawing.StringAlignment]::Far; $g.DrawString($s, $f, $b, (RectF ($RightX - 400) $y 400 ($px * 2)), $sf) }
    else { $g.DrawString($s, $f, $b, [single]$x, [single]$y, $sf) }
    $f.Dispose(); $b.Dispose(); $sf.Dispose()
}
# Görüntüyü tam piksel konumuna, istenirse en yakın komşu büyütmeyle koy
function Blit($g, [Drawing.Image]$im, [double]$x, [double]$y, [int]$scale = 1) {
    $g.DrawImage($im, (New-Object Drawing.Rectangle([int]$x, [int]$y, ($im.Width * $scale), ($im.Height * $scale))))
}
function Box($g, [Drawing.Color]$c, [double]$x, [double]$y, [double]$w, [double]$h) { $b = Solid $c; $g.FillRectangle($b, [single]$x, [single]$y, [single]$w, [single]$h); $b.Dispose() }

# Windows 11 görev çubuğu provası (%100): 48 px yükseklik, 24 px uygulama simgesi, 16 px tepsi simgesi.
# Diğer uygulamalar markasız, nötr yer tutucular.
function Draw-Taskbar($g, [double]$x, [double]$y, [double]$w, [bool]$dark, $icon24, $icon16) {
    if ($dark) { $bg = Col 32 32 32; $line = Col 58 58 58; $fg = Col 255 255 255; $hover = Col 255 255 255 22; $pill = Col 76 194 255; $ph = Col 120 120 126 }
    else { $bg = Col 236 236 236; $line = Col 212 212 212; $fg = Col 26 26 26; $hover = Col 0 0 0 14; $pill = Col 0 95 184; $ph = Col 150 150 156 }
    Box $g $bg $x $y $w 48
    Box $g $line $x $y $w 1
    $bx = [Math]::Round($x + $w / 2 - 170)
    $tones = @((Col 96 130 190), (Col 210 168 60), (Col 90 160 110), $ph, $null, (Col 150 110 190))
    for ($i = 0; $i -lt 6; $i++) {
        $cx = $bx + $i * 44 + 20
        if ($i -eq 4) {
            $g.FillPath((Solid $hover), (RRect ($cx - 20) ($y + 4) 40 40 4))
            Blit $g $icon24 ($cx - 12) ($y + 12)
            $g.FillPath((Solid $pill), (RRect ($cx - 8) ($y + 42) 16 3 1.5))
        } else {
            $g.FillPath((Solid $tones[$i]), (RRect ($cx - 11) ($y + 13) 22 22 5))
            if ($i -eq 1 -or $i -eq 2) { $g.FillPath((Solid $ph), (RRect ($cx - 3) ($y + 42) 6 3 1.5)) }
        }
    }
    # tepsi: gizli simgeler oku, iki yer tutucu, SyHost, saat
    $tx = $x + $w - 196
    Text $g '^' ($tx) ($y + 15) 13 $fg
    $g.FillEllipse((Solid $ph), [single]($tx + 24), [single]($y + 16), 16, 16)
    $g.FillPath((Solid $ph), (RRect ($tx + 48) ($y + 17) 16 14 2))
    Blit $g $icon16 ($tx + 72) ($y + 16)
    Text $g '21:47' 0 ($y + 9) 12 $fg -RightX ($x + $w - 12)
    Text $g '27.11.2026' 0 ($y + 26) 12 $fg -RightX ($x + $w - 12)
}

# Konsol penceresi başlık çubuğu provası (Windows 11, %100): 16 px simge, başlık, simge durumu/kapat düğmeleri
function Draw-TitleBar($g, [double]$x, [double]$y, [double]$w, [bool]$dark, $icon16) {
    if ($dark) { $bg = Col 32 32 32; $fg = Col 255 255 255 } else { $bg = Col 243 243 243; $fg = Col 0 0 0 }
    Box $g $bg $x $y $w 32
    Blit $g $icon16 ($x + 8) ($y + 8)
    Text $g 'SyHost' ($x + 32) ($y + 9) 12 $fg
    $pen = New-Object Drawing.Pen($fg, 1)
    $bx = $x + $w - 138
    $g.DrawLine($pen, [single]($bx + 18), [single]($y + 16), [single]($bx + 28), [single]($y + 16))
    $g.DrawRectangle($pen, [single]($bx + 64), [single]($y + 11), 9, 9)
    $g.DrawLine($pen, [single]($bx + 110), [single]($y + 11), [single]($bx + 120), [single]($y + 21))
    $g.DrawLine($pen, [single]($bx + 120), [single]($y + 11), [single]($bx + 110), [single]($y + 21))
    $pen.Dispose()
}
# Konsoldaki SYHOST logosu (legacy/src/SyHost.ps1 231-238), bloklar kırmızı, gölgeler koyu kırmızı
$LogoFont = @{
    'S' = @('███████╗', '██╔════╝', '███████╗', '╚════██║', '███████║', '╚══════╝')
    'Y' = @('██╗   ██╗', '╚██╗ ██╔╝', ' ╚████╔╝ ', '  ╚██╔╝  ', '   ██║   ', '   ╚═╝   ')
    'H' = @('██╗  ██╗', '██║  ██║', '███████║', '██╔══██║', '██║  ██║', '╚═╝  ╚═╝')
    'O' = @(' ██████╗ ', '██╔═══██╗', '██║   ██║', '██║   ██║', '╚██████╔╝', ' ╚═════╝ ')
    'T' = @('████████╗', '╚══██╔══╝', '   ██║   ', '   ██║   ', '   ██║   ', '   ╚═╝   ')
}
# Terminal gibi hücre hücre: █ tam hücre dikdörtgeni, gölge karakterleri yazı tipinden. Renkler Render-Logo'nun
# t=0 anındaki dalgası (SyHost.ps1 259-261).
function Draw-ConsoleLogo($g, [double]$x, [double]$y, [int]$cw, [int]$ch, [double]$px) {
    $full = [char]0x2588
    for ($r = 0; $r -lt 6; $r++) {
        $line = (('SYHOST'.ToCharArray() | ForEach-Object { $LogoFont[[string]$_][$r] }) -join '')
        for ($i = 0; $i -lt $line.Length; $i++) {
            $c = $line[$i]
            if ($c -eq ' ') { continue }
            $wave = ([Math]::Sin($i / 7.0 + $r * 0.35) + 1) / 2
            if ($c -eq $full) { Box $g (Col ([int](175 + 80 * $wave)) ([int](18 + 70 * [Math]::Pow($wave, 3))) ([int](30 + 70 * [Math]::Pow($wave, 3)))) ($x + $i * $cw) ($y + $r * $ch) $cw $ch }
            else { Text $g ([string]$c) ($x + $i * $cw) ($y + $r * $ch) $px (Col ([int](70 + 40 * $wave)) 14 20) }
        }
    }
}

#region main
# ---------- Taslaklar ----------
New-Item -ItemType Directory -Force $OutDir | Out-Null
$Drafts = @{}
foreach ($d in 'A', 'B', 'C') {
    $dir = Join-Path $OutDir $d
    New-Item -ItemType Directory -Force $dir | Out-Null
    $draw = (Get-Item "function:Draw-$d").ScriptBlock
    $frames = foreach ($s in $Sizes) { Render $draw $s }
    foreach ($f in $frames) { Save-Png $f (Join-Path $dir "$d-$($f.Width).png") }
    Save-Ico (Join-Path $dir "SyHost-$d.ico") $frames
    $Drafts[$d] = $frames
}
Write-Host 'Taslaklar hazır: A, B, C'

# ---------- Seçilen tasarımın klasörleri ve sunucu simgesi ----------
$FolderKinds = @('syhost', 'servers', 'server', 'backups')
$GlyphOf = @{ syhost = 'syhost'; servers = 'stack'; server = 'server'; backups = 'clock' }
$FolderDir = Join-Path $OutDir 'folders'
New-Item -ItemType Directory -Force $FolderDir | Out-Null
$Folders = @{}
foreach ($k in $FolderKinds) {
    $glyph = $GlyphOf[$k]
    $draw = { param($g, $s) Draw-FolderIcon $g $s $glyph $Design }
    $frames = foreach ($s in $Sizes) { Render $draw $s }
    foreach ($f in $frames) { Save-Png $f (Join-Path $FolderDir "folder-$k-$($f.Width).png") }
    Save-Ico (Join-Path $FolderDir "folder-$k.ico") $frames
    $Folders[$k] = $frames
}
$ServerIcon = Render { param($g, $s) Draw-ServerIcon $g $Design } 64
Save-Png $ServerIcon (Join-Path $OutDir 'server-icon.png')
Write-Host "Klasörler ve sunucu simgesi hazır (tasarım $Design)"

# ---------- drafts.png: üç taslak yan yana ----------
$Names = @{ A = 'refined tile'; B = 'logo block S'; C = 'block cube' }
$Gray = Col 150 150 156
$RowH = 316; $Top = 76
$sheet, $g = New-Canvas 1890 ($Top + 3 * $RowH + 8)
$g.Clear((Col 28 24 26))
Text $g 'SyHost icon drafts' 24 18 24 $White -Bold
$Picked = if ($NoInstall) { 'selected' } else { 'installed' }
Text $g "rows A B C  |  dark #0E0B0C and light #F3F3F3: 256 64 48 32 24 16 px  |  Windows 11 taskbar at 100%  |  tray 16 px at 1x 2x 8x  |  ${Picked}: $Design" 24 50 13 $Gray
$i = 0
foreach ($d in 'A', 'B', 'C') {
    $y0 = $Top + $i * $RowH; $i++
    $fr = $Drafts[$d]
    Text $g $d 26 ($y0 + 6) 64 $White -Bold
    Text $g $Names[$d] 26 ($y0 + 86) 12 $Gray
    if ($d -eq $Design) { Text $g $Picked 26 ($y0 + 104) 12 $Brand -Bold }
    foreach ($pn in @(@(120, $Ink, (Col 120 120 126)), @(690, $Paper, (Col 110 110 116)))) {
        Box $g $pn[1] $pn[0] $y0 556 300
        $x = $pn[0] + 18; $base = $y0 + 18 + 256
        foreach ($s in 256, 64, 48, 32, 24, 16) {
            Blit $g (Frame $fr $s) $x ($base - $s)
            Text $g "$s" ($x - 10) ($base + 6) 11 $pn[2] -CenterW ($s + 20)
            $x += $s + 16
        }
    }
    Draw-Taskbar $g 1260 ($y0 + 8) 614 $true (Frame $fr 24) (Frame $fr 16)
    Draw-Taskbar $g 1260 ($y0 + 64) 614 $false (Frame $fr 24) (Frame $fr 16)
    # tepsi boyutu: 16 px gerçek boyutta, 2 kat ve 8 kat (en yakın komşu), karanlık ve açık zeminde
    $zy = $y0 + 128
    $f16 = Frame $fr 16
    Box $g $Ink 1260 $zy 40 40; Blit $g $f16 1272 ($zy + 12)
    Box $g $Paper 1304 $zy 40 40; Blit $g $f16 1316 ($zy + 12)
    Text $g '1x' 1260 ($zy + 46) 11 $Gray -CenterW 84
    Box $g $Ink 1356 $zy 56 56; Blit $g $f16 1368 ($zy + 12) 2
    Box $g $Paper 1416 $zy 56 56; Blit $g $f16 1428 ($zy + 12) 2
    Text $g '2x' 1356 ($zy + 62) 11 $Gray -CenterW 116
    Box $g $Ink 1484 $zy 144 144; Blit $g $f16 1492 ($zy + 8) 8
    Box $g $Paper 1632 $zy 144 144; Blit $g $f16 1640 ($zy + 8) 8
    Text $g '8x' 1484 ($zy + 148) 11 $Gray -CenterW 292
}
$g.Dispose()
Save-Png $sheet (Join-Path $OutDir 'drafts.png')

# ---------- titlebar.png: her taslak 16 px olarak konsol penceresinin başlık çubuğunda ----------
$TRow = 212
$tb, $g = New-Canvas 1480 (64 + 3 * $TRow)
$g.Clear((Col 28 24 26))
Text $g 'Console window title bar at 100% (16 px icon), dark and light theme, with 3x zoom of the corner' 24 22 15 $White -Bold
$i = 0
foreach ($d in 'A', 'B', 'C') {
    $y0 = 64 + $i * $TRow; $i++
    Text $g $d 24 ($y0 + 2) 28 $White -Bold
    $j = 0
    foreach ($dark in $true, $false) {
        $win, $wg = New-Canvas 520 164
        $wg.Clear((Col 12 12 12))
        Draw-TitleBar $wg 0 0 520 $dark (Frame $Drafts[$d] 16)
        Draw-ConsoleLogo $wg 81 44 7 14 12
        Text $wg 'modded Minecraft server hub' 0 140 12 (Col 240 240 240) -CenterW 520
        $wg.Dispose()
        $x0 = 64 + $j * 540
        Box $g (Col 80 80 86) ($x0 - 1) ($y0 - 1) 522 166
        Blit $g $win $x0 $y0
        # sol üst köşe 3 kat büyütülmüş: simgenin pikselleri başlık çubuğunda nasıl duruyor
        $crop, $cg = New-Canvas 100 32
        $cg.DrawImage($win, (New-Object Drawing.Rectangle(0, 0, 100, 32)), (New-Object Drawing.Rectangle(0, 0, 100, 32)), [Drawing.GraphicsUnit]::Pixel)
        $cg.Dispose()
        Blit $g $crop 1144 ($y0 + $j * 104) 3
        $j++
    }
}
$g.Dispose()
Save-Png $tb (Join-Path $OutDir 'titlebar.png')

# ---------- folders.png: seçilen tasarımın klasörleri ----------
$FolderNames = @{ syhost = 'SyHost'; servers = 'Servers'; server = 'one server'; backups = 'Backups' }
$FRow = 300
$fs, $g = New-Canvas 1890 (76 + 4 * $FRow + 236 + 166)
$g.Clear((Col 28 24 26))
Text $g "SyHost folder icons (design $Design)" 24 18 24 $White -Bold
Text $g 'dark and light: 256 64 48 32 24 16 px  |  16 px at 8x  |  Explorer at 100%' 24 50 13 $Gray
$i = 0
foreach ($k in $FolderKinds) {
    $y0 = 76 + $i * $FRow; $i++
    $fr = $Folders[$k]
    Text $g $FolderNames[$k] 24 ($y0 + 6) 18 $White -Bold
    Text $g "folder-$k.ico" 24 ($y0 + 32) 11 $Gray
    foreach ($pn in @(@(160, $Ink, (Col 120 120 126)), @(730, $Paper, (Col 110 110 116)))) {
        Box $g $pn[1] $pn[0] $y0 556 288
        $x = $pn[0] + 18; $base = $y0 + 12 + 256
        foreach ($s in 256, 64, 48, 32, 24, 16) {
            Blit $g (Frame $fr $s) $x ($base - $s)
            Text $g "$s" ($x - 10) ($base + 4) 11 $pn[2] -CenterW ($s + 20)
            $x += $s + 16
        }
    }
    foreach ($bg in $Ink, $Paper) { $zx = if ($bg -eq $Ink) { 1300 } else { 1448 }; Box $g $bg $zx $y0 144 144; Blit $g (Frame $fr 16) ($zx + 8) ($y0 + 8) 8 }
    foreach ($bg in $Ink, $Paper) { $zx = if ($bg -eq $Ink) { 1300 } else { 1448 }; Box $g $bg $zx ($y0 + 148) 144 140; Blit $g (Frame $fr 32) ($zx + 24) ($y0 + 166) 3 }
}
# Gezgin provası: ayrıntılar görünümü (16 px) ve büyük simgeler (48 px), açık ve karanlık tema
$ey = 76 + 4 * $FRow
$sample = @(@('syhost', 'SyHost'), @('servers', 'SyHost Servers'), @('server', 'Create Plus'), @('server', 'Vanilla 1.21'), @('backups', 'Backups'))
foreach ($dark in $true, $false) {
    $ex = if ($dark) { 160 } else { 1025 }
    if ($dark) { $bg = Col 25 25 25; $fg = Col 255 255 255; $sub = Col 160 160 166 } else { $bg = Col 255 255 255; $fg = Col 26 26 26; $sub = Col 96 96 102 }
    Box $g $bg $ex $ey 840 220
    $ry = $ey + 12
    foreach ($row in $sample) {
        Blit $g (Frame $Folders[$row[0]] 16) ($ex + 14) $ry
        Text $g $row[1] ($ex + 40) ($ry + 1) 12 $fg
        Text $g 'File folder' ($ex + 230) ($ry + 1) 12 $sub
        $ry += 24
    }
    $lx = $ex + 350
    foreach ($row in $sample) {
        Blit $g (Frame $Folders[$row[0]] 48) ($lx + 22) ($ey + 40)
        Text $g $row[1] $lx ($ey + 96) 11 $fg -CenterW 92
        $lx += 96
    }
}
# Minecraft çok oyunculu listesi provası: server-icon.png GUI ölçeği 1, 2 ve 3'te (oyun gibi en yakın komşu)
$my = $ey + 236
Box $g (Col 20 17 15) 160 $my 1705 150
Text $g 'server-icon.png (64x64) in the Minecraft multiplayer list at GUI scale 1, 2 and 3' 176 ($my + 8) 11 $Gray
$mx = 176; $ty = $my + 32
foreach ($sc in 1, 2, 3) {
    $sz = 32 * $sc; $tx = $mx + $sz + 4 * $sc
    $g.DrawImage($ServerIcon, (New-Object Drawing.Rectangle([int]$mx, [int]$ty, $sz, $sz)))
    Text $g 'SyHost' $tx $ty (8 * $sc) $White
    Text $g 'Create Plus - modded 1.21.1' $tx ($ty + 11 * $sc) (8 * $sc) (Col 168 168 168)
    for ($b = 0; $b -lt 5; $b++) { Box $g (Col 64 214 80) ($tx + 150 * $sc + $b * 2 * $sc) ($ty + (6 - $b) * $sc) $sc (($b + 2) * $sc) }
    $mx = $tx + 196 * $sc
}
$g.Dispose()
Save-Png $fs (Join-Path $OutDir 'folders.png')
Write-Host "Önizlemeler: $(Join-Path $OutDir 'drafts.png')"

# ---------- Kurulum: seçilen tasarım Assets'e ----------
$Installed = @()
if (-not $NoInstall) {
    $iconDir = Join-Path $Assets 'icons'
    New-Item -ItemType Directory -Force $iconDir | Out-Null
    Copy-Item (Join-Path $OutDir "$Design\SyHost-$Design.ico") (Join-Path $Assets 'SyHost.ico') -Force
    $Installed += Join-Path $Assets 'SyHost.ico'
    foreach ($k in $FolderKinds) {
        Copy-Item (Join-Path $FolderDir "folder-$k.ico") (Join-Path $iconDir "folder-$k.ico") -Force
        $Installed += Join-Path $iconDir "folder-$k.ico"
    }
    Copy-Item (Join-Path $OutDir 'server-icon.png') (Join-Path $Assets 'server-icon.png') -Force
    Write-Host "Kuruldu: tasarım $Design -> src\SyHost\Assets"
}

# ---------- Doğrulama: her .ico'yu geri oku, her boyut çizilenle piksel piksel aynı olmalı ----------
# BMP kayıtları Windows'un simge API'siyle (System.Drawing.Icon -> CreateIconFromResourceEx) açılır.
# PNG kayıtları doğrudan PNG olarak çözülür: .NET Framework'ün Icon sınıfı PNG kayıtlarını okuyamaz
# (Gezgin, görev çubuğu ve Win32 okur), bu yüzden onları onunla denemiyoruz.
function Same-Pixels([Drawing.Bitmap]$a, [Drawing.Bitmap]$b) { [Convert]::ToBase64String((Get-Bgra $a)) -ceq [Convert]::ToBase64String((Get-Bgra $b)) }
function Test-Ico([string]$path, $frames) {
    $b = [IO.File]::ReadAllBytes($path)
    if ([BitConverter]::ToUInt16($b, 2) -ne 1) { throw "$path : simge dosyası değil" }
    $n = [BitConverter]::ToUInt16($b, 4)
    if ($n -ne $frames.Count) { throw "$path : $n kayıt var, $($frames.Count) bekleniyordu" }
    for ($i = 0; $i -lt $n; $i++) {
        $o = 6 + 16 * $i; $s = if ($b[$o] -eq 0) { 256 } else { [int]$b[$o] }
        $len = [BitConverter]::ToInt32($b, $o + 8); $off = [BitConverter]::ToInt32($b, $o + 12)
        if ($b[$off] -eq 0x89) { $im = New-Object Drawing.Bitmap((New-Object IO.MemoryStream($b, $off, $len))) }
        else { $icon = New-Object Drawing.Icon($path, $s, $s); $im = $icon.ToBitmap(); $icon.Dispose() }
        if ($im.Width -ne $s -or $im.Height -ne $s) { throw "$path : $s px kaydı $($im.Width)x$($im.Height) çıktı" }
        if (-not (Same-Pixels $im (Frame $frames $s))) { throw "$path : $s px kaydı çizilenle aynı değil" }
        $im.Dispose()
    }
}
$checked = 0
foreach ($d in 'A', 'B', 'C') { Test-Ico (Join-Path $OutDir "$d\SyHost-$d.ico") $Drafts[$d]; $checked++ }
foreach ($k in $FolderKinds) { Test-Ico (Join-Path $FolderDir "folder-$k.ico") $Folders[$k]; $checked++ }
if (-not $NoInstall) {
    Test-Ico (Join-Path $Assets 'SyHost.ico') $Drafts[$Design]; $checked++
    foreach ($k in $FolderKinds) { Test-Ico (Join-Path $Assets "icons\folder-$k.ico") $Folders[$k]; $checked++ }
}
$png = New-Object Drawing.Bitmap((Join-Path $OutDir 'server-icon.png'))
try { if ($png.Width -ne 64 -or $png.Height -ne 64 -or -not (Same-Pixels $png $ServerIcon)) { throw 'server-icon.png 64x64 değil ya da çizilenle aynı değil' } } finally { $png.Dispose() }
Write-Host "Doğrulandı: $checked .ico dosyası ($($Sizes -join ', ') px) ve 64x64 server-icon.png" -ForegroundColor Green
