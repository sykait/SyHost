// SyHost - yardimci kod (PowerShell tarafindan derlenir)
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace SyHost
{
    public static class Native
    {
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] static extern IntPtr GetSystemMenu(IntPtr h, bool revert);
        [DllImport("user32.dll")] static extern bool DeleteMenu(IntPtr m, uint pos, uint flags);
        [DllImport("user32.dll")] static extern bool DrawMenuBar(IntPtr h);
        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint m);
        [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint m);

        public static IntPtr Hwnd { get { return GetConsoleWindow(); } }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct CONSOLE_FONT_INFOEX
        {
            public uint cbSize; public uint nFont; public short X; public short Y;
            public int FontFamily; public int FontWeight;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string FaceName;
        }
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool SetCurrentConsoleFontEx(IntPtr h, bool max, ref CONSOLE_FONT_INFOEX f);

        public static bool SetFont(string face, short size)
        {
            CONSOLE_FONT_INFOEX f = new CONSOLE_FONT_INFOEX();
            f.cbSize = (uint)Marshal.SizeOf(typeof(CONSOLE_FONT_INFOEX));
            f.X = 0; f.Y = size; f.FontFamily = 54; f.FontWeight = 400; f.FaceName = face;
            return SetCurrentConsoleFontEx(GetStdHandle(-11), false, ref f);
        }

        // Dosya secme penceresi (ayri STA is parcaciginda)
        public static string PickFile(string title, string filter)
        {
            string result = null;
            Thread t = new Thread(() =>
            {
                using (OpenFileDialog d = new OpenFileDialog())
                {
                    d.Title = title; d.Filter = filter; d.CheckFileExists = true;
                    d.InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + "\\Downloads";
                    using (Form owner = new Form { TopMost = true, ShowInTaskbar = false, Opacity = 0, StartPosition = FormStartPosition.CenterScreen })
                    {
                        owner.Show();
                        if (d.ShowDialog(owner) == DialogResult.OK) result = d.FileName;
                    }
                }
            });
            t.SetApartmentState(ApartmentState.STA);
            t.Start();
            t.Join();
            return result;
        }

        [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr v);
        // Ekran olceklemesinde (125%/150%) konumlar dogru hesaplansin
        public static void DpiAware() { try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { } }

        public static void PrepareConsole()
        {
            // Renkli cizim (VT) ac
            IntPtr o = GetStdHandle(-11); uint m;
            if (GetConsoleMode(o, out m)) SetConsoleMode(o, m | 0x0004);
            // QuickEdit kapat: pencereye tiklayinca panel donmasin
            IntPtr i = GetStdHandle(-10);
            if (GetConsoleMode(i, out m)) SetConsoleMode(i, (m & ~0x0040u) | 0x0080u);
        }

        // X tusunu kaldir: kapatma her zaman sunucuyu duzgun durdurarak yapilsin
        public static void DisableCloseButton()
        {
            IntPtr h = GetConsoleWindow();
            IntPtr menu = GetSystemMenu(h, false);
            if (menu != IntPtr.Zero) { DeleteMenu(menu, 0xF060, 0); DrawMenuBar(h); }
        }

        public static void Hide() { ShowWindow(GetConsoleWindow(), 0); }
        public static void Show()
        {
            IntPtr h = GetConsoleWindow();
            ShowWindow(h, IsIconic(h) ? 9 : 5);
            SetForegroundWindow(h);
        }
        public static bool Visible { get { IntPtr h = GetConsoleWindow(); return IsWindowVisible(h) && !IsIconic(h); } }

        [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);

        // x, y, genislik, yukseklik
        public static int[] GetRect() { RECT r; GetWindowRect(GetConsoleWindow(), out r); return new int[] { r.L, r.T, r.R - r.L, r.B - r.T }; }
        public static void MoveTo(int x, int y) { SetWindowPos(GetConsoleWindow(), IntPtr.Zero, x, y, 0, 0, 0x0001 | 0x0004 | 0x0010); }
        public static void SetTopMost(bool on) { SetWindowPos(GetConsoleWindow(), on ? new IntPtr(-1) : new IntPtr(-2), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010); }
        public static int[] WorkArea()
        {
            Rectangle w = Screen.FromHandle(GetConsoleWindow()).WorkingArea;
            return new int[] { w.Left, w.Top, w.Width, w.Height };
        }
        public static bool OnAnyScreen(int x, int y)
        {
            foreach (Screen s in Screen.AllScreens) if (s.WorkingArea.Contains(x + 40, y + 10)) return true;
            return false;
        }
        // Pencere saydam yapilmissa tam opak yap
        public static void MakeOpaque()
        {
            IntPtr h = GetConsoleWindow();
            if ((GetWindowLong(h, -20) & 0x80000) != 0) SetLayeredWindowAttributes(h, 0, 255, 2);
        }
    }

    // Her yerden calisan kisayol tuslari (oyundayken bile). Gizli ust duzey pencere oldugu icin
    // Windows kapanirken / oturum kapanirken gelen WM_ENDSESSION da buraya duser.
    public class HotkeyWindow : NativeWindow
    {
        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
        public string Status = "";
        public HotkeyWindow()
        {
            CreateHandle(new CreateParams());
            // Ctrl+Alt+K: kucuk/buyuk   Ctrl+Alt+G: gizle/goster
            bool a = RegisterHotKey(Handle, 1, 0x0002 | 0x0001 | 0x4000, 0x4B);
            bool b = RegisterHotKey(Handle, 2, 0x0002 | 0x0001 | 0x4000, 0x47);
            Status = (a ? "K:ok" : "K:fail") + " " + (b ? "G:ok" : "G:fail");
        }
        public void Release()
        {
            if (Handle == IntPtr.Zero) return;
            UnregisterHotKey(Handle, 1);
            UnregisterHotKey(Handle, 2);
            DestroyHandle();
        }
        protected override void WndProc(ref Message m)
        {
            try
            {
                if (m.Msg == 0x0312)
                {
                    int id = m.WParam.ToInt32();
                    if (id == 1) Tray.Actions.Enqueue("mini");
                    else if (id == 2) Tray.Toggle();
                }
                // WM_ENDSESSION: user32 kullanan konsol programina CTRL_LOGOFF_EVENT / CTRL_SHUTDOWN_EVENT
                // gelmez (CloseGuard calismaz); Windows bunun yerine gizli pencereye bunu gonderir
                else if (m.Msg == 0x0016 && m.WParam != IntPtr.Zero) Tray.SaveServer();
            }
            catch { }   // pencere yordamindan hata kacarsa Windows Forms hata penceresi acar
            base.WndProc(ref m);
        }
    }

    // Panel kapanirsa (zorla bile) sunucu yetim kalmasin
    public static class JobGuard
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string n);
        [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr j, int cls, IntPtr info, uint len);
        [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);

        [StructLayout(LayoutKind.Sequential)]
        struct BASIC { public long a, b; public uint LimitFlags; public UIntPtr c, d; public uint e; public UIntPtr f; public uint g, h; }
        [StructLayout(LayoutKind.Sequential)]
        struct IOC { public ulong a, b, c, d, e, f; }
        [StructLayout(LayoutKind.Sequential)]
        struct EXT { public BASIC B; public IOC I; public UIntPtr p, j, pp, jp; }

        static IntPtr job = IntPtr.Zero;

        public static void Add(Process p)
        {
            if (job == IntPtr.Zero)
            {
                job = CreateJobObject(IntPtr.Zero, null);
                EXT e = new EXT();
                e.B.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE
                int len = Marshal.SizeOf(typeof(EXT));
                IntPtr ptr = Marshal.AllocHGlobal(len);
                Marshal.StructureToPtr(e, ptr, false);
                SetInformationJobObject(job, 9, ptr, (uint)len);
                Marshal.FreeHGlobal(ptr);
            }
            AssignProcessToJobObject(job, p.Handle);
        }

        // Pencere kapatilirken Windows SyHost'u birkac saniyede sonlandirir; "kapaninca oldur" kurali sunucuyu
        // kaydederken oldururdu. "stop" gonderildikten sonra kural kaldirilir (C#: JobGuard.LetChildrenFinish).
        public static void LetChildrenFinish()
        {
            if (job == IntPtr.Zero) return;
            EXT e = new EXT();
            int len = Marshal.SizeOf(typeof(EXT));
            IntPtr ptr = Marshal.AllocHGlobal(len);
            try { Marshal.StructureToPtr(e, ptr, false); SetInformationJobObject(job, 9, ptr, (uint)len); }
            finally { Marshal.FreeHGlobal(ptr); }
        }
    }

    public class Server
    {
        public Process P;
        public readonly ConcurrentQueue<string> Out = new ConcurrentQueue<string>();
        StreamWriter input;

        public bool Running { get { try { return P != null && !P.HasExited; } catch { return false; } } }

        public void Start(string exe, string args, string dir)
        {
            ProcessStartInfo psi = new ProcessStartInfo(exe, args);
            psi.WorkingDirectory = dir;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;
            P = new Process();
            P.StartInfo = psi;
            P.OutputDataReceived += (s, e) => { if (e.Data != null) Out.Enqueue(e.Data); };
            P.ErrorDataReceived += (s, e) => { if (e.Data != null) Out.Enqueue("[STDERR] " + e.Data); };
            // Konsol girdisi BOM'lu UTF-8 ise .NET ilk komutun basina gorunmez bir karakter ekler; onu engelle
            Encoding oldIn = null;
            try { oldIn = Console.InputEncoding; Console.InputEncoding = new UTF8Encoding(false); } catch { }
            try { P.Start(); } finally { try { if (oldIn != null && oldIn.GetPreamble().Length == 0) Console.InputEncoding = oldIn; } catch { } }
            input = new StreamWriter(P.StandardInput.BaseStream, new UTF8Encoding(false));
            input.AutoFlush = true;
            input.NewLine = "\n";
            P.BeginOutputReadLine();
            P.BeginErrorReadLine();
            try { JobGuard.Add(P); } catch { }
        }

        public void Send(string line)
        {
            if (!Running) return;
            try { input.WriteLine(line); } catch { }
        }
    }

    // Windows kapanirken / oturum kapanirken sunucuyu kaydedip durdur
    public static class CloseGuard
    {
        public delegate bool Handler(int type);
        [DllImport("kernel32.dll")] static extern bool SetConsoleCtrlHandler(Handler h, bool add);
        static Handler keep;
        public static Server Current;
        // playit: SyHost kapanirken hemen kapatilir (yalnizca SyHost acikken calisir)
        public static Server Playit;

        public static void Install()
        {
            keep = t =>
            {
                if (t == 0 || t == 1) return true; // Ctrl+C / Ctrl+Break: yok say
                SaveAndRelease();
                return false;
            };
            SetConsoleCtrlHandler(keep, true);
        }

        // Windows SyHost'u kapatiyor (pencere kapatma, oturum kapanmasi): playit'i kapat, sunucuya "stop" gonder ve
        // SyHost sonlandirilsa da sunucunun kaydi bitirebilmesi icin onu is nesnesinden serbest birak (C#: CloseGuard.SaveAndRelease)
        public static void SaveAndRelease()
        {
            try { Server p = Playit; if (p != null && p.Running) p.P.Kill(); } catch { }
            Server s = Current;
            if (s != null && s.Running)
            {
                s.Send("stop");
                JobGuard.LetChildrenFinish();
                try { s.P.WaitForExit(25000); } catch { }
            }
        }
    }

    // Saat yanindaki simge, menusu, balon bildirimleri ve kisayol tuslari (C# surumu: src\SyHost\Core\Tray.cs)
    public static class Tray
    {
        public static readonly ConcurrentQueue<string> Actions = new ConcurrentQueue<string>();
        static NotifyIcon icon;
        static Control invoker;
        static HotkeyWindow hotkeys;
        static Thread thread;
        static IntPtr iconHandle;
        static volatile bool up, stopped;
        static readonly ManualResetEvent ready = new ManualResetEvent(false);
        static readonly ConcurrentQueue<Action> early = new ConcurrentQueue<Action>();
        // Menu yazilari: PowerShell L ile verir (SetLabels), dil degisince yeniden verir; menu her acilista bunlari yazar.
        // Varsayilanlar Turkce anahtarlar (Lang.Screens.ps1, AddTray).
        static volatile string[] labels = { "Paneli G\u00f6ster", "Paneli Gizle", "K\u00fc\u00e7\u00fck / B\u00fcy\u00fck Mod  (Ctrl+Alt+K)", "Sunucuyu Yeniden Ba\u015flat", "SyHost'u Kapat" };

        public static string HotkeyStatus { get { HotkeyWindow h = hotkeys; return h == null ? "" : h.Status; } }
        // Kisayol / oturum penceresi (testler icin)
        public static IntPtr Hwnd { get { HotkeyWindow h = hotkeys; return h == null ? IntPtr.Zero : h.Handle; } }
        public static bool Running { get { return up && !stopped; } }
        public static string[] Labels { get { return (string[])labels.Clone(); } }

        // Menu yazilari (sirayla: goster, gizle, kucuk/buyuk, yeniden baslat, kapat). Bos ya da null olan degismez.
        // Her is parcacigindan, Start'tan once ya da sonra cagrilabilir.
        public static void SetLabels(string show, string hide, string mini, string restart, string quit)
        {
            string[] cur = labels;
            labels = new string[] { Pick(show, cur[0]), Pick(hide, cur[1]), Pick(mini, cur[2]), Pick(restart, cur[3]), Pick(quit, cur[4]) };
        }
        static string Pick(string s, string old) { return string.IsNullOrEmpty(s) ? old : s; }

        public static void Start(string text) { Start(text, null); }

        // iconFile: simgesi kullanilacak dosya (SyHost.exe); yoksa ya da okunamazsa kirmizi "S" cizilir
        public static void Start(string text, string iconFile)
        {
            if (thread != null) return;
            string tip = Trim(text ?? "");
            Thread th = new Thread(() =>
            {
                try
                {
                    Application.ThreadException += (s, e) => { };   // bu is parcacigindaki hata pencere acmasin
                    Application.EnableVisualStyles();
                    invoker = new Control();
                    IntPtr force = invoker.Handle;
                    hotkeys = new HotkeyWindow();
                    icon = new NotifyIcon();
                    Icon ic = IconFromFile(iconFile);
                    if (ic != null) iconHandle = ic.Handle; else ic = MakeIcon();
                    icon.Icon = ic;
                    icon.Text = tip;
                    icon.ContextMenu = BuildMenu();
                    icon.MouseClick += (s, e) => { if (e.Button == MouseButtons.Left) Toggle(); };
                    icon.Visible = true;
                    up = true;
                }
                catch { }
                ready.Set();
                Flush();
                if (!up) return;
                try { Application.Run(); } catch { }
            });
            th.SetApartmentState(ApartmentState.STA);
            th.IsBackground = true;
            thread = th;
            th.Start();
        }

        // Windows'un kendi acilir menusu (C# surumundeki gibi); yazilar her acilista guncel dilden
        public static ContextMenu BuildMenu()
        {
            string[] l = labels;
            ContextMenu menu = new ContextMenu();
            menu.MenuItems.Add(new MenuItem(l[0], (s, e) => Native.Show()));
            menu.MenuItems.Add(new MenuItem(l[1], (s, e) => Native.Hide()));
            menu.MenuItems.Add(new MenuItem(l[2], (s, e) => Actions.Enqueue("mini")));
            menu.MenuItems.Add(new MenuItem("-"));
            menu.MenuItems.Add(new MenuItem(l[3], (s, e) => Actions.Enqueue("restart")));
            menu.MenuItems.Add(new MenuItem(l[4], (s, e) => { Native.Show(); Actions.Enqueue("quit"); }));
            menu.Popup += (s, e) => ApplyLabels(menu);
            return menu;
        }

        public static void ApplyLabels(ContextMenu menu)
        {
            string[] l = labels;
            int[] at = { 0, 1, 2, 4, 5 };
            for (int i = 0; i < at.Length; i++) if (menu.MenuItems[at[i]].Text != l[i]) menu.MenuItems[at[i]].Text = l[i];
        }

        internal static void Toggle() { if (Native.Visible) Native.Hide(); else Native.Show(); }

        // Windows kapanirken / oturum kapanirken (WM_ENDSESSION): CloseGuard gibi sunucuyu kaydedip durdur
        internal static void SaveServer() { CloseGuard.SaveAndRelease(); }

        static string Trim(string s) { return s.Length > 63 ? s.Substring(0, 63) : s; }

        // Tepsi is parcaciginda calistir. Tepsi henuz acilmadiysa sirada bekler, acilinca yapilir.
        static void OnUi(Action a)
        {
            if (thread == null || stopped) return;
            Action safe = () => { try { a(); } catch { } };
            if (!up)
            {
                if (ready.WaitOne(0)) return;   // tepsi acilamadi
                early.Enqueue(safe);
                if (up || ready.WaitOne(0)) Flush();   // bu arada acildi
                return;
            }
            try { invoker.BeginInvoke(safe); } catch { }
        }

        static void Flush()
        {
            Action a;
            while (early.TryDequeue(out a))
            {
                if (!up) continue;
                if (Thread.CurrentThread == thread) a();
                else { try { invoker.BeginInvoke(a); } catch { } }
            }
        }

        public static void Balloon(string title, string msg)
        {
            if (string.IsNullOrEmpty(msg)) return;   // bos metinle Windows Forms hata verir
            string t = title ?? "";
            OnUi(() => { if (icon != null && icon.Visible) icon.ShowBalloonTip(3000, t, msg, ToolTipIcon.Info); });
        }

        public static void SetText(string s)
        {
            string t = Trim(s ?? "");
            OnUi(() => { if (icon != null && icon.Text != t) icon.Text = t; });
        }

        // Simgeyi kaldir, kisayollari birak, is parcacigini bitir. Cikisi bekletmez (en fazla birkac saniye).
        public static void Close()
        {
            Thread th = thread;
            if (th == null || stopped) return;
            stopped = true;
            if (Thread.CurrentThread == th) { Stop(); return; }
            ready.WaitOne(2000);
            if (up) { try { invoker.BeginInvoke((Action)Stop); } catch { } }
            // Simge kalkmadan cikilirsa fare ustune gelene kadar saatin yaninda hayalet simge kalir
            th.Join(3000);
        }

        static void Stop()
        {
            try { if (icon != null) { icon.Visible = false; icon.Dispose(); } } catch { }
            try { if (iconHandle != IntPtr.Zero) { DestroyIcon(iconHandle); iconHandle = IntPtr.Zero; } } catch { }
            try { if (hotkeys != null) hotkeys.Release(); } catch { }
            up = false;
            try { Application.ExitThread(); } catch { }
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHDefExtractIcon(string file, int index, uint flags, out IntPtr large, out IntPtr small, uint sizes);
        [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);
        [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
        [DllImport("user32.dll")] static extern int GetSystemMetricsForDpi(int i, uint dpi);
        [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);

        // Gorev cubugunun olcegine uygun kucuk simge boyutu (125%/150% olcekte bulanik olmasin)
        static int SmallIconSize()
        {
            int n = 0;
            try
            {
                IntPtr bar = FindWindow("Shell_TrayWnd", null);
                uint dpi = bar != IntPtr.Zero ? GetDpiForWindow(bar) : 0;
                if (dpi != 0) n = GetSystemMetricsForDpi(49, dpi);   // SM_CXSMICON
            }
            catch { }   // Windows 10 1607 oncesinde bu islevler yok
            if (n <= 0) n = GetSystemMetrics(49);
            return n > 0 ? n : 16;
        }

        // Dosyanin (SyHost.exe) ilk simgesi, gorev cubugu boyutunda; olmazsa null
        public static Icon IconFromFile(string file)
        {
            try
            {
                if (string.IsNullOrEmpty(file) || !File.Exists(file)) return null;
                int cs = SmallIconSize();
                IntPtr large, small;
                // sizes: alt 16 bit buyuk, ust 16 bit kucuk simgenin boyutu
                if (SHDefExtractIcon(file, 0, 0, out large, out small, (uint)((cs << 16) | (cs * 2))) != 0) return null;
                if (large != IntPtr.Zero) DestroyIcon(large);
                return small == IntPtr.Zero ? null : Icon.FromHandle(small);
            }
            catch { return null; }
        }

        // Kirmizi, "S" yazili kucuk tepsi simgesi (SyHost.exe yoksa, ornegin gelistirirken)
        static Icon MakeIcon()
        {
            Bitmap b = new Bitmap(32, 32);
            using (Graphics g = Graphics.FromImage(b))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                using (GraphicsPath path = Rounded(new Rectangle(1, 1, 30, 30), 7))
                using (LinearGradientBrush br = new LinearGradientBrush(new Point(0, 0), new Point(32, 32), Color.FromArgb(239, 55, 66), Color.FromArgb(120, 10, 20)))
                {
                    g.FillPath(br, path);
                    using (Pen pen = new Pen(Color.FromArgb(60, 0, 8), 1.5f)) g.DrawPath(pen, path);
                }
                using (Font f = new Font("Segoe UI", 13f, FontStyle.Bold, GraphicsUnit.Pixel))
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                {
                    g.DrawString("S", f, new SolidBrush(Color.FromArgb(40, 0, 0)), new RectangleF(1, 2, 32, 32), sf);
                    g.DrawString("S", f, Brushes.White, new RectangleF(0, 1, 32, 32), sf);
                }
            }
            return Icon.FromHandle(b.GetHicon());
        }

        static GraphicsPath Rounded(Rectangle r, int rad)
        {
            GraphicsPath p = new GraphicsPath();
            int d = rad * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
    }

    public static class Backup
    {
        // Sunucu acikken de calisir (dosyalar paylasimli okunur)
        public static Task<string> ZipAsync(string src, string dst)
        {
            return Task.Run(() =>
            {
                string tmp = dst + ".tmp";
                using (FileStream fs = new FileStream(tmp, FileMode.Create))
                using (ZipArchive zip = new ZipArchive(fs, ZipArchiveMode.Create))
                {
                    int cut = src.TrimEnd('\\').Length + 1;
                    foreach (string file in Directory.EnumerateFiles(src, "*", SearchOption.AllDirectories))
                    {
                        if (file.EndsWith("session.lock", StringComparison.OrdinalIgnoreCase)) continue;
                        string rel = file.Substring(cut).Replace('\\', '/');
                        try
                        {
                            using (FileStream inp = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                            {
                                ZipArchiveEntry entry = zip.CreateEntry(rel, CompressionLevel.Fastest);
                                using (Stream outp = entry.Open()) inp.CopyTo(outp);
                            }
                        }
                        catch { }
                    }
                }
                if (File.Exists(dst)) File.Delete(dst);
                File.Move(tmp, dst);
                return dst;
            });
        }
    }
}
