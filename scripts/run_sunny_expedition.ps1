[CmdletBinding()]
param([switch]$Offline, [switch]$Smoke)
$ErrorActionPreference = 'Stop'
$SunnyRoot = Split-Path -Parent $PSScriptRoot
$SunnyGodot = & (Join-Path $PSScriptRoot 'find_godot.ps1')
$SunnyImportDirectory = Join-Path $SunnyRoot ('.tools/sunny-import/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $SunnyImportDirectory -Force | Out-Null
$SunnyImport = Start-Process -FilePath $SunnyGodot -ArgumentList @('--headless', '--path', ('"' + $SunnyRoot + '"'), '--editor', '--import', '--quit') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $SunnyImportDirectory 'stdout.log') -RedirectStandardError (Join-Path $SunnyImportDirectory 'stderr.log')
$SunnyImportHandle = $SunnyImport.Handle
$SunnyImport.WaitForExit()
if ($SunnyImport.ExitCode -ne 0 -or (Select-String -LiteralPath (Join-Path $SunnyImportDirectory 'stderr.log') -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet)) { throw "Asset import failed. See $SunnyImportDirectory" }
& (Join-Path $PSScriptRoot 'run_church_ai_forge.ps1') -Campaign Sunny -Offline:$Offline -Smoke:$Smoke
exit $LASTEXITCODE
