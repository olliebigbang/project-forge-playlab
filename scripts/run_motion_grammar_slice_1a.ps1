param(
    [ValidateSet("", "Pan", "Broom", "Shotgun", "ShotgunMelee")]
    [string]$Asset = "",
    [switch]$BlindComparison
)

$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")

$AssetMap = @{
    Pan = "frying_pan"
    Broom = "old_mop"
    ShotgunMelee = "shotgun_melee"
}

function Invoke-MotionGrammarRun {
    param(
        [Parameter(Mandatory = $true)] [string]$MotionGrammarAsset,
        [string]$BlindLabel = "",
        [string]$BlindResultPath = ""
    )

    $GodotArguments = @(
        "--path", $PlaylabRoot,
        "res://scenes/combat_feel_slice_0.tscn",
        "--",
        "--mode=combat-feel-slice-0",
        "--motion-grammar-asset=$MotionGrammarAsset"
    )
    if (-not [string]::IsNullOrWhiteSpace($BlindLabel)) {
        $GodotArguments += "--blind-comparison=true"
        $GodotArguments += "--blind-label=$BlindLabel"
        $GodotArguments += "--blind-result-path=$BlindResultPath"
    }

    & $Godot @GodotArguments | Out-Host
    $NativeExitCode = $LASTEXITCODE
    return $NativeExitCode
}

function Read-BlindLabel {
    param([Parameter(Mandatory = $true)] [string]$Question)
    while ($true) {
        $Answer = (Read-Host "$Question (A/B/C)").Trim().ToUpperInvariant()
        if ($Answer -in @("A", "B", "C")) {
            return $Answer
        }
        Write-Warning "Please enter A, B, or C."
    }
}

function Read-YesNo {
    param([Parameter(Mandatory = $true)] [string]$Question)
    while ($true) {
        $Answer = (Read-Host "$Question (Y/N)").Trim().ToUpperInvariant()
        if ($Answer -in @("Y", "YES")) { return $true }
        if ($Answer -in @("N", "NO")) { return $false }
        Write-Warning "Please enter Y or N."
    }
}

if ($BlindComparison) {
    $BlindAssetIds = @("frying_pan", "old_mop", "shotgun_melee")
    $RandomizedAssets = @(Get-Random -InputObject $BlindAssetIds -Count $BlindAssetIds.Count)
    $BlindLabels = @("A", "B", "C")
    $SessionId = "blind-{0}-{1}" -f ((Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
    $ApplicationData = [Environment]::GetFolderPath("ApplicationData")
    $BlindDirectory = Join-Path $ApplicationData "Godot\app_userdata\Forge Playlab V1\playlab\motion_grammar_slice_1a"
    New-Item -ItemType Directory -Path $BlindDirectory -Force | Out-Null

    $Mapping = @{}
    $RunEvidence = @()
    Write-Output "MOTION GRAMMAR SLICE 1A - BLIND COMPARISON"
    Write-Output "Three real generated sprites will run in randomized order. Identity, Recipe, and Affordance labels stay hidden."
    Write-Output "Complete all three waves for A, B, and C. Do not answer the comparison questions until all three runs finish."

    for ($Index = 0; $Index -lt $BlindLabels.Count; $Index++) {
        $Label = $BlindLabels[$Index]
        $InternalAssetId = $RandomizedAssets[$Index]
        $Mapping[$Label] = $InternalAssetId
        $RunResultPath = Join-Path $BlindDirectory ("{0}-{1}.json" -f $SessionId, $Label)
        if (Test-Path -LiteralPath $RunResultPath) {
            Remove-Item -LiteralPath $RunResultPath -Force
        }
        Write-Output "Launching BLIND $Label. Complete the fight, then click COMPLETE BLIND $Label."
        $RunExitCode = Invoke-MotionGrammarRun -MotionGrammarAsset $InternalAssetId -BlindLabel $Label -BlindResultPath $RunResultPath
        if ($RunExitCode -ne 0 -or -not (Test-Path -LiteralPath $RunResultPath)) {
            throw "BLIND_${Label}_NOT_COMPLETED"
        }
        $RunRecord = Get-Content -LiteralPath $RunResultPath -Raw | ConvertFrom-Json
        if (-not $RunRecord.completed -or $RunRecord.blind_label -ne $Label) {
            throw "BLIND_${Label}_RESULT_INVALID"
        }
        $RunEvidence += $RunRecord
    }

    Write-Output "All three blind runs are complete. Answer from feel only."
    $Answers = [ordered]@{
        shortest_reach = Read-BlindLabel "1. Which weapon had the shortest reach?"
        widest_range = Read-BlindLabel "2. Which weapon covered the widest area?"
        heaviest_third_hit = Read-BlindLabel "3. Which weapon had the heaviest third hit?"
        best_control = Read-BlindLabel "4. Which weapon felt best for crowd control?"
        most_forward_progress = Read-BlindLabel "5. Which weapon moved forward the most?"
    }

    $Expected = [ordered]@{
        shortest_reach = ($Mapping.GetEnumerator() | Where-Object Value -eq "frying_pan").Key
        widest_range = ($Mapping.GetEnumerator() | Where-Object Value -eq "old_mop").Key
        heaviest_third_hit = ($Mapping.GetEnumerator() | Where-Object Value -eq "shotgun_melee").Key
        best_control = ($Mapping.GetEnumerator() | Where-Object Value -eq "old_mop").Key
        most_forward_progress = ($Mapping.GetEnumerator() | Where-Object Value -eq "shotgun_melee").Key
    }

    $Correctness = [ordered]@{}
    $CorrectCount = 0
    foreach ($QuestionId in $Expected.Keys) {
        $IsCorrect = $Answers[$QuestionId] -eq $Expected[$QuestionId]
        $Correctness[$QuestionId] = $IsCorrect
        if ($IsCorrect) { $CorrectCount++ }
    }

    Write-Output "Now confirm whether the intended qualitative differences were actually felt."
    $Qualitative = [ordered]@{
        pan_short_fast_heavy_slap = Read-YesNo "Did the Pan feel short, fast, and like a heavy slap?"
        broom_long_wide_control = Read-YesNo "Did the Broom/Mop feel long, wide, and control-oriented?"
        shotgun_linear_heaviest_third = Read-YesNo "Did the Shotgun stock feel linear, advancing, with the heaviest third hit?"
    }
    $AllQualitativePassed = -not ($Qualitative.Values -contains $false)
    $Verdict = if ($CorrectCount -ge 4 -and $AllQualitativePassed) {
        "TECHNICAL PASS / FEEL PASS"
    } else {
        "TECHNICAL PASS / FEEL NEEDS WORK"
    }

    $BlindRecord = [ordered]@{
        schema = "forge-motion-grammar-slice-1a-blind-comparison-v1"
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        session_id = $SessionId
        randomized_mapping = $Mapping
        run_evidence = $RunEvidence
        answers = $Answers
        expected = $Expected
        correctness = $Correctness
        correct_count = $CorrectCount
        qualitative_confirmation = $Qualitative
        verdict = $Verdict
        human_fun_claim = $false
    }
    $HistoryPath = Join-Path $BlindDirectory "blind_comparison_results.jsonl"
    [IO.File]::AppendAllText($HistoryPath, (($BlindRecord | ConvertTo-Json -Depth 12 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

    Write-Output "Blind mapping: A=$($Mapping['A']) B=$($Mapping['B']) C=$($Mapping['C'])"
    Write-Output "Correct answers: $CorrectCount/5"
    Write-Output "Verdict: $Verdict"
    Write-Output "Saved locally: $HistoryPath"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Asset)) {
    Write-Output "Select a real Motion Grammar asset:"
    Write-Output "  1. Pan"
    Write-Output "  2. Broom"
    Write-Output "  3. Shotgun melee (developer-only intent override)"
    $Selection = Read-Host "Enter 1, 2, or 3"
    $Asset = @{
        "1" = "Pan"
        "2" = "Broom"
        "3" = "ShotgunMelee"
    }[$Selection]
    if ([string]::IsNullOrWhiteSpace($Asset)) {
        throw "Invalid selection. Enter 1, 2, or 3."
    }
}

if ($Asset -eq "Shotgun") {
    $Asset = "ShotgunMelee"
}

$MotionGrammarAsset = $AssetMap[$Asset]
Write-Output "Starting Motion Grammar Slice 1A ($Asset)."
if ($Asset -eq "ShotgunMelee") {
    Write-Output "Developer-only melee intent override; the frozen ranged Blueprint is not modified."
}
$ExitCode = Invoke-MotionGrammarRun -MotionGrammarAsset $MotionGrammarAsset
exit $ExitCode
