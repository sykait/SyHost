// GEÇİCİ: komut ve tuş bölümü yazılınca bu dosya silinir (yerine App/App.Commands.cs gelir)
namespace SyHost;

sealed partial class App
{
    private partial string Cmd(string tr) => tr;
    private partial void RunCommand(string line) { }
    private partial void CompleteInput() { }
    private partial void HandleKey(ConsoleKeyInfo k)
    {
        Dirty = true;
        bool ctrl = (k.Modifiers & ConsoleModifiers.Control) != 0;
        switch (Screen)
        {
            case "splash": AfterSplash(); return;
            case "outro": Quit = true; return;
            case "home": if (k.Key == ConsoleKey.F9) { OpenSettings(); return; } HandleHomeKey(k, ctrl); return;
            case "wizard": HandleWizardKey(k, ctrl); return;
            case "firstrun": HandleFirstRunKey(k, ctrl); return;
            case "settings": HandleSettingsKey(k, ctrl); return;
            case "uninstall": HandleUninstallKey(k, ctrl); return;
        }
    }
}
