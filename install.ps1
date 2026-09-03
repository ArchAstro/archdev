param(
    [string]$Version = $env:ARCHDEV_VERSION,
    [string]$InstallDir = $env:ARCHDEV_INSTALL_DIR,
    [string]$BaseUrl = $env:ARCHDEV_RELEASE_BASE_URL,
    [switch]$DryRun,
    [switch]$PrintAssetUrl,
    [switch]$SkipPathUpdate,
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
$Owner = "ArchAstro"
$Repo = "archdev"
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = "latest" }
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $env:LOCALAPPDATA "ArchDev\bin"
}

switch ($env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()) {
    "amd64" { $ArchLabel = "x64" }
    "arm64" { $ArchLabel = "arm64" }
    default { throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}
$VersionTag = if ($Version -eq "latest" -or $Version.StartsWith("v")) { $Version } else { "v$Version" }
$AssetName = "archdev-windows-$ArchLabel.zip"
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $ResolvedBaseUrl = if ($Version -eq "latest") {
        "https://github.com/$Owner/$Repo/releases/latest/download"
    } else {
        "https://github.com/$Owner/$Repo/releases/download/$VersionTag"
    }
} else {
    $ResolvedBaseUrl = $BaseUrl.TrimEnd('/')
}
$AssetUrl = "$ResolvedBaseUrl/$AssetName"
$ChecksumUrl = "$ResolvedBaseUrl/SHA256SUMS"
if ($PrintAssetUrl) { Write-Output $AssetUrl; exit 0 }
if ($DryRun) {
    @("version=$Version", "arch=$ArchLabel", "asset=$AssetName", "release_base_url=$ResolvedBaseUrl", "asset_url=$AssetUrl", "checksum_url=$ChecksumUrl", "install_dir=$InstallDir") | Write-Output
    exit 0
}

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("archdev-install-" + [Guid]::NewGuid().ToString("N"))
$ArchivePath = Join-Path $TempRoot $AssetName
$ChecksumPath = Join-Path $TempRoot "SHA256SUMS"
$ExtractDir = Join-Path $TempRoot "extract"
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
try {
    Invoke-WebRequest $AssetUrl -OutFile $ArchivePath
    Invoke-WebRequest $ChecksumUrl -OutFile $ChecksumPath
    $ExpectedLine = Select-String -Path $ChecksumPath -Pattern ([Regex]::Escape($AssetName) + '$') | Select-Object -First 1
    if (-not $ExpectedLine) { throw "Checksum missing for $AssetName" }
    $ExpectedHash = ($ExpectedLine.Line -split '\s+')[0]
    $ActualHash = (Get-FileHash $ArchivePath -Algorithm SHA256).Hash
    if ($ActualHash.ToLowerInvariant() -ne $ExpectedHash.ToLowerInvariant()) { throw "Checksum mismatch for $AssetName" }
    Expand-Archive -Path $ArchivePath -DestinationPath $ExtractDir -Force
    foreach ($Name in @("archdev.exe", "archdev-dashboard.exe")) {
        $Source = Join-Path $ExtractDir $Name
        if (-not (Test-Path $Source)) { throw "Archive is missing $Name" }
        Copy-Item $Source (Join-Path $InstallDir $Name) -Force
    }
    if (-not $SkipPathUpdate) {
        $CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $Entries = if ($CurrentUserPath) { $CurrentUserPath -split ';' } else { @() }
        if ($Entries -notcontains $InstallDir) {
            $NewPath = if ($CurrentUserPath) { "$CurrentUserPath;$InstallDir" } else { $InstallDir }
            [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        }
    }
    if (-not $SkipVerify) { & (Join-Path $InstallDir "archdev.exe") --version }
    Write-Host "Installed archdev and archdev-dashboard to $InstallDir"
} finally {
    Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
