$ErrorActionPreference = "Stop"

function Resolve-ArchDevPath([string]$Candidate) {
    return (Resolve-Path -LiteralPath $Candidate).Path
}

function Install-ArchDev {
    $installerUrl = if ($env:ARCHDEV_INSTALLER_URL) {
        $env:ARCHDEV_INSTALLER_URL
    } else {
        "https://raw.githubusercontent.com/ArchAstro/archdev/7c16002d66a004b13812cf675042cb1c50fbf6df/install.ps1"
    }
    $installDir = if ($env:ARCHDEV_INSTALL_DIR) {
        $env:ARCHDEV_INSTALL_DIR
    } else {
        Join-Path $env:LOCALAPPDATA "ArchDev\bin"
    }
    $installerPath = Join-Path ([IO.Path]::GetTempPath()) ("archdev-install-" + [Guid]::NewGuid().ToString("N") + ".ps1")
    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
        $env:ARCHDEV_INSTALL_DIR = $installDir
        & $installerPath -SkipPathUpdate *> $null
        if (-not $?) { throw "ArchDev installer failed" }
    } finally {
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    }
    return (Resolve-ArchDevPath (Join-Path $installDir "archdev.exe"))
}

$existing = Get-Command archdev -ErrorAction SilentlyContinue
$archdev = if ($existing) { Resolve-ArchDevPath $existing.Source } else { Install-ArchDev }

function Test-Reviews([string]$Binary) {
    $helpText = & $Binary reviews local --help 2>$null
    if ($LASTEXITCODE -ne 0 -or (($helpText -join "`n") -notmatch "(?m)^Usage: archdev reviews local ")) { return $false }
    $helpText = & $Binary reviews workflows run --help 2>$null
    return ($LASTEXITCODE -eq 0 -and (($helpText -join "`n") -match "(?m)^Usage: archdev reviews workflows run "))
}

if (-not (Test-Reviews $archdev)) {
    [Console]::Error.WriteLine("Updating ArchDev because this version lacks Reviews commands.")
    $archdev = Install-ArchDev
}

if (-not (Test-Path -LiteralPath $archdev -PathType Leaf)) {
    throw "ArchDev installer did not create an executable at $archdev"
}
& $archdev --version *> $null
if ($LASTEXITCODE -ne 0) { throw "ArchDev version verification failed" }
if (-not (Test-Reviews $archdev)) { throw "Installed ArchDev does not provide Reviews commands" }
Write-Output $archdev
