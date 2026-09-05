[CmdletBinding()]
param([string]$Archive = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads/PixelPrototypePlayer.zip'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ActionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ActionDestination = [IO.Path]::GetFullPath((Join-Path $ActionRoot 'assets/dead_revolver_player_v1'))
$ActionExcluded = '^(Ladder|Climb|Ledge|Monkey|Wall)'
$ActionZip = [IO.Compression.ZipFile]::OpenRead($Archive)
$ActionVerified = 0
$ActionAdded = 0
try {
    foreach ($ActionEntry in $ActionZip.Entries) {
        $ActionRelative = $ActionEntry.FullName -replace '^Pixel Prototype Player/', ''
        $ActionInclude = $ActionRelative -match '^Aseprite/(PlayerFishing|Effects)\.aseprite$'
        if ($ActionRelative -match '^Sprites/(?:(Combat|Fishing|FX|Weapons)/)?([^/]+)/[^/]+\.png$') {
            $ActionInclude = $Matches[2] -notmatch $ActionExcluded
        }
        if ($ActionRelative -match '^SpritesSeparated/Combat/Gun[^/]+/Weapon/[^/]+\.png$') { $ActionInclude = $true }
        # Gameplay attachment needs the untouched body layers and reference
        # weapon layer. Never bake the reference weapon into the new actor.
        if ($ActionRelative -match '^SpritesSeparated/(?:(Combat|Fishing)/)?([^/]+)/(Head|Torso|LeftArm|RightArm|LeftLeg|RightLeg|Weapon)/[^/]+\.png$') {
            $ActionInclude = $Matches[2] -notmatch $ActionExcluded
        }
        if (-not $ActionInclude) { continue }
        $ActionTarget = [IO.Path]::GetFullPath((Join-Path $ActionDestination $ActionRelative))
        if (-not $ActionTarget.StartsWith($ActionDestination + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive target outside asset directory.' }
        $ActionStream = $ActionEntry.Open()
        $ActionHasher = [Security.Cryptography.SHA256]::Create()
        try { $ActionHash = [BitConverter]::ToString($ActionHasher.ComputeHash($ActionStream)).Replace('-','') }
        finally { $ActionStream.Dispose(); $ActionHasher.Dispose() }
        if (Test-Path -LiteralPath $ActionTarget) {
            if ((Get-FileHash -LiteralPath $ActionTarget -Algorithm SHA256).Hash -ne $ActionHash) { throw "Existing asset differs; refusing overwrite: $ActionTarget" }
        } else {
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ActionTarget)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($ActionEntry, $ActionTarget, $false)
            $ActionAdded++
        }
        if ((Get-FileHash -LiteralPath $ActionTarget -Algorithm SHA256).Hash -ne $ActionHash) { throw "Source hash mismatch: $ActionRelative" }
        $ActionVerified++
    }
} finally { $ActionZip.Dispose() }
Write-Output "Verified $ActionVerified exact source files; added $ActionAdded. No modified images, traversal imports or bundled script execution."
