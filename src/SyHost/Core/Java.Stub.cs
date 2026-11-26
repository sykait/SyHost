// GEÇİCİ: Java bölümü yazılınca bu dosya silinir (yerine Core/Java.cs gelir)
namespace SyHost;

static class Java
{
    /// <summary>Get-JavaMajor: Minecraft sürümüne göre gereken Java (8, 17, 21)</summary>
    public static int GetMajor(string mc) => 21;
    /// <summary>Find-Java: önce bilgisayardaki Java, yoksa SyHost'un indirdiği (Data\tools\java-N)</summary>
    public static string Find(int major, string dataDir) => null;
    /// <summary>Java'yı Data\tools\java-N içine indirir, java.exe yolunu döner (hata olursa fırlatır)</summary>
    public static string Download(int major, string dataDir, Action<string> detail) => throw new NotImplementedException();
}
