[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OpenRoot = Split-Path -Parent $PSScriptRoot
$PlaylabRoot = Split-Path -Parent (Split-Path -Parent $OpenRoot)
$DocumentsRoot = Split-Path -Parent $PlaylabRoot
$LiveRoot = Join-Path $PlaylabRoot "tools\live_e2e"
$PythonPath = "C:\AI\ComfyUI-ForgeFlux2\.venv\Scripts\python.exe"
$GodotPath = Join-Path $DocumentsRoot "project forge\.tools\Godot_v4.7.1-stable_win64.exe"
$GodotConsolePath = Join-Path $DocumentsRoot "project forge\.tools\Godot_v4.7.1-stable_win64_console.exe"
$ExpectedModel = "claude-sonnet-5"
$SessionId = "open-{0}-{1}" -f [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ").ToLowerInvariant(), [Guid]::NewGuid().ToString("N").Substring(0, 8)
$SessionRoot = Join-Path $OpenRoot "runtime\$SessionId"
$SessionOutput = Join-Path $OpenRoot "output\sessions\$SessionId"
$PreflightPath = Join-Path $SessionRoot "preflight.json"
$ConfigPath = Join-Path $OpenRoot "config\open_playtest_config.json"
$BridgeStdout = Join-Path $SessionRoot "bridge.stdout.log"
$BridgeStderr = Join-Path $SessionRoot "bridge.stderr.log"
$GodotStdout = Join-Path $SessionRoot "godot.stdout.log"
$GodotStderr = Join-Path $SessionRoot "godot.stderr.log"
$BridgeProcess = $null
$GodotProcess = $null
$SecureKey = $null
$KeyText = $null
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
            if ($Uri.EndsWith("/system_stats", [StringComparison]::Ordinal) -and $null -ne $result.system) { return $result }
            if ([string]$result.status -eq "ok") { return $result }
        }
        catch { }
        Start-Sleep -Milliseconds 350
    }
    throw "HEALTH_TIMEOUT:$Uri"
}

function Stop-OwnedProcess([System.Diagnostics.Process]$Process) {
    if ($null -eq $Process) { return }
    if (-not (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue)) { return }
    Stop-Process -Id $Process.Id -ErrorAction SilentlyContinue
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ((Get-Process -Id $Process.Id -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
    }
    if (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $Process.Id -Force }
}

try {
    foreach ($path in @($PythonPath, $GodotPath, $GodotConsolePath, $ConfigPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "OPEN_PLAYTEST_REQUIRED_FILE_MISSING:$path" }
    }
    if (@(Get-Listeners 8188).Count -ne 0 -or @(Get-Listeners 8190).Count -ne 0 -or @(Get-Listeners 8771).Count -ne 0) {
        throw "OPEN_PLAYTEST_REQUIRED_PORT_ALREADY_IN_USE"
    }
    New-Item -ItemType Directory -Force -Path $SessionRoot | Out-Null

    $testStdout = Join-Path $SessionRoot "offline_tests.stdout.log"
    $testStderr = Join-Path $SessionRoot "offline_tests.stderr.log"
    $testArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $PSScriptRoot "test_open_playtest.ps1")
    $testProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $testArgs -WindowStyle Hidden `
        -RedirectStandardOutput $testStdout -RedirectStandardError $testStderr -PassThru -Wait
    $testOutput = @(
        if (Test-Path -LiteralPath $testStdout) { [IO.File]::ReadAllText($testStdout, [Text.Encoding]::UTF8) }
        if (Test-Path -LiteralPath $testStderr) { [IO.File]::ReadAllText($testStderr, [Text.Encoding]::UTF8) }
    ) -join ""
    [IO.File]::WriteAllText((Join-Path $SessionRoot "offline_tests.log"), $testOutput, [Text.UTF8Encoding]::new($false))
    Write-Host $testOutput
    if ($testProcess.ExitCode -ne 0) { throw "OPEN_PLAYTEST_OFFLINE_TESTS_FAILED" }

    $env:FORGE_SEMANTIC_MODEL = $ExpectedModel
    if ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
        Write-Host "One key entry opens the whole continuous playtest session; it is not requested again per idea."
        $SecureKey = Read-Host "SECURE INPUT ONLY: paste ANTHROPIC_API_KEY (characters stay hidden)" -AsSecureString
        if ($SecureKey.Length -eq 0) { throw "ANTHROPIC_API_KEY_EMPTY" }
        $Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
        try { $KeyText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr) }
        $env:ANTHROPIC_API_KEY = $KeyText
    }
    else {
        Write-Host "Using ANTHROPIC_API_KEY already present in this process; it will never be printed or persisted."
    }
    Write-Host "Approved semantic model fixed by contract: $ExpectedModel"

    $preflightArgs = @(
        (Join-Path $LiveRoot "bridge\live_preflight.py"),
        "--playlab", $PlaylabRoot,
        "--formal-repo", (Join-Path $DocumentsRoot "project forge"),
        "--output", $PreflightPath
    )
    $formalClaude = Join-Path $DocumentsRoot "project-forge-claude"
    if (Test-Path -LiteralPath $formalClaude -PathType Container) { $preflightArgs += @("--formal-repo", $formalClaude) }
    & $PythonPath @preflightArgs
    if ($LASTEXITCODE -ne 0) { throw "OPEN_PLAYTEST_PREFLIGHT_FAILED" }

    & (Join-Path $LiveRoot "scripts\start_live_comfyui.ps1") -SessionId $SessionId | Out-Host
    $ComfyStarted = $true
    Wait-Health -Uri "http://127.0.0.1:8190/system_stats" -Seconds 30 | Out-Null

    $bridgeArguments = @(
        (Join-Path $OpenRoot "bridge\open_playtest_server.py"),
        "--forge-open-playtest",
        "--session-id", $SessionId,
        "--preflight-file", $PreflightPath,
        "--config-file", $ConfigPath,
        "--port", "8771"
    )
    $BridgeProcess = Start-Process -FilePath $PythonPath -ArgumentList (($bridgeArguments | ForEach-Object {
        if ([string]$_ -match '\s') { '"{0}"' -f [string]$_ } else { [string]$_ }
    }) -join " ") -WorkingDirectory (Join-Path $OpenRoot "bridge") -WindowStyle Hidden `
        -RedirectStandardOutput $BridgeStdout -RedirectStandardError $BridgeStderr -PassThru
    Wait-Health -Uri "http://127.0.0.1:8771/health" -Seconds 20 | Out-Null

    $godotArguments = @(
        "--path", $PlaylabRoot,
        "res://tools/open_playtest/godot/open_playtest.tscn",
        "--",
        "--forge-open-playtest",
        "--open-bridge=http://127.0.0.1:8771",
        "--open-session=$SessionId"
    )
    $GodotProcess = Start-Process -FilePath $GodotPath -ArgumentList (($godotArguments | ForEach-Object {
        if ([string]$_ -match '\s') { '"{0}"' -f [string]$_ } else { [string]$_ }
    }) -join " ") -WorkingDirectory $PlaylabRoot -RedirectStandardOutput $GodotStdout `
        -RedirectStandardError $GodotStderr -PassThru -Wait
    if ($GodotProcess.ExitCode -ne 0) { throw "OPEN_PLAYTEST_GODOT_EXITED:$($GodotProcess.ExitCode)" }
    $ExitCode = 0
}
catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
}
finally {
    if ($null -ne $BridgeProcess -and (Get-Process -Id $BridgeProcess.Id -ErrorAction SilentlyContinue)) {
        try {
            $finalizeBody = @{ session_id = $SessionId } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri "http://127.0.0.1:8771/session/finalize" -Method Post `
                -ContentType "application/json" -Body $finalizeBody -TimeoutSec 10 | Out-Null
        }
        catch { Write-Warning "OPEN_SESSION_FINALIZE_REQUEST_FAILED" }
    }
    Stop-OwnedProcess -Process $BridgeProcess
    if ($ComfyStarted -or (Test-Path -LiteralPath (Join-Path $LiveRoot "runtime\live_comfy_state.json"))) {
        try { & (Join-Path $LiveRoot "scripts\stop_live_comfyui.ps1") | Out-Host }
        catch { Write-Error "COMFY_STOP_FAILED:$($_.Exception.Message)" -ErrorAction Continue; $ExitCode = 1 }
    }
    Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\FORGE_SEMANTIC_MODEL -ErrorAction SilentlyContinue
    $KeyText = $null
    $SecureKey = $null
    [GC]::Collect()
    if (@(Get-Listeners 8188).Count -ne 0 -or @(Get-Listeners 8190).Count -ne 0 -or @(Get-Listeners 8771).Count -ne 0) {
        Write-Error "OPEN_PLAYTEST_PORT_CLEANUP_FAILED" -ErrorAction Continue
        $ExitCode = 1
    }
    if ((Test-Path -LiteralPath $PreflightPath -PathType Leaf) -and (Test-Path -LiteralPath $SessionOutput -PathType Container)) {
        & $PythonPath (Join-Path $OpenRoot "bridge\open_playtest_cleanup.py") `
            --session-id $SessionId --preflight-file $PreflightPath --session-output $SessionOutput
        if ($LASTEXITCODE -ne 0) { Write-Error "OPEN_PLAYTEST_CLEANUP_ATTESTATION_FAILED" -ErrorAction Continue; $ExitCode = 1 }
    }
    Write-Host "Open Playtest session output: $SessionOutput"
    Write-Host "Local history: $(Join-Path $OpenRoot 'local_history\playtest_history.json')"
    Write-Host "Ports 8190/8188/8771 closed: $(@(Get-Listeners 8190).Count -eq 0 -and @(Get-Listeners 8188).Count -eq 0 -and @(Get-Listeners 8771).Count -eq 0)"
}

exit $ExitCode
