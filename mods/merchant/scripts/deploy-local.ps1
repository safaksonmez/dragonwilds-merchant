[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$GameRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like '*Dragonwilds*' }).Count -gt 0) {
    throw 'Close Dragonwilds before updating the mod. This script never closes the game.'
}
$modRoot = Split-Path -Parent $PSScriptRoot
$binaryRoot = Join-Path ([System.IO.Path]::GetFullPath($GameRoot)) 'RSDragonwilds/Binaries/Win64'
if (-not (Test-Path -LiteralPath (Join-Path $binaryRoot 'RSDragonwilds-Win64-Shipping.exe') -PathType Leaf)) {
    throw 'Expected a Dragonwilds Win64 installation.'
}
$modsRoot = Join-Path $binaryRoot 'ue4ss/Mods'
if (-not (Test-Path -LiteralPath (Join-Path $modsRoot 'RuneSchema/dlls/main.dll') -PathType Leaf)) {
    throw 'Install RuneSchema 0.8.0.3 and compatible UE4SS first.'
}
if (Test-Path -LiteralPath (Join-Path $modsRoot 'DragonwildsMerchant')) {
    throw 'A legacy top-level DragonwildsMerchant copy conflicts with the companion. Back it up and remove that copy first.'
}
$source = [System.IO.Path]::GetFullPath((Join-Path $modRoot 'src/DragonwildsMerchant'))
$destination = Join-Path $modsRoot 'RuneSchema/mods/DragonwildsMerchant'
if (Test-Path -LiteralPath $destination) {
    $backup = Join-Path $modRoot ('local/backups/before-addon-update-' + (Get-Date -Format 'yyyyMMdd-HHmmss-ffff'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Copy-Item -LiteralPath $destination -Destination $backup -Recurse
    Write-Output "Previous add-on backed up: $backup"
}
$prefix = $source.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$files = @(Get-ChildItem -LiteralPath $source -Recurse -File)
foreach ($file in $files) {
    $relative = $file.FullName.Substring($prefix.Length)
    $target = Join-Path $destination $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {
        throw "Deployment readback failed: $relative"
    }
}
Write-Output "Deployed and hash-verified $($files.Count) source files: $destination"
Write-Output 'Existing Data journals and RuneSchema settings were preserved. Full restart required. Gameplay not tested by this script.'
