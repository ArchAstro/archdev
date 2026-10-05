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
# The Rust archdev has no Windows build yet, so Windows installs the
# TypeScript CLI, released as archdev-old under the archdev-old-v<version> tag.
# releases/latest belongs to the Rust CLI and has no Windows zips.
$ReleaseTagPrefix = "archdev-old-v"
$AssetPrefix = "archdev-old"
$SourceExe = "archdev-old.exe"
$ReleasesUrl = "https://github.com/$Owner/$Repo/releases"
$ReleaseTag = $null
if ($Version -eq "latest") {
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        # The Atom feed lists the newest releases without API rate limits.
        $Feed = (Invoke-WebRequest "$ReleasesUrl.atom" -UseBasicParsing).Content
        $Newest = [regex]::Matches($Feed, "/releases/tag/$([Regex]::Escape($ReleaseTagPrefix))(\d+\.\d+\.\d+)(?=[`"'<\s])") |
            ForEach-Object { [Version]$_.Groups[1].Value } |
            Sort-Object -Descending |
            Select-Object -First 1
        if ($Newest) {
            $ReleaseTag = "$ReleaseTagPrefix$Newest"
        } else {
            # No archdev-old release is published yet: latest is still the
            # TypeScript CLI, with its original asset and binary names.
            $AssetPrefix = "archdev"
            $SourceExe = "archdev.exe"
        }
    }
} else {
    $Bare = $Version -replace "^($([Regex]::Escape($ReleaseTagPrefix))|v)", ""
    $ReleaseTag = "$ReleaseTagPrefix$Bare"
}
$AssetName = "$AssetPrefix-windows-$ArchLabel.zip"
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $ResolvedBaseUrl = if ($ReleaseTag) {
        "$ReleasesUrl/download/$ReleaseTag"
    } else {
        "$ReleasesUrl/latest/download"
    }
} else {
    $ResolvedBaseUrl = $BaseUrl.TrimEnd('/')
}
$AssetUrl = "$ResolvedBaseUrl/$AssetName"
$ChecksumUrl = "$ResolvedBaseUrl/SHA256SUMS"
if ($PrintAssetUrl) { Write-Output $AssetUrl; exit 0 }
Write-Host "Windows installs the TypeScript ArchDev CLI until the Rust Windows build ships."
if ($DryRun) {
    @("version=$Version", "arch=$ArchLabel", "release_tag=$ReleaseTag", "asset=$AssetName", "release_base_url=$ResolvedBaseUrl", "asset_url=$AssetUrl", "checksum_url=$ChecksumUrl", "install_dir=$InstallDir") | Write-Output
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
    # The TypeScript build ships as archdev-old.exe; install it as archdev.exe.
    $Source = Join-Path $ExtractDir $SourceExe
    if (-not (Test-Path $Source)) { throw "Archive is missing $SourceExe" }
    Copy-Item $Source (Join-Path $InstallDir "archdev.exe") -Force
    if (-not $SkipPathUpdate) {
        $CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $Entries = if ($CurrentUserPath) { $CurrentUserPath -split ';' } else { @() }
        if ($Entries -notcontains $InstallDir) {
            $NewPath = if ($CurrentUserPath) { "$CurrentUserPath;$InstallDir" } else { $InstallDir }
            [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        }
    }
    if (-not $SkipVerify) { & (Join-Path $InstallDir "archdev.exe") --version }
    Write-Host "Installed archdev to $InstallDir"
} finally {
    Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
