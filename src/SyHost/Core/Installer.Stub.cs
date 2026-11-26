// GEÇİCİ: kurulum bölümü yazılınca bu dosya silinir (yerine Core/Installer.cs gelir)
namespace SyHost;

static class Installer
{
    /// <summary>$InstallScript (SyHost.ps1 634-793): sunucuyu kurar. Arka plan iş parçacığında çağrılır,
    /// ilerlemeyi sync'e yazar, bitince sync.Done = true yapar. Hata olursa sync.Error doldurulur.</summary>
    public static void Run(InstallSync sync, PackInfo info, string target, string worldName, string voiceHost, int maxPlayers, string motd, string dataDir)
    {
        sync.Error = "not implemented";
        sync.Done = true;
    }
}
