[CmdletBinding()]
param(
    [string]$EnvFile = "",
    [ValidateSet("Church", "Sunny")][string]$Campaign = "Church",
    [string]$Model = "claude-sonnet-5",
    [switch]$Smoke,
    [switch]$Offline,
    [switch]$LiveReview
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ($Smoke -and $LiveReview) { throw "Choose Smoke or LiveReview, not both." }
if ($Offline -and $LiveReview) { throw "Offline cannot be combined with LiveReview." }
$ChurchRoot = Split-Path -Parent $PSScriptRoot
$ChurchGodot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$ChurchPythonCommand = Get-Command python -ErrorAction SilentlyContinue
$ChurchPython = if ($ChurchPythonCommand) { $ChurchPythonCommand.Source } else { "" }
$ChurchLogRoot = Join-Path $ChurchRoot (".tools/church-ai-forge/launch-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $ChurchLogRoot -Force | Out-Null
$ChurchEnvNames = @("ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY", "FORGE_SEMANTIC_MODEL", "FORGE_WEAPON_LIBRARY_ROOT")
$ChurchPrevious = @{}
foreach ($Name in $ChurchEnvNames) { $ChurchPrevious[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process") }
$ChurchExit = 1
try {
    if ($Smoke -or $Offline) {
        # This diagnostic is unconditionally offline, even in a keyed parent.
        foreach ($Name in $ChurchEnvNames) { [Environment]::SetEnvironmentVariable($Name, $null, "Process") }
        if ($Smoke) { $env:FORGE_WEAPON_LIBRARY_ROOT = Join-Path $ChurchLogRoot "isolated-library" }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($EnvFile)) { $EnvFile = Join-Path $env:USERPROFILE ".env" }
        if (Test-Path -LiteralPath $EnvFile) {
            foreach ($Line in Get-Content -LiteralPath $EnvFile) {
                if ($Line -notmatch '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { continue }
                $Name = $Matches[1]
                if ($Name -notin @("ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY")) { continue }
                $Value = $Matches[2].Trim()
                if ($Value.Length -ge 2 -and (($Value.StartsWith('"') -and $Value.EndsWith('"')) -or ($Value.StartsWith("'") -and $Value.EndsWith("'")))) { $Value = $Value.Substring(1, $Value.Length - 2) }
                if ([string]::IsNullOrWhiteSpace($Value)) { continue }
                $Target = if ($Name -eq "FAL_API_KEY") { "FAL_KEY" } else { $Name }
                if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Target, "Process"))) { [Environment]::SetEnvironmentVariable($Target, $Value, "Process") }
                $Value = $null
            }
        }
        if ([string]::IsNullOrWhiteSpace($env:FAL_KEY) -and -not [string]::IsNullOrWhiteSpace($env:FAL_API_KEY)) { $env:FAL_KEY = $env:FAL_API_KEY }
        if ($LiveReview -and ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY) -or [string]::IsNullOrWhiteSpace($env:FAL_KEY))) { throw "LiveReview requires ANTHROPIC_API_KEY and FAL_KEY. No key values are logged." }
        if ([string]::IsNullOrWhiteSpace($Model)) { throw "Semantic model is required." }
        $env:FORGE_SEMANTIC_MODEL = $Model.Trim()
    }
    $ChurchArgs = @("--path", $ChurchRoot)
    if ($LiveReview) {
        # Explicit bounded developer test; isolated library, no user saves touched.
        $env:FORGE_WEAPON_LIBRARY_ROOT = Join-Path $ChurchLogRoot "isolated-library"
        $ChurchArgs += @("--script", "res://tests/church_forge_live_review.gd", "--", "--allow-live-ai-review")
        Write-Host "LIVE AI REVIEW: up to three new descriptions, max two visual requests each. Paid API calls. Automated inputs, not desktop manual play."
    }
    else {
        $ChurchScene = if ($Campaign -eq "Sunny") { "res://scenes/sunny_expedition.tscn" } elseif ($Smoke) { "res://scenes/church_forge.tscn" } else { "res://scenes/church_expedition.tscn" }
        $ChurchArgs += @($ChurchScene, "--")
        if ($Smoke) { $ChurchArgs += "--smoke" }
        Write-Host $(if ($Smoke) { "$Campaign Forge OFFLINE smoke: no .env and no API." } else { "$Campaign Forge: AI generation uses paid API calls only when Generate is pressed. Saving is explicit." })
    }
    if ($ChurchPython) { $ChurchArgs += "--fal-python=$ChurchPython" }
    $ChurchQuoted = foreach ($Argument in $ChurchArgs) { if ($Argument -match '[\s"]') { '"' + $Argument.Replace('"', '\"') + '"' } else { $Argument } }
    Write-Host "Launch logs: $ChurchLogRoot"
    $ChurchWindowStyle = if ($Smoke -or $LiveReview) { 'Hidden' } else { 'Normal' }
    $ChurchProcess = Start-Process -FilePath $ChurchGodot -ArgumentList $ChurchQuoted -WorkingDirectory $ChurchRoot -WindowStyle $ChurchWindowStyle -PassThru -RedirectStandardOutput (Join-Path $ChurchLogRoot "stdout.log") -RedirectStandardError (Join-Path $ChurchLogRoot "stderr.log")
    $ChurchProcessHandle = $ChurchProcess.Handle
    $ChurchProcess.WaitForExit()
    $ChurchExit = $ChurchProcess.ExitCode
}
finally {
    foreach ($Name in $ChurchEnvNames) { [Environment]::SetEnvironmentVariable($Name, $ChurchPrevious[$Name], "Process") }
    $Value = $null
    $ChurchPrevious.Clear()
}
exit $ChurchExit
