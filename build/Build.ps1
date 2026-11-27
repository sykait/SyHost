# =====================================================================
#  SyHost - derleme
#    build\Build.ps1             hızlı derleme denetimi (Debug)
#    build\Build.ps1 -Publish    tek dosya SyHost.exe üretir (NativeAOT) -> dist\SyHost.exe
#    build\Build.ps1 -Run        derleyip test klasöründe açar (geliştirme için)
#    build\Build.ps1 -Publish -Terminal   ayrıca Terminal sürümünü tek exe yapar -> dist\SyHost-Terminal.exe
#                                         (PowerShell uygulaması + SyHost.Core.dll exe'nin içinde)
#    build\Build.ps1 -Terminal            hızlı derleme denetimine Terminal başlatıcısını da ekler
#  Gerekenler: .NET 10 SDK ve Visual Studio C++ derleme araçları (yalnızca -Publish için).
#  Terminal sürümü ayrıca Windows'un .NET Framework 4 derleyicisini (csc.exe) kullanır.
# =====================================================================
[CmdletBinding()]
param(
    [switch]$Publish,
    [switch]$Terminal,
    [switch]$Run,
    [string]$RunRoot = 'D:\SyHostTest\dev'
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $Repo 'src\SyHost\SyHost.csproj'
$TerminalProject = Join-Path $Repo 'src\SyHost.Terminal\SyHost.Terminal.csproj'
$Dist = Join-Path $Repo 'dist'

$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'

# .NET: önce kullanıcıya özel kurulum, yoksa PATH'teki
$userDotnet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
if (Test-Path $userDotnet) { $Dotnet = $userDotnet; $env:DOTNET_ROOT = Split-Path $userDotnet }
else { $Dotnet = (Get-Command dotnet -ErrorAction Stop).Source }

function Invoke-Dotnet([string[]]$a) {
    & $Dotnet @a
    if ($LASTEXITCODE -ne 0) { throw "dotnet $($a[0]) başarısız (kod $LASTEXITCODE)" }
}

# NativeAOT için C++ bağlayıcısı: Visual Studio kendini düzgün kaydetmemişse ortamı biz hazırlarız
function Use-VcEnvironment {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $false }
    $normal = & $vswhere -latest -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($normal) { return $false }   # NativeAOT kendisi bulur
    $any = & $vswhere -all -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
    if (-not $any) { return $false }
    $vcvars = Join-Path $any 'VC\Auxiliary\Build\vcvarsall.bat'
    if (-not (Test-Path $vcvars)) { return $false }
    foreach ($l in (cmd /c "`"$vcvars`" amd64 >nul 2>&1 && set")) {
        $i = $l.IndexOf('=')
        if ($i -gt 0) { Set-Item -Path ('env:' + $l.Substring(0, $i)) -Value $l.Substring($i + 1) }
    }
    Remove-Item env:Platform -ErrorAction SilentlyContinue   # vcvarsall'ın Platform değişkeni çıktı klasörlerini değiştirir
    $true
}

if ($Publish) {
    $envTools = Use-VcEnvironment
    $out = Join-Path $Repo 'src\SyHost\bin\publish'
    $a = @('publish', $Project, '-c', 'Release', '-r', 'win-x64', '-o', $out, '-nologo')
    if ($envTools) { $a += '-p:IlcUseEnvironmentalTools=true' }
    Invoke-Dotnet $a
    New-Item -ItemType Directory -Force $Dist | Out-Null
    Copy-Item (Join-Path $out 'SyHost.exe') (Join-Path $Dist 'SyHost.exe') -Force
    $kb = [int]((Get-Item (Join-Path $Dist 'SyHost.exe')).Length / 1KB)
    Write-Host "dist\SyHost.exe hazır ($kb KB)" -ForegroundColor Green

    # Terminal (PowerShell) sürümü: PowerShell uygulamasını içinde taşıyan tek exe
    if ($Terminal) {
        if (Test-Path $TerminalProject) {
            # Önce PowerShell sürümünün yardımcı kodu: legacy\src\SyHost.*.cs -> SyHost.Core.dll (.NET Framework csc.exe).
            # Hata varsa burada, uzun NativeAOT derlemesinden önce görünür. Yayınlama aynı dosyayı exe'ye gömer.
            Invoke-Dotnet @('msbuild', $TerminalProject, '-t:SyHostCoreDll', '-nologo', '-v:m')
            $tout = Join-Path $Repo 'src\SyHost.Terminal\bin\publish'
            $ta = @('publish', $TerminalProject, '-c', 'Release', '-r', 'win-x64', '-o', $tout, '-nologo')
            if ($envTools) { $ta += '-p:IlcUseEnvironmentalTools=true' }
            Invoke-Dotnet $ta
            # Derlemenin adı SyHost (exe'nin sürüm bilgisi ve kurulunca SyHost.exe adı); dağıtılan adı SyHost-Terminal.exe
            Copy-Item (Join-Path $tout 'SyHost.exe') (Join-Path $Dist 'SyHost-Terminal.exe') -Force
            $tkb = [int]((Get-Item (Join-Path $Dist 'SyHost-Terminal.exe')).Length / 1KB)
            Write-Host "dist\SyHost-Terminal.exe hazır ($tkb KB)" -ForegroundColor Green
        } else {
            Write-Warning 'Terminal sürümünün başlatıcısı (src\SyHost.Terminal) henüz yok, atlandı.'
        }
    }
} else {
    Invoke-Dotnet @('build', $Project, '-c', 'Debug', '-nologo', '-v', 'q', '-clp:NoSummary')
    if ($Terminal) { Invoke-Dotnet @('build', $TerminalProject, '-c', 'Debug', '-nologo', '-v', 'q', '-clp:NoSummary') }
    Write-Host 'Derleme başarılı' -ForegroundColor Green
}

if ($Run) {
    $exe = if ($Publish) { Join-Path $Dist 'SyHost.exe' } else { Join-Path $Repo 'src\SyHost\bin\Debug\net10.0-windows\win-x64\SyHost.exe' }
    New-Item -ItemType Directory -Force $RunRoot | Out-Null
    Copy-Item $exe (Join-Path $RunRoot 'SyHost.exe') -Force
    Start-Process (Join-Path $env:SystemRoot 'System32\conhost.exe') -ArgumentList "`"$(Join-Path $RunRoot 'SyHost.exe')`""
}
