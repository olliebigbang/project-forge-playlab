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

$SmokePrompt = @"
one isolated old wooden table, flat rectangular tabletop, four wooden legs, aged wood, side view, complete object visible, plain background
"@.Trim()
$SmokeSeed = 5050001
$ExpectedApiBase = "http://127.0.0.1:8190"
$Flux2Root = Split-Path -Parent $PSScriptRoot
$ComfyToolsRoot = Split-Path -Parent $Flux2Root
$ProfilePath = Join-Path $ComfyToolsRoot "config\profiles\flux2_klein_4b.json"
$RunnerPath = Join-Path $Flux2Root "bridge\run_flux2_spike.py"
$StartScript = Join-Path $PSScriptRoot "start_flux2_comfyui.ps1"
$StopScript = Join-Path $PSScriptRoot "stop_flux2_comfyui.ps1"
$LogRoot = Join-Path $Flux2Root "logs"
$StatePath = Join-Path $LogRoot "runtime_state.json"
$PreflightPath = Join-Path $LogRoot "preflight_last.json"
$AttemptLedgerPath = Join-Path $LogRoot "smoke_attempts.json"
$SmokeLastPath = Join-Path $LogRoot "smoke_last.json"
$modeName = if ($LowMemory) { "low_memory" } else { "normal" }
$runToken = "smoke-{0}-{1}" -f [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ"), [Guid]::NewGuid().ToString("N")

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
            (($Value | ConvertTo-Json -Depth 30) + "`n"),
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

function Publish-PartialLog {
    param(
        [Parameter(Mandatory = $true)][string]$PartialPath,
        [Parameter(Mandatory = $true)][string]$FinalPath
    )
    if (-not [System.IO.File]::Exists($PartialPath)) { return }
    if ([System.IO.File]::Exists($FinalPath)) {
        throw "REFUSING_TO_OVERWRITE_SMOKE_LOG:$FinalPath"
    }
    [System.IO.File]::Move($PartialPath, $FinalPath)
}

function ConvertTo-SafeCommandLine {
    param([Parameter(Mandatory = $true)][string[]]$Values)
    return ($Values | ForEach-Object {
        $value = [string]$_
        if ($value.Contains('"')) {
            throw "UNSAFE_DOUBLE_QUOTE_IN_SMOKE_ARGUMENT"
        }
        if ($value -match '\s') { '"{0}"' -f $value } else { $value }
    }) -join " "
}

function Get-ExistingAttempts {
    if (-not (Test-Path -LiteralPath $AttemptLedgerPath -PathType Leaf)) {
        return @()
    }
    try {
        $ledger = [System.IO.File]::ReadAllText($AttemptLedgerPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        throw "SMOKE_ATTEMPT_LEDGER_INVALID_JSON"
    }
    if ([string]$ledger.contract -ne "forge-flux2-smoke-attempts-v1") {
        throw "SMOKE_ATTEMPT_LEDGER_CONTRACT_INVALID"
    }
    return @($ledger.attempts)
}

function Save-Attempts {
    param([Parameter(Mandatory = $true)][object[]]$Attempts)
    Write-JsonAtomic -Path $AttemptLedgerPath -Value ([ordered]@{
        contract = "forge-flux2-smoke-attempts-v1"
        fixed_prompt = $SmokePrompt
        fixed_seed = $SmokeSeed
        automatic_retry_count = 0
        attempts = $Attempts
        updated_at_utc = [DateTime]::UtcNow.ToString("o")
    })
}

function Test-CudaOomText {
    param([Parameter(Mandatory = $true)][string]$Text)
    return $Text -match '(?i)(CUDA\s+out\s+of\s+memory|CUDA_OOM|OutOfMemoryError|CUBLAS_STATUS_ALLOC_FAILED)'
}

foreach ($requiredFile in @($ProfilePath, $RunnerPath, $StartScript, $StopScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "SMOKE_DEPENDENCY_MISSING:$requiredFile"
    }
}
$profile = [System.IO.File]::ReadAllText($ProfilePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if ([string]$profile.profile_id -ne "flux2_klein_4b" -or [string]$profile.api_base -ne $ExpectedApiBase) {
    throw "SMOKE_PROFILE_BINDING_INVALID"
}
if ([int]$profile.generation.width -ne 512 -or [int]$profile.generation.height -ne 512 -or
    [int]$profile.generation.batch_size -ne 1 -or [int]$profile.generation.steps -ne 4 -or
    [int]$profile.generation.concurrency -ne 1) {
    throw "SMOKE_PROFILE_FIXED_PARAMETERS_CHANGED"
}
if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    throw "SMOKE_REQUIRES_STOPPED_RUNTIME:refusing to reuse a service owned by another invocation"
}

$existingAttempts = @(Get-ExistingAttempts)
$normalAttempts = @($existingAttempts | Where-Object { [string]$_.mode -eq "normal" })
$lowMemoryAttempts = @($existingAttempts | Where-Object { [string]$_.mode -eq "low_memory" })
if ($LowMemory) {
    if ($lowMemoryAttempts.Count -ne 0) {
        throw "LOW_MEMORY_SMOKE_ALREADY_ATTEMPTED:no repeated retries are allowed"
    }
    if ($normalAttempts.Count -ne 1 -or [string]$normalAttempts[0].outcome -ne "CUDA_OOM") {
        throw "LOW_MEMORY_REQUIRES_EXACTLY_ONE_RECORDED_NORMAL_CUDA_OOM"
    }
}
elseif ($normalAttempts.Count -ne 0) {
    throw "NORMAL_SMOKE_ALREADY_ATTEMPTED:no repeated retries are allowed"
}

$runtimeStarted = $false
$attemptRecord = $null
$allAttempts = [System.Collections.ArrayList]::new()
foreach ($existing in $existingAttempts) { [void]$allAttempts.Add($existing) }
$primaryError = $null
$stopError = $null
$bridgeStdoutPartial = Join-Path $LogRoot ("{0}.bridge.stdout.partial" -f $runToken)
$bridgeStderrPartial = Join-Path $LogRoot ("{0}.bridge.stderr.partial" -f $runToken)
$bridgeStdoutFinal = Join-Path $LogRoot ("{0}.bridge.stdout.log" -f $runToken)
$bridgeStderrFinal = Join-Path $LogRoot ("{0}.bridge.stderr.log" -f $runToken)
$wallClock = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $startParameters = @{ StartupTimeoutSeconds = $StartupTimeoutSeconds }
    if ($LowMemory) { $startParameters.LowMemory = $true }
    $startOutput = (& $StartScript @startParameters | Out-String).Trim()
    $runtimeStarted = $true
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $PreflightPath -PathType Leaf)) {
        throw "SMOKE_START_DID_NOT_PUBLISH_RUNTIME_EVIDENCE"
    }
    $runtimeState = [System.IO.File]::ReadAllText($StatePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $preflight = [System.IO.File]::ReadAllText($PreflightPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$runtimeState.status -ne "running" -or [string]$runtimeState.mode -ne $modeName -or
        [string]$preflight.status -ne "PASS" -or [string]$preflight.mode -ne $modeName) {
        throw "SMOKE_RUNTIME_EVIDENCE_INVALID"
    }

    $attemptRecord = [ordered]@{
        attempt_id = $runToken
        mode = $modeName
        status = "running"
        outcome = "UNFINISHED"
        prompt = $SmokePrompt
        seed = $SmokeSeed
        width = 512
        height = 512
        batch_size = 1
        steps = 4
        retry_count = 0
        automatic_retry = $false
        runtime_pid = [int]$runtimeState.pid
        comfyui_commit = [string]$runtimeState.comfyui_commit
        model_hashes = [ordered]@{}
        failure_reason = ""
        output_directory = ""
        raw_png = ""
        raw_png_bytes = 0
        raw_png_sha256 = ""
        output_size = @()
        workflow_hash = ""
        generation_seconds = 0.0
        total_wall_seconds = 0.0
        peak_vram_mb = 0.0
        peak_ram_mb = 0.0
        started_at_utc = [DateTime]::UtcNow.ToString("o")
        completed_at_utc = ""
        bridge_stdout_log = $bridgeStdoutFinal
        bridge_stderr_log = $bridgeStderrFinal
    }
    foreach ($model in @($preflight.models)) {
        $attemptRecord.model_hashes[[string]$model.filename] = [string]$model.sha256
    }
    [void]$allAttempts.Add($attemptRecord)
    Save-Attempts -Attempts @($allAttempts)

    $pythonPath = [System.IO.Path]::GetFullPath([string]$profile.python_executable)
    $bridgeArguments = @(
        $RunnerPath,
        "--profile", $ProfilePath,
        "smoke",
        "--mode", $modeName
    )
    $bridgeArgumentLine = ConvertTo-SafeCommandLine -Values $bridgeArguments
    $bridgeProcess = Start-Process -FilePath $pythonPath -ArgumentList $bridgeArgumentLine `
        -WorkingDirectory (Split-Path -Parent $RunnerPath) -RedirectStandardOutput $bridgeStdoutPartial `
        -RedirectStandardError $bridgeStderrPartial -WindowStyle Hidden -Wait -PassThru
    Publish-PartialLog -PartialPath $bridgeStdoutPartial -FinalPath $bridgeStdoutFinal
    Publish-PartialLog -PartialPath $bridgeStderrPartial -FinalPath $bridgeStderrFinal
    $bridgeStdout = if (Test-Path -LiteralPath $bridgeStdoutFinal) {
        [System.IO.File]::ReadAllText($bridgeStdoutFinal, [System.Text.Encoding]::UTF8).Trim()
    } else { "" }
    $bridgeStderr = if (Test-Path -LiteralPath $bridgeStderrFinal) {
        [System.IO.File]::ReadAllText($bridgeStderrFinal, [System.Text.Encoding]::UTF8).Trim()
    } else { "" }
    if ($bridgeProcess.ExitCode -ne 0) {
        $combinedFailure = "$bridgeStdout`n$bridgeStderr".Trim()
        if (Test-CudaOomText -Text $combinedFailure) {
            $attemptRecord.status = "completed"
            $attemptRecord.outcome = "CUDA_OOM"
            $attemptRecord.failure_reason = "CUDA_OOM"
            $attemptRecord.completed_at_utc = [DateTime]::UtcNow.ToString("o")
            Save-Attempts -Attempts @($allAttempts)
            throw "SMOKE_CUDA_OOM:$modeName; no automatic retry was performed"
        }
        $attemptRecord.status = "completed"
        $attemptRecord.outcome = "FAIL"
        $attemptRecord.failure_reason = "BRIDGE_EXIT_$($bridgeProcess.ExitCode):$combinedFailure"
        $attemptRecord.completed_at_utc = [DateTime]::UtcNow.ToString("o")
        Save-Attempts -Attempts @($allAttempts)
        throw "SMOKE_BRIDGE_FAILED:$($bridgeProcess.ExitCode)"
    }
    try {
        $bridgeResult = $bridgeStdout | ConvertFrom-Json
    }
    catch {
        throw "SMOKE_BRIDGE_STDOUT_INVALID_JSON"
    }
    if ([string]$bridgeResult.status -ne "success") {
        throw "SMOKE_BRIDGE_DID_NOT_REPORT_SUCCESS"
    }
    $outputDirectory = [System.IO.Path]::GetFullPath([string]$bridgeResult.output_directory)
    $manifestPath = Join-Path $outputDirectory "manifest.json"
    $rawPath = Join-Path $outputDirectory "raw.png"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
        throw "SMOKE_DELIVERY_MISSING"
    }
    $generationManifest = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([string]$generationManifest.status -ne "raw_success" -or
        [string]$generationManifest.positive_prompt -cne $SmokePrompt -or
        [int]$generationManifest.seed -ne $SmokeSeed -or
        [string]$generationManifest.run_id -ne "seed_$($SmokeSeed)_$modeName" -or
        [int]$generationManifest.width -ne 512 -or [int]$generationManifest.height -ne 512 -or
        [int]$generationManifest.batch_size -ne 1 -or [int]$generationManifest.steps -ne 4 -or
        [int]$generationManifest.retry_count -ne 0 -or
        @($generationManifest.raw_dimensions) -join "x" -ne "512x512") {
        throw "SMOKE_GENERATION_MANIFEST_INVALID"
    }

    $attemptRecord.status = "completed"
    $attemptRecord.outcome = "PASS"
    $attemptRecord.failure_reason = ""
    $attemptRecord.output_directory = $outputDirectory
    $attemptRecord.raw_png = $rawPath
    $attemptRecord.raw_png_bytes = (Get-Item -LiteralPath $rawPath).Length
    $attemptRecord.raw_png_sha256 = (Get-FileHash -LiteralPath $rawPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $attemptRecord.output_size = @($generationManifest.raw_dimensions)
    $attemptRecord.workflow_hash = [string]$generationManifest.workflow_sha256
    $attemptRecord.generation_seconds = [double]$generationManifest.generation_seconds
    $attemptRecord.total_wall_seconds = [double]$generationManifest.total_wall_seconds
    $attemptRecord.peak_vram_mb = [double]$generationManifest.peak_vram_mb
    $attemptRecord.peak_ram_mb = [double]$generationManifest.peak_ram_mb
    $attemptRecord.completed_at_utc = [DateTime]::UtcNow.ToString("o")
    Save-Attempts -Attempts @($allAttempts)
    Write-JsonAtomic -Path $SmokeLastPath -Value $attemptRecord
}
catch {
    $primaryError = $_
    if ($null -ne $attemptRecord -and [string]$attemptRecord.outcome -eq "UNFINISHED") {
        $attemptRecord.status = "completed"
        $attemptRecord.outcome = if (Test-CudaOomText -Text $_.Exception.Message) { "CUDA_OOM" } else { "FAIL" }
        $attemptRecord.failure_reason = $_.Exception.Message
        $attemptRecord.completed_at_utc = [DateTime]::UtcNow.ToString("o")
        Save-Attempts -Attempts @($allAttempts)
        Write-JsonAtomic -Path $SmokeLastPath -Value $attemptRecord
    }
}
finally {
    $wallClock.Stop()
    Publish-PartialLog -PartialPath $bridgeStdoutPartial -FinalPath $bridgeStdoutFinal
    Publish-PartialLog -PartialPath $bridgeStderrPartial -FinalPath $bridgeStderrFinal
    if ($runtimeStarted) {
        try {
            [void](& $StopScript | Out-String)
        }
        catch {
            $stopError = $_
        }
    }
}

if ($null -ne $primaryError) {
    if ($null -ne $stopError) {
        throw "SMOKE_FAILED:$($primaryError.Exception.Message); STOP_FAILED:$($stopError.Exception.Message)"
    }
    throw $primaryError
}
if ($null -ne $stopError) {
    throw "SMOKE_STOP_FAILED:$($stopError.Exception.Message)"
}

[ordered]@{
    status = "PASS"
    mode = $modeName
    attempt_id = $runToken
    seed = $SmokeSeed
    retry_count = 0
    automatic_retry_count = 0
    output_directory = [string]$attemptRecord.output_directory
    raw_png = [string]$attemptRecord.raw_png
    generation_seconds = [double]$attemptRecord.generation_seconds
    total_wall_seconds = [double]$attemptRecord.total_wall_seconds
    orchestration_wall_seconds = [Math]::Round($wallClock.Elapsed.TotalSeconds, 3)
    peak_vram_mb = [double]$attemptRecord.peak_vram_mb
    peak_ram_mb = [double]$attemptRecord.peak_ram_mb
    port_8190_closed_after = $true
    port_8188_closed = $true
} | ConvertTo-Json -Depth 10
