// GEÇİCİ: sihirbaz bölümü yazılınca bu dosya silinir (yerine App/App.Wizard.cs gelir)
namespace SyHost;

sealed partial class App
{
    private partial PackInfo ReadPack(string path) => throw new NotImplementedException();
    private partial string SafeFolderName(string name) => name;
    private partial void StartWizard() { }
    private partial List<(string Label, string Value)> WizardWorldOptions() => new();
    private partial List<string> InstallStepNames(PackInfo info) => new();
    private partial void BeginInstall() { }
    private partial void CheckInstall() { }
    private partial List<string> RenderWizard(int W, int H) => new() { "  (sihirbaz yapım aşamasında)" };
    private partial void HandleWizardKey(ConsoleKeyInfo k, bool ctrl) { if (k.Key == ConsoleKey.Escape) { Screen = "home"; ResetFrame(); } }
}
