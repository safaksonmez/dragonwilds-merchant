[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $modRoot 'mod.json') -Raw | ConvertFrom-Json
if ($manifest.id -cne 'DragonwildsMerchant') {
    throw 'Unexpected mod identity. Review the packaging layout before renaming the mod.'
}
if ($manifest.version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw 'Version must be a safe semantic version such as 0.1.0-dev.1.'
}

$sourceRoot = Join-Path $modRoot 'src'
$sourceMod = Join-Path $sourceRoot $manifest.id
foreach ($required in @('assets/10-coin.json', 'npc/10-bramblemead-merchant.json', 'npc/20-bramblemead-stall.json',
    'vendors/10-coin-store.json', 'recipes/20-merchant-recipes.json', 'raw/20-merchant-row.json',
    'ue4ss/DragonwildsMerchant/Scripts/main.lua', 'ue4ss/DragonwildsMerchant/Data/README.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceMod $required) -PathType Leaf)) {
        throw "Required source file missing: $required"
    }
}

# RuneSchema LoadVendors requires Id AND Items even for an empty bootstrap
# store. A syntactically valid JSON file without Items disables the NPC.
$store = Get-Content -LiteralPath (Join-Path $sourceMod 'vendors/10-coin-store.json') -Raw | ConvertFrom-Json
$npc = Get-Content -LiteralPath (Join-Path $sourceMod 'npc/10-bramblemead-merchant.json') -Raw | ConvertFrom-Json
if ($store.Id -cne 'coin_store' -or $npc.VendorID -cne $store.Id -or
    -not ($store.PSObject.Properties.Name -contains 'Items') -or $store.Items -isnot [array] -or
    $store.RowName -cne 'DWM_CoinMerchant_bootstrap_v1') {
    throw 'Invalid bootstrap storefront. RuneSchema requires Items: [] and a separate provider-owned bootstrap row.'
}

# Inspect all of src because the ZIP is created from this directory.
$sourcePrefix = [System.IO.Path]::GetFullPath($sourceRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force)
$expected = @{}
foreach ($file in $files) {
    $relative = $file.FullName.Substring($sourcePrefix.Length).Replace('\', '/')
    if ($relative -cnotmatch '^DragonwildsMerchant/(assets|npc|vendors|recipes|raw)/[A-Za-z0-9_-]+\.json$' -and
        $relative -cnotmatch '^DragonwildsMerchant/ue4ss/DragonwildsMerchant/Scripts/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.lua$' -and
        $relative -cne 'DragonwildsMerchant/ue4ss/DragonwildsMerchant/Data/README.txt') {
        throw "Unexpected distributable file: $relative. Keep non-runtime files outside src."
    }
    if ($file.Extension -eq '.json') { $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json }
    $expected[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}
if (@(Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force | Where-Object {
    $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint
}).Count -gt 0) {
    throw 'Linked files/directories are not supported in package sources.'
}

$outputDir = Join-Path $modRoot 'dist'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$archivePath = Join-Path $outputDir ("{0}-{1}.zip" -f $manifest.id, $manifest.version)
if ((Test-Path -LiteralPath $archivePath) -and -not $Force) {
    throw "Package already exists: $archivePath. Use -Force to rebuild it."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$temporaryPath = Join-Path $outputDir (([guid]::NewGuid().ToString('N')) + '.tmp.zip')
try {
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $sourceRoot, $temporaryPath, [System.IO.Compression.CompressionLevel]::Optimal, $false
    )

    $archive = [System.IO.Compression.ZipFile]::OpenRead($temporaryPath)
    try {
        $seen = @{}
        foreach ($entry in $archive.Entries) {
            $entryPath = $entry.FullName.Replace('\', '/')
            if ($entryPath.EndsWith('/')) { continue }
            if (-not $expected.ContainsKey($entryPath) -or $seen.ContainsKey($entryPath)) {
                throw "Unexpected or duplicate ZIP entry: $entryPath"
            }
            $stream = $entry.Open()
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $digest = [System.BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '')
                if ($digest -ne $expected[$entryPath]) {
                    throw "ZIP content mismatch: $entryPath"
                }
            }
            finally {
                $sha.Dispose()
                $stream.Dispose()
            }
            $seen[$entryPath] = $true
        }
        if ($seen.Count -ne $expected.Count) { throw 'ZIP is missing runtime files.' }
    }
    finally { $archive.Dispose() }

    Move-Item -LiteralPath $temporaryPath -Destination $archivePath -Force:$Force
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumPath = $archivePath + '.sha256'
    $checksum = $hash + '  ' + [System.IO.Path]::GetFileName($archivePath) + "`n"
    [System.IO.File]::WriteAllText($checksumPath, $checksum, [System.Text.UTF8Encoding]::new($false))
    Write-Output "Created: $archivePath"
    Write-Output "Verified runtime files: $($expected.Count)"
    Write-Output "SHA256: $hash"
    Write-Output 'RuneSchema add-on with nested Lua companion. In-game regression and Vortex validation are still required.'
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}
