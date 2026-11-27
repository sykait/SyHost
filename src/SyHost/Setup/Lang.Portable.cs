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
        // Terminal sürümü: PowerShell açılışta kapandıysa olası neden (başlatıcının hata penceresinde, sebebin altında)
        Tx("Bir SyHost dosyası yazıldıktan hemen sonra kayboldu:\n{0}\n\nBir virüs tarayıcısı kaldırmış olabilir. README'deki \"Güvenlik ve virüs tarayıcıları\" bölümüne bak.",
           "A SyHost file disappeared right after it was written:\n{0}\n\nAn antivirus program may have removed it. See \"Security and antivirus\" in the README.",
           "SyHost のファイルが書き込まれた直後に消えました:\n{0}\n\nウイルス対策ソフトが削除した可能性があります。README の「セキュリティとウイルス対策ソフト」を参照してください。");
        Tx("SyHost klasörü bir ağ konumunda. Windows PowerShell oradaki betikleri çalıştırmayabilir: SyHost klasörünü bu bilgisayardaki bir sürücüye taşı ya da SyHost Modern'i kullan.",
           "The SyHost folder is on a network location. Windows PowerShell may refuse to run scripts there: move the SyHost folder to a drive on this PC, or use SyHost Modern.",
           "SyHost フォルダーはネットワーク上にあります。Windows PowerShell はそこにあるスクリプトを実行しないことがあります。SyHost フォルダーをこの PC のドライブに移動するか、SyHost Modern を使ってください。");
    }
}
