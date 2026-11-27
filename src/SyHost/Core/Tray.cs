// =====================================================================
//  SyHost - tepsi simgesi, menüsü, balon bildirimleri ve kısayol tuşları
//  legacy/src/SyHost.Core.cs'teki HotkeyWindow (133-156) ve Tray (254-348)
//  sınıflarının tek exe (NativeAOT) uyumlu karşılığı: WinForms yerine kendi
//  iş parçacığında mesaj döngüsü çalıştıran gizli bir pencere.
// =====================================================================
using System.Collections.Concurrent;
using System.Runtime.InteropServices;

namespace SyHost;

/// <summary>Saat yanındaki simge, menüsü, balon bildirimleri ve her yerden çalışan kısayol tuşları.</summary>
static unsafe partial class Tray
{
    /// <summary>Menüden ve kısayollardan gelen istekler ("mini", "restart", "quit"); ana döngü okur.</summary>
    public static readonly ConcurrentQueue<string> Actions = new();

    /// <summary>Kısayol tuşlarının durumu, ör. "K:ok G:ok". Tepsi henüz hazır değilse boş.</summary>
    public static string HotkeyStatus => hotkeyStatus;

    // ---------- kernel32 / user32 / shell32 ----------
    [LibraryImport("kernel32.dll", EntryPoint = "GetModuleHandleW")] private static partial nint GetModuleHandle(nint name);
    [LibraryImport("user32.dll", EntryPoint = "RegisterClassExW")] private static partial ushort RegisterClassEx(WNDCLASSEXW* wc);
    [LibraryImport("user32.dll", EntryPoint = "CreateWindowExW")] private static partial nint CreateWindowEx(uint exStyle, char* cls, char* name, uint style, int x, int y, int w, int h, nint parent, nint menu, nint inst, nint param);
    [LibraryImport("user32.dll", EntryPoint = "DefWindowProcW")] private static partial nint DefWindowProc(nint h, uint msg, nint w, nint l);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DestroyWindow(nint h);
    [LibraryImport("user32.dll", EntryPoint = "GetMessageW")] private static partial int GetMessage(MSG* m, nint h, uint min, uint max);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool TranslateMessage(MSG* m);
    [LibraryImport("user32.dll", EntryPoint = "DispatchMessageW")] private static partial nint DispatchMessage(MSG* m);
    [LibraryImport("user32.dll", EntryPoint = "PostMessageW")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool PostMessage(nint h, uint msg, nint w, nint l);
    [LibraryImport("user32.dll")] private static partial void PostQuitMessage(int code);
    [LibraryImport("user32.dll", EntryPoint = "RegisterWindowMessageW", StringMarshalling = StringMarshalling.Utf16)] private static partial uint RegisterWindowMessage(string name);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool ChangeWindowMessageFilterEx(nint h, uint msg, uint action, nint info);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool RegisterHotKey(nint h, int id, uint mod, uint vk);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool UnregisterHotKey(nint h, int id);
    [LibraryImport("user32.dll")] private static partial nint CreatePopupMenu();
    [LibraryImport("user32.dll", EntryPoint = "AppendMenuW")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool AppendMenu(nint m, uint flags, nuint id, char* text);
    [LibraryImport("user32.dll")] private static partial int TrackPopupMenuEx(nint m, uint flags, int x, int y, nint h, nint tpm);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DestroyMenu(nint m);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool EndMenu();
    [LibraryImport("user32.dll")] private static partial int GetSystemMetrics(int i);
    [LibraryImport("user32.dll")] private static partial int GetSystemMetricsForDpi(int i, uint dpi);
    [LibraryImport("user32.dll")] private static partial uint GetDpiForWindow(nint h);
    [LibraryImport("user32.dll")] private static partial uint GetDpiForSystem();
    [LibraryImport("user32.dll", EntryPoint = "LoadImageW")] private static partial nint LoadImage(nint inst, nint name, uint type, int cx, int cy, uint flags);
    [LibraryImport("user32.dll", EntryPoint = "LoadIconW")] private static partial nint LoadIcon(nint inst, nint name);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DestroyIcon(nint h);
    [LibraryImport("user32.dll")] private static partial nuint SetTimer(nint h, nuint id, uint ms, nint fn);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool KillTimer(nint h, nuint id);
    [LibraryImport("shell32.dll", EntryPoint = "Shell_NotifyIconW")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool ShellNotifyIcon(uint msg, NOTIFYICONDATAW* d);
    [LibraryImport("shell32.dll", EntryPoint = "ExtractIconExW", StringMarshalling = StringMarshalling.Utf16)] private static partial uint ExtractIconEx(string file, int index, nint* large, nint* small, uint n);

    [StructLayout(LayoutKind.Sequential)]
    struct WNDCLASSEXW
    {
        public uint cbSize, style;
        public delegate* unmanaged<nint, uint, nint, nint, nint> lpfnWndProc;
        public int cbClsExtra, cbWndExtra;
        public nint hInstance, hIcon, hCursor, hbrBackground;
        public char* lpszMenuName, lpszClassName;
        public nint hIconSm;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MSG { public nint hwnd; public uint message; public nint wParam, lParam; public uint time; public int ptX, ptY; public uint lPrivate; }

    [StructLayout(LayoutKind.Sequential)]
    struct NOTIFYICONDATAW
    {
        public uint cbSize;
        public nint hWnd;
        public uint uID, uFlags, uCallbackMessage;
        public nint hIcon;
        public fixed char szTip[128];
        public uint dwState, dwStateMask;
        public fixed char szInfo[256];
        public uint uTimeoutOrVersion;
        public fixed char szInfoTitle[64];
        public uint dwInfoFlags;
        public Guid guidItem;
        public nint hBalloonIcon;
    }

    // ---------- Windows sabitleri ----------
    const uint WM_DESTROY = 0x0002, WM_ENDSESSION = 0x0016, WM_CONTEXTMENU = 0x007B, WM_TIMER = 0x0113;
    const uint WM_LBUTTONUP = 0x0202, WM_LBUTTONDBLCLK = 0x0203, WM_DPICHANGED = 0x02E0, WM_HOTKEY = 0x0312;
    const uint WM_TRAY = 0x8000 + 1;   // WM_APP+1: simgeye tıklama, menü tuşu
    const uint WM_WORK = 0x8000 + 2;   // WM_APP+2: başka iş parçacığından balon / ipucu isteği
    const uint WM_STOP = 0x8000 + 3;   // WM_APP+3: Close()
    const uint NIN_KEYSELECT = 0x0401;
    const uint NIM_ADD = 0, NIM_MODIFY = 1, NIM_DELETE = 2, NIM_SETVERSION = 4, NOTIFYICON_VERSION_4 = 4;
    const uint NIF_MESSAGE = 0x01, NIF_ICON = 0x02, NIF_TIP = 0x04, NIF_INFO = 0x10, NIF_SHOWTIP = 0x80;
    const uint NIIF_INFO = 0x01, NIIF_USER = 0x04, NIIF_LARGE_ICON = 0x20;
    const uint MOD_ALT = 0x0001, MOD_CONTROL = 0x0002, MOD_NOREPEAT = 0x4000;
    const uint MF_STRING = 0x0000, MF_SEPARATOR = 0x0800;
    const uint TPM_LEFTALIGN = 0x0000, TPM_RIGHTBUTTON = 0x0002, TPM_RIGHTALIGN = 0x0008, TPM_NONOTIFY = 0x0080, TPM_RETURNCMD = 0x0100;
    const int SM_CXICON = 11, SM_CYICON = 12, SM_MENUDROPALIGNMENT = 40, SM_CXSMICON = 49, SM_CYSMICON = 50;
    const uint WS_POPUP = 0x80000000, WS_EX_TOOLWINDOW = 0x00000080, MSGFLT_ALLOW = 1, IMAGE_ICON = 1;
    const nint AppIconId = 32512;      // derleyicinin exe'ye gömdüğü simge grubunun numarası
    const nuint RetryTimer = 1;

    // Menü komutları
    const uint CmdShow = 1, CmdHide = 2, CmdMini = 3, CmdRestart = 4, CmdQuit = 5;

    // ---------- Her iş parçacığından erişilenler ----------
    static Thread thread;
    static volatile nint hwnd;
    static volatile bool stopped;
    static volatile string hotkeyStatus = "";
    static readonly ManualResetEventSlim ready = new(false);
    static readonly ConcurrentQueue<(bool Tip, string A, string B)> work = new();

    // ---------- Yalnızca tepsi iş parçacığı ----------
    static string tip = "";
    static nint iconSmall, iconLarge;
    static bool smallShared, added, menuOpen, closing, dblClick;
    static uint taskbarCreated;
    static int retries;
    static long lastKeySelect;

    /// <summary>Simgeyi ve kısayolları ayrı bir iş parçacığında başlat (hemen döner).</summary>
    public static void Start(string text)
    {
        if (thread != null) return;
        tip = Trim(text ?? "");
        var t = new Thread(Run) { IsBackground = true, Name = "SyHost tepsi" };
        t.SetApartmentState(ApartmentState.STA);
        thread = t;
        t.Start();
    }

    // Eski sürümdeki gibi en fazla 63 karakter
    static string Trim(string s) => s.Length > 63 ? s.Substring(0, 63) : s;

    /// <summary>Balon bildirimi (Windows 10/11'de bildirim olarak görünür). Her iş parçacığından çağrılabilir.</summary>
    public static void Balloon(string title, string msg) => Post((false, title, msg));

    /// <summary>Simgenin üzerine gelince görünen yazı. Her iş parçacığından çağrılabilir.</summary>
    public static void SetText(string s) => Post((true, s, null));

    static void Post((bool, string, string) w)
    {
        // Tepsi hiç açılamadıysa ya da kapandıysa kuyruk boşuna büyümesin
        if (thread == null || stopped || (ready.IsSet && hwnd == 0)) return;
        work.Enqueue(w);
        // Pencere henüz yoksa sorun değil: tepsi iş parçacığı açılınca kuyruğu boşaltır
        nint h = hwnd;
        if (h != 0) PostMessage(h, WM_WORK, 0, 0);
    }

    /// <summary>Simgeyi kaldır, kısayolları bırak, iş parçacığını bitir. Çıkışı bekletmez (en fazla birkaç saniye).</summary>
    public static void Close()
    {
        Thread t = thread;
        if (t == null || stopped) return;
        stopped = true;
        if (Thread.CurrentThread == t) { Stop(); return; }
        ready.Wait(2000);
        nint h = hwnd;
        if (h != 0) PostMessage(h, WM_STOP, 0, 0);
        // Simge kalkmadan çıkılırsa fare üstüne gelene kadar saatin yanında hayalet simge kalır
        t.Join(3000);
    }

    // ---------- Tepsi iş parçacığı ----------
    static void Run()
    {
        try
        {
            nint inst = GetModuleHandle(0);
            fixed (char* cls = "SyHostTray", name = "SyHost")
            {
                var wc = new WNDCLASSEXW { cbSize = (uint)sizeof(WNDCLASSEXW), lpfnWndProc = &WndProc, hInstance = inst, lpszClassName = cls };
                RegisterClassEx(&wc);
                // Gizli ama üst düzey pencere: yalnızca mesaj alan (message-only) pencere öne alınamaz,
                // o zaman menünün dışına tıklayınca menü kapanmaz
                hwnd = CreateWindowEx(WS_EX_TOOLWINDOW, cls, name, WS_POPUP, 0, 0, 0, 0, 0, 0, inst, 0);
            }
            if (hwnd == 0) return;

            // Explorer yeniden başlarsa simgeyi tekrar eklemek için (yönetici olarak açılsa da gelsin)
            taskbarCreated = RegisterWindowMessage("TaskbarCreated");
            if (taskbarCreated != 0) ChangeWindowMessageFilterEx(hwnd, taskbarCreated, MSGFLT_ALLOW, 0);

            // Ctrl+Alt+K: küçük/büyük   Ctrl+Alt+G: gizle/göster
            bool k = RegisterHotKey(hwnd, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 0x4B);
            bool g = RegisterHotKey(hwnd, 2, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 0x47);
            hotkeyStatus = (k ? "K:ok" : "K:fail") + " " + (g ? "G:ok" : "G:fail");
            ready.Set();   // Close() artık pencereye mesaj gönderebilir (Explorer'ın yanıtını beklemeden)

            LoadIcons();
            AddIcon();
            DoWork();

            MSG m;
            while (GetMessage(&m, 0, 0, 0) > 0)
            {
                TranslateMessage(&m);
                DispatchMessage(&m);
            }
        }
        catch { }
        finally
        {
            hwnd = 0;
            ready.Set();
            FreeIcons();
        }
    }

    [UnmanagedCallersOnly]
    static nint WndProc(nint h, uint msg, nint wp, nint lp)
    {
        try
        {
            if (msg == taskbarCreated && msg != 0)
            {
                // Explorer yeniden başladı: eski simge gitti, yeniden ekle (ekran ölçeği de değişmiş olabilir)
                added = false;
                retries = 0;
                LoadIcons();
                AddIcon();
                return 0;
            }
            switch (msg)
            {
                case WM_TRAY:
                    // NOTIFYICON_VERSION_4: lParam'ın alt yarısı olay, wParam tıklanan noktanın ekran koordinatı
                    OnIcon((uint)(lp & 0xFFFF), (short)(wp & 0xFFFF), (short)((wp >> 16) & 0xFFFF));
                    return 0;
                case WM_WORK:
                    DoWork();
                    return 0;
                case WM_STOP:
                    Stop();
                    return 0;
                case WM_HOTKEY:
                    if (wp == 1) Actions.Enqueue("mini");
                    else if (wp == 2) Toggle();
                    return 0;
                case WM_TIMER:
                    if ((nuint)wp == RetryTimer)
                    {
                        KillTimer(h, RetryTimer);
                        if (!added && !closing) AddIcon();
                    }
                    return 0;
                case WM_DPICHANGED:
                    LoadIcons();
                    return 0;
                case WM_ENDSESSION:
                    if (wp != 0) SaveServer();
                    return 0;
                case WM_DESTROY:
                    hwnd = 0;
                    PostQuitMessage(0);
                    return 0;
            }
        }
        catch { }   // pencere yordamından hata dışarı kaçarsa uygulama kapanır
        return DefWindowProc(h, msg, wp, lp);
    }

    static void OnIcon(uint ev, int x, int y)
    {
        switch (ev)
        {
            case WM_LBUTTONUP:
                // WinForms MouseClick gibi: çift tıklamanın ikinci bırakışı ayrı tıklama sayılmaz
                if (dblClick) dblClick = false;
                else Toggle();
                break;
            case WM_LBUTTONDBLCLK:
                dblClick = true;
                break;
            case NIN_KEYSELECT:
                // Klavyeyle seçildi (Enter / Boşluk). Tek basış iki bildirim üretirse
                // pencere açılıp hemen kapanmasın: kısa sürede gelen ikincisi sayılmaz
                long now = Environment.TickCount64;
                if (now - lastKeySelect > 300) Toggle();
                lastKeySelect = now;
                break;
            case WM_CONTEXTMENU:
                // Sağ tık ya da klavyeyle menü tuşu
                ShowMenu(x, y);
                break;
        }
    }

    static void Toggle()
    {
        if (Native.Visible) Native.Hide();
        else Native.Show();
    }

    static void ShowMenu(int x, int y)
    {
        if (menuOpen || closing) return;
        nint m = CreatePopupMenu();
        if (m == 0) return;
        int cmd = 0;
        try
        {
            AddItem(m, CmdShow, Lang.L("Paneli Göster"));
            AddItem(m, CmdHide, Lang.L("Paneli Gizle"));
            AddItem(m, CmdMini, Lang.L("Küçük / Büyük Mod  (Ctrl+Alt+K)"));
            AppendMenu(m, MF_SEPARATOR, 0, null);
            AddItem(m, CmdRestart, Lang.L("Sunucuyu Yeniden Başlat"));
            AddItem(m, CmdQuit, Lang.L("SyHost'u Kapat"));
            // Pencere önce öne alınmazsa menünün dışına tıklayınca menü kapanmaz
            Native.SetForegroundWindow(hwnd);
            uint align = GetSystemMetrics(SM_MENUDROPALIGNMENT) != 0 ? TPM_RIGHTALIGN : TPM_LEFTALIGN;
            menuOpen = true;
            cmd = TrackPopupMenuEx(m, align | TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY, x, y, hwnd, 0);
        }
        finally
        {
            menuOpen = false;
            DestroyMenu(m);
            // Menü kapandıktan sonra pencerenin bir mesaj işlemesi gerekir, yoksa ikinci açılışta menü hemen kapanır
            nint h = hwnd;
            if (h != 0) PostMessage(h, 0, 0, 0);   // WM_NULL
        }
        if (closing) { Stop(); return; }   // menü açıkken Close() geldi
        switch ((uint)cmd)
        {
            case CmdShow: Native.Show(); break;
            case CmdHide: Native.Hide(); break;
            case CmdMini: Actions.Enqueue("mini"); break;
            case CmdRestart: Actions.Enqueue("restart"); break;
            case CmdQuit: Native.Show(); Actions.Enqueue("quit"); break;
        }
    }

    static void AddItem(nint m, uint id, string text)
    {
        fixed (char* p = text) AppendMenu(m, MF_STRING, id, p);
    }

    // Close(): simgeyi kaldır, kısayolları bırak, pencereyi kapat (mesaj döngüsü biter)
    static void Stop()
    {
        closing = true;
        if (menuOpen)
        {
            // Menünün kendi döngüsü içindeyiz: önce menüyü kapat, ShowMenu dönünce burası tekrar çağrılır
            EndMenu();
            return;
        }
        nint h = hwnd;
        if (h == 0) return;
        KillTimer(h, RetryTimer);
        if (added)
        {
            var d = Data(0);
            ShellNotifyIcon(NIM_DELETE, &d);
            added = false;
        }
        UnregisterHotKey(h, 1);
        UnregisterHotKey(h, 2);
        DestroyWindow(h);
    }

    // ---------- Simge ----------
    static NOTIFYICONDATAW Data(uint flags)
    {
        var d = new NOTIFYICONDATAW
        {
            cbSize = (uint)sizeof(NOTIFYICONDATAW),
            hWnd = hwnd,
            uID = 1,
            uFlags = flags,
            uCallbackMessage = WM_TRAY,
            hIcon = iconSmall,
        };
        Copy(tip, d.szTip, 128);
        return d;
    }

    static void Copy(string s, char* dst, int size)
    {
        s ??= "";
        int n = Math.Min(s.Length, size - 1);
        for (int i = 0; i < n; i++) dst[i] = s[i];
        dst[n] = '\0';
    }

    static void AddIcon()
    {
        if (hwnd == 0 || closing) return;
        // NIF_SHOWTIP: sürüm 4'te bu bayrak olmadan üzerine gelince yazı görünmez
        var d = Data(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP);
        // Explorer geç yanıt verince ekleme zaman aşımına düşüp yine de yapılmış olabilir: o zaman güncellemek yeter
        bool ok = ShellNotifyIcon(NIM_ADD, &d) || ShellNotifyIcon(NIM_MODIFY, &d);
        if (ok)
        {
            d.uTimeoutOrVersion = NOTIFYICON_VERSION_4;
            ShellNotifyIcon(NIM_SETVERSION, &d);
            added = true;
            retries = 0;
        }
        else if (++retries <= 30)
        {
            // Oturum yeni açıldıysa görev çubuğu henüz hazır olmayabilir: biraz sonra tekrar dene
            SetTimer(hwnd, RetryTimer, 2000, 0);
        }
    }

    static bool Modify(uint flags)
    {
        if (!added) return false;
        var d = Data(flags | NIF_TIP | NIF_SHOWTIP);
        return ShellNotifyIcon(NIM_MODIFY, &d);
    }

    static void ShowBalloon(string title, string msg)
    {
        if (!added || string.IsNullOrEmpty(msg)) return;
        var d = Data(NIF_INFO | NIF_TIP | NIF_SHOWTIP);
        Copy(title, d.szInfoTitle, 64);
        Copy(msg, d.szInfo, 256);
        d.uTimeoutOrVersion = 3000;
        // Bildirimde SyHost simgesi görünsün; olmazsa Windows'un bilgi simgesi
        d.dwInfoFlags = iconLarge != 0 ? NIIF_USER | NIIF_LARGE_ICON : NIIF_INFO;
        d.hBalloonIcon = iconLarge;
        if (!ShellNotifyIcon(NIM_MODIFY, &d) && iconLarge != 0)
        {
            d.dwInfoFlags = NIIF_INFO;
            d.hBalloonIcon = 0;
            ShellNotifyIcon(NIM_MODIFY, &d);
        }
    }

    static void DoWork()
    {
        while (work.TryDequeue(out var w))
        {
            if (w.Tip)
            {
                string t = Trim(w.A ?? "");
                if (t == tip) continue;
                tip = t;
                Modify(0);
            }
            else ShowBalloon(w.A, w.B);
        }
    }

    // Exe'nin kendi simgesi, görev çubuğunun ölçeğine uygun boyutta (125%/150% ölçekte bulanık olmasın)
    static void LoadIcons()
    {
        uint dpi = 0;
        try
        {
            nint bar = Native.FindWindow("Shell_TrayWnd", null);
            if (bar != 0) dpi = GetDpiForWindow(bar);
            if (dpi == 0) dpi = GetDpiForSystem();
        }
        catch { }
        int Metric(int i)
        {
            try { if (dpi != 0) return GetSystemMetricsForDpi(i, dpi); } catch { }
            return GetSystemMetrics(i);
        }
        nint inst = GetModuleHandle(0);
        int cs = Metric(SM_CXSMICON), cl = Metric(SM_CXICON);
        nint small = LoadImage(inst, AppIconId, IMAGE_ICON, cs, Metric(SM_CYSMICON), 0);
        nint large = LoadImage(inst, AppIconId, IMAGE_ICON, cl, Metric(SM_CYICON), 0);
        if (small == 0 || large == 0)
        {
            // Yedek yol: exe dosyasındaki ilk simge (sistem ölçeğindeki boyutlarda)
            nint l = 0, s = 0;
            string exe = Environment.ProcessPath;
            if (!string.IsNullOrEmpty(exe)) ExtractIconEx(exe, 0, &l, &s, 1);
            if (small == 0) small = s; else if (s != 0) DestroyIcon(s);
            if (large == 0) large = l; else if (l != 0) DestroyIcon(l);
        }
        bool shared = false;
        if (small == 0) { small = LoadIcon(0, AppIconId); shared = true; }   // IDI_APPLICATION (paylaşılan, silinmez)

        nint oldSmall = iconSmall, oldLarge = iconLarge;
        bool oldShared = smallShared;
        iconSmall = small;
        iconLarge = large;
        smallShared = shared;
        if (added) Modify(NIF_ICON);
        // Eskileri ancak Explorer yenisini aldıktan sonra sil
        if (oldSmall != 0 && !oldShared) DestroyIcon(oldSmall);
        if (oldLarge != 0) DestroyIcon(oldLarge);
    }

    static void FreeIcons()
    {
        if (iconSmall != 0 && !smallShared) DestroyIcon(iconSmall);
        if (iconLarge != 0) DestroyIcon(iconLarge);
        iconSmall = iconLarge = 0;
    }

    // Windows kapanırken / oturum kapanırken: user32 kullanan konsol programına CTRL_SHUTDOWN_EVENT
    // gelmez (CloseGuard çalışmaz), onun yerine gizli pencereye WM_ENDSESSION gelir.
    // CloseGuard ile aynı işi yap: sunucuyu kaydedip durdur, kapanmasını bekle.
    static void SaveServer() => CloseGuard.SaveAndRelease();
}

static partial class Lang
{
    static partial void AddTray()
    {
        // ---------- Tepsi menüsü ----------
        Tx("Paneli Göster", "Show panel", "パネルを表示");
        Tx("Paneli Gizle", "Hide panel", "パネルを隠す");
        Tx("Küçük / Büyük Mod  (Ctrl+Alt+K)", "Mini / full mode  (Ctrl+Alt+K)", "ミニ / 通常モード  (Ctrl+Alt+K)");
        Tx("Sunucuyu Yeniden Başlat", "Restart server", "サーバーを再起動");
        Tx("SyHost'u Kapat", "Quit SyHost", "SyHost を終了");
    }
}
