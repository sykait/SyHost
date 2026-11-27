// =====================================================================
//  SyHost - indirilen bir programın imzası (Authenticode) geçerli mi?
//  playit GitHub'dan imzalı sürümüyle indirilir; dosya çalıştırılmadan önce Windows'a sorulur (WinVerifyTrust):
//  imza bozuk, eksik ya da Windows'un güvenmediği bir yayıncıdansa kullanılmaz. Yayıncının adı denetlenmez (playit
//  sertifikasını yenileyince kurulum bozulmasın). Pencere açılmaz, iptal listesi için internete çıkılmaz (yalnızca
//  Windows'un önbelleği). Dosyaya gömülü imzaya bakar (playit öyledir). Terminal sürümünde aynı karar PowerShell'in
//  Get-AuthenticodeSignature'ıyla verilir (FirstRunJob.ps1); o, iptal ve katalog denetimini Windows'un varsayılanıyla yapar.
// =====================================================================
using System.Runtime.InteropServices;

namespace SyHost;

static unsafe partial class Trust
{
    // WINTRUST_ACTION_GENERIC_VERIFY_V2
    static readonly Guid GenericVerifyV2 = new("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

    [StructLayout(LayoutKind.Sequential)]
    struct WtFile { public uint cbStruct; public nint pcwszFilePath; public nint hFile; public nint pgKnownSubject; }

    [StructLayout(LayoutKind.Sequential)]
    struct WtData
    {
        public uint cbStruct; public nint pPolicyCallbackData; public nint pSIPClientData; public uint dwUIChoice; public uint fdwRevocationChecks;
        public uint dwUnionChoice; public nint pFile; public uint dwStateAction; public nint hWVTStateData; public nint pwszURLReference;
        public uint dwProvFlags; public uint dwUIContext; public nint pSignatureSettings;
    }

    [LibraryImport("wintrust.dll")] private static partial int WinVerifyTrust(nint hwnd, Guid* action, WtData* data);

    /// <summary>Dosyanın Authenticode imzası geçerli ve Windows'un güvendiği bir yayıncıdan mı?</summary>
    public static bool IsSigned(string path)
    {
        nint p = Marshal.StringToHGlobalUni(path);
        try
        {
            var file = new WtFile { cbStruct = (uint)sizeof(WtFile), pcwszFilePath = p };
            var data = new WtData
            {
                cbStruct = (uint)sizeof(WtData),
                dwUIChoice = 2,          // WTD_UI_NONE
                fdwRevocationChecks = 0, // WTD_REVOKE_NONE
                dwUnionChoice = 1,       // WTD_CHOICE_FILE
                pFile = (nint)(&file),
                dwStateAction = 1,       // WTD_STATEACTION_VERIFY
                dwProvFlags = 0x1000,    // WTD_CACHE_ONLY_URL_RETRIEVAL
            };
            Guid action = GenericVerifyV2;
            int result = WinVerifyTrust(-1, &action, &data);   // -1: kullanıcıya hiçbir şey sorulmaz
            data.dwStateAction = 2;                            // WTD_STATEACTION_CLOSE
            WinVerifyTrust(-1, &action, &data);
            return result == 0;
        }
        catch { return false; }
        finally { Marshal.FreeHGlobal(p); }
    }
}
