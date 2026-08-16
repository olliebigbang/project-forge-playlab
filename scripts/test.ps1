$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$godot = & (Join-Path $PSScriptRoot "find_godot.ps1")

function Invoke-Godot {
    param([string[]]$GodotArgs)
    # Start-Process joins ArgumentList with spaces and does not quote, so a
    # repository path containing spaces would be split into separate arguments.
    $quoted = @($GodotArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } })
    # The non-console Windows build does not set $LASTEXITCODE when invoked with
    # the call operator, which reported success even when the suite failed to
    # load. Start-Process -PassThru reports the real exit code.
    $process = Start-Process -FilePath $godot -ArgumentList $quoted -NoNewWindow -Wait -PassThru
    return $process.ExitCode
}

# A fresh clone or git worktree has no .godot import cache. Without it every
# global class_name fails to resolve and run_tests.gd cannot even parse.
$importExit = Invoke-Godot @("--headless", "--path", $repoRoot, "--import")
if ($importExit -ne 0) {
    Write-Output "Godot project import failed with exit code $importExit"
    exit $importExit
}

$testExit = Invoke-Godot @("--headless", "--path", $repoRoot, "--script", (Join-Path $repoRoot "tests\run_tests.gd"))
exit $testExit
