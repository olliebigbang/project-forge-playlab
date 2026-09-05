[CmdletBinding()]
param([string]$Archive = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads/PixelPrototypePlayer.zip'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$SwordRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SwordDestination = [IO.Path]::GetFullPath((Join-Path $SwordRoot 'assets/dead_revolver_player_v1'))
$SwordNames = @('SwordRun','SwordCombo01','SwordCombo02','SwordCombo03','SwordCombo04')
$SwordZip = [IO.Compression.ZipFile]::OpenRead($Archive)
$SwordCount = 0
try {
    foreach ($SwordName in $SwordNames) {
        $SwordPrefix = "Pixel Prototype Player/Sprites/Combat/$SwordName/"
        foreach ($SwordEntry in $SwordZip.Entries) {
            if (-not $SwordEntry.FullName.StartsWith($SwordPrefix) -or -not $SwordEntry.Name.EndsWith('.png')) { continue }
            $SwordRelative = $SwordEntry.FullName.Substring('Pixel Prototype Player/'.Length)
            $SwordTarget = [IO.Path]::GetFullPath((Join-Path $SwordDestination $SwordRelative))
            if (-not $SwordTarget.StartsWith($SwordDestination + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive target outside asset directory.' }
            $SwordStream = $SwordEntry.Open()
            $SwordHasher = [Security.Cryptography.SHA256]::Create()
            try { $SwordHash = [BitConverter]::ToString($SwordHasher.ComputeHash($SwordStream)).Replace('-','') }
            finally { $SwordStream.Dispose(); $SwordHasher.Dispose() }
            if (Test-Path -LiteralPath $SwordTarget) {
                if ((Get-FileHash -LiteralPath $SwordTarget -Algorithm SHA256).Hash -ne $SwordHash) { throw "Existing asset differs; refusing overwrite: $SwordTarget" }
            } else {
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($SwordTarget)) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($SwordEntry, $SwordTarget, $false)
            }
            if ((Get-FileHash -LiteralPath $SwordTarget -Algorithm SHA256).Hash -ne $SwordHash) { throw "Source hash mismatch: $SwordRelative" }
            $SwordCount++
        }
    }
} finally { $SwordZip.Dispose() }
if ($SwordCount -ne 32) { throw "Expected 32 original PNGs, found $SwordCount." }
Write-Output "Verified $SwordCount original full-body PNGs against user ZIP. No image edits or bundled script execution."
