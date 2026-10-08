param(
    [string]$Version = $env:ARCHDEV_VERSION,
    [string]$InstallDir = $env:ARCHDEV_INSTALL_DIR,
    [string]$BaseUrl = $env:ARCHDEV_RELEASE_BASE_URL,
    [switch]$DryRun,
    [switch]$PrintAssetUrl,
    [switch]$SkipPathUpdate,
    [switch]$SkipVerify,
    # Where `archdev setup` installs the skill and hooks: user (globally) or
    # repository. Asked inside a Git repository; otherwise user.
    [string]$Scope = $env:ARCHDEV_INSTALL_SCOPE,
    # Deprecated: reporting is always enabled. `disabled` declines setup.
    [string]$Reporting = $env:ARCHDEV_INSTALL_REPORTING,
    [switch]$SkipLogin,
    [switch]$SkipSetup,
    # Never prompt. Sign-in then needs ARCHDEV_TOKEN, and setup installs
    # globally unless -Scope says otherwise.
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
# Under `irm | iex` this runs in the caller's scope. With PowerShell 7.4's
# opt-in set, a failing native command would throw a generic error before the
# installer's own exit-code checks could explain it.
$PSNativeCommandUseErrorActionPreference = $false
$Owner = "ArchAstro"
$Repo = "archdev"
$AgentPrompt = "Set up this repository with ArchDev."
function Test-Truthy([string]$Value) { return @("1", "true", "yes", "on") -contains "$Value".ToLowerInvariant() }
if (Test-Truthy $env:ARCHDEV_INSTALL_SKIP_LOGIN) { $SkipLogin = $true }
if (Test-Truthy $env:ARCHDEV_INSTALL_SKIP_SETUP) { $SkipSetup = $true }
if (Test-Truthy $env:ARCHDEV_INSTALL_NONINTERACTIVE) { $Yes = $true }
if (@("", "user", "repository") -notcontains "$Scope") { throw "Unknown -Scope: $Scope (use user or repository)" }
if (@("", "enabled", "disabled") -notcontains "$Reporting") { throw "Unknown -Reporting: $Reporting (use enabled or disabled)" }
$DocsUrl = "https://docs.archdev.ai"
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = "latest" }
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $env:LOCALAPPDATA "ArchDev\bin"
}

switch ($env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()) {
    "amd64" { $ArchLabel = "x64" }
    "arm64" { $ArchLabel = "arm64" }
    default { throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}
$ReleasesUrl = "https://github.com/$Owner/$Repo/releases"
$Bare = if ($Version -eq "latest") { "" } else { $Version -replace "^(archdev-old-v|v)", "" }

# SHA256SUMS of the release at $Base, or $null when that release does not exist.
function Get-Checksums([string]$Base) {
    try {
        $Content = (Invoke-WebRequest "$Base/SHA256SUMS" -UseBasicParsing).Content
    } catch {
        $Response = $_.Exception.Response
        if ($Response -and ([int]$Response.StatusCode -eq 404)) { return $null }
        throw
    }
    # GitHub serves the file as application/octet-stream, which arrives as bytes.
    if ($Content -is [byte[]]) { $Content = [Text.Encoding]::UTF8.GetString($Content) }
    return "$Content"
}

function Get-ExpectedHash([string]$Checksums, [string]$Name) {
    $Line = "$Checksums" -split "`r?`n" | Where-Object { $_ -match ('\s\*?' + [Regex]::Escape($Name) + '$') } | Select-Object -First 1
    if ($Line) { return ($Line.Trim() -split '\s+')[0] }
    return $null
}

# The Rust CLI is released under v<version>, and releases/latest points at it.
$ReleaseTag = if ($Bare) { "v$Bare" } else { $null }
$AssetName = "archdev-windows-$ArchLabel.zip"
$SourceExe = "archdev.exe"
$ResolvedBaseUrl = if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl.TrimEnd('/')
} elseif ($ReleaseTag) {
    "$ReleasesUrl/download/$ReleaseTag"
} else {
    "$ReleasesUrl/latest/download"
}
$Checksums = Get-Checksums $ResolvedBaseUrl
$TypeScriptFallback = -not (Get-ExpectedHash $Checksums $AssetName)
if ($TypeScriptFallback) {
    # Rust releases up to v0.49.5 have no Windows zips. For those, install the
    # TypeScript CLI, released as archdev-old under archdev-old-v<version>.
    $AssetName = "archdev-old-windows-$ArchLabel.zip"
    $SourceExe = "archdev-old.exe"
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        if ($Bare) {
            $ReleaseTag = "archdev-old-v$Bare"
        } else {
            # The Atom feed lists the newest releases without API rate limits.
            $Feed = (Invoke-WebRequest "$ReleasesUrl.atom" -UseBasicParsing).Content
            $Newest = [regex]::Matches($Feed, "/releases/tag/archdev-old-v(\d+\.\d+\.\d+)(?=[`"'<\s])") |
                ForEach-Object { [Version]$_.Groups[1].Value } |
                Sort-Object -Descending |
                Select-Object -First 1
            if (-not $Newest) { throw "No ArchDev release with a Windows build was found at $ReleasesUrl" }
            $ReleaseTag = "archdev-old-v$Newest"
        }
        $ResolvedBaseUrl = "$ReleasesUrl/download/$ReleaseTag"
        $Checksums = $null
    }
}
$AssetUrl = "$ResolvedBaseUrl/$AssetName"
$ChecksumUrl = "$ResolvedBaseUrl/SHA256SUMS"
if ($PrintAssetUrl) { Write-Output $AssetUrl; exit 0 }
if ($DryRun) {
    @("version=$Version", "arch=$ArchLabel", "release_tag=$ReleaseTag", "asset=$AssetName", "release_base_url=$ResolvedBaseUrl", "asset_url=$AssetUrl", "checksum_url=$ChecksumUrl", "install_dir=$InstallDir") | Write-Output
    exit 0
}

Write-Host "==> 1. Install the CLI"
if ($TypeScriptFallback) { Write-Host "This release has no Windows build of the Rust CLI. Installing the TypeScript CLI (archdev-old) instead." }
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("archdev-install-" + [Guid]::NewGuid().ToString("N"))
$ArchivePath = Join-Path $TempRoot $AssetName
$ExtractDir = Join-Path $TempRoot "extract"
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
try {
    if (-not $Checksums) { $Checksums = Get-Checksums $ResolvedBaseUrl }
    if (-not $Checksums) { throw "Release not found: $ChecksumUrl" }
    $ExpectedHash = Get-ExpectedHash $Checksums $AssetName
    if (-not $ExpectedHash) { throw "Checksum missing for $AssetName" }
    Invoke-WebRequest $AssetUrl -OutFile $ArchivePath
    $ActualHash = (Get-FileHash $ArchivePath -Algorithm SHA256).Hash
    if ($ActualHash.ToLowerInvariant() -ne $ExpectedHash.ToLowerInvariant()) { throw "Checksum mismatch for $AssetName" }
    Expand-Archive -Path $ArchivePath -DestinationPath $ExtractDir -Force
    # The TypeScript fallback ships as archdev-old.exe; install it as archdev.exe.
    $Source = Join-Path $ExtractDir $SourceExe
    if (-not (Test-Path $Source)) { throw "Archive is missing $SourceExe" }
    # Run the binary before it replaces anything on PATH, as install.sh does. A
    # native command's exit code never trips $ErrorActionPreference, so a binary
    # that cannot start would otherwise install "successfully" and every later
    # step would fail without output.
    if (-not $SkipVerify) {
        $VerifiedVersion = "$(& $Source --version)".Trim()
        Write-Host $VerifiedVersion
        if ($LASTEXITCODE -eq -1073741515) {
            # STATUS_DLL_NOT_FOUND: older Rust CLI releases need the Visual
            # C++ runtime, which a fresh Windows install does not have.
            throw "archdev.exe could not start because a DLL it needs is missing. Install the Microsoft Visual C++ Redistributable (https://aka.ms/vs/17/release/vc_redist.$ArchLabel.exe) and run this installer again."
        }
        if ($LASTEXITCODE -ne 0) { throw "archdev.exe --version exited with code $LASTEXITCODE" }
        if (-not $VerifiedVersion) { throw "archdev.exe --version printed nothing; it does not run on this machine" }
    }
    Copy-Item $Source (Join-Path $InstallDir "archdev.exe") -Force
    if (-not $SkipPathUpdate) {
        $CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $Entries = if ($CurrentUserPath) { $CurrentUserPath -split ';' } else { @() }
        if ($Entries -notcontains $InstallDir) {
            $NewPath = if ($CurrentUserPath) { "$CurrentUserPath;$InstallDir" } else { $InstallDir }
            [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        }
    }
    Write-Host "Installed archdev to $InstallDir"
} finally {
    Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Sign in, then install the skill and hooks. Mirrors install.sh.
# ---------------------------------------------------------------------------

$Bin = Join-Path $InstallDir "archdev.exe"
# Setup requires archdev on PATH; the user PATH edit above reaches new shells only.
if (($env:Path -split ';') -notcontains $InstallDir) { $env:Path = "$InstallDir;$env:Path" }
$env:ARCHDEV_NO_UPDATE_CHECK = "1"
$Interactive = (-not $Yes) -and (-not $env:CI) -and [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected)

# Run the CLI and capture its output. Windows PowerShell turns redirected
# stderr into terminating errors under "Stop", so relax it for the call.
function Invoke-Archdev {
    $ErrorActionPreference = "Continue"
    $script:CliOutput = @(& $Bin @args 2>&1 | ForEach-Object { "$_" })
    return $LASTEXITCODE -eq 0
}

# Outside a repository git writes to stderr, so this needs the same relaxation.
function Get-RepositoryRoot {
    $ErrorActionPreference = "Continue"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return "" }
    return "$(git rev-parse --show-toplevel 2>$null)".Trim()
}

# `archdev auth status` exits 0 only when the saved session is usable.
function Show-SignedIn {
    $Email = ($script:CliOutput | Where-Object { $_ -match '^Email: ' } | Select-Object -First 1) -replace '^Email: ', ''
    if ([string]::IsNullOrWhiteSpace($Email)) { $Email = "your account" }
    Write-Host "Signed in as $Email"
}

Write-Host ""
Write-Host "==> 2. Sign in"
$SignedIn = $false
if ($SkipLogin) {
    Write-Host "Skipped. Sign in later with: archdev auth login"
} elseif (Invoke-Archdev auth status) {
    $SignedIn = $true
    Show-SignedIn
} elseif (-not $Interactive) {
    Write-Host "No terminal to sign in from. Run: archdev auth login"
    Write-Host "For CI, set ARCHDEV_TOKEN to a personal access token."
} else {
    Write-Host "ArchDev signs you in with GitHub in your browser."
    $Answer = Read-Host "Sign in now? [Y/n]"
    if ($Answer -match '^\s*n') {
        Write-Host "Skipped. Sign in later with: archdev auth login"
    } else {
        # Releases that have --onboarding open the workspace in the browser
        # after sign-in instead of a "return to your terminal" page; older
        # ones reject it.
        $LoginArgs = @("auth", "login")
        if ((Invoke-Archdev auth login --help) -and ($script:CliOutput -match '--onboarding')) { $LoginArgs += "--onboarding" }
        # The CLI owns the browser and copy/paste flows; give it the console.
        & $Bin @LoginArgs
        if (($LASTEXITCODE -eq 0) -and (Invoke-Archdev auth status)) {
            $SignedIn = $true
            Show-SignedIn
        } else {
            Write-Warning "Sign-in did not finish. Run: archdev auth login"
        }
    }
}

Write-Host ""
Write-Host "==> 3. Install the skill and hooks"
$SetupDone = $false
$SetupFailed = $false
if ($SkipSetup) {
    Write-Host "Skipped. Finish later with: archdev setup"
} elseif (-not $SignedIn) {
    Write-Host "Sign in first, then run: archdev setup"
} elseif ($Reporting -eq "disabled") {
    Write-Host "Nothing changed: setup always enables activity reporting, so -Reporting disabled declines setup."
} else {
    $RepoRoot = Get-RepositoryRoot
    $HasNode = [bool](Get-Command node -ErrorAction SilentlyContinue)

    # The only question: inside a repository, the skill and hooks can live there
    # instead of globally. Everywhere else, and without a terminal, they are
    # global. Repository hooks need Node.js, so without it the answer is global.
    if ([string]::IsNullOrWhiteSpace($Scope)) {
        $Scope = "user"
        if ($Interactive -and $RepoRoot -and $HasNode) {
            Write-Host "Where should ArchDev install its skill and hooks?"
            Write-Host "  1) Globally  (every repository you work in)"
            Write-Host "  2) This repository  ($RepoRoot)"
            if ((Read-Host "Choose [1]").Trim() -eq "2") { $Scope = "repository" }
        }
    }
    if ($Scope -eq "repository") {
        if (-not $RepoRoot) { throw "-Scope repository needs a Git repository. Run the installer from inside the repository." }
        if (-not $HasNode) { throw "Repository hooks need Node.js on PATH. Install Node.js, or use -Scope user." }
    }

    Write-Host "Setup posts a one-time installation announcement, and session hooks report activity and findings to your organization's shared stream, visible to its members."
    if ($Scope -eq "repository") { Push-Location $RepoRoot }
    try {
        # Releases before the reporting question was removed require the flag.
        $SetupDone = Invoke-Archdev setup --scope $Scope --reporting enabled
    } finally {
        if ($Scope -eq "repository") { Pop-Location }
    }
    if ($SetupDone) {
        if ($Scope -eq "repository") {
            Write-Host "Skill and hooks installed for $RepoRoot"
        } else {
            Write-Host "Skill and hooks installed for this user"
        }
        # The CLI reports whether the one-time announcement was recorded, queued
        # or failed; pass that sentence through instead of restating it.
        $Announcement = $script:CliOutput | Where-Object { $_ -match 'announcement' } | Select-Object -First 1
        if ($Announcement) { Write-Host $Announcement }
        Write-Host "Restart your coding agents so they load the hooks. Codex and Grok ask you to trust repository hooks; that approval stays with you."
    } else {
        $SetupFailed = $true
        Write-Warning "archdev setup did not finish:"
        $script:CliOutput | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" }
        Write-Host "Fix the issue above, then run: archdev setup --scope $Scope"
    }
}

function Write-NextCommand([string]$Command, [string]$Hint) {
    Write-Host ("    {0,-22} {1}" -f $Command, $Hint)
}

Write-Host ""
$InstalledVersion = if (Invoke-Archdev --version) { "$($script:CliOutput | Select-Object -First 1)".Trim() } else { "" }
if ($SignedIn -and $SetupDone) {
    Write-Host "ArchDev $InstalledVersion is ready"
} else {
    Write-Host "ArchDev $InstalledVersion is installed"
}
Write-Host ""
if (-not $SkipPathUpdate) { Write-Host "    Open a new terminal to load archdev onto PATH." }
if (-not $SignedIn) { Write-NextCommand "archdev auth login" "sign in with GitHub" }
if (-not $SetupDone) {
    Write-NextCommand "archdev setup" "install the skill and hooks for your agents"
} else {
    # The agent finishes the job: it maps the repository's plans, tasks and
    # review workflow, which the installer cannot know.
    if ($Scope -eq "repository") {
        Write-Host "    Start your coding agent in this repository and tell it:"
    } else {
        Write-Host "    Go to a repository you work in, start your coding agent and tell it:"
    }
    Write-Host ""
    Write-Host "      $AgentPrompt"
    Write-Host ""
}
Write-Host ""
Write-Host "    Docs  $DocsUrl"
Write-Host ""
# The CLI is installed, but a setup the user asked for did not complete.
if ($SetupFailed) { throw "archdev setup did not finish." }
