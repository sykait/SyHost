// =====================================================================
//  SyHost - ana menü
//  legacy/src/SyHost.ps1: Switch-Language (384-391), Handle-HomeKey (979-1004)
//  ve Render-Home (1282-1357) fonksiyonlarının birebir karşılığı.
// =====================================================================
namespace SyHost;

sealed partial class App
{
    // ---------- Dil (SyHost.ps1 384-391) ----------
    // Dili sırayla değiştir (en → tr → ja), ayara kaydet ve SyHost'u yeni dille yeniden aç
    private partial void SwitchLanguage()
    {
        var codes = Lang.Languages;
        // [Array]::IndexOf: bulunamazsa -1, o zaman sıradaki ilk dil olur
        int idx = -1;
        for (int i = 0; i < codes.Length; i++) { if (codes[i].Code == Lang.Code) { idx = i; break; } }
        string next = codes[(idx + 1) % codes.Length].Code;
        Cfg.dil = next;
        SaveConfig();
        RestartApp = true; Quit = true;
    }

    // ---------- Tuşlar: ana menü (SyHost.ps1 979-1004) ----------
    private partial void HandleHomeKey(ConsoleKeyInfo k, bool ctrl)
    {
        int count = Servers.Count + 1;   // + yeni sunucu
        if (Ps.Eq(HomeMode, "sil"))
        {
            switch (k.Key)
            {
                case ConsoleKey.Enter:
                {
                    var gone = Servers[HomeSel]; Servers.RemoveAt(HomeSel); SaveServers(); HomeSel = Math.Max(0, HomeSel - 1); HomeMode = "list";
                    ShowHomeMsg(Lang.L("{0} listeden kaldırıldı (dosyaları duruyor: {1})", gone.ad, gone.klasor));
                    break;
                }
                default: HomeMode = "list"; break;
            }
            return;
        }
        switch (k.Key)
        {
            case ConsoleKey.UpArrow: HomeSel = (HomeSel + count - 1) % count; return;
            case ConsoleKey.DownArrow: HomeSel = (HomeSel + 1) % count; return;
            case ConsoleKey.Enter:
                if (!Allow("homeEnter", 800)) return;
                if (HomeSel >= Servers.Count) StartWizard(); else EnterServer(Servers[HomeSel]);
                return;
            case ConsoleKey.Delete: if (HomeSel < Servers.Count) HomeMode = "sil"; return;
            case ConsoleKey.F9: OpenSettings(); return;
            case ConsoleKey.F2: if (Allow("F2")) HidePanel(); return;
            case ConsoleKey.F10: if (Allow("F10")) StartOutro(); return;
            case ConsoleKey.Escape: return;
        }
        if (ctrl && k.Key == ConsoleKey.Q) { StartOutro(); return; }
        if (k.Key == ConsoleKey.L && !ctrl) { if (Allow("lang", 1500)) SwitchLanguage(); return; }
        // PowerShell'de -eq harflerde büyük-küçük ayırmaz: '+', 'n' ya da 'N'
        if (k.KeyChar == '+' || k.KeyChar == 'n' || k.KeyChar == 'N') { HomeSel = Servers.Count; StartWizard(); }
    }

    // ---------- Çizim: ana menü (SyHost.ps1 1282-1357) ----------
    private partial List<string> RenderHome(int W, int H)
    {
        var rows = new List<string>();
        var logo = RenderLogo(1.0, LogoShine());
        string[] info =
        {
            Bo + c.brass + Lang.L("SUNUCU MERKEZİ") + R,
            c.dim + "v" + VersionText + "  ·  " + Edition + "  ·  sykait" + R,
            c.dark + Ps.Rep("─", 38) + R,
            c.soft + Lang.L("Arkadaş adresi  ") + R + (HasFriendAddr ? Bo + c.cyan + FriendAddr : c.dim + Lang.L("henüz yok")) + R,
            c.soft + Lang.L("Dış erişim      ") + R + (PlayitOn() ? c.green + Lang.L("● açık (playit)") : HasFriendAddr ? c.yellow + Lang.L("● bağlanıyor") : c.yellow + Lang.L("● kurulu değil") + c.dim + Lang.L("  (F9 ayarlar)")) + R,
            c.soft + Lang.L("Bilgisayar      ") + R + c.text + Ps.F(Lang.L("{0:0.0} GB boş"), SysFree / (1024.0 * 1024 * 1024)) + R + c.dim + Ps.F(" / {0:0} GB", TotalRam / (1024.0 * 1024 * 1024)) + R,
        };
        rows.Add("");
        for (int i = 0; i < 6; i++) rows.Add("    " + logo[i] + (W >= LogoW + 52 ? "        " + info[i] : ""));
        rows.Add("");
        rows.Add(Rule(Lang.L("SUNUCULARIN"), W, c.dim + Lang.L(" {0} sunucu ", Servers.Count) + R));
        rows.Add("");
        int sel = Math.Min(HomeSel, Servers.Count);
        double pulse = (Math.Sin(T() * 4) + 1) / 2;
        string hlBg = E + "[48;2;" + Ps.Int(45 + 35 * pulse) + ";" + Ps.Int(14 + 6 * pulse) + ";" + Ps.Int(20 + 8 * pulse) + "m";
        for (int i = 0; i <= Servers.Count; i++)
        {
            bool isSel = i == sel;
            string line;
            if (i < Servers.Count)
            {
                var sv = Servers[i];
                string id = sv.id ?? "";
                if (!ModCountCache.ContainsKey(id)) ModCountCache[id] = GetModCount(sv.klasor);
                string icon = isSel ? c.brass + Spin(6) : c.dark + "⬡";
                string name = (sv.ad ?? "").PadRight(22).Substring(0, 22);
                string meta = Lang.L("{0} {1} · {2} mod", HomeLoaderName(sv.loader), sv.mc, ModCountCache[id]);
                line = "  " + (isSel ? c.brass + Bo + "❯" : " ") + R + " " + icon + R + " " + (isSel ? Bo + c.text : c.soft) + name + R + "  " + c.dim + meta.PadRight(32) + R + "  " + c.dark + Lang.L("son açılış: ") + R + c.soft + FmtWhen(sv.sonAcilis) + R;
            }
            else
            {
                line = "  " + (isSel ? c.green + Bo + "❯" : " ") + R + " " + c.green + "+" + R + " " + (isSel ? Bo + c.green : c.soft) + Lang.L("Yeni sunucu ekle") + R + c.dim + Lang.L("   bir .mrpack dosyası seçip kur") + R;
            }
            if (isSel) { int vl = VLen(line); line = hlBg + line.Replace(R, R + hlBg) + Ps.Rep(" ", Math.Max(0, W - 1 - vl)) + R; }
            rows.Add(line);
        }
        rows.Add("");

        // Seçili sunucu ayrıntısı
        if (Ps.Eq(HomeMode, "sil") && sel < Servers.Count)
        {
            var sv = Servers[sel];
            foreach (string l in Card(Lang.L("LİSTEDEN KALDIR"), new[]
            {
                Bo + c.red + Lang.L("{0} listeden kaldırılsın mı?", sv.ad) + R,
                c.soft + Lang.L("Dosyaları silinmez, klasörü yerinde kalır:") + R,
                c.dim + sv.klasor + R,
                "",
                Pill("200;30;45", "255;255;255", "Enter") + c.text + Lang.L(" Evet, kaldır    ") + R + Pill("50;50;56", "235;235;235", Lang.L("herhangi bir tuş")) + c.text + Lang.L(" Vazgeç") + R,
            }, Math.Min(W, 90))) rows.Add(" " + l);
        }
        else if (sel < Servers.Count)
        {
            var sv = Servers[sel];
            string id = sv.id ?? "";
            if (!WorldSizeCache.ContainsKey(id))
            {
                string wd = Path.Combine(sv.klasor ?? "", "world");
                WorldSizeCache[id] = (File.Exists(wd) || Directory.Exists(wd)) ? Ps.F("{0:0} MB", HomeSizeBytes(wd) / (1024.0 * 1024)) : Lang.L("henüz oluşmadı");
            }
            string pk = Ps.In(sv.paket, PackKeys) ? sv.paket : "normal";
            foreach (string l in Card((sv.ad ?? "").ToUpper(), new[]
            {
                c.soft + Lang.L("Sürüm     ") + R + c.text + "Minecraft " + sv.mc + "  ·  " + HomeLoaderName(sv.loader) + " " + sv.loaderSurum + R,
                c.soft + Lang.L("Paket     ") + R + Bo + PackColor[pk] + PackName(pk) + R + c.dim + Lang.L("   ·   Java {0}   ·   dünya {1}", sv.java, WorldSizeCache[id]) + R,
                c.soft + Lang.L("Klasör    ") + R + c.dim + sv.klasor + R,
                c.dim + Lang.L("Enter ile aç: sunucu kendiliğinden başlar.") + R,
            }, Math.Min(W, 90))) rows.Add(" " + l);
        }
        else
        {
            foreach (string l in Card(Lang.L("YENİ SUNUCU"), new[]
            {
                c.text + Lang.L("Enter'a bas, Modrinth paketini (.mrpack) seç.") + R,
                c.soft + Lang.L("Java, mod yükleyici, modlar ve ayarlar kendiliğinden kurulur.") + R,
                c.dim + Lang.L("Desteklenen: NeoForge · Forge · Fabric") + R,
                "",
            }, Math.Min(W, 90))) rows.Add(" " + l);
        }
        if (!string.IsNullOrEmpty(HomeMsg) && Now() < HomeMsgUntil) { rows.Add(""); rows.Add("  " + c.yellow + "● " + HomeMsg + R); }

        while (rows.Count < H - 2) rows.Add("");
        UpdateSky(W, H, 0.07, 1, false, 0.75);
        for (int r1 = 0; r1 < rows.Count; r1++) { if (rows[r1] == "") rows[r1] = SkySeg(r1, 0, W); }
        rows.Add(c.dark + Ps.Rep("─", W) + R);
        rows.Add(" " + Key("↑↓", Lang.L("seç")) + Key("Enter", Lang.L("aç")) + Key("+", Lang.L("yeni sunucu")) + Key("Del", Lang.L("listeden kaldır")) + Key("L", Lang.L("dil") + ": " + Lang.NameOf(Lang.Code)) + Key("F9", Lang.L("ayarlar")) + Key("F2", Lang.L("gizle")) + c.dark + "│  " + R + Pill("200;30;45", "255;255;255", Lang.L("F10 ÇIK")));
        return rows;
    }

    // $LoaderName[$sv.loader]: tabloda olmayan yükleyici PowerShell'deki gibi boş ($null) yazılır
    static string HomeLoaderName(string loader) => loader != null && LoaderName.TryGetValue(loader, out string n) ? n : null;

    // (Get-ChildItem $wd -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    // -Force olmadığı için gizli dosyalar ve gizli klasörlerin içi sayılmaz; okunamayan klasörler atlanır.
    static double HomeSizeBytes(string path)
    {
        long sum = 0;
        try
        {
            if (File.Exists(path)) return new FileInfo(path).Length;
            var opt = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.Hidden };
            foreach (var f in new DirectoryInfo(path).EnumerateFiles("*", opt)) { try { sum += f.Length; } catch { } }
        }
        catch { }
        return sum;
    }
}
