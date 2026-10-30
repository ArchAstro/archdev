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

$minVersion = [Version]"0.49.6"

function Test-Version([string]$Binary) {
    $raw = (& $Binary --version 2>$null | Select-Object -First 1) -replace "[^0-9.]", ""
    if ($LASTEXITCODE -ne 0) { return $false }
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

# A Homebrew install owns its copy. Installing another one elsewhere leaves two
# binaries that are upgraded separately, and whichever comes first on PATH wins.
# Homebrew exists only on macOS and Linux; Windows keeps the installer path.
$brewFormula = "archastro/tools/archdev"

# Resolves every symlink in the path, including directory links such as
# Homebrew's opt link. A dangling keg link still yields its Cellar path.
function Get-RealPath([string]$Path) {
    $pending = [Collections.Generic.List[string]]::new()
    $pending.AddRange([string[]]@([IO.Path]::GetFullPath($Path).Split("/") | Where-Object { $_ }))
    $real = ""
    $hops = 0
    while ($pending.Count -gt 0) {
        $part = $pending[0]
        $pending.RemoveAt(0)
        if ($part -eq ".") { continue }
        if ($part -eq "..") {
            $real = $real.Substring(0, [Math]::Max(0, $real.LastIndexOf("/")))
            continue
        }
        $next = "$real/$part"
        $item = Get-Item -LiteralPath $next -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkTarget -and $hops -lt 32) {
            $hops++
            if ($item.LinkTarget.StartsWith("/")) { $real = "" }
            $pending.InsertRange(0, [string[]]@($item.LinkTarget.Split("/") | Where-Object { $_ }))
            continue
        }
        $real = $next
    }
    return $real
}

# Test-Path accepts a dangling link; a removed keg leaves one behind.
function Test-LinkedFile([string]$Path) {
    return (Test-Path -LiteralPath (Get-RealPath $Path) -PathType Leaf)
}

function Test-HomebrewArchDev([string]$Path) {
    return ((Get-RealPath $Path) -like "*/Cellar/archdev/*")
}

function Get-Brew {
    return (Get-Command brew -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
}

# The Homebrew-managed archdev on PATH, else <brew --prefix>/bin/archdev when
# Homebrew links it there, even if another copy comes first on PATH.
function Find-HomebrewArchDev($Candidate) {
    if ($env:OS -eq "Windows_NT") { return $null }
    if ($Candidate -and (Test-HomebrewArchDev $Candidate)) { return $Candidate }
    $brew = Get-Brew
    if (-not $brew) { return $null }
    $prefix = @(& $brew.Source --prefix 2>$null) | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $prefix) { return $null }
    $linked = Join-Path $prefix "bin/archdev"
    if ((Get-Item -LiteralPath $linked -Force -ErrorAction SilentlyContinue) -and (Test-HomebrewArchDev $linked)) {
        return $linked
    }
    return $null
}

# Repairs a Homebrew-managed archdev with Homebrew rather than a second copy:
# upgrade when it reports a too-old version; reinstall when the binary is
# missing, crashes, or a current version fails the capability probes, where
# upgrade would be a no-op.
function Update-HomebrewArchDev([string]$Binary) {
    # The brew that owns this keg; another prefix's brew could install a second copy.
    $real = Get-RealPath $Binary
    $brew = $real.Substring(0, $real.IndexOf("/Cellar/archdev/")) + "/bin/brew"
    if (-not (Test-Path -LiteralPath $brew -PathType Leaf)) {
        throw "ArchDev at $Binary is managed by Homebrew, but $brew is missing. Run: brew upgrade $brewFormula. Not installing a second copy of ArchDev."
    }
    $version = $null
    if (Test-LinkedFile $Binary) {
        $raw = (& $Binary --version 2>$null | Select-Object -First 1) -replace "[^0-9.]", ""
        try { $version = [Version]$raw } catch { $version = $null }
    }
    # Only a readable, too-old version needs an upgrade; anything else is broken.
    $action = if ($version -and $version -lt $minVersion) { "upgrade" } else { "reinstall" }
    [Console]::Error.WriteLine("Updating Homebrew-managed ArchDev at ${Binary}: brew $action $brewFormula")
    # Callers read stdout as the archdev path, so brew's progress goes to stderr.
    & $brew $action $brewFormula | ForEach-Object { [Console]::Error.WriteLine($_) }
    if ($LASTEXITCODE -ne 0) {
        throw "brew $action $brewFormula failed. ArchDev at $Binary is managed by Homebrew; not installing a second copy."
    }
}

# Cache success only for this invocation, never across an install/repair.
$skillChecked = $false
$existing = Get-Command archdev -ErrorAction SilentlyContinue
$candidate = if ($existing) { Resolve-ArchDevPath $existing.Source } else { $null }
$homebrewArchDev = Find-HomebrewArchDev $candidate
if ($homebrewArchDev) {
    $archdev = $homebrewArchDev
    if ($candidate -and $candidate -ne $archdev) {
        [Console]::Error.WriteLine("Using Homebrew-managed ArchDev at $archdev; $candidate comes first on PATH.")
    }
    if ((Test-LinkedFile $archdev) -and (Test-Skill $archdev)) {
        $skillChecked = $true
    } else {
        Update-HomebrewArchDev $archdev
    }
} else {
    $archdev = if ($candidate) { $candidate } else { Install-ArchDev }
    if (Test-Skill $archdev) {
        $skillChecked = $true
    } else {
        [Console]::Error.WriteLine("Updating ArchDev: this skill requires 0.49.6+ and repository hook setup with --local.")
        $archdev = Install-ArchDev
    }
}

if ($homebrewArchDev -and -not (Test-LinkedFile $archdev)) {
    throw "Homebrew did not leave an executable at $archdev; not installing a second copy."
}
if (-not (Test-Path -LiteralPath $archdev -PathType Leaf)) {
    throw "ArchDev installer did not create an executable at $archdev"
}
if (-not $skillChecked -and -not (Test-Skill $archdev)) {
    if ($homebrewArchDev) { throw "Homebrew-managed ArchDev at $archdev still fails the capability check after brew; not installing a second copy." }
    throw "Installed ArchDev lacks required commands or --local hook setup (need 0.49.6+); stopping without a global fallback"
}

# Resolving the executable must not choose configuration scope. Install and
# repair hooks only through the approved branch in https://archdev.ai/install.md.
Write-Output $archdev
