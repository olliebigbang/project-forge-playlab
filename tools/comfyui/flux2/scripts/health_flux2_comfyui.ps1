[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 30)]
    [int]$RequestTimeoutSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ExpectedApiBase = "http://127.0.0.1:8190"
$ExpectedRuntimeRoot = "C:\AI\ComfyUI-ForgeFlux2"
$ExpectedComfyCommit = "b1693ecba9f5b65f8c80ab36b195ab963ec92413"
$Flux2Root = Split-Path -Parent $PSScriptRoot
$ComfyToolsRoot = Split-Path -Parent $Flux2Root
$ProfilePath = Join-Path $ComfyToolsRoot "config\profiles\flux2_klein_4b.json"
$LogRoot = Join-Path $Flux2Root "logs"
$StatePath = Join-Path $LogRoot "runtime_state.json"
$PreflightPath = Join-Path $LogRoot "preflight_last.json"
$ExpectedPython = [System.IO.Path]::GetFullPath((Join-Path $ExpectedRuntimeRoot ".venv\Scripts\python.exe")).TrimEnd('\')
$ExpectedMain = [System.IO.Path]::GetFullPath((Join-Path $ExpectedRuntimeRoot "ComfyUI\main.py")).TrimEnd('\')

function ConvertTo-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Get-PortListeners {
    param([Parameter(Mandatory = $true)][int]$Port)
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Test-ArgumentPair {
    param(
        [Parameter(Mandatory = $true)][object[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )
    for ($index = 0; $index -lt ($Arguments.Count - 1); $index++) {
        if ([string]$Arguments[$index] -eq $Name -and [string]$Arguments[$index + 1] -eq $Value) {
            return $true
        }
    }
    return $false
}

function Assert-StateAndProcess {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$CimProcess
    )
    if ([string]$State.contract -ne "forge-flux2-owned-runtime-v1" -or
        [string]$State.status -ne "running") {
        throw "RUNTIME_STATE_NOT_RUNNING"
    }
    if ([string]$State.api_base -ne $ExpectedApiBase -or [int]$State.port -ne 8190 -or
        [string]$State.listen_address -ne "127.0.0.1") {
        throw "RUNTIME_STATE_BINDING_INVALID"
    }
    if ((ConvertTo-NormalizedPath ([string]$State.runtime_root)) -ine (ConvertTo-NormalizedPath $ExpectedRuntimeRoot) -or
        (ConvertTo-NormalizedPath ([string]$State.python_executable)) -ine $ExpectedPython -or
        (ConvertTo-NormalizedPath ([string]$State.main_py)) -ine $ExpectedMain -or
        (ConvertTo-NormalizedPath ([string]$State.executable_path)) -ine $ExpectedPython -or
        [string]$State.comfyui_commit -ne $ExpectedComfyCommit) {
        throw "RUNTIME_STATE_IDENTITY_INVALID"
    }
    if ([string]::IsNullOrWhiteSpace([string]$State.ownership_nonce) -or
        [string]::IsNullOrWhiteSpace([string]$State.process_creation_utc)) {
        throw "RUNTIME_STATE_OWNERSHIP_INCOMPLETE"
    }
    if ($null -eq $CimProcess) {
        throw "RECORDED_RUNTIME_PID_NOT_RUNNING"
    }
    if ([int]$CimProcess.ProcessId -ne [int]$State.pid -or
        (ConvertTo-NormalizedPath ([string]$CimProcess.ExecutablePath)) -ine $ExpectedPython -or
        [string]$CimProcess.CommandLine -cne [string]$State.command_line) {
        throw "RECORDED_PID_PROCESS_IDENTITY_MISMATCH"
    }
    $recordedCreation = [DateTime]::Parse(
        [string]$State.process_creation_utc,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind
    ).ToUniversalTime()
    $actualCreation = ([DateTime]$CimProcess.CreationDate).ToUniversalTime()
    if ([Math]::Abs(($actualCreation - $recordedCreation).TotalSeconds) -gt 1.0) {
        throw "RECORDED_PID_CREATION_TIME_MISMATCH"
    }
}

function Assert-ListenerProcess {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$ListenerProcess
    )
    if ($null -eq $ListenerProcess -or [int]$ListenerProcess.ProcessId -ne [int]$State.listener_pid -or
        [int]$ListenerProcess.ParentProcessId -ne [int]$State.pid -or
        [string]$ListenerProcess.CommandLine -cne [string]$State.listener_command_line -or
        (ConvertTo-NormalizedPath ([string]$ListenerProcess.ExecutablePath)) -ine
            (ConvertTo-NormalizedPath ([string]$State.listener_executable_path)) -or
        [System.IO.Path]::GetFileName([string]$ListenerProcess.ExecutablePath) -ine "python.exe") {
        throw "LISTENER_PROCESS_IDENTITY_MISMATCH"
    }
    $commandLine = [string]$ListenerProcess.CommandLine
    if ($commandLine.IndexOf($ExpectedMain, [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $commandLine.IndexOf("--listen 127.0.0.1", [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $commandLine.IndexOf("--port 8190", [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $commandLine.IndexOf("--disable-all-custom-nodes", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "LISTENER_PROCESS_COMMAND_LINE_MISMATCH"
    }
    $recordedCreation = [DateTime]::Parse([string]$State.listener_process_creation_utc).ToUniversalTime()
    $actualCreation = ([DateTime]$ListenerProcess.CreationDate).ToUniversalTime()
    if ([Math]::Abs(($actualCreation - $recordedCreation).TotalSeconds) -gt 1.0) {
        throw "LISTENER_PROCESS_CREATION_TIME_MISMATCH"
    }
}

try {
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        throw "FLUX2_PROFILE_MISSING"
    }
    $profile = [System.IO.File]::ReadAllText($ProfilePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$profile.profile_id -ne "flux2_klein_4b" -or
        [string]$profile.api_base -ne $ExpectedApiBase -or
        (ConvertTo-NormalizedPath ([string]$profile.runtime_root)) -ine (ConvertTo-NormalizedPath $ExpectedRuntimeRoot)) {
        throw "FLUX2_PROFILE_BINDING_INVALID"
    }
    $listeners8188 = @(Get-PortListeners 8188)
    if ($listeners8188.Count -ne 0) {
        throw "PORT_8188_MUST_NOT_BE_LISTENING"
    }
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        throw "OWNED_RUNTIME_STATE_MISSING"
    }
    try {
        $state = [System.IO.File]::ReadAllText($StatePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        throw "OWNED_RUNTIME_STATE_INVALID_JSON"
    }
    $recordedProcessId = [int]$state.pid
    $cimProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $recordedProcessId" -ErrorAction SilentlyContinue
    Assert-StateAndProcess -State $state -CimProcess $cimProcess
    $listenerProcessId = [int]$state.listener_pid
    $listenerProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $listenerProcessId" -ErrorAction SilentlyContinue
    Assert-ListenerProcess -State $state -ListenerProcess $listenerProcess

    if (-not (Test-Path -LiteralPath $PreflightPath -PathType Leaf)) {
        throw "RUNTIME_PREFLIGHT_EVIDENCE_MISSING"
    }
    $preflight = [System.IO.File]::ReadAllText($PreflightPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$preflight.contract -ne "forge-flux2-runtime-preflight-v1" -or
        [string]$preflight.status -ne "PASS" -or [string]$preflight.api_base -ne $ExpectedApiBase -or
        [string]$preflight.comfyui_commit -ne $ExpectedComfyCommit -or
        [string]$preflight.mode -ne [string]$state.mode -or @($preflight.models).Count -ne 3) {
        throw "RUNTIME_PREFLIGHT_EVIDENCE_INVALID"
    }
    $preflightTime = [DateTime]::Parse([string]$preflight.checked_at_utc).ToUniversalTime()
    $startedTime = [DateTime]::Parse([string]$state.started_at_utc).ToUniversalTime()
    if ($preflightTime -gt $startedTime -or ($startedTime - $preflightTime).TotalMinutes -gt 30) {
        throw "RUNTIME_PREFLIGHT_EVIDENCE_NOT_FOR_THIS_START"
    }

    $listeners8190 = @(Get-PortListeners 8190)
    $ownedListener = @($listeners8190 | Where-Object {
        $_.LocalAddress -eq "127.0.0.1" -and [int]$_.OwningProcess -eq $listenerProcessId
    })
    $foreignListener = @($listeners8190 | Where-Object {
        $_.LocalAddress -ne "127.0.0.1" -or [int]$_.OwningProcess -ne $listenerProcessId
    })
    if ($ownedListener.Count -ne 1 -or $foreignListener.Count -ne 0) {
        throw "PORT_8190_NOT_EXACTLY_ONE_OWNED_LOOPBACK_LISTENER"
    }

    $stats = Invoke-RestMethod -Uri "$ExpectedApiBase/system_stats" -Method Get -TimeoutSec $RequestTimeoutSeconds
    $serverArguments = @($stats.system.argv)
    if (-not (Test-ArgumentPair -Arguments $serverArguments -Name "--listen" -Value "127.0.0.1") -or
        -not (Test-ArgumentPair -Arguments $serverArguments -Name "--port" -Value "8190") -or
        $serverArguments -notcontains "--disable-all-custom-nodes" -or
        $serverArguments -notcontains "--disable-api-nodes") {
        throw "SYSTEM_STATS_ARGUMENT_ATTESTATION_FAILED"
    }
    if ([string]$state.mode -eq "low_memory") {
        foreach ($requiredFlag in @("--lowvram", "--cpu-vae", "--cache-none")) {
            if ($serverArguments -notcontains $requiredFlag) {
                throw "LOW_MEMORY_ARGUMENT_MISSING:$requiredFlag"
            }
        }
    }
    elseif ([string]$state.mode -eq "normal") {
        foreach ($forbiddenFlag in @("--lowvram", "--cpu-vae", "--cache-none")) {
            if ($serverArguments -contains $forbiddenFlag) {
                throw "NORMAL_MODE_HAS_LOW_MEMORY_ARGUMENT:$forbiddenFlag"
            }
        }
    }
    else {
        throw "RUNTIME_MODE_INVALID"
    }

    [ordered]@{
        status = "PASS"
        healthy = $true
        api_base = $ExpectedApiBase
        launcher_pid = $recordedProcessId
        listener_pid = $listenerProcessId
        mode = [string]$state.mode
        listener_address = "127.0.0.1"
        listener_port = 8190
        port_8188_closed = $true
        listener_owned_by_verified_child_pid = $true
        custom_nodes_disabled = $true
        api_nodes_disabled = $true
        comfyui_commit = [string]$state.comfyui_commit
        preflight_model_count = @($preflight.models).Count
        system_stats = $stats.system
        checked_at_utc = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json -Depth 12
}
catch {
    [ordered]@{
        status = "FAIL"
        healthy = $false
        api_base = $ExpectedApiBase
        failure_reason = $_.Exception.Message
        port_8190_listeners = @(
            Get-PortListeners 8190 | Select-Object LocalAddress, LocalPort, OwningProcess
        )
        port_8188_listeners = @(
            Get-PortListeners 8188 | Select-Object LocalAddress, LocalPort, OwningProcess
        )
        checked_at_utc = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json -Depth 8
    exit 2
}
