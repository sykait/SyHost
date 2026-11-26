// =====================================================================
//  SyHost - test modu: yeni ekranların (ilk açılış, ayarlar, kaldır) senaryo alanları
//  Terminal sürümündeki karşılığı aynı alanları okur; iki sürüm aynı kareyi çizmelidir.
//  Senaryo "state" içindeki alanlar:
//    appRoot, setupMode, defaultRoot, legacyDir, osBuild, dryRun, fontOk, javaOwn, playitReady,
//    javaFound (true/false ya da {"25":false,"21":true,...}), shortcuts {"desktop":"ours|none|other|dead|foreign","start":...},
//    migrated {"servers":1,"playit":true}, movedTo,
//    firstRun {steps,index,sel,returnTo,target,otherInstall,note,noteCol,confirm,busy,jobText,desk,start,phase,field,mcAddr,voiceAddr},
//    settings {sel,note,noteCol}, uninstall {items:[{key,title,detail,on,needsAdmin,state,error}],sel,phase}
//  Renk adları: yellow, red, green, dim, soft, text.
// =====================================================================
using System.Text.Json;

namespace SyHost;

sealed partial class App
{
    string ColorByName(string n) => n switch
    {
        "yellow" => c.yellow, "red" => c.red, "green" => c.green, "dim" => c.dim, "soft" => c.soft, "text" => c.text, "brass" => c.brass,
        _ => null,
    };

    void ApplyScenarioScreens(JsonElement st)
    {
        static bool Has(JsonElement e, string n, out JsonElement v) => e.TryGetProperty(n, out v) && v.ValueKind != JsonValueKind.Null;
        static string Str(JsonElement e, string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
        static bool Bool(JsonElement e, string n, bool def = false) => e.TryGetProperty(n, out var v) && (v.ValueKind == JsonValueKind.True || v.ValueKind == JsonValueKind.False) ? v.GetBoolean() : def;
        static int Int(JsonElement e, string n, int def = 0) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt32() : def;

        if (Has(st, "appRoot", out var v)) AppRoot = v.GetString();
        if (Has(st, "setupMode", out v)) SetupMode = v.GetBoolean();
        if (Has(st, "defaultRoot", out v)) TestDefaultRoot = v.GetString();
        if (Has(st, "legacyDir", out v)) TestLegacyDir = v.GetString();
        if (Has(st, "osBuild", out v)) TestOsBuild = v.GetInt32();
        if (Has(st, "dryRun", out v)) TestDryRun = v.GetBoolean();
        if (Has(st, "fontOk", out v)) TestFontOk = v.GetBoolean();
        if (Has(st, "javaOwn", out v)) TestJavaOwn = v.GetBoolean();
        if (Has(st, "playitReady", out v)) TestPlayitReady = v.GetBoolean();
        if (Has(st, "javaFound", out v) && v.ValueKind == JsonValueKind.Object)
        {
            TestJava = new Dictionary<int, bool>();
            foreach (var p in v.EnumerateObject()) TestJava[int.Parse(p.Name, Ps.Inv)] = p.Value.GetBoolean();
        }
        if (Has(st, "shortcuts", out v))
        {
            TestShortcut = new Dictionary<string, Shortcuts.State>();
            foreach (var p in v.EnumerateObject())
                TestShortcut[p.Name] = p.Value.GetString() switch
                {
                    "ours" => Shortcuts.State.Ours, "other" => Shortcuts.State.OtherLive, "dead" => Shortcuts.State.Dead,
                    "foreign" => Shortcuts.State.Foreign, _ => Shortcuts.State.Missing,
                };
        }
        if (Has(st, "migrated", out v)) FrMigrated = new Migration.Result { Servers = Int(v, "servers"), Playit = Bool(v, "playit") };
        if (Has(st, "movedTo", out v)) FrMovedTo = v.GetString();

        if (Has(st, "firstRun", out var f))
        {
            Fr = new FirstRunState
            {
                Index = Int(f, "index"), Sel = Int(f, "sel"), ReturnTo = Str(f, "returnTo"),
                Target = Str(f, "target"), OtherInstall = Str(f, "otherInstall"),
                Note = Str(f, "note"), NoteCol = ColorByName(Str(f, "noteCol")), Confirm = Bool(f, "confirm"),
                JobText = Str(f, "jobText") ?? "", Desk = Bool(f, "desk", true), Start = Bool(f, "start", true),
                Phase = Str(f, "phase") ?? "", Field = Int(f, "field"), McAddr = Str(f, "mcAddr") ?? "", VoiceAddr = Str(f, "voiceAddr") ?? "",
            };
            foreach (var s in f.GetProperty("steps").EnumerateArray()) Fr.Steps.Add(s.GetString());
            if (Bool(f, "busy")) { Fr.Job = new Task(() => { }); Fr.JobDone = false; }
        }
        if (Has(st, "settings", out var s2))
        {
            SetSel = Int(s2, "sel"); SetNote = Str(s2, "note"); SetNoteCol = ColorByName(Str(s2, "noteCol"));
        }
        if (Has(st, "uninstall", out var u))
        {
            UnItems = new List<Uninstall.Item>();
            foreach (var it in u.GetProperty("items").EnumerateArray())
                UnItems.Add(new Uninstall.Item
                {
                    Key = Str(it, "key"), Title = Str(it, "title"), Detail = Str(it, "detail") ?? "", On = Bool(it, "on"),
                    NeedsAdmin = Bool(it, "needsAdmin"), State = Int(it, "state"), Error = Str(it, "error"),
                });
            UnSel = Int(u, "sel"); UnPhase = Str(u, "phase") ?? "liste";
        }
    }
}
