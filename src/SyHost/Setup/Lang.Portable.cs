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
        Tx("SyHost bu klasöre yazamıyor:\n{0}\n\nSyHost klasörünü içindekilerle birlikte (SyHost.exe, Servers ve Data) yazılabilir bir yere taşı (ör. {1}) ve SyHost.exe'yi oradan aç.",
           "SyHost can't write to this folder:\n{0}\n\nMove the whole SyHost folder (SyHost.exe together with Servers and Data) to a place you can write to (for example {1}) and open SyHost.exe from there.",
           "SyHost はこのフォルダーに書き込めません:\n{0}\n\nSyHost フォルダーを中身ごと（SyHost.exe、Servers、Data）書き込める場所（例: {1}）に移動し、そこから SyHost.exe を開いてください。");
    }
}
