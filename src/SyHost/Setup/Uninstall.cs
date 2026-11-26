// =====================================================================
//  SyHost - uygulamanın içinden kaldırma
//  Klasörün DIŞINDA kalan izleri bulur ve yalnızca kullanıcının seçtiklerini kaldırır:
//    kısayollar, SyHost'un kurduğu kullanıcı yazı tipi, 0.5.0'dan kalanlar (eski veri
//    klasörü, eski kurulum klasörü, Program Files'taki playit, C:\Windows\Fonts'taki yazı tipi,
//    winget ile kurulmuş Java) ve istenirse SyHost klasörünün kendisi.
//  Java varsayılan olarak silinmez (başka programlar da kullanıyor olabilir).
//  Klasör dışındaki sunucu klasörlerine asla dokunulmaz.
//  SYHOST_DRYRUN=1: hiçbir şey silinmez, yalnızca ne yapılacağı yazılır (testler için).
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

        // 1) Bu SyHost'u açan kısayollar
        var ours = Shortcuts.Locations().Where(l => Shortcuts.StateOf(l, exe) == Shortcuts.State.Ours).ToList();
        if (ours.Count > 0)
            list.Add(new Item { Key = "kisayol", Title = "Masaüstü ve Başlat menüsü kısayolları", Detail = string.Join("  ·  ", ours), On = true, Run = () => { Shortcuts.RemoveOurs(exe); return null; } });

        // 2) SyHost'un bu kullanıcıya kurduğu yazı tipi
        if (Fonts.InstalledBySyHost())
            list.Add(new Item { Key = "yazitipi", Title = "SyHost'un kurduğu Cascadia Mono yazı tipi", Detail = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\Windows\Fonts"), On = true, Run = () => Fonts.UninstallPerUser() ? null : "?" });

        // 3) 0.5.0'ın veri klasörü
        string legacy = Migration.LegacyDir();
        if (Directory.Exists(legacy) && !Portable.IsInside(legacy, root))
            list.Add(new Item { Key = "eskiveri", Title = "Eski sürümün veri klasörü", Detail = legacy, On = false, Run = () => DeleteDir(legacy) });

        // 4) 0.5.0'ın kurulum klasörü (install.ps1 buraya kuruyordu) ve onu açan eski kısayollar
        string oldInstall = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\SyHost");
        if (Directory.Exists(oldInstall) && !Portable.IsInside(oldInstall, root) && !Portable.IsInside(root, oldInstall))
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

        // 8) SyHost klasörünün kendisi (sunucular ve dünyalar dahil)
        list.Add(new Item { Key = "klasor", Title = "SyHost klasörünün kendisi", Detail = root, On = false, Run = () => null });
        return list;
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

    static string DeleteDir(string dir)
    {
        if (DryRun) { Log("klasör silinecekti: " + dir); return null; }
        try
        {
            foreach (var f in new DirectoryInfo(dir).EnumerateFileSystemInfos("*", SearchOption.AllDirectories)) { try { f.Attributes = FileAttributes.Normal; } catch { } }
            Directory.Delete(dir, true);
            return null;
        }
        catch (Exception e) { return e.Message; }
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

    /// <summary>Bir programın kendi kaldırıcısını çalıştır (MSI ise Windows izin penceresi çıkar).</summary>
    static string RunUninstaller(string cmd)
    {
        try
        {
            string file, args;
            cmd = cmd.Trim();
            if (cmd.StartsWith("MsiExec.exe", StringComparison.OrdinalIgnoreCase))
            {
                // MsiExec.exe /I{GUID} -> /X{GUID} /qb (yalnızca ilerleme çubuğu)
                file = "msiexec.exe";
                args = System.Text.RegularExpressions.Regex.Replace(cmd.Substring("MsiExec.exe".Length), "/I", "/X", System.Text.RegularExpressions.RegexOptions.IgnoreCase).Trim() + " /qb";
            }
            else if (cmd.StartsWith("\""))
            {
                int q = cmd.IndexOf('"', 1);
                file = cmd.Substring(1, q - 1); args = cmd.Substring(q + 1).Trim();
            }
            else
            {
                int sp = cmd.IndexOf(' ');
                file = sp < 0 ? cmd : cmd.Substring(0, sp); args = sp < 0 ? "" : cmd.Substring(sp + 1);
            }
            using var p = Process.Start(new ProcessStartInfo(file, args) { UseShellExecute = true, Verb = "runas" });
            p?.WaitForExit();
            return p == null || p.ExitCode == 0 || p.ExitCode == 3010 ? null : "kod " + p.ExitCode;
        }
        catch (System.ComponentModel.Win32Exception e) when (e.NativeErrorCode == 1223) { return "izin verilmedi"; }
        catch (Exception e) { return e.Message; }
    }

    /// <summary>Eski kurulumun C:\Windows\Fonts'a koyduğu Cascadia Mono'yu kaldır (yönetici izniyle).</summary>
    static string RemoveSystemFont()
    {
        string ps = "$k='HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts';" +
                    "Remove-ItemProperty $k 'Cascadia Mono Regular (TrueType)' -ErrorAction SilentlyContinue;" +
                    "Remove-ItemProperty $k 'Cascadia Mono Bold (TrueType)' -ErrorAction SilentlyContinue;" +
                    "foreach($f in 'CascadiaMono-Regular.ttf','CascadiaMono-Bold.ttf'){ $p=Join-Path $env:WINDIR ('Fonts\\'+$f); try{ Remove-Item $p -Force -ErrorAction Stop }catch{} }";
        try
        {
            string enc = Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(ps));
            using var p = Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand " + enc) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden });
            p?.WaitForExit();
            return null;
        }
        catch (System.ComponentModel.Win32Exception e) when (e.NativeErrorCode == 1223) { return "izin verilmedi"; }
        catch (Exception e) { return e.Message; }
    }

    /// <summary>SyHost kapandıktan sonra klasörü sil (kendini silemediği için ayrı bir cmd ile).</summary>
    public static void DeleteFolderAfterExit(string root)
    {
        if (DryRun) { Log("SyHost kapanınca klasör silinecekti: " + root); return; }
        string q = "\"" + root.TrimEnd('\\') + "\"";
        string cmd = $"/d /c for /l %i in (1,1,60) do (if exist {q} (attrib -r -s -h {q} /s /d >nul 2>&1 & attrib -r -s -h {q}\\* /s /d >nul 2>&1 & rmdir /s /q {q} >nul 2>&1 & ping -n 2 127.0.0.1 >nul))";
        try
        {
            Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "cmd.exe"), cmd)
            {
                UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Path.GetTempPath(),
            });
        }
        catch { }
    }

    /// <summary>Explorer'da SyHost klasörünü seçili göster ("artık silebilirsin").</summary>
    public static void ShowFolder(string root)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + root.TrimEnd('\\') + "\"") { UseShellExecute = true }); } catch { }
    }
}
