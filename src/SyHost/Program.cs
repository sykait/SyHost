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

        bool hosted = Array.IndexOf(args, "--hosted") >= 0;

        // Pencere gizleme, küçük mod ve taşıma yalnızca klasik konsol penceresinde (conhost) çalışır.
        // Windows Terminal'de açıldıysak kendimizi conhost'ta yeniden aç.
        if (!hosted && !Native.IsConhost())
        {
            Relaunch(args);
            return 0;
        }

        string root = ArgValue(args, "--root") ?? AppContext.BaseDirectory;

        // Tek kopya: ikinci kez açılırsa açık olan pencereyi öne getir
        using var mutex = new Mutex(true, @"Local\SyHostSunucuMerkezi", out bool created);
        if (!created)
        {
            Native.FocusWindow(App.Title);
            return 0;
        }

        var app = new App(root);
        try { app.Run(); }
        finally { try { mutex.ReleaseMutex(); } catch { } }

        if (app.RestartApp) Relaunch(args);
        return 0;
    }

    /// <summary>SyHost'u klasik konsol penceresinde (conhost) yeniden aç.</summary>
    public static void Relaunch(string[] args)
    {
        var rest = new List<string>();
        foreach (string a in args) if (a != "--hosted") rest.Add(a.Contains(' ') ? "\"" + a + "\"" : a);
        string exe = Environment.ProcessPath;
        var psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "conhost.exe"), $"\"{exe}\" --hosted {string.Join(' ', rest)}".TrimEnd())
        {
            UseShellExecute = true,
            WorkingDirectory = Path.GetDirectoryName(exe),
        };
        try { Process.Start(psi); } catch { }
    }

    static string ArgValue(string[] args, string name)
    {
        int i = Array.IndexOf(args, name);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }
}
