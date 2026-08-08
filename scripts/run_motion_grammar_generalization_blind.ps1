param()

$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")

function Invoke-GeneralizationRun {
    param(
        [Parameter(Mandatory = $true)] [string]$AssetId,
        [Parameter(Mandatory = $true)] [string]$BlindLabel,
        [Parameter(Mandatory = $true)] [string]$BlindResultPath
    )

    $GodotArguments = @(
        "--path", $PlaylabRoot,
        "res://scenes/combat_feel_slice_0.tscn",
        "--",
        "--mode=combat-feel-slice-0",
        "--generalization-asset=$AssetId",
        "--blind-comparison=true",
        "--blind-suite=generalization_v1",
        "--blind-label=$BlindLabel",
        "--blind-result-path=$BlindResultPath"
    )
    & $Godot @GodotArguments | Out-Host
    return $LASTEXITCODE
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

function Get-ExpectedLabel {
    param(
        [Parameter(Mandatory = $true)] [hashtable]$RecordsByLabel,
        [Parameter(Mandatory = $true)] [string]$Metric,
        [Parameter(Mandatory = $true)] [bool]$Maximum
    )
    $Rows = foreach ($Label in @("A", "B", "C")) {
        $Value = [double]$RecordsByLabel[$Label].compiled_metrics.$Metric
        [PSCustomObject]@{ Label = $Label; Value = $Value }
    }
    $Sorted = @($Rows | Sort-Object -Property Value -Descending:$Maximum)
    if ([Math]::Abs($Sorted[0].Value - $Sorted[1].Value) -lt 0.000001) {
        throw "GENERALIZATION_METRIC_TIE:$Metric"
    }
    return $Sorted[0].Label
}

$BlindAssetIds = @(
    "longsword_generalization",
    "spear_generalization",
    "wooden_chair_generalization"
)
$RandomizedAssets = @(Get-Random -InputObject $BlindAssetIds -Count $BlindAssetIds.Count)
$BlindLabels = @("A", "B", "C")
$SessionId = "generalization-blind-{0}-{1}" -f ((Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$ApplicationData = [Environment]::GetFolderPath("ApplicationData")
$BlindDirectory = Join-Path $ApplicationData "Godot\app_userdata\Forge Playlab V1\playlab\motion_grammar_generalization_v1"
New-Item -ItemType Directory -Path $BlindDirectory -Force | Out-Null

$Mapping = @{}
$RecordsByLabel = @{}
$RunEvidence = @()
Write-Output "MOTION GRAMMAR GENERALIZATION BLIND V1"
Write-Output "This is a NEW set: longsword, spear, and wooden chair. It does not reuse Pan, Broom/Mop, or Shotgun."
Write-Output "All three use frozen real generated sprites and the existing MeleeMotionCompiler/Controller chain."
Write-Output "Complete all three waves, then click COMPLETE BLIND A/B/C. Do not answer comparison questions early."

for ($Index = 0; $Index -lt $BlindLabels.Count; $Index++) {
    $Label = $BlindLabels[$Index]
    $InternalAssetId = $RandomizedAssets[$Index]
    $Mapping[$Label] = $InternalAssetId
    $RunResultPath = Join-Path $BlindDirectory ("{0}-{1}.json" -f $SessionId, $Label)
    if (Test-Path -LiteralPath $RunResultPath) {
        Remove-Item -LiteralPath $RunResultPath -Force
    }
    Write-Output "Launching GENERALIZATION BLIND $Label. Complete the fight, then click COMPLETE BLIND $Label."
    $RunExitCode = Invoke-GeneralizationRun -AssetId $InternalAssetId -BlindLabel $Label -BlindResultPath $RunResultPath
    if ($RunExitCode -ne 0 -or -not (Test-Path -LiteralPath $RunResultPath)) {
        throw "GENERALIZATION_BLIND_${Label}_NOT_COMPLETED"
    }
    $RunRecord = Get-Content -LiteralPath $RunResultPath -Raw | ConvertFrom-Json
    if (-not $RunRecord.completed -or $RunRecord.blind_label -ne $Label -or $RunRecord.blind_suite -ne "generalization_v1") {
        throw "GENERALIZATION_BLIND_${Label}_RESULT_INVALID"
    }
    if ($null -eq $RunRecord.compiled_metrics -or [string]::IsNullOrWhiteSpace($RunRecord.compiled_metrics.recipe_signature)) {
        throw "GENERALIZATION_BLIND_${Label}_METRICS_MISSING"
    }
    $RecordsByLabel[$Label] = $RunRecord
    $RunEvidence += $RunRecord
}

$Signatures = @($RunEvidence | ForEach-Object { $_.compiled_metrics.recipe_signature } | Sort-Object -Unique)
if ($Signatures.Count -ne 3) {
    throw "GENERALIZATION_RECIPES_NOT_DISTINCT"
}

$Expected = [ordered]@{
    shortest_reach = Get-ExpectedLabel -RecordsByLabel $RecordsByLabel -Metric "reach_pixels" -Maximum $false
    widest_range = Get-ExpectedLabel -RecordsByLabel $RecordsByLabel -Metric "maximum_coverage_score" -Maximum $true
    heaviest_third_hit = Get-ExpectedLabel -RecordsByLabel $RecordsByLabel -Metric "third_hit_weight_score" -Maximum $true
    best_control = Get-ExpectedLabel -RecordsByLabel $RecordsByLabel -Metric "control_score" -Maximum $true
    most_forward_progress = Get-ExpectedLabel -RecordsByLabel $RecordsByLabel -Metric "combo_root_motion_total" -Maximum $true
}

Write-Output "All three NEW blind runs are complete. Answer from feel only."
$Answers = [ordered]@{
    shortest_reach = Read-BlindLabel "1. Which object had the shortest reach?"
    widest_range = Read-BlindLabel "2. Which object covered the widest area?"
    heaviest_third_hit = Read-BlindLabel "3. Which object had the heaviest third hit?"
    best_control = Read-BlindLabel "4. Which object felt best for crowd control?"
    most_forward_progress = Read-BlindLabel "5. Which object moved forward the most?"
}

$Correctness = [ordered]@{}
$CorrectCount = 0
foreach ($QuestionId in $Expected.Keys) {
    $IsCorrect = $Answers[$QuestionId] -eq $Expected[$QuestionId]
    $Correctness[$QuestionId] = $IsCorrect
    if ($IsCorrect) { $CorrectCount++ }
}

$Qualitative = [ordered]@{
    three_objects_felt_distinct = Read-YesNo "Did the three objects feel materially different?"
    visible_structure_matched_motion = Read-YesNo "Did each motion feel plausible for the visible object structure?"
    same_moves_with_swapped_sprites = Read-YesNo "Did they feel like the same moves with swapped sprites?"
}
$QualitativePassed = $Qualitative.three_objects_felt_distinct -and $Qualitative.visible_structure_matched_motion -and -not $Qualitative.same_moves_with_swapped_sprites
$Verdict = if ($CorrectCount -ge 4 -and $QualitativePassed) {
    "TECHNICAL PASS / FEEL PASS"
} else {
    "TECHNICAL PASS / FEEL NEEDS WORK"
}

$BlindRecord = [ordered]@{
    schema = "forge-motion-grammar-generalization-blind-v1"
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    session_id = $SessionId
    randomized_mapping = $Mapping
    run_evidence = $RunEvidence
    expected_from_frozen_runtime_metrics = $Expected
    answers = $Answers
    correctness = $Correctness
    correct_count = $CorrectCount
    qualitative_confirmation = $Qualitative
    recipe_signatures_distinct = $true
    verdict = $Verdict
    human_fun_claim = $false
}
$HistoryPath = Join-Path $BlindDirectory "generalization_blind_results.jsonl"
[IO.File]::AppendAllText($HistoryPath, (($BlindRecord | ConvertTo-Json -Depth 12 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

Write-Output "Blind mapping: A=$($Mapping['A']) B=$($Mapping['B']) C=$($Mapping['C'])"
Write-Output "Correct answers: $CorrectCount/5"
Write-Output "Verdict: $Verdict"
Write-Output "Saved locally: $HistoryPath"
