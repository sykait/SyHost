// =====================================================================
//  SyHost - Java
//  legacy/src/SyHost.ps1: Get-JavaMajor (113-121) ve Find-Java (122-127).
//  Yeni (sahibi onayladı): Java yoksa winget ile bilgisayara kurulmaz.
//  Eclipse Temurin JRE, SyHost'un kendi klasörüne (Data\tools\java-N)
//  indirilir: yönetici izni istemez, bilgisayarın geri kalanına dokunmaz.
// =====================================================================
using System.Diagnostics;
using System.Globalization;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SyHost;

static class Java
{
    const string Api = "https://api.adoptium.net/v3";
    const long MaxZip = 1L << 30;   // JRE zip'i ~50 MB; bundan büyüğü bozuk say

    // Get-ChildItem gibi: gizli klasörleri saymaz, büyük-küçük harfe bakmaz
    static readonly EnumerationOptions Visible = new()
    {
        AttributesToSkip = FileAttributes.Hidden,
        MatchCasing = MatchCasing.CaseInsensitive,
        MatchType = MatchType.Win32,
        IgnoreInaccessible = true,
    };

    /// <summary>Get-JavaMajor: Minecraft sürümüne göre gereken Java (8, 17, 21)</summary>
    public static int GetMajor(string mc)
    {
        string[] p = (mc ?? "").Split('.');           // $mc -split '\.'
        // Yıl numaralı sürümler (26.1, 26.2 ...) Java 25 ister (Mojang sürüm listesi: javaVersion.majorVersion = 25)
        if (!Ps.Eq(p[0], "1")) return Lead(p[0]) >= 26 ? 25 : 21;
        // PowerShell [int]$p[1] "1.21-rc1" gibi ön sürümlerde hata verir; burada da yamadaki gibi baştaki sayı alınır
        int minor = p.Length > 1 ? Lead(p[1]) : 0;
        int patch = p.Length > 2 ? Lead(p[2]) : 0;   // [int]($p[2] -replace '\D.*$', '')
        if (minor >= 21) return 21;
        if (minor == 20 && patch >= 5) return 21;
        if (minor >= 17) return 17;
        return 8;
    }

    // Baştaki rakamlar: "5-pre1" -> 5, "" -> 0
    static int Lead(string s)
    {
        int n = 0;
        while (n < s.Length && s[n] >= '0' && s[n] <= '9') n++;
        if (n == 0) return 0;
        return int.TryParse(s.AsSpan(0, n), NumberStyles.None, CultureInfo.InvariantCulture, out int v) ? v : int.MaxValue;
    }

    /// <summary>Find-Java: önce bilgisayardaki Java, yoksa SyHost'un indirdiği (Data\tools\java-N)</summary>
    public static string Find(int major, string dataDir)
    {
        // PowerShell'deki yerler, aynı sırayla
        string[] pats = major == 8
            ? new[] { @"Eclipse Adoptium\jre-8*", @"Eclipse Adoptium\jdk-8*" }
            : new[] { $@"Microsoft\jdk-{major}*", $@"Eclipse Adoptium\jdk-{major}*", $@"Eclipse Adoptium\jre-{major}*" };
        foreach (string pt in pats)
        {
            foreach (string pf in ProgramFiles())
            {
                string j = Newest(Path.Combine(pf, Path.GetDirectoryName(pt)), Path.GetFileName(pt));
                if (j != null) return j;
            }
        }
        return Own(major, dataDir);
    }

    // PowerShell "C:\Program Files" yazar; Windows başka sürücüdeyse oradaki de bakılır
    static IEnumerable<string> ProgramFiles()
    {
        const string fixedDir = @"C:\Program Files";
        yield return fixedDir;
        string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        if (!string.IsNullOrEmpty(pf) && !string.Equals(pf.TrimEnd('\\'), fixedDir, StringComparison.OrdinalIgnoreCase)) yield return pf;
    }

    /// <summary>parent\desen\bin\java.exe: bulunanların en büyüğü (Sort-Object FullName -Descending | Select-Object -First 1)</summary>
    static string Newest(string parent, string pattern)
    {
        var hits = new List<string>();
        try
        {
            if (!Directory.Exists(parent)) return null;
            foreach (string d in Directory.EnumerateDirectories(parent, pattern, Visible))
            {
                string j = Path.Combine(d, "bin", "java.exe");
                if (File.Exists(j)) hits.Add(j);
            }
        }
        catch { }
        if (hits.Count == 0) return null;
        hits.Sort(StringComparer.CurrentCultureIgnoreCase);
        return hits[^1];
    }

    /// <summary>SyHost'un kendi kopyası: Data\tools\java-N</summary>
    static string Own(int major, string dataDir)
    {
        if (string.IsNullOrEmpty(dataDir)) return null;
        try { return Locate(Path.Combine(dataDir, "tools", "java-" + major)); } catch { return null; }
    }

    /// <summary>klasör\bin\java.exe ya da bir alt klasörde (Adoptium zip'i böyle açılır: jdk-21.0.5+11-jre\bin\java.exe)</summary>
    static string Locate(string root)
    {
        string j = Path.Combine(root, "bin", "java.exe");
        if (File.Exists(j)) return j;
        return Directory.Exists(root) ? Newest(root, "*") : null;
    }

    /// <summary>Java'yı Data\tools\java-N içine indirir, java.exe yolunu döner (hata olursa fırlatır)</summary>
    public static string Download(int major, string dataDir, Action<string> detail)
    {
        detail?.Invoke(Lang.L("Java {0} indiriliyor...", major));
        string tools = Path.Combine(Path.GetFullPath(dataDir), "tools");
        Directory.CreateDirectory(tools);
        string final = Path.Combine(tools, "java-" + major);
        Sweep(tools, major);

        Exception last = null;
        for (int attempt = 0; attempt < 3; attempt++)
        {
            if (attempt > 0) Thread.Sleep(2000 * attempt);
            string id = Guid.NewGuid().ToString("N")[..8];
            string zip = Path.Combine(tools, $"java-{major}.{id}.zip");
            string tmp = Path.Combine(tools, $"java-{major}.{id}.tmp");
            try
            {
                // Adoptium'un bildirdiği SHA-256 (ulaşılamazsa null: o zaman zip'in açılması ve java -version yeter)
                string sum = Checksum(major);
                using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                // İlerleme: "OpenJDK21U-jre_x64_windows_hotspot_21.0.5_11.zip  ·  23 / 48 MB" (dile bağlı değil)
                Installer.Fetch($"{Api}/binary/latest/{major}/ga/windows/x64/jre/hotspot/normal/eclipse", zip, new[] { sha }, MaxZip,
                    (name, got, total) => detail?.Invoke(name + "  ·  " + (got >> 20) + (total > 0 ? " / " + (total >> 20) : "") + " MB"));
                string hash = Convert.ToHexStringLower(sha.GetHashAndReset());
                // Tutmazsa bir kez daha sor: iki istek arasında yeni sürüm çıkmış olabilir
                if (sum != null && !Ps.Eq(sum, hash) && !Ps.Eq(Checksum(major), hash))
                    throw new InvalidDataException($"The Java {major} archive does not match its SHA-256 checksum.");

                ZipFile.ExtractToDirectory(zip, tmp);
                if (Locate(tmp) == null) throw new InvalidDataException($"java.exe is missing from the Java {major} archive.");
                Installer.TryDelete(zip);

                // Yarım kalmış eski klasörü kenara al, yenisini tek adımda yerine koy
                if (Directory.Exists(final))
                {
                    string old = Path.Combine(tools, $"java-{major}.{id}.old");
                    Retry(() => Directory.Move(final, old));
                    RemoveDir(old);
                }
                Retry(() => Directory.Move(tmp, final));

                string exe = Locate(final);
                string why = Check(exe, major);
                if (why != null)
                {
                    // Çalışmayan Java "bulunmuş" sayılmasın: silinemezse en azından adı değişsin
                    RemoveDir(final);
                    if (Directory.Exists(final))
                    {
                        string bad = Path.Combine(tools, $"java-{major}.{id}.old");
                        try { Retry(() => Directory.Move(final, bad)); RemoveDir(bad); } catch { }
                    }
                    throw new InvalidDataException(why);
                }
                return exe;
            }
            catch (Exception ex)
            {
                last = ex;
                if (ex is Installer.HttpError he && he.Permanent) break;   // böyle bir sürüm yok: tekrar denemek boşuna
            }
            finally
            {
                Installer.TryDelete(zip);
                RemoveDir(tmp);
            }
        }
        throw new IOException($"Java {major} could not be downloaded: {last?.Message}", last);
    }

    /// <summary>assets API'sindeki package.checksum (zip'in SHA-256'sı); ulaşılamazsa null</summary>
    static string Checksum(int major)
    {
        try
        {
            string json = Installer.GetText($"{Api}/assets/latest/{major}/hotspot?architecture=x64&image_type=jre&os=windows&vendor=eclipse", 1);
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return null;
            foreach (var rel in doc.RootElement.EnumerateArray())
            {
                if (rel.ValueKind != JsonValueKind.Object || !rel.TryGetProperty("binary", out var b) || b.ValueKind != JsonValueKind.Object) continue;
                if (!Ps.Eq(Str(b, "os"), "windows") || !Ps.Eq(Str(b, "architecture"), "x64") || !Ps.Eq(Str(b, "image_type"), "jre")) continue;
                if (!b.TryGetProperty("package", out var pk) || pk.ValueKind != JsonValueKind.Object) continue;
                string sum = Str(pk, "checksum");
                if (sum != null && Regex.IsMatch(sum, "^[0-9a-fA-F]{64}$")) return sum;
            }
        }
        catch { }
        return null;
    }

    static string Str(JsonElement e, string name) => e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    /// <summary>java.exe -version çalışıyor mu? Sorun yoksa null, varsa nedeni.</summary>
    static string Check(string exe, int major)
    {
        if (exe == null) return "java.exe not found after extracting";
        var psi = new ProcessStartInfo(exe)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        psi.ArgumentList.Add("-version");
        Process started;
        // Başlatılamayan java.exe (bozuk, antivirüs ya da AppLocker engeli) da başarısız denetimdir: klasör silinsin, "bulunmuş" sayılmasın
        try { started = Process.Start(psi); } catch (Exception ex) { return "java.exe could not be started: " + ex.Message; }
        using var p = started;
        var err = p.StandardError.ReadToEndAsync();
        var outp = p.StandardOutput.ReadToEndAsync();
        if (!p.WaitForExit(60_000))
        {
            try { p.Kill(true); } catch { }
            return "java -version did not finish";
        }
        string text = err.GetAwaiter().GetResult() + outp.GetAwaiter().GetResult();
        if (p.ExitCode != 0) return $"java -version exited with code {p.ExitCode}: {text.Trim()}";
        // openjdk version "21.0.5" / "1.8.0_432"
        var m = Regex.Match(text, "version \"(\\d+)(?:\\.(\\d+))?");
        if (m.Success && int.TryParse(m.Groups[1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out int v))
        {
            if (v == 1 && m.Groups[2].Success) int.TryParse(m.Groups[2].Value, NumberStyles.None, CultureInfo.InvariantCulture, out v);
            if (v != major) return $"expected Java {major} but the archive has Java {v}";
        }
        return null;
    }

    // Önceki yarım kalmış denemelerin artıkları: java-N.xxxx.zip / .tmp / .old
    static void Sweep(string tools, int major)
    {
        try
        {
            foreach (string f in Directory.EnumerateFiles(tools, $"java-{major}.*.zip")) Installer.TryDelete(f);
            foreach (string d in Directory.EnumerateDirectories(tools, $"java-{major}.*.tmp")) RemoveDir(d);
            foreach (string d in Directory.EnumerateDirectories(tools, $"java-{major}.*.old")) RemoveDir(d);
        }
        catch { }
    }

    static void RemoveDir(string dir)
    {
        for (int i = 0; i < 5; i++)
        {
            try
            {
                if (!Directory.Exists(dir)) return;
                Directory.Delete(dir, true);
                return;
            }
            catch { Thread.Sleep(300); }
        }
    }

    // Virüs tarayıcısı yeni açılan dosyaları kısa süre kilitleyebilir
    static void Retry(Action a)
    {
        for (int i = 0; ; i++)
        {
            try { a(); return; }
            catch (Exception ex) when (i < 10 && ex is IOException or UnauthorizedAccessException) { Thread.Sleep(300); }
        }
    }
}
