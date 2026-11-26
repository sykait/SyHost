// GEÇİCİ: ana menü bölümü yazılınca bu dosya silinir (yerine App/App.Home.cs gelir)
namespace SyHost;

sealed partial class App
{
    private partial List<string> RenderHome(int W, int H) => new() { "  (ana menü yapım aşamasında)" };
    private partial void HandleHomeKey(ConsoleKeyInfo k, bool ctrl) { if (k.Key == ConsoleKey.F10) StartOutro(); }
    private partial void SwitchLanguage() { }
}
