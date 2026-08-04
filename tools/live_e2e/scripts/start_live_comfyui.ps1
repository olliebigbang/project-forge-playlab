[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9-]{8,80}$')]
    [string]$SessionId,

    [Parameter(Mandatory = $false)]
    [ValidateRange(30, 600)]
    [int]$StartupTimeoutSeconds = 240
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$LiveRoot = Split-Path -Parent $PSScriptRoot
$RuntimeRoot = Join-Path $LiveRoot "runtime"
$SessionRoot = Join-Path $RuntimeRoot $SessionId
$StatePath = Join-Path $RuntimeRoot "live_comfy_state.json"
$ComfyRoot = "C:\AI\ComfyUI-ForgeFlux2\ComfyUI"
$PythonPath = "C:\AI\ComfyUI-ForgeFlux2\.venv\Scripts\python.exe"
$MainPath = Join-Path $ComfyRoot "main.py"
$ExpectedCommit = "b1693ecba9f5b65f8c80ab36b195ab963ec92413"
$ExpectedModels = [ordered]@{
    "C:\AI\ComfyUI-ForgeFlux2\ComfyUI\models\diffusion_models\flux-2-klein-4b-fp8.safetensors" = "97ed34fe0567e436200f2faee3939b88f2b5d99f8af2a4dc16532c4245c0ccb6"
    "C:\AI\ComfyUI-ForgeFlux2\ComfyUI\models\text_encoders\qwen_3_4b.safetensors" = "6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a"
    "C:\AI\ComfyUI-ForgeFlux2\ComfyUI\models\vae\flux2-vae.safetensors" = "d64f3a68e1cc4f9f4e29b6e0da38a0204fe9a49f2d4053f0ec1fa1ca02f9c4b5"
    "C:\AI\ComfyUI-ForgeFlux2\ComfyUI\models\background_removal\birefnet.safetensors" = "9ab37426bf4de0567af6b5d21b16151357149139362e6e8992021b8ce356a154"
}
function Get-Listeners([int]$Port) {
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Write-JsonAtomic([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temporary = Join-Path $parent (".{0}.{1}.tmp" -f ([IO.Path]::GetFileName($Path)), [Guid]::NewGuid().ToString("N"))
    [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
    if ([IO.File]::Exists($Path)) {
        [IO.File]::Delete($temporary)
        throw "REFUSING_TO_OVERWRITE_LIVE_COMFY_STATE"
    }
    [IO.File]::Move($temporary, $Path)
}

function Stop-Owned([int]$ProcessId) {
    if ($ProcessId -le 0) { return }
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) { return }
    Stop-Process -Id $ProcessId -ErrorAction SilentlyContinue
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        Stop-Process -Id $ProcessId -Force
    }
}

$started = $null
$listenerPid = 0
try {
    if (Test-Path -LiteralPath $StatePath) { throw "LIVE_COMFY_STATE_ALREADY_EXISTS" }
    if (@(Get-Listeners 8188).Count -ne 0) { throw "PORT_8188_MUST_BE_CLOSED" }
    if (@(Get-Listeners 8190).Count -ne 0) { throw "PORT_8190_ALREADY_IN_USE" }
    foreach ($path in @($ComfyRoot, $PythonPath, $MainPath)) {
        if (-not (Test-Path -LiteralPath $path)) { throw "LIVE_COMFY_REQUIRED_PATH_MISSING:$path" }
    }
    $commit = ((& git -C $ComfyRoot rev-parse HEAD) | Out-String).Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $commit -ne $ExpectedCommit) { throw "COMFYUI_COMMIT_MISMATCH:$commit" }
    foreach ($entry in $ExpectedModels.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) { throw "MODEL_MISSING:$($entry.Key)" }
        $actual = (Get-FileHash -LiteralPath $entry.Key -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne [string]$entry.Value) { throw "MODEL_SHA256_MISMATCH:$([IO.Path]::GetFileName($entry.Key))" }
    }
    $inputDirectory = Join-Path $SessionRoot "comfy_input"
    $outputDirectory = Join-Path $SessionRoot "comfy_output"
    $tempDirectory = Join-Path $SessionRoot "comfy_temp"
    $logDirectory = Join-Path $SessionRoot "logs"
    foreach ($directory in @($inputDirectory, $outputDirectory, $tempDirectory, $logDirectory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $stdout = Join-Path $logDirectory "comfy.stdout.log"
    $stderr = Join-Path $logDirectory "comfy.stderr.log"
    $arguments = @(
        $MainPath, "--listen", "127.0.0.1", "--port", "8190", "--disable-auto-launch",
        "--output-directory", $outputDirectory, "--input-directory", $inputDirectory,
        "--temp-directory", $tempDirectory, "--disable-metadata", "--preview-method", "none",
        "--disable-all-custom-nodes", "--disable-api-nodes"
    )
    $argumentLine = ($arguments | ForEach-Object {
        $value = [string]$_
        if ($value.Contains('"')) { throw "UNSAFE_LIVE_COMFY_ARGUMENT" }
        if ($value -match '\s') { '"{0}"' -f $value } else { $value }
    }) -join " "
    $started = Start-Process -FilePath $PythonPath -ArgumentList $argumentLine -WorkingDirectory $ComfyRoot `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
    $healthy = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        $started.Refresh()
        if ($started.HasExited) { throw "COMFYUI_EXITED_DURING_STARTUP:$($started.ExitCode)" }
        if (@(Get-Listeners 8188).Count -ne 0) { throw "PORT_8188_BECAME_ACTIVE" }
        $listeners = @(Get-Listeners 8190)
        if ($listeners.Count -eq 1 -and [string]$listeners[0].LocalAddress -eq "127.0.0.1") {
            $listenerPid = [int]$listeners[0].OwningProcess
            $listener = Get-CimInstance Win32_Process -Filter "ProcessId = $listenerPid" -ErrorAction SilentlyContinue
            if ($null -ne $listener -and [string]$listener.CommandLine -match '--port\s+8190' -and
                [string]$listener.CommandLine -match '--listen\s+127\.0\.0\.1') {
                try {
                    $stats = Invoke-RestMethod -Uri "http://127.0.0.1:8190/system_stats" -Method Get -TimeoutSec 5
                    if ($null -ne $stats.system) { $healthy = $true; break }
                } catch { }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $healthy) { throw "LIVE_COMFY_STARTUP_TIMEOUT" }
    $launcherCim = Get-CimInstance Win32_Process -Filter "ProcessId = $($started.Id)" -ErrorAction Stop
    $listenerCim = Get-CimInstance Win32_Process -Filter "ProcessId = $listenerPid" -ErrorAction Stop
    $state = [ordered]@{
        contract = "forge-live-e2e-owned-comfy-v1"
        session_id = $SessionId
        status = "running"
        launcher_pid = [int]$started.Id
        launcher_creation_utc = ([DateTime]$launcherCim.CreationDate).ToUniversalTime().ToString("o")
        listener_pid = $listenerPid
        listener_creation_utc = ([DateTime]$listenerCim.CreationDate).ToUniversalTime().ToString("o")
        listener_command_line = [string]$listenerCim.CommandLine
        python_executable = $PythonPath
        main_py = $MainPath
        api_base = "http://127.0.0.1:8190"
        input_directory = $inputDirectory
        output_directory = $outputDirectory
        temp_directory = $tempDirectory
        stdout_log = $stdout
        stderr_log = $stderr
        comfyui_commit = $commit
        started_at_utc = [DateTime]::UtcNow.ToString("o")
    }
    Write-JsonAtomic -Path $StatePath -Value $state
    $state | ConvertTo-Json -Depth 12
}
catch {
    Stop-Owned -ProcessId $listenerPid
    if ($null -ne $started) { Stop-Owned -ProcessId ([int]$started.Id) }
    throw
}
