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

$minVersion = [Version]"0.49.6"

function Test-Version([string]$Binary) {
    $raw = (& $Binary --version 2>$null | Select-Object -First 1) -replace "[^0-9.]", ""
    try {
        return ([Version]$raw -ge $minVersion)
    } catch {
        return $false
    }
}

function Test-Skill([string]$Binary) {
    if (-not (Test-Version $Binary)) { return $false }
    $helpText = & $Binary agents run --help 2>$null
    if ($LASTEXITCODE -ne 0 -or (($helpText -join "`n") -notmatch "(?m)^Usage: archdev agents run ")) { return $false }
    $helpText = & $Binary settings provider models --help 2>$null
    if ($LASTEXITCODE -ne 0 -or (($helpText -join "`n") -notmatch "(?m)^Usage: archdev settings provider models ")) { return $false }
    $helpText = & $Binary repo status --help 2>$null
    if ($LASTEXITCODE -ne 0 -or (($helpText -join "`n") -notmatch "Probe CLI, login, model access")) { return $false }
    $helpText = & $Binary projects list --help 2>$null
    if ($LASTEXITCODE -ne 0 -or (($helpText -join "`n") -notmatch "(?m)^Usage: archdev projects list ")) { return $false }
    $helpText = & $Binary log post --help 2>$null
    if ($LASTEXITCODE -ne 0 -or (($helpText -join "`n") -notmatch "--project <id>")) { return $false }
    $helpText = & $Binary repo hook setup --help 2>$null
    return ($LASTEXITCODE -eq 0 -and (($helpText -join "`n") -match "--local"))
}

if (-not (Test-Skill $archdev)) {
    [Console]::Error.WriteLine("Updating ArchDev: this skill requires 0.49.6+ and repository hook setup with --local.")
    $archdev = Install-ArchDev
}

if (-not (Test-Path -LiteralPath $archdev -PathType Leaf)) {
    throw "ArchDev installer did not create an executable at $archdev"
}
& $archdev --version *> $null
if ($LASTEXITCODE -ne 0) { throw "ArchDev version verification failed" }
if (-not (Test-Skill $archdev)) { throw "Installed ArchDev lacks required commands or --local hook setup (need 0.49.6+); stopping without a global fallback" }

# Resolving the executable must not choose configuration scope. Install and
# repair hooks only through the approved branch in https://archdev.ai/install.md.
Write-Output $archdev
