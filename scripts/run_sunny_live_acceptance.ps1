[CmdletBinding()]
param([switch]$AllowLive, [string]$EnvFile = "", [string]$Model = "claude-sonnet-5", [string]$ReserveFrom = "", [string[]]$SampleIds = @(), [string]$Manifest = "")
$ErrorActionPreference = "Stop"
$AcceptanceProject = Split-Path -Parent $PSScriptRoot
$AcceptanceRoot = Join-Path $AcceptanceProject (".tools/sunny-live-acceptance/" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $AcceptanceRoot -Force | Out-Null
$AcceptanceNames = @("ANTHROPIC_API_KEY", "FAL_KEY", "FAL_API_KEY", "FORGE_SEMANTIC_MODEL", "FORGE_WEAPON_LIBRARY_ROOT", "FORGE_ACCEPTANCE_ROOT", "FORGE_ACCEPTANCE_SAMPLE_IDS", "FORGE_ACCEPTANCE_MANIFEST")
$AcceptancePrevious = @{}
foreach ($Name in $AcceptanceNames) { $AcceptancePrevious[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process"); [Environment]::SetEnvironmentVariable($Name, $null, "Process") }
$AcceptanceExit = 1
try {
    if ($Manifest) {
        if ($ReserveFrom -or $SampleIds.Count -gt 0) { throw 'A fresh manifest cannot be combined with a reserve.' }
        $AcceptanceDataRoot = (Resolve-Path -LiteralPath (Join-Path $AcceptanceProject 'data')).Path
        $AcceptanceManifestPath = (Resolve-Path -LiteralPath $Manifest).Path
        if (-not $AcceptanceManifestPath.StartsWith($AcceptanceDataRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fresh acceptance manifest must be a checked project data file.' }
        $AcceptanceManifest = Get-Content -LiteralPath $AcceptanceManifestPath -Raw | ConvertFrom-Json
        if (@($AcceptanceManifest.samples).Count -ne 1 -or [int]$AcceptanceManifest.max_first_pass_visual_requests -ne 1 -or [int]$AcceptanceManifest.max_visual_requests_per_sample -ne 1 -or [int]$AcceptanceManifest.reserve_visual_requests -ne 0) { throw 'Fresh acceptance manifest must authorize exactly one sample, one visual pipeline, and no reserve.' }
        $env:FORGE_ACCEPTANCE_MANIFEST = $AcceptanceManifestPath.Replace('\','/')
    }
    if ($AllowLive) {
        if ($ReserveFrom -or $SampleIds.Count -gt 0) {
            $AcceptanceBase = (Resolve-Path -LiteralPath (Join-Path $AcceptanceProject '.tools/sunny-live-acceptance')).Path
            $AcceptancePrior = (Resolve-Path -LiteralPath $ReserveFrom).Path
            if (-not $AcceptancePrior.StartsWith($AcceptanceBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Reserve source must be a previous isolated acceptance run.' }
            $AcceptanceBudgetPath = Join-Path $AcceptancePrior 'budget.json'
            $AcceptanceBudget = Get-Content -LiteralPath $AcceptanceBudgetPath -Raw | ConvertFrom-Json
            if ([int]$AcceptanceBudget.separately_authorized_reserve_limit -ne 2 -or [int]$AcceptanceBudget.reserved_first_pass_visual_requests -ne 6) { throw 'A reserve cannot itself authorize further reserves.' }
            $AcceptanceUsed = if ($AcceptanceBudget.PSObject.Properties.Name -contains 'reserve_requests_used') { [int]$AcceptanceBudget.reserve_requests_used } else { 0 }
            if ($SampleIds.Count -lt 1 -or $AcceptanceUsed + $SampleIds.Count -gt 2 -or @($SampleIds | Where-Object { $_ -notin $AcceptanceBudget.started_cases }).Count -gt 0) { throw 'Reserve exceeds two requests or sample was not in the original run.' }
            $AcceptanceBudget | Add-Member -NotePropertyName reserve_requests_used -NotePropertyValue ($AcceptanceUsed + $SampleIds.Count) -Force
            $AcceptanceBudget | Add-Member -NotePropertyName last_reserve_directory -NotePropertyValue $AcceptanceRoot -Force
            [IO.File]::WriteAllText($AcceptanceBudgetPath, ($AcceptanceBudget | ConvertTo-Json -Depth 6))
            $env:FORGE_ACCEPTANCE_SAMPLE_IDS = $SampleIds -join ','
        }
        if ([string]::IsNullOrWhiteSpace($EnvFile)) { $EnvFile = Join-Path $env:USERPROFILE ".env" }
        foreach ($Line in Get-Content -LiteralPath $EnvFile) {
            if ($Line -notmatch '^\s*(?:export\s+)?(ANTHROPIC_API_KEY|FAL_KEY|FAL_API_KEY)\s*=\s*(.*?)\s*$') { continue }
            $Name = $Matches[1]; $Value = $Matches[2].Trim().Trim('"').Trim("'")
            if (-not [string]::IsNullOrWhiteSpace($Value)) { [Environment]::SetEnvironmentVariable($Name, $Value, "Process") }
            $Value = $null
        }
        if (-not $env:FAL_KEY) { $env:FAL_KEY = $env:FAL_API_KEY }
        if (-not $env:ANTHROPIC_API_KEY -or -not $env:FAL_KEY) { throw "Required semantic/image key missing; values are never logged." }
        $env:FORGE_SEMANTIC_MODEL = $Model
        Write-Host $(if ($Manifest) { "PAID fresh acceptance: one frozen input, one visual pipeline task, no reserve or automatic retry." } elseif ($SampleIds.Count -gt 0) { "PAID bounded reserve: $($SampleIds -join ','); original identities, one pipeline task each." } else { "PAID live acceptance: six frozen inputs, max one visual pipeline task each; no automatic retry." })
    }
    $env:FORGE_WEAPON_LIBRARY_ROOT = Join-Path $AcceptanceRoot "isolated-library"
    $env:FORGE_ACCEPTANCE_ROOT = $AcceptanceRoot.Replace('\','/')
    $env:FORGE_WEAPON_LIBRARY_ROOT = $env:FORGE_ACCEPTANCE_ROOT + "/isolated-library"
    $AcceptanceGodot = & (Join-Path $PSScriptRoot "find_godot.ps1")
    $AcceptancePython = (Get-Command python).Source
    $AcceptanceArgs = @("--path", $AcceptanceProject, "--position", "-1600,-900", "--script", "res://tests/sunny_live_acceptance.gd", "--", "--fal-python=$AcceptancePython")
    $AcceptanceArgs += $(if ($AllowLive) { "--allow-live-ai-review" } else { "--dry-run" })
    $AcceptanceQuoted = foreach ($Argument in $AcceptanceArgs) { if ($Argument -match '[\s"]') { '"' + $Argument.Replace('"','\"') + '"' } else { $Argument } }
    Write-Host "Acceptance evidence: $AcceptanceRoot"
    $AcceptanceProcess = Start-Process -FilePath $AcceptanceGodot -ArgumentList $AcceptanceQuoted -WorkingDirectory $AcceptanceProject -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $AcceptanceRoot "stdout.log") -RedirectStandardError (Join-Path $AcceptanceRoot "stderr.log")
    $AcceptanceHandle = $AcceptanceProcess.Handle
    $AcceptanceProcess.WaitForExit()
    $AcceptanceExit = $AcceptanceProcess.ExitCode
    if (Select-String -LiteralPath (Join-Path $AcceptanceRoot "stderr.log") -Pattern "SCRIPT ERROR|Parse Error|Compile Error" -Quiet) { $AcceptanceExit = 2 }
}
finally {
    foreach ($Name in $AcceptanceNames) { [Environment]::SetEnvironmentVariable($Name, $AcceptancePrevious[$Name], "Process") }
    $AcceptancePrevious.Clear(); $Value = $null
}
exit $AcceptanceExit
