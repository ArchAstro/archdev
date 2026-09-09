$ErrorActionPreference = "Stop"

function Resolve-ArchDevPath([string]$Candidate) {
    return (Resolve-Path -LiteralPath $Candidate).Path
}

function Install-ArchDev {
    $installerUrl = if ($env:ARCHDEV_INSTALLER_URL) {
        $env:ARCHDEV_INSTALLER_URL
    } else {
        "https://raw.githubusercontent.com/ArchAstro/archdev/9d50e7ce1e64a731d88cca8ae15ec2c45b1375df/install.ps1"
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

function Test-Rooms([string]$Binary) {
    & $Binary rooms start --help *> $null
    if ($LASTEXITCODE -ne 0) { return $false }
    $helpText = & $Binary rooms search --help 2>$null
    return ($LASTEXITCODE -eq 0 -and (($helpText -join "`n") -match '--messages'))
}

if (-not (Test-Rooms $archdev)) {
    [Console]::Error.WriteLine("Updating ArchDev because this version lacks Rooms lifecycle or Knowledge search commands.")
    $archdev = Install-ArchDev
}

if (-not (Test-Path -LiteralPath $archdev -PathType Leaf)) {
    throw "ArchDev installer did not create an executable at $archdev"
}
& $archdev --version *> $null
if ($LASTEXITCODE -ne 0) { throw "ArchDev version verification failed" }
if (-not (Test-Rooms $archdev)) { throw "Installed ArchDev does not provide Rooms lifecycle and Knowledge search commands" }
Write-Output $archdev
