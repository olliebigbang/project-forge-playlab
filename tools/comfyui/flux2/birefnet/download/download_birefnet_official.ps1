[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoId = "Comfy-Org/BiRefNet"
$RepoCommit = "8fdc9d315889de96cc0c6269eeecd333e2727889"
$RelativeModelPath = "background_removal/birefnet.safetensors"
$SourceUrl = "https://huggingface.co/$RepoId/resolve/$RepoCommit/$RelativeModelPath"
$SourceTemplateUrl = "https://huggingface.co/Comfy-Org/BiRefNet/resolve/main/background_removal/birefnet.safetensors"
$ExpectedBytes = [int64]444473596
$ExpectedSha256 = "9ab37426bf4de0567af6b5d21b16151357149139362e6e8992021b8ce356a154"
$ExpectedTensorKey = "bb.layers.1.blocks.0.attn.relative_position_index"
$Destination = "C:\AI\ComfyUI-ForgeFlux2\ComfyUI\models\background_removal\birefnet.safetensors"
$Partial = "$Destination.partial"
$SpikeRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $SpikeRoot "reports\model_download_manifest.json"

function Test-SafetensorsHeader {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 10) { throw "SAFETENSORS_FILE_TOO_SMALL" }
        $lengthBytes = New-Object byte[] 8
        if ($stream.Read($lengthBytes, 0, 8) -ne 8) { throw "SAFETENSORS_HEADER_LENGTH_UNREADABLE" }
        if (-not [BitConverter]::IsLittleEndian) { [Array]::Reverse($lengthBytes) }
        $headerLength = [BitConverter]::ToUInt64($lengthBytes, 0)
        if ($headerLength -lt 2 -or $headerLength -gt 104857600 -or $headerLength -gt ([uint64]$stream.Length - 8)) {
            throw "SAFETENSORS_HEADER_LENGTH_INVALID:$headerLength"
        }
        $headerBytes = New-Object byte[] ([int]$headerLength)
        $offset = 0
        while ($offset -lt $headerBytes.Length) {
            $read = $stream.Read($headerBytes, $offset, $headerBytes.Length - $offset)
            if ($read -le 0) { throw "SAFETENSORS_HEADER_TRUNCATED" }
            $offset += $read
        }
        try {
            $header = ([System.Text.Encoding]::UTF8.GetString($headerBytes)) | ConvertFrom-Json
        }
        catch {
            throw "SAFETENSORS_HEADER_JSON_INVALID"
        }
        if ($null -eq $header.PSObject.Properties[$ExpectedTensorKey]) {
            throw "SAFETENSORS_BIREFNET_KEY_MISSING:$ExpectedTensorKey"
        }
        return [ordered]@{
            valid = $true
            header_length = [uint64]$headerLength
            required_tensor_key = $ExpectedTensorKey
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-VerifiedModelRecord {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "MODEL_FILE_MISSING:$Path" }
    $item = Get-Item -LiteralPath $Path
    if ([int64]$item.Length -ne $ExpectedBytes) {
        throw "MODEL_SIZE_MISMATCH:expected=$ExpectedBytes:actual=$($item.Length)"
    }
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($sha256 -ne $ExpectedSha256) {
        throw "MODEL_SHA256_MISMATCH:expected=$ExpectedSha256:actual=$sha256"
    }
    $header = Test-SafetensorsHeader -Path $Path
    return [ordered]@{
        filename = "birefnet.safetensors"
        destination = [System.IO.Path]::GetFullPath($Path)
        bytes = [int64]$item.Length
        sha256 = $sha256
        safetensors_header = $header
    }
}

function Write-JsonExclusiveAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    if (Test-Path -LiteralPath $Path) { throw "REFUSING_TO_OVERWRITE_MANIFEST:$Path" }
    $temporary = Join-Path $parent (".{0}.{1}.partial" -f ([IO.Path]::GetFileName($Path)), [Guid]::NewGuid().ToString("N"))
    try {
        [IO.File]::WriteAllText(
            $temporary,
            (($Value | ConvertTo-Json -Depth 20) + "`n"),
            [Text.UTF8Encoding]::new($false)
        )
        if (Test-Path -LiteralPath $Path) { throw "REFUSING_TO_OVERWRITE_MANIFEST:$Path" }
        [IO.File]::Move($temporary, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

$destinationDirectory = Split-Path -Parent $Destination
New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
if ((Resolve-Path $destinationDirectory).Path -ine "C:\AI\ComfyUI-ForgeFlux2\ComfyUI\models\background_removal") {
    throw "MODEL_DESTINATION_DIRECTORY_INVALID"
}

$downloaded = $false
if (Test-Path -LiteralPath $Destination -PathType Leaf) {
    $model = Get-VerifiedModelRecord -Path $Destination
}
else {
    $curl = Get-Command curl.exe -ErrorAction Stop
    & $curl.Source --fail --show-error --location --retry 0 --proto "=https" --tlsv1.2 `
        --continue-at - --output $Partial $SourceUrl
    if ($LASTEXITCODE -ne 0) { throw "BIREFNET_DOWNLOAD_FAILED:exit=$LASTEXITCODE" }
    $model = Get-VerifiedModelRecord -Path $Partial
    if (Test-Path -LiteralPath $Destination) { throw "MODEL_DESTINATION_APPEARED_DURING_DOWNLOAD" }
    [IO.File]::Move($Partial, $Destination)
    $downloaded = $true
    $model = Get-VerifiedModelRecord -Path $Destination
}

$manifest = [ordered]@{
    contract = "forge-birefnet-official-model-download-v1"
    status = "PASS"
    downloaded_this_run = $downloaded
    official_repository = $RepoId
    official_repository_commit = $RepoCommit
    official_template_url = $SourceTemplateUrl
    resolved_download_url = $SourceUrl
    expected_bytes_from_official_head = $ExpectedBytes
    expected_sha256_from_official_lfs_etag = $ExpectedSha256
    license = "MIT"
    license_evidence = @(
        "https://huggingface.co/api/models/Comfy-Org/BiRefNet",
        "https://huggingface.co/Comfy-Org/BiRefNet/raw/$RepoCommit/README.md"
    )
    model = $model
    partial_path = $Partial
    partial_exists_after_success = (Test-Path -LiteralPath $Partial)
    custom_nodes_installed = $false
    completed_at_utc = [DateTime]::UtcNow.ToString("o")
}
Write-JsonExclusiveAtomic -Path $ManifestPath -Value $manifest
$manifest | ConvertTo-Json -Depth 20
