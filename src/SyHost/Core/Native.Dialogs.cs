// =====================================================================
//  SyHost - klasör seçme penceresi
//  Windows'un modern klasör seçicisi (IFileOpenDialog + FOS_PICKFOLDERS).
//  NativeAOT uyumlu: COM nesnesi doğrudan sanal tablosu (vtable) üzerinden
//  çağrılır; çalışma anında kod üretimi ya da yansıma (reflection) gerekmez.
// =====================================================================
using System.Runtime.InteropServices;

namespace SyHost;

static unsafe partial class Native
{
    [LibraryImport("ole32.dll", EntryPoint = "CoInitializeEx")] private static partial int DlgCoInitializeEx(nint reserved, uint flags);
    [LibraryImport("ole32.dll", EntryPoint = "CoUninitialize")] private static partial void DlgCoUninitialize();
    [LibraryImport("ole32.dll", EntryPoint = "CoCreateInstance")] private static partial int DlgCoCreateInstance(Guid* clsid, nint outer, uint context, Guid* iid, void** obj);
    [LibraryImport("ole32.dll", EntryPoint = "CoTaskMemFree")] private static partial void DlgCoTaskMemFree(void* p);
    [LibraryImport("shell32.dll", EntryPoint = "SHCreateItemFromParsingName", StringMarshalling = StringMarshalling.Utf16)] private static partial int DlgCreateShellItem(string path, nint bindCtx, Guid* iid, void** obj);

    static readonly Guid DlgClsidFileOpenDialog = new("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7");
    static readonly Guid DlgIidFileOpenDialog = new("D57C7288-D4AD-4768-BE02-9D969532D960");
    static readonly Guid DlgIidShellItem = new("43826D1E-E718-42EE-BC55-A1E261C37BFE");

    /// <summary>Klasör seçme penceresi (konsol penceresinin önünde açılır). initialDir yoksa var olan en yakın üst klasörden başlar.
    /// Seçilen klasörün tam yolu; vazgeçilirse null.</summary>
    public static string PickFolder(string title, string initialDir)
    {
        string result = null;
        var t = new Thread(() => { try { result = DlgPickFolder(title, initialDir); } catch { } });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
        t.Join();
        return result;
    }

    static string DlgPickFolder(string title, string initialDir)
    {
        // IFileOpenDialog sanal tablosundaki sıra: IUnknown (0-2), IModalWindow.Show (3), IFileDialog (4-26)
        const int Show = 3, SetOptions = 9, GetOptions = 10, SetFolder = 12, SetTitle = 17, GetResult = 20;
        const int ItemGetDisplayName = 5;   // IShellItem
        const uint FOS_PICKFOLDERS = 0x20, FOS_FORCEFILESYSTEM = 0x40, FOS_PATHMUSTEXIST = 0x800;
        const uint SIGDN_FILESYSPATH = 0x80058000;

        int init = DlgCoInitializeEx(0, 0x2 | 0x4);   // COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE
        void* dlg = null, folder = null, item = null;
        char* path = null;
        try
        {
            Guid clsid = DlgClsidFileOpenDialog, iid = DlgIidFileOpenDialog;
            if (DlgCoCreateInstance(&clsid, 0, 0x1 /* CLSCTX_INPROC_SERVER */, &iid, &dlg) < 0 || dlg == null) return null;
            void** vt = *(void***)dlg;

            uint options = 0;
            ((delegate* unmanaged[Stdcall]<void*, uint*, int>)vt[GetOptions])(dlg, &options);
            ((delegate* unmanaged[Stdcall]<void*, uint, int>)vt[SetOptions])(dlg, options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
            if (!string.IsNullOrEmpty(title))
            {
                fixed (char* p = title) ((delegate* unmanaged[Stdcall]<void*, char*, int>)vt[SetTitle])(dlg, p);
            }

            string start = DlgExistingDir(initialDir);
            if (start != null)
            {
                Guid itemIid = DlgIidShellItem;
                if (DlgCreateShellItem(start, 0, &itemIid, &folder) >= 0 && folder != null)
                    ((delegate* unmanaged[Stdcall]<void*, void*, int>)vt[SetFolder])(dlg, folder);
            }

            // Kullanıcı kapatana kadar bekler; vazgeçilirse HRESULT_FROM_WIN32(ERROR_CANCELLED) döner
            if (((delegate* unmanaged[Stdcall]<void*, nint, int>)vt[Show])(dlg, GetConsoleWindow()) < 0) return null;
            if (((delegate* unmanaged[Stdcall]<void*, void**, int>)vt[GetResult])(dlg, &item) < 0 || item == null) return null;

            void** ivt = *(void***)item;
            if (((delegate* unmanaged[Stdcall]<void*, uint, char**, int>)ivt[ItemGetDisplayName])(item, SIGDN_FILESYSPATH, &path) < 0 || path == null) return null;
            return new string(path);
        }
        finally
        {
            if (path != null) DlgCoTaskMemFree(path);
            DlgRelease(item);
            DlgRelease(folder);
            DlgRelease(dlg);
            if (init >= 0) DlgCoUninitialize();
        }
    }

    // IUnknown.Release
    static void DlgRelease(void* obj)
    {
        if (obj != null) ((delegate* unmanaged[Stdcall]<void*, uint>)(*(void***)obj)[2])(obj);
    }

    /// <summary>Başlangıç klasörü: verilen klasör yoksa var olan en yakın üst klasörü.</summary>
    static string DlgExistingDir(string dir)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(dir)) return null;
            string d = Path.GetFullPath(Environment.ExpandEnvironmentVariables(dir.Trim()));
            while (!string.IsNullOrEmpty(d) && !Directory.Exists(d)) d = Path.GetDirectoryName(d);
            return string.IsNullOrEmpty(d) ? null : d;
        }
        catch { return null; }
    }
}
