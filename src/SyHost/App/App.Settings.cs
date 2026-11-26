// =====================================================================
//  SyHost - Ayarlar ekranı (ana menüde F9)
//  Görünüm ana menüdeki liste gibi: seçili satır nabız gibi atan koyu kırmızı
//  zeminle vurgulanır, altta seçili ayarın açıklaması kartta görünür.
//  Her değişiklik hemen ayarlar.json'a yazılır.
// =====================================================================
using System.Diagnostics;

namespace SyHost;

sealed partial class App
{
    int SetSel;
    string SetNote, SetNoteCol;

    static readonly (string Key, string Group, string Label, string Help)[] SettingRows =
    {
        ("dil", "GENEL", "Dil", "Arayüzün dili. Klasör adları da bu dilde görünür."),
        ("klasor", "GENEL", "Sunucu klasörü", "Yeni sunucuların kurulacağı yer. Enter ile değiştir."),
        ("masaustu", "GENEL", "Masaüstü kısayolu", "Enter ile aç ya da kapat."),
        ("baslat", "GENEL", "Başlat menüsü kısayolu", "Enter ile aç ya da kapat."),
        ("yazi", "GENEL", "Yazı boyutu", "← → ile ayarla. Pencere yeni boyuta göre büyür ya da küçülür."),
        ("arkadas", "SUNUCU", "Arkadaş bağlantısı (playit)", "Arkadaşlarının internetten bağlanması için. Enter ile kur ya da yeniden bağla."),
        ("java", "SUNUCU", "Java", "Bulunan Java sürümleri. Enter ile Java 21'i SyHost klasörüne indir."),
        ("oyuncu", "SUNUCU", "Maksimum oyuncu", "Yeni kurulan sunucular için. ← → ile ayarla."),
        ("yedek", "SUNUCU", "Otomatik yedek", "Sunucu açıkken dünya kaç saatte bir yedeklensin. 0 = kapalı."),
        ("sakla", "SUNUCU", "Saklanacak yedek", "Her sunucuda tutulacak en yeni yedek sayısı."),
        ("cokme", "SUNUCU", "Çökerse yeniden başlat", "Sunucu beklenmedik şekilde kapanırsa 10 saniye sonra yeniden açılır."),
        ("ac", "SYHOST", "Klasörü aç", "SyHost klasörünü Explorer'da açar."),
        ("kaldir", "SYHOST", "SyHost'u kaldır", "Kısayolları ve klasör dışındaki izleri kaldırır; istersen klasörü de siler."),
    };

    void OpenSettings()
    {
        SetSel = 0; SetNote = null;
        Screen = "settings";
        ResetFrame();
    }

    string OnOff(bool on) => on ? c.green + "● " + Lang.L("açık") + R : c.dim + "○ " + Lang.L("kapalı") + R;

    string ShortcutValue(string lnk)
    {
        var st = Shortcuts.StateOf(lnk, ExePath);
        if (st == Shortcuts.State.Ours) return OnOff(true);
        if (st == Shortcuts.State.OtherLive) return c.yellow + "● " + Lang.L("başka bir SyHost'u açıyor") + R;
        return OnOff(false);
    }

    string SettingValue(string key)
    {
        switch (key)
        {
            case "dil": return c.text + Lang.NameOf(Lang.Code) + R;
            case "klasor": return c.text + Cfg.sunucuKokKlasoru + R;
            case "masaustu": return ShortcutValue(Shortcuts.DesktopPath);
            case "baslat": return ShortcutValue(Shortcuts.StartMenuPath);
            case "yazi": return c.text + (Cfg.yaziTipiBoyutu != 0 ? Cfg.yaziTipiBoyutu : 16) + R + c.dark + "   ‹ ›" + R;
            case "arkadas":
                if (PlayitOn()) return c.green + Lang.L("● açık (playit)") + R + "  " + Bo + c.cyan + Cfg.arkadasAdresi + R;
                if (HasFriendAddr) return c.yellow + Lang.L("● bağlanıyor") + R + "  " + Bo + c.cyan + Cfg.arkadasAdresi + R;
                return c.dim + Lang.L("kurulu değil") + R;
            case "java":
            {
                var parts = new List<string>();
                foreach (int m in new[] { 21, 17, 8 }) parts.Add(FindJava(m) != null ? c.text + m + " " + c.green + "✓" + R : c.dark + m + " —" + R);
                return string.Join("   ", parts);
            }
            case "oyuncu": return c.text + MaxPlayers + R + c.dark + "   ‹ ›" + R;
            case "yedek": return c.text + (Cfg.otomatikYedekSaat <= 0 ? Lang.L("kapalı") : Lang.L("{0} saatte bir", Cfg.otomatikYedekSaat)) + R + c.dark + "   ‹ ›" + R;
            case "sakla": return c.text + Cfg.saklanacakYedek + R + c.dark + "   ‹ ›" + R;
            case "cokme": return OnOff(Cfg.cokerseYenidenBaslat);
            case "ac": return c.dim + AppRoot + R;
            default: return "";
        }
    }

    private partial List<string> RenderSettings(int W, int H)
    {
        var rows = new List<string>
        {
            "",
            "  " + Bo + c.brass + Lang.L("AYARLAR") + R + "   " + VersionLine(),
        };
        string group = null;
        for (int i = 0; i < SettingRows.Length; i++)
        {
            var s = SettingRows[i];
            if (s.Group != group) { group = s.Group; rows.Add(""); rows.Add(Rule(Lang.L(group), W)); }
            bool sel = i == SetSel;
            string label = s.Key == "kaldir" ? (sel ? Bo + c.red : c.red) + Lang.L(s.Label) : (sel ? Bo + c.text : c.soft) + Lang.L(s.Label);
            string line = "  " + (sel ? c.brass + Bo + "❯" : " ") + R + " " + PadV(label, 30) + "  " + SettingValue(s.Key);
            rows.Add(sel ? SelLine(line, W) : line);
        }
        rows.Add("");
        var cur = SettingRows[SetSel];
        var lines = new List<string>();
        foreach (string l in WordWrap(Lang.L(cur.Help), Math.Min(W, 90) - 6)) lines.Add(c.soft + l + R);
        if (SetNote != null) foreach (string l in WordWrap(SetNote, Math.Min(W, 90) - 6)) lines.Add(SetNoteCol + l + R);
        foreach (string l in Card(Lang.L(cur.Label).ToUpper(), lines, Math.Min(W, 90))) rows.Add(" " + l);

        while (rows.Count < H - 2) rows.Add("");
        UpdateSky(W, H, 0.07, 1, false, 0.75);
        for (int r1 = 0; r1 < rows.Count; r1++) if (rows[r1] == "") rows[r1] = SkySeg(r1, 0, W);
        rows.Add(c.dark + new string('─', W) + R);
        rows.Add(" " + Key("↑↓", Lang.L("seç")) + Key("Enter", Lang.L("değiştir")) + Key("← →", Lang.L("ayarla")) + Key("Esc", Lang.L("geri")));
        return rows;
    }

    private partial void HandleSettingsKey(ConsoleKeyInfo k, bool ctrl)
    {
        int n = SettingRows.Length;
        string key = SettingRows[SetSel].Key;
        switch (k.Key)
        {
            case ConsoleKey.UpArrow: SetSel = (SetSel + n - 1) % n; SetNote = null; return;
            case ConsoleKey.DownArrow: SetSel = (SetSel + 1) % n; SetNote = null; return;
            case ConsoleKey.Escape: case ConsoleKey.F9: Screen = "home"; ResetFrame(); return;
            case ConsoleKey.LeftArrow: SettingAdjust(key, -1); return;
            case ConsoleKey.RightArrow: SettingAdjust(key, +1); return;
            case ConsoleKey.Enter: SettingEnter(key); return;
        }
    }

    void SettingAdjust(string key, int d)
    {
        switch (key)
        {
            case "dil":
            {
                int i = Array.FindIndex(Lang.Languages, l => l.Code == Lang.Code);
                int n = Lang.Languages.Length;
                SetLanguage(Lang.Languages[((i + d) % n + n) % n].Code);
                return;
            }
            case "yazi":
                Cfg.yaziTipiBoyutu = Math.Clamp((Cfg.yaziTipiBoyutu != 0 ? Cfg.yaziTipiBoyutu : 16) + d, 10, 36);
                SaveConfig();
                Native.SetFont(Fonts.Face, (short)Cfg.yaziTipiBoyutu);
                ResetFrame();
                return;
            case "oyuncu": MaxPlayers = Math.Clamp(MaxPlayers + d, 1, 200); Cfg.maksOyuncu = MaxPlayers; SaveConfig(); return;
            case "yedek": Cfg.otomatikYedekSaat = Math.Clamp((int)Math.Round(Cfg.otomatikYedekSaat) + d, 0, 24); SaveConfig(); return;
            case "sakla": Cfg.saklanacakYedek = Math.Clamp(Cfg.saklanacakYedek + d, 1, 100); SaveConfig(); return;
            case "cokme": Cfg.cokerseYenidenBaslat = !Cfg.cokerseYenidenBaslat; SaveConfig(); return;
            case "masaustu": case "baslat": SettingEnter(key); return;
        }
    }

    void SettingEnter(string key)
    {
        SetNote = null;
        switch (key)
        {
            case "dil": SettingAdjust("dil", +1); return;
            case "klasor":
            {
                string picked = Native.PickFolder(Lang.L("Yeni sunucuların kurulacağı klasörü seç"), Directory.Exists(Cfg.sunucuKokKlasoru) ? Cfg.sunucuKokKlasoru : AppRoot);
                ResetFrame();
                if (string.IsNullOrEmpty(picked)) return;
                if (Portable.IsInOneDrive(picked)) { SetNote = Lang.L("Bu klasör OneDrive ile eşitleniyor. Sunucu dosyaları büyük ve sürekli değişir; OneDrive dışında bir yer önerilir."); SetNoteCol = c.yellow; }
                Cfg.sunucuKokKlasoru = picked; SaveConfig();
                return;
            }
            case "masaustu": case "baslat":
            {
                bool desk = Shortcuts.StateOf(Shortcuts.DesktopPath, ExePath) == Shortcuts.State.Ours;
                bool start = Shortcuts.StateOf(Shortcuts.StartMenuPath, ExePath) == Shortcuts.State.Ours;
                if (key == "masaustu") desk = !desk; else start = !start;
                ApplyShortcuts(desk, start);
                return;
            }
            case "arkadas": StartFirstRun("arkadas"); ResetFrame(); return;
            case "java":
                if (FindJava(21) != null) { SetNote = Lang.L("Java 21 hazır"); SetNoteCol = c.green; return; }
                StartFirstRun("java"); ResetFrame(); return;
            case "yazi": case "oyuncu": case "yedek": case "sakla": SettingAdjust(key, +1); return;
            case "cokme": SettingAdjust(key, +1); return;
            case "ac": try { Process.Start(new ProcessStartInfo("explorer.exe", "\"" + AppRoot + "\"") { UseShellExecute = true }); } catch { } return;
            case "kaldir": StartUninstall(); return;
        }
    }

    /// <summary>Dili hemen değiştir (yeniden başlatmadan): metinler, klasör adları ve kısayol açıklamaları.</summary>
    void SetLanguage(string code)
    {
        Lang.Code = code; Cfg.dil = code; SaveConfig();
        InitTables();
        string root = AppRoot; var dirs = Servers.Select(s => s.klasor).ToList();
        Task.Run(() => FolderLook.Apply(root, code, dirs));
        string desc = Lang.L("SyHost - modlu Minecraft sunucu merkezi");
        foreach (string lnk in Shortcuts.Locations())
            try { if (Shortcuts.StateOf(lnk, ExePath) == Shortcuts.State.Ours) Shortcuts.Write(lnk, ExePath, desc); } catch { }
        ResetFrame();
    }
}
