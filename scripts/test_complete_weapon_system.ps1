[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$GodotPath = & (Join-Path $PSScriptRoot "find_godot.ps1")
$RunRoot = Join-Path $ProjectRoot (".tools/system-tests/" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
$EnvironmentNames = @("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "FORGE_SEMANTIC_MODEL", "FAL_KEY", "FAL_API_KEY", "FORGE_WEAPON_LIBRARY_ROOT")
$PreviousEnvironment = @{}
foreach ($Name in $EnvironmentNames) {
    $PreviousEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    [Environment]::SetEnvironmentVariable($Name, $null, "Process")
}
$Results = @()
$OverallExit = 0
try {
    $Suites = @(
        "test_unified_weapon_library", "test_general_object_ai_parser", "test_general_weapon_generation_service", "test_stockless_support",
        "test_automatic_level_loop", "test_open_identity_provider",
        "test_three_battle_strategy_playtest", "test_enemy_attack_mechanisms_v1",
        "test_weapon_target_interactions", "test_firearm_v5_runtime", "test_arena_mechanism_axes",
		"test_training_melee_compatibility", "test_soft_structure_readability",
        "test_art_vertical_slice_v1", "test_church_presentation", "test_church_pixel_style",
        "test_church_style_providers", "test_church_forge", "test_side_loop_grip", "test_church_expedition",
        "test_authored_player", "test_sunny_expedition", "test_sunny_enemy_visual_contract", "test_motion_grammar_slice_1a"
    )
    foreach ($Suite in $Suites) {
        $env:FORGE_WEAPON_LIBRARY_ROOT = Join-Path $RunRoot "$Suite-library"
        $StdoutPath = Join-Path $RunRoot "$Suite.stdout.log"
        $StderrPath = Join-Path $RunRoot "$Suite.stderr.log"
        $EngineLog = Join-Path $RunRoot "$Suite.engine.log"
        $Timer = [Diagnostics.Stopwatch]::StartNew()
        $Process = Start-Process -FilePath $GodotPath -ArgumentList @(
            "--headless", "--path", ('"' + $ProjectRoot + '"'),
            "--log-file", ('"' + $EngineLog + '"'), "--script", "res://tests/$Suite.gd"
        ) -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru `
          -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
        $ProcessHandle = $Process.Handle
        $TimedOut = $false
        while (-not $Process.WaitForExit(1000)) {
            if ($Timer.Elapsed.TotalSeconds -gt 180) {
                # Only the exact headless child started by this test runner.
                $Process.Kill()
                $TimedOut = $true
                break
            }
        }
        $Process.WaitForExit()
        $Timer.Stop()
        $Output = Get-Content -LiteralPath $StdoutPath -Raw
        $Errors = Get-Content -LiteralPath $StderrPath -Raw
        $Summary = @($Output -split "`r?`n" | Where-Object { $_ -match "passed=\d+.*failed=\d+|\d+ passed, \d+ failed" })
        # Godot can emit a platform certificate-store warning even for offline
        # runs. No test in this runner is allowed to use a paid provider.
        $UnexpectedErrors = @($Errors -split "`r?`n" | Where-Object {
            $_ -match "^(SCRIPT ERROR:|ERROR:|FAIL \|)" -and $_ -notmatch "Failed to read the root certificate store"
        })
        $ReportedFailures = @($Summary | Where-Object { $_ -match "failed=[1-9][0-9]*|(?:^|,\s*)[1-9][0-9]* failed(?:\s|$)" })
        $Ok = -not $TimedOut -and $Process.ExitCode -eq 0 -and $Summary.Count -gt 0 -and $ReportedFailures.Count -eq 0 -and $UnexpectedErrors.Count -eq 0
        if (-not $Ok) { $OverallExit = 1 }
        $Results += [ordered]@{ suite = $Suite; ok = $Ok; exit_code = $Process.ExitCode; seconds = [math]::Round($Timer.Elapsed.TotalSeconds, 2); summary = $Summary; errors = $UnexpectedErrors }
        Write-Output ("{0}: {1} ({2:N1}s) {3}" -f $Suite, $(if ($Ok) { "PASS" } else { "FAIL" }), $Timer.Elapsed.TotalSeconds, ($Summary -join " / "))
    }
    Push-Location $ProjectRoot
    try {
        & python -B -m unittest discover -s tools/semantic/tests -p test_automatic_armory_candidate_bridge.py -v
        if ($LASTEXITCODE -ne 0) { $OverallExit = 1 }
        $Results += [ordered]@{ suite = "automatic_armory_candidate_bridge"; ok = ($LASTEXITCODE -eq 0); exit_code = $LASTEXITCODE }
        foreach ($SemanticSuite in @("test_firearm_identity_ai_bridge", "test_general_object_ai_bridge", "test_generalization_v3_matrix")) {
            & python -B -m unittest discover -s tools/semantic/tests -p "$SemanticSuite.py" -v
            if ($LASTEXITCODE -ne 0) { $OverallExit = 1 }
            $Results += [ordered]@{ suite = $SemanticSuite; ok = ($LASTEXITCODE -eq 0); exit_code = $LASTEXITCODE }
        }
        foreach ($VisualSuite in @("test_church_style_contract", "test_fal_general_object_pixel_bridge", "test_fal_firearm_pixel_bridge")) {
            & python -B -m unittest discover -s tools/visual/tests -p "$VisualSuite.py" -v
            if ($LASTEXITCODE -ne 0) { $OverallExit = 1 }
            $Results += [ordered]@{ suite = $VisualSuite; ok = ($LASTEXITCODE -eq 0); exit_code = $LASTEXITCODE }
        }
    }
    finally { Pop-Location }
    $Results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $RunRoot "summary.json") -Encoding UTF8
    Write-Output "Evidence: $RunRoot"
}
finally {
    foreach ($Name in $EnvironmentNames) {
        [Environment]::SetEnvironmentVariable($Name, $PreviousEnvironment[$Name], "Process")
    }
}
exit $OverallExit
