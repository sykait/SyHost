// =====================================================================
//  SyHost - arkadaş bağlantısı (playit.gg) kurulumu
//  Setup.ps1'deki adımların uygulama içindeki karşılığı:
//    soru → (indir) → bağla (tarayıcıda onay) → tünel adresleri → hazır
//  playit hiçbir yere kurulmaz: tek exe'lik program Data\tools\playit içine iner
//  ve yalnızca SyHost açıkken çalışır. Eski sürümün Program Files'taki playit'i
//  varsa o da kullanılabilir.
// =====================================================================
using System.Diagnostics;
using System.Text.RegularExpressions;

namespace SyHost;

sealed partial class App
{
    static readonly Regex AddrRx = new(@"^[\w\.-]+\.\w+(:\d+)?$", RegexOptions.Compiled);
    Process PlayitClaimProc;

    // playit 2.x iki programdır: playitd.exe tünelleri çalıştırır (StartPlayit bunu açar),
    // playit.exe yalnızca komut satırı aracıdır (hesap bağlama: claim generate/url/exchange).
    // İkisi de Data\tools\playit içine iner; eski sürümün Program Files'taki kopyası da kullanılabilir.
    string PlayitToolDir => Path.Combine(Data, "tools", "playit");
    const string PlayitLegacyBin = @"C:\Program Files\playit_gg\bin";

    /// <summary>Hesap bağlama komutlarını çalıştıracak playit aracı (yoksa null).</summary>
    string PlayitCliExe()
    {
        string own = Path.Combine(PlayitToolDir, "playit.exe");
        if (File.Exists(own)) return own;
        string legacy = Path.Combine(PlayitLegacyBin, "playit.exe");
        return File.Exists(legacy) ? legacy : null;
    }

    /// <summary>Tünelleri çalıştıracak program var mı?</summary>
    bool PlayitDaemonAvailable() => File.Exists(Path.Combine(PlayitToolDir, "playitd.exe")) || File.Exists(Path.Combine(PlayitLegacyBin, "playitd.exe"));

    /// <summary>Bağlantı zaten kurulu mu (anahtar, adres ve program var)?</summary>
    bool PlayitReady() => TestPlayitReady ?? Cfg.playitKullan && File.Exists(PlayitSecret) && !string.IsNullOrEmpty(Cfg.arkadasAdresi) && PlayitDaemonAvailable();

    // İndirilen playit dosyası için akıl sınırı (bugün ~8 MB)
    const long PlayitMaxBytes = 64L * 1024 * 1024;

    /// <summary>
    /// playit'in iki programını indir (GitHub'daki son sürüm, Windows x64). Yalnızca imzalı sürüm kabul edilir ve
    /// dosya yerine konmadan (hiç çalıştırılmadan) önce doğrulanır: GitHub'ın verdiği SHA-256 tutmalı ve Windows
    /// imzayı geçerli bulmalı. Tutmazsa dosya silinir, adım "kurulamadı" ile atlanır. (Terminal: FirstRunJob.ps1)
    /// </summary>
    void PlayitDownload()
    {
        Fr.JobText = Lang.L("playit indiriliyor...");
        string fail = Lang.L("playit kurulamadı, bu adım atlanıyor.");
        using var http = new HttpClient();
        http.DefaultRequestHeaders.UserAgent.ParseAdd("SyHost/1.0 (+https://github.com/sykait/SyHost)");
        http.Timeout = TimeSpan.FromMinutes(5);
        string json = http.GetStringAsync("https://api.github.com/repos/playit-cloud/playit-agent/releases/latest").GetAwaiter().GetResult();
        using var doc = System.Text.Json.JsonDocument.Parse(json);
        var assets = new Dictionary<string, (string Url, string Digest)>(StringComparer.OrdinalIgnoreCase);
        foreach (var a in doc.RootElement.GetProperty("assets").EnumerateArray())
        {
            string digest = a.TryGetProperty("digest", out var d) && d.ValueKind == System.Text.Json.JsonValueKind.String ? d.GetString() : null;
            assets[a.GetProperty("name").GetString() ?? ""] = (a.GetProperty("browser_download_url").GetString(), digest);
        }
        Directory.CreateDirectory(PlayitToolDir);
        foreach (var (asset, target) in new[] { ("playitd-windows-x86_64-signed.exe", "playitd.exe"), ("playit-windows-x86_64-signed.exe", "playit.exe") })
        {
            if (!assets.TryGetValue(asset, out var info) || !Uri.TryCreate(info.Url, UriKind.Absolute, out Uri url) || url.Scheme != Uri.UriSchemeHttps) throw new Exception(fail);
            string dst = Path.Combine(PlayitToolDir, target), tmp = dst + ".indiriliyor";
            try
            {
                using (var s = http.GetStreamAsync(url).GetAwaiter().GetResult())
                using (var f = File.Create(tmp))
                {
                    var buf = new byte[81920];
                    long total = 0;
                    for (int n; (n = s.Read(buf, 0, buf.Length)) > 0;)
                    {
                        total += n;
                        if (total > PlayitMaxBytes) throw new Exception(fail);
                        f.Write(buf, 0, n);
                    }
                }
                if (!PlayitFileOk(tmp, info.Digest)) throw new Exception(fail);
                File.Move(tmp, dst, true);
            }
            catch
            {
                try { File.Delete(tmp); } catch { }
                throw;
            }
        }
    }

    /// <summary>İndirilen dosya GitHub'ın SHA-256'sıyla tutuyor mu (verdiyse) ve imzası geçerli mi?</summary>
    static bool PlayitFileOk(string file, string digest)
    {
        if (!string.IsNullOrEmpty(digest))
        {
            if (!digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase)) return false;
            string hex;
            using (var fs = File.OpenRead(file)) hex = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(fs));
            if (!hex.Equals(digest.Substring(7), StringComparison.OrdinalIgnoreCase)) return false;
        }
        return Trust.IsSigned(file);
    }

    /// <summary>Hesap bağlama sayfası yalnızca playit.gg'nin kendi https adresiyse tarayıcıda açılır.</summary>
    static bool IsPlayitUrl(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out Uri u) && u.Scheme == Uri.UriSchemeHttps &&
        (u.Host.Equals("playit.gg", StringComparison.OrdinalIgnoreCase) || u.Host.EndsWith(".playit.gg", StringComparison.OrdinalIgnoreCase));

    /// <summary>playit komutunu çalıştır, bütün çıktıyı döndür. Esc (PlayitCancel) hangi komut çalışırken basılırsa basılsın onu kapatır.</summary>
    string PlayitRun(string args, int timeoutMs)
    {
        if (Fr.Cancel) throw new Exception(Lang.L("playit bağlantısı tamamlanmadı. Tekrar deneyebilirsin."));
        var psi = new ProcessStartInfo(PlayitCliExe(), args)
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            WorkingDirectory = Data,
        };
        using var p = Process.Start(psi);
        PlayitClaimProc = p;
        try { JobGuard.Add(p); } catch { }   // SyHost kapanırsa onay bekleyen playit yetim kalmasın
        if (Fr.Cancel) { try { p.Kill(); } catch { } }   // iptal tam başlarken geldiyse
        var output = new System.Text.StringBuilder();
        p.OutputDataReceived += (s, e) => { if (e.Data != null) lock (output) output.AppendLine(e.Data); };
        p.ErrorDataReceived += (s, e) => { if (e.Data != null) lock (output) output.AppendLine(e.Data); };
        p.BeginOutputReadLine(); p.BeginErrorReadLine();
        if (!p.WaitForExit(timeoutMs)) { try { p.Kill(); } catch { } }
        p.WaitForExit();
        PlayitClaimProc = null;
        string all; lock (output) all = output.ToString();
        return all;
    }

    /// <summary>Tarayıcıda hesap bağlama: kod üret, sayfayı aç, onayı bekle, anahtarı yaz.</summary>
    void PlayitClaim()
    {
        string code = LastLine(PlayitRun("claim generate", 30000));
        if (string.IsNullOrWhiteSpace(code)) throw new Exception(Lang.L("playit bağlantısı tamamlanmadı. Tekrar deneyebilirsin."));
        Fr.Code = code;
        string url = LastLine(PlayitRun("claim url " + code + " --name SyHost", 30000));
        if (IsPlayitUrl(url) && !TestMode && !Fr.Cancel) { try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { } }
        Fr.JobText = Lang.L("Tarayıcıda onaylamanı bekliyorum (en fazla 10 dakika)...");
        string outp = PlayitRun("claim exchange " + code + " --wait 600", 620000);
        var m = Regex.Match(outp, "([0-9a-f]{64})");
        if (!m.Success) throw new Exception(Lang.L("playit bağlantısı tamamlanmadı. Tekrar deneyebilirsin."));
        File.WriteAllText(PlayitSecret, "secret_key = \"" + m.Groups[1].Value + "\"\n", Json.Utf8NoBom);
    }

    static string LastLine(string s)
    {
        var lines = (s ?? "").Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return lines.Length == 0 ? "" : lines[^1];
    }

    void PlayitCancel()
    {
        Fr.Cancel = true;
        try { PlayitClaimProc?.Kill(); } catch { }
        Fr.Phase = "soru"; Fr.Note = Lang.L("playit bağlantısı tamamlanmadı. Tekrar deneyebilirsin."); Fr.NoteCol = c.yellow;
    }

    /// <summary>Arka plandaki playit işi bitince sonraki aşamaya geç.</summary>
    void PlayitJobDone()
    {
        if (Fr.JobError != null)
        {
            Fr.Phase = "soru"; Fr.Note = Fr.JobError; Fr.NoteCol = c.red;
            return;
        }
        if (Fr.Phase == "indir") { Fr.Phase = "bagla"; FrRun(PlayitClaim); return; }
        if (Fr.Phase == "bagla")
        {
            Fr.Phase = "adres"; Fr.Field = 0; Fr.McAddr = Cfg.arkadasAdresi ?? ""; Fr.VoiceAddr = Cfg.sesAdresi ?? "";
            if (!TestMode) { try { Process.Start(new ProcessStartInfo("https://playit.gg/account/tunnels") { UseShellExecute = true }); } catch { } }
        }
    }

    void PlayitKey(ConsoleKeyInfo k)
    {
        switch (Fr.Phase)
        {
            case "soru":
                if (k.Key == ConsoleKey.UpArrow || k.Key == ConsoleKey.DownArrow) { Fr.Sel = 1 - Fr.Sel; return; }
                if (k.Key == ConsoleKey.Escape) { FrBack(); return; }
                if (k.Key != ConsoleKey.Enter) return;
                Fr.Note = null;
                if (PlayitReady())
                {
                    if (Fr.Sel == 0) { FrNext(); return; }
                    Fr.Phase = "bagla"; FrRun(PlayitClaim); return;   // yeniden bağla
                }
                if (Fr.Sel == 1)
                {
                    // Şimdilik hayır: sunucuya bu bilgisayardan ve aynı evdeki ağdan girilebilir
                    Cfg.playitKullan = false; SaveConfig(); HasFriendAddr = false; FriendAddr = Lang.L("henüz yok");
                    FrNext(); return;
                }
                if (PlayitCliExe() == null || !PlayitDaemonAvailable()) { Fr.Phase = "indir"; FrRun(PlayitDownload); }
                else { Fr.Phase = "bagla"; FrRun(PlayitClaim); }
                return;

            case "adres":
            {
                ref string val = ref (Fr.Field == 0 ? ref Fr.McAddr : ref Fr.VoiceAddr);
                if (k.Key == ConsoleKey.Backspace) { if (val.Length > 0) val = val.Substring(0, val.Length - 1); return; }
                if (k.Key == ConsoleKey.Escape) { if (Fr.Field == 1) Fr.Field = 0; else { Fr.Phase = "soru"; } return; }
                if (k.Key == ConsoleKey.Enter)
                {
                    val = val.Trim();
                    if (Fr.Field == 0)
                    {
                        if (!AddrRx.IsMatch(Fr.McAddr)) { Fr.Note = Lang.L("Adres anlaşılamadı. Örnek: bir-sey.joinmc.link"); Fr.NoteCol = c.yellow; return; }
                        Fr.Note = null; Fr.Field = 1; return;
                    }
                    if (Fr.VoiceAddr.Length > 0 && !AddrRx.IsMatch(Fr.VoiceAddr)) { Fr.Note = Lang.L("Sesli sohbet adresi anlaşılamadı, boş bırakıldı."); Fr.NoteCol = c.yellow; Fr.VoiceAddr = ""; }
                    Cfg.arkadasAdresi = Fr.McAddr; Cfg.sesAdresi = Fr.VoiceAddr; Cfg.playitKullan = true;
                    SaveConfig();
                    HasFriendAddr = true; FriendAddr = Fr.McAddr;
                    StopPlayit(); PlayitResetBudget(); StartPlayit();
                    Fr.Phase = "hazir";
                    return;
                }
                if (k.KeyChar >= 32 && val.Length < 120) val += k.KeyChar;
                return;
            }

            case "hazir":
                if (k.Key == ConsoleKey.Enter) FrNext();
                return;
        }
    }

    string RenderPlayitStep(List<string> rows, int W)
    {
        string In(string t) => "  " + c.soft + t + R;
        switch (Fr.Phase)
        {
            case "indir":
            case "bagla":
                if (Fr.Phase == "bagla")
                {
                    rows.Add("  " + c.text + Bo + Lang.L("playit hesabına bağlanma") + R);
                    rows.Add(In(Lang.L("1. Birazdan tarayıcıda playit.gg açılacak.")));
                    rows.Add(In(Lang.L("2. Hesabın yoksa bedava oluştur (Create Account), varsa giriş yap.")));
                    rows.Add(In(Lang.L("3. Çıkan sayfada bu bilgisayarı onayla (Continue / Add Agent).")));
                    rows.Add("");
                }
                rows.Add("  " + c.brass + Spin() + R + "  " + Shimmer(string.IsNullOrEmpty(Fr.JobText) ? Lang.L("playit indiriliyor...") : Fr.JobText, new[] { 229, 231, 235 }, new[] { 255, 70, 80 }));
                return Fr.Phase == "bagla" ? Key("Esc", Lang.L("iptal")) : "";

            case "adres":
            {
                rows.Add("  " + c.text + Bo + Lang.L("Arkadaşlarının bağlanacağı adres") + R);
                rows.Add(In(Lang.L("1. Birazdan playit.gg tünel sayfası açılacak.")));
                rows.Add(In(Lang.L("2. \"Add Tunnel\" > \"Minecraft Java\" seç > Continue > bölge \"Automatic (Free)\" > Create Tunnel.")));
                rows.Add(In(Lang.L("3. Sesli sohbet modu kullanıyorsan bir tane de \"MC: Simple Voice Chat\" tüneli oluştur.")));
                rows.Add(In(Lang.L("4. Tünellerin adreslerini aşağıya yapıştır (sağ tık = yapıştır).")));
                rows.Add("");
                string caret = Ps.Int(T() * 2) % 2 == 0 ? c.brass + "▌" : " ";
                (string Label, string Hint, string Val)[] f =
                {
                    (Lang.L("Minecraft adresi"), Lang.L("(ör. bir-sey.joinmc.link veya xxx.tun.ply.gg)"), Fr.McAddr),
                    (Lang.L("Sesli sohbet adresi"), Lang.L("(yoksa boş bırakıp Enter)"), Fr.VoiceAddr),
                };
                for (int i = 0; i < 2; i++)
                {
                    bool s = i == Fr.Field;
                    rows.Add("  " + (s ? c.text + Bo : c.soft) + f[i].Label + R + "  " + c.dim + f[i].Hint + R);
                    rows.Add("  " + (s ? c.brass + Bo + "❯ " : c.dark + "  ") + R + Bo + c.text + f[i].Val + R + (s ? caret : "") + R);
                }
                if (Fr.Note != null) { rows.Add(""); rows.Add("  " + Fr.NoteCol + Fr.Note + R); }
                return Key("Enter", Lang.L("devam")) + Key("Esc", Lang.L("geri"));
            }

            case "hazir":
                rows.Add(Check(Lang.L("Arkadaş adresi kaydedildi: {0}", Cfg.arkadasAdresi)));
                if (!string.IsNullOrEmpty(Cfg.sesAdresi)) rows.Add(Check(Lang.L("Sesli sohbet:  {0}  (otomatik)", Cfg.sesAdresi)));
                rows.Add("");
                rows.Add("  " + c.dim + Lang.L("SyHost playit'i sadece kendisi açıkken çalıştırır, bilgisayarın açılışında başlamaz.") + R);
                return Key("Enter", Lang.L("devam"));

            default: // soru
            {
                string[] opts;
                if (PlayitReady())
                {
                    rows.Add(Check(Lang.L("Arkadaş bağlantısı hazır: {0}", Cfg.arkadasAdresi)));
                    rows.Add("");
                    opts = new[] { Lang.L("Devam"), Lang.L("Yeniden bağla") };
                }
                else
                {
                    rows.Add(In(Lang.L("Çoğu ev internetinde (CGNAT) arkadaşların doğrudan bağlanamaz.")));
                    rows.Add(In(Lang.L("playit.gg bunu bedava çözer ve sana sabit bir adres verir (ör. bir-sey.joinmc.link).")));
                    rows.Add(In(Lang.L("SyHost playit'i sadece kendisi açıkken çalıştırır, bilgisayarın açılışında başlamaz.")));
                    rows.Add("");
                    rows.Add("  " + c.text + Bo + Lang.L("Arkadaşların internetten bağlanabilsin mi?") + R);
                    opts = new[] { Lang.L("Evet, bağlantıyı kur"), Lang.L("Şimdilik hayır") };
                }
                for (int i = 0; i < opts.Length; i++)
                {
                    bool s = i == Fr.Sel;
                    string line = "   " + (s ? c.brass + Bo + "❯ " + c.text : "  " + c.soft) + opts[i] + R;
                    rows.Add(s ? SelLine(line, W) : line);
                }
                if (Fr.Note != null) { rows.Add(""); foreach (string l in WordWrap(Fr.Note, W - 8)) rows.Add("  " + Fr.NoteCol + l + R); }
                return Key("↑↓", Lang.L("seç")) + Key("Enter", Lang.L("devam")) + Key("Esc", Lang.L("geri"));
            }
        }
    }
}
