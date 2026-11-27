// SyHost - tasinabilir klasor icin yardimci kod (PowerShell tarafindan SyHost.Core.cs ile birlikte derlenir)
// Yalnizca Windows'a dokunan parcalar burada; kararlar Portable.ps1'de. C# surumundeki karsiliklari:
//   Portable    src\SyHost\Setup\Portable.cs (Downloads, CopyExe, ShowDir, IsInside, Alert), Fonts.cs (yazi tipi kaydi),
//               Core\Native.Dialogs.cs (PickFolder), Core\Native.cs (SetWindowIcon)
//   ShellLink   src\SyHost\Setup\Shortcuts.cs (IShellLinkW ile okuma/yazma)
//   FolderLook  src\SyHost\Setup\FolderLook.cs (desktop.ini, simgeler, SHChangeNotify)
// C# 5 (.NET Framework 4 derleyicisi): $"", =>, ?. ve out var yok.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace SyHost
{
    public static class Portable
    {
        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();

        // ---------- Indirilenler klasoru ----------
        [DllImport("shell32.dll")] static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid id, uint flags, IntPtr token, out IntPtr path);

        public static string Downloads()
        {
            IntPtr p = IntPtr.Zero;
            try
            {
                if (SHGetKnownFolderPath(new Guid("374DE290-123F-4565-9164-39C4925E467B"), 0, IntPtr.Zero, out p) == 0 && p != IntPtr.Zero)
                    return Marshal.PtrToStringUni(p);
            }
            catch { }
            finally { if (p != IntPtr.Zero) Marshal.FreeCoTaskMem(p); }
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        }

        // ---------- Dosyayi yerine koy (C#: File.Move(kaynak, hedef, true)) ----------
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "MoveFileExW")]
        static extern bool MoveFileEx(string from, string to, uint flags);

        /// Hedef varsa ustune yazar. Hedef kilitliyse (ornegin calisan SyHost.exe) her zaman IOException firlatir.
        public static void MoveReplace(string from, string to)
        {
            if (MoveFileEx(from, to, 0x1 | 0x2)) return;   // MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED
            int err = Marshal.GetLastWin32Error();
            throw new IOException(new System.ComponentModel.Win32Exception(err).Message + " " + to, unchecked((int)0x80070000) | err);
        }

        // Klasor gizliyse gorunur yap: Data gizli degildir (icinde indirilen programlar da durur; C#: Portable.ShowDir)
        public static void ShowDir(string dir)
        {
            try
            {
                DirectoryInfo di = new DirectoryInfo(dir);
                if (di.Exists && (di.Attributes & FileAttributes.Hidden) != 0) di.Attributes &= ~FileAttributes.Hidden;
            }
            catch { }
        }

        /// Bir yol SyHost klasorunun icinde mi? (klasorun kendisi de icinde sayilir)
        public static bool IsInside(string path, string root)
        {
            try
            {
                string p = Path.GetFullPath(path).TrimEnd('\\') + "\\";
                string r = Path.GetFullPath(root).TrimEnd('\\') + "\\";
                return p.StartsWith(r, StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        // ---------- Uyari penceresi (konsol cizilmeden once, ornegin klasore yazilamiyor) ----------
        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "MessageBoxW")]
        static extern int MessageBox(IntPtr h, string text, string caption, uint type);

        public static void Alert(string text) { MessageBox(GetConsoleWindow(), text, "SyHost", 0x30 | 0x10000); }   // MB_ICONWARNING | MB_SETFOREGROUND

        // ---------- Pencere ve gorev cubugu simgesi ----------
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "ExtractIconExW")]
        static extern uint ExtractIconEx(string file, int index, out IntPtr large, out IntPtr small, uint count);
        [DllImport("user32.dll", EntryPoint = "SendMessageW")]
        static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);

        /// file: simgesi alinacak exe ya da .ico (C# surumu kendi exe'sini kullanir)
        public static void SetWindowIcon(string file)
        {
            try
            {
                if (string.IsNullOrEmpty(file)) return;
                IntPtr large, small;
                if (ExtractIconEx(file, 0, out large, out small, 1) == 0) return;
                IntPtr h = GetConsoleWindow();
                if (large != IntPtr.Zero) SendMessage(h, 0x0080, new IntPtr(1), large);   // WM_SETICON, ICON_BIG
                if (small != IntPtr.Zero) SendMessage(h, 0x0080, IntPtr.Zero, small);     // WM_SETICON, ICON_SMALL
            }
            catch { }
        }

        // ---------- Yazi tipi (kullaniciya kurulum, yonetici izni gerekmez) ----------
        [DllImport("gdi32.dll", CharSet = CharSet.Unicode, EntryPoint = "AddFontResourceW")] static extern int AddFontResourceW(string file);
        [DllImport("gdi32.dll", CharSet = CharSet.Unicode, EntryPoint = "RemoveFontResourceW")] static extern bool RemoveFontResourceW(string file);
        [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
        static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);

        public static int AddFont(string file) { return AddFontResourceW(file); }
        public static bool RemoveFont(string file) { return RemoveFontResourceW(file); }
        /// Butun pencerelere "yazi tipleri degisti" de (WM_FONTCHANGE, SMTO_ABORTIFHUNG, 1 sn)
        public static void FontsChanged() { try { IntPtr r; SendMessageTimeout(new IntPtr(0xffff), 0x001D, IntPtr.Zero, IntPtr.Zero, 2, 1000, out r); } catch { } }

        // ---------- Explorer'a "klasor degisti" de ----------
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern void SHChangeNotify(int eventId, uint flags, string item1, IntPtr item2);

        internal static void DirChanged(string dir) { SHChangeNotify(0x00001000, 0x0005 | 0x1000, dir, IntPtr.Zero); }   // SHCNE_UPDATEDIR, SHCNF_PATHW | SHCNF_FLUSH

        // ---------- Klasor secme penceresi (Windows'un modern secicisi: IFileOpenDialog + FOS_PICKFOLDERS) ----------
        [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")] class FileOpenDialogCo { }

        // Sanal tablodaki sira onemli: IUnknown (0-2), IModalWindow.Show (3), IFileDialog (4-20, gerisi kullanilmiyor)
        [ComImport, Guid("D57C7288-D4AD-4768-BE02-9D969532D960"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IFileOpenDialog
        {
            [PreserveSig] int Show(IntPtr parent);
            [PreserveSig] int SetFileTypes(uint count, IntPtr specs);
            [PreserveSig] int SetFileTypeIndex(uint index);
            [PreserveSig] int GetFileTypeIndex(out uint index);
            [PreserveSig] int Advise(IntPtr events, out uint cookie);
            [PreserveSig] int Unadvise(uint cookie);
            [PreserveSig] int SetOptions(uint options);
            [PreserveSig] int GetOptions(out uint options);
            [PreserveSig] int SetDefaultFolder(IShellItem item);
            [PreserveSig] int SetFolder(IShellItem item);
            [PreserveSig] int GetFolder(out IShellItem item);
            [PreserveSig] int GetCurrentSelection(out IShellItem item);
            [PreserveSig] int SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
            [PreserveSig] int GetFileName(out IntPtr name);
            [PreserveSig] int SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
            [PreserveSig] int SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string text);
            [PreserveSig] int SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string text);
            [PreserveSig] int GetResult(out IShellItem item);
        }

        [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellItem
        {
            [PreserveSig] int BindToHandler(IntPtr bc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
            [PreserveSig] int GetParent(out IShellItem parent);
            [PreserveSig] int GetDisplayName(uint sigdn, out IntPtr name);
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHCreateItemFromParsingName(string path, IntPtr bc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, [MarshalAs(UnmanagedType.Interface)] out IShellItem item);

        /// Klasor secme penceresi (konsol penceresinin onunde acilir). initialDir yoksa var olan en yakin ust klasorden baslar.
        /// Secilen klasorun tam yolu; vazgecilirse null.
        public static string PickFolder(string title, string initialDir)
        {
            string result = null;
            Thread t = new Thread(delegate () { try { result = PickFolderSta(title, initialDir); } catch { } });
            t.SetApartmentState(ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
            t.Join();
            return result;
        }

        static string PickFolderSta(string title, string initialDir)
        {
            const uint FOS_PICKFOLDERS = 0x20, FOS_FORCEFILESYSTEM = 0x40, FOS_PATHMUSTEXIST = 0x800;
            const uint SIGDN_FILESYSPATH = 0x80058000;
            IFileOpenDialog dlg = null;
            IShellItem folder = null, item = null;
            IntPtr path = IntPtr.Zero;
            try
            {
                dlg = (IFileOpenDialog)new FileOpenDialogCo();
                uint options;
                dlg.GetOptions(out options);
                dlg.SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
                if (!string.IsNullOrEmpty(title)) dlg.SetTitle(title);
                string start = ExistingDir(initialDir);
                if (start != null && SHCreateItemFromParsingName(start, IntPtr.Zero, typeof(IShellItem).GUID, out folder) >= 0 && folder != null)
                    dlg.SetFolder(folder);
                // Kullanici kapatana kadar bekler; vazgecilirse HRESULT_FROM_WIN32(ERROR_CANCELLED) doner
                if (dlg.Show(GetConsoleWindow()) < 0) return null;
                if (dlg.GetResult(out item) < 0 || item == null) return null;
                if (item.GetDisplayName(SIGDN_FILESYSPATH, out path) < 0 || path == IntPtr.Zero) return null;
                return Marshal.PtrToStringUni(path);
            }
            finally
            {
                if (path != IntPtr.Zero) Marshal.FreeCoTaskMem(path);
                if (item != null) Marshal.ReleaseComObject(item);
                if (folder != null) Marshal.ReleaseComObject(folder);
                if (dlg != null) Marshal.ReleaseComObject(dlg);
            }
        }

        /// Baslangic klasoru: verilen klasor yoksa var olan en yakin ust klasoru.
        static string ExistingDir(string dir)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(dir)) return null;
                string d = Path.GetFullPath(Environment.ExpandEnvironmentVariables(dir.Trim()));
                while (!string.IsNullOrEmpty(d) && !Directory.Exists(d)) d = Path.GetDirectoryName(d);
                return string.IsNullOrEmpty(d) ? null : d;
            }
            catch { return null; }
        }
    }

    /// Kisayol (.lnk) okuma ve yazma: Windows'un kendi kisayol nesnesi (IShellLinkW + IPersistFile)
    public static class ShellLink
    {
        [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class ShellLinkCo { }

        // Sanal tablo sirasi: 3 GetPath, 7 SetDescription, 8 GetWorkingDirectory, 9 SetWorkingDirectory,
        // 10 GetArguments, 11 SetArguments, 16 GetIconLocation, 17 SetIconLocation, 20 SetPath
        [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellLinkW
        {
            [PreserveSig] int GetPath([MarshalAs(UnmanagedType.LPWStr)] StringBuilder file, int cch, IntPtr findData, uint flags);
            [PreserveSig] int GetIDList(out IntPtr pidl);
            [PreserveSig] int SetIDList(IntPtr pidl);
            [PreserveSig] int GetDescription([MarshalAs(UnmanagedType.LPWStr)] StringBuilder name, int cch);
            [PreserveSig] int SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
            [PreserveSig] int GetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] StringBuilder dir, int cch);
            [PreserveSig] int SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string dir);
            [PreserveSig] int GetArguments([MarshalAs(UnmanagedType.LPWStr)] StringBuilder args, int cch);
            [PreserveSig] int SetArguments([MarshalAs(UnmanagedType.LPWStr)] string args);
            [PreserveSig] int GetHotkey(out short key);
            [PreserveSig] int SetHotkey(short key);
            [PreserveSig] int GetShowCmd(out int cmd);
            [PreserveSig] int SetShowCmd(int cmd);
            [PreserveSig] int GetIconLocation([MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int cch, out int index);
            [PreserveSig] int SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
            [PreserveSig] int SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
            [PreserveSig] int Resolve(IntPtr hwnd, uint flags);
            [PreserveSig] int SetPath([MarshalAs(UnmanagedType.LPWStr)] string file);
        }

        // IPersistFile sanal tablosu: 5 Load, 6 Save
        [ComImport, Guid("0000010b-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IPersistFile
        {
            [PreserveSig] int GetClassID(out Guid clsid);
            [PreserveSig] int IsDirty();
            [PreserveSig] int Load([MarshalAs(UnmanagedType.LPWStr)] string file, int mode);
            [PreserveSig] int Save([MarshalAs(UnmanagedType.LPWStr)] string file, [MarshalAs(UnmanagedType.Bool)] bool remember);
            [PreserveSig] int SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string file);
            [PreserveSig] int GetCurFile(out IntPtr file);
        }

        /// Kisayolun ici: [0] hedef, [1] argumanlar, [2] calisma klasoru, [3] simge. Yoksa ya da okunamazsa null.
        public static string[] Read(string lnk)
        {
            if (!File.Exists(lnk)) return null;
            string[] result = null;
            Sta(delegate ()
            {
                object o = null;
                try
                {
                    o = new ShellLinkCo();
                    IShellLinkW sl = (IShellLinkW)o;
                    if (((IPersistFile)o).Load(lnk, 0) < 0) return;   // STGM_READ
                    StringBuilder b = new StringBuilder(1024);
                    sl.GetPath(b, 1024, IntPtr.Zero, 0x4); string target = b.ToString();   // SLGP_RAWPATH
                    b = new StringBuilder(1024); sl.GetArguments(b, 1024); string args = b.ToString();
                    b = new StringBuilder(1024); sl.GetWorkingDirectory(b, 1024); string dir = b.ToString();
                    int idx; b = new StringBuilder(1024); sl.GetIconLocation(b, 1024, out idx); string icon = b.ToString();
                    result = new string[] { target, args, dir, icon };
                }
                finally { if (o != null) Marshal.FinalReleaseComObject(o); }
            });
            return result;
        }

        /// Kisayolu olustur ya da ustune yaz. Kaydedildiyse true.
        public static bool Write(string lnk, string target, string args, string workDir, string description, string iconPath, int iconIndex)
        {
            bool ok = false;
            Sta(delegate ()
            {
                object o = null;
                try
                {
                    o = new ShellLinkCo();
                    IShellLinkW sl = (IShellLinkW)o;
                    sl.SetPath(target);
                    sl.SetArguments(args ?? "");
                    sl.SetWorkingDirectory(workDir ?? "");
                    sl.SetDescription(description ?? "");
                    sl.SetIconLocation(iconPath ?? "", iconIndex);
                    ok = ((IPersistFile)o).Save(lnk, true) >= 0;
                }
                finally { if (o != null) Marshal.FinalReleaseComObject(o); }
            });
            return ok;
        }

        /// COM isini STA is parcaciginda yap (kabuk nesneleri bunu ister). PowerShell'in ana is parcacigi zaten STA.
        static void Sta(ThreadStart a)
        {
            if (Thread.CurrentThread.GetApartmentState() == ApartmentState.STA) { a(); return; }
            Exception err = null;
            Thread t = new Thread(delegate () { try { a(); } catch (Exception e) { err = e; } });
            t.SetApartmentState(ApartmentState.STA);
            t.Start(); t.Join();
            if (err != null) throw err;
        }
    }

    /// Klasorlerin Explorer'daki gorunumu: desktop.ini ile simge ve secilen dilde ad (diskteki ad hic degismez).
    /// Simge yollari goreli: klasor tasinsa da simgeler yerinde kalir. Yalnizca SyHost klasorunun ICINE yazar.
    public static class FolderLook
    {
        static readonly string[] IconNames = { "folder-syhost.ico", "folder-servers.ico", "folder-server.ico", "folder-backups.ico" };

        /// iconSource: simgelerin bulundugu klasor (App\icons ya da repodaki src\SyHost\Assets\icons); yoksa null.
        /// serversName, backupsName: "Servers" ve "yedekler" klasorlerinin secilen dildeki adi.
        public static void Apply(string root, string iconSource, string serversName, string backupsName, string[] serverDirs)
        {
            try
            {
                string data = Path.Combine(root, "Data");
                string icons = Path.Combine(data, "icons");
                Directory.CreateDirectory(icons);
                foreach (string n in IconNames) CopyIcon(iconSource, n, Path.Combine(icons, n));
                Portable.ShowDir(data);

                Write(root, Path.Combine(icons, "folder-syhost.ico"), null);
                string servers = Path.Combine(root, "Servers");
                if (Directory.Exists(servers)) Write(servers, Path.Combine(icons, "folder-servers.ico"), serversName);
                if (serverDirs == null) return;
                foreach (string dir in serverDirs)
                {
                    if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir) || !Portable.IsInside(dir, root)) continue;
                    Write(dir, Path.Combine(icons, "folder-server.ico"), null);
                    string bak = Path.Combine(dir, "yedekler");
                    if (Directory.Exists(bak)) Write(bak, Path.Combine(icons, "folder-backups.ico"), backupsName);
                }
            }
            catch { }
        }

        /// Apply'i arka planda calistir (acilisi bekletmesin)
        public static Task ApplyAsync(string root, string iconSource, string serversName, string backupsName, string[] serverDirs)
        {
            string[] dirs = serverDirs == null ? new string[0] : (string[])serverDirs.Clone();
            return Task.Run(delegate () { Apply(root, iconSource, serversName, backupsName, dirs); });
        }

        // C#: exe'ye gomulu simge Data\icons'a cikarilir (ayni boyda dosya varsa dokunulmaz)
        static void CopyIcon(string sourceDir, string name, string path)
        {
            try
            {
                if (string.IsNullOrEmpty(sourceDir)) return;
                string src = Path.Combine(sourceDir, name);
                if (!File.Exists(src)) return;
                if (File.Exists(path) && new FileInfo(path).Length == new FileInfo(src).Length) return;
                File.Copy(src, path, true);
            }
            catch { }
        }

        /// Bir klasorun desktop.ini'sini yaz (degismediyse dokunma).
        static void Write(string dir, string iconFile, string displayName)
        {
            try
            {
                bool hasIcon = File.Exists(iconFile);
                if (!hasIcon && string.IsNullOrEmpty(displayName)) return;
                StringBuilder sb = new StringBuilder();
                sb.Append("[.ShellClassInfo]\r\n");
                if (!string.IsNullOrEmpty(displayName)) sb.Append("LocalizedResourceName=").Append(displayName).Append("\r\n");
                if (hasIcon) sb.Append("IconResource=").Append(RelativePath(dir, iconFile)).Append(",0\r\n");
                string ini = Path.Combine(dir, "desktop.ini");
                string text = sb.ToString();
                if (File.Exists(ini))
                {
                    try { if (File.ReadAllText(ini, Encoding.Unicode) == text) { EnsureAttributes(dir, ini); return; } } catch { }
                    File.SetAttributes(ini, FileAttributes.Normal);
                }
                File.WriteAllText(ini, text, Encoding.Unicode);   // UTF-16 + BOM: Japonca adlar icin sart
                EnsureAttributes(dir, ini);
                Portable.DirChanged(dir);
            }
            catch { }
        }

        static void EnsureAttributes(string dir, string ini)
        {
            File.SetAttributes(ini, FileAttributes.Hidden | FileAttributes.System);
            DirectoryInfo di = new DirectoryInfo(dir);
            if ((di.Attributes & FileAttributes.ReadOnly) == 0) di.Attributes |= FileAttributes.ReadOnly;   // Explorer desktop.ini'yi ancak boyle okur
        }

        /// C#'taki Path.GetRelativePath (.NET Framework'te yok): ayni koke sahip iki tam yol, buyuk-kucuk harf farksiz.
        /// Kokler farkliysa (baska surucu) tam yol doner.
        static string RelativePath(string fromDir, string path)
        {
            string fa = Path.GetFullPath(fromDir), fb = Path.GetFullPath(path);
            if (!string.Equals(Path.GetPathRoot(fa), Path.GetPathRoot(fb), StringComparison.OrdinalIgnoreCase)) return fb;
            string[] a = fa.TrimEnd('\\').Split('\\'), b = fb.TrimEnd('\\').Split('\\');
            int n = 0;
            while (n < a.Length && n < b.Length && string.Equals(a[n], b[n], StringComparison.OrdinalIgnoreCase)) n++;
            StringBuilder sb = new StringBuilder();
            for (int i = n; i < a.Length; i++) { if (sb.Length > 0) sb.Append('\\'); sb.Append(".."); }
            for (int i = n; i < b.Length; i++) { if (sb.Length > 0) sb.Append('\\'); sb.Append(b[i]); }
            return sb.Length == 0 ? "." : sb.ToString();
        }
    }
}
