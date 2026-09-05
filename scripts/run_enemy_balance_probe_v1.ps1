[CmdletBinding()]
param(
    [string]$Seeds = "7,14,29",
    [ValidateRange(30, 900)]
    [int]$Seconds = 900,
    [switch]$SkipRender
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$godot = & (Join-Path $PSScriptRoot "find_godot.ps1")
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$evidenceRoot = Join-Path $repoRoot ".tools\enemy-balance-probe\$stamp"
New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null

$savedKeys = @{}
foreach ($name in @("ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY", "OPENAI_API_KEY", "FORGE_WEAPON_LIBRARY_ROOT")) {
    $savedKeys[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
    [Environment]::SetEnvironmentVariable($name, $null, "Process")
}

try {
    $botRoot = Join-Path $evidenceRoot "multi-seed-normal-input-bot"
    New-Item -ItemType Directory -Force -Path $botRoot | Out-Null
    $botOut = Join-Path $botRoot "stdout.log"
    $botErr = Join-Path $botRoot "stderr.log"
    $bot = Start-Process -FilePath $godot -ArgumentList @(
        "--headless", "--path", ('"' + $repoRoot + '"'),
        "--script", "res://tests/enemy_balance_probe_v1.gd", "--",
        ('--output="' + $botRoot + '"'), ("--seconds=" + $Seconds), ("--seeds=" + $Seeds)
    ) -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput $botOut -RedirectStandardError $botErr
    $bot.WaitForExit()
    if ($bot.ExitCode -ne 0) { throw "Enemy balance normal-input probe failed with exit code $($bot.ExitCode). See $botErr" }

    if (-not $SkipRender) {
        $renderRoot = Join-Path $evidenceRoot "real-gpu"
        New-Item -ItemType Directory -Force -Path $renderRoot | Out-Null
        $renderOut = Join-Path $renderRoot "stdout.log"
        $renderErr = Join-Path $renderRoot "stderr.log"
        $render = Start-Process -FilePath $godot -ArgumentList @(
            "--path", ('"' + $repoRoot + '"'),
            "--script", "res://tests/enemy_balance_probe_v1.gd", "--",
            ('--output="' + $renderRoot + '"'), "--seconds=24", "--seed=14", "--render"
        ) -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
          -RedirectStandardOutput $renderOut -RedirectStandardError $renderErr
        $render.WaitForExit()
        if ($render.ExitCode -ne 0) { throw "Enemy balance real-render probe failed with exit code $($render.ExitCode). See $renderErr" }
    }

    Write-Output "ENEMY_BALANCE_PROBE_EVIDENCE $evidenceRoot"
}
finally {
    foreach ($name in $savedKeys.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedKeys[$name], "Process")
    }
}
