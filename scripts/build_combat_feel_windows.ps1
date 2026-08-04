$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$OutputDirectory = Join-Path $PlaylabRoot "build\windows"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$Executable = Join-Path $OutputDirectory "ForgeCombatFeelSlice0.exe"
$Pack = Join-Path $OutputDirectory "ForgeCombatFeelSlice0.pck"
$TemplateCandidates = @(
    (Join-Path $env:APPDATA "Godot\export_templates\4.7.1.stable\windows_release_x86_64.exe"),
    (Join-Path (Split-Path -Parent $Godot) "editor_data\export_templates\4.7.1.stable\windows_release_x86_64.exe")
)
$HasWindowsTemplate = $false
foreach ($Template in $TemplateCandidates) {
    if (Test-Path -LiteralPath $Template) { $HasWindowsTemplate = $true; break }
}

if ($HasWindowsTemplate) {
    & $Godot --headless --path $PlaylabRoot --export-release "Windows Desktop"
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $Executable)) {
        Write-Output "COMBAT_FEEL_WINDOWS_BUILD=PASS kind=RELEASE_EXPORT path=$Executable"
        exit 0
    }
}

if (-not $HasWindowsTemplate -or -not (Test-Path -LiteralPath $Executable)) {
    Write-Warning "Windows export templates are unavailable. Building an offline Playlab runtime bundle from the existing local Godot 4.7.1 executable and a platform-neutral PCK."
    & $Godot --headless --path $PlaylabRoot --export-pack "Windows Desktop" $Pack
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Pack)) { throw "PCK fallback export failed." }
    Copy-Item -LiteralPath $Godot -Destination $Executable -Force
    if (-not (Test-Path -LiteralPath $Executable)) { throw "Local Godot runtime copy failed." }
    Write-Output "COMBAT_FEEL_WINDOWS_BUILD=PASS kind=LOCAL_GODOT_RUNTIME_BUNDLE path=$Executable pack=$Pack"
    exit 0
}

throw "Windows build failed."
