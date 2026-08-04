[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SpikeRoot = Split-Path -Parent $PSScriptRoot
$StatePath = Join-Path $SpikeRoot "logs\runtime_state.json"
$LifecyclePath = Join-Path $SpikeRoot "logs\lifecycle_last.json"
$ExpectedMain = "C:\AI\ComfyUI-ForgeFlux2\ComfyUI\main.py"

function Get-Listeners([int]$Port) {
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Stop-Verified([int]$ProcessId, [string]$RecordedCommandLine) {
    if ($ProcessId -le 0) { return }
    $candidate = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
    if ($null -eq $candidate) { return }
    if ([string]$candidate.CommandLine -cne $RecordedCommandLine -or [string]$candidate.CommandLine -notlike "*$ExpectedMain*") {
        throw "REFUSING_TO_STOP_UNVERIFIED_PROCESS:$ProcessId"
    }
    Stop-Process -Id $ProcessId
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ((Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        $again = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
        if ([string]$again.CommandLine -cne $RecordedCommandLine) { throw "PROCESS_ID_REUSED:$ProcessId" }
        Stop-Process -Id $ProcessId -Force
    }
}

if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
    if (@(Get-Listeners 8190).Count -ne 0) { throw "NO_STATE_BUT_8190_LISTENING" }
    if (@(Get-Listeners 8188).Count -ne 0) { throw "PORT_8188_MUST_BE_CLOSED" }
    [ordered]@{status="PASS";action="already_stopped";port_8190_closed=$true;port_8188_closed=$true} | ConvertTo-Json
    return
}

$state = Get-Content -Raw -Encoding UTF8 -LiteralPath $StatePath | ConvertFrom-Json
if ([string]$state.contract -ne "forge-birefnet-owned-runtime-v1" -or [string]$state.api_base -ne "http://127.0.0.1:8190") {
    throw "RUNTIME_STATE_INVALID"
}
$listenerPid = [int]$state.listener_pid
$launcherPid = [int]$state.launcher_pid
$recordedCommand = [string]$state.command_line
Stop-Verified -ProcessId $listenerPid -RecordedCommandLine $recordedCommand
if ($launcherPid -ne $listenerPid) {
    $launcher = Get-CimInstance Win32_Process -Filter "ProcessId = $launcherPid" -ErrorAction SilentlyContinue
    if ($null -ne $launcher) {
        if ([string]$launcher.CommandLine -notlike "*$ExpectedMain*") { throw "REFUSING_TO_STOP_UNVERIFIED_LAUNCHER:$launcherPid" }
        Stop-Process -Id $launcherPid -ErrorAction SilentlyContinue
    }
}
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while (@(Get-Listeners 8190).Count -ne 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
if (@(Get-Listeners 8190).Count -ne 0) { throw "PORT_8190_STILL_LISTENING" }
if (@(Get-Listeners 8188).Count -ne 0) { throw "PORT_8188_IS_LISTENING" }

$stoppedAt = [DateTime]::UtcNow
$archive = Join-Path (Split-Path -Parent $StatePath) ("runtime_state.stopped-{0}-{1}.json" -f $stoppedAt.ToString("yyyyMMddTHHmmssfffZ"), [Guid]::NewGuid().ToString("N"))
[IO.File]::Move($StatePath, $archive)
$lifecycle = [ordered]@{
    contract = "forge-birefnet-runtime-lifecycle-v1"
    status = "PASS"
    action = "stopped"
    launcher_pid = $launcherPid
    listener_pid = $listenerPid
    port_8190_closed = $true
    port_8188_closed = $true
    archived_state = $archive
    stopped_at_utc = $stoppedAt.ToString("o")
}
$temporary = "$LifecyclePath.$([Guid]::NewGuid().ToString('N')).partial"
[IO.File]::WriteAllText($temporary, (($lifecycle | ConvertTo-Json -Depth 10) + "`n"), [Text.UTF8Encoding]::new($false))
if (Test-Path -LiteralPath $LifecyclePath) {
    $old = "$LifecyclePath.$([Guid]::NewGuid().ToString('N')).previous"
    [IO.File]::Move($LifecyclePath, $old)
}
[IO.File]::Move($temporary, $LifecyclePath)
$lifecycle | ConvertTo-Json -Depth 10
