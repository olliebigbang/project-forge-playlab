param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"

$comfyRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    # Backwards-compatible Spike 0 default.
    $resolvedConfigPath = Join-Path $comfyRoot "config\forge_comfy_config.local.json"
}
elseif ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
}
else {
    $resolvedConfigPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $ConfigPath))
}
if (-not (Test-Path -LiteralPath $resolvedConfigPath -PathType Leaf)) {
    throw "Missing local config: $resolvedConfigPath. Copy the matching example config and set local paths."
}
$config = [System.IO.File]::ReadAllText($resolvedConfigPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if ($config.api_base -notmatch '^http://127\.0\.0\.1:(\d{1,5})$') {
    throw "api_base must bind to 127.0.0.1"
}
$port = [int]$Matches[1]
if ($port -lt 1 -or $port -gt 65535) {
    throw "api_base port must be between 1 and 65535"
}
if ($config.api_base -ne "http://127.0.0.1:$port") {
    throw "api_base must use the canonical http://127.0.0.1:<port> form"
}
$existing = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
if ($existing) {
    $nonLoopback = @($existing | Where-Object { $_.LocalAddress -ne "127.0.0.1" })
    if ($nonLoopback.Count -gt 0) {
        throw "Port $port already has a non-loopback listener; refusing to claim or reuse it."
    }
    Write-Output "ComfyUI is already listening at $($config.api_base)"
    exit 0
}

function Resolve-ConfigPath([string]$value) {
    if ([System.IO.Path]::IsPathRooted($value)) { return [System.IO.Path]::GetFullPath($value) }
    return [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $resolvedConfigPath) $value))
}

$runtime = Join-Path $comfyRoot "runtime"
$inputDirectory = Resolve-ConfigPath $config.input_directory
$outputDirectory = Resolve-ConfigPath $config.comfy_output_directory
$tempDirectory = Join-Path $runtime "temp"
New-Item -ItemType Directory -Force -Path $runtime, $inputDirectory, $outputDirectory, $tempDirectory | Out-Null
$main = Join-Path $config.comfyui_install "main.py"
$stdout = Join-Path $runtime "comfyui.stdout.log"
$stderr = Join-Path $runtime "comfyui.stderr.log"
$argumentLine = '"{0}" --listen 127.0.0.1 --port {1} --disable-auto-launch --output-directory "{2}" --input-directory "{3}" --temp-directory "{4}" --disable-metadata --preview-method none --disable-all-custom-nodes' -f $main, $port, $outputDirectory, $inputDirectory, $tempDirectory
$process = Start-Process -FilePath $config.python_executable -ArgumentList $argumentLine -WorkingDirectory $config.comfyui_install -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
$process.Id | Out-File -LiteralPath (Join-Path $runtime "comfyui.pid") -Encoding ascii
Write-Output "Started local-only ComfyUI PID $($process.Id) at $($config.api_base)"
