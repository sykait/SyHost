// =====================================================================
//  SyHost - yeni sunucu kurma sihirbazı (ekran tarafı)
//  legacy/src/SyHost.ps1'deki aynı adlı fonksiyonların birebir karşılığı:
//  Read-Pack (605-623), Safe-FolderName (625-632), Start-Wizard (795-803),
//  Wizard-WorldOptions (804-814), Begin-Install (815-831), Check-Install (832-845),
//  Handle-WizardKey (1006-1040), Render-Wizard (1360-1451).
//  Kurulumun kendisi (indirme, kopyalama) Core/Installer.cs'te.
// =====================================================================
using System.IO.Compression;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SyHost;

sealed partial class App
{
    // PowerShell'deki -match / -replace gibi büyük-küçük harf duyarsız
    static readonly Regex WizSaveRx = new(@"^overrides/saves/([^/]+)/level\.dat$", RegexOptions.IgnoreCase);
    static readonly Regex WizBadCharRx = new(@"[\\/:*?""<>|]", RegexOptions.IgnoreCase);
    static readonly Regex WizSpaceRx = new(@"\s+", RegexOptions.IgnoreCase);
    static readonly Regex WizIdRx = new("[^a-z0-9]", RegexOptions.IgnoreCase);

    // ---------- Paketi oku (Read-Pack) ----------
    private partial PackInfo ReadPack(string path)
    {
        using var zip = ZipFile.OpenRead(path);
        var ie = zip.GetEntry("modrinth.index.json");
        if (ie == null) throw new InvalidDataException(Lang.L("Bu dosya bir Modrinth paketi (.mrpack) değil."));
        string text;
        using (var sr = new StreamReader(ie.Open())) text = sr.ReadToEnd();
        using var doc = JsonDocument.Parse(text);
        JsonElement idx = doc.RootElement;
        JsonElement deps = WizProp(idx, "dependencies");
        string loader = null, lv = null;
        foreach (string k in new[] { "neoforge", "forge", "fabric-loader", "quilt-loader" })
        {
            if (WizHas(deps, k)) { loader = k.Replace("-loader", ""); lv = WizStr(WizProp(deps, k)); break; }
        }
        if (loader == null) throw new InvalidDataException(Lang.L("Paketin mod yükleyicisi anlaşılamadı."));

        // Hazır dünyalar: overrides/saves/<ad>/level.dat
        var found = new List<string>();
        foreach (var en in zip.Entries)
        {
            var m = WizSaveRx.Match(en.FullName);
            if (m.Success) found.Add(m.Groups[1].Value);
        }
        // Sort-Object -Unique: kültüre göre, büyük-küçük harf duyarsız sırala; aynı sayılanlardan birini tut
        var cmp = StringComparer.CurrentCultureIgnoreCase;
        var saves = new List<string>();
        foreach (string s in found.OrderBy(x => x, cmp)) if (saves.Count == 0 || cmp.Compare(saves[^1], s) != 0) saves.Add(s);

        // Sunucuya inecek modlar ve sadece oyuncuda çalışanlar (env.server yoksa sunucuda da çalışır sayılır)
        int mods = 0, clientOnly = 0;
        foreach (var f in WizItems(WizProp(idx, "files")))
        {
            bool unsupported = Ps.Eq(WizStr(WizProp(WizProp(f, "env"), "server")), "unsupported");
            string p = WizStr(WizProp(f, "path"));
            if (!unsupported && p != null && p.StartsWith("mods/", StringComparison.OrdinalIgnoreCase)) mods++;
            if (unsupported) clientOnly++;
        }
        string mc = WizStr(WizProp(deps, "minecraft"));
        return new PackInfo
        {
            Path = path, Name = WizStr(WizProp(idx, "name")), Version = WizStr(WizProp(idx, "versionId")), Mc = mc, Loader = loader, LoaderVer = lv,
            Java = GetJavaMajor(mc ?? ""), Mods = mods, ClientOnly = clientOnly,
            Saves = saves, SizeMb = Math.Round(new FileInfo(path).Length / 1048576.0),
        };
    }

    // JSON özelliği: PowerShell'deki gibi adı büyük-küçük harf duyarsız; aynı ad iki kez varsa sonuncusu geçer
    static JsonElement WizProp(JsonElement e, string name)
    {
        JsonElement v = default;
        if (e.ValueKind == JsonValueKind.Object)
            foreach (var p in e.EnumerateObject())
                if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) v = p.Value;
        return v;
    }

    // $obj.PSObject.Properties.Name -contains $name (değeri null olsa da özellik vardır)
    static bool WizHas(JsonElement e, string name)
    {
        if (e.ValueKind == JsonValueKind.Object)
            foreach (var p in e.EnumerateObject())
                if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    // Değerin metni; yoksa ya da null ise null
    static string WizStr(JsonElement e) => e.ValueKind switch
    {
        JsonValueKind.String => e.GetString(),
        JsonValueKind.Undefined or JsonValueKind.Null => null,
        _ => e.GetRawText(),
    };

    // $idx.files | Where-Object ... : dizi ise elemanları, tek bir nesne ise kendisi
    static IEnumerable<JsonElement> WizItems(JsonElement e)
    {
        if (e.ValueKind == JsonValueKind.Array) { foreach (var x in e.EnumerateArray()) yield return x; }
        else if (e.ValueKind == JsonValueKind.Object) yield return e;
    }

    // ---------- Klasör adı (Safe-FolderName) ----------
    private partial string SafeFolderName(string name)
    {
        string n = WizBadCharRx.Replace(name ?? "", "").Trim().TrimEnd('.');
        n = WizSpaceRx.Replace(n, "");
        if (n.Length == 0) n = "Sunucu";
        string bas = Path.Combine(Cfg.sunucuKokKlasoru, n), p = bas;
        int i = 2;
        // SyHost klasörünün kendisi sunucu klasörü seçildiyse App (Terminal sürümünün uygulaması) adı kullanılmaz
        while (File.Exists(p) || Directory.Exists(p) || IsReservedServerDir(p)) { p = bas + "-" + i; i++; }
        return p;
    }

    bool IsReservedServerDir(string p)
    {
        try
        {
            string parent = Path.GetDirectoryName(Path.GetFullPath(p))?.TrimEnd('\\');
            if (!string.Equals(parent, AppRoot.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) return false;
            string name = Path.GetFileName(p);
            return Ps.In(name, "App", "App.new", "App.old");
        }
        catch { return false; }
    }

    // ---------- Sihirbazı başlat (Start-Wizard) ----------
    private partial void StartWizard()
    {
        string path = Native.PickFile(Lang.L("Kurulacak modpack dosyasını seç (.mrpack)"), Lang.L("Modrinth paketi (*.mrpack)|*.mrpack"));
        ResetFrame();
        if (string.IsNullOrEmpty(path)) { ShowHomeMsg(Lang.L("Dosya seçilmedi.")); return; }
        PackInfo info;
        try { info = ReadPack(path); }
        catch (Exception ex) { ShowHomeMsg(Lang.L("Paket okunamadı: {0}", ex.Message)); return; }
        if (Ps.Eq(info.Loader, "quilt")) { ShowHomeMsg(Lang.L("Quilt paketleri henüz desteklenmiyor (NeoForge, Forge, Fabric destekleniyor).")); return; }
        // Adı olmayan pakette PowerShell sürümü Enter'da çöker; burada boş isimle başlar
        Wiz = new WizardState { Step = "isim", Info = info, Name = info.Name ?? "", WorldSel = 0, Sync = null, Job = null, Target = null };
        Screen = "wizard";
    }

    // ---------- Dünya seçenekleri (Wizard-WorldOptions) ----------
    private partial List<(string Label, string Value)> WizardWorldOptions()
    {
        var opts = new List<(string Label, string Value)>();
        var saves = Wiz?.Info?.Saves;
        int i = 1;
        if (saves != null)
        {
            foreach (string sv in saves)
            {
                string label = Lang.L("Paketteki kayıtlı dünyayla başla") + (saves.Count > 1 ? " (" + i + ")" : "");
                opts.Add((label, sv ?? ""));
                i++;
            }
        }
        opts.Add((Lang.L("Yepyeni bir dünya oluştur"), ""));
        return opts;
    }

    // PowerShell dizisi gibi: eksi sıra sondan sayar, dışarıdaysa boş
    static (string Label, string Value) WizOptAt(List<(string Label, string Value)> opts, int i)
    {
        if (i < 0) i += opts.Count;
        return i >= 0 && i < opts.Count ? opts[i] : (null, null);
    }

    static int WizSaveCount(PackInfo inf) => inf?.Saves?.Count ?? 0;

    // $LoaderName[$x]: tabloda yoksa boş ($null)
    static string WizLoaderName(string k) => k != null && LoaderName.TryGetValue(k, out string v) ? v : null;

    // ---------- Kurulum (Begin-Install, Check-Install) ----------
    private partial List<string> InstallStepNames(PackInfo info) => new()
    {
        Lang.L("Klasör hazırlanıyor"), Lang.L("Java {0} kontrol ediliyor", info.Java), Lang.L("{0} {1} kuruluyor", WizLoaderName(info.Loader), info.LoaderVer),
        Lang.L("Modlar indiriliyor"), Lang.L("Ayar dosyaları kopyalanıyor"), Lang.L("Dünya hazırlanıyor"), Lang.L("Son ayarlar yapılıyor"),
    };

    private partial void BeginInstall()
    {
        var w = Wiz;
        w.Target = SafeFolderName(w.Name);
        string worldName = WizSaveCount(w.Info) > 0 ? WizOptAt(WizardWorldOptions(), w.WorldSel).Value ?? "" : "";
        var sync = new InstallSync();
        foreach (string n in InstallStepNames(w.Info)) sync.Steps.Add(new InstallStep { N = n, S = 0 });
        PackInfo info = w.Info;
        string target = w.Target, voiceHost = Cfg.playitKullan ? Cfg.sesAdresi : "", motd = w.Name + " | SyHost", data = Data;
        int maxPlayers = MaxPlayers;
        w.Sync = sync;
        w.Job = Task.Run(() => WizInstall(sync, info, target, worldName, voiceHost, maxPlayers, motd, data));
        w.StartedAt = Now();
        w.Step = "kurulum";
    }

    // Arka planda çalışır. Installer.Run kendi hatalarını yakalar; yine de bir hata kaçarsa PowerShell'deki
    // gibi hata yazılır, süren adım x olur ve kurulum bitmiş sayılır (ekran "kuruluyor"da takılı kalmasın).
    static void WizInstall(InstallSync sync, PackInfo info, string target, string worldName, string voiceHost, int maxPlayers, string motd, string data)
    {
        try { Installer.Run(sync, info, target, worldName, voiceHost, maxPlayers, motd, data); }
        catch (Exception ex)
        {
            if (string.IsNullOrEmpty(sync.Error)) sync.Error = string.IsNullOrEmpty(ex.Message) ? ex.GetType().Name : ex.Message;
            foreach (var st in sync.Steps) if (st.S == 1) { st.S = 3; break; }
        }
        finally { sync.Done = true; }
    }

    private partial void CheckInstall()
    {
        var w = Wiz;
        if (w == null || !Ps.Eq(w.Step, "kurulum") || w.Sync == null || !w.Sync.Done) return;
        try { w.Job?.Wait(); } catch { }   // EndInvoke: Done en sonda yazılır, iş hemen biter
        if (!string.IsNullOrEmpty(w.Sync.Error)) { w.Step = "hata"; return; }
        var res = w.Sync.Result;
        string id = WizIdRx.Replace(Norm(w.Name), "");
        if (id.Length == 0) id = "sunucu";
        string bas = id; int k = 2;
        while (Servers.Exists(s => Ps.Eq(s?.id, id))) { id = bas + k; k++; }
        var entry = new ServerEntry
        {
            id = id, ad = w.Name, klasor = w.Target, mc = res?.mc, loader = res?.loader, loaderSurum = res?.loaderSurum, java = res?.java ?? 0, baslat = res?.baslat,
            paket = "normal", eklenme = Now().ToString("yyyy-MM-dd HH:mm"), sonAcilis = null, sonBaslatmaSn = null,
        };
        Servers.Add(entry); SaveServers();
        RefreshFolderLook();   // yeni sunucunun klasörü hemen kendi simgesini alsın
        HomeSel = Servers.Count - 1;
        w.Step = "bitti";
    }

    // ---------- Çizim (Render-Wizard) ----------
    private partial List<string> RenderWizard(int W, int H)
    {
        var rows = new List<string>();
        var wz = Wiz;
        if (wz?.Info == null) { while (rows.Count < H) rows.Add(""); return rows; }   // sihirbaz yoksa (olmamalı) boş ekran
        var inf = wz.Info;
        int saveCount = WizSaveCount(inf);
        rows.Add("");
        rows.Add("  " + Bo + c.brass + Lang.L("YENİ SUNUCU KURULUMU") + R + c.dim + "   " + inf.Name + " " + inf.Version + R);
        string[] labels = { Lang.L("İsim"), Lang.L("Dünya"), Lang.L("Onay"), Lang.L("Kurulum") };
        int curIdx = Ps.Eq(wz.Step, "isim") ? 0 : Ps.Eq(wz.Step, "dunya") ? 1 : Ps.Eq(wz.Step, "onay") ? 2 : 3;
        string sb = "  ";
        for (int i = 0; i < 4; i++)
        {
            if (i == 1 && saveCount == 0) continue;
            string col = (i < curIdx || Ps.Eq(wz.Step, "bitti")) ? c.green : i == curIdx ? c.brass + Bo : c.dark;
            sb += col + (i + 1) + " " + labels[i] + R + c.dark + (i < 3 ? "  ›  " : "") + R;
        }
        rows.Add(sb);
        rows.Add("");
        rows.Add(Rule(Lang.L("PAKET"), W));
        rows.Add("  " + c.soft + Lang.L("Minecraft ") + R + c.text + inf.Mc + R + c.dark + "  ·  " + R + c.soft + Lang.L("Yükleyici ") + R + c.text + WizLoaderName(inf.Loader) + " " + inf.LoaderVer + R
            + c.dark + "  ·  " + R + c.soft + Lang.L("Sunucu modu ") + R + c.text + inf.Mods + R + c.dim + Lang.L(" (+{0} sadece oyuncuda)", inf.ClientOnly) + R
            + c.dark + "  ·  " + R + c.soft + "Java " + R + c.text + inf.Java + R);
        rows.Add("");

        string step = wz.Step;
        if (Ps.Eq(step, "isim"))
        {
            rows.Add(Rule(Lang.L("SUNUCUNUN ADI"), W));
            rows.Add("");
            rows.Add("  " + c.soft + Lang.L("Listede görünecek isim:") + R);
            rows.Add("  " + c.brass + Bo + "❯ " + R + Bo + c.text + wz.Name + R + (Ps.Int(T() * 2) % 2 == 0 ? c.brass + "▌" : " ") + R);
            rows.Add("");
            rows.Add("  " + c.dim + Lang.L("Kurulacağı klasör: {0}", SafeFolderName(wz.Name)) + R);
            rows.Add("");
            rows.Add("  " + Key("Enter", Lang.L("devam")) + Key("Esc", Lang.L("iptal")));
        }
        else if (Ps.Eq(step, "dunya"))
        {
            rows.Add(Rule(Lang.L("DÜNYA"), W));
            rows.Add("");
            rows.Add("  " + c.soft + Lang.L("Pakette hazır bir dünya var. Nasıl başlayalım?") + R);
            rows.Add("");
            var opts = WizardWorldOptions();
            for (int i = 0; i < opts.Count; i++)
            {
                bool isS = i == wz.WorldSel;
                rows.Add("   " + (isS ? c.brass + Bo + "❯ " + c.text : "  " + c.soft) + opts[i].Label + R);
            }
            rows.Add("");
            rows.Add("  " + Key("↑↓", Lang.L("seç")) + Key("Enter", Lang.L("devam")) + Key("Esc", Lang.L("geri")));
        }
        else if (Ps.Eq(step, "onay"))
        {
            rows.Add(Rule(Lang.L("ÖZET"), W));
            rows.Add("");
            string worldTxt = saveCount > 0 ? WizOptAt(WizardWorldOptions(), wz.WorldSel).Label : Lang.L("Yeni dünya");
            rows.Add("  " + c.soft + Lang.L("İsim       ") + R + Bo + c.text + wz.Name + R);
            rows.Add("  " + c.soft + Lang.L("Klasör     ") + R + c.text + SafeFolderName(wz.Name) + R);
            rows.Add("  " + c.soft + Lang.L("Dünya      ") + R + c.text + worldTxt + R);
            rows.Add("  " + c.soft + Lang.L("İndirilecek") + R + c.text + Lang.L(" {0} mod", inf.Mods) + (string.IsNullOrEmpty(FindJava(inf.Java)) ? " + Java " + inf.Java : "") + " + " + WizLoaderName(inf.Loader) + R);
            rows.Add("");
            rows.Add("  " + c.dim + Lang.L("Kurarak Minecraft kullanım sözleşmesini (aka.ms/MinecraftEULA) kabul etmiş olursun.") + R);
            if (string.IsNullOrEmpty(FindJava(inf.Java))) rows.Add("  " + c.dim + Lang.L("Java {0} otomatik olarak SyHost klasörüne indirilecek.", inf.Java) + R);
            rows.Add("");
            rows.Add("  " + Pill("240;240;240", "18;18;20", "Enter") + c.text + Lang.L(" Kur   ") + R + Pill("50;50;56", "235;235;235", "Esc") + c.text + Lang.L(" Geri") + R);
        }
        else if (Ps.In(step, "kurulum", "bitti", "hata"))
        {
            var sy = wz.Sync;
            rows.Add(Rule(Lang.L("KURULUM"), W, c.dim + " " + FmtDur(Now() - wz.StartedAt) + " " + R));
            rows.Add("");
            int stIdx = -1;
            foreach (var st in sy?.Steps ?? new List<InstallStep>())
            {
                stIdx++;
                int s = st.S;   // arka plandaki kurulum değiştirebilir: bu karede bir kez oku
                string n = st.N ?? "";
                string mark = s switch { 2 => c.green + Bo + "✓", 1 => c.brass + Spin(), 3 => c.red + Bo + "x", _ => c.dark + "·" };
                string txt = s == 1 ? Shimmer(n, new[] { 229, 231, 235 }, new[] { 255, 70, 80 }) : s == 2 ? c.soft + n : s == 3 ? c.red + n : c.dark + n;
                rows.Add("   " + mark + R + "  " + txt + R);
                if (s == 1 && stIdx == 3) { int pct = sy.Pct; rows.Add("      " + BarP(pct, 30) + " " + c.brass + Bo + "%" + pct + R + c.dim + "  " + sy.Count + R); }
            }
            rows.Add("");
            if (Ps.Eq(step, "kurulum"))
            {
                rows.Add("   " + c.dim + sy?.Detail + R);
                rows.Add("");
                rows.Add("   " + c.brass + Pulse() + R + " " + Shimmer(Verb() + "…", new[] { 110, 110, 120 }, new[] { 255, 60, 70 }));
            }
            else if (Ps.Eq(step, "bitti"))
            {
                rows.Add("   " + Bo + c.green + Lang.L("{0} hazır!", wz.Name) + R);
                var failed = sy?.Failed;
                if (failed != null && failed.Count > 0) rows.Add("   " + c.yellow + Lang.L("Şu modlar indirilemedi: {0}", string.Join(", ", failed)) + R);
                rows.Add("");
                rows.Add("   " + Pill("240;240;240", "18;18;20", "Enter") + c.text + Lang.L(" Sunucuyu şimdi aç   ") + R + Pill("50;50;56", "235;235;235", "Esc") + c.text + Lang.L(" Ana menü") + R);
            }
            else
            {
                rows.Add("   " + Bo + c.red + Lang.L("Kurulum tamamlanamadı:") + R);
                foreach (string l in WordWrap(sy?.Error ?? "", W - 8)) rows.Add("   " + c.red + l + R);
                rows.Add("");
                rows.Add("   " + c.dim + Lang.L("Yarım kalan klasör: {0}", wz.Target) + R);
                rows.Add("   " + Pill("50;50;56", "235;235;235", "Enter") + c.text + Lang.L(" Ana menüye dön") + R);
            }
        }
        while (rows.Count < H) rows.Add("");
        return rows;
    }

    // ---------- Tuşlar (Handle-WizardKey) ----------
    private partial void HandleWizardKey(ConsoleKeyInfo k, bool ctrl)
    {
        var w = Wiz;
        if (w == null) return;
        if (Ps.Eq(w.Step, "isim"))
        {
            w.Name ??= "";
            switch (k.Key)
            {
                case ConsoleKey.Enter:
                    if (w.Name.Trim().Length > 0) { w.Name = w.Name.Trim(); w.Step = WizSaveCount(w.Info) > 0 ? "dunya" : "onay"; }
                    return;
                case ConsoleKey.Escape: Screen = "home"; ResetFrame(); return;
                case ConsoleKey.Backspace: if (w.Name.Length > 0) w.Name = w.Name.Substring(0, w.Name.Length - 1); return;
            }
            if (k.KeyChar >= 32 && w.Name.Length < 32) w.Name += k.KeyChar;
        }
        else if (Ps.Eq(w.Step, "dunya"))
        {
            int n = WizardWorldOptions().Count;
            switch (k.Key)
            {
                case ConsoleKey.UpArrow: w.WorldSel = (w.WorldSel + n - 1) % n; break;
                case ConsoleKey.DownArrow: w.WorldSel = (w.WorldSel + 1) % n; break;
                case ConsoleKey.Enter: w.Step = "onay"; break;
                case ConsoleKey.Escape: w.Step = "isim"; break;
            }
        }
        else if (Ps.Eq(w.Step, "onay"))
        {
            switch (k.Key)
            {
                case ConsoleKey.Enter: BeginInstall(); break;
                case ConsoleKey.Escape: w.Step = WizSaveCount(w.Info) > 0 ? "dunya" : "isim"; break;
            }
        }
        else if (Ps.Eq(w.Step, "bitti"))
        {
            switch (k.Key)
            {
                case ConsoleKey.Enter: if (Servers.Count > 0) { var srv = Servers[Servers.Count - 1]; Wiz = null; EnterServer(srv); } break;
                case ConsoleKey.Escape: Wiz = null; Screen = "home"; ResetFrame(); break;
            }
        }
        else if (Ps.Eq(w.Step, "hata"))
        {
            if (k.Key == ConsoleKey.Enter || k.Key == ConsoleKey.Escape) { Wiz = null; Screen = "home"; ResetFrame(); }
        }
    }
}
