// =====================================================================
//  SyHost - sunucu ekranının çizimi (yalnızca çizim)
//  legacy/src/SyHost.ps1 1453-1727: Get-StartPct, Get-StatusStrip,
//  Render-Header, Render-Log, Render-Help, Render-Packs, Mark,
//  Render-Confirm, Render-Closing, Render-Mini, Render-Server.
//  Satır satır port: aynı birleştirme sırası, aynı boşluklar, aynı renkler.
//  Parantez içindeki sayılar PowerShell dosyasındaki satırlardır.
// =====================================================================
namespace SyHost;

sealed partial class App
{
    // ---------- Get-StartPct (1455-1461) ----------
    private partial int GetStartPct()
    {
        if (StartTime == null) return 0;
        double el = (Now() - StartTime.Value).TotalSeconds;
        int pct = Math.Min(95, Ps.Int(el / Math.Max(5, ExpectedStart) * 100));   // PowerShell: [Math]::Min(95, <ondalık>) Int32 sürümü
        int min = Stage switch { 2 => 8, 3 => 55, 4 => 75, _ => 0 };
        return Ps.Int(Math.Max(pct, min));
    }

    // ---------- Get-StatusStrip (1462-1489) ----------
    private partial string GetStatusStrip(bool Short)
    {
        if (Ps.Eq(Status, "KAPALI"))
        {
            if (AutoRestartAt != null)
            {
                int sec = Ps.Int(Math.Max(0, (AutoRestartAt.Value - Now()).TotalSeconds));
                return Pill("200;30;45", "255;255;255", Lang.L("■ KAPALI")) + c.yellow + (Short ? Lang.L("  {0} sn sonra açılıyor", sec) : Lang.L("  Sunucu çöktü, {0} sn sonra kendiliğinden yeniden açılacak.", sec)) + R;
            }
            if (Short) return Pill("200;30;45", "255;255;255", Lang.L("■ KAPALI")) + c.soft + Lang.L("  açmak: baslat") + R;
            return Pill("200;30;45", "255;255;255", Lang.L("■ SUNUCU KAPALI")) + c.soft + Lang.L("  Açmak için ") + R + Bo + c.brass + Cmd("baslat") + R + c.soft + Lang.L(" yaz ve Enter'a bas.") + R;
        }
        if (Ps.Eq(Status, "BASLIYOR"))
        {
            int pct = GetStartPct();
            if (Short) return Pill("190;28;42", "255;255;255", Spin() + Lang.L(" AÇILIYOR")) + " " + BarP(pct, 10) + c.yellow + " %" + pct + R;
            int left = Ps.Int(Math.Max(0, ExpectedStart - (Now() - StartTime.Value).TotalSeconds));
            string eta = left > 0 ? Lang.L("~{0} sn", left) : Lang.L("birazdan");
            return Pill("190;28;42", "255;255;255", Spin() + Lang.L(" HAZIRLANIYOR")) + "  " + BarP(pct, 16) + " " + c.yellow + Bo + "%" + pct + R + "  " + Shimmer(Lang.L("Adım {0}/4 · {1}", Math.Max(1, Stage), ViewStageName(Stage)), new[] { 229, 231, 235 }, new[] { 255, 70, 80 }) + c.dim + Lang.L("  ·  {0}  ·  ", eta) + R + c.dark + Verb() + "…" + R;
        }
        if (Ps.Eq(Status, "ACIK"))
        {
            if (Short) return Pill("240;240;240", "18;18;20", Lang.L("● AÇIK")) + c.green + Lang.L("  girilebilir") + R;
            return Pill("240;240;240", "18;18;20", Lang.L("● SUNUCU AÇIK")) + (HasFriendAddr ? c.green + Lang.L("  Arkadaşların girebilir: ") + R + Bo + c.cyan + FriendAddr + R + c.dim + Lang.L("   (kopyalamak için: kopyala)") : c.green + Lang.L("  Sen girebilirsin: ") + R + Bo + c.cyan + "localhost") + R;
        }
        if (Ps.Eq(Status, "DURUYOR"))
        {
            string ph = StopPhase switch { 2 => Lang.L("Dünya kaydediliyor"), 3 => Lang.L("Son işlemler yapılıyor"), _ => Lang.L("Kapatılıyor") };
            if (Short) return Pill("110;14;24", "255;220;222", Spin() + Lang.L(" KAPANIYOR")) + c.orange + "  " + ph + R;
            return Pill("110;14;24", "255;220;222", Spin() + Lang.L(" SUNUCU KAPANIYOR")) + "  " + Shimmer(ph + "…", new[] { 220, 45, 55 }, new[] { 255, 255, 255 }) + c.dim + Lang.L("  lütfen bekle") + R;
        }
        // PowerShell'de hiçbir durum eşleşmezse fonksiyon bir şey döndürmez ($null): birleştirmede boş metin
        return "";
    }

    // ---------- Render-Header (1491-1535) ----------
    private partial List<string> RenderHeader(int W)
    {
        var rows = new List<string>();
        var look = StatusLook[Status];
        Pack p = Packs[ActivePack];
        if (ShowLogo)
        {
            List<string> logo = RenderLogo(1.0, LogoShine());
            string[] info =
            {
                Bo + c.brass + Cur.ad.ToUpper() + R,
                c.dim + Lang.L("{0} {1}  ·  {2} mod  ·  en fazla {3} oyuncu", ViewLoaderName(Cur.loader), Cur.mc, ModCount, MaxPlayers) + R,
                c.dark + Ps.Rep("─", 38) + R,
                c.soft + Lang.L("Adres  ") + R + (HasFriendAddr ? Bo + c.cyan + FriendAddr : c.dim + Lang.L("dış adres yok")) + R,
                c.soft + Lang.L("Yerel  ") + R + c.dim + Lang.L("localhost  (bu bilgisayardan giriş)") + R,
                c.dim + Lang.L("F1 nasıl kullanılır  ·  F3 paket  ·  F2 gizle") + R,
            };
            rows.Add("");
            for (int i = 0; i < 6; i++) rows.Add("    " + logo[i] + (W >= LogoW + 52 ? "        " + info[i] : ""));
            rows.Add("");
        }
        int lw = (int)Math.Floor(W / 2.0); int rw = W - lw;
        string up = StartTime != null && S != null && S.Running ? FmtDur(Now() - StartTime.Value) : "--:--:--";
        string plist = Players.Count > 0 ? c.text + string.Join(", ", Players) : c.dim + Lang.L("kimse yok");
        string dot = Ps.In(Status, "BASLIYOR", "DURUYOR") ? Spin() : "●";
        string[] left =
        {
            look.Col + Bo + dot + " " + look.Text + R + "     " + c.dim + Lang.L("süre ") + R + c.text + up + R,
            c.soft + Lang.L("Oyuncular ") + R + Bo + c.text + Players.Count + "/" + MaxPlayers + R + "   " + plist + R,
            c.soft + Lang.L("Paket     ") + R + Bo + ViewPackColor(ActivePack) + PackName(ActivePack) + R + "   " + c.dim + Lang.L("öncelik ") + R + c.text + ViewPrio(p.oncelik) + R + (RamPending ? "   " + c.yellow + Lang.L("! RAM için 'yeniden'") + R : ""),
        };
        int barW = Math.Max(8, rw - 40);
        bool running = S != null && S.Running;
        double ramGb = RamNow / 1073741824.0;
        int ramMax = running ? LoadedRamMax : p.ramMax;
        string ramTxt = running ? Ps.F("{0,4:0.0} / {1} GB", ramGb, ramMax) : "  - / " + ramMax + " GB";
        string cpuTxt = running ? Ps.F("{0,4:0}%", CpuNow) : "   -";
        int cores = Math.Min(p.cekirdek, Threads);
        string plTxt = HasFriendAddr && PlayitOn() ? c.green + Lang.L("● açık (playit)") : HasFriendAddr ? c.yellow + Lang.L("● bağlanıyor") : c.yellow + Lang.L("● yok");
        string[] right =
        {
            c.soft + "RAM  " + R + Bar(running ? ramGb / Math.Max(1, ramMax) : 0, barW) + " " + c.text + ramTxt + R,
            c.soft + "CPU  " + R + Bar(running ? CpuNow / 100 : 0, barW) + " " + c.text + cpuTxt + R + c.dim + Lang.L("  {0}/{1} çekirdek", cores, Threads) + R,
            c.soft + Lang.L("Dış erişim ") + R + plTxt + R + "    " + c.soft + Lang.L("Bilgisayar ") + R + c.text + Ps.F(Lang.L("{0:0.0} GB boş"), SysFree / 1073741824.0) + R,
        };
        List<string> lc = Card(Lang.L("DURUM"), left, lw);
        List<string> rc = Card(Lang.L("KAYNAKLAR"), right, rw);
        for (int i = 0; i < lc.Count; i++) rows.Add(lc[i] + rc[i]);
        return rows;
    }

    // ---------- Render-Log (1537-1560) ----------
    private partial List<string> RenderLog(int W, int H)
    {
        var rows = new List<string>();
        int pre = 18; int avail = Math.Max(10, W - pre - 1);
        int idx = Log.Count - 1; int skip = Scroll;
        while (idx >= 0 && skip > 0) { if (Detail || Log[idx].V) skip--; idx--; }
        while (idx >= 0 && rows.Count < H)
        {
            LogEntry en = Log[idx];
            if (!Detail && !en.V) { idx--; continue; }
            if (!Badge.TryGetValue(en.K ?? "", out var bd)) bd = Badge["info"];
            string msg = en.M ?? ""; var chunks = new List<string>();
            if (msg.Length == 0) chunks.Add("");
            for (int i = 0; i < msg.Length; i += avail) chunks.Add(msg.Substring(i, Math.Min(avail, msg.Length - i)));
            for (int j = chunks.Count - 1; j >= 0; j--)
            {
                string head;
                if (j == 0) head = c.dark + en.T + " " + R + bd.C1 + Bo + bd.Label.PadRight(6) + R + c.dark + " │ " + R;
                else head = Ps.Rep(" ", 15) + c.dark + " │ " + R;
                rows.Insert(0, head + bd.C2 + chunks[j] + R);
            }
            idx--;
        }
        // H < 0 iken (pencere çok kısa) PowerShell boş listede RemoveAt çağırıp hata ekranına düşer;
        // burada döngü boş listede durur. H >= 0 için çıktı birebir aynıdır. (Packs/Confirm/Closing'de de aynı)
        while (rows.Count > H && rows.Count > 0) rows.RemoveAt(0);
        if (rows.Count == 0) rows.Add(c.dim + Lang.L("  Henüz önemli bir olay yok. Tüm teknik kayıtları görmek için F5.") + R);
        while (rows.Count < H) rows.Insert(0, "");
        return rows;
    }

    // ---------- Render-Help (1562-1590) ----------
    private partial List<string> RenderHelp(int W, int H)
    {
        string k = c.brass, d = c.soft, hd = Bo + c.text;
        string[] items =
        {
            Bo + c.brass + Lang.L("NASIL KULLANILIR?") + R + c.dim + Lang.L("   (Esc ile kapat)") + R,
            "",
            hd + Lang.L("1) Sunucu açılırken") + R,
            d + "   " + Lang.L("Üstteki şerit SARI iken bekle. YEŞİL/BEYAZ \"SUNUCU AÇIK\" yazınca hazırdır.") + R,
            hd + Lang.L("2) Arkadaşını oyuna almak") + R,
            d + "   " + Lang.L("a. {0} yaz, Enter'a bas  →  adres panoya kopyalanır", k + Cmd("kopyala") + R + d) + R,
            d + "   " + Lang.L("b. Discord'dan arkadaşına yapıştır (Ctrl+V)") + R,
            d + "   " + Lang.L("c. Arkadaşın: Minecraft → Çok Oyunculu → Sunucu Ekle → adresi yapıştırır") + R,
            hd + Lang.L("3) Kapatmak") + R,
            d + "   " + Lang.L("F10 → Enter: sunucuyu kapatıp ana menüye döner.  K: her şeyi kapatır.") + R,
            hd + Lang.L("4) Gizlemek / küçültmek") + R,
            d + "   " + Lang.L("F2 gizler (sunucu çalışmaya devam eder). Geri getirmek için Ctrl+Alt+G (her yerden).") + R,
            d + "   " + Lang.L("F4 ya da Ctrl+Alt+K köşedeki küçük moda geçirir. F6 küçük modu üstte tutar.") + R,
            hd + Lang.L("5) Performans paketi") + R,
            d + "   " + Lang.L("F3 bas → ← → ile seç → Enter. Oyun oynarken DÜŞÜK, normalde NORMAL.") + R,
            hd + Lang.L("6) Diğer") + R,
            d + "   " + Lang.L("{0} dünyayı yedekler (zaten 3 saatte bir kendiliğinden)   F5 tüm teknik kayıtları gösterir", k + Cmd("yedek") + R + d) + R,
            d + "   " + Lang.L("Oyun komutlarını direkt yaz: op isim (yönetici yap)  kick isim  say mesaj  time set day") + R,
            "",
            c.dim + "  " + Lang.L("Tüm komutlar: {0}", string.Join(" ", Builtins)) + R,
        };
        var rows = new List<string>();
        foreach (string i in items) { if (rows.Count < H) rows.Add("  " + i); }
        while (rows.Count < H) rows.Add("");
        return rows;
    }

    // ---------- Render-Packs (1592-1624) ----------
    private partial List<string> RenderPacks(int W, int H)
    {
        var rows = new List<string>();
        int cw = (int)Math.Floor((W - 6) / 3.0); int inner = cw - 4;
        var cards = new List<List<string>>();
        for (int i = 0; i < 3; i++)
        {
            string key = PackKeys[i]; Pack p = Packs[key]; bool sel = i == PackSel; bool act = Ps.Eq(key, ActivePack);
            string bc, tl, tr, bl, br, hz, vt;
            if (sel) { bc = c.brass; tl = "╔"; tr = "╗"; bl = "╚"; br = "╝"; hz = "═"; vt = "║"; } else { bc = c.dark; tl = "╭"; tr = "╮"; bl = "╰"; br = "╯"; hz = "─"; vt = "│"; }
            var body = new List<string>();
            body.Add("");
            body.Add(Bo + ViewPackColor(key) + (i + 1) + "  " + PackName(key) + R);
            body.Add(c.dark + Ps.Rep("─", Math.Min(18, inner)) + R);
            body.Add(c.soft + Lang.L("RAM       ") + R + c.text + p.ramMin + "-" + p.ramMax + " GB" + R);
            body.Add(c.soft + Lang.L("Çekirdek  ") + R + c.text + Math.Min(p.cekirdek, Threads) + " / " + Threads + R);
            body.Add(c.soft + Lang.L("Öncelik   ") + R + c.text + ViewPrio(p.oncelik) + R);
            body.Add("");
            foreach (string l in WordWrap(PackDesc(key), inner)) body.Add(c.dim + l + R);
            while (body.Count < 11) body.Add("");
            body.Add(act ? c.green + Bo + Lang.L("● ŞU AN AKTİF") + R : sel ? c.brass + Lang.L("Enter ile seç") + R : "");
            var card = new List<string> { bc + tl + Ps.Rep(hz, cw - 2) + tr + R };
            foreach (string l in body) card.Add(bc + vt + R + " " + PadV(l, inner) + " " + bc + vt + R);
            card.Add(bc + bl + Ps.Rep(hz, cw - 2) + br + R);
            cards.Add(card);
        }
        rows.Add("");
        rows.Add("  " + Bo + c.brass + Lang.L("KAYNAK PAKETİ SEÇ") + R + c.dim + Lang.L("   Çekirdek ve öncelik anında değişir, RAM yeniden başlatınca.") + R);
        rows.Add("");
        // Kartların satır sayısı farklıysa PowerShell olmayan satırı boş ($null) sayar
        for (int ri = 0; ri < cards[0].Count; ri++) rows.Add("  " + cards[0][ri] + " " + ViewAt(cards[1], ri) + " " + ViewAt(cards[2], ri));
        rows.Add("");
        rows.Add("  " + Key("← →", Lang.L("seç")) + Key("1 2 3", Lang.L("hızlı seçim")) + Key("Enter", Lang.L("uygula")) + Key("Esc", Lang.L("vazgeç")));
        while (rows.Count > H && rows.Count > 0) rows.RemoveAt(rows.Count - 1);
        while (rows.Count < H) rows.Add("");
        return rows;
    }

    // ---------- Mark (1626) ----------
    private partial string Mark(int state) => state switch
    {
        2 => c.green + Bo + "✓" + R,
        1 => c.yellow + Spin() + R,
        _ => c.dark + "·" + R,
    };

    // ---------- Render-Confirm (1627-1641) ----------
    private partial List<string> RenderConfirm(int W, int H)
    {
        var rows = new List<string>();
        rows.Add("");
        rows.Add("  " + Bo + c.red + Lang.L("{0} KAPATILSIN MI?", Cur.ad.ToUpper()) + R);
        rows.Add("");
        if (Players.Count > 0) { rows.Add("  " + c.yellow + Lang.L("Dikkat: şu an {0} kişi oyunda ({1})", Players.Count, string.Join(", ", Players)) + R); rows.Add(""); }
        rows.Add("  " + c.soft + Lang.L("Oyunculara haber verilir, dünya kaydedilir, sunucu kapanır.") + R);
        rows.Add("");
        rows.Add("  " + Pill("190;28;42", "255;255;255", "Enter") + c.text + Lang.L(" Kapat, ana menüye dön") + R);
        rows.Add("  " + Pill("200;30;45", "255;255;255", "  K  ") + c.text + Lang.L(" Kapat ve SyHost'u tamamen kapat") + R);
        rows.Add("  " + Pill("50;50;56", "235;235;235", " Esc ") + c.text + Lang.L(" Vazgeç") + R);
        while (rows.Count > H && rows.Count > 0) rows.RemoveAt(rows.Count - 1);
        while (rows.Count < H) rows.Add("");
        return rows;
    }

    // ---------- Render-Closing (1642-1664) ----------
    private partial List<string> RenderClosing(int W, int H)
    {
        bool running = S != null && S.Running;
        int s1 = ShutdownStopAt != null ? 1 : 2;
        int s2 = !running || StopPhase >= 3 ? 2 : ShutdownStopAt == null ? 1 : 0;
        int s3 = !running ? 2 : StopPhase >= 3 ? 1 : 0;
        int s4 = FinishAt != null ? 1 : 0;
        int el = ClosingSince != null ? Ps.Int((Now() - ClosingSince.Value).TotalSeconds) : 0;
        string last = Ps.Eq(AfterClose, "quit") ? Lang.L("SyHost kapanıyor") : Lang.L("Ana menüye dönülüyor");
        var rows = new List<string>();
        rows.Add("");
        rows.Add("  " + Shimmer(Lang.L("KAPATILIYOR"), new[] { 220, 45, 55 }, new[] { 255, 255, 255 }, 10) + c.dim + "   " + el + " sn" + R);
        rows.Add("");
        rows.Add("  " + Mark(s1) + " " + c.text + Lang.L("Oyunculara haber veriliyor") + R);
        rows.Add("  " + Mark(s2) + " " + c.text + Lang.L("Dünya kaydediliyor") + R);
        rows.Add("  " + Mark(s3) + " " + c.text + Lang.L("Sunucu kapanıyor") + R);
        rows.Add("  " + Mark(s4) + " " + c.text + last + R);
        rows.Add("");
        if (FinishAt != null) rows.Add("  " + c.green + Bo + Lang.L("Her şey kaydedildi.") + R);
        else rows.Add("  " + c.dim + Lang.L("Bekle, kendisi bitecek. 60 sn içinde kapanmazsa zorla kapatılır.") + R);
        while (rows.Count > H && rows.Count > 0) rows.RemoveAt(rows.Count - 1);
        while (rows.Count < H) rows.Add("");
        return rows;
    }

    // ---------- Render-Mini (1667-1707) ----------
    private partial List<string> RenderMini(int W, int H)
    {
        var rows = new List<string>();
        bool running = S != null && S.Running;
        Pack p = Packs[ActivePack];
        string up = StartTime != null && running ? FmtDur(Now() - StartTime.Value) : "--:--:--";
        string pin = Win.ustte ? c.brass + "■" : c.dark + "□";
        string left = GetStatusStrip(true);
        string right = c.text + up + R + " " + pin + R;
        rows.Add(left + Ps.Rep(" ", Math.Max(1, W - VLen(left) - VLen(right))) + right);
        rows.Add(c.dark + Ps.Rep("─", W) + R);
        string plist = Players.Count > 0 ? c.text + string.Join(", ", Players) : c.dim + Lang.L("kimse yok");
        rows.Add(Bo + c.brass + Cur?.ad + R + c.dark + "  ·  " + R + c.soft + Lang.L("Oyuncu ") + R + Bo + c.text + Players.Count + "/" + MaxPlayers + "  " + R + plist + R);
        int ramMax = running ? LoadedRamMax : p.ramMax;
        int barW = Math.Max(6, W - 22);
        rows.Add(c.soft + "RAM " + R + Bar(running ? (RamNow / 1073741824.0) / Math.Max(1, ramMax) : 0, barW) + c.text + (running ? Ps.F(" {0,4:0.0}/{1} GB", RamNow / 1073741824.0, ramMax) : "   -/" + ramMax + " GB") + R);
        rows.Add(c.soft + "CPU " + R + Bar(running ? CpuNow / 100 : 0, barW) + c.text + (running ? Ps.F(" {0,4:0}%", CpuNow) : "    -") + R);
        string plTxt = HasFriendAddr && PlayitOn() ? c.green + "●" : c.yellow + "●";
        rows.Add(c.soft + Lang.L("Paket ") + R + Bo + ViewPackColor(ActivePack) + PackName(ActivePack) + R + (RamPending ? c.yellow + " !" + R : "") + c.dark + "  ·  " + R + c.soft + Lang.L("dış ") + R + plTxt + R + (!string.IsNullOrEmpty(BackupStage) ? c.dark + "  ·  " + R + c.brass + Lang.L("yedek...") + R : ""));
        rows.Add((HasFriendAddr ? Bo + c.cyan + FriendAddr : c.dim + Lang.L("yerel: localhost")) + R);
        rows.Add(c.dark + "── " + R + c.dim + Lang.L("son olaylar ") + c.dark + Ps.Rep("─", Math.Max(0, W - 15)) + R);
        int evH = H - rows.Count - 2;
        if (Ps.In(Mode, "kapat", "closing"))
        {
            List<string> ov = Ps.Eq(Mode, "kapat") ? RenderConfirm(W, evH + 1) : RenderClosing(W, evH + 1);
            rows.RemoveAt(rows.Count - 1);
            foreach (string l in ov) rows.Add(l.Substring(Math.Min(1, l.Length)));
            rows.Add((Ps.Eq(Mode, "kapat") ? c.text + Lang.L("Enter menü · K tamamen kapat · Esc vazgeç") : c.dim + Lang.L("kapanıyor, bekle...")) + R);
            return rows;
        }
        var ev = new List<string>();
        for (int i = Log.Count - 1; i >= 0 && ev.Count < evH; i--)
        {
            LogEntry en = Log[i];
            if (!Ps.In(en.K, MiniKinds)) continue;
            var bd = Badge[en.K];
            ev.Insert(0, c.dark + en.T.Substring(0, 5) + " " + R + bd.C2 + en.M + R);
        }
        if (ev.Count == 0) ev.Add(c.dim + Lang.L("henüz bir şey yok") + R);
        while (ev.Count < evH) ev.Add("");
        foreach (string l in ev) rows.Add(l);
        rows.Add(Key("F4", Lang.L("büyüt")) + Key("F2", Lang.L("gizle")) + Key("F6", Lang.L("üstte")) + c.red + Bo + "F10" + R + c.dim + Lang.L(" kapat") + R);
        return rows;
    }

    // ---------- Render-Server (1709-1727) ----------
    private partial List<string> RenderServer(int W, int H)
    {
        var all = new List<string>();
        if (Ps.Eq(UiMode, "kucuk"))
        {
            foreach (string mr in RenderMini(W - 1, H - 1)) all.Add(" " + mr);
            return all;
        }
        ShowLogo = H >= 34 && W >= 70;
        foreach (string hr in RenderHeader(W)) all.Add(hr);
        all.Add(" " + GetStatusStrip());
        string label;
        if (Ps.Eq(Mode, "help")) label = Lang.L("YARDIM");
        else if (Ps.Eq(Mode, "paket")) label = Lang.L("PAKETLER");
        else if (Ps.Eq(Mode, "kapat")) label = Lang.L("KAPAT");
        else if (Ps.Eq(Mode, "closing")) label = Lang.L("KAPATILIYOR");
        else label = Detail ? Lang.L("KONSOL · detaylı") : Lang.L("KONSOL · sade (önemli olaylar)");
        string extra = Ps.Eq(Mode, "log") && Scroll > 0 ? c.yellow + Lang.L(" ▲ {0} satır yukarıdasın · End ile en alta ", Scroll) + R : !string.IsNullOrEmpty(BackupStage) ? c.brass + " " + Spin() + Lang.L(" yedek alınıyor... ") + R : "";
        all.Add(Rule(label, W, extra));
        int bodyH = H - all.Count - 3;
        List<string> body;
        if (Ps.Eq(Mode, "help")) body = RenderHelp(W, bodyH);
        else if (Ps.Eq(Mode, "paket")) body = RenderPacks(W, bodyH);
        else if (Ps.Eq(Mode, "kapat")) body = RenderConfirm(W, bodyH);
        else if (Ps.Eq(Mode, "closing")) body = RenderClosing(W, bodyH);
        else body = RenderLog(W, bodyH);
        foreach (string br2 in body) all.Add(br2);
        all.Add(c.dark + Ps.Rep("─", W) + R);
        all.Add(" " + Key("F1", Lang.L("nasıl kullanılır")) + Key("F2", Lang.L("gizle")) + Key("F3", Lang.L("paket")) + Key("F4", Lang.L("küçük")) + Key("F5", Lang.L("detaylı konsol")) + c.dark + "│  " + R + Pill("200;30;45", "255;255;255", Lang.L("F10 KAPAT")));
        return all;
    }

    // ---------- Yardımcılar ----------
    // PowerShell'de tabloda olmayan anahtar $null (boş metin) verir. Anahtarın kendisi $null ise
    // PowerShell hata verir ("array index evaluated to null"); burada o durumda da boş metin döner.
    string ViewLoaderName(string k) => k != null && LoaderName.TryGetValue(k, out var v) ? v : null;
    string ViewPrio(string k) => k != null && PrioTr.TryGetValue(k, out var v) ? v : null;
    string ViewPackColor(string k) => k != null && PackColor.TryGetValue(k, out var v) ? v : null;
    string ViewStageName(int k) => StageNames.TryGetValue(k, out var v) ? v : null;
    // Dizinin dışındaki satır PowerShell'de $null olur
    static string ViewAt(List<string> list, int i) => i >= 0 && i < list.Count ? list[i] : null;
}
