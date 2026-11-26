// =====================================================================
//  SyHost - sunucu kurulumu (arka planda çalışır)
//  legacy/src/SyHost.ps1: $InstallScript (634-793) birebir: aynı 7 adım,
//  aynı ekran metinleri, aynı dosyalar. Ekranda görünmeyen iyileştirmeler:
//    - modlar 6'şar 6'şar paralel iner, SHA-1 (varsa SHA-512) ile doğrulanır
//    - her indirme önce geçici dosyaya yazılır, doğrulanınca yerine taşınır
//    - yükleyici dosyaları ve Fabric bilgisi de 3 kez denenir
//    - tek bir HttpClient, SyHost'u tanıtan User-Agent ile
//  Java yoksa winget yerine Java.Download (Core/Java.cs) kullanılır.
// =====================================================================
using System.Buffers;
using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SyHost;

static partial class Lang
{
    static partial void AddInstall()
    {
        // Java artık SyHost'un kendi klasörüne iniyor; Windows izin sormuyor
        Tx("Java {0} indiriliyor...", "Downloading Java {0}...", "Java {0} をダウンロード中...");
    }
}

static class Installer
{
    const int Tries = 3;                 // PowerShell'deki gibi her iş 3 kez denenir
    const int ModsAtOnce = 6;            // aynı anda inen dosya sayısı
    const long MaxFile = 4L << 30;       // tek dosya için akıl sınırı (bitmeyen indirmeye karşı)
    static readonly TimeSpan HeaderTimeout = TimeSpan.FromSeconds(100);   // .NET Framework'ün (PowerShell) varsayılanı
    static readonly TimeSpan StallTimeout = TimeSpan.FromSeconds(60);     // bu kadar süre hiç veri gelmezse bağlantı kopmuş sayılır
    static readonly TimeSpan InstallerSilence = TimeSpan.FromMinutes(15); // yükleyici bu kadar süre hiçbir şey yazmazsa takılmış sayılır

    static readonly Regex SkipFilesRx = new("^(resourcepacks|shaderpacks)/", RegexOptions.IgnoreCase);
    static readonly Regex SkipOverridesRx = new("^(resourcepacks|shaderpacks|saves)/", RegexOptions.IgnoreCase);
    static readonly object MoveGate = new();

    /// <summary>Bütün indirmelerin kullandığı tek HttpClient.</summary>
    internal static readonly HttpClient Http = CreateHttp();

    static HttpClient CreateHttp()
    {
        var handler = new SocketsHttpHandler
        {
            AllowAutoRedirect = true,
            MaxAutomaticRedirections = 10,
            AutomaticDecompression = DecompressionMethods.None,   // dosyalar baytı baytına insin (karma doğrulaması)
            ConnectTimeout = TimeSpan.FromSeconds(30),
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
        };
        var http = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };   // süreleri istek başına biz tutarız
        http.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "SyHost/1.0 (+https://github.com/sykait/SyHost)");
        return http;
    }

    /// <summary>$InstallScript (SyHost.ps1 634-793): sunucuyu kurar. Arka plan iş parçacığında çağrılır,
    /// ilerlemeyi sync'e yazar, bitince sync.Done = true yapar. Hata olursa sync.Error doldurulur.</summary>
    public static void Run(InstallSync sync, PackInfo info, string target, string worldName, string voiceHost, int maxPlayers, string motd, string dataDir)
    {
        int cur = 0;
        void Step(int i, int st) { if (i >= 0 && i < sync.Steps.Count) sync.Steps[i].S = st; if (st == 1) cur = i; }
        void Det(string t) => sync.Detail = t;
        ZipArchive zip = null;
        try
        {
            zip = ZipFile.OpenRead(info.Path);
            List<ModFile> files;
            using (var index = ReadIndex(zip)) files = ServerFiles(index.RootElement);
            string mc = info.Mc, lv = info.LoaderVer;
            string full = Path.GetFullPath(target);

            // 0 klasör
            cur = 0; Step(0, 1);
            Directory.CreateDirectory(target);
            Directory.CreateDirectory(Path.Combine(target, "mods"));
            Step(0, 2);

            // 1 Java
            cur = 1; Step(1, 1);
            int jm = Java.GetMajor(mc);
            string java = Java.Find(jm, dataDir);
            if (java == null)
            {
                // PowerShell burada winget ile bilgisayara kurardı; artık SyHost'un kendi klasörüne iner
                Exception why = null;
                try { Java.Download(jm, dataDir, Det); } catch (Exception ex) { why = ex; }
                java = Java.Find(jm, dataDir);
                if (java == null)
                {
                    Note(target, $"Java {jm} could not be prepared: {Chain(why)}");
                    throw new InstallError(Lang.L("Java {0} kurulamadı.", jm), why);
                }
            }
            Det(Lang.L("Java {0} hazır", jm));
            Step(1, 2);

            // 2 Mod yükleyici
            cur = 2; Step(2, 1);
            string launch = InstallLoader(info.Loader, mc, lv, java, target, Det);
            Step(2, 2);

            // 3 Modlar
            cur = 3; Step(3, 1);
            sync.Failed = DownloadAll(sync, files, target, full);
            sync.Pct = 100;
            Step(3, 2);

            // 4 Ayar dosyaları
            cur = 4; Step(4, 1);
            // Önce overrides, sonra server-overrides: Modrinth kuralına göre sunucuya özel olan kazanır
            foreach (string pre in new[] { "overrides/", "server-overrides/" })
            {
                foreach (var en in zip.Entries)
                {
                    string fn = en.FullName;
                    if (!fn.StartsWith(pre, StringComparison.Ordinal) || en.Name.Length == 0) continue;
                    string rel = fn.Substring(pre.Length);
                    if (SkipOverridesRx.IsMatch(rel)) continue;
                    string dst = Inside(target, rel, full);
                    if (dst == null) continue;
                    Directory.CreateDirectory(Path.GetDirectoryName(dst));
                    en.ExtractToFile(dst, true);
                }
            }
            Step(4, 2);

            // 5 Dünya
            cur = 5; Step(5, 1);
            if (!string.IsNullOrEmpty(worldName))
            {
                Det(Lang.L("Paketteki dünya kopyalanıyor"));
                string pre = "overrides/saves/" + worldName + "/";
                string worldDir = Path.Combine(target, "world");
                foreach (var en in zip.Entries)
                {
                    if (!en.FullName.StartsWith(pre, StringComparison.Ordinal) || en.Name.Length == 0) continue;
                    string rel = en.FullName.Substring(pre.Length);
                    if (Ps.Eq(rel, "session.lock")) continue;
                    string dst = Inside(worldDir, rel, full);
                    if (dst == null) continue;
                    Directory.CreateDirectory(Path.GetDirectoryName(dst));
                    en.ExtractToFile(dst, true);
                }
            }
            else Det(Lang.L("İlk açılışta yeni bir dünya oluşturulacak"));
            Step(5, 2);

            // 6 Son ayarlar
            cur = 6; Step(6, 1);
            WriteProperties(Path.Combine(target, "server.properties"), new (string, string)[]
            {
                ("motd", motd), ("level-name", "world"), ("max-players", Ps.S(maxPlayers)), ("online-mode", "true"), ("difficulty", "normal"),
                ("spawn-protection", "0"), ("view-distance", "10"), ("simulation-distance", "8"), ("allow-flight", "true"),
                ("server-port", "25565"), ("enable-command-block", "true"),
            });
            File.WriteAllText(Path.Combine(target, "eula.txt"), "eula=true\r\n", Encoding.ASCII);   // Set-Content -Encoding ASCII
            string mods = Path.Combine(target, "mods");
            if (!string.IsNullOrEmpty(voiceHost) && Directory.Exists(mods) && Directory.EnumerateFileSystemEntries(mods, "*voicechat*", Visible).Any())
            {
                string vd = Path.Combine(target, "config", "voicechat");
                Directory.CreateDirectory(vd);
                string vp = Path.Combine(vd, "voicechat-server.properties");
                if (!(File.Exists(vp) || Directory.Exists(vp)))
                    File.WriteAllLines(vp, new[] { "port=24454", "bind_address=", "voice_host=" + voiceHost }, Json.Utf8NoBom);
                else
                {
                    string vt = File.ReadAllText(vp);
                    // -match büyük-küçük harfe bakmaz, [regex]::Replace bakar: PowerShell'deki gibi
                    if (Regex.IsMatch(vt, "(?m)^voice_host=", RegexOptions.IgnoreCase)) vt = Regex.Replace(vt, "(?m)^voice_host=.*$", "voice_host=" + voiceHost);
                    else vt = vt.TrimEnd() + "\nvoice_host=" + voiceHost + "\n";
                    File.WriteAllText(vp, vt, Json.Utf8NoBom);
                }
            }
            Step(6, 2);
            zip.Dispose(); zip = null;
            sync.Result = new InstallResult { mc = mc, loader = info.Loader, loaderSurum = lv, java = jm, baslat = launch };
        }
        catch (Exception ex)
        {
            sync.Error = ex.Message;
            try { sync.Steps[cur].S = 3; } catch { }
        }
        finally
        {
            try { zip?.Dispose(); } catch { }
            sync.Done = true;
        }
    }

    /// <summary>Kurulumda gösterilen hata (metni ekrana olduğu gibi yazılır).</summary>
    sealed class InstallError : Exception
    {
        public InstallError(string message, Exception inner = null) : base(message, inner) { }
    }

    // ---------- Paket ----------
    sealed class ModFile
    {
        public int Index;
        public string Path, Leaf, Sha1, Sha512;
        public long Size;
        public readonly List<string> Urls = new();
    }

    static JsonDocument ReadIndex(ZipArchive zip)
    {
        var ie = zip.GetEntry("modrinth.index.json") ?? throw new InstallError(Lang.L("Bu dosya bir Modrinth paketi (.mrpack) değil."));
        string json;
        using (var sr = new StreamReader(ie.Open())) json = sr.ReadToEnd();
        return JsonDocument.Parse(json, new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip });
    }

    /// <summary>Sunucuya inecek dosyalar: env.server 'unsupported' değil, resourcepacks/shaderpacks değil.</summary>
    static List<ModFile> ServerFiles(JsonElement index)
    {
        var list = new List<ModFile>();
        if (!Prop(index, "files", out var files) || files.ValueKind != JsonValueKind.Array) return list;
        foreach (var f in files.EnumerateArray())
        {
            if (f.ValueKind != JsonValueKind.Object) continue;
            string server = Prop(f, "env", out var env) && env.ValueKind == JsonValueKind.Object && Prop(env, "server", out var sv) ? Text(sv) : null;
            if (Ps.Eq(server, "unsupported")) continue;
            string path = Prop(f, "path", out var pv) ? Text(pv) : null;
            if (SkipFilesRx.IsMatch(path ?? "")) continue;
            var m = new ModFile { Index = list.Count, Path = path, Leaf = Leaf(path) };
            if (Prop(f, "downloads", out var dl))
            {
                if (dl.ValueKind == JsonValueKind.Array) { foreach (var u in dl.EnumerateArray()) AddUrl(m, Text(u)); }
                else AddUrl(m, Text(dl));
            }
            if (Prop(f, "hashes", out var hs) && hs.ValueKind == JsonValueKind.Object)
            {
                if (Prop(hs, "sha1", out var h1)) m.Sha1 = NullIfEmpty(Text(h1));
                if (Prop(hs, "sha512", out var h5)) m.Sha512 = NullIfEmpty(Text(h5));
            }
            if (Prop(f, "fileSize", out var sz) && sz.ValueKind == JsonValueKind.Number && sz.TryGetInt64(out long n)) m.Size = n;
            list.Add(m);
        }
        return list;
    }

    static void AddUrl(ModFile m, string u) { if (!string.IsNullOrWhiteSpace(u)) m.Urls.Add(u); }
    static string NullIfEmpty(string s) => string.IsNullOrEmpty(s) ? null : s;

    // PowerShell'de $obj.ad büyük-küçük harfe bakmaz
    static bool Prop(JsonElement e, string name, out JsonElement v)
    {
        v = default;
        if (e.ValueKind != JsonValueKind.Object) return false;
        if (e.TryGetProperty(name, out v)) return true;
        foreach (var p in e.EnumerateObject())
            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) { v = p.Value; return true; }
        return false;
    }

    static string Text(JsonElement v) => v.ValueKind switch
    {
        JsonValueKind.String => v.GetString(),
        JsonValueKind.Null or JsonValueKind.Undefined => null,
        _ => v.GetRawText(),
    };

    /// <summary>Split-Path -Leaf</summary>
    static string Leaf(string p)
    {
        if (string.IsNullOrEmpty(p)) return "";
        int i = p.LastIndexOfAny(new[] { '/', '\\' });
        return i >= 0 ? p.Substring(i + 1) : p;
    }

    /// <summary>
    /// [IO.Path]::GetFullPath((Join-Path $base ($rel -replace '/', '\'))) ve kök klasör denetimi.
    /// Kökün dışına çıkan (../), sürücü ya da akış adı içeren (C:, dosya:akış) yollar için null.
    /// PowerShell yalnızca "kökle başlıyor mu" diye bakar; burada "Sunucu2" gibi kardeş klasör de geçmez.
    /// </summary>
    static string Inside(string baseDir, string rel, string rootFull)
    {
        if (string.IsNullOrEmpty(rel)) return null;
        string r = rel.Replace('/', '\\');
        if (r.IndexOf(':') >= 0 || r.IndexOfAny(BadPathChars) >= 0) return null;
        string p;
        try { p = Path.GetFullPath(baseDir.TrimEnd('\\') + "\\" + r.TrimStart('\\')); }
        catch { return null; }
        string root = rootFull.TrimEnd('\\') + "\\";
        return p.Length > root.Length && p.StartsWith(root, StringComparison.OrdinalIgnoreCase) ? p : null;
    }

    static readonly char[] BadPathChars = BuildBadPathChars();
    static char[] BuildBadPathChars()
    {
        var l = new List<char> { '<', '>', '"', '|', '?', '*' };
        for (char ch = '\0'; ch < ' '; ch++) l.Add(ch);
        return l.ToArray();
    }

    // Get-ChildItem -Filter gibi: gizli dosyaları saymaz
    static readonly EnumerationOptions Visible = new()
    {
        AttributesToSkip = FileAttributes.Hidden,
        MatchCasing = MatchCasing.CaseInsensitive,
        MatchType = MatchType.Win32,
        IgnoreInaccessible = true,
    };

    // ---------- 2: mod yükleyici ----------
    static string InstallLoader(string loader, string mc, string lv, string java, string target, Action<string> det)
    {
        if (Ps.Eq(loader, "neoforge"))
        {
            det(Lang.L("{0} {1} indiriliyor", "NeoForge", lv));
            string inst = Path.Combine(target, "neoforge-installer.jar");
            DownloadFile($"https://maven.neoforged.net/releases/net/neoforged/neoforge/{lv}/neoforge-{lv}-installer.jar", inst);
            det(Lang.L("{0} {1} kuruluyor (biraz sürebilir)", "NeoForge", lv));
            if (!RunInstaller(java, inst, "--install-server", target)) throw new InstallError(Lang.L("{0} kurulamadı (kurulum.log dosyasına bak).", "NeoForge"));
            TryDelete(inst); TryDelete(Path.Combine(target, "neoforge-installer.jar.log"));
            return $"@libraries/net/neoforged/neoforge/{lv}/win_args.txt nogui";
        }
        if (Ps.Eq(loader, "forge"))
        {
            string fv = mc + "-" + lv;
            det(Lang.L("{0} {1} indiriliyor", "Forge", fv));
            string inst = Path.Combine(target, "forge-installer.jar");
            DownloadFile($"https://maven.minecraftforge.net/net/minecraftforge/forge/{fv}/forge-{fv}-installer.jar", inst);
            det(Lang.L("{0} {1} kuruluyor (biraz sürebilir)", "Forge", fv));
            if (!RunInstaller(java, inst, "--installServer", target)) throw new InstallError(Lang.L("{0} kurulamadı (kurulum.log dosyasına bak).", "Forge"));
            TryDelete(inst); TryDelete(Path.Combine(target, "forge-installer.jar.log"));
            string args = Path.Combine(target, "libraries", "net", "minecraftforge", "forge", fv, "win_args.txt");
            if (File.Exists(args) || Directory.Exists(args)) return $"@libraries/net/minecraftforge/forge/{fv}/win_args.txt nogui";
            // Eski Forge (1.16 ve öncesi): forge-*.jar ile başlar
            string jar = null;
            foreach (string f in Directory.EnumerateFileSystemEntries(target, "forge-*.jar", Visible))
            {
                string name = Path.GetFileName(f);
                if (!Regex.IsMatch(name, "installer", RegexOptions.IgnoreCase)) { jar = name; break; }
            }
            if (jar == null) throw new InstallError(Lang.L("Forge başlatma dosyası bulunamadı."));
            return $"-jar {jar} nogui";
        }
        if (Ps.Eq(loader, "fabric"))
        {
            det(Lang.L("{0} {1} indiriliyor", "Fabric", lv));
            string instVer = FabricInstallerVersion();
            DownloadFile($"https://meta.fabricmc.net/v2/versions/loader/{mc}/{lv}/{instVer}/server/jar", Path.Combine(target, "fabric-server-launch.jar"));
            return "-jar fabric-server-launch.jar nogui";
        }
        throw new InstallError(Lang.L("{0} henüz desteklenmiyor (NeoForge, Forge ve Fabric destekleniyor).", loader));
    }

    /// <summary>
    /// (Invoke-RestMethod .../v2/versions/installer | Where-Object { $_.stable } | Select-Object -First 1).version
    /// Not: Windows PowerShell 5.1 JSON dizisini tek nesne olarak verdiği için oradaki satır bütün sürümleri
    /// boşlukla birleştirir ve sunucu 400 döner. Burada amaçlanan yapılır: ilk kararlı sürüm.
    /// </summary>
    static string FabricInstallerVersion()
    {
        using var doc = JsonDocument.Parse(GetText("https://meta.fabricmc.net/v2/versions/installer"));
        string first = null;
        if (doc.RootElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var v in doc.RootElement.EnumerateArray())
            {
                string ver = Prop(v, "version", out var vv) ? Text(vv) : null;
                if (string.IsNullOrEmpty(ver)) continue;
                first ??= ver;
                if (Prop(v, "stable", out var st) && st.ValueKind == JsonValueKind.True) return ver;
            }
        }
        return first ?? "";
    }

    /// <summary>
    /// for ($try = 0; $try -lt 3 -and -not $ok; $try++) { Push-Location $target; &amp; $java -jar $inst ... $target *&gt; kurulum.log; $ok = ($LASTEXITCODE -eq 0); Pop-Location }
    /// </summary>
    static bool RunInstaller(string java, string jar, string flag, string target)
    {
        string log = Path.Combine(target, "kurulum.log");
        for (int t = 0; t < Tries; t++)
        {
            if (t > 0) Thread.Sleep(2000);
            if (RunToLog(java, new[] { "-jar", jar, flag, target }, target, log) == 0) return true;
        }
        return false;
    }

    /// <summary>Programı çalıştırır, çıktısını ve hatalarını sırayla dosyaya yazar (her denemede baştan). Çıkış kodunu döner.</summary>
    static int RunToLog(string exe, string[] args, string dir, string logPath)
    {
        // Latin1 baytı baytına geçirir: Java'nın yazdığı (Windows kod sayfasındaki) metin dosyaya aynen gider
        using var log = new StreamWriter(logPath, false, Encoding.Latin1);
        var gate = new object();
        long last = Environment.TickCount64;
        void Line(string s)
        {
            if (s == null) return;
            lock (gate) { log.WriteLine(s); last = Environment.TickCount64; }
        }
        var psi = new ProcessStartInfo(exe)
        {
            WorkingDirectory = dir,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.Latin1,
            StandardErrorEncoding = Encoding.Latin1,
        };
        foreach (string a in args) psi.ArgumentList.Add(a);
        using var p = new Process { StartInfo = psi };
        p.OutputDataReceived += (s, e) => Line(e.Data);
        p.ErrorDataReceived += (s, e) => Line(e.Data);
        try { p.Start(); }
        catch (Exception ex)
        {
            lock (gate) log.WriteLine("SyHost: could not start " + exe + ": " + ex.Message);
            return -1;
        }
        try { JobGuard.Add(p); } catch { }   // SyHost kapanırsa yükleyici yetim kalmasın
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        while (!p.WaitForExit(1000))
        {
            long quiet;
            lock (gate) quiet = Environment.TickCount64 - last;
            if (quiet > (long)InstallerSilence.TotalMilliseconds)
            {
                lock (gate) log.WriteLine($"SyHost: the installer wrote nothing for {(int)InstallerSilence.TotalMinutes} minutes, stopping it.");
                try { p.Kill(true); } catch { }
                break;
            }
        }
        p.WaitForExit();   // çıktının sonu da dosyaya yazılsın
        lock (gate) log.Flush();
        try { return p.ExitCode; } catch { return -1; }
    }

    // ---------- 3: modlar ----------
    /// <summary>
    /// Dosyaları 6'şar 6'şar indirir. Ekrandaki %, n/toplam ve dosya adı PowerShell'deki gibi güncellenir
    /// (sayaç dosyalar bittikçe ilerler). İnemeyenler paketteki sırayla döner.
    /// </summary>
    static List<string> DownloadAll(InstallSync sync, List<ModFile> files, string target, string full)
    {
        int total = files.Count, done = 0;
        var failed = new bool[total];
        var running = new List<ModFile>();
        ModFile shown = null;
        var gate = new object();
        if (total > 0) sync.Count = "0/" + Ps.S(total);
        Parallel.ForEachAsync(files, new ParallelOptions { MaxDegreeOfParallelism = ModsAtOnce }, async (f, ct) =>
        {
            lock (gate) { running.Add(f); shown = f; sync.Detail = f.Leaf; }
            try
            {
                string outp = Inside(target, f.Path, full);
                if (outp == null) return;   // PowerShell: continue (sayılır, indirilmez)
                Directory.CreateDirectory(Path.GetDirectoryName(outp));
                if (!await FetchVerified(f, outp, ct).ConfigureAwait(false)) failed[f.Index] = true;
            }
            finally
            {
                lock (gate)
                {
                    running.Remove(f);
                    // Ekranda biten dosyanın adı kalmasın: hâlâ inen en son dosyayı göster
                    if (shown == f && running.Count > 0) { shown = running[^1]; sync.Detail = shown.Leaf; }
                    done++;
                    sync.Pct = Ps.Int((double)done / Math.Max(1, total) * 100);
                    sync.Count = Ps.S(done) + "/" + Ps.S(total);
                }
            }
        }).GetAwaiter().GetResult();
        if (total > 0) sync.Detail = files[^1].Leaf;   // PowerShell'deki gibi son dosyanın adı kalır
        var list = new List<string>();
        for (int i = 0; i < total; i++) if (failed[i]) list.Add(files[i].Leaf);
        return list;
    }

    /// <summary>3 tur, her turda downloads[] içindeki her adres; karma tutunca dosya yerine konur.</summary>
    static async Task<bool> FetchVerified(ModFile f, string outp, CancellationToken ct)
    {
        // PowerShell sha1'i yoksa hiçbir indirmeyi kabul etmez; burada sha512 de yeter
        if (f.Urls.Count == 0 || (f.Sha1 == null && f.Sha512 == null)) return false;
        string part = outp + "." + f.Index + ".part";
        long max = f.Size > 0 ? f.Size * 2 + (1 << 20) : MaxFile;
        for (int round = 0; round < Tries; round++)
        {
            if (round > 0) await Task.Delay(500 * round, ct).ConfigureAwait(false);   // geçici ağ sorununa kısa bir nefes
            foreach (string url in f.Urls)
            {
                using var sha1 = f.Sha1 != null ? IncrementalHash.CreateHash(HashAlgorithmName.SHA1) : null;
                using var sha512 = f.Sha512 != null ? IncrementalHash.CreateHash(HashAlgorithmName.SHA512) : null;
                try
                {
                    var hashes = sha1 != null && sha512 != null ? new[] { sha1, sha512 } : new[] { sha1 ?? sha512 };
                    await FetchAsync(url, part, hashes, max, ct).ConfigureAwait(false);
                    if ((sha1 == null || Ps.Eq(Convert.ToHexStringLower(sha1.GetHashAndReset()), f.Sha1)) &&
                        (sha512 == null || Ps.Eq(Convert.ToHexStringLower(sha512.GetHashAndReset()), f.Sha512)))
                    {
                        lock (MoveGate) File.Move(part, outp, true);
                        return true;
                    }
                }
                catch (OperationCanceledException) when (ct.IsCancellationRequested) { TryDelete(part); throw; }
                catch { }
                TryDelete(part);
            }
        }
        return false;
    }

    // ---------- 6: server.properties ----------
    /// <summary>Var olan satırları yerinde günceller (büyük-küçük harfe bakmadan), olmayanları sona ekler. UTF-8 (BOM'suz), CRLF.</summary>
    static void WriteProperties(string pf, (string K, string V)[] props)
    {
        var lines = new List<string>();
        if (File.Exists(pf) || Directory.Exists(pf)) lines.AddRange(File.ReadAllLines(pf));
        foreach (var (k, v) in props)
        {
            var rx = new Regex("^" + Regex.Escape(k) + "=", RegexOptions.IgnoreCase);
            bool found = false;
            for (int i = 0; i < lines.Count; i++) if (rx.IsMatch(lines[i])) { lines[i] = k + "=" + v; found = true; }
            if (!found) lines.Add(k + "=" + v);
        }
        File.WriteAllLines(pf, lines, Json.Utf8NoBom);
    }

    static void Note(string target, string text)
    {
        try { File.AppendAllText(Path.Combine(target, "kurulum.log"), "SyHost: " + text + Environment.NewLine, Json.Utf8NoBom); } catch { }
    }

    static string Chain(Exception ex)
    {
        var sb = new StringBuilder();
        for (var e = ex; e != null; e = e.InnerException)
        {
            if (sb.Length > 0) sb.Append(" <- ");
            sb.Append(e.Message);
        }
        return sb.Length > 0 ? sb.ToString() : "not found after download";
    }

    internal static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    // ---------- İndirme (Core/Java.cs de kullanır) ----------
    /// <summary>Sunucu hata kodu döndürdü. Metin PowerShell sürümündekiyle (.NET Framework WebException) aynı.</summary>
    internal sealed class HttpError : Exception
    {
        public readonly int Code;
        public HttpError(int code, string reason) : base($"The remote server returned an error: ({code}) {reason}.") { Code = code; }
        /// <summary>Tekrar denemek boşuna (dosya yok, yasak...)</summary>
        public bool Permanent => Code >= 400 && Code < 500 && Code != 408 && Code != 429;
    }

    static void Ensure(HttpResponseMessage resp)
    {
        if (!resp.IsSuccessStatusCode) throw new HttpError((int)resp.StatusCode, resp.ReasonPhrase ?? "");
    }

    /// <summary>
    /// Ağ hatasını PowerShell sürümünün gösterdiği metne çevirir (Invoke-WebRequest'in .NET Framework iletileri).
    /// Kurulum hatası ekranda olduğu gibi görünür, iki sürüm aynı şeyi yazsın.
    /// </summary>
    static Exception NetError(Exception ex, string url)
    {
        if (ex is HttpRequestException h)
        {
            if (h.HttpRequestError == HttpRequestError.NameResolutionError)
            {
                string host = Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.Host : url;
                return new IOException($"The remote name could not be resolved: '{host}'", ex);
            }
            if (h.HttpRequestError == HttpRequestError.ConnectionError) return new IOException("Unable to connect to the remote server", ex);
        }
        if (ex is OperationCanceledException or TimeoutException) return new TimeoutException("The operation has timed out.", ex);
        return ex;
    }

    /// <summary>Metin indir (API yanıtları). tries kez dener; olmazsa PowerShell metniyle fırlatır.</summary>
    internal static string GetText(string url, int tries = Tries)
    {
        Exception last = null;
        for (int i = 0; i < tries; i++)
        {
            if (i > 0) Thread.Sleep(1000 * i);
            try { return GetTextAsync(url).GetAwaiter().GetResult(); }
            catch (Exception ex) { last = ex; if (ex is HttpError he && he.Permanent) break; }
        }
        throw NetError(last, url);
    }

    static async Task<string> GetTextAsync(string url)
    {
        using var cts = new CancellationTokenSource(HeaderTimeout);
        using var resp = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cts.Token).ConfigureAwait(false);
        Ensure(resp);
        return await resp.Content.ReadAsStringAsync(cts.Token).ConfigureAwait(false);
    }

    /// <summary>Invoke-WebRequest -OutFile: 3 kez dener, yarım dosya bırakmaz; olmazsa PowerShell metniyle fırlatır.</summary>
    internal static void DownloadFile(string url, string path)
    {
        string part = path + ".part";
        Exception last = null;
        for (int i = 0; i < Tries; i++)
        {
            if (i > 0) Thread.Sleep(1500 * i);
            try
            {
                FetchAsync(url, part, null, MaxFile, CancellationToken.None).GetAwaiter().GetResult();
                File.Move(part, path, true);
                return;
            }
            catch (Exception ex)
            {
                last = ex;
                TryDelete(part);
                if (ex is HttpError he && he.Permanent) break;
            }
        }
        throw NetError(last, url);
    }

    /// <summary>Tek deneme, eşzamanlı. Dönen adres yönlendirmelerden sonraki son adrestir.</summary>
    internal static Uri Fetch(string url, string path, IncrementalHash[] hashes, long maxBytes)
    {
        try { return FetchAsync(url, path, hashes, maxBytes, CancellationToken.None).GetAwaiter().GetResult(); }
        catch (Exception ex) { throw NetError(ex, url); }
    }

    /// <summary>
    /// Adresi dosyaya indirir, inerken karmaları hesaplar. Başlıklar 100 sn içinde gelmeli,
    /// sonra 60 sn hiç veri gelmezse bağlantı kopmuş sayılır (yavaş ama ilerleyen indirme kesilmez).
    /// </summary>
    static async Task<Uri> FetchAsync(string url, string path, IncrementalHash[] hashes, long maxBytes, CancellationToken ct)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(HeaderTimeout);
        using var resp = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cts.Token).ConfigureAwait(false);
        Ensure(resp);
        Uri final = resp.RequestMessage?.RequestUri ?? new Uri(url);
        byte[] buf = ArrayPool<byte>.Shared.Rent(1 << 16);
        try
        {
            await using var body = await resp.Content.ReadAsStreamAsync(cts.Token).ConfigureAwait(false);
            await using var fs = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, FileOptions.Asynchronous);
            long total = 0;
            while (true)
            {
                cts.CancelAfter(StallTimeout);
                int n = await body.ReadAsync(buf.AsMemory(), cts.Token).ConfigureAwait(false);
                if (n == 0) break;
                total += n;
                if (maxBytes > 0 && total > maxBytes) throw new InvalidDataException("The download is larger than expected.");
                if (hashes != null) foreach (var h in hashes) h.AppendData(buf, 0, n);
                await fs.WriteAsync(buf.AsMemory(0, n), cts.Token).ConfigureAwait(false);
            }
        }
        finally { ArrayPool<byte>.Shared.Return(buf); }
        return final;
    }
}
