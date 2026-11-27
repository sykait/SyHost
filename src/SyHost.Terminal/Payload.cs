// =====================================================================
//  SyHost - gömülü uygulama (Terminal sürümünün App klasörü)
//  Exe'nin içindeki dosyalar ("app\<göreli yol>" adlı kaynaklar) bir klasöre çıkarılır:
//    Kurulu klasörde: <SyHost>\App (gizli). Yalnızca içerik değişince yenilenir: önce App.new'a
//    çıkarılır, sonra App ile yer değiştirir; eski App değişim bitene kadar App.old olarak durur.
//    Data ve Servers'a hiç dokunulmaz.
//    Kurulum ekranında: %TEMP%\SyHost-Terminal-<karma>-<rastgele>. SyHost kapanınca silinir. Başlatıcı
//    yarıda kapatıldıysa (ör. süreç ağacı öldürüldü) bir sonraki açılış artığı temizler.
// =====================================================================
using System.Diagnostics;
using System.Reflection;
using System.Text;

namespace SyHost;

static class Payload
{
    const string Prefix = @"app\";
    public const string AppName = "App";
    public const string MarkerName = "version.txt";
    public const string TempPrefix = "SyHost-Terminal-";
    // Geçici klasörün sahibi (başlatıcı) açıkken tuttuğu dosya: temizleyici bunu silemezse klasör kullanımdadır
    const string LockName = ".kilit";
    // App bir an kilitliyse (ör. yeni kapanan PowerShell, virüs tarayıcı) en çok bu kadar yeniden denenir;
    // daha uzun kilitte kullanıcı beklemesin, sebebiyle birlikte hata görsün
    const int BusyMs = 4000;

    /// <summary>App\version.txt: sürüm ve gömülü dosyaların karması. Biri değişirse App yenilenir.</summary>
    public static readonly string Marker = PayloadInfo.Version + "\r\n" + PayloadInfo.Hash + "\r\n";

    static readonly Assembly Asm = typeof(Payload).Assembly;
    static List<(string Rel, string Res, long Size)> entries;

    /// <summary>Gömülü dosyalar: App içindeki göreli yol, kaynak adı ve boyut.</summary>
    static List<(string Rel, string Res, long Size)> Entries()
    {
        if (entries != null) return entries;
        var list = new List<(string Rel, string Res, long Size)>();
        foreach (string res in Asm.GetManifestResourceNames())
        {
            if (!res.StartsWith(Prefix, StringComparison.Ordinal)) continue;
            using Stream s = Asm.GetManifestResourceStream(res);
            list.Add((res.Substring(Prefix.Length), res, s.Length));
        }
        if (!list.Exists(e => e.Rel.Equals(@"src\SyHost.ps1", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidDataException("This SyHost.exe does not carry the app (src\\SyHost.ps1 is missing).");
        list.Sort((a, b) => string.CompareOrdinal(a.Rel, b.Rel));
        return entries = list;
    }

    /// <summary>Klasörde bu exe'nin uygulaması eksiksiz duruyor mu? (işaret dosyası + her dosyanın boyutu)</summary>
    public static bool IsCurrent(string app)
    {
        try
        {
            string marker = Path.Combine(app, MarkerName);
            if (!File.Exists(marker) || File.ReadAllText(marker) != Marker) return false;
            foreach (var e in Entries())
            {
                var fi = new FileInfo(Path.Combine(app, e.Rel));
                if (!fi.Exists || fi.Length != e.Size) return false;
            }
            return true;
        }
        catch { return false; }
    }

    /// <summary>Gömülü dosyaları (boş) bir klasöre yaz. İşaret dosyası en son: yarım kalan çıkarma güncel sayılmaz.</summary>
    public static void ExtractTo(string dir)
    {
        string full = Path.GetFullPath(dir).TrimEnd('\\') + "\\";
        foreach (var e in Entries())
        {
            string path = Path.GetFullPath(Path.Combine(full, e.Rel));
            if (!path.StartsWith(full, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Bad app file name: " + e.Rel);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            using Stream src = Asm.GetManifestResourceStream(e.Res) ?? throw new InvalidDataException("Missing app file: " + e.Rel);
            using var dst = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 1 << 16);
            src.CopyTo(dst);
        }
        File.WriteAllText(Path.Combine(full, MarkerName), Marker, Encoding.ASCII);
    }

    /// <summary>
    /// Kurulu klasör: &lt;root&gt;\App bu exe'nin uygulaması değilse yenile ve yolunu döndür.
    /// Aynı klasörü aynı anda hazırlayan iki başlatıcı (çift tıklama) birbirini beklesin diye kilitli.
    /// </summary>
    public static string Install(string root)
    {
        string app = Path.Combine(root, AppName), fresh = app + ".new", old = app + ".old";
        using (FolderLock.Take(root))
        {
            if (IsCurrent(app)) TestLog.Write("app current " + app);
            else
            {
                TestLog.Write("extract " + app);
                DeleteDir(fresh);   // yarıda kalmış bir önceki deneme
                Directory.CreateDirectory(fresh);
                Hide(fresh);
                try
                {
                    ExtractTo(fresh);
                    if (Directory.Exists(app))
                    {
                        DeleteDir(old);
                        Retry(() => Directory.Move(app, old));   // App içinde açık bir dosya varsa olmaz: App olduğu gibi kalır
                    }
                    try { Retry(() => Directory.Move(fresh, app)); }
                    catch
                    {
                        // Yeni uygulama yerine konamadı: eskisini geri koy, SyHost klasörü uygulamasız kalmasın
                        if (!Directory.Exists(app) && Directory.Exists(old)) { try { Directory.Move(old, app); } catch { } }
                        throw;
                    }
                }
                catch
                {
                    TryDeleteDir(fresh, 2000);
                    throw;
                }
                TestLog.Write("swapped " + app);
            }
            Hide(app);
            TryDeleteDir(old);
            TryDeleteDir(fresh);
        }
        return app;
    }

    /// <summary>Kurulum ekranı için %TEMP%'te yeni bir klasöre çıkar. Dispose klasörü siler.</summary>
    public static TempApp ExtractTemp()
    {
        string temp = Path.GetTempPath();
        for (int attempt = 0; ; attempt++)
        {
            string dir = Path.Combine(temp, TempPrefix + PayloadInfo.Hash.Substring(0, 12) + "-" + Random.Shared.Next().ToString("x8"));
            if (Directory.Exists(dir)) continue;
            Directory.CreateDirectory(dir);
            FileStream lk;
            // Kilit hemen: o ana kadar boş klasörü eşzamanlı bir temizleyici silmiş olabilir, o zaman yeni ad
            try { lk = new FileStream(Path.Combine(dir, LockName), FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) when (attempt < 5) { continue; }
            var t = new TempApp(dir, lk);
            try { ExtractTo(dir); }
            catch { t.Dispose(); throw; }
            TestLog.Write("temp " + dir);
            return t;
        }
    }

    public sealed class TempApp : IDisposable
    {
        public readonly string Dir;
        FileStream lockFile;

        public TempApp(string dir, FileStream lk) { Dir = dir; lockFile = lk; }

        public void Dispose()
        {
            if (lockFile == null) return;
            lockFile.Dispose();
            lockFile = null;
            // PowerShell yeni kapandıysa son dosyaları bir an daha tutabilir: bir süre yeniden dene
            if (TryDeleteDir(Dir, 10000)) TestLog.Write("temp deleted " + Dir);
            else TestLog.Write("temp left " + Dir);
        }
    }

    /// <summary>
    /// Önceki açılışlardan kalan geçici klasörleri sil (başlatıcı öldürüldüyse kendi klasörünü silemedi).
    /// Kullanımdakilere hiç dokunulmaz: sahibi (başlatıcı) açıksa kilit dosyasını, PowerShell açıksa yüklediği
    /// SyHost.Core.dll'i açık tutar; ikisi de özel olarak açılabiliyorsa klasör artıktır.
    /// </summary>
    public static void CleanStaleTemps()
    {
        try
        {
            foreach (string dir in Directory.EnumerateDirectories(Path.GetTempPath(), TempPrefix + "*"))
            {
                if (!Path.GetFileName(dir).StartsWith(TempPrefix, StringComparison.OrdinalIgnoreCase)) continue;
                try
                {
                    string lk = Path.Combine(dir, LockName);
                    if (InUse(lk) || InUse(Path.Combine(dir, "bin", "SyHost.Core.dll")))
                    {
                        TestLog.Write("stale temp in use " + dir);
                        continue;
                    }
                    // Kilidi henüz olmayan yeni bir klasörü başka bir başlatıcı şu an hazırlıyor olabilir
                    if (!File.Exists(lk) && DateTime.UtcNow - Directory.GetCreationTimeUtc(dir) < TimeSpan.FromMinutes(1)) continue;
                    Directory.Delete(dir, true);
                    TestLog.Write("stale temp deleted " + dir);
                }
                catch (Exception e) { TestLog.Write("stale temp kept " + dir + " (" + e.GetType().Name + ")"); }
            }
        }
        catch { }
    }

    /// <summary>Dosyayı başka bir süreç açık tutuyor mu? (yoksa false)</summary>
    static bool InUse(string file)
    {
        try
        {
            using (new FileStream(file, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) { }
            return false;
        }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
        catch (IOException) { return true; }                   // paylaşım ihlali: açık
        catch (UnauthorizedAccessException) { return true; }   // açılamıyor: dokunma
    }

    static void Hide(string dir)
    {
        try
        {
            var di = new DirectoryInfo(dir);
            if ((di.Attributes & FileAttributes.Hidden) == 0) di.Attributes |= FileAttributes.Hidden;
        }
        catch { }
    }

    /// <summary>Klasörü sil (yoksa bir şey yapma); kilitliyse bir süre yeniden dener, olmazsa hata.</summary>
    static void DeleteDir(string dir)
    {
        if (!TryDeleteDir(dir, BusyMs) && Directory.Exists(dir)) Directory.Delete(dir, true);   // son deneme: hatanın sebebi görünsün
    }

    static bool TryDeleteDir(string dir) => TryDeleteDir(dir, 0);

    static bool TryDeleteDir(string dir, int totalMs)
    {
        var sw = Stopwatch.StartNew();
        int wait = 50;
        while (true)
        {
            try
            {
                if (Directory.Exists(dir)) Directory.Delete(dir, true);
                return true;
            }
            catch (UnauthorizedAccessException) { ClearReadOnly(dir); }
            catch (IOException) { }
            if (sw.ElapsedMilliseconds >= totalMs) return false;
            Thread.Sleep(wait);
            wait = Math.Min(wait * 2, 500);
        }
    }

    static void ClearReadOnly(string dir)
    {
        try
        {
            foreach (string f in Directory.EnumerateFileSystemEntries(dir, "*", SearchOption.AllDirectories))
                try { File.SetAttributes(f, FileAttributes.Normal); } catch { }
        }
        catch { }
    }

    /// <summary>Taşıma: dosya bir an kilitliyse (ör. kapanmakta olan PowerShell, virüs tarayıcı) yeniden dene.</summary>
    static void Retry(Action a)
    {
        var sw = Stopwatch.StartNew();
        int wait = 50;
        while (true)
        {
            try { a(); return; }
            catch (Exception e) when ((e is IOException || e is UnauthorizedAccessException) && sw.ElapsedMilliseconds < BusyMs) { }
            Thread.Sleep(wait);
            wait = Math.Min(wait * 2, 500);
        }
    }

    /// <summary>Bir SyHost klasörü için başlatıcılar arası kilit (yalnızca App hazırlanırken tutulur).</summary>
    sealed class FolderLock : IDisposable
    {
        readonly Mutex m;

        FolderLock(Mutex m) { this.m = m; }

        public static FolderLock Take(string root)
        {
            string key = Path.GetFullPath(root).TrimEnd('\\').ToUpperInvariant();
            ulong h = 14695981039346656037;   // FNV-1a: yol mutex adında geçemez (\ yasak), karması geçer
            foreach (char ch in key) { h ^= ch; h *= 1099511628211; }
            var m = new Mutex(false, @"Local\SyHostBaslatici-" + h.ToString("x16"));
            try
            {
                if (!m.WaitOne(TimeSpan.FromSeconds(60))) { m.Dispose(); throw new TimeoutException("Another SyHost.exe is still preparing this folder."); }
            }
            catch (AbandonedMutexException) { }   // önceki başlatıcı yarıda kapandı: kilit artık bizde
            return new FolderLock(m);
        }

        public void Dispose()
        {
            try { m.ReleaseMutex(); } catch { }
            m.Dispose();
        }
    }
}
