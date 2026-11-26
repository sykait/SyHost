// =====================================================================
//  SyHost - bölümler arası sözleşme
//  Her bölüm (ana menü, sihirbaz, sunucu, ...) aşağıdaki fonksiyonları kendi
//  dosyasında doldurur. İmzalar burada sabittir; parçalar birbirini bu
//  imzalarla çağırır. Parantez içindeki satır numaraları legacy/src/SyHost.ps1.
// =====================================================================
namespace SyHost;

sealed partial class App
{
    // ---------- Ana menü (App.Home.cs) ----------
    /// <summary>Render-Home (1282-1357)</summary>
    private partial List<string> RenderHome(int W, int H);
    /// <summary>Handle-HomeKey (979-1004)</summary>
    private partial void HandleHomeKey(ConsoleKeyInfo k, bool ctrl);
    /// <summary>Switch-Language (384-391): dili sırayla değiştir, kaydet, SyHost'u yeni dille yeniden aç</summary>
    private partial void SwitchLanguage();

    // ---------- Sunucu kurma sihirbazı (App.Wizard.cs) ----------
    /// <summary>Read-Pack (605-623). Okunamazsa açıklayıcı bir hata fırlatır.</summary>
    private partial PackInfo ReadPack(string path);
    /// <summary>Safe-FolderName (625-632)</summary>
    private partial string SafeFolderName(string name);
    /// <summary>Start-Wizard (795-803)</summary>
    private partial void StartWizard();
    /// <summary>Wizard-WorldOptions (804-814): (görünen ad, dünya klasörü adı; yeni dünya için "")</summary>
    private partial List<(string Label, string Value)> WizardWorldOptions();
    /// <summary>Begin-Install (815-831) içindeki adım adları (820. satır)</summary>
    private partial List<string> InstallStepNames(PackInfo info);
    /// <summary>Begin-Install (815-831): kurulumu arka planda başlatır</summary>
    private partial void BeginInstall();
    /// <summary>Check-Install (832-845)</summary>
    private partial void CheckInstall();
    /// <summary>Render-Wizard (1360-1451)</summary>
    private partial List<string> RenderWizard(int W, int H);
    /// <summary>Handle-WizardKey (1006-1040)</summary>
    private partial void HandleWizardKey(ConsoleKeyInfo k, bool ctrl);

    // ---------- Sunucu kontrolü (App.Server.cs) ----------
    /// <summary>Load-Servers (93-103): klasor göreli ise AppRoot'a göre mutlak yola çevrilir</summary>
    private partial void LoadServers();
    /// <summary>Save-Servers (104-108): SyHost klasörünün içindeki yollar göreli yazılır</summary>
    private partial void SaveServers();
    /// <summary>Get-Mask (395-400)</summary>
    private partial long GetMask(int n);
    /// <summary>Apply-PackLive (401-406)</summary>
    private partial void ApplyPackLive();
    /// <summary>Set-Pack (407-421)</summary>
    private partial void SetPack(string name);
    /// <summary>Start-Playit (427-433)</summary>
    private partial void StartPlayit();
    /// <summary>Stop-Playit (434)</summary>
    private partial void StopPlayit();
    /// <summary>Get-ModCount (440)</summary>
    private partial int GetModCount(string dir);
    /// <summary>Ensure-VoiceHost (442-451)</summary>
    private partial void EnsureVoiceHost();
    /// <summary>Start-Server (453-475)</summary>
    private partial void StartServer();
    /// <summary>Stop-Server (476-484); then: null | "restart" | "close"</summary>
    private partial void StopServer(string then);
    /// <summary>Start-Backup (486-497)</summary>
    private partial void StartBackup();
    /// <summary>Begin-Zip (498-503)</summary>
    private partial void BeginZip();
    /// <summary>Check-Backup (504-517)</summary>
    private partial void CheckBackup();
    /// <summary>Add-ServerLine (521-561)</summary>
    private partial void AddServerLine(string raw);
    /// <summary>Enter-Server (564-578)</summary>
    private partial void EnterServer(ServerEntry srv);
    /// <summary>Go-Home (579-585)</summary>
    private partial void GoHome();
    /// <summary>Begin-Shutdown (586-598); after: "home" | "quit"</summary>
    private partial void BeginShutdown(string after);
    /// <summary>Hide-Panel (599-602)</summary>
    private partial void HidePanel();
    /// <summary>Çalışan başka sunucuların (komut satırında "nogui" geçen java.exe) süreç numaraları.
    /// PowerShell: Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'nogui' } (456 ve 892. satırlar)</summary>
    private partial List<int> OtherServerPids();

    // ---------- Sunucu ekranı çizimi (App.ServerView.cs) ----------
    /// <summary>Get-StartPct (1455-1461)</summary>
    private partial int GetStartPct();
    /// <summary>Get-StatusStrip (1462-1489)</summary>
    private partial string GetStatusStrip(bool Short = false);
    /// <summary>Render-Header (1491-1535)</summary>
    private partial List<string> RenderHeader(int W);
    /// <summary>Render-Log (1537-1560)</summary>
    private partial List<string> RenderLog(int W, int H);
    /// <summary>Render-Help (1562-1590)</summary>
    private partial List<string> RenderHelp(int W, int H);
    /// <summary>Render-Packs (1592-1624)</summary>
    private partial List<string> RenderPacks(int W, int H);
    /// <summary>Mark (1626)</summary>
    private partial string Mark(int state);
    /// <summary>Render-Confirm (1627-1641)</summary>
    private partial List<string> RenderConfirm(int W, int H);
    /// <summary>Render-Closing (1642-1664)</summary>
    private partial List<string> RenderClosing(int W, int H);
    /// <summary>Render-Mini (1667-1707)</summary>
    private partial List<string> RenderMini(int W, int H);
    /// <summary>Render-Server (1709-1727)</summary>
    private partial List<string> RenderServer(int W, int H);

    // ---------- Komutlar ve tuşlar (App.Commands.cs) ----------
    /// <summary>Cmd (852): ekranda gösterilen komut adı</summary>
    private partial string Cmd(string tr);
    /// <summary>Run-Command (855-902)</summary>
    private partial void RunCommand(string line);
    /// <summary>Complete-Input (903-919)</summary>
    private partial void CompleteInput();
    /// <summary>Handle-Key (922-977)</summary>
    private partial void HandleKey(ConsoleKeyInfo k);

    // ---------- Yeni ekranlar (ilk açılış, ayarlar, kaldır) ----------
    private partial List<string> RenderFirstRun(int W, int H);
    private partial void HandleFirstRunKey(ConsoleKeyInfo k, bool ctrl);
    private partial List<string> RenderSettings(int W, int H);
    private partial void HandleSettingsKey(ConsoleKeyInfo k, bool ctrl);
    private partial List<string> RenderUninstall(int W, int H);
    private partial void HandleUninstallKey(ConsoleKeyInfo k, bool ctrl);

    // ---------- Java (Core/Java.cs'e köprü; test modunda sonuç sabitlenebilir) ----------
    int GetJavaMajor(string mc) => Java.GetMajor(mc);

    string FindJava(int major)
    {
        if (TestJavaFound.HasValue) return TestJavaFound.Value ? "java.exe" : null;
        return Java.Find(major, Data);
    }

    bool PlayitOn()
    {
        if (TestPlayitOn.HasValue) return TestPlayitOn.Value;
        return Pl != null && Pl.Running;
    }
}
