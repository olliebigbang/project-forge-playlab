[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$LiveRoot = Split-Path -Parent $PSScriptRoot
$RuntimeRoot = Join-Path $LiveRoot "runtime"
$StatePath = Join-Path $RuntimeRoot "live_comfy_state.json"

function Get-Listeners([int]$Port) {
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Stop-VerifiedProcess([int]$ProcessId, [string]$CreationUtc, [string]$ExpectedFragment) {
    if ($ProcessId -le 0) { return }
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
    if ($null -eq $cim) { return }
    $actualCreation = ([DateTime]$cim.CreationDate).ToUniversalTime()
    $recordedCreation = [DateTime]::Parse($CreationUtc).ToUniversalTime()
    if ([Math]::Abs(($actualCreation - $recordedCreation).TotalSeconds) -gt 1.0) {
        throw "LIVE_COMFY_PROCESS_CREATION_MISMATCH:$ProcessId"
    }
    if ([string]$cim.CommandLine -notlike "*$ExpectedFragment*") {
        throw "LIVE_COMFY_PROCESS_COMMAND_MISMATCH:$ProcessId"
    }
    Stop-Process -Id $ProcessId -ErrorAction Stop
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ((Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        $fresh = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
        if ([string]$fresh.CommandLine -notlike "*$ExpectedFragment*") { throw "LIVE_COMFY_PROCESS_CHANGED:$ProcessId" }
        Stop-Process -Id $ProcessId -Force
    }
}

if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
    if (@(Get-Listeners 8190).Count -ne 0) { throw "UNOWNED_8190_LISTENER_REFUSED" }
    if (@(Get-Listeners 8188).Count -ne 0) { throw "PORT_8188_MUST_BE_CLOSED" }
    [ordered]@{ status = "PASS"; action = "already_stopped"; port_8190_closed = $true; port_8188_closed = $true } | ConvertTo-Json
    return
}

$state = [IO.File]::ReadAllText($StatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
if ([string]$state.contract -ne "forge-live-e2e-owned-comfy-v1" -or [string]$state.api_base -ne "http://127.0.0.1:8190") {
    throw "LIVE_COMFY_STATE_INVALID"
}
$expectedFragment = [string]$state.temp_directory
Stop-VerifiedProcess -ProcessId ([int]$state.listener_pid) -CreationUtc ([string]$state.listener_creation_utc) -ExpectedFragment $expectedFragment
if ([int]$state.launcher_pid -ne [int]$state.listener_pid) {
    Stop-VerifiedProcess -ProcessId ([int]$state.launcher_pid) -CreationUtc ([string]$state.launcher_creation_utc) -ExpectedFragment ([string]$state.main_py)
}
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while (@(Get-Listeners 8190).Count -ne 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
if (@(Get-Listeners 8190).Count -ne 0) { throw "PORT_8190_REMAINS_ACTIVE" }
if (@(Get-Listeners 8188).Count -ne 0) { throw "PORT_8188_MUST_BE_CLOSED" }
$archiveRoot = Join-Path $RuntimeRoot "stopped"
New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
$archive = Join-Path $archiveRoot ("live_comfy_state.{0}.{1}.json" -f [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ"), [Guid]::NewGuid().ToString("N"))
[IO.File]::Move($StatePath, $archive)
[ordered]@{
    status = "PASS"
    action = "stopped"
    session_id = [string]$state.session_id
    port_8190_closed = $true
    port_8188_closed = $true
    archived_state = $archive
} | ConvertTo-Json -Depth 8
