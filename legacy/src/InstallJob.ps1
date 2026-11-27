# =====================================================================
#  SyHost - sihirbazın arka plan kurulumu (Terminal sürümü; C# Core/Installer.cs Run)
#  Aynı 7 adım, aynı ekran metinleri, aynı dosyalar. Begin-Install (SyHost.ps1) bu dosyayı ayrı bir çalışma
#  alanında çalıştırır; yardımcılar Install.ps1 ve Java.ps1'den diskten yüklenir (metinden kod üretilmez).
#  İlerlemeyi $sync'e yazar; ne olursa olsun en sonda $sync.Done = $true olur (ekran "kuruluyor"da takılı kalmaz).
#  Ekran metinleri: Begin-Install bu dosyadaki L anahtarlarını ana iş parçacığında çevirip $tt ile verir.
# =====================================================================
param($sync, $info, $target, $worldName, $voiceHost, $maxPlayers, $motd, $dataDir, $tt)
$zip = $null; $cur = 0
try {
    $ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
    # Ekran metinleri ana iş parçacığında çevrildi ($tt); L burada aynı anahtarlarla o tablodan okur
    function L([string]$Key) { $t = $tt[$Key]; if ($null -eq $t) { $t = $Key }; if ($args.Count) { return ($t -f $args) }; $t }
    function Step([int]$i, [int]$st) { if ($i -ge 0 -and $i -lt $sync.Steps.Count) { $sync.Steps[$i].S = $st }; if ($st -eq 1) { Set-Variable -Name cur -Value $i -Scope 1 } }
    function Det([string]$t) { $sync.Detail = $t }
    . (Join-Path $PSScriptRoot 'Install.ps1')
    # Java yardımcıları (Get-JavaMajor, Find-Java, Install-Java) SyHost'un Data klasörünü $DataDir'den okur
    $DataDir = $dataDir; $Data = $dataDir
    . (Join-Path $PSScriptRoot 'Java.ps1')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # Paralel indirmeler aynı sunucuya gider: .NET Framework'ün varsayılanı sunucu başına 2 bağlantı
    if ([Net.ServicePointManager]::DefaultConnectionLimit -lt 2 * $InstAtOnce) { [Net.ServicePointManager]::DefaultConnectionLimit = 2 * $InstAtOnce }

    $zip = [IO.Compression.ZipFile]::OpenRead($info.Path)
    $ie = $zip.GetEntry('modrinth.index.json')
    if (-not $ie) { throw (L 'Bu dosya bir Modrinth paketi (.mrpack) değil.') }
    $sr = New-Object IO.StreamReader($ie.Open())
    try { $index = $sr.ReadToEnd() | ConvertFrom-Json } finally { $sr.Dispose() }
    $files = Inst-ServerFiles $index
    $mc = $info.Mc; $lv = $info.LoaderVer
    $full = [IO.Path]::GetFullPath($target)

    # 0 klasör
    $cur = 0; Step 0 1
    [void][IO.Directory]::CreateDirectory($target)
    [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($target, 'mods'))
    Step 0 2

    # 1 Java
    $cur = 1; Step 1 1
    $jm = Get-JavaMajor $mc
    $java = Find-Java $jm
    if (-not $java) {
        # Eskiden winget ile bilgisayara kurulurdu; artık SyHost'un kendi klasörüne iner (Install-Java)
        $why = $null; $got = @()
        Det (L 'Java {0} indiriliyor...' $jm)
        try {
            $onDetail = { param($t) $sync.Detail = [string]$t }.GetNewClosure()
            $more = @{}
            $ij = Get-Command Install-Java -CommandType Function -ErrorAction SilentlyContinue
            if ($ij -and $ij.Parameters.ContainsKey('HeadText')) { $more.HeadText = (L 'Java {0} indiriliyor...' $jm) }
            $got = @(Install-Java $jm $onDetail @more)
        } catch { $why = Inst-BaseError $_.Exception }
        $java = Find-Java $jm
        # Find-Java bulamadı ama Install-Java denetlenmiş java.exe'nin yolunu verdi
        if (-not $java -and $got.Count -gt 0 -and $got[-1] -is [string] -and [IO.File]::Exists($got[-1])) { $java = $got[-1] }
        if (-not $java) {
            Inst-Note $target ('Java ' + $jm + ' could not be prepared: ' + (Inst-Chain $why))
            throw (L 'Java {0} kurulamadı.' $jm)
        }
    }
    Det (L 'Java {0} hazır' $jm)
    Step 1 2

    # 2 Mod yükleyici
    $cur = 2; Step 2 1
    $launch = $null
    switch ($info.Loader) {
        'neoforge' {
            Det (L '{0} {1} indiriliyor' 'NeoForge' $lv)
            $inst = [IO.Path]::Combine($target, 'neoforge-installer.jar')
            Inst-SaveUrl "https://maven.neoforged.net/releases/net/neoforged/neoforge/$lv/neoforge-$lv-installer.jar" $inst
            Det (L '{0} {1} kuruluyor (biraz sürebilir)' 'NeoForge' $lv)
            if (-not (Inst-RunInstaller $java $inst '--install-server' $target)) { throw (L '{0} kurulamadı (kurulum.log dosyasına bak).' 'NeoForge') }
            Inst-Delete $inst; Inst-Delete ([IO.Path]::Combine($target, 'neoforge-installer.jar.log'))
            $launch = "@libraries/net/neoforged/neoforge/$lv/win_args.txt nogui"
        }
        'forge' {
            $fv = "$mc-$lv"
            Det (L '{0} {1} indiriliyor' 'Forge' $fv)
            $inst = [IO.Path]::Combine($target, 'forge-installer.jar')
            Inst-SaveUrl "https://maven.minecraftforge.net/net/minecraftforge/forge/$fv/forge-$fv-installer.jar" $inst
            Det (L '{0} {1} kuruluyor (biraz sürebilir)' 'Forge' $fv)
            if (-not (Inst-RunInstaller $java $inst '--installServer' $target)) { throw (L '{0} kurulamadı (kurulum.log dosyasına bak).' 'Forge') }
            Inst-Delete $inst; Inst-Delete ([IO.Path]::Combine($target, 'forge-installer.jar.log'))
            $winArgs = [IO.Path]::Combine($target, "libraries\net\minecraftforge\forge\$fv\win_args.txt")
            if ([IO.File]::Exists($winArgs) -or [IO.Directory]::Exists($winArgs)) { $launch = "@libraries/net/minecraftforge/forge/$fv/win_args.txt nogui" }
            else {
                # Eski Forge (1.16 ve öncesi): forge-*.jar ile başlar
                $jar = Get-ChildItem -LiteralPath $target -Filter 'forge-*.jar' | Where-Object { $_.Name -notmatch 'installer' } | Select-Object -First 1
                if (-not $jar) { throw (L 'Forge başlatma dosyası bulunamadı.') }
                $launch = "-jar $($jar.Name) nogui"
            }
        }
        'fabric' {
            Det (L '{0} {1} indiriliyor' 'Fabric' $lv)
            $instVer = Inst-FabricVersion
            Inst-SaveUrl "https://meta.fabricmc.net/v2/versions/loader/$mc/$lv/$instVer/server/jar" ([IO.Path]::Combine($target, 'fabric-server-launch.jar'))
            $launch = '-jar fabric-server-launch.jar nogui'
        }
        default { throw (L '{0} henüz desteklenmiyor (NeoForge, Forge ve Fabric destekleniyor).' $info.Loader) }
    }
    Step 2 2

    # 3 Modlar (aynı anda 6 dosya; doğrulanmayan dosya yerine konmaz)
    $cur = 3; Step 3 1
    $sync.Failed = @(Inst-AllMods $sync $files $target $full)
    $sync.Pct = 100
    Step 3 2

    # 4 Ayar dosyaları: önce overrides, sonra server-overrides (Modrinth kuralı: sunucuya özel olan kazanır;
    # eskiden zip'teki sıraya göre hangisi sonra geldiyse o kalıyordu)
    $cur = 4; Step 4 1
    foreach ($pre in 'overrides/', 'server-overrides/') {
        foreach ($en in $zip.Entries) {
            $fn = $en.FullName
            if (-not $fn.StartsWith($pre, [StringComparison]::Ordinal) -or -not $en.Name) { continue }
            $rel = $fn.Substring($pre.Length)
            if ($rel -match '^(resourcepacks|shaderpacks|saves)/') { continue }
            $dst = Inst-Inside $target $rel $full
            if (-not $dst) { continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($en, $dst, $true)
        }
    }
    Step 4 2

    # 5 Dünya
    $cur = 5; Step 5 1
    if ($worldName) {
        Det (L 'Paketteki dünya kopyalanıyor')
        $pre = "overrides/saves/$worldName/"
        $worldDir = [IO.Path]::Combine($target, 'world')
        foreach ($en in $zip.Entries) {
            if (-not $en.FullName.StartsWith($pre, [StringComparison]::Ordinal) -or -not $en.Name) { continue }
            $rel = $en.FullName.Substring($pre.Length)
            if ($rel -eq 'session.lock') { continue }
            $dst = Inst-Inside $worldDir $rel $full
            if (-not $dst) { continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($en, $dst, $true)
        }
    } else { Det (L 'İlk açılışta yeni bir dünya oluşturulacak') }
    Step 5 2

    # 6 Son ayarlar
    $cur = 6; Step 6 1
    $props = [ordered]@{ 'motd' = $motd; 'level-name' = 'world'; 'max-players' = "$maxPlayers"; 'online-mode' = 'true'; 'difficulty' = 'normal'; 'spawn-protection' = '0'; 'view-distance' = '10'; 'simulation-distance' = '8'; 'allow-flight' = 'true'; 'server-port' = '25565'; 'enable-command-block' = 'true' }
    $pf = [IO.Path]::Combine($target, 'server.properties')
    $lines = New-Object System.Collections.Generic.List[string]
    if ([IO.File]::Exists($pf) -or [IO.Directory]::Exists($pf)) { foreach ($ln in [IO.File]::ReadAllLines($pf)) { $lines.Add($ln) } }
    foreach ($k in $props.Keys) {
        $found = $false
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^$([regex]::Escape($k))=") { $lines[$i] = "$k=$($props[$k])"; $found = $true } }
        if (-not $found) { $lines.Add("$k=$($props[$k])") }
    }
    [IO.File]::WriteAllLines($pf, $lines.ToArray(), (New-Object Text.UTF8Encoding $false))
    [IO.File]::WriteAllText([IO.Path]::Combine($target, 'eula.txt'), "eula=true`r`n", [Text.Encoding]::ASCII)
    $modsDir = [IO.Path]::Combine($target, 'mods')
    if ($voiceHost -and [IO.Directory]::Exists($modsDir) -and @(Get-ChildItem -LiteralPath $modsDir -Filter '*voicechat*' -ErrorAction SilentlyContinue).Count) {
        $vd = [IO.Path]::Combine($target, 'config\voicechat'); [void][IO.Directory]::CreateDirectory($vd)
        $vp = [IO.Path]::Combine($vd, 'voicechat-server.properties')
        if (-not ([IO.File]::Exists($vp) -or [IO.Directory]::Exists($vp))) { [IO.File]::WriteAllLines($vp, [string[]]@('port=24454', 'bind_address=', "voice_host=$voiceHost"), (New-Object Text.UTF8Encoding $false)) }
        else { $vt = [IO.File]::ReadAllText($vp); if ($vt -match '(?m)^voice_host=') { $vt = [regex]::Replace($vt, '(?m)^voice_host=.*$', "voice_host=$voiceHost") } else { $vt = $vt.TrimEnd() + "`nvoice_host=$voiceHost`n" }; [IO.File]::WriteAllText($vp, $vt, (New-Object Text.UTF8Encoding $false)) }
    }
    Step 6 2
    $zip.Dispose(); $zip = $null
    $sync.Result = @{ mc = $mc; loader = $info.Loader; loaderSurum = $lv; java = $jm; baslat = $launch }
} catch {
    # Ekranda olduğu gibi görünür: .NET hatasının asıl metni ('Exception calling ...' sarmalı olmadan)
    $ex = $_.Exception
    while ($ex -is [Management.Automation.ExtendedTypeSystemException] -and $ex.InnerException) { $ex = $ex.InnerException }
    $sync.Error = $(if ($ex.Message) { $ex.Message } else { $ex.GetType().Name })
    try { $sync.Steps[$cur].S = 3 } catch {}
} finally {
    try { if ($zip) { $zip.Dispose() } } catch {}
    $sync.Done = $true   # en sonda: ekran bunu görünce sonucu okur (Check-Install)
}
