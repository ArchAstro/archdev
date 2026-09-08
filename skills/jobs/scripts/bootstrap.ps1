$ErrorActionPreference = "Stop"

function Resolve-ArchDevPath([string]$Candidate) {
    return (Resolve-Path -LiteralPath $Candidate).Path
}

function Install-ArchDev {
    $installDir = if ($env:ARCHDEV_INSTALL_DIR) {
        $env:ARCHDEV_INSTALL_DIR
    } else {
        Join-Path $env:LOCALAPPDATA "ArchDev\bin"
    }
    $requestedVersion = if ($env:ARCHDEV_VERSION) { $env:ARCHDEV_VERSION } else { "latest" }
    $baseUrl = if ($env:ARCHDEV_RELEASE_BASE_URL) {
        $env:ARCHDEV_RELEASE_BASE_URL.TrimEnd('/')
    } elseif ($requestedVersion -eq "latest") {
        "https://github.com/ArchAstro/archdev/releases/latest/download"
    } else {
        $tag = if ($requestedVersion.StartsWith("v")) { $requestedVersion } else { "v$requestedVersion" }
        "https://github.com/ArchAstro/archdev/releases/download/$tag"
    }
    $architecture = switch ($env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()) {
        "amd64" { "x64" }
        "arm64" { "arm64" }
        default { throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
    }
    $asset = "archdev-windows-$architecture.zip"
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("archdev-skill-" + [Guid]::NewGuid().ToString("N"))
    $archive = Join-Path $tempRoot $asset
    $checksums = Join-Path $tempRoot "SHA256SUMS"
    $extract = Join-Path $tempRoot "extract"
    try {
        New-Item -ItemType Directory -Path $extract -Force | Out-Null
        Invoke-WebRequest -Uri "$baseUrl/$asset" -OutFile $archive
        Invoke-WebRequest -Uri "$baseUrl/SHA256SUMS" -OutFile $checksums
        $expectedLine = Select-String -Path $checksums -Pattern ([Regex]::Escape($asset) + '$') | Select-Object -First 1
        if (-not $expectedLine) { throw "Checksum missing for $asset" }
        $expected = ($expectedLine.Line -split '\s+')[0]
        $actual = (Get-FileHash $archive -Algorithm SHA256).Hash
        if ($actual.ToLowerInvariant() -ne $expected.ToLowerInvariant()) {
            throw "Checksum mismatch for $asset"
        }
        Expand-Archive -Path $archive -DestinationPath $extract -Force
        $source = Join-Path $extract "archdev.exe"
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Archive is missing archdev.exe"
        }
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Copy-Item $source (Join-Path $installDir "archdev.exe") -Force
        Remove-Item (Join-Path $installDir "archdev-dashboard.exe") -Force -ErrorAction SilentlyContinue
    } finally {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    return (Resolve-ArchDevPath (Join-Path $installDir "archdev.exe"))
}

$existing = Get-Command archdev -ErrorAction SilentlyContinue
$archdev = if ($existing) { Resolve-ArchDevPath $existing.Source } else { Install-ArchDev }

& $archdev jobs setup --help *> $null
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("Updating ArchDev because this version lacks the Jobs domain.")
    $archdev = Install-ArchDev
}

if (-not (Test-Path -LiteralPath $archdev -PathType Leaf)) {
    throw "ArchDev installation did not create an executable at $archdev"
}
& $archdev --version *> $null
if ($LASTEXITCODE -ne 0) { throw "ArchDev version verification failed" }
& $archdev jobs setup --help *> $null
if ($LASTEXITCODE -ne 0) { throw "Installed ArchDev does not provide the Jobs domain" }
Write-Output $archdev
