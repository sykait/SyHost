// =====================================================================
//  SyHost - gizli öz denetim komutları (geliştirme ve otomatik testler için)
//    SyHost.exe --selftest shortcuts <klasör>
//    SyHost.exe --selftest folderlook <SyHost klasörü> <dil>
//    SyHost.exe --selftest migration <eski veri kopyası> <SyHost klasörü>
//    SyHost.exe --selftest paths <klasör>
//    SyHost.exe --selftest uninstall <SyHost klasörü> [<silinecek deneme klasörü>]   (Uninstall.SelfTest; deneme modunda)
//  Kullanıcının gerçek kısayollarına ve verilerine dokunmaz: hepsi verilen klasörlerde çalışır.
// =====================================================================
namespace SyHost;

static class SelfTest
{
    public static int Run(string[] args)
    {
        string what = args.Length > 1 ? args[1] : "";
        try
        {
            switch (what)
            {
                case "shortcuts": return TestShortcuts(args[2]);
                case "folderlook": return TestFolderLook(args[2], args.Length > 3 ? args[3] : "tr");
                case "migration": return TestMigration(args[2], args[3]);
                case "paths": return TestPaths(args[2]);
                case "uninstall": return Uninstall.SelfTest(args[2], args.Length > 3 ? args[3] : null);
                default: Console.WriteLine("bilinmeyen test: " + what); return 2;
            }
        }
        catch (Exception e) { Console.WriteLine("HATA: " + e); return 1; }
    }

    static int Check(bool ok, string what) { Console.WriteLine((ok ? "ok    " : "HATA  ") + what); return ok ? 0 : 1; }

    static int TestShortcuts(string dir)
    {
        Environment.SetEnvironmentVariable("SYHOST_SHORTCUT_DIR", dir);
        int fail = 0;
        string a = Path.Combine(dir, "A", "SyHost.exe"), b = Path.Combine(dir, "B", "SyHost.exe");
        Directory.CreateDirectory(Path.GetDirectoryName(a)); Directory.CreateDirectory(Path.GetDirectoryName(b));
        File.WriteAllText(a, "x"); File.WriteAllText(b, "x");
        string lnk = Shortcuts.DesktopPath;
        fail += Check(Shortcuts.Write(lnk, a, "SyHost test"), "kısayol yazıldı: " + lnk);
        var i = Shortcuts.Read(lnk);
        fail += Check(i != null, "kısayol okundu");
        if (i != null) Console.WriteLine($"      hedef={i.Value.Target}  argümanlar={i.Value.Args}  klasör={i.Value.WorkDir}  simge={i.Value.Icon}");
        fail += Check(Shortcuts.StateOf(lnk, a) == Shortcuts.State.Ours, "A için durum = Ours");
        fail += Check(Shortcuts.StateOf(lnk, b) == Shortcuts.State.OtherLive, "B için durum = OtherLive (A hâlâ duruyor)");
        File.Delete(a);
        fail += Check(Shortcuts.StateOf(lnk, b) == Shortcuts.State.Dead, "A silinince B için durum = Dead");
        fail += Check(Shortcuts.FixMoved(b, "SyHost test") >= 1, "FixMoved ölü kısayolu B'ye çevirdi");
        fail += Check(Shortcuts.StateOf(lnk, b) == Shortcuts.State.Ours, "artık B için durum = Ours");
        fail += Check(Shortcuts.RemoveOurs(b) >= 1 && !File.Exists(lnk), "RemoveOurs kısayolu sildi");
        Console.WriteLine(fail == 0 ? "SONUÇ: geçti" : $"SONUÇ: {fail} hata");
        return fail == 0 ? 0 : 1;
    }

    static int TestFolderLook(string root, string lang)
    {
        int fail = 0;
        string srv = Path.Combine(root, "Servers", "Deneme Sunucu");
        Directory.CreateDirectory(Path.Combine(srv, "yedekler"));
        Directory.CreateDirectory(Path.Combine(root, "Data"));
        FolderLook.Apply(root, lang, new[] { srv });
        foreach (string d in new[] { root, Path.Combine(root, "Servers"), srv, Path.Combine(srv, "yedekler") })
        {
            string ini = Path.Combine(d, "desktop.ini");
            fail += Check(File.Exists(ini), "desktop.ini: " + d);
            if (File.Exists(ini)) Console.WriteLine("      " + File.ReadAllText(ini, System.Text.Encoding.Unicode).Replace("\r\n", " | "));
        }
        fail += Check((new DirectoryInfo(Path.Combine(root, "Data")).Attributes & FileAttributes.Hidden) != 0, "Data gizli");
        Console.WriteLine(fail == 0 ? "SONUÇ: geçti" : $"SONUÇ: {fail} hata");
        return fail == 0 ? 0 : 1;
    }

    static int TestMigration(string legacy, string root)
    {
        Environment.SetEnvironmentVariable("SYHOST_LEGACY_DATA", legacy);
        int fail = 0;
        string data = Path.Combine(root, "Data");
        fail += Check(Migration.HasLegacyData(), "eski veri bulundu: " + legacy);
        fail += Check(Migration.DataIsFresh(data), "yeni Data boş");
        var r = Migration.Copy(data, root, "tr");
        Console.WriteLine("      kopyalanan: " + string.Join(", ", r.Copied) + $"  sunucu: {r.Servers}  playit: {r.Playit}");
        fail += Check(File.Exists(Path.Combine(legacy, Migration.NoteName)), "eski klasöre not bırakıldı");
        fail += Check(Migration.MovedTo() == root, "not okunuyor: " + Migration.MovedTo());
        try { var s = Json.ReadSettings(Path.Combine(data, "ayarlar.json")); Console.WriteLine($"      sunucu klasörü: {s.sunucuKokKlasoru}  dil: {s.dil}  kurulumTamam: {s.kurulumTamam}"); } catch { }
        Console.WriteLine(fail == 0 ? "SONUÇ: geçti" : $"SONUÇ: {fail} hata");
        return fail == 0 ? 0 : 1;
    }

    static int TestPaths(string dir)
    {
        Console.WriteLine("varsayılan kurulum yeri: " + Portable.DefaultRoot());
        Console.WriteLine("İndirilenler: " + Portable.Downloads());
        Console.WriteLine("Windows dili: " + Portable.UiLanguage());
        Console.WriteLine($"OneDrive mı ({dir}): " + Portable.IsInOneDrive(dir));
        Console.WriteLine($"OneDrive mı (Masaüstü): " + Portable.IsInOneDrive(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)));
        Console.WriteLine($"yazılabilir mi ({dir}): " + Portable.CanWrite(dir));
        Console.WriteLine($"yazılabilir mi (Program Files): " + Portable.CanWrite(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "SyHostDeneme")));
        Console.WriteLine($"kendi boş klasörü mü (İndirilenler): " + Portable.IsOwnEmptyFolder(Portable.Downloads(), Path.Combine(Portable.Downloads(), "SyHost.exe")));
        Console.WriteLine("Cascadia Mono kurulu mu: " + Fonts.IsAvailable());
        return 0;
    }
}
