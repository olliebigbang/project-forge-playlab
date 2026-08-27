[CmdletBinding()]
param(
    [string]$Model = "claude-sonnet-5",
    [ValidateSet("MOCK", "LOCAL_COMFYUI", "FAL_FIREARM")]
    [string]$VisualProvider = "FAL_FIREARM",
    [string]$EnvFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$Python = (Get-Command python -ErrorAction Stop).Source
$HadApiKey = Test-Path Env:ANTHROPIC_API_KEY
$HadFalKey = Test-Path Env:FAL_KEY
$HadModel = Test-Path Env:FORGE_SEMANTIC_MODEL
$SavedApiKey = $env:ANTHROPIC_API_KEY
$SavedFalKey = $env:FAL_KEY
$SavedModel = $env:FORGE_SEMANTIC_MODEL
$SecureKey = $null
$KeyText = $null
$SecureFalKey = $null
$FalKeyText = $null
$ExitCode = 1

try {
    if (-not [string]::IsNullOrWhiteSpace($EnvFile)) {
        $ResolvedEnvFile = (Resolve-Path -LiteralPath $EnvFile -ErrorAction Stop).Path
        foreach ($Line in Get-Content -LiteralPath $ResolvedEnvFile) {
            if ($Line -notmatch '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { continue }
            $Name = $Matches[1]
            if ($Name -notin @("ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY")) { continue }
            $Value = $Matches[2].Trim()
            if ($Value.Length -ge 2 -and (
                ($Value.StartsWith('"') -and $Value.EndsWith('"')) -or
                ($Value.StartsWith("'") -and $Value.EndsWith("'"))
            )) {
                $Value = $Value.Substring(1, $Value.Length - 2)
            }
            if ([string]::IsNullOrWhiteSpace($Value)) { continue }
            if ($Name -eq "ANTHROPIC_API_KEY" -and [string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
                $env:ANTHROPIC_API_KEY = $Value
            }
            if ($Name -in @("FAL_KEY", "FAL_API_KEY") -and [string]::IsNullOrWhiteSpace($env:FAL_KEY)) {
                $env:FAL_KEY = $Value
            }
            $Value = $null
        }
    }
    if ([string]::IsNullOrWhiteSpace($Model)) {
        throw "FIREARM_AI_MODEL_ID_REQUIRED"
    }
    $env:FORGE_SEMANTIC_MODEL = $Model.Trim()
    if ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
        Write-Host "Developer setup only: enter the semantic AI key once. Players are never asked for combat mechanics."
        $SecureKey = Read-Host "SECURE INPUT ONLY: paste ANTHROPIC_API_KEY" -AsSecureString
        if ($SecureKey.Length -eq 0) { throw "ANTHROPIC_API_KEY_EMPTY" }
        $Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
        try { $KeyText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr) }
        $env:ANTHROPIC_API_KEY = $KeyText
    }
    if ($VisualProvider -eq "FAL_FIREARM" -and [string]::IsNullOrWhiteSpace($env:FAL_KEY)) {
        Write-Host "Developer setup only: FAL draws the finished firearm sprite. The key stays in this process only."
        $SecureFalKey = Read-Host "SECURE INPUT ONLY: paste FAL_KEY" -AsSecureString
        if ($SecureFalKey.Length -eq 0) { throw "FAL_KEY_EMPTY" }
        $FalBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureFalKey)
        try { $FalKeyText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($FalBstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($FalBstr) }
        $env:FAL_KEY = $FalKeyText
    }

    Write-Host "Starting Forge with dynamic firearm and general-object AI enabled."
    Write-Host "The AI fills strict identity and affordance cards; Godot validates and compiles all mechanics locally."
    if ($VisualProvider -eq "FAL_FIREARM") {
        Write-Host "FAL renders firearms or general objects as transparent identity art and converts them to bounded-palette pixel art; this mode uses paid API calls."
    }
    $Arguments = @(
        "--path", $PlaylabRoot,
        "res://scenes/open_identity_spike.tscn",
        "--",
        "--firearm-ai=anthropic",
        "--firearm-ai-python=$Python",
        "--object-ai=anthropic",
        "--object-ai-python=$Python",
        "--fal-python=$Python",
        "--visual-provider=$VisualProvider"
    )
    $NativeArguments = foreach ($Argument in $Arguments) {
        if ($Argument -match '[\s"]') {
            '"' + $Argument.Replace('"', '\"') + '"'
        }
        else {
            $Argument
        }
    }
    # This is the visible interactive game process. Waiting here keeps both
    # developer credentials alive for child bridges, then clears them on exit.
    $GodotProcess = Start-Process -FilePath $Godot -ArgumentList $NativeArguments -PassThru
    $GodotProcess.WaitForExit()
    $ExitCode = $GodotProcess.ExitCode
}
finally {
    if ($HadApiKey) { $env:ANTHROPIC_API_KEY = $SavedApiKey }
    else { Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue }
    if ($HadFalKey) { $env:FAL_KEY = $SavedFalKey }
    else { Remove-Item Env:\FAL_KEY -ErrorAction SilentlyContinue }
    if ($HadModel) { $env:FORGE_SEMANTIC_MODEL = $SavedModel }
    else { Remove-Item Env:\FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue }
    $KeyText = $null
    $FalKeyText = $null
    $SavedApiKey = $null
    $SavedFalKey = $null
    $SavedModel = $null
}

exit $ExitCode
