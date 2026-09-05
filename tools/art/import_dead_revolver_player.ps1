[CmdletBinding()]
param([string]$Archive = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads/PixelPrototypePlayer.zip'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$PlayerRepo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$PlayerDestination = [IO.Path]::GetFullPath((Join-Path $PlayerRepo 'assets/dead_revolver_player_v1'))
$PlayerAnimations = @('Idle','Walk','Run','Roll','Combat/GunAim','Combat/GunFire','Combat/GunFire2H','Combat/GunWalk','Combat/GunRun','Combat/SwordIdle','Combat/SwordWalk','Combat/SwordSlash01','Combat/StandingSlash','Combat/ThrowOverarm')
$PlayerZip = [IO.Compression.ZipFile]::OpenRead($Archive)
$PlayerCopied = 0
try {
    foreach ($PlayerEntry in $PlayerZip.Entries) {
        if (-not $PlayerEntry.FullName.StartsWith('Pixel Prototype Player/') -or $PlayerEntry.Name -eq '') { continue }
        $PlayerRelative = $PlayerEntry.FullName.Substring('Pixel Prototype Player/'.Length)
        $PlayerSelected = $PlayerRelative -eq 'Readme.txt' -or $PlayerRelative -match '^Aseprite/(Player|PlayerCombat|Weapons)\.aseprite$'
        foreach ($PlayerAnimation in $PlayerAnimations) {
            if ($PlayerRelative.StartsWith("SpritesSeparated/$PlayerAnimation/") -or $PlayerRelative.StartsWith("Sprites/$PlayerAnimation/")) { $PlayerSelected = $true }
        }
        if (-not $PlayerSelected) { continue }
        $PlayerTarget = [IO.Path]::GetFullPath((Join-Path $PlayerDestination $PlayerRelative))
        if (-not $PlayerTarget.StartsWith($PlayerDestination + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive path outside destination.' }
        if (Test-Path -LiteralPath $PlayerTarget) { throw "Refusing to overwrite existing file: $PlayerTarget" }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($PlayerTarget)) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($PlayerEntry, $PlayerTarget, $false)
        $PlayerCopied++
    }
} finally { $PlayerZip.Dispose() }
Write-Output "Copied $PlayerCopied original files without pixel edits. Did not execute any bundled scripts."
Get-FileHash -LiteralPath $Archive -Algorithm SHA256 | Select-Object Hash,Path | ConvertTo-Json -Compress
