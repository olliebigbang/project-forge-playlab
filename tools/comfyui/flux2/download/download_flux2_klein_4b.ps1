[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\AI\ComfyUI-ForgeFlux2',
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Assert-AllowedResolvedSource([string]$Url) {
    $uri = [Uri]$Url
    $hostName = $uri.DnsSafeHost.ToLowerInvariant()
    $allowed = $hostName -eq 'huggingface.co' -or
        $hostName.EndsWith('.huggingface.co') -or
        $hostName.EndsWith('.hf.co') -or
        $hostName.EndsWith('.xethub.hf.co')
    if ($uri.Scheme -ne 'https' -or -not $allowed) {
        throw "DOWNLOAD_SOURCE_NOT_ALLOWED:$Url"
    }
}

function Get-SafeResolvedUrl([string]$Url) {
    $uri = [Uri]$Url
    return $uri.GetLeftPart([UriPartial]::Path)
}

function Test-SafetensorsHeader([string]$Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 16) { throw "SAFETENSORS_TOO_SMALL:$Path" }
        $lengthBytes = New-Object byte[] 8
        if ($stream.Read($lengthBytes, 0, 8) -ne 8) { throw "SAFETENSORS_HEADER_LENGTH_MISSING:$Path" }
        $headerLength = [BitConverter]::ToUInt64($lengthBytes, 0)
        if ($headerLength -lt 2 -or $headerLength -gt 104857600 -or ($headerLength + 8) -ge $stream.Length) {
            throw "SAFETENSORS_HEADER_LENGTH_INVALID:${Path}:$headerLength"
        }
        $headerBytes = New-Object byte[] ([int]$headerLength)
        if ($stream.Read($headerBytes, 0, [int]$headerLength) -ne [int]$headerLength) {
            throw "SAFETENSORS_HEADER_TRUNCATED:$Path"
        }
        $header = [Text.Encoding]::UTF8.GetString($headerBytes)
        $parsed = $header | ConvertFrom-Json
        if ($null -eq $parsed) { throw "SAFETENSORS_HEADER_JSON_INVALID:$Path" }
    }
    finally {
        $stream.Dispose()
    }
}

$runtimeResolved = [IO.Path]::GetFullPath($RuntimeRoot)
if (-not $runtimeResolved.StartsWith('C:\AI\ComfyUI-ForgeFlux2', [StringComparison]::OrdinalIgnoreCase)) {
    throw "RUNTIME_ROOT_OUT_OF_SCOPE:$runtimeResolved"
}
$drive = Get-PSDrive -Name C
if ($drive.Free -lt 40GB) {
    throw ('INSUFFICIENT_C_DRIVE_SPACE:{0:N2}GB' -f ($drive.Free / 1GB))
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw 'CURL_EXE_REQUIRED'
}

$models = @(
    [ordered]@{
        filename = 'flux-2-klein-4b-fp8.safetensors'
        directory = 'diffusion_models'
        official_source = 'https://huggingface.co/black-forest-labs/FLUX.2-klein-4b-fp8/resolve/main/flux-2-klein-4b-fp8.safetensors'
        expected_bytes = 4070624520
        expected_sha256 = '97ed34fe0567e436200f2faee3939b88f2b5d99f8af2a4dc16532c4245c0ccb6'
        license = 'Apache-2.0'
    },
    [ordered]@{
        filename = 'qwen_3_4b.safetensors'
        directory = 'text_encoders'
        official_source = 'https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors'
        expected_bytes = 8044982048
        expected_sha256 = '6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a'
        license = 'TO VALIDATE: converted artifact license not explicit; see LICENSE_AUDIT.md'
    },
    [ordered]@{
        filename = 'flux2-vae.safetensors'
        directory = 'vae'
        official_source = 'https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors'
        expected_bytes = 336213556
        expected_sha256 = 'd64f3a68e1cc4f9f4e29b6e0da38a0204fe9a49f2d4053f0ec1fa1ca02f9c4b5'
        license = 'TO VALIDATE: hosting repo identifies FLUX.2 Dev non-commercial license; see LICENSE_AUDIT.md'
    }
)

$manifestEntries = @()
foreach ($model in $models) {
    $approvedOrigins = @(
        'https://huggingface.co/black-forest-labs/FLUX.2-klein-4b-fp8/resolve/main/flux-2-klein-4b-fp8.safetensors',
        'https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors',
        'https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors'
    )
    if ($approvedOrigins -notcontains $model.official_source) {
        throw "DOWNLOAD_ORIGIN_NOT_IN_FROZEN_ALLOWLIST:$($model.official_source)"
    }
    if ($model.filename -match '(?i)(base|9b|dev|gguf|lora|controlnet)') {
        throw "UNAUTHORIZED_MODEL_FILENAME:$($model.filename)"
    }
    $targetDirectory = Join-Path $runtimeResolved "ComfyUI\models\$($model.directory)"
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    $destination = Join-Path $targetDirectory $model.filename
    $partial = "$destination.partial"
    $headerFile = "$partial.headers"
    $effectiveFile = "$partial.effective"
    $downloadedNow = $false

    if (-not (Test-Path -LiteralPath $destination)) {
        $curlArgs = @(
            '--fail', '--location', '--continue-at', '-',
            '--retry', '0', '--connect-timeout', '30',
            '--dump-header', $headerFile,
            '--write-out', '%{url_effective}',
            '--output', $partial,
            $model.official_source
        )
        $effective = & curl.exe @curlArgs
        if ($LASTEXITCODE -ne 0) { throw "MODEL_DOWNLOAD_FAILED:$($model.filename):$LASTEXITCODE" }
        [IO.File]::WriteAllText($effectiveFile, [string]$effective, [Text.UTF8Encoding]::new($false))
        $downloadedNow = $true
    }

    $candidate = if (Test-Path -LiteralPath $destination) { $destination } else { $partial }
    $item = Get-Item -LiteralPath $candidate
    if ($item.Length -ne [Int64]$model.expected_bytes) {
        throw "MODEL_SIZE_MISMATCH:$($model.filename):$($item.Length):$($model.expected_bytes)"
    }
    $firstBytes = New-Object byte[] 32
    $probe = [IO.File]::OpenRead($candidate)
    try { [void]$probe.Read($firstBytes, 0, $firstBytes.Length) } finally { $probe.Dispose() }
    $prefix = [Text.Encoding]::ASCII.GetString($firstBytes).TrimStart()
    if ($prefix.StartsWith('<!DOCTYPE', [StringComparison]::OrdinalIgnoreCase) -or
        $prefix.StartsWith('<html', [StringComparison]::OrdinalIgnoreCase)) {
        throw "HTML_RESPONSE_REJECTED:$($model.filename)"
    }
    Test-SafetensorsHeader $candidate
    $actualHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $model.expected_sha256) {
        throw "MODEL_SHA256_MISMATCH:$($model.filename):$actualHash"
    }
    if ($candidate -eq $partial) {
        [IO.File]::Move($partial, $destination)
    }

    $headers = if (Test-Path -LiteralPath $headerFile) { Get-Content -LiteralPath $headerFile } else { @() }
    $etagLine = @($headers | Where-Object { $_ -match '^(?i)etag:' }) | Select-Object -Last 1
    $modifiedLine = @($headers | Where-Object { $_ -match '^(?i)last-modified:' }) | Select-Object -Last 1
    $effectiveUrl = if (Test-Path -LiteralPath $effectiveFile) {
        Get-SafeResolvedUrl ((Get-Content -LiteralPath $effectiveFile -Raw).Trim())
    } else {
        $model.official_source
    }
    Assert-AllowedResolvedSource $effectiveUrl
    $manifestEntries += [ordered]@{
        filename = $model.filename
        destination = $destination
        official_source = $model.official_source
        resolved_url = $effectiveUrl
        bytes = [Int64](Get-Item -LiteralPath $destination).Length
        sha256 = $actualHash
        expected_sha256 = $model.expected_sha256
        etag = if ($etagLine) { ($etagLine -replace '^(?i)etag:\s*', '').Trim() } else { $null }
        last_modified = if ($modifiedLine) { ($modifiedLine -replace '^(?i)last-modified:\s*', '').Trim() } else { $null }
        downloaded_at = [DateTime]::UtcNow.ToString('o')
        license = $model.license
        status = if ($downloadedNow) { 'downloaded_verified' } else { 'existing_verified' }
    }
}

$reportDirectory = Join-Path $ProjectRoot 'tools\comfyui\flux2\reports'
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$manifestPath = Join-Path $reportDirectory 'model_download_manifest.json'
$tempManifest = "$manifestPath.partial"
$payload = [ordered]@{
    contract = 'forge-flux2-model-download-v1'
    runtime_root = $runtimeResolved
    free_c_drive_bytes_after = [Int64](Get-PSDrive -Name C).Free
    source_template_commit = 'cebdebc9fc2febcb97a5db0dd291f59f5300b176'
    files = $manifestEntries
    status = 'PASS'
}
[IO.File]::WriteAllText($tempManifest, (($payload | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
if (Test-Path -LiteralPath $manifestPath) {
    [IO.File]::Replace($tempManifest, $manifestPath, $null)
} else {
    [IO.File]::Move($tempManifest, $manifestPath)
}
Write-Output ($payload | ConvertTo-Json -Depth 8)
