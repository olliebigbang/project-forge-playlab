[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$LowMemory,

    [Parameter(Mandatory = $false)]
    [ValidateRange(30, 600)]
    [int]$StartupTimeoutSeconds = 240
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ExpectedApiBase = "http://127.0.0.1:8190"
$ExpectedRuntimeRoot = "C:\AI\ComfyUI-ForgeFlux2"
$ExpectedComfyCommit = "b1693ecba9f5b65f8c80ab36b195ab963ec92413"
$ExpectedComfyRemote = "https://github.com/Comfy-Org/ComfyUI.git"
$ExpectedComfyTag = "v0.30.0"
$ExpectedModels = @(
    "flux-2-klein-4b-fp8.safetensors",
    "qwen_3_4b.safetensors",
    "flux2-vae.safetensors"
)

$Flux2Root = Split-Path -Parent $PSScriptRoot
$ComfyToolsRoot = Split-Path -Parent $Flux2Root
$ProfilePath = Join-Path $ComfyToolsRoot "config\profiles\flux2_klein_4b.json"
$ModelManifestPath = Join-Path $Flux2Root "reports\model_download_manifest.json"
$LogRoot = Join-Path $Flux2Root "logs"
$StatePath = Join-Path $LogRoot "runtime_state.json"
$LifecyclePath = Join-Path $LogRoot "lifecycle_last.json"

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
        $json = ($Value | ConvertTo-Json -Depth 20) + "`n"
        [System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Replace($temporary, $Path, $backup, $true)
            if ([System.IO.File]::Exists($backup)) {
                [System.IO.File]::Delete($backup)
            }
        }
        else {
            [System.IO.File]::Move($temporary, $Path)
        }
    }
    finally {
        if ([System.IO.File]::Exists($temporary)) {
            [System.IO.File]::Delete($temporary)
        }
        if ([System.IO.File]::Exists($backup)) {
            [System.IO.File]::Delete($backup)
        }
    }
}

function Get-PortListeners {
    param([Parameter(Mandatory = $true)][int]$Port)
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Get-RuntimeProcesses {
    param(
        [Parameter(Mandatory = $true)][string]$PythonPath,
        [Parameter(Mandatory = $true)][string]$MainPath
    )
    $expectedPython = ConvertTo-NormalizedPath $PythonPath
    $expectedMain = ConvertTo-NormalizedPath $MainPath
    return @(
        Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $executable = [string]$_.ExecutablePath
            $commandLine = [string]$_.CommandLine
            ((-not [string]::IsNullOrWhiteSpace($executable)) -and
                ((ConvertTo-NormalizedPath $executable) -ieq $expectedPython)) -or
            ((-not [string]::IsNullOrWhiteSpace($commandLine)) -and
                $commandLine.IndexOf($expectedMain, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
        }
    )
}

function Assert-HelpFlag {
    param(
        [Parameter(Mandatory = $true)][string]$HelpText,
        [Parameter(Mandatory = $true)][string]$Flag
    )
    if ($HelpText.IndexOf($Flag, [System.StringComparison]::Ordinal) -lt 0) {
        throw "COMFYUI_HELP_FLAG_MISSING:$Flag"
    }
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

function Get-VerifiedListenerProcess {
    param(
        [Parameter(Mandatory = $true)]$Listener,
        [Parameter(Mandatory = $true)][int]$LauncherPid,
        [Parameter(Mandatory = $true)][string]$MainPath
    )
    if ([string]$Listener.LocalAddress -ne "127.0.0.1") { return $null }
    $candidate = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$Listener.OwningProcess)" -ErrorAction SilentlyContinue
    if ($null -eq $candidate) { return $null }
    $commandLine = [string]$candidate.CommandLine
    $isLauncherOrDirectChild = [int]$candidate.ProcessId -eq $LauncherPid -or [int]$candidate.ParentProcessId -eq $LauncherPid
    $commandMatches = $commandLine.IndexOf($MainPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $commandLine.IndexOf("--listen 127.0.0.1", [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $commandLine.IndexOf("--port 8190", [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        $commandLine.IndexOf("--disable-all-custom-nodes", [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    if (-not $isLauncherOrDirectChild -or -not $commandMatches -or
        [System.IO.Path]::GetFileName([string]$candidate.ExecutablePath) -ine "python.exe") {
        return $null
    }
    return $candidate
}

function Stop-StartedProcess {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    $owned = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $owned) {
        return
    }
    Stop-Process -Id $ProcessId -ErrorAction SilentlyContinue
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Publish-PartialLog {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PartialPath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FinalPath
    )
    if ([string]::IsNullOrWhiteSpace($PartialPath) -or [string]::IsNullOrWhiteSpace($FinalPath)) {
        return
    }
    if (-not [System.IO.File]::Exists($PartialPath)) {
        return
    }
    if ([System.IO.File]::Exists($FinalPath)) {
        throw "REFUSING_TO_OVERWRITE_LOG:$FinalPath"
    }
    [System.IO.File]::Move($PartialPath, $FinalPath)
}

$startedProcess = $null
$statePublished = $false
$stdoutPartial = ""
$stderrPartial = ""
$stdoutFinal = ""
$stderrFinal = ""
$runToken = "{0}-{1}" -f [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ"), [Guid]::NewGuid().ToString("N")
$modeName = if ($LowMemory) { "low_memory" } else { "normal" }

try {
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        throw "FLUX2_PROFILE_MISSING:$ProfilePath"
    }
    if (-not (Test-Path -LiteralPath $ModelManifestPath -PathType Leaf)) {
        throw "MODEL_DOWNLOAD_MANIFEST_MISSING:$ModelManifestPath"
    }
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        throw "RUNTIME_STATE_ALREADY_EXISTS:run stop_flux2_comfyui.ps1 before starting"
    }
    if (@(Get-PortListeners 8188).Count -ne 0) {
        throw "PORT_8188_MUST_NOT_BE_LISTENING"
    }
    if (@(Get-PortListeners 8190).Count -ne 0) {
        throw "PORT_8190_ALREADY_LISTENING:refusing to reuse or claim an existing service"
    }

    $profile = [System.IO.File]::ReadAllText($ProfilePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$profile.profile_id -ne "flux2_klein_4b") {
        throw "PROFILE_ID_INVALID"
    }
    if ([string]$profile.api_base -ne $ExpectedApiBase) {
        throw "PROFILE_API_BASE_INVALID:expected $ExpectedApiBase"
    }
    if ([string]$profile.selected_install_label -ne "forge-flux2-isolated-v0.30.0") {
        throw "PROFILE_INSTALL_LABEL_INVALID"
    }

    $runtimeRoot = ConvertTo-NormalizedPath ([string]$profile.runtime_root)
    $comfyRoot = ConvertTo-NormalizedPath ([string]$profile.comfyui_root)
    $pythonPath = ConvertTo-NormalizedPath ([string]$profile.python_executable)
    $expectedRuntime = ConvertTo-NormalizedPath $ExpectedRuntimeRoot
    $expectedComfy = ConvertTo-NormalizedPath (Join-Path $ExpectedRuntimeRoot "ComfyUI")
    $expectedPython = ConvertTo-NormalizedPath (Join-Path $ExpectedRuntimeRoot ".venv\Scripts\python.exe")
    if ($runtimeRoot -ine $expectedRuntime -or $comfyRoot -ine $expectedComfy -or $pythonPath -ine $expectedPython) {
        throw "ISOLATED_RUNTIME_PATH_MISMATCH"
    }
    foreach ($requiredPath in @($runtimeRoot, $comfyRoot, $pythonPath)) {
        if ([System.IO.Path]::GetPathRoot($requiredPath).TrimEnd('\') -ine "C:") {
            throw "RUNTIME_MUST_REMAIN_ON_C_DRIVE:$requiredPath"
        }
    }
    $mainPath = ConvertTo-NormalizedPath (Join-Path $comfyRoot "main.py")
    if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
        throw "ISOLATED_VENV_PYTHON_MISSING:$pythonPath"
    }
    if (-not (Test-Path -LiteralPath $mainPath -PathType Leaf)) {
        throw "COMFYUI_MAIN_MISSING:$mainPath"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $comfyRoot ".git") -PathType Container)) {
        throw "COMFYUI_RUNTIME_IS_NOT_A_GIT_CHECKOUT"
    }

    $git = Get-Command git.exe -ErrorAction Stop
    $remote = ((& $git.Source -C $comfyRoot remote get-url origin) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $remote -ine $ExpectedComfyRemote) {
        throw "COMFYUI_REMOTE_MISMATCH:$remote"
    }
    $commit = ((& $git.Source -C $comfyRoot rev-parse HEAD) | Out-String).Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $commit -ne $ExpectedComfyCommit) {
        throw "COMFYUI_COMMIT_MISMATCH:$commit"
    }
    $tagsAtHead = @(& $git.Source -C $comfyRoot tag --points-at HEAD)
    if ($LASTEXITCODE -ne 0 -or $tagsAtHead -notcontains $ExpectedComfyTag) {
        throw "COMFYUI_RELEASE_TAG_MISSING_AT_COMMIT:$ExpectedComfyTag"
    }
    $trackedRuntimeChanges = ((& $git.Source -C $comfyRoot status --porcelain --untracked-files=no) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($trackedRuntimeChanges)) {
        throw "COMFYUI_TRACKED_WORKTREE_NOT_CLEAN"
    }

    $pythonProbeCode = @'
import json, os, sys
import torch
print(json.dumps({
    'executable': os.path.realpath(sys.executable),
    'prefix': os.path.realpath(sys.prefix),
    'base_prefix': os.path.realpath(sys.base_prefix),
    'version': sys.version.split()[0],
    'torch_version': torch.__version__,
    'cuda_runtime': torch.version.cuda,
    'cuda_available': torch.cuda.is_available(),
    'cuda_device_count': torch.cuda.device_count(),
    'cuda_device_name': torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
}))
'@
    $pythonProbeText = ((& $pythonPath -I -c $pythonProbeCode 2>&1) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "VENV_CUDA_PROBE_FAILED:$pythonProbeText"
    }
    try {
        $pythonProbe = $pythonProbeText | ConvertFrom-Json
    }
    catch {
        throw "VENV_CUDA_PROBE_RETURNED_INVALID_JSON"
    }
    if ((ConvertTo-NormalizedPath ([string]$pythonProbe.executable)) -ine $pythonPath) {
        throw "VENV_EXECUTABLE_MISMATCH"
    }
    $expectedVenv = ConvertTo-NormalizedPath (Join-Path $ExpectedRuntimeRoot ".venv")
    if ((ConvertTo-NormalizedPath ([string]$pythonProbe.prefix)) -ine $expectedVenv -or
        (ConvertTo-NormalizedPath ([string]$pythonProbe.base_prefix)) -ieq $expectedVenv) {
        throw "PYTHON_IS_NOT_THE_ISOLATED_VENV"
    }
    if (-not [bool]$pythonProbe.cuda_available -or [int]$pythonProbe.cuda_device_count -lt 1 -or
        [string]::IsNullOrWhiteSpace([string]$pythonProbe.cuda_runtime)) {
        throw "CUDA_NOT_AVAILABLE_IN_ISOLATED_VENV"
    }

    $manifest = [System.IO.File]::ReadAllText($ModelManifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$manifest.contract -ne "forge-flux2-model-download-v1" -or [string]$manifest.status -ne "PASS") {
        throw "MODEL_DOWNLOAD_MANIFEST_NOT_PASS"
    }
    if ((ConvertTo-NormalizedPath ([string]$manifest.runtime_root)) -ine $runtimeRoot) {
        throw "MODEL_MANIFEST_RUNTIME_MISMATCH"
    }
    $manifestFiles = @($manifest.files)
    if ($manifestFiles.Count -ne 3) {
        throw "MODEL_MANIFEST_MUST_CONTAIN_EXACTLY_THREE_FILES"
    }
    $modelEvidence = @()
    foreach ($expectedName in $ExpectedModels) {
        $matches = @($manifestFiles | Where-Object { [string]$_.filename -eq $expectedName })
        if ($matches.Count -ne 1) {
            throw "MODEL_MANIFEST_ENTRY_INVALID:$expectedName"
        }
        $entry = $matches[0]
        if ([string]$entry.status -ne "downloaded_verified") {
            throw "MODEL_NOT_VERIFIED:$expectedName"
        }
        $destination = ConvertTo-NormalizedPath ([string]$entry.destination)
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            throw "MODEL_FILE_MISSING:$expectedName"
        }
        $profileModelPaths = @(
            ConvertTo-NormalizedPath ([string]$profile.model_paths.diffusion_model)
            ConvertTo-NormalizedPath ([string]$profile.model_paths.text_encoder)
            ConvertTo-NormalizedPath ([string]$profile.model_paths.vae)
        )
        if ($profileModelPaths -notcontains $destination) {
            throw "MODEL_DESTINATION_NOT_IN_PROFILE:$expectedName"
        }
        if ([int64]$entry.bytes -ne (Get-Item -LiteralPath $destination).Length) {
            throw "MODEL_SIZE_MISMATCH:$expectedName"
        }
        $actualHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne ([string]$entry.sha256).ToLowerInvariant() -or
            $actualHash -ne ([string]$entry.expected_sha256).ToLowerInvariant()) {
            throw "MODEL_SHA256_MISMATCH:$expectedName"
        }
        $modelEvidence += [ordered]@{
            filename = $expectedName
            bytes = [int64]$entry.bytes
            sha256 = $actualHash
            destination = $destination
        }
    }
    $unexpectedWeights = @(
        Get-ChildItem -LiteralPath (Join-Path $comfyRoot "models") -Recurse -File -ErrorAction Stop |
            Where-Object { @(".safetensors", ".gguf", ".ckpt", ".pt", ".pth") -contains $_.Extension.ToLowerInvariant() } |
            Where-Object { $modelEvidence.destination -notcontains (ConvertTo-NormalizedPath $_.FullName) }
    )
    if ($unexpectedWeights.Count -ne 0) {
        throw "UNAUTHORIZED_MODEL_WEIGHT_PRESENT:$($unexpectedWeights[0].FullName)"
    }

    $helpText = ((& $pythonPath $mainPath --help 2>&1) | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "COMFYUI_MAIN_HELP_FAILED"
    }
    $normalFlags = @(
        "--listen", "--port", "--disable-auto-launch", "--output-directory",
        "--input-directory", "--temp-directory", "--disable-metadata",
        "--preview-method", "--disable-all-custom-nodes", "--disable-api-nodes"
    )
    foreach ($flag in $normalFlags) {
        Assert-HelpFlag -HelpText $helpText -Flag $flag
    }
    if ($LowMemory) {
        foreach ($flag in @("--lowvram", "--cpu-vae", "--cache-none")) {
            Assert-HelpFlag -HelpText $helpText -Flag $flag
        }
    }

    $runtimeProcesses = @(Get-RuntimeProcesses -PythonPath $pythonPath -MainPath $mainPath)
    if ($runtimeProcesses.Count -ne 0) {
        throw "UNOWNED_ISOLATED_RUNTIME_PROCESS_ALREADY_EXISTS:$($runtimeProcesses[0].ProcessId)"
    }
    if (@(Get-PortListeners 8188).Count -ne 0 -or @(Get-PortListeners 8190).Count -ne 0) {
        throw "PORT_STATE_CHANGED_DURING_PREFLIGHT"
    }

    $inputDirectory = ConvertTo-NormalizedPath ([string]$profile.comfy_input_directory)
    $outputDirectory = ConvertTo-NormalizedPath ([string]$profile.comfy_output_directory)
    $tempDirectory = ConvertTo-NormalizedPath (Join-Path $ExpectedRuntimeRoot "runtime-temp")
    foreach ($directory in @($inputDirectory, $outputDirectory, $tempDirectory, $LogRoot)) {
        if ([System.IO.Path]::GetPathRoot($directory).TrimEnd('\') -ine "C:") {
            throw "RUNTIME_DIRECTORY_MUST_BE_ON_C_DRIVE:$directory"
        }
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $preflight = [ordered]@{
        contract = "forge-flux2-runtime-preflight-v1"
        status = "PASS"
        checked_at_utc = [DateTime]::UtcNow.ToString("o")
        mode = $modeName
        api_base = $ExpectedApiBase
        port_8188_closed = $true
        port_8190_closed_before_start = $true
        runtime_root = $runtimeRoot
        comfyui_root = $comfyRoot
        python_executable = $pythonPath
        python = $pythonProbe
        comfyui_remote = $remote
        comfyui_commit = $commit
        comfyui_tag = $ExpectedComfyTag
        tracked_worktree_clean = $true
        help_sha256 = ([System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($helpText))
        ) -replace "-", "").ToLowerInvariant()
        models = $modelEvidence
    }
    Write-JsonAtomic -Path (Join-Path $LogRoot "preflight_last.json") -Value $preflight

    $stdoutPartial = Join-Path $LogRoot ("comfyui-{0}.stdout.partial" -f $runToken)
    $stderrPartial = Join-Path $LogRoot ("comfyui-{0}.stderr.partial" -f $runToken)
    $stdoutFinal = Join-Path $LogRoot ("comfyui-{0}.stdout.log" -f $runToken)
    $stderrFinal = Join-Path $LogRoot ("comfyui-{0}.stderr.log" -f $runToken)
    $argumentValues = @(
        $mainPath,
        "--listen", "127.0.0.1",
        "--port", "8190",
        "--disable-auto-launch",
        "--output-directory", $outputDirectory,
        "--input-directory", $inputDirectory,
        "--temp-directory", $tempDirectory,
        "--disable-metadata",
        "--preview-method", "none",
        "--disable-all-custom-nodes",
        "--disable-api-nodes"
    )
    if ($LowMemory) {
        $argumentValues += @("--lowvram", "--cpu-vae", "--cache-none")
    }
    $argumentLine = ($argumentValues | ForEach-Object {
        $value = [string]$_
        if ($value.Contains('"')) {
            throw "UNSAFE_DOUBLE_QUOTE_IN_START_ARGUMENT"
        }
        if ($value -match '\s') { '"{0}"' -f $value } else { $value }
    }) -join " "

    $startedProcess = Start-Process -FilePath $pythonPath -ArgumentList $argumentLine `
        -WorkingDirectory $comfyRoot -RedirectStandardOutput $stdoutPartial `
        -RedirectStandardError $stderrPartial -WindowStyle Hidden -PassThru

    $cimProcess = $null
    $cimDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while ($null -eq $cimProcess -and [DateTime]::UtcNow -lt $cimDeadline) {
        $cimProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($startedProcess.Id)" -ErrorAction SilentlyContinue
        if ($null -eq $cimProcess) { Start-Sleep -Milliseconds 100 }
    }
    if ($null -eq $cimProcess) {
        throw "STARTED_PROCESS_IDENTITY_UNAVAILABLE"
    }
    $creationUtc = ([DateTime]$cimProcess.CreationDate).ToUniversalTime().ToString("o")
    $runtimeState = [ordered]@{
        contract = "forge-flux2-owned-runtime-v1"
        status = "starting"
        ownership_nonce = [Guid]::NewGuid().ToString("N")
        pid = [int]$startedProcess.Id
        process_creation_utc = $creationUtc
        command_line = [string]$cimProcess.CommandLine
        executable_path = ConvertTo-NormalizedPath ([string]$cimProcess.ExecutablePath)
        python_executable = $pythonPath
        main_py = $mainPath
        runtime_root = $runtimeRoot
        comfyui_root = $comfyRoot
        comfyui_commit = $commit
        api_base = $ExpectedApiBase
        listen_address = "127.0.0.1"
        port = 8190
        mode = $modeName
        argument_values = $argumentValues
        stdout_log_partial = $stdoutPartial
        stderr_log_partial = $stderrPartial
        stdout_log = $stdoutFinal
        stderr_log = $stderrFinal
        started_at_utc = [DateTime]::UtcNow.ToString("o")
    }
    Write-JsonAtomic -Path $StatePath -Value $runtimeState
    $statePublished = $true

    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    $lastFailure = "STARTUP_TIMEOUT"
    $healthy = $false
    $healthyListenerProcess = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $startedProcess.Refresh()
        if ($startedProcess.HasExited) {
            $lastFailure = "COMFYUI_EXITED_DURING_STARTUP:$($startedProcess.ExitCode)"
            break
        }
        if (@(Get-PortListeners 8188).Count -ne 0) {
            $lastFailure = "PORT_8188_BECAME_LISTENING"
            break
        }
        $listeners = @(Get-PortListeners 8190)
        $verified = @()
        $foreign = @()
        foreach ($listener in $listeners) {
            $verifiedProcess = Get-VerifiedListenerProcess -Listener $listener -LauncherPid ([int]$startedProcess.Id) -MainPath $mainPath
            if ($null -ne $verifiedProcess) {
                $verified += [pscustomobject]@{ Listener = $listener; Process = $verifiedProcess }
            }
            else {
                $foreign += $listener
            }
        }
        if ($verified.Count -eq 1 -and $foreign.Count -eq 0) {
            try {
                $stats = Invoke-RestMethod -Uri "$ExpectedApiBase/system_stats" -Method Get -TimeoutSec 5
                $serverArguments = @($stats.system.argv)
                if ((Test-ArgumentPair -Arguments $serverArguments -Name "--listen" -Value "127.0.0.1") -and
                    (Test-ArgumentPair -Arguments $serverArguments -Name "--port" -Value "8190") -and
                    $serverArguments -contains "--disable-all-custom-nodes" -and
                    $serverArguments -contains "--disable-api-nodes") {
                    $healthy = $true
                    $healthyListenerProcess = $verified[0].Process
                    break
                }
                $lastFailure = "SYSTEM_STATS_ARGUMENT_ATTESTATION_FAILED"
            }
            catch {
                $lastFailure = "SYSTEM_STATS_NOT_READY"
            }
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $healthy) {
        throw "COMFYUI_START_FAILED:$lastFailure"
    }

    $runtimeState["listener_pid"] = [int]$healthyListenerProcess.ProcessId
    $runtimeState["listener_parent_pid"] = [int]$healthyListenerProcess.ParentProcessId
    $runtimeState["listener_process_creation_utc"] = ([DateTime]$healthyListenerProcess.CreationDate).ToUniversalTime().ToString("o")
    $runtimeState["listener_command_line"] = [string]$healthyListenerProcess.CommandLine
    $runtimeState["listener_executable_path"] = ConvertTo-NormalizedPath ([string]$healthyListenerProcess.ExecutablePath)
    $runtimeState.status = "running"
    $runtimeState.healthy_at_utc = [DateTime]::UtcNow.ToString("o")
    Write-JsonAtomic -Path $StatePath -Value $runtimeState
    Write-JsonAtomic -Path $LifecyclePath -Value ([ordered]@{
        contract = "forge-flux2-lifecycle-v1"
        action = "started"
        status = "PASS"
        pid = [int]$startedProcess.Id
        api_base = $ExpectedApiBase
        mode = $modeName
        comfyui_commit = $commit
        port_8188_closed = $true
        listener_owned_and_loopback_only = $true
        recorded_at_utc = [DateTime]::UtcNow.ToString("o")
    })

    [ordered]@{
        status = "PASS"
        action = "started"
        pid = [int]$startedProcess.Id
        api_base = $ExpectedApiBase
        mode = $modeName
        comfyui_commit = $commit
    } | ConvertTo-Json -Depth 6
}
catch {
    $failureMessage = $_.Exception.Message
    $cleanupPid = 0
    if ($null -ne $startedProcess) {
        $cleanupPid = [int]$startedProcess.Id
        Stop-StartedProcess -ProcessId $cleanupPid
    }
    $portClosed = @(Get-PortListeners 8190).Count -eq 0
    if ($statePublished -and $portClosed -and -not (Get-Process -Id $cleanupPid -ErrorAction SilentlyContinue)) {
        $failedStatePath = Join-Path $LogRoot ("runtime_state.failed-{0}.json" -f $runToken)
        if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
            [System.IO.File]::Move($StatePath, $failedStatePath)
        }
    }
    Publish-PartialLog -PartialPath $stdoutPartial -FinalPath $stdoutFinal
    Publish-PartialLog -PartialPath $stderrPartial -FinalPath $stderrFinal
    Write-JsonAtomic -Path $LifecyclePath -Value ([ordered]@{
        contract = "forge-flux2-lifecycle-v1"
        action = "start_failed"
        status = "FAIL"
        failure_reason = $failureMessage
        pid = $cleanupPid
        api_base = $ExpectedApiBase
        mode = $modeName
        port_8190_closed_after_cleanup = $portClosed
        port_8188_closed = (@(Get-PortListeners 8188).Count -eq 0)
        recorded_at_utc = [DateTime]::UtcNow.ToString("o")
    })
    throw
}
