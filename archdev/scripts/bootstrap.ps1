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

$minVersion = [Version]"0.46.5"

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
    $helpText = & $Binary extract finalize --help 2>$null
    return ($LASTEXITCODE -eq 0 -and (($helpText -join "`n") -match "--publish <pull>"))
}

if (-not (Test-Skill $archdev)) {
    [Console]::Error.WriteLine("Updating ArchDev because this version lacks Agents, provider, repo, projects, log --project, or extract finalize --publish commands (need 0.46.5+).")
    $archdev = Install-ArchDev
}

if (-not (Test-Path -LiteralPath $archdev -PathType Leaf)) {
    throw "ArchDev installer did not create an executable at $archdev"
}
& $archdev --version *> $null
if ($LASTEXITCODE -ne 0) { throw "ArchDev version verification failed" }
if (-not (Test-Skill $archdev)) { throw "Installed ArchDev does not provide Agents, provider, repo, and projects commands" }

# Ensure ArchDev hooks for the harness running this skill, so the monitor
# contract reaches later sessions even when they never load the skill. The
# harness comes from the marker it sets on the shells it spawns.
function Get-CallingHarness {
    if ($env:CLAUDECODE -eq "1") { return "claude" }
    if ($env:CODEX_THREAD_ID) { return "codex" }
    if ($env:GROK_SESSION_ID) { return "grok" }
    return $null
}

function Get-HomeDirectory {
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    return $HOME
}

# The file each harness reads hooks from; keep in step with the CLI's
# harnessHookFile.
function Get-HarnessHookFile([string]$Harness) {
    $homeDir = Get-HomeDirectory
    switch ($Harness) {
        "claude" {
            $dir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $homeDir ".claude" }
            return (Join-Path $dir "settings.json")
        }
        "codex" {
            $dir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $homeDir ".codex" }
            return (Join-Path $dir "hooks.json")
        }
        "grok" {
            $dir = if ($env:GROK_HOME) { $env:GROK_HOME } else { Join-Path $homeDir ".grok" }
            return (Join-Path (Join-Path $dir "hooks") "archdev.json")
        }
    }
}

# Whether the harness config already carries a hook command archdev wrote.
function Test-ArchDevHooks([string]$Harness) {
    $file = Get-HarnessHookFile $Harness
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $false }
    $text = Get-Content -LiteralPath $file -Raw
    return ($text -match '"command"\s*:\s*"\s*archdev (repo|inspect) hook ')
}

# The archdev Claude Code plugin ships the same hooks; settings.json hooks on
# top of it would run every hook twice. Counts a user-scope install that the
# user settings have not disabled.
function Test-ClaudePlugin {
    $config = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path (Get-HomeDirectory) ".claude" }
    $root = if ($env:CLAUDE_CODE_PLUGIN_CACHE_DIR) { $env:CLAUDE_CODE_PLUGIN_CACHE_DIR } else { Join-Path $config "plugins" }
    $file = Join-Path $root "installed_plugins.json"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $false }
    $installs = (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json).plugins.'archdev@archastro'
    if (-not (@($installs) | Where-Object { $_.scope -eq "user" })) { return $false }
    $settings = Join-Path $config "settings.json"
    if (Test-Path -LiteralPath $settings -PathType Leaf) {
        $enabled = (Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).enabledPlugins
        if ($enabled -and $enabled.'archdev@archastro' -eq $false) { return $false }
    }
    return $true
}

# `repo hook setup --uninstall` records an opt-out only on CLIs that also
# print the plugin hooks (`repo hook plugin-hooks-json`). An older CLI would
# undo a deliberate uninstall, so it only refreshes.
function Test-SetupHonoursOptOut {
    $help = (& $archdev repo hook --help 2>$null) -join "`n"
    return ($help -match "plugin-hooks-json")
}

# Failures are reported without blocking the skill (for example an older
# archdev earlier on PATH, which setup refuses to wire). Setup's stderr goes
# straight to the console; only stdout is relayed, because merging stderr into
# the pipeline under ErrorActionPreference=Stop throws. Each step has its own
# try so a failed install still leaves the refresh.
try {
    $ErrorActionPreference = "Continue"
    $harness = Get-CallingHarness
    $install = $harness -and -not (Test-ArchDevHooks $harness) -and
        -not ($harness -eq "claude" -and (Test-ClaudePlugin)) -and
        (Test-SetupHonoursOptOut)
    if ($install) {
        & $archdev repo hook setup --harness $harness | ForEach-Object { [Console]::Error.WriteLine($_) }
        if ($LASTEXITCODE -ne 0) {
            [Console]::Error.WriteLine("Could not install ArchDev hooks for $harness; see above, then run: archdev repo hook setup --harness $harness")
        }
    }
} catch {
    [Console]::Error.WriteLine("Could not install ArchDev hooks: $_")
}
# Bring every harness that has archdev hooks, and ArchDev's own runtime, up
# to this CLI's hook wiring.
try {
    $ErrorActionPreference = "Continue"
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
