// GEÇİCİ: sunucu kontrol bölümü yazılınca bu dosya silinir (yerine App/App.Server.cs gelir)
namespace SyHost;

sealed partial class App
{
    private partial void LoadServers() { }
    private partial void SaveServers() { }
    private partial long GetMask(int n) => 0;
    private partial void ApplyPackLive() { }
    private partial void SetPack(string name) { }
    private partial void StartPlayit() { }
    private partial void StopPlayit() { }
    private partial int GetModCount(string dir) => 0;
    private partial void EnsureVoiceHost() { }
    private partial void StartServer() { }
    private partial void StopServer(string then) { }
    private partial void StartBackup() { }
    private partial void BeginZip() { }
    private partial void CheckBackup() { }
    private partial void AddServerLine(string raw) { }
    private partial void EnterServer(ServerEntry srv) { }
    private partial void GoHome() { Screen = "home"; ResetFrame(); }
    private partial void BeginShutdown(string after) { }
    private partial void HidePanel() { }
}
