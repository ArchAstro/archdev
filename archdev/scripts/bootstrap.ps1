$ErrorActionPreference = "Stop"

function Resolve-ArchDevPath([string]$Candidate) {
    return (Resolve-Path -LiteralPath $Candidate).Path
}

function Install-ArchDev {
    # Reviewed installer bytes; update the revision and digest together.
    $installerUrl = "https://raw.githubusercontent.com/ArchAstro/archdev/9d50e7ce1e64a731d88cca8ae15ec2c45b1375df/install.ps1"
    $installerSha256 = "222e807055126433a1239b2c30d0561f68e6f9661d994c86b7a0b9831452227e"
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

$minVersion = [Version]"0.46.0"

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
    return ($LASTEXITCODE -eq 0 -and (($helpText -join "`n") -match "--project <id>"))
}

if (-not (Test-Skill $archdev)) {
    [Console]::Error.WriteLine("Updating ArchDev because this version lacks Agents, provider, repo, projects, or log --project commands (need 0.46.0+).")
    $archdev = Install-ArchDev
}

if (-not (Test-Path -LiteralPath $archdev -PathType Leaf)) {
    throw "ArchDev installer did not create an executable at $archdev"
}
& $archdev --version *> $null
if ($LASTEXITCODE -ne 0) { throw "ArchDev version verification failed" }
if (-not (Test-Skill $archdev)) { throw "Installed ArchDev does not provide Agents, provider, repo, and projects commands" }

# Bring installed ArchDev harness hooks up to this CLI's hook wiring. Only
# harnesses that already have archdev hooks change, and a failure (for example
# an older archdev earlier on PATH) is reported without blocking the skill.
# Its stderr goes straight to the console; only stdout is relayed, because
# merging stderr into the pipeline under ErrorActionPreference=Stop throws.
try {
    $hookHelp = (& $archdev repo hook setup --help 2>$null) -join "`n"
    if ($hookHelp -match "--refresh") {
        & $archdev repo hook setup --refresh | ForEach-Object { [Console]::Error.WriteLine($_) }
        if ($LASTEXITCODE -ne 0) {
            [Console]::Error.WriteLine("Could not refresh ArchDev hooks; see above, then run: archdev repo hook setup")
        }
    }
} catch {
    [Console]::Error.WriteLine("Could not refresh ArchDev hooks: $_")
}
Write-Output $archdev
