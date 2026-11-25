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

    // Her yerden calisan kisayol tuslari (oyundayken bile)
    public class HotkeyWindow : NativeWindow
    {
        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
        public string Status = "";
        public HotkeyWindow()
        {
            CreateHandle(new CreateParams());
            // Ctrl+Alt+K: kucuk/buyuk   Ctrl+Alt+G: gizle/goster
            bool a = RegisterHotKey(Handle, 1, 0x0002 | 0x0001 | 0x4000, 0x4B);
            bool b = RegisterHotKey(Handle, 2, 0x0002 | 0x0001 | 0x4000, 0x47);
            Status = (a ? "K:ok" : "K:fail") + " " + (b ? "G:ok" : "G:fail");
        }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0312)
            {
                int id = m.WParam.ToInt32();
                if (id == 1) Tray.Actions.Enqueue("mini");
                else if (id == 2) { if (Native.Visible) Native.Hide(); else Native.Show(); }
            }
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

        public static void Install()
        {
            keep = t =>
            {
                if (t == 0 || t == 1) return true; // Ctrl+C / Ctrl+Break: yok say
                Server s = Current;
                if (s != null && s.Running) { s.Send("stop"); try { s.P.WaitForExit(25000); } catch { } }
                return false;
            };
            SetConsoleCtrlHandler(keep, true);
        }
    }

    public static class Tray
    {
        public static readonly ConcurrentQueue<string> Actions = new ConcurrentQueue<string>();
        static NotifyIcon icon;
        static Control invoker;
        static HotkeyWindow hotkeys;
        public static string HotkeyStatus { get { return hotkeys == null ? "" : hotkeys.Status; } }

        public static void Start(string text)
        {
            Thread th = new Thread(() =>
            {
                Application.EnableVisualStyles();
                invoker = new Control();
                IntPtr force = invoker.Handle;
                hotkeys = new HotkeyWindow();
                icon = new NotifyIcon();
                icon.Icon = MakeIcon();
                icon.Text = Trim(text);
                ContextMenuStrip menu = new ContextMenuStrip();
                menu.Items.Add("Paneli Goster", null, (s, e) => Native.Show());
                menu.Items.Add("Paneli Gizle", null, (s, e) => Native.Hide());
                menu.Items.Add("Kucuk / Buyuk Mod  (Ctrl+Alt+K)", null, (s, e) => Actions.Enqueue("mini"));
                menu.Items.Add(new ToolStripSeparator());
                menu.Items.Add("Sunucuyu Yeniden Baslat", null, (s, e) => Actions.Enqueue("restart"));
                menu.Items.Add("SyHost'u Kapat", null, (s, e) => { Native.Show(); Actions.Enqueue("quit"); });
                icon.ContextMenuStrip = menu;
                icon.MouseClick += (s, e) => { if (e.Button == MouseButtons.Left) { if (Native.Visible) Native.Hide(); else Native.Show(); } };
                icon.Visible = true;
                Application.Run();
            });
            th.SetApartmentState(ApartmentState.STA);
            th.IsBackground = true;
            th.Start();
        }

        static string Trim(string s) { return s.Length > 63 ? s.Substring(0, 63) : s; }

        static void OnUi(Action a)
        {
            Control c = invoker;
            if (c == null || icon == null) return;
            try { c.BeginInvoke(a); } catch { }
        }

        public static void Balloon(string title, string msg)
        {
            OnUi(() => icon.ShowBalloonTip(3000, title, msg, ToolTipIcon.Info));
        }

        public static void SetText(string s) { OnUi(() => icon.Text = Trim(s)); }

        public static void Close()
        {
            Control c = invoker;
            if (c == null) return;
            try { c.Invoke((Action)(() => { icon.Visible = false; icon.Dispose(); Application.ExitThread(); })); } catch { }
        }

        // Kirmizi, "S" yazili kucuk tepsi simgesi
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
