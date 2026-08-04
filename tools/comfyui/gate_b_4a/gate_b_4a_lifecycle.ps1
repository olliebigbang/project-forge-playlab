param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("start", "stop", "status")]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"
$gateRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $resolvedConfig = Join-Path $gateRoot "forge_gate_b_4a_config.local.json"
} elseif ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = [System.IO.Path]::GetFullPath($ConfigPath)
} else {
    $resolvedConfig = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $ConfigPath))
}
if (-not (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)) {
    throw "Gate B config missing: $resolvedConfig"
}
$config = [System.IO.File]::ReadAllText($resolvedConfig, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if ($config.api_base -ne "http://127.0.0.1:8188") {
    throw "Gate B 4A requires the exact loopback API http://127.0.0.1:8188"
}

function Resolve-GatePath([string]$Value) {
    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    if ($expanded.StartsWith('${')) { throw "Unresolved path configuration: $Value" }
    if ([System.IO.Path]::IsPathRooted($expanded)) { return [System.IO.Path]::GetFullPath($expanded) }
    return [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $resolvedConfig) $expanded))
}

$runtimeRoot = Join-Path $gateRoot "runtime"
$pidPath = Join-Path $runtimeRoot "comfyui.pid"
$lifecyclePath = Join-Path $runtimeRoot "lifecycle.json"
$stdoutPath = Join-Path $runtimeRoot "comfyui.stdout.log"
$stderrPath = Join-Path $runtimeRoot "comfyui.stderr.log"

function Get-PortListeners {
    return @(Get-NetTCPConnection -State Listen -LocalPort 8188 -ErrorAction SilentlyContinue)
}

function Write-Lifecycle([hashtable]$Payload) {
    New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
    $temporary = "$lifecyclePath.$([Guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($temporary, (($Payload | ConvertTo-Json -Depth 8) + "`n"), [System.Text.Encoding]::UTF8)
    Move-Item -LiteralPath $temporary -Destination $lifecyclePath -Force
}

if ($Action -eq "status") {
    $listeners = Get-PortListeners
    $recordedPid = if (Test-Path -LiteralPath $pidPath) { [int](Get-Content -LiteralPath $pidPath) } else { 0 }
    [pscustomobject]@{
        action = "status"
        recorded_pid = $recordedPid
        listener_count = $listeners.Count
        listeners = @($listeners | Select-Object LocalAddress, LocalPort, OwningProcess)
    } | ConvertTo-Json -Depth 6
    exit 0
}

if ($Action -eq "start") {
    $existing = Get-PortListeners
    if ($existing.Count -ne 0) {
        throw "Port 8188 is already listening; Gate B refuses to reuse any existing process."
    }
    if (Test-Path -LiteralPath $pidPath) {
        throw "Gate B PID file already exists; inspect it before starting: $pidPath"
    }
    $install = Resolve-GatePath ([string]$config.comfyui_install)
    $python = Resolve-GatePath ([string]$config.python_executable)
    $inputDirectory = Resolve-GatePath ([string]$config.input_directory)
    $outputDirectory = Resolve-GatePath ([string]$config.comfy_output_directory)
    $tempDirectory = Resolve-GatePath ([string]$config.runtime_temp_directory)
    $main = Join-Path $install "main.py"
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw "Configured Python is missing: $python" }
    if (-not (Test-Path -LiteralPath $main -PathType Leaf)) { throw "Configured ComfyUI main.py is missing: $main" }
    New-Item -ItemType Directory -Force -Path $runtimeRoot, $inputDirectory, $outputDirectory, $tempDirectory | Out-Null
    $arguments = '"{0}" --listen 127.0.0.1 --port 8188 --disable-auto-launch --output-directory "{1}" --input-directory "{2}" --temp-directory "{3}" --disable-metadata --preview-method none --disable-all-custom-nodes' -f $main, $outputDirectory, $inputDirectory, $tempDirectory
    $process = Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $install -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    [System.IO.File]::WriteAllText($pidPath, "$($process.Id)`n", [System.Text.Encoding]::ASCII)
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $healthy = $false
    $failure = "STARTUP_TIMEOUT"
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($process.HasExited) {
            $failure = "COMFYUI_EXITED_DURING_STARTUP:$($process.ExitCode)"
            break
        }
        $listeners = Get-PortListeners
        $ours = @($listeners | Where-Object { $_.LocalAddress -eq "127.0.0.1" -and $_.OwningProcess -eq $process.Id })
        $foreign = @($listeners | Where-Object { $_.LocalAddress -ne "127.0.0.1" -or $_.OwningProcess -ne $process.Id })
        if ($ours.Count -eq 1 -and $foreign.Count -eq 0) {
            try {
                $stats = Invoke-RestMethod -Uri "http://127.0.0.1:8188/system_stats" -Method Get -TimeoutSec 5
                $argv = @($stats.system.argv)
                if ($argv -contains "127.0.0.1" -and $argv -contains "--listen") {
                    $healthy = $true
                    break
                }
                $failure = "SYSTEM_STATS_ARGV_DID_NOT_ATTEST_LOOPBACK"
            } catch {
                $failure = "HEALTH_NOT_READY"
            }
        }
        Start-Sleep -Milliseconds 500
        $process.Refresh()
    }
    if (-not $healthy) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
        Remove-Item -LiteralPath $pidPath -ErrorAction SilentlyContinue
        throw "Gate B ComfyUI start failed: $failure"
    }
    Write-Lifecycle @{
        gate = "GATE_B_4A"
        action = "started"
        pid = $process.Id
        api_base = "http://127.0.0.1:8188"
        selected_install = [string]$config.selected_install_label
        checkpoint = [string]$config.checkpoint
        start_arguments = $arguments
        started_at_utc = [DateTime]::UtcNow.ToString("o")
    }
    Write-Output "GATE_B_4A_COMFYUI_STARTED pid=$($process.Id) api=http://127.0.0.1:8188"
    exit 0
}

if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) {
    $listeners = Get-PortListeners
    if ($listeners.Count -ne 0) {
        throw "No Gate B PID record exists, but port 8188 is listening; refusing to stop an unowned process."
    }
    Write-Output "GATE_B_4A_COMFYUI_ALREADY_STOPPED port_8188_closed=true"
    exit 0
}
$recordedPid = [int](Get-Content -LiteralPath $pidPath)
$listenersBefore = Get-PortListeners
$foreignBefore = @($listenersBefore | Where-Object { $_.OwningProcess -ne $recordedPid })
if ($foreignBefore.Count -ne 0) {
    throw "Port 8188 has a listener not owned by Gate B PID $recordedPid; refusing destructive stop."
}
$ownedProcess = Get-Process -Id $recordedPid -ErrorAction SilentlyContinue
if ($ownedProcess) {
    Stop-Process -Id $recordedPid
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ((Get-Process -Id $recordedPid -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
    if (Get-Process -Id $recordedPid -ErrorAction SilentlyContinue) {
        throw "Gate B ComfyUI PID $recordedPid did not stop within 30 seconds."
    }
}
$listenersAfter = Get-PortListeners
if ($listenersAfter.Count -ne 0) {
    throw "Port 8188 is still listening after stopping Gate B PID $recordedPid."
}
Remove-Item -LiteralPath $pidPath
Write-Lifecycle @{
    gate = "GATE_B_4A"
    action = "stopped"
    pid = $recordedPid
    api_base = "http://127.0.0.1:8188"
    port_8188_closed = $true
    stopped_at_utc = [DateTime]::UtcNow.ToString("o")
}
Write-Output "GATE_B_4A_COMFYUI_STOPPED pid=$recordedPid port_8188_closed=true"
