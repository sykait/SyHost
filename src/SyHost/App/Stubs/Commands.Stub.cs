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
            case "splash": Screen = "home"; ResetFrame(); return;
            case "outro": Quit = true; return;
            case "home": HandleHomeKey(k, ctrl); return;
            case "wizard": HandleWizardKey(k, ctrl); return;
        }
    }
}
