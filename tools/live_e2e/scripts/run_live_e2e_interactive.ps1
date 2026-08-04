[CmdletBinding()]
param(
    [string]$ResumeFromSessionId = "",
    [string]$ResumeRunId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$LiveRoot = Split-Path -Parent $PSScriptRoot
$PlaylabRoot = Split-Path -Parent (Split-Path -Parent $LiveRoot)
$DocumentsRoot = Split-Path -Parent $PlaylabRoot
$PythonPath = "C:\AI\ComfyUI-ForgeFlux2\.venv\Scripts\python.exe"
$GodotPath = Join-Path $DocumentsRoot "project forge\.tools\Godot_v4.7.1-stable_win64.exe"
$GodotConsolePath = Join-Path $DocumentsRoot "project forge\.tools\Godot_v4.7.1-stable_win64_console.exe"
$ExpectedModel = "claude-sonnet-5"
$IsRecovery = -not [string]::IsNullOrWhiteSpace($ResumeFromSessionId) -or -not [string]::IsNullOrWhiteSpace($ResumeRunId)
if ($IsRecovery -and ([string]::IsNullOrWhiteSpace($ResumeFromSessionId) -or [string]::IsNullOrWhiteSpace($ResumeRunId))) {
    throw "LIVE_E2E_RECOVERY_REQUIRES_SOURCE_SESSION_AND_RUN"
}
$SessionId = "live-e2e-{0}-{1}" -f [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ").ToLowerInvariant(), [Guid]::NewGuid().ToString("N").Substring(0, 8)
$RunId = if ($IsRecovery) { $ResumeRunId } else { "spike7-{0}-{1}" -f [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ").ToLowerInvariant(), [Guid]::NewGuid().ToString("N").Substring(0, 8) }
$SessionRoot = Join-Path $LiveRoot "runtime\$SessionId"
$PreflightPath = Join-Path $SessionRoot "preflight.json"
$BridgeStdout = Join-Path $SessionRoot "bridge.stdout.log"
$BridgeStderr = Join-Path $SessionRoot "bridge.stderr.log"
$GodotStdout = Join-Path $SessionRoot "godot.stdout.log"
$GodotStderr = Join-Path $SessionRoot "godot.stderr.log"
$ReportPath = Join-Path $LiveRoot "reports\$RunId\LIVE_E2E_REPORT.md"
$BridgeProcess = $null
$GodotProcess = $null
$KeyText = $null
$SecureKey = $null
$ComfyStarted = $false
$ExitCode = 1

function Get-Listeners([int]$Port) {
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Wait-Health([string]$Uri, [int]$Seconds) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $result = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 3
            if ($Uri.EndsWith("/system_stats", [System.StringComparison]::Ordinal) -and $null -ne $result.system) {
                return $result
            }
            if ([string]$result.status -in @("ok", "LISTENING")) { return $result }
        }
        catch { }
        Start-Sleep -Milliseconds 350
    }
    throw "HEALTH_TIMEOUT:$Uri"
}

function Stop-OwnedProcess([System.Diagnostics.Process]$Process) {
    if ($null -eq $Process) { return }
    $current = Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
    if ($null -eq $current) { return }
    Stop-Process -Id $Process.Id -ErrorAction SilentlyContinue
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ((Get-Process -Id $Process.Id -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
    }
    if (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue) {
        Stop-Process -Id $Process.Id -Force
    }
}

try {
    if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw "LIVE_PYTHON_MISSING:$PythonPath" }
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "GODOT_4_7_1_MISSING:$GodotPath" }
    if (-not (Test-Path -LiteralPath $GodotConsolePath -PathType Leaf)) { throw "GODOT_4_7_1_CONSOLE_MISSING:$GodotConsolePath" }
    if (@(Get-Listeners 8188).Count -ne 0 -or @(Get-Listeners 8190).Count -ne 0 -or @(Get-Listeners 8767).Count -ne 0) {
        throw "LIVE_E2E_REQUIRED_PORT_ALREADY_IN_USE"
    }
    New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null
    $offlineStdout = Join-Path $SessionRoot "offline_tests.stdout.log"
    $offlineStderr = Join-Path $SessionRoot "offline_tests.stderr.log"
    $offlineCombined = Join-Path $SessionRoot "offline_tests.log"
    $testArgumentLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $PSScriptRoot "test_live_e2e.ps1")
    $testProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $testArgumentLine -WindowStyle Hidden `
        -RedirectStandardOutput $offlineStdout -RedirectStandardError $offlineStderr -PassThru -Wait
    $testOutput = @(
        if (Test-Path -LiteralPath $offlineStdout) { [IO.File]::ReadAllText($offlineStdout, [Text.Encoding]::UTF8) }
        if (Test-Path -LiteralPath $offlineStderr) { [IO.File]::ReadAllText($offlineStderr, [Text.Encoding]::UTF8) }
    ) -join ""
    [IO.File]::WriteAllText($offlineCombined, $testOutput, [Text.UTF8Encoding]::new($false))
    Write-Host $testOutput
    if ($testProcess.ExitCode -ne 0) { throw "LIVE_E2E_OFFLINE_TESTS_FAILED:$($testProcess.ExitCode)" }
    & $GodotConsolePath --headless --path $PlaylabRoot --script "res://tools/live_e2e/godot/live_e2e.gd" --check-only
    if ($LASTEXITCODE -ne 0) { throw "LIVE_E2E_GODOT_PARSE_FAILED" }
    # The model is already explicitly approved by the user and is not entered
    # interactively.  Keeping the only prompt secret prevents a credential from
    # being exposed if it is pasted immediately when the window becomes ready.
    $ModelId = $ExpectedModel
    Write-Host "Approved model fixed by contract: $ExpectedModel"
    $SecureKey = Read-Host "SECURE INPUT ONLY: paste the NEW ANTHROPIC_API_KEY (characters stay hidden)" -AsSecureString
    if ($SecureKey.Length -eq 0) { throw "ANTHROPIC_API_KEY_EMPTY" }
    $Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
    try {
        $KeyText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
    }
    $env:ANTHROPIC_API_KEY = $KeyText
    $env:FORGE_SEMANTIC_MODEL = $ModelId

    $preflightArgs = @(
        (Join-Path $LiveRoot "bridge\live_preflight.py"),
        "--playlab", $PlaylabRoot,
        "--formal-repo", (Join-Path $DocumentsRoot "project forge"),
        "--output", $PreflightPath
    )
    $formalClaude = Join-Path $DocumentsRoot "project-forge-claude"
    if (Test-Path -LiteralPath $formalClaude -PathType Container) {
        $preflightArgs += @("--formal-repo", $formalClaude)
    }
    & $PythonPath @preflightArgs
    if ($LASTEXITCODE -ne 0) { throw "LIVE_E2E_PREFLIGHT_FAILED" }

    & (Join-Path $PSScriptRoot "start_live_comfyui.ps1") -SessionId $SessionId | Out-Host
    $ComfyStarted = $true
    Wait-Health -Uri "http://127.0.0.1:8190/system_stats" -Seconds 30 | Out-Null

    $bridgeArgs = @(
        (Join-Path $LiveRoot "bridge\live_server.py"),
        "--forge-live-e2e-spike7",
        "--session-id", $SessionId,
        "--run-id", $RunId,
        "--preflight-file", $PreflightPath,
        "--port", "8767"
    )
    if ($IsRecovery) {
        $bridgeArgs += @("--resume-from-session-id", $ResumeFromSessionId)
        Write-Host "RECOVERY_MODE: reusing frozen L01 technical evidence; remaining model-call limit=2"
    }
    $BridgeProcess = Start-Process -FilePath $PythonPath -ArgumentList (($bridgeArgs | ForEach-Object {
        if ([string]$_ -match '\s') { '"{0}"' -f [string]$_ } else { [string]$_ }
    }) -join " ") -WorkingDirectory (Join-Path $LiveRoot "bridge") -RedirectStandardOutput $BridgeStdout `
        -RedirectStandardError $BridgeStderr -WindowStyle Hidden -PassThru
    Wait-Health -Uri "http://127.0.0.1:8767/health" -Seconds 20 | Out-Null

    $godotArgs = @(
        "--path", $PlaylabRoot,
        "res://tools/live_e2e/godot/live_e2e.tscn",
        "--",
        "--forge-live-e2e-spike7",
        "--live-bridge=http://127.0.0.1:8767",
        "--live-session=$SessionId",
        "--live-run=$RunId"
    )
    $GodotProcess = Start-Process -FilePath $GodotPath -ArgumentList (($godotArgs | ForEach-Object {
        if ([string]$_ -match '\s') { '"{0}"' -f [string]$_ } else { [string]$_ }
    }) -join " ") -WorkingDirectory $PlaylabRoot -RedirectStandardOutput $GodotStdout `
        -RedirectStandardError $GodotStderr -PassThru -Wait
    if ($GodotProcess.ExitCode -ne 0) { throw "GODOT_LIVE_E2E_EXITED:$($GodotProcess.ExitCode)" }
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "LIVE_E2E_REPORT_NOT_DELIVERED" }
    $ExitCode = 0
}
catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
}
finally {
    Stop-OwnedProcess -Process $BridgeProcess
    if ($ComfyStarted -or (Test-Path -LiteralPath (Join-Path $LiveRoot "runtime\live_comfy_state.json"))) {
        try { & (Join-Path $PSScriptRoot "stop_live_comfyui.ps1") | Out-Host }
        catch { Write-Error "COMFY_STOP_FAILED:$($_.Exception.Message)" -ErrorAction Continue; $ExitCode = 1 }
    }
    Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue
    $KeyText = $null
    $SecureKey = $null
    [GC]::Collect()
    if (@(Get-Listeners 8190).Count -ne 0 -or @(Get-Listeners 8188).Count -ne 0 -or @(Get-Listeners 8767).Count -ne 0) {
        Write-Error "LIVE_E2E_PORT_CLEANUP_FAILED" -ErrorAction Continue
        $ExitCode = 1
    }
    $residual = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        [string]$_.CommandLine -like "*$SessionId*" -and ([string]$_.CommandLine -like "*main.py*" -or [string]$_.CommandLine -like "*live_server.py*")
    })
    if ($residual.Count -ne 0) {
        Write-Error "LIVE_E2E_OWNED_PROCESS_REMAINS:$($residual.ProcessId -join ',')" -ErrorAction Continue
        $ExitCode = 1
    }
    if (Test-Path -LiteralPath $ReportPath -PathType Leaf) {
        & $PythonPath (Join-Path $LiveRoot "bridge\finalize_cleanup.py") --run-id $RunId --session-id $SessionId --preflight-file $PreflightPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "LIVE_E2E_FINAL_CLEANUP_ATTESTATION_FAILED" -ErrorAction Continue
            $ExitCode = 1
        }
    }
    Write-Host "Live E2E report path: $ReportPath"
    Write-Host "Ports 8190/8188/8767 closed: $(@(Get-Listeners 8190).Count -eq 0 -and @(Get-Listeners 8188).Count -eq 0 -and @(Get-Listeners 8767).Count -eq 0)"
}

exit $ExitCode
