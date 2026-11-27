// =====================================================================
//  SyHost - komutlar ve tuşlar (sunucu ekranı)
//  legacy/src/SyHost.ps1: "Komutlar (sunucu ekranı)" (847-919) ve
//  "Tuşlar" (921-977) bölümlerinin birebir karşılığı.
// =====================================================================
using System.Diagnostics;
using System.Text.RegularExpressions;

namespace SyHost;

sealed partial class App
{
    // PowerShell'deki -split '\s+', -match '\s' ve -replace '\S+\s*$' (hepsi büyük-küçük harf duyarsız)
    static readonly Regex CmdSpaceRx = new(@"\s+", RegexOptions.IgnoreCase);
    static readonly Regex CmdHasSpaceRx = new(@"\s", RegexOptions.IgnoreCase);
    static readonly Regex CmdLastWordRx = new(@"\S+\s*$", RegexOptions.IgnoreCase);

    // ---------- Komutlar (sunucu ekranı) ----------
    // Ekranda gösterilen komut adı (Türkçe dışındaki dillerde İngilizce komutlar)
    private partial string Cmd(string tr)
    {
        tr ??= "";
        if (Lang.Code == "tr") return tr;
        int i = Array.IndexOf(BuiltinsTr, tr);
        return i >= 0 ? BuiltinsEn[i] : tr;
    }

    private partial void RunCommand(string line)
    {
        line = (line ?? "").Trim();
        if (line.Length == 0) return;
        if (History.Count == 0 || !Ps.Eq(History[History.Count - 1], line)) History.Add(line);
        HistIdx = -1;
        string[] parts = CmdSpaceRx.Split(line, 2);
        string cmd = Norm(parts[0]);
        string arg = parts.Length > 1 ? parts[1] : "";
        if (Ps.In(cmd, "yardim", "help", "?")) { Mode = "help"; }
        else if (Ps.In(cmd, "baslat", "start")) { StartServer(); }
        else if (Ps.In(cmd, "durdur", "stop")) { if (AutoRestartAt != null) { AutoRestartAt = null; AddLog("ok", Lang.L("Otomatik yeniden başlatma iptal edildi.")); } else StopServer(null); }
        else if (Ps.In(cmd, "yeniden", "restart")) { AddLog("panel", Lang.L("Yeniden başlatılıyor...")); StopServer("restart"); }
        else if (Ps.In(cmd, "paket", "pack")) { if (arg.Length > 0) SetPack(arg); else Mode = "paket"; }
        else if (Ps.In(cmd, "yedek", "backup")) { StartBackup(); }
        else if (Ps.In(cmd, "oyuncular", "players", "list")) { if (S != null && S.Running) { ReplyUntil = Now().AddSeconds(2); S.Send("list"); } else AddLog("warn", Lang.L("Sunucu kapalı.")); }
        else if (Ps.In(cmd, "adres", "address"))
        {
            AddLog("ok", Lang.L("Arkadaşların:  {0}", FriendAddr));
            AddLog("ok", Lang.L("Sen (bu PC):   localhost"));
            if (!string.IsNullOrEmpty(Cfg.sesAdresi) && HasFriendAddr) AddLog("ok", Lang.L("Sesli sohbet:  {0}  (otomatik)", Cfg.sesAdresi));
        }
        else if (Ps.In(cmd, "kopyala", "copy"))
        {
            if (HasFriendAddr)
            {
                // Set-Clipboard (test modunda panoya dokunulmaz)
                if (TestMode || Clipboard.SetText(FriendAddr, Native.Hwnd)) AddLog("ok", Lang.L("Adres panoya kopyalandı: {0}  (Discord'a yapıştırabilirsin)", FriendAddr));
                // Pano başka bir programda kilitli kaldı: PowerShell burada çökerdi; kopyalandı demek yerine adresi göster
                else AddLog("warn", Lang.L("Arkadaşların:  {0}", FriendAddr));
            }
            else AddLog("warn", Lang.L("Henüz arkadaşların için bir dış adres yok."));
        }
        else if (Ps.In(cmd, "gizle", "hide")) { HidePanel(); }
        else if (Ps.In(cmd, "kucuk", "mini")) { if (UiMode != "kucuk") SetUiMode("kucuk"); }
        else if (Ps.In(cmd, "buyuk", "tam", "full")) { if (UiMode != "buyuk") SetUiMode("buyuk"); }
        else if (Ps.In(cmd, "ustte", "pin"))
        {
            Win.ustte = !Win.ustte;
            if (UiMode == "kucuk" && !TestMode) Native.SetTopMost(Win.ustte);
            AddLog("ok", Win.ustte ? Lang.L("Küçük mod her zaman üstte kalacak.") : Lang.L("Küçük mod artık üstte sabitlenmiyor."));
            SaveWinState();
        }
        else if (Ps.In(cmd, "detay", "sade", "detail", "simple"))
        {
            Detail = Ps.In(cmd, "detay", "detail"); Scroll = 0;
            AddLog("ok", Detail ? Lang.L("Detaylı konsol: tüm teknik kayıtlar görünüyor. (F5 ile sade görünüme dön)") : Lang.L("Sade konsol: sadece önemli olaylar görünüyor. (F5 ile detaylı görünüm)"));
        }
        else if (Ps.In(cmd, "temizle", "cls", "clear")) { Log.Clear(); Scroll = 0; }
        else if (Ps.In(cmd, "klasor", "folder")) { CmdOpenFolder(Cur?.klasor); }
        else if (Ps.In(cmd, "zorla", "force"))
        {
            if (S != null && S.Running)
            {
                StopRequested = true;
                if (!TestMode) { try { S.P.Kill(); } catch { } }
                AddLog("warn", Lang.L("Sunucu zorla kapatıldı (son otomatik kayıttan sonrası kaybolabilir)."));
            }
            else
            {
                // Yalnızca SyHost'un başlattığı sunucular (IsSyHostServer) kapatılır; başka bir programın sunucusuna dokunulmaz
                List<int> pids;
                try { pids = OtherServerPids() ?? new List<int>(); } catch { pids = new List<int>(); }
                foreach (int pid in pids)
                {
                    if (!IsSyHostServer(pid)) { AddLog("warn", Lang.L("PID {0}: bu sunucuyu SyHost başlatmadı, ona dokunulmadı. Kendi penceresinden ya da Görev Yöneticisi'nden kapatabilirsin.", pid)); continue; }
                    string err = TestMode ? null : CmdKillProcess(pid);
                    if (err == null) AddLog("warn", Lang.L("Eski sunucu süreci kapatıldı (PID {0}).", pid));
                    else AddLog("error", err);
                }
            }
        }
        else if (Ps.In(cmd, "menu", "kapat", "close")) { BeginShutdown("home"); }
        else if (Ps.In(cmd, "cikis", "exit", "quit")) { BeginShutdown("quit"); }
        else
        {
            if (S != null && S.Running) { AddLog("cmd", line); ReplyUntil = Now().AddSeconds(2); S.Send(line.TrimStart('/')); }
            else AddLog("warn", Lang.L("Bilinmeyen komut ya da sunucu kapalı: '{0}'  (F1 yardım)", line));
        }
    }

    // Start-Process explorer.exe $Cur.klasor. Yol tırnak içinde: boşluklu ya da virgüllü klasörler de doğru açılsın.
    void CmdOpenFolder(string dir)
    {
        if (TestMode) return;
        try { Process.Start(new ProcessStartInfo("explorer.exe", "\"" + dir + "\"") { UseShellExecute = true })?.Dispose(); }
        catch { }
    }

    // Stop-Process -Id pid -Force. Süreç zaten kapanmışsa da kapatılmış sayılır (null); kapatılamazsa hata mesajı döner.
    static string CmdKillProcess(int pid)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            p.Kill();
            return null;
        }
        catch (ArgumentException) { return null; }          // böyle bir süreç artık yok
        catch (InvalidOperationException) { return null; }  // süreç bu arada kapandı
        catch (Exception ex) { return ex.Message; }
    }

    // $PackKeys[$PackSel]: PowerShell dizisi gibi eksi sıra sondan sayar, dışarıdaysa null
    static string CmdPackAt(int i)
    {
        if (i < 0) i += PackKeys.Length;
        return i >= 0 && i < PackKeys.Length ? PackKeys[i] : null;
    }

    private partial void CompleteInput()
    {
        string txt = InputText;
        if (!CmdHasSpaceRx.IsMatch(txt))
        {
            // String.StartsWith(string): .NET'te de PowerShell'de de bilgisayarın kültürüyle karşılaştırır
            string n = Norm(txt);
            var hits = new List<string>();
            foreach (string b in Builtins) if (b.StartsWith(n, StringComparison.CurrentCulture)) hits.Add(b);
            if (hits.Count == 1) InputText = hits[0] + " ";
            else if (hits.Count > 1) AddLog("panel", Lang.L("Seçenekler: ") + string.Join(", ", hits));
            return;
        }
        string[] words = CmdSpaceRx.Split(txt);
        string parts0 = words[0];
        string first = Norm(parts0);
        if (Ps.In(first, "paket", "pack"))
        {
            string last = words[words.Length - 1];
            var hh = new List<string>();
            foreach (string pk in PackKeys) if (pk.StartsWith(Norm(last), StringComparison.CurrentCulture)) hh.Add(pk);
            if (hh.Count == 1) InputText = parts0 + " " + hh[0];
            return;
        }
        if (Ps.In(first, PlayerCmds))
        {
            string last = words[words.Length - 1];
            var hh = new List<string>();
            foreach (string pl in Players) if (pl.StartsWith(last, StringComparison.OrdinalIgnoreCase)) hh.Add(pl);
            if (hh.Count == 1) InputText = txt.Substring(0, txt.Length - last.Length) + hh[0] + " ";
        }
    }

    // ---------- Tuşlar ----------
    private partial void HandleKey(ConsoleKeyInfo k)
    {
        Dirty = true;
        bool ctrl = (k.Modifiers & ConsoleModifiers.Control) != 0;
        switch (Screen)
        {
            case "splash": AfterSplash(); return;
            case "outro": Quit = true; return;
            case "home": HandleHomeKey(k, ctrl); return;
            case "wizard": HandleWizardKey(k, ctrl); return;
            // yalnızca C# sürümünde olan ekranlar
            case "firstrun": HandleFirstRunKey(k, ctrl); return;
            case "settings": HandleSettingsKey(k, ctrl); return;
            case "uninstall": HandleUninstallKey(k, ctrl); return;
        }
        // --- sunucu ekranı ---
        if (Mode == "closing") return;
        if (Mode == "kapat")
        {
            switch (k.Key)
            {
                case ConsoleKey.Enter: BeginShutdown("home"); return;
                case ConsoleKey.K: BeginShutdown("quit"); return;
                case ConsoleKey.Escape: Mode = "log"; return;
                case ConsoleKey.H: Mode = "log"; return;
            }
            return;
        }
        if (k.Key == ConsoleKey.F10 || (ctrl && k.Key == ConsoleKey.Q)) { if (Allow("kapat")) Mode = "kapat"; return; }
        if (Mode == "paket")
        {
            switch (k.Key)
            {
                case ConsoleKey.LeftArrow: PackSel = (PackSel + 2) % 3; return;
                case ConsoleKey.RightArrow: PackSel = (PackSel + 1) % 3; return;
                case ConsoleKey.D1: PackSel = 0; return;
                case ConsoleKey.D2: PackSel = 1; return;
                case ConsoleKey.D3: PackSel = 2; return;
                case ConsoleKey.Enter: SetPack(CmdPackAt(PackSel)); Mode = "log"; return;
                case ConsoleKey.Escape: Mode = "log"; return;
                case ConsoleKey.F3: Mode = "log"; return;
            }
        }
        if (UiMode == "kucuk" && (k.Key == ConsoleKey.F1 || k.Key == ConsoleKey.F3)) SetUiMode("buyuk");
        switch (k.Key)
        {
            case ConsoleKey.F1: Mode = Mode == "help" ? "log" : "help"; return;
            case ConsoleKey.F2: if (Allow("F2")) HidePanel(); return;
            case ConsoleKey.F3: Mode = "paket"; PackSel = Array.IndexOf(PackKeys, ActivePack); return;
            case ConsoleKey.F4: ToggleUiMode(); return;
            case ConsoleKey.F5: if (Allow("F5", 400)) RunCommand(Detail ? "simple" : "detail"); return;
            case ConsoleKey.F6: if (Allow("F6")) RunCommand("pin"); return;
            case ConsoleKey.PageUp: Scroll = Math.Min(Log.Count - 1, Scroll + 10); return;
            case ConsoleKey.PageDown: Scroll = Math.Max(0, Scroll - 10); return;
            case ConsoleKey.End: Scroll = 0; return;
            case ConsoleKey.Home: Scroll = Math.Max(0, Log.Count - 5); return;
            case ConsoleKey.UpArrow:
                if (History.Count > 0)
                {
                    if (HistIdx < 0) HistIdx = History.Count - 1; else if (HistIdx > 0) HistIdx--;
                    InputText = History[HistIdx];
                }
                return;
            case ConsoleKey.DownArrow:
                if (HistIdx >= 0)
                {
                    if (HistIdx < History.Count - 1) { HistIdx++; InputText = History[HistIdx]; }
                    else { HistIdx = -1; InputText = ""; }
                }
                return;
            case ConsoleKey.Tab: CompleteInput(); return;
            case ConsoleKey.Enter:
            {
                string t = InputText; InputText = "";
                if (Mode != "log") Mode = "log";
                RunCommand(t);
                return;
            }
            case ConsoleKey.Escape: if (Mode != "log") Mode = "log"; else InputText = ""; return;
            case ConsoleKey.Backspace:
                if (InputText.Length > 0)
                {
                    // Ctrl+Backspace: son kelimeyi sil
                    if (ctrl) InputText = CmdLastWordRx.Replace(InputText, "");
                    else InputText = InputText.Substring(0, InputText.Length - 1);
                }
                return;
        }
        if (ctrl && k.Key == ConsoleKey.C) { InputText = ""; return; }
        if (ctrl && k.Key == ConsoleKey.L) { Log.Clear(); Scroll = 0; return; }
        if (k.KeyChar >= 32)
        {
            if (Mode == "help") Mode = "log";
            if (InputText.Length < 240) InputText += k.KeyChar;
        }
    }
}
