// =====================================================================
//  SyHost - taşınabilir klasör, kısayollar ve eski verinin taşınması metinleri
// =====================================================================
namespace SyHost;

static partial class Lang
{
    static partial void AddPortable()
    {
        // Explorer'da görünen klasör adları (diskteki ad değişmez)
        Tx("Sunucular", "Servers", "サーバー");
        Tx("Yedekler", "Backups", "バックアップ");
        // Kısayol açıklaması
        Tx("SyHost - modlu Minecraft sunucu merkezi", "SyHost - modded Minecraft server hub", "SyHost - MOD入り Minecraft サーバーハブ");
        Tx("Kısayollar yeni yere güncellendi.", "Shortcuts now point to the new location.", "ショートカットを新しい場所に更新しました。");
        // Klasöre yazılamıyorsa (ör. Program Files) konsol açılmadan gösterilir
        Tx("SyHost bu klasöre yazamıyor:\n{0}\n\nSyHost.exe'yi yazılabilir bir klasöre taşı (ör. {1}) ve oradan aç.",
           "SyHost can't write to this folder:\n{0}\n\nMove SyHost.exe to a folder you can write to (for example {1}) and open it from there.",
           "SyHost はこのフォルダーに書き込めません:\n{0}\n\nSyHost.exe を書き込み可能なフォルダー（例: {1}）に移動してから開いてください。");
    }
}
