// =====================================================================
//  SyHost - uygulamanın içinden kaldırma
//  Klasörün DIŞINDA kalan izleri bulur ve yalnızca kullanıcının seçtiklerini kaldırır:
//    kısayollar, SyHost'un kurduğu kullanıcı yazı tipi, 0.5.0'dan kalanlar (eski veri
//    klasörü, eski kurulum klasörü, Program Files'taki playit, C:\Windows\Fonts'taki yazı tipi,
//    winget ile kurulmuş Java) ve istenirse SyHost klasörünün kendisi.
//  Java varsayılan olarak silinmez (başka programlar da kullanıyor olabilir).
//  Klasör dışındaki sunucu klasörlerine asla dokunulmaz: kayıtlı bir sunucuyu ya da SyHost klasörünü içeren eski
//  klasörler önerilmez; sürücü kökü, git deposu ya da kullanıcı klasörü gibi bir SyHost klasörü hiç silinmez.
//  Silerken bağlantıların (junction, sembolik bağlantı) içine girilmez.
//  Gizli pencere, kodlanmış komut ya da kendini silen yardımcı süreç yoktur: yönetici izni gereken tek SyHost adımı
//  SyHost.exe'nin kendisidir (OldSystemFont.Arg); klasörün içi SyHost kapanırken bu süreçte silinir, boş kalan
//  klasörü kullanıcı Explorer'dan siler.
//  SYHOST_DRYRUN=1: hiçbir şey silinmez, yalnızca ne yapılacağı yazılır (testler için).
//  Terminal sürümündeki karşılığı: legacy\src\Uninstall.ps1 (aynı kurallar).
// =====================================================================
using System.Diagnostics;
using Microsoft.Win32;

namespace SyHost;

static class Uninstall
{
    public static bool DryRun => Environment.GetEnvironmentVariable("SYHOST_DRYRUN") == "1";

    public sealed class Item
    {
        public string Key;          // kisayol, yazitipi, eskiveri, eskikurulum, eskiplayit, eskiyazitipi, java, klasor
        public string Title;        // ekranda görünen ad (Türkçe anahtar, L ile çevrilir)
        public string Detail;       // ayrıntı (yol vb., çevrilmez)
        public bool On;             // seçili mi
        public bool NeedsAdmin;     // Windows izin penceresi çıkar
        public volatile int State;  // 0 bekliyor, 1 sürüyor, 2 bitti, 3 hata, 4 atlandı
        public volatile string Error;
        internal Func<string> Run;  // hata metni ya da null
    }

    /// <summary>Kaldırılabilecek her şeyi bul.</summary>
    public static List<Item> Detect(string root, string exe, IEnumerable<ServerEntry> servers)
    {
        var list = new List<Item>();
        var serverDirs = (servers ?? Enumerable.Empty<ServerEntry>()).Select(s => s.klasor).Where(k => !string.IsNullOrEmpty(k)).ToList();
        // Kayıtlı bir sunucu bu klasörün içinde mi? (öyleyse klasör kaldırılmaya önerilmez)
        bool holdsServer(string dir) => serverDirs.Any(k => Portable.IsInside(k, dir));

        // 1) Bu SyHost'u açan kısayollar (okunamazsa satır gösterilmez)
        var ours = new List<string>();
        try { ours = Shortcuts.Locations().Where(l => Shortcuts.StateOf(l, exe) == Shortcuts.State.Ours).ToList(); } catch { }
        if (ours.Count > 0)
            list.Add(new Item { Key = "kisayol", Title = "Masaüstü ve Başlat menüsü kısayolları", Detail = string.Join("  ·  ", ours), On = true, Run = () => { Shortcuts.RemoveOurs(exe); return null; } });

        // 2) SyHost'un bu kullanıcıya kurduğu yazı tipi
        if (Fonts.InstalledBySyHost())
            list.Add(new Item { Key = "yazitipi", Title = "SyHost'un kurduğu Cascadia Mono yazı tipi", Detail = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\Windows\Fonts"), On = true, Run = () => Fonts.UninstallPerUser() ? null : "?" });

        // 3) 0.5.0'ın veri klasörü (SyHost klasörünü ya da kayıtlı bir sunucuyu içeriyorsa önerilmez)
        string legacy = Migration.LegacyDir();
        if (Directory.Exists(legacy) && !Portable.IsInside(legacy, root) && !Portable.IsInside(root, legacy) && !holdsServer(legacy))
            list.Add(new Item { Key = "eskiveri", Title = "Eski sürümün veri klasörü", Detail = legacy, On = false, Run = () => DeleteDir(legacy) });

        // 4) 0.5.0'ın kurulum klasörü (install.ps1 buraya kuruyordu) ve onu açan eski kısayollar
        string oldInstall = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\SyHost");
        if (Directory.Exists(oldInstall) && !Portable.IsInside(oldInstall, root) && !Portable.IsInside(root, oldInstall) && !holdsServer(oldInstall))
            list.Add(new Item
            {
                Key = "eskikurulum", Title = "Eski sürümün program klasörü", Detail = oldInstall, On = false,
                Run = () =>
                {
                    foreach (string l in Shortcuts.Locations())
                    {
                        var i = Shortcuts.Read(l); string p = i == null ? null : Shortcuts.SyHostPathOf(i.Value);
                        if (p != null && Portable.IsInside(p, oldInstall)) { if (DryRun) Log("kısayol silinecekti: " + l); else try { File.Delete(l); } catch { } }
                    }
                    return DeleteDir(oldInstall);
                },
            });

        // 5) Program Files'taki playit (eski kurulum, winget)
        var playit = FindMsi(n => n.StartsWith("playit", StringComparison.OrdinalIgnoreCase));
        if (playit != null)
            list.Add(new Item { Key = "eskiplayit", Title = "Eski playit kurulumu (Program Files)", Detail = playit.Value.Name, On = false, NeedsAdmin = true, Run = () => RunUninstaller(playit.Value.Uninstall) });

        // 6) Eski kurulumun C:\Windows\Fonts'a koyduğu yazı tipi
        string sysFont = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"Fonts\CascadiaMono-Regular.ttf");
        if (File.Exists(sysFont))
            list.Add(new Item { Key = "eskiyazitipi", Title = "Eski kurulumun sisteme koyduğu yazı tipi", Detail = sysFont, On = false, NeedsAdmin = true, Run = RemoveSystemFont });

        // 7) Eski sürümün winget ile kurduğu Java'lar (varsayılan: silinmez)
        foreach (var j in FindMsiAll(n => n.StartsWith("Microsoft Build of OpenJDK", StringComparison.OrdinalIgnoreCase) || n.StartsWith("Eclipse Temurin JRE with Hotspot 8", StringComparison.OrdinalIgnoreCase)))
            list.Add(new Item { Key = "java", Title = "Java (başka programlar da kullanıyor olabilir)", Detail = j.Name, On = false, NeedsAdmin = true, Run = () => RunUninstaller(j.Uninstall) });

        // 8) SyHost klasörünün kendisi (sunucular ve dünyalar dahil); silinmesi felaket olacak bir yerse önerilmez
        if (CanDeleteRoot(root))
            list.Add(new Item { Key = "klasor", Title = "SyHost klasörünün kendisi", Detail = root, On = false, Run = () => null });
        return list;
    }

    /// <summary>
    /// SyHost klasörünün kendisi silinebilir mi? Sürücü kökü (ör. bir USB bellek), git deposu, kullanıcı klasörü,
    /// Masaüstü, Belgeler, İndirilenler, Program Files, Windows ya da bunlardan birini içeren bir klasör silinmez
    /// (Data klasörü olan herhangi bir klasör "kurulu" sayıldığı için SyHost böyle bir yerde açılmış olabilir).
    /// </summary>
    public static bool CanDeleteRoot(string root)
    {
        try
        {
            string full = Path.GetFullPath(root).TrimEnd('\\');
            // Klasörün kendisi bir bağlantıysa (junction, sembolik bağlantı, klasöre bağlanmış bir sürücü) içini boşaltmak
            // gösterdiği yerdeki her şeyi silerdi (ör. bir USB belleğin tamamı): böyle bir klasör hiç önerilmez
            var di = new DirectoryInfo(full);
            if (di.Exists && (di.Attributes & FileAttributes.ReparsePoint) != 0) return false;
            string drive = Path.GetPathRoot(full);
            if (string.IsNullOrEmpty(drive) || drive.TrimEnd('\\').Equals(full, StringComparison.OrdinalIgnoreCase)) return false;
            string git = Path.Combine(full, ".git");
            if (Directory.Exists(git) || File.Exists(git)) return false;
            foreach (string p in ProtectedFolders()) if (!string.IsNullOrEmpty(p) && Portable.IsInside(p, full)) return false;
            return true;
        }
        catch { return false; }
    }

    static IEnumerable<string> ProtectedFolders()
    {
        foreach (var f in new[]
                 {
                     Environment.SpecialFolder.UserProfile, Environment.SpecialFolder.DesktopDirectory, Environment.SpecialFolder.MyDocuments,
                     Environment.SpecialFolder.MyMusic, Environment.SpecialFolder.MyPictures, Environment.SpecialFolder.MyVideos,
                     Environment.SpecialFolder.ApplicationData, Environment.SpecialFolder.LocalApplicationData, Environment.SpecialFolder.CommonApplicationData,
                     Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.Windows, Environment.SpecialFolder.Programs,
                 })
            yield return Environment.GetFolderPath(f);
        yield return Portable.Downloads();
        foreach (string v in new[] { "OneDrive", "OneDriveConsumer", "OneDriveCommercial" }) yield return Environment.GetEnvironmentVariable(v);
    }

    /// <summary>Seçili adımları sırayla çalıştır (arka planda çağrılır).</summary>
    public static void RunSelected(List<Item> items)
    {
        foreach (var it in items)
        {
            if (!it.On || it.Key == "klasor") { it.State = it.On ? 2 : 4; continue; }
            it.State = 1;
            try
            {
                string err = DryRun ? DryRunLog(it) : it.Run();
                it.Error = err; it.State = err == null ? 2 : 3;
            }
            catch (Exception e) { it.Error = e.Message; it.State = 3; }
        }
    }

    static string DryRunLog(Item it) { Log("[deneme] yapılacaktı: " + it.Key + "  " + it.Detail); return null; }

    static void Log(string s)
    {
        try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "syhost-dryrun.log"), DateTime.Now.ToString("HH:mm:ss ") + s + Environment.NewLine); } catch { }
    }

    /// <summary>
    /// Klasörü sil. Bağlantılara (junction, sembolik bağlantı) girilmez: bağlantının kendisi silinir, gösterdiği yer
    /// olduğu gibi kalır. Silmeyi engelleyen tek öznitelik olan "salt okunur" silmeden önce kaldırılır.
    /// </summary>
    internal static string DeleteDir(string dir)
    {
        if (DryRun) { Log("klasör silinecekti: " + dir); return null; }
        try
        {
            var top = new DirectoryInfo(dir);
            if ((top.Attributes & FileAttributes.ReparsePoint) != 0) { Directory.Delete(top.FullName, false); return null; }
            ClearReadOnly(top);
            var links = new List<FileSystemInfo>();
            var stack = new Stack<DirectoryInfo>();
            stack.Push(top);
            while (stack.Count > 0)
            {
                foreach (var e in stack.Pop().EnumerateFileSystemInfos())
                {
                    if ((e.Attributes & FileAttributes.ReparsePoint) != 0) { links.Add(e); continue; }
                    ClearReadOnly(e);
                    if (e is DirectoryInfo d) stack.Push(d);
                }
            }
            foreach (var l in links) { if (l is DirectoryInfo) Directory.Delete(l.FullName, false); else File.Delete(l.FullName); }
            Directory.Delete(top.FullName, true);
            return null;
        }
        catch (Exception e) { return e.Message; }
    }

    static void ClearReadOnly(FileSystemInfo e)
    {
        try { if ((e.Attributes & FileAttributes.ReadOnly) != 0) e.Attributes &= ~FileAttributes.ReadOnly; } catch { }
    }

    readonly record struct Msi(string Name, string Uninstall);

    static Msi? FindMsi(Func<string, bool> match) => FindMsiAll(match).Cast<Msi?>().FirstOrDefault();

    static List<Msi> FindMsiAll(Func<string, bool> match)
    {
        var r = new List<Msi>();
        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            try
            {
                using var hk = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
                using var k = hk.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall");
                if (k == null) continue;
                foreach (string sub in k.GetSubKeyNames())
                {
                    using var e = k.OpenSubKey(sub);
                    if (e?.GetValue("DisplayName") is not string name || !match(name)) continue;
                    string u = e.GetValue("QuietUninstallString") as string ?? e.GetValue("UninstallString") as string;
                    if (string.IsNullOrEmpty(u) || r.Any(x => x.Name == name)) continue;
                    r.Add(new Msi(name, u));
                }
            }
            catch { }
        }
        return r;
    }

    /// <summary>Kaldırıcı komutunu çalıştırılacak dosya ve argümanlara ayır.</summary>
    internal static (string File, string Args) UninstallerCommand(string cmd)
    {
        cmd = cmd.Trim();
        // MsiExec.exe /I{GUID} -> /X{GUID} /qb (yalnızca ilerleme çubuğu). Tam yoluyla: yalın ad, SyHost klasöründeki
        // aynı adlı bir dosyayı da bulabilirdi (çalışma klasörü SyHost klasörü) ve o yönetici olarak açılırdı.
        if (cmd.StartsWith("MsiExec.exe", StringComparison.OrdinalIgnoreCase))
            return (Path.Combine(Environment.SystemDirectory, "msiexec.exe"), System.Text.RegularExpressions.Regex.Replace(cmd.Substring("MsiExec.exe".Length), "/I", "/X", System.Text.RegularExpressions.RegexOptions.IgnoreCase).Trim() + " /qb");
        if (cmd.StartsWith("\""))
        {
            int q = cmd.IndexOf('"', 1);
            return (cmd.Substring(1, q - 1), cmd.Substring(q + 1).Trim());
        }
        int sp = cmd.IndexOf(' ');
        return (sp < 0 ? cmd : cmd.Substring(0, sp), sp < 0 ? "" : cmd.Substring(sp + 1));
    }

    /// <summary>Bir programın kendi kaldırıcısını çalıştır (MSI ise Windows izin penceresi çıkar).</summary>
    static string RunUninstaller(string cmd)
    {
        try
        {
            var (file, args) = UninstallerCommand(cmd);
            using var p = Process.Start(new ProcessStartInfo(file, args) { UseShellExecute = true, Verb = "runas" });
            p?.WaitForExit();
            return p == null || p.ExitCode == 0 || p.ExitCode == 3010 ? null : "kod " + p.ExitCode;
        }
        catch (System.ComponentModel.Win32Exception e) when (e.NativeErrorCode == 1223) { return "izin verilmedi"; }
        catch (Exception e) { return e.Message; }
    }

    /// <summary>
    /// Eski kurulumun C:\Windows\Fonts'a koyduğu Cascadia Mono'yu kaldır: SyHost.exe kendini yalnızca
    /// OldSystemFont.Arg ile yönetici olarak açar (Windows izin penceresinde SyHost görünür). 0 dışındaki çıkış
    /// kodu "kod N" olarak gösterilir (ör. dosya kullanımda: kayıt silindi, dosya oturum kapanınca silinebilir).
    /// </summary>
    static string RemoveSystemFont()
    {
        try
        {
            string exe = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exe) || !File.Exists(exe)) return "kod 2";
            using var p = Process.Start(new ProcessStartInfo(exe, OldSystemFont.Arg) { UseShellExecute = true, Verb = "runas" });
            if (p == null) return null;
            p.WaitForExit();
            return p.ExitCode == 0 ? null : "kod " + p.ExitCode;
        }
        catch (System.ComponentModel.Win32Exception e) when (e.NativeErrorCode == 1223) { return "izin verilmedi"; }
        catch (Exception e) { return e.Message; }
    }

    /// <summary>
    /// Kaldır &gt; "SyHost klasörünün kendisi": SyHost kapanırken (sunucu, playit ve tepsi kapandıktan sonra, tek kopya
    /// kilidi henüz bırakılmadan) klasörün içindekileri BU süreçte siler. Kendini silen yardımcı bir süreç
    /// başlatılmaz. keep'tekiler (çalışan exe; Terminal sürümünde SyHost.Core.dll'i yüklü App klasörü) ve
    /// kullanımdaki dosyalar kalır, klasörün kendisi de kalır (SyHost'un çalışma klasörüdür): ardından Explorer
    /// klasörü gösterir (ShowFolder), kullanıcı kalanı oradan siler. Bağlantıların gösterdiği yere dokunulmaz.
    /// </summary>
    public static void DeleteFolderAfterExit(string root, IEnumerable<string> keep)
    {
        if (!CanDeleteRoot(root)) return;
        if (DryRun) { Log("SyHost kapanınca klasör silinecekti: " + root); return; }
        try { Environment.CurrentDirectory = Path.GetTempPath(); } catch { }
        var kept = new List<string>();
        foreach (string k in keep ?? Enumerable.Empty<string>())
            try { if (!string.IsNullOrEmpty(k)) kept.Add(Path.GetFullPath(k).TrimEnd('\\')); } catch { }
        // Yeni kapanan sunucu ya da playit dosyaları bir an daha tutabilir: birkaç tur dene (en çok ~5 sn)
        for (int round = 0; round < 10 && !EmptyFolder(root, kept); round++) Thread.Sleep(500);
        try { var di = new DirectoryInfo(root); di.Attributes &= ~(FileAttributes.ReadOnly | FileAttributes.System); } catch { }
    }

    /// <summary>Klasörün içini sil (klasörün kendisi kalır); keep'tekiler kalır. Silinemeyen bir şey kaldıysa false.</summary>
    static bool EmptyFolder(string dir, List<string> keep)
    {
        List<FileSystemInfo> entries;
        try { entries = new DirectoryInfo(dir).EnumerateFileSystemInfos().ToList(); }
        catch { return false; }
        bool clean = true;
        foreach (var e in entries)
        {
            string full = e.FullName.TrimEnd('\\');
            if (keep.Any(k => k.Equals(full, StringComparison.OrdinalIgnoreCase))) continue;
            try
            {
                if ((e.Attributes & FileAttributes.ReparsePoint) != 0)
                {
                    // Bağlantı: yalnızca kendisi silinir, gösterdiği yer olduğu gibi kalır
                    if (e is DirectoryInfo) Directory.Delete(full, false); else File.Delete(full);
                }
                else if (e is DirectoryInfo)
                {
                    // İçinde saklanacak bir şey varsa klasörün içine girilir, yoksa bütünüyle silinir
                    if (keep.Any(k => Portable.IsInside(k, full))) { if (!EmptyFolder(full, keep)) clean = false; }
                    else if (DeleteDir(full) != null) clean = false;
                }
                else
                {
                    ClearReadOnly(e);
                    File.Delete(full);
                }
            }
            catch { clean = false; }
        }
        return clean;
    }

    /// <summary>Explorer'da SyHost klasörünü seçili göster ("artık silebilirsin").</summary>
    public static void ShowFolder(string root)
    {
        // Tam yoluyla: yalın "explorer.exe" çalışma klasöründe (SyHost klasörü) de aranırdı
        string explorer = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe");
        try { Process.Start(new ProcessStartInfo(explorer, "/select,\"" + root.TrimEnd('\\') + "\"") { UseShellExecute = true }); } catch { }
    }

    /// <summary>
    /// SyHost.exe --selftest uninstall &lt;SyHost klasörü&gt; [&lt;silinecek deneme klasörü&gt;]
    /// Bulmayı ve kaldırmayı DENEME modunda çalıştırıp sonucu satır satır yazar; Terminal sürümünün testi
    /// (tests\legacy\Test-Uninstall.ps1) aynı satırları kendisi üretip karşılaştırır. SYHOST_DRYRUN=1 zorlanır.
    /// Sunucular: &lt;SyHost klasörü&gt;\Data\sunucular.json. İkinci klasör verilirse ve içinde syhost-selftest-sil.txt
    /// varsa yalnızca o klasör gerçekten silinir (bağlantıların gösterdiği yere dokunulmadığını görmek için).
    /// </summary>
    internal static int SelfTest(string root, string deleteDir)
    {
        Console.OutputEncoding = new System.Text.UTF8Encoding(false);   // Türkçe adlar karşılaştırılabilsin
        root = Path.GetFullPath(root);
        if (deleteDir != null)
        {
            if (!File.Exists(Path.Combine(deleteDir, "syhost-selftest-sil.txt"))) { Console.WriteLine("HATA  syhost-selftest-sil.txt yok: " + deleteDir); return 1; }
            Environment.SetEnvironmentVariable("SYHOST_DRYRUN", null);
            string err = DeleteDir(deleteDir);
            Console.WriteLine("sil|" + (Directory.Exists(deleteDir) ? "duruyor" : "silindi") + "|" + err);
        }
        Environment.SetEnvironmentVariable("SYHOST_DRYRUN", "1");
        var servers = new List<ServerEntry>();
        string file = Path.Combine(root, Portable.DataName, "sunucular.json");
        if (File.Exists(file))
            foreach (var s in Json.ParseServers(Json.ReadText(file)))
            {
                string k = Environment.ExpandEnvironmentVariables(s.klasor ?? "");
                if (k.Length > 0 && !Path.IsPathRooted(k)) k = Path.GetFullPath(Path.Combine(root, k));
                s.klasor = k;
                servers.Add(s);
            }
        var items = Detect(root, Path.Combine(root, Portable.ExeName), servers);
        foreach (var it in items) Console.WriteLine("item|" + it.Key + "|" + it.Title + "|" + it.Detail + "|" + it.On + "|" + it.NeedsAdmin);
        foreach (var it in items) it.On = true;
        RunSelected(items);
        foreach (var it in items) Console.WriteLine("run|" + it.Key + "|" + it.State + "|" + it.Error);
        string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        foreach (string p in new[]
                 {
                     root, Path.GetDirectoryName(root), Path.GetPathRoot(root), profile, Path.Combine(profile, "SyHost"), Portable.Downloads(),
                     Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                     Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                     Path.GetDirectoryName(profile),
                     // Test-Uninstall burada bir bağlantı (junction) kurar: bağlantı olan SyHost klasörü silinmez
                     Path.Combine(Path.GetDirectoryName(root), "Kok-Baglanti"),
                 })
            Console.WriteLine("candelete|" + p + "|" + CanDeleteRoot(p));
        // Kaldırıcı komutları yalnızca ayrıştırılır, çalıştırılmaz: kayıt defterindekiler ve örnekler
        var cmds = FindMsiAll(n => n.StartsWith("playit", StringComparison.OrdinalIgnoreCase) || n.StartsWith("Microsoft Build of OpenJDK", StringComparison.OrdinalIgnoreCase) || n.StartsWith("Eclipse Temurin JRE with Hotspot 8", StringComparison.OrdinalIgnoreCase)).Select(m => m.Uninstall).ToList();
        cmds.AddRange(new[]
        {
            "MsiExec.exe /I{11111111-2222-3333-4444-555555555555}", "  msiexec.exe /i {AAAA} /qn  ", "MsiExec.exe /X{BBBB}",
            "\"C:\\Program Files\\Deneme App\\unins000.exe\" /SILENT", "C:\\Deneme\\uninstall.exe /S /D=x", "C:\\Deneme\\uninstall.exe", "\"C:\\Kapanmayan tırnak",
        });
        foreach (string c in cmds)
        {
            try { var (f, a) = UninstallerCommand(c); Console.WriteLine("uninst|" + c + "|" + f + "|" + a); }
            catch { Console.WriteLine("uninst|" + c + "|HATA"); }
        }
        DeleteFolderAfterExit(root, new[] { Path.Combine(root, Portable.ExeName) });   // deneme modu: yalnızca günlüğe yazar
        return 0;
    }
}
