// =====================================================================
//  SyHost - Masaüstü ve Başlat menüsü kısayolları
//  Windows'un kendi kısayol nesnesi (IShellLinkW) ile okur ve yazar.
//  Tek exe (NativeAOT) uyumlu: COM arayüzleri doğrudan vtable ile çağrılır.
//
//  Kurallar:
//  - "Bu klasörün kısayolu" = hedefinde bu SyHost.exe geçen kısayol.
//  - Gösterdiği SyHost artık yoksa (klasör taşınmış) kendiliğinden bu exe'ye çevrilir.
//  - Hâlâ çalışan başka bir SyHost'u gösteriyorsa dokunulmaz (kullanıcıya sorulur).
//  Test için SYHOST_SHORTCUT_DIR ortam değişkeni kısayolları başka bir klasöre yönlendirir.
// =====================================================================
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace SyHost;

static unsafe partial class Shortcuts
{
    public const string FileName = "SyHost.lnk";

    /// <summary>Kısayolun duracağı yerler: [0] Masaüstü, [1] Başlat menüsü (Programlar).</summary>
    public static string[] Locations()
    {
        string test = Environment.GetEnvironmentVariable("SYHOST_SHORTCUT_DIR");
        if (!string.IsNullOrEmpty(test))
            return new[] { Path.Combine(test, "Desktop", FileName), Path.Combine(test, "Programs", FileName) };
        return new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), FileName),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), FileName),
        };
    }

    public static string DesktopPath => Locations()[0];
    public static string StartMenuPath => Locations()[1];

    /// <summary>Kısayolun içi: hedef, argümanlar, çalışma klasörü, simge.</summary>
    public readonly record struct Info(string Target, string Args, string WorkDir, string Icon);

    /// <summary>Kısayolu oku (yoksa ya da okunamazsa null).</summary>
    public static Info? Read(string lnk)
    {
        if (!File.Exists(lnk)) return null;
        Info? result = null;
        Sta(() =>
        {
            nint sl = Create(); if (sl == 0) return;
            nint pf = 0;
            try
            {
                pf = Query(sl, IID_IPersistFile); if (pf == 0) return;
                var load = (delegate* unmanaged[Stdcall]<nint, char*, uint, int>)Slot(pf, 5);
                fixed (char* p = lnk) if (load(pf, p, 0) < 0) return;
                char* buf = stackalloc char[1024];
                var getPath = (delegate* unmanaged[Stdcall]<nint, char*, int, nint, uint, int>)Slot(sl, 3);
                var getStr = (delegate* unmanaged[Stdcall]<nint, char*, int, int>)null;
                buf[0] = '\0'; getPath(sl, buf, 1024, 0, 0x4); string target = new string(buf);
                getStr = (delegate* unmanaged[Stdcall]<nint, char*, int, int>)Slot(sl, 10);
                buf[0] = '\0'; getStr(sl, buf, 1024); string args = new string(buf);
                getStr = (delegate* unmanaged[Stdcall]<nint, char*, int, int>)Slot(sl, 8);
                buf[0] = '\0'; getStr(sl, buf, 1024); string dir = new string(buf);
                var getIcon = (delegate* unmanaged[Stdcall]<nint, char*, int, int*, int>)Slot(sl, 16);
                int idx = 0; buf[0] = '\0'; getIcon(sl, buf, 1024, &idx); string icon = new string(buf);
                result = new Info(target, args, dir, icon);
            }
            finally { Release(pf); Release(sl); }
        });
        return result;
    }

    /// <summary>Kısayolu oluştur ya da üzerine yaz: SyHost'u klasik konsol penceresinde (conhost) açar, simgesi exe'den gelir.</summary>
    public static bool Write(string lnk, string exe, string description)
    {
        bool ok = false;
        string conhost = Path.Combine(Environment.SystemDirectory, "conhost.exe");
        string args = "\"" + exe + "\" --hosted";
        string dir = Path.GetDirectoryName(exe);
        Directory.CreateDirectory(Path.GetDirectoryName(lnk));
        Sta(() =>
        {
            nint sl = Create(); if (sl == 0) return;
            nint pf = 0;
            try
            {
                var setStr = (delegate* unmanaged[Stdcall]<nint, char*, int>)Slot(sl, 20);   // SetPath
                fixed (char* p = conhost) setStr(sl, p);
                setStr = (delegate* unmanaged[Stdcall]<nint, char*, int>)Slot(sl, 11);       // SetArguments
                fixed (char* p = args) setStr(sl, p);
                setStr = (delegate* unmanaged[Stdcall]<nint, char*, int>)Slot(sl, 9);        // SetWorkingDirectory
                fixed (char* p = dir) setStr(sl, p);
                setStr = (delegate* unmanaged[Stdcall]<nint, char*, int>)Slot(sl, 7);        // SetDescription
                fixed (char* p = description ?? "") setStr(sl, p);
                var setIcon = (delegate* unmanaged[Stdcall]<nint, char*, int, int>)Slot(sl, 17);
                fixed (char* p = exe) setIcon(sl, p, 0);
                pf = Query(sl, IID_IPersistFile); if (pf == 0) return;
                var save = (delegate* unmanaged[Stdcall]<nint, char*, int, int>)Slot(pf, 6);
                fixed (char* p = lnk) ok = save(pf, p, 1) >= 0;
            }
            finally { Release(pf); Release(sl); }
        });
        return ok;
    }

    static readonly Regex SyHostRx = new("\"?([^\"]*?(?:SyHost[^\"\\\\]*\\.exe|SyHost\\.ps1))\"?", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// <summary>Kısayolun açtığı SyHost'un yolu (exe ya da eski sürümün SyHost.ps1'i). SyHost kısayolu değilse null.</summary>
    public static string SyHostPathOf(Info i)
    {
        foreach (string s in new[] { i.Args ?? "", i.Target ?? "" })
        {
            var m = SyHostRx.Match(s);
            if (m.Success) return m.Groups[1].Value.Trim();
        }
        return null;
    }

    public enum State { Missing, Ours, Dead, OtherLive, Foreign }

    /// <summary>Bir kısayolun bu exe'ye göre durumu.</summary>
    public static State StateOf(string lnk, string exe)
    {
        var i = Read(lnk);
        if (i == null) return File.Exists(lnk) ? State.Foreign : State.Missing;
        string p = SyHostPathOf(i.Value);
        if (p == null) return State.Foreign;
        try { if (string.Equals(Path.GetFullPath(p), Path.GetFullPath(exe), StringComparison.OrdinalIgnoreCase)) return State.Ours; } catch { }
        return File.Exists(p) ? State.OtherLive : State.Dead;
    }

    /// <summary>
    /// Bu exe'yi doğrudan açan kısayollarımızı (Terminal sürümü SyHost.exe'yi böyle açar) conhost biçimine çevir:
    /// klasör sürümler arasında değiştirildiyse kısayol yine doğru pencerede açılsın. Değişen sayısını döner.
    /// </summary>
    public static int Normalize(string exe, string description)
    {
        int n = 0;
        string conhost = Path.Combine(Environment.SystemDirectory, "conhost.exe");
        foreach (string lnk in Locations())
        {
            try
            {
                var i = Read(lnk);
                if (i == null || StateOf(lnk, exe) != State.Ours) continue;
                if (!string.Equals(i.Value.Target, conhost, StringComparison.OrdinalIgnoreCase) && Write(lnk, exe, description)) n++;
            }
            catch { }
        }
        return n;
    }

    /// <summary>Taşınmış klasör: gösterdiği SyHost artık olmayan kısayolları bu exe'ye çevir. Değişen kısayol sayısını döner.</summary>
    public static int FixMoved(string exe, string description)
    {
        int n = 0;
        foreach (string lnk in Locations())
        {
            try { if (StateOf(lnk, exe) == State.Dead && Write(lnk, exe, description)) n++; } catch { }
        }
        return n;
    }

    /// <summary>Hâlâ duran başka bir SyHost (exe) kurulumunun klasörü; yoksa null.</summary>
    public static string FindOtherInstall(string exe)
    {
        foreach (string lnk in Locations())
        {
            try
            {
                var i = Read(lnk); if (i == null) continue;
                string p = SyHostPathOf(i.Value);
                if (p == null || !p.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) || !File.Exists(p)) continue;
                if (string.Equals(Path.GetFullPath(p), Path.GetFullPath(exe), StringComparison.OrdinalIgnoreCase)) continue;
                string root = Path.GetDirectoryName(p);
                if (Portable.IsInstalled(root)) return root;
            }
            catch { }
        }
        return null;
    }

    /// <summary>Yalnızca bu exe'yi gösteren kısayolları sil.</summary>
    public static int RemoveOurs(string exe)
    {
        int n = 0;
        foreach (string lnk in Locations())
        {
            try { if (StateOf(lnk, exe) == State.Ours) { File.Delete(lnk); n++; } } catch { }
        }
        return n;
    }

    // ---------- COM ayrıntıları ----------
    // IShellLinkW vtable: 3 GetPath, 7 SetDescription, 8 GetWorkingDirectory, 9 SetWorkingDirectory,
    // 10 GetArguments, 11 SetArguments, 16 GetIconLocation, 17 SetIconLocation, 20 SetPath
    // IPersistFile vtable: 5 Load, 6 Save
    static readonly Guid CLSID_ShellLink = new("00021401-0000-0000-C000-000000000046");
    static readonly Guid IID_IShellLinkW = new("000214F9-0000-0000-C000-000000000046");
    static readonly Guid IID_IPersistFile = new("0000010b-0000-0000-C000-000000000046");

    [LibraryImport("ole32.dll")] private static partial int CoCreateInstance(Guid* clsid, nint outer, uint ctx, Guid* iid, nint* obj);

    static nint Slot(nint obj, int slot) => (*(nint**)obj)[slot];

    static nint Create()
    {
        Guid c = CLSID_ShellLink, i = IID_IShellLinkW; nint p;
        return CoCreateInstance(&c, 0, 1, &i, &p) >= 0 ? p : 0;
    }

    static nint Query(nint obj, Guid iid)
    {
        nint p;
        var qi = (delegate* unmanaged[Stdcall]<nint, Guid*, nint*, int>)Slot(obj, 0);
        return qi(obj, &iid, &p) >= 0 ? p : 0;
    }

    static void Release(nint obj)
    {
        if (obj == 0) return;
        var rel = (delegate* unmanaged[Stdcall]<nint, uint>)Slot(obj, 2);
        rel(obj);
    }

    /// <summary>COM işini STA iş parçacığında yap (kabuk nesneleri bunu ister).</summary>
    static void Sta(Action a)
    {
        Exception err = null;
        var t = new Thread(() => { try { a(); } catch (Exception e) { err = e; } });
        t.SetApartmentState(ApartmentState.STA);
        t.Start(); t.Join();
        if (err != null) throw err;
    }
}
