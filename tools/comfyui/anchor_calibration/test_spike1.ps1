$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$godot = & (Join-Path $repoRoot "scripts\find_godot.ps1")
$testEvidence = New-Object System.Collections.Generic.List[string]

function Invoke-GodotChecked {
    param(
        [string[]]$GodotArguments,
        [string]$ExpectedPattern = "",
        [string]$EvidenceName = "Godot"
    )

    $token = [Guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $env:TEMP "forge-spike1-$token.stdout.tmp"
    $stderrPath = Join-Path $env:TEMP "forge-spike1-$token.stderr.tmp"
    $quotedArguments = foreach ($argument in $GodotArguments) {
        if ($argument -match '[\s"]') {
            '"' + $argument.Replace('"', '\"') + '"'
        }
        else {
            $argument
        }
    }

    try {
        $process = Start-Process -FilePath $godot `
            -ArgumentList $quotedArguments `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -NoNewWindow `
            -Wait `
            -PassThru
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -Raw -LiteralPath $stdoutPath } else { "" }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -Raw -LiteralPath $stderrPath } else { "" }
        $combined = "$stdout`n$stderr"
        $ansiPattern = "$([char]27)\[[0-9;]*[A-Za-z]"
        $cleanCombined = $combined -replace $ansiPattern, ""
        $script:testEvidence.Add("=== $EvidenceName ===`n$($cleanCombined.Trim())")
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            Write-Host $stdout.TrimEnd()
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Write-Host $stderr.TrimEnd()
        }
        if ($process.ExitCode -ne 0) {
            throw "Godot exited with code $($process.ExitCode)."
        }
        if ($combined -match 'SCRIPT ERROR|Parse Error|Failed to load script') {
            throw "Godot reported a script or parse error."
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedPattern) -and $combined -notmatch $ExpectedPattern) {
            throw "Godot output did not contain expected success marker: $ExpectedPattern"
        }
    }
    finally {
        [System.IO.File]::Delete([string]$stdoutPath)
        [System.IO.File]::Delete([string]$stderrPath)
    }
}

Invoke-GodotChecked -GodotArguments @("--headless", "--editor", "--path", $repoRoot, "--quit") -EvidenceName "Godot parse/import scan"
Invoke-GodotChecked `
    -GodotArguments @("--headless", "--path", $repoRoot, "--script", (Join-Path $repoRoot "tests\run_tests.gd")) `
    -ExpectedPattern 'RESULT: \d+ passed, 0 failed' `
    -EvidenceName "Playlab and semantic UI tests"
Invoke-GodotChecked `
    -GodotArguments @("--headless", "--path", $repoRoot, "--script", (Join-Path $PSScriptRoot "evaluate_spike1.gd")) `
    -ExpectedPattern 'SPIKE1_RESULT=PASS' `
    -EvidenceName "11-sprite corpus evaluation"

$reportPath = Join-Path $PSScriptRoot "reports\evaluation.json"
$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$evidencePath = Join-Path $PSScriptRoot "reports\test_run.txt"
[System.IO.File]::WriteAllText($evidencePath, (($testEvidence -join "`r`n`r`n") + "`r`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host "Spike 1 verified without starting ComfyUI."
Write-Host "Auto anchors: $($report.auto_adjustable_anchor_accuracy.passed)/$($report.auto_adjustable_anchor_accuracy.total) ($($report.auto_adjustable_anchor_accuracy.percent)%)"
Write-Host "Auto usable: $($report.auto_usable_rate.passed)/$($report.auto_usable_rate.total) ($($report.auto_usable_rate.percent)%)"
Write-Host "Final usable: $($report.final_usable_after_calibration_rate.passed)/$($report.final_usable_after_calibration_rate.total) ($($report.final_usable_after_calibration_rate.percent)%)"
