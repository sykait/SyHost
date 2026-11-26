// GEÇİCİ: sunucu ekranı çizimi yazılınca bu dosya silinir (yerine App/App.ServerView.cs gelir)
namespace SyHost;

sealed partial class App
{
    private partial int GetStartPct() => 0;
    private partial string GetStatusStrip(bool Short) => "";
    private partial List<string> RenderHeader(int W) => new();
    private partial List<string> RenderLog(int W, int H) => new();
    private partial List<string> RenderHelp(int W, int H) => new();
    private partial List<string> RenderPacks(int W, int H) => new();
    private partial string Mark(int state) => "";
    private partial List<string> RenderConfirm(int W, int H) => new();
    private partial List<string> RenderClosing(int W, int H) => new();
    private partial List<string> RenderMini(int W, int H) => new();
    private partial List<string> RenderServer(int W, int H) => new() { "  (sunucu ekranı yapım aşamasında)" };
}
