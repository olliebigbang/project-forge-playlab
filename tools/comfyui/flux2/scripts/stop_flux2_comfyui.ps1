[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(5, 120)]
    [int]$GracefulTimeoutSeconds = 30,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 60)]
    [int]$ForcedTimeoutSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ExpectedApiBase = "http://127.0.0.1:8190"
$ExpectedRuntimeRoot = "C:\AI\ComfyUI-ForgeFlux2"
$ExpectedComfyCommit = "b1693ecba9f5b65f8c80ab36b195ab963ec92413"
$Flux2Root = Split-Path -Parent $PSScriptRoot
$LogRoot = Join-Path $Flux2Root "logs"
$StatePath = Join-Path $LogRoot "runtime_state.json"
$LifecyclePath = Join-Path $LogRoot "lifecycle_last.json"
$ExpectedPython = [System.IO.Path]::GetFullPath((Join-Path $ExpectedRuntimeRoot ".venv\Scripts\python.exe")).TrimEnd('\')
$ExpectedMain = [System.IO.Path]::GetFullPath((Join-Path $ExpectedRuntimeRoot "ComfyUI\main.py")).TrimEnd('\')

function ConvertTo-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temporary = Join-Path $parent (".{0}.{1}.tmp" -f ([System.IO.Path]::GetFileName($Path)), [Guid]::NewGuid().ToString("N"))
    $backup = "$Path.replace-backup"
    try {
        [System.IO.File]::WriteAllText(
            $temporary,
            (($Value | ConvertTo-Json -Depth 20) + "`n"),
            [System.Text.UTF8Encoding]::new($false)
        )
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Replace($temporary, $Path, $backup, $true)
            if ([System.IO.File]::Exists($backup)) { [System.IO.File]::Delete($backup) }
        }
        else {
            [System.IO.File]::Move($temporary, $Path)
        }
    }
    finally {
        if ([System.IO.File]::Exists($temporary)) { [System.IO.File]::Delete($temporary) }
        if ([System.IO.File]::Exists($backup)) { [System.IO.File]::Delete($backup) }
    }
}

function Get-PortListeners {
    param([Parameter(Mandatory = $true)][int]$Port)
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Get-RuntimeProcesses {
    return @(
        Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $executable = [string]$_.ExecutablePath
            $commandLine = [string]$_.CommandLine
            ((-not [string]::IsNullOrWhiteSpace($executable)) -and
                ((ConvertTo-NormalizedPath $executable) -ieq $ExpectedPython)) -or
            ((-not [string]::IsNullOrWhiteSpace($commandLine)) -and
                $commandLine.IndexOf($ExpectedMain, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
        }
    )
}

function Publish-PartialLog {
    param(
        [Parameter(Mandatory = $true)][string]$PartialPath,
        [Parameter(Mandatory = $true)][string]$FinalPath
    )
    if (-not [System.IO.File]::Exists($PartialPath)) { return }
    if ([System.IO.File]::Exists($FinalPath)) {
        throw "REFUSING_TO_OVERWRITE_LOG:$FinalPath"
    }
    [System.IO.File]::Move($PartialPath, $FinalPath)
}

function Assert-StateContract {
    param([Parameter(Mandatory = $true)]$State)
    if ([string]$State.contract -ne "forge-flux2-owned-runtime-v1") {
        throw "RUNTIME_STATE_CONTRACT_INVALID"
    }
    if ([string]$State.status -notin @("starting", "running")) {
        throw "RUNTIME_STATE_STATUS_INVALID"
    }
    if ([string]$State.api_base -ne $ExpectedApiBase -or [int]$State.port -ne 8190 -or
        [string]$State.listen_address -ne "127.0.0.1") {
        throw "RUNTIME_STATE_BINDING_INVALID"
    }
    if ((ConvertTo-NormalizedPath ([string]$State.runtime_root)) -ine (ConvertTo-NormalizedPath $ExpectedRuntimeRoot) -or
        (ConvertTo-NormalizedPath ([string]$State.python_executable)) -ine $ExpectedPython -or
        (ConvertTo-NormalizedPath ([string]$State.main_py)) -ine $ExpectedMain -or
        (ConvertTo-NormalizedPath ([string]$State.executable_path)) -ine $ExpectedPython) {
        throw "RUNTIME_STATE_PATH_INVALID"
    }
    if ([string]$State.comfyui_commit -ne $ExpectedComfyCommit) {
        throw "RUNTIME_STATE_COMMIT_INVALID"
    }
    if ([string]::IsNullOrWhiteSpace([string]$State.ownership_nonce) -or
        [string]::IsNullOrWhiteSpace([string]$State.command_line) -or
        [string]::IsNullOrWhiteSpace([string]$State.process_creation_utc)) {
        throw "RUNTIME_STATE_OWNERSHIP_INCOMPLETE"
    }
    if ([string]$State.status -eq "running" -and
        ([int]$State.listener_pid -le 0 -or [int]$State.listener_parent_pid -ne [int]$State.pid -or
        [string]::IsNullOrWhiteSpace([string]$State.listener_command_line) -or
        [string]::IsNullOrWhiteSpace([string]$State.listener_process_creation_utc))) {
        throw "RUNTIME_STATE_LISTENER_OWNERSHIP_INCOMPLETE"
    }
}

function Assert-OwnedListenerProcess {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$CimProcess
    )
    if ($null -eq $CimProcess -or [int]$CimProcess.ProcessId -ne [int]$State.listener_pid -or
        [int]$CimProcess.ParentProcessId -ne [int]$State.pid -or
        [string]$CimProcess.CommandLine -cne [string]$State.listener_command_line -or
        (ConvertTo-NormalizedPath ([string]$CimProcess.ExecutablePath)) -ine
            (ConvertTo-NormalizedPath ([string]$State.listener_executable_path)) -or
        [System.IO.Path]::GetFileName([string]$CimProcess.ExecutablePath) -ine "python.exe") {
        throw "OWNED_LISTENER_PROCESS_IDENTITY_MISMATCH"
    }
    $commandLine = [string]$CimProcess.CommandLine
    if ($commandLine.IndexOf($ExpectedMain, [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $commandLine.IndexOf("--listen 127.0.0.1", [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $commandLine.IndexOf("--port 8190", [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $commandLine.IndexOf("--disable-all-custom-nodes", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "OWNED_LISTENER_PROCESS_COMMAND_LINE_MISMATCH"
    }
    $recordedCreation = [DateTime]::Parse([string]$State.listener_process_creation_utc).ToUniversalTime()
    $actualCreation = ([DateTime]$CimProcess.CreationDate).ToUniversalTime()
    if ([Math]::Abs(($actualCreation - $recordedCreation).TotalSeconds) -gt 1.0) {
        throw "OWNED_LISTENER_PROCESS_CREATION_TIME_MISMATCH"
    }
}

function Assert-OwnedProcess {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$CimProcess
    )
    if ([int]$CimProcess.ProcessId -ne [int]$State.pid) {
        throw "OWNED_PROCESS_PID_MISMATCH"
    }
    if ((ConvertTo-NormalizedPath ([string]$CimProcess.ExecutablePath)) -ine $ExpectedPython) {
        throw "OWNED_PROCESS_EXECUTABLE_MISMATCH"
    }
    $commandLine = [string]$CimProcess.CommandLine
    if ($commandLine -cne [string]$State.command_line -or
        $commandLine.IndexOf($ExpectedMain, [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $commandLine.IndexOf("--listen 127.0.0.1", [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $commandLine.IndexOf("--port 8190", [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -or
        $commandLine.IndexOf("--disable-all-custom-nodes", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "OWNED_PROCESS_COMMAND_LINE_MISMATCH"
    }
    $recordedCreation = [DateTime]::Parse(
        [string]$State.process_creation_utc,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind
    ).ToUniversalTime()
    $actualCreation = ([DateTime]$CimProcess.CreationDate).ToUniversalTime()
    if ([Math]::Abs(($actualCreation - $recordedCreation).TotalSeconds) -gt 1.0) {
        throw "OWNED_PROCESS_CREATION_TIME_MISMATCH"
    }
}

function Get-GpuMemoryUsedMb {
    $nvidiaSmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($null -eq $nvidiaSmi) { return $null }
    $value = ((& $nvidiaSmi.Source --query-gpu=memory.used --format=csv,noheader,nounits 2>$null) | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or $null -eq $value) { return $null }
    $parsed = 0
    if ([int]::TryParse(([string]$value).Trim(), [ref]$parsed)) { return $parsed }
    return $null
}

if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
    $listeners8190 = @(Get-PortListeners 8190)
    $runtimeProcesses = @(Get-RuntimeProcesses)
    $listeners8188 = @(Get-PortListeners 8188)
    if ($listeners8190.Count -ne 0) {
        throw "NO_OWNERSHIP_STATE_BUT_8190_IS_LISTENING:refusing to stop an unowned listener"
    }
    if ($runtimeProcesses.Count -ne 0) {
        throw "NO_OWNERSHIP_STATE_BUT_RUNTIME_PROCESS_EXISTS:$($runtimeProcesses[0].ProcessId)"
    }
    if ($listeners8188.Count -ne 0) {
        throw "PORT_8188_MUST_NOT_BE_LISTENING:stop script will not kill an unrelated service"
    }
    Write-JsonAtomic -Path $LifecyclePath -Value ([ordered]@{
        contract = "forge-flux2-lifecycle-v1"
        action = "already_stopped"
        status = "PASS"
        api_base = $ExpectedApiBase
        port_8190_closed = $true
        port_8188_closed = $true
        isolated_runtime_process_count = 0
        recorded_at_utc = [DateTime]::UtcNow.ToString("o")
    })
    [ordered]@{
        status = "PASS"
        action = "already_stopped"
        port_8190_closed = $true
        port_8188_closed = $true
    } | ConvertTo-Json -Depth 5
    return
}

try {
    $state = [System.IO.File]::ReadAllText($StatePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}
catch {
    throw "RUNTIME_STATE_INVALID_JSON:refusing destructive stop"
}
Assert-StateContract -State $state
$recordedProcessId = [int]$state.pid
$cimProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $recordedProcessId" -ErrorAction SilentlyContinue
$processWasRunning = $null -ne $cimProcess
$listenerProcessId = if ([string]$state.status -eq "running") { [int]$state.listener_pid } else { 0 }
$listenerCimProcess = if ($listenerProcessId -gt 0) {
    Get-CimInstance Win32_Process -Filter "ProcessId = $listenerProcessId" -ErrorAction SilentlyContinue
} else { $null }
$listenerWasRunning = $null -ne $listenerCimProcess

if ($processWasRunning) {
    Assert-OwnedProcess -State $state -CimProcess $cimProcess
}
if ($listenerWasRunning) {
    Assert-OwnedListenerProcess -State $state -CimProcess $listenerCimProcess
    Stop-Process -Id $listenerProcessId
    $listenerDeadline = [DateTime]::UtcNow.AddSeconds($GracefulTimeoutSeconds)
    while ((Get-Process -Id $listenerProcessId -ErrorAction SilentlyContinue) -and
        [DateTime]::UtcNow -lt $listenerDeadline) {
        Start-Sleep -Milliseconds 250
    }
    if (Get-Process -Id $listenerProcessId -ErrorAction SilentlyContinue) {
        $refreshedListener = Get-CimInstance Win32_Process -Filter "ProcessId = $listenerProcessId" -ErrorAction SilentlyContinue
        Assert-OwnedListenerProcess -State $state -CimProcess $refreshedListener
        Stop-Process -Id $listenerProcessId -Force
    }
}

if ($processWasRunning -and (Get-Process -Id $recordedProcessId -ErrorAction SilentlyContinue)) {
    Stop-Process -Id $recordedProcessId
    $gracefulDeadline = [DateTime]::UtcNow.AddSeconds($GracefulTimeoutSeconds)
    while ((Get-Process -Id $recordedProcessId -ErrorAction SilentlyContinue) -and
        [DateTime]::UtcNow -lt $gracefulDeadline) {
        Start-Sleep -Milliseconds 250
    }
    if (Get-Process -Id $recordedProcessId -ErrorAction SilentlyContinue) {
        # This force applies only to the PID whose executable, command line, and creation time matched our state.
        Stop-Process -Id $recordedProcessId -Force
        $forcedDeadline = [DateTime]::UtcNow.AddSeconds($ForcedTimeoutSeconds)
        while ((Get-Process -Id $recordedProcessId -ErrorAction SilentlyContinue) -and
            [DateTime]::UtcNow -lt $forcedDeadline) {
            Start-Sleep -Milliseconds 200
        }
    }
    if (Get-Process -Id $recordedProcessId -ErrorAction SilentlyContinue) {
        throw "OWNED_RUNTIME_PID_DID_NOT_STOP:$recordedProcessId"
    }
}
if ($listenerProcessId -gt 0 -and (Get-Process -Id $listenerProcessId -ErrorAction SilentlyContinue)) {
    throw "OWNED_LISTENER_PID_DID_NOT_STOP:$listenerProcessId"
}

$portDeadline = [DateTime]::UtcNow.AddSeconds(15)
while (@(Get-PortListeners 8190).Count -ne 0 -and [DateTime]::UtcNow -lt $portDeadline) {
    Start-Sleep -Milliseconds 200
}
$listenersAfter = @(Get-PortListeners 8190)
if ($listenersAfter.Count -ne 0) {
    throw "PORT_8190_STILL_LISTENING_AFTER_OWNED_PID_STOP:owners=$($listenersAfter.OwningProcess -join ',')"
}
$runtimeProcessesAfter = @(Get-RuntimeProcesses)
if ($runtimeProcessesAfter.Count -ne 0) {
    throw "ISOLATED_RUNTIME_PROCESS_REMAINS:$($runtimeProcessesAfter[0].ProcessId):not killed because it is not the recorded PID"
}

Publish-PartialLog -PartialPath ([string]$state.stdout_log_partial) -FinalPath ([string]$state.stdout_log)
Publish-PartialLog -PartialPath ([string]$state.stderr_log_partial) -FinalPath ([string]$state.stderr_log)

$stoppedAt = [DateTime]::UtcNow
$archivePath = Join-Path $LogRoot ("runtime_state.stopped-{0}-{1}.json" -f $stoppedAt.ToString("yyyyMMddTHHmmssfffZ"), [Guid]::NewGuid().ToString("N"))
[System.IO.File]::Move($StatePath, $archivePath)
$listeners8188After = @(Get-PortListeners 8188)
$gpuMemoryUsedMb = Get-GpuMemoryUsedMb
$lifecycle = [ordered]@{
    contract = "forge-flux2-lifecycle-v1"
    action = "stopped"
    status = if ($listeners8188After.Count -eq 0) { "PASS" } else { "FAIL" }
    launcher_pid = $recordedProcessId
    listener_pid = $listenerProcessId
    process_was_running = $processWasRunning
    listener_was_running = $listenerWasRunning
    api_base = $ExpectedApiBase
    mode = [string]$state.mode
    port_8190_closed = $true
    port_8188_closed = ($listeners8188After.Count -eq 0)
    isolated_runtime_process_count = 0
    gpu_memory_used_mb_after_stop = $gpuMemoryUsedMb
    archived_runtime_state = $archivePath
    stopped_at_utc = $stoppedAt.ToString("o")
}
Write-JsonAtomic -Path $LifecyclePath -Value $lifecycle

if ($listeners8188After.Count -ne 0) {
    throw "PORT_8188_IS_LISTENING_AFTER_FLUX2_STOP:the owned 8190 PID was stopped; unrelated 8188 was not touched"
}

[ordered]@{
    status = "PASS"
    action = "stopped"
    launcher_pid = $recordedProcessId
    listener_pid = $listenerProcessId
    port_8190_closed = $true
    port_8188_closed = $true
    isolated_runtime_process_count = 0
    gpu_memory_used_mb_after_stop = $gpuMemoryUsedMb
} | ConvertTo-Json -Depth 6
