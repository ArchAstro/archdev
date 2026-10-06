$ErrorActionPreference = "Stop"

function Resolve-ArchDevPath([string]$Candidate) {
    return (Resolve-Path -LiteralPath $Candidate).Path
}

function Install-ArchDev {
    # Reviewed installer bytes; update the revision and digest together.
    $installerUrl = "https://raw.githubusercontent.com/ArchAstro/archdev/a530d21dd04eaed5742b8ad7daf9140a3ee2ef0f/install.ps1"
    $installerSha256 = "f767834cb5aeae252b9c37f427818906ee82f9a11a71b9d4fd0ba0cd2e8086e1"
    $installDir = if ($env:ARCHDEV_INSTALL_DIR) {
        $env:ARCHDEV_INSTALL_DIR
    } else {
        Join-Path $env:LOCALAPPDATA "ArchDev\bin"
    }
    $installerRoot = Join-Path ([IO.Path]::GetTempPath()) ("archdev-install-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $installerRoot -ErrorAction Stop | Out-Null
    $installerPath = Join-Path $installerRoot "install.ps1"
    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
        $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
        if ($actualHash -ne $installerSha256) {
            throw "ArchDev installer SHA256 mismatch; refusing to execute downloaded content."
        }
        & $installerPath -InstallDir $installDir -BaseUrl "" -SkipPathUpdate -SkipVerify:$false *> $null
        if (-not $?) { throw "ArchDev installer failed" }
    } finally {
        Remove-Item $installerRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    return (Resolve-ArchDevPath (Join-Path $installDir "archdev.exe"))
}

$existing = Get-Command archdev -ErrorAction SilentlyContinue
$archdev = if ($existing) { Resolve-ArchDevPath $existing.Source } else { Install-ArchDev }

function Test-Tasks([string]$Binary) {
    $raw = (& $Binary --version 2>$null | Select-Object -First 1) -replace "[^0-9.]", ""
    try {
        if ([Version]$raw -lt [Version]"0.47.0") { return $false }
    } catch { return $false }
    $helpText = & $Binary tasks review update --help 2>$null
    if ($LASTEXITCODE -ne 0 -or (($helpText -join "`n") -notmatch "(?m)^Usage: archdev tasks review update ")) { return $false }
    # This capability marks the release with consent-safe hook self-heal.
    $hookHelp = & $Binary repo hook setup --help 2>$null
    return ($LASTEXITCODE -eq 0 -and (($hookHelp -join "`n") -match "--local"))
}

if (-not (Test-Tasks $archdev)) {
    [Console]::Error.WriteLine("Updating ArchDev: Tasks requires 0.47.0+, web review commands, and consent-safe repository hook support.")
    $archdev = Install-ArchDev
}

if (-not (Test-Path -LiteralPath $archdev -PathType Leaf)) {
    throw "ArchDev installer did not create an executable at $archdev"
}
& $archdev --version *> $null
if ($LASTEXITCODE -ne 0) { throw "ArchDev version verification failed" }
if (-not (Test-Tasks $archdev)) { throw "Installed ArchDev lacks Tasks web review commands or consent-safe repository hook support on 0.47.0+" }

# Tasks executable resolution does not authorize changing hook configuration.
Write-Output $archdev
