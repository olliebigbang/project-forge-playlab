$ErrorActionPreference = "Stop"
$PlaylabRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $PSScriptRoot "find_godot.ps1")

$TestLog = New-TemporaryFile
& $Godot --headless --verbose --path $PlaylabRoot --script "res://tests/test_enemy_attack_mechanisms_v1.gd" 2>&1 | Tee-Object -FilePath $TestLog.FullName
$TestExit = $LASTEXITCODE
$TestOutput = Get-Content -LiteralPath $TestLog.FullName -Raw
Remove-Item -LiteralPath $TestLog.FullName

$ExpectedSummary = "ENEMY ATTACK MECHANISMS V1 RESULT: 12 passed, 0 failed"
if (
    $TestExit -ne 0 -or
    $TestOutput -match "ERROR: FAIL|failed=[1-9]|ENEMY ATTACK MECHANISMS V1 RESULT:.*[1-9] failed" -or
    -not $TestOutput.Contains($ExpectedSummary)
) {
    exit 1
}

Write-Output "ENEMY_ATTACK_MECHANISMS_V1=PASS"
exit 0
