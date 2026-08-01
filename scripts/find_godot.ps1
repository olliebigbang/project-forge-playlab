$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

$candidates = New-Object System.Collections.Generic.List[string]
$candidates.Add((Join-Path $repoRoot ".tools\Godot_v4.7.1-stable_win64_console.exe"))
$candidates.Add((Join-Path $repoRoot ".tools\Godot_v4.7.1-stable_win64.exe"))

foreach ($commandName in @("godot4", "godot")) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $candidates.Add($command.Source)
    }
}

$candidates.Add((Join-Path $env:LOCALAPPDATA "Temp\godot4.exe"))

foreach ($candidate in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
        $version = & $candidate --version
        if ([string]::IsNullOrWhiteSpace($version)) {
            $version = (Get-Item -LiteralPath $candidate).VersionInfo.ProductVersion
        }
        if ($version -match "^4\.7\.1") {
            Write-Output $candidate
            exit 0
        }
    }
}

throw "Godot 4.7.1 was not found. Checked repository .tools, PATH, and local discovered candidates."
