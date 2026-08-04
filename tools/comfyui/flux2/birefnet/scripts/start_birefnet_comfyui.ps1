[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(30, 300)]
    [int]$StartupTimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ApiBase = "http://127.0.0.1:8190"
$ComfyRoot = "C:\AI\ComfyUI-ForgeFlux2\ComfyUI"
$PythonPath = "C:\AI\ComfyUI-ForgeFlux2\.venv\Scripts\python.exe"
$MainPath = Join-Path $ComfyRoot "main.py"
$ExpectedCommit = "b1693ecba9f5b65f8c80ab36b195ab963ec92413"
$ModelPath = Join-Path $ComfyRoot "models\background_removal\birefnet.safetensors"
$ExpectedModelSha256 = "9ab37426bf4de0567af6b5d21b16151357149139362e6e8992021b8ce356a154"
$ExpectedModelBytes = [int64]444473596
$SpikeRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $SpikeRoot "reports\model_download_manifest.json"
$LogRoot = Join-Path $SpikeRoot "logs"
$StatePath = Join-Path $LogRoot "runtime_state.json"
$RuntimeRoot = "C:\AI\ComfyUI-ForgeFlux2\birefnet-runtime"
$InputDirectory = Join-Path $RuntimeRoot "input"
$OutputDirectory = Join-Path $RuntimeRoot "output"
$TempDirectory = Join-Path $RuntimeRoot "temp"

function Get-Listeners([int]$Port) {
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Write-JsonExclusiveAtomic([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    if (Test-Path -LiteralPath $Path) { throw "REFUSING_TO_OVERWRITE_STATE:$Path" }
    $temporary = Join-Path $parent (".{0}.{1}.partial" -f ([IO.Path]::GetFileName($Path)), [Guid]::NewGuid().ToString("N"))
    try {
        [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path) { throw "REFUSING_TO_OVERWRITE_STATE:$Path" }
        [IO.File]::Move($temporary, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Stop-OwnedProcess([int]$ProcessId, [string]$ExpectedMain) {
    if ($ProcessId -le 0) { return }
    $candidate = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
    if ($null -eq $candidate) { return }
    if ([string]$candidate.CommandLine -notlike "*$ExpectedMain*") {
        throw "REFUSING_TO_STOP_UNVERIFIED_PROCESS:$ProcessId"
    }
    Stop-Process -Id $ProcessId -ErrorAction SilentlyContinue
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        Stop-Process -Id $ProcessId -Force
    }
}

$launcher = $null
$listenerPid = 0
$stdoutPartial = ""
$stderrPartial = ""
try {
    if (Get-Listeners 8188) { throw "PORT_8188_MUST_BE_CLOSED" }
    if (Get-Listeners 8190) { throw "PORT_8190_ALREADY_LISTENING" }
    if (Test-Path -LiteralPath $StatePath) { throw "RUNTIME_STATE_ALREADY_EXISTS" }
    foreach ($required in @($PythonPath, $MainPath, $ManifestPath, $ModelPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "REQUIRED_FILE_MISSING:$required" }
    }
    $commit = ((& git.exe -C $ComfyRoot rev-parse HEAD) | Out-String).Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $commit -ne $ExpectedCommit) { throw "COMFYUI_COMMIT_MISMATCH:$commit" }
    $tracked = ((& git.exe -C $ComfyRoot status --porcelain --untracked-files=no) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $tracked) { throw "COMFYUI_TRACKED_WORKTREE_NOT_CLEAN" }
    $modelItem = Get-Item -LiteralPath $ModelPath
    $modelSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $ModelPath).Hash.ToLowerInvariant()
    if ($modelItem.Length -ne $ExpectedModelBytes -or $modelSha -ne $ExpectedModelSha256) {
        throw "BIREFNET_MODEL_VERIFICATION_FAILED"
    }
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestPath | ConvertFrom-Json
    if ([string]$manifest.status -ne "PASS" -or [string]$manifest.model.sha256 -ne $ExpectedModelSha256) {
        throw "BIREFNET_MODEL_MANIFEST_INVALID"
    }
    $existing = @(Get-CimInstance Win32_Process | Where-Object {
        [string]$_.CommandLine -like "*$MainPath*" -or [string]$_.ExecutablePath -ieq $PythonPath
    })
    if ($existing.Count -ne 0) { throw "ISOLATED_COMFYUI_PROCESS_ALREADY_EXISTS:$($existing[0].ProcessId)" }

    foreach ($directory in @($LogRoot, $InputDirectory, $OutputDirectory, $TempDirectory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $token = "{0}-{1}" -f [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ"), [Guid]::NewGuid().ToString("N")
    $stdoutPartial = Join-Path $LogRoot "comfyui-$token.stdout.partial"
    $stderrPartial = Join-Path $LogRoot "comfyui-$token.stderr.partial"
    $args = @(
        $MainPath,
        "--listen", "127.0.0.1",
        "--port", "8190",
        "--disable-auto-launch",
        "--input-directory", $InputDirectory,
        "--output-directory", $OutputDirectory,
        "--temp-directory", $TempDirectory,
        "--disable-metadata",
        "--preview-method", "none",
        "--disable-all-custom-nodes",
        "--disable-api-nodes"
    )
    $argumentLine = ($args | ForEach-Object {
        if ([string]$_ -match '\s') { '"{0}"' -f ([string]$_) } else { [string]$_ }
    }) -join " "
    $launcher = Start-Process -FilePath $PythonPath -ArgumentList $argumentLine -WorkingDirectory $ComfyRoot `
        -RedirectStandardOutput $stdoutPartial -RedirectStandardError $stderrPartial -WindowStyle Hidden -PassThru

    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    $systemStats = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($launcher.HasExited) { throw "COMFYUI_EXITED_DURING_STARTUP:$($launcher.ExitCode)" }
        if (Get-Listeners 8188) { throw "PORT_8188_BECAME_LISTENING" }
        $listeners = @(Get-Listeners 8190)
        if ($listeners.Count -eq 1 -and [string]$listeners[0].LocalAddress -eq "127.0.0.1") {
            $listenerPid = [int]$listeners[0].OwningProcess
            $listenerProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $listenerPid" -ErrorAction SilentlyContinue
            if ($null -ne $listenerProcess -and [string]$listenerProcess.CommandLine -like "*$MainPath*") {
                try {
                    $systemStats = Invoke-RestMethod -Method Get -Uri "$ApiBase/system_stats" -TimeoutSec 5
                    $loader = Invoke-RestMethod -Method Get -Uri "$ApiBase/object_info/LoadBackgroundRemovalModel" -TimeoutSec 10
                    $remover = Invoke-RestMethod -Method Get -Uri "$ApiBase/object_info/RemoveBackground" -TimeoutSec 10
                    if ($null -ne $loader.LoadBackgroundRemovalModel -and $null -ne $remover.RemoveBackground) { break }
                }
                catch { $systemStats = $null }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $systemStats) { throw "COMFYUI_BIREFNET_STARTUP_TIMEOUT" }

    $state = [ordered]@{
        contract = "forge-birefnet-owned-runtime-v1"
        status = "running"
        api_base = $ApiBase
        listen_address = "127.0.0.1"
        port = 8190
        port_8188_closed = $true
        launcher_pid = [int]$launcher.Id
        listener_pid = $listenerPid
        python_executable = $PythonPath
        main_py = $MainPath
        command_line = [string](Get-CimInstance Win32_Process -Filter "ProcessId = $listenerPid").CommandLine
        comfyui_commit = $commit
        model_path = $ModelPath
        model_sha256 = $modelSha
        input_directory = $InputDirectory
        output_directory = $OutputDirectory
        temp_directory = $TempDirectory
        stdout_partial = $stdoutPartial
        stderr_partial = $stderrPartial
        started_at_utc = [DateTime]::UtcNow.ToString("o")
    }
    Write-JsonExclusiveAtomic -Path $StatePath -Value $state
    [ordered]@{status="PASS"; action="started"; api_base=$ApiBase; launcher_pid=$launcher.Id; listener_pid=$listenerPid; model_sha256=$modelSha} | ConvertTo-Json
}
catch {
    $failure = $_.Exception.Message
    if ($listenerPid -gt 0) { Stop-OwnedProcess -ProcessId $listenerPid -ExpectedMain $MainPath }
    if ($null -ne $launcher -and $launcher.Id -ne $listenerPid) { Stop-OwnedProcess -ProcessId $launcher.Id -ExpectedMain $MainPath }
    throw $failure
}
