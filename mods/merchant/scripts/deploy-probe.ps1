[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$GameRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$binaryRoot = Join-Path $GameRoot 'RSDragonwilds/Binaries/Win64'
if (-not (Test-Path -LiteralPath (Join-Path $binaryRoot 'RSDragonwilds-Win64-Shipping.exe') -PathType Leaf)) {
    throw 'The supplied directory is not a Dragonwilds Win64 installation.'
}
if (-not (Test-Path -LiteralPath (Join-Path $binaryRoot 'ue4ss/UE4SS.dll') -PathType Leaf)) {
    throw 'Install a compatible UE4SS build first.'
}
$modRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $modRoot 'tools/DragonwildsMerchantProbe'
$destination = Join-Path $binaryRoot 'ue4ss/Mods/DragonwildsMerchantProbe'
New-Item -ItemType Directory -Path (Join-Path $destination 'Scripts') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $source 'enabled.txt') -Destination (Join-Path $destination 'enabled.txt') -Force
Copy-Item -LiteralPath (Join-Path $source 'Scripts/main.lua') -Destination (Join-Path $destination 'Scripts/main.lua') -Force
$commandFile = (Join-Path $modRoot 'local/probe-command.lua').Replace('\', '/').Replace("'", "\'")
$config = "return { command_file = '$commandFile' }`n"
[System.IO.File]::WriteAllText((Join-Path $destination 'Scripts/probe_config.lua'), $config, [System.Text.UTF8Encoding]::new($false))
Write-Output "Installed read-only development probe: $destination"
Write-Output 'Start the game. F8 refreshes the dump; F9 runs local/probe-command.lua on the game thread.'
