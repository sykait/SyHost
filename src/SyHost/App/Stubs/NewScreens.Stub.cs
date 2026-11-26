// GEÇİCİ: ilk açılış, ayarlar ve kaldır ekranları yazılınca bu dosya silinir
namespace SyHost;

sealed partial class App
{
    private partial List<string> RenderFirstRun(int W, int H) => new();
    private partial void HandleFirstRunKey(ConsoleKeyInfo k, bool ctrl) { }
    private partial List<string> RenderSettings(int W, int H) => new();
    private partial void HandleSettingsKey(ConsoleKeyInfo k, bool ctrl) { }
    private partial List<string> RenderUninstall(int W, int H) => new();
    private partial void HandleUninstallKey(ConsoleKeyInfo k, bool ctrl) { }
}
