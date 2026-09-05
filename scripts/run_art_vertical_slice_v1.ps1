[CmdletBinding()]
param(
    [switch]$Replay,
    [switch]$Probe,
    [switch]$Smoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (([int]$Replay.IsPresent + [int]$Probe.IsPresent + [int]$Smoke.IsPresent) -gt 1) { throw "Choose only one of Replay, Probe or Smoke." }
$ArtSampleRoot = Split-Path -Parent $PSScriptRoot
$ArtSampleGodot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$ArtSampleArguments = @("--path", ('"' + $ArtSampleRoot + '"'), "res://scenes/art_vertical_slice_v1.tscn")
if ($Probe) { $ArtSampleArguments = @("--headless") + $ArtSampleArguments + @("--", "--probe") }
elseif ($Replay) { $ArtSampleArguments += @("--", "--replay") }
elseif ($Smoke) { $ArtSampleArguments += @("--", "--smoke") }

# This launcher intentionally never reads .env. The scene only reads accepted
# local caches and existing offline blueprints; it never writes the armory.
Write-Host "Church art sample: OFFLINE. No generation charges. Existing weapon library is read-only."
if ($Replay) { Write-Host "Automated inputs with real Godot rendering; this is not a desktop manual playtest." }
if ($Smoke) { Write-Host "Normal-scene first-frame diagnostic: no bot inputs; this does not verify Windows capture or manual input." }
$ArtSampleLogRoot = Join-Path $ArtSampleRoot (".tools/art-vertical-slice-v1/launch-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $ArtSampleLogRoot -Force | Out-Null
$ArtSampleProcessOptions = @{
    FilePath = $ArtSampleGodot
    ArgumentList = $ArtSampleArguments
    WorkingDirectory = $ArtSampleRoot
    PassThru = $true
    RedirectStandardOutput = Join-Path $ArtSampleLogRoot "stdout.log"
    RedirectStandardError = Join-Path $ArtSampleLogRoot "stderr.log"
}
if ($Probe) { $ArtSampleProcessOptions.WindowStyle = "Hidden" }
Write-Host "Launch logs: $ArtSampleLogRoot"
$ArtSampleProcess = Start-Process @ArtSampleProcessOptions
$ArtSampleTimedOut = $false
if ($Probe -or $Replay -or $Smoke) {
    $ArtSampleTimeoutSeconds = if ($Replay) { 180 } else { 45 }
    $ArtSampleTimer = [Diagnostics.Stopwatch]::StartNew()
    while (-not $ArtSampleProcess.WaitForExit(1000)) {
        if ($ArtSampleTimer.Elapsed.TotalSeconds -gt $ArtSampleTimeoutSeconds) {
            # Only this exact diagnostic child, never other open game windows.
            $ArtSampleProcess.Kill()
            $ArtSampleTimedOut = $true
            break
        }
    }
}
$ArtSampleProcess.WaitForExit()
Get-Content -LiteralPath (Join-Path $ArtSampleLogRoot "stdout.log")
Get-Content -LiteralPath (Join-Path $ArtSampleLogRoot "stderr.log")
if ($ArtSampleTimedOut) {
    Write-Error "Art sample diagnostic timed out; inspect the launch logs."
    exit 124
}
exit $ArtSampleProcess.ExitCode
