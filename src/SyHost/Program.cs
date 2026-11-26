// =====================================================================
//  SyHost - Modlu Minecraft sunucu merkezi (C# sürümü)
//  Modrinth paketlerinden (.mrpack) sunucu kurar, açar ve yönetir.
//
//  Yapımcı : sykait
//  Lisans  : LICENSE.md (kullanırsan kredi vermek zorunlu)
// =====================================================================
using System.Diagnostics;

namespace SyHost;

static class Program
{
    static int Main(string[] args)
    {
        // Test modu: tek bir kareyi dosyaya yaz (iki sürümün ekranlarını karşılaştırmak için)
        if (args.Length >= 3 && args[0] == "--frame")
            return App.RunFrameTest(args[1], args[2], ArgValue(args, "--root") ?? Path.GetDirectoryName(Path.GetFullPath(args[1])));
        // Gizli öz denetim komutları (geliştirme ve otomatik testler)
        if (args.Length >= 2 && args[0] == "--selftest")
            return SelfTest.Run(args);

        bool hosted = HasArg(args, "--hosted");

        // Pencere gizleme, küçük mod ve taşıma yalnızca klasik konsol penceresinde (conhost) çalışır.
        // Windows Terminal'de açıldıysak kendimizi conhost'ta yeniden aç.
        if (!hosted && !Native.IsConhost())
        {
            Launch(Environment.ProcessPath, args);
            return 0;
        }

        string exe = Environment.ProcessPath;
        string root = ArgValue(args, "--root") ?? Path.GetDirectoryName(exe);
        bool installed = Portable.IsInstalled(root);

        // Kurulu klasöre yazılamıyorsa (ör. Program Files'a taşınmış) sessizce çökme, anlaşılır uyarı göster
        if (installed && !Portable.CanWrite(Path.Combine(root, Portable.DataName)))
        {
            Lang.Code = Portable.UiLanguage();
            Portable.Alert(Lang.L("SyHost bu klasöre yazamıyor:\n{0}\n\nSyHost.exe'yi yazılabilir bir klasöre taşı (ör. {1}) ve oradan aç.", root, Portable.DefaultRoot()));
            return 1;
        }

        // Tek kopya: ikinci kez açılırsa açık olan pencereyi öne getir
        var app = new App(root) { SetupMode = !installed, NoSplash = HasArg(args, "--no-splash") };
        // Terminal sürümüyle aynı kilit: iki sürüm aynı anda açılamaz (aynı verileri kullanırlar)
        string mutexName = @"Local\SyHostSunucuMerkezi" + (App.Title == "SyHost" ? "" : "-" + App.Title);
        using (var mutex = new Mutex(true, mutexName, out bool created))
        {
            if (!created)
            {
                Native.FocusWindow(App.Title);
                return 0;
            }
            try { app.Run(); }
            finally { try { mutex.ReleaseMutex(); } catch { } }
        }

        // Kurulum/güncelleme bitti: SyHost'u yeni yerinden aç (animasyon tekrar oynamasın)
        if (app.LaunchAfterExit != null) Launch(app.LaunchAfterExit, new[] { "--no-splash" });
        else if (app.RestartApp) Launch(exe, args);
        // Kaldır: SyHost kapandıktan sonra klasörü sil
        if (app.DeleteRootAfterExit) Uninstall.DeleteFolderAfterExit(root);
        return 0;
    }

    /// <summary>Bir SyHost.exe'yi klasik konsol penceresinde (conhost) aç.</summary>
    public static void Launch(string exe, string[] args)
    {
        var rest = new List<string>();
        foreach (string a in args) if (a != "--hosted") rest.Add(a.Contains(' ') ? "\"" + a + "\"" : a);
        var psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "conhost.exe"), $"\"{exe}\" --hosted {string.Join(' ', rest)}".TrimEnd())
        {
            UseShellExecute = true,
            WorkingDirectory = Path.GetDirectoryName(exe),
        };
        try { Process.Start(psi); } catch { }
    }

    static bool HasArg(string[] args, string name) => Array.IndexOf(args, name) >= 0;

    static string ArgValue(string[] args, string name)
    {
        int i = Array.IndexOf(args, name);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }
}
