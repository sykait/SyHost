// =====================================================================
//  SyHost - Kaldır ekranı (Ayarlar > SyHost'u kaldır)
//  Klasörün dışında kalan her iz ayrı bir satırda; kullanıcı ne kaldırılacağını
//  tek tek seçer (Boşluk). Java varsayılan olarak seçili gelmez. Klasörü silmek
//  ayrıca seçilir ve ikinci bir Enter ile onaylanır. Klasör dışındaki sunuculara
//  asla dokunulmaz. Görünüm "kapatılıyor" ekranındaki adım listesi gibidir.
// =====================================================================
namespace SyHost;

sealed partial class App
{
    List<Uninstall.Item> UnItems;
    int UnSel;
    string UnPhase = "liste";    // liste | onay | calisiyor | bitti
    Task UnJob;

    void StartUninstall()
    {
        UnItems = Uninstall.Detect(AppRoot, ExePath, Servers);
        UnSel = 0; UnPhase = "liste"; UnJob = null;
        Screen = "uninstall";
        ResetFrame();
    }

    int UnServersInside => Servers.Count(s => Portable.IsInside(s.klasor ?? "", AppRoot));

    private partial List<string> RenderUninstall(int W, int H)
    {
        if (UnItems == null) StartUninstall();
        if (UnPhase == "calisiyor" && UnJob != null && UnJob.IsCompleted) UnFinish();
        var rows = new List<string>
        {
            "",
            "  " + Bo + c.red + Lang.L("SYHOST'U KALDIR") + R + c.dim + "   " + AppRoot + R,
            "",
            Rule(UnPhase == "bitti" ? Lang.L("BİTTİ") : Lang.L("NELER KALDIRILSIN?"), W),
            "",
        };
        bool listing = UnPhase == "liste" || UnPhase == "onay";
        for (int i = 0; i < UnItems.Count; i++)
        {
            var it = UnItems[i];
            if (!listing && !it.On) continue;
            string detail = it.Key == "klasor"
                ? c.yellow + Lang.L("içinde {0} sunucu ve dünyaları var", UnServersInside) + R
                : c.dim + it.Detail + R;
            if (it.NeedsAdmin) detail += c.yellow + "  ·  " + Lang.L("Windows izin isteyecek") + R;
            string line;
            if (listing)
            {
                bool sel = i == UnSel;
                string box = it.On ? (it.Key == "klasor" ? c.red : c.brass) + Bo + "■" + R : c.dark + "□" + R;
                line = "  " + (sel ? c.brass + Bo + "❯" : " ") + R + " " + box + " " + PadV((sel ? Bo + c.text : c.soft) + Lang.L(it.Title), 46) + "  " + detail;
                rows.Add(sel ? SelLine(line, W) : line);
            }
            else
            {
                string mark = it.State switch { 2 => c.green + Bo + "✓", 1 => c.yellow + Spin(), 3 => c.red + Bo + "x", _ => c.dark + "·" };
                line = "  " + mark + R + " " + c.text + Lang.L(it.Title) + R + (it.State == 3 ? c.red + "   " + it.Error + R : "");
                rows.Add(line);
            }
        }
        rows.Add("");
        if (listing)
        {
            rows.Add("  " + c.dim + Lang.L("Java varsayılan olarak silinmez; başka programlar da kullanıyor olabilir.") + R);
            var outside = Servers.Where(s => !Portable.IsInside(s.klasor ?? "", AppRoot)).Select(s => s.klasor).ToList();
            if (outside.Count > 0) foreach (string l in WordWrap(Lang.L("Klasörün dışındaki sunuculara dokunulmaz: {0}", string.Join(", ", outside)), W - 6)) rows.Add("  " + c.dim + l + R);
            rows.Add("");
            if (UnPhase == "onay")
            {
                foreach (string l in WordWrap(Lang.L("Emin misin? SyHost klasörü, içindeki sunucular ve dünyalarla birlikte silinecek. Onaylamak için tekrar Enter'a bas."), W - 6)) rows.Add("  " + Bo + c.red + l + R);
                rows.Add("");
            }
            rows.Add("  " + Pill("200;30;45", "255;255;255", "Enter") + c.text + Lang.L(" Seçilenleri kaldır   ") + R + Pill("50;50;56", "235;235;235", Lang.L("Boşluk")) + c.text + Lang.L(" seç / bırak   ") + R + Pill("50;50;56", "235;235;235", "Esc") + c.text + Lang.L(" Vazgeç") + R);
        }
        else if (UnPhase == "calisiyor")
        {
            rows.Add("  " + c.brass + Pulse() + R + " " + Shimmer(Lang.L("Kaldırılıyor…"), new[] { 110, 110, 120 }, new[] { 255, 60, 70 }));
        }
        else
        {
            bool folder = UnItems.Any(x => x.Key == "klasor" && x.On);
            rows.Add("  " + c.green + Bo + Lang.L("Kaldırma tamamlandı.") + R);
            rows.Add("  " + c.soft + (folder ? Lang.L("SyHost kapanınca klasörü de silinecek.") : Lang.L("Artık SyHost klasörünü silebilirsin; Explorer'da gösterdim.")) + R);
            if (DryRunShown) rows.Add("  " + c.yellow + Lang.L("Deneme modu: hiçbir şey silinmedi.") + R);
            rows.Add("");
            rows.Add("  " + Pill("240;240;240", "18;18;20", "Enter") + c.text + Lang.L(" SyHost'u kapat") + R);
        }
        while (rows.Count < H - 2) rows.Add("");
        UpdateSky(W, H, 0.07, 1, false, 0.75);
        for (int r1 = 0; r1 < rows.Count; r1++) if (rows[r1] == "") rows[r1] = SkySeg(r1, 0, W);
        rows.Add(c.dark + new string('─', W) + R);
        rows.Add(" " + (listing ? Key("↑↓", Lang.L("seç")) + Key(Lang.L("Boşluk"), Lang.L("seç / bırak")) + Key("Enter", Lang.L("kaldır")) + Key("Esc", Lang.L("vazgeç")) : UnPhase == "bitti" ? Key("Enter", Lang.L("kapat")) : ""));
        return rows;
    }

    private partial void HandleUninstallKey(ConsoleKeyInfo k, bool ctrl)
    {
        switch (UnPhase)
        {
            case "liste":
            case "onay":
                switch (k.Key)
                {
                    case ConsoleKey.UpArrow: UnSel = (UnSel + UnItems.Count - 1) % UnItems.Count; UnPhase = "liste"; return;
                    case ConsoleKey.DownArrow: UnSel = (UnSel + 1) % UnItems.Count; UnPhase = "liste"; return;
                    case ConsoleKey.Spacebar: UnItems[UnSel].On = !UnItems[UnSel].On; UnPhase = "liste"; return;
                    case ConsoleKey.Escape: UnItems = null; Screen = "settings"; ResetFrame(); return;
                    case ConsoleKey.Enter:
                        if (UnItems.Any(x => x.Key == "klasor" && x.On) && UnPhase != "onay") { UnPhase = "onay"; return; }
                        if (!UnItems.Any(x => x.On)) return;
                        UnPhase = "calisiyor";
                        if (UnItems.Any(x => x.Key == "klasor" && x.On)) StopPlayit();
                        var items = UnItems;
                        UnJob = Task.Run(() => Uninstall.RunSelected(items));
                        return;
                }
                return;
            case "bitti":
                if (k.Key == ConsoleKey.Enter) StartOutro();
                return;
        }
    }

    void UnFinish()
    {
        UnPhase = "bitti";
        if (UnItems.Any(x => x.Key == "klasor" && x.On)) DeleteRootAfterExit = true;
        else if (!Uninstall.DryRun && !TestMode) Uninstall.ShowFolder(AppRoot);
        Dirty = true;
    }
}
