$ErrorActionPreference = "Stop"

$runtime = Join-Path (Split-Path -Parent $PSScriptRoot) "runtime"
$pidPath = Join-Path $runtime "comfyui.pid"
if (-not (Test-Path -LiteralPath $pidPath)) {
    Write-Output "No Spike ComfyUI PID file found."
    exit 0
}
$comfyPid = [int](Get-Content -LiteralPath $pidPath)
$process = Get-Process -Id $comfyPid -ErrorAction SilentlyContinue
if ($process) {
    Stop-Process -Id $comfyPid
    Write-Output "Stopped Spike ComfyUI PID $comfyPid"
} else {
    Write-Output "Spike ComfyUI PID $comfyPid was not running."
}
Remove-Item -LiteralPath $pidPath -ErrorAction SilentlyContinue
