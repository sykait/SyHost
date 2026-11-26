// GEÇİCİ: tepsi bölümü yazılınca bu dosya silinir (yerine Core/Tray.cs gelir)
using System.Collections.Concurrent;

namespace SyHost;

/// <summary>Saat yanındaki simge, menüsü, balon bildirimleri ve her yerden çalışan kısayol tuşları.</summary>
static class Tray
{
    public static readonly ConcurrentQueue<string> Actions = new();
    public static string HotkeyStatus => "";
    public static void Start(string text) { }
    public static void Balloon(string title, string msg) { }
    public static void SetText(string s) { }
    public static void Close() { }
}
