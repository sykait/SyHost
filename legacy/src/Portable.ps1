# =====================================================================
#  SyHost - taşınabilir klasör (Terminal sürümü)  [GEÇİCİ İSKELET]
#  C# karşılığı: src\SyHost\Setup\Portable.cs, Migration.cs, FolderLook.cs, Fonts.cs, Shortcuts.cs,
#  Core\Java.cs (bulma ve indirme). Bu dosya tam sürümüyle değiştirilecek.
# =====================================================================
function Get-UiLanguage { $two = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName; if ($two -eq 'tr') { 'tr' } elseif ($two -eq 'ja') { 'ja' } else { 'en' } }
function Get-DefaultRoot { if ($env:SYHOST_DEFAULT_ROOT) { $env:SYHOST_DEFAULT_ROOT } else { [IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'), 'SyHost') } }
function Get-LegacyDir { if ($env:SYHOST_LEGACY_DATA) { $env:SYHOST_LEGACY_DATA } else { [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'SyHost') } }
function Test-DryRun { $env:SYHOST_DRYRUN -eq '1' }
function Test-Installed([string]$root) { [IO.Directory]::Exists([IO.Path]::Combine($root, 'Data')) }
function Test-Inside([string]$path, [string]$root) { try { [IO.Path]::GetFullPath($path).StartsWith([IO.Path]::GetFullPath($root).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) } catch { $false } }
function Test-FontAvailable { $true }
function Get-ShortcutLocations {
    if ($env:SYHOST_SHORTCUT_DIR) { return @([IO.Path]::Combine($env:SYHOST_SHORTCUT_DIR, 'Desktop', 'SyHost.lnk'), [IO.Path]::Combine($env:SYHOST_SHORTCUT_DIR, 'Programs', 'SyHost.lnk')) }
    @([IO.Path]::Combine([Environment]::GetFolderPath('DesktopDirectory'), 'SyHost.lnk'), [IO.Path]::Combine([Environment]::GetFolderPath('Programs'), 'SyHost.lnk'))
}
function Get-LinkState([string]$lnk, [string]$exe) { 'Missing' }
function Write-Shortcut([string]$lnk, [string]$exe, [string]$desc) { }
function Find-PlayitDaemon {
    foreach ($p in [IO.Path]::Combine($PlayitToolDir, 'playitd.exe'), [IO.Path]::Combine($PlayitLegacyBin, 'playitd.exe')) { if ([IO.File]::Exists($p)) { return $p } }
    $null
}
function Set-WindowIcon { }
function Invoke-PortableStartup { $script:NextAfterSplash = if ($SetupMode) { 'firstrun' } else { 'home' }; if (-not $SetupMode) { Load-Servers } }
function Remove-RootAfterExit([string]$root) { }
