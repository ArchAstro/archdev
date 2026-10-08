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
if ($DryRun) {
    @("version=$Version", "arch=$ArchLabel", "release_tag=$ReleaseTag", "asset=$AssetName", "release_base_url=$ResolvedBaseUrl", "asset_url=$AssetUrl", "checksum_url=$ChecksumUrl", "install_dir=$InstallDir") | Write-Output
    exit 0
}

Write-Host "==> 1. Install the CLI"
Write-Host "Windows installs the TypeScript ArchDev CLI until the Rust Windows build ships."
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
        # The CLI owns the browser and copy/paste flows; give it the console.
        & $Bin auth login
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
Write-NextCommand "archdev tasks" "plan, claim and complete shared work"
Write-NextCommand "archdev review" "review local changes in ArchCode"
Write-NextCommand "archdev upgrade" "update the CLI, skills and hooks"
Write-Host ""
Write-Host "    Docs  $DocsUrl"
Write-Host ""
# The CLI is installed, but a setup the user asked for did not complete.
if ($SetupFailed) { throw "archdev setup did not finish." }
