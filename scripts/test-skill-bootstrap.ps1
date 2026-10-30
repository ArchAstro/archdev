# Runs core and Tasks bootstrap against fake-archdev in isolated homes.
# Capability probes are allowed; no hook installation or refresh is allowed.
# test-skill-bootstrap-cli.sh proves explicit scope with the real CLI. The fake CLI is a Bash script;
# on Windows an archdev.cmd runs it through Git Bash, and the bootstrap runs
# under Windows PowerShell (`powershell -File`), as SKILL.md invokes it.

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ("archdev-bootstrap-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$failures = 0
$onWindows = $env:OS -eq "Windows_NT"

# Every variable a case may set; each case starts with all of them cleared.
$caseVariables = @(
    "CLAUDECODE", "CODEX_THREAD_ID", "GROK_SESSION_ID", "USERPROFILE",
    "ARCHDEV_FACTORY_AGENT_ROLE", "ARCHDEV_JOB_ID", "ARCHDEV_STEP_ID",
    "ARCHDEV_FAKE_SETUP_EXIT", "ARCHDEV_FAKE_LOG", "ARCHDEV_FAKE_INVOCATIONS", "ARCHDEV_FAKE_NO_LOCAL", "ARCHDEV_FAKE_NO_HEARTBEAT", "ARCHDEV_FAKE_NO_INBOX", "ARCHDEV_FAKE_VERBOSE_HELP", "ARCHDEV_FAKE_VERBOSE_VERSION", "ARCHDEV_FAKE_VERSION", "ARCHDEV_INSTALL_DIR"
)
$savedPath = $env:PATH
$savedHome = $env:HOME
$saved = @{}
foreach ($name in $caseVariables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }

function Invoke-Case {
    param(
        [string]$Name,
        [string]$Expected,
        [hashtable]$Environment = @{},
        [string]$Skill = "archdev",
        [bool]$ExpectFailure = $false
    )
    $caseDir = Join-Path $work $Name
    $homeDir = Join-Path $caseDir "home"
    $bin = Join-Path $caseDir "bin"
    $log = Join-Path $caseDir "setup.log"
    New-Item -ItemType Directory -Path $homeDir, $bin | Out-Null
    if ($onWindows) {
        $archdevPath = Join-Path $bin "archdev.cmd"
        $bash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
        Set-Content -LiteralPath $archdevPath -Value "@`"$bash`" `"$(Join-Path $repo 'scripts/fake-archdev')`" %*"
        $casePath = "$bin;$env:SystemRoot\System32;$env:SystemRoot"
        # Absolute: the case PATH below leaves out the PowerShell directory.
        $shell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    } else {
        $archdevPath = Join-Path $bin "archdev"
        Copy-Item (Join-Path $repo "scripts/fake-archdev") $archdevPath
        & chmod +x $archdevPath
        $casePath = "$bin`:/usr/bin:/bin"
        $shell = (Get-Process -Id $PID).Path
    }
    Set-Content -LiteralPath $log -Value $null -NoNewline

    foreach ($variable in $caseVariables) { Remove-Item "Env:$variable" -ErrorAction SilentlyContinue }
    $env:HOME = $homeDir
    if ($onWindows) { $env:USERPROFILE = $homeDir }
    $env:PATH = $casePath
    $env:ARCHDEV_FAKE_LOG = $log
    $env:ARCHDEV_FAKE_INVOCATIONS = Join-Path $caseDir "invocations.log"
    # Linux PowerShell has no LOCALAPPDATA; rejection tests must reach the
    # intercepted download, not fail while constructing a Windows default.
    $env:ARCHDEV_INSTALL_DIR = Join-Path $caseDir "install"
    foreach ($key in $Environment.Keys) { Set-Item "Env:$key" $Environment[$key] }
    # Intercept every installer download, including negative capability cases.
    $runner = Join-Path $caseDir "runner.ps1"
    $bootstrap = (Join-Path $repo "$Skill/scripts/bootstrap.ps1").Replace("'", "''")
    Set-Content -LiteralPath $runner -Value @"
`$ErrorActionPreference = 'Stop'
function global:Invoke-WebRequest { throw 'Blocked installer download in bootstrap fixture' }
try { & '$bootstrap' } catch {
    [Console]::Error.WriteLine(`$_.ToString())
    exit 1
}
exit 0
"@
    try {
        $out = & $shell -NoProfile -ExecutionPolicy Bypass -File $runner 2>(Join-Path $caseDir "stderr")
        $exit = $LASTEXITCODE
    } finally {
        $env:PATH = $savedPath
        $env:HOME = $savedHome
    }

    if ($ExpectFailure) {
        $errorText = Get-Content (Join-Path $caseDir "stderr") -Raw
        if ($exit -eq 0 -or @($out).Count -ne 0 -or (Get-Item $log).Length -ne 0 -or $errorText -notmatch 'Blocked installer download') {
            Write-Host "FAIL ${Name}: unsupported CLI accepted, wrote hooks, or escaped download interception (exit=$exit)"
            Write-Host $errorText
            $script:failures++
        } else { Write-Host "ok   $Name rejected without downloads or global fallback" }
        return
    }
    if ($exit -ne 0) {
        Write-Host "FAIL ${Name}: bootstrap exited $exit"
        Get-Content (Join-Path $caseDir "stderr") | Write-Host
        $script:failures++
        return
    }
    # Callers read stdout as the archdev path, so nothing else may reach it.
    if (@($out).Count -ne 1 -or @($out)[0] -ne $archdevPath) {
        Write-Host "FAIL ${Name}: bootstrap printed '$out', not the archdev path"
        $script:failures++
        return
    }
    if ($Skill -eq "archdev") {
        $calls = @(Get-Content -LiteralPath (Join-Path $caseDir "invocations.log"))
        if ($calls.Count -ne 7 -or @($calls | Select-Object -Unique).Count -ne 7) {
            Write-Host "FAIL ${Name}: healthy core bootstrap must probe version and six capabilities once"
            $script:failures++
            return
        }
    }
    $actual = (Get-Content -LiteralPath $log -Raw)
    $actual = if ($actual) { $actual.Trim() } else { "" }
    if ($actual -eq $Expected) {
        Write-Host "ok   $Name"
    } else {
        Write-Host "FAIL ${Name}`n  expected setup calls: '$Expected'`n  actual setup calls:   '$actual'"
        $script:failures++
    }
}

# Homebrew layouts (macOS and Linux only): <prefix>/Cellar/archdev/<v>/bin/archdev
# linked from <prefix>/bin/archdev, and scripts/fake-brew recording its calls.
# Bootstrap must repair that copy with brew and never install a second one.
function New-FakeArchDev([string]$Path, [string]$Version) {
    Set-Content -LiteralPath $Path -Value "#!/bin/sh`nARCHDEV_FAKE_VERSION=$Version exec `"$(Join-Path $repo 'scripts/fake-archdev')`" `"`$@`""
    & chmod +x $Path
}

function Invoke-BrewCase {
    param(
        [string]$Name,
        [string]$Skill,
        # An old keg is 0.49.0; every other keg is the formula's latest, 0.60.0,
        # so a `brew upgrade` of it changes nothing, as with real Homebrew.
        [ValidateSet("old", "stub", "crash", "version-error", "current", "missing", "none")][string]$Keg,
        [ValidateSet("yes", "no", "fail")][string]$Brew,
        [ValidateSet("none", "old", "current")][string]$Copy,
        # upgrade / reinstall: brew repairs the keg; current: used as is;
        # copy: the installer copy is used as is;
        # error: stops naming Homebrew; installer: reaches the pinned installer.
        [string]$Expect,
        [string]$ErrorText = "",
        # opt: PATH reaches the keg through Homebrew's opt link.
        # other-brew: another prefix's brew comes first on PATH.
        [ValidateSet("", "opt", "other-brew", "verbose")][string]$Variant = ""
    )
    $label = "brew $Skill-$Name"
    $caseDir = Join-Path $work "brew-$Skill-$Name"
    $homeDir = Join-Path $caseDir "home"
    $prefix = Join-Path $caseDir "homebrew"
    $prefixBin = Join-Path $prefix "bin"
    $brewLog = Join-Path $caseDir "brew.log"
    $setupLog = Join-Path $caseDir "setup.log"
    New-Item -ItemType Directory -Path $homeDir, $prefixBin | Out-Null
    Set-Content -LiteralPath $brewLog -Value $null -NoNewline
    Set-Content -LiteralPath $setupLog -Value $null -NoNewline
    $kegVersion = if ($Keg -eq "old") { "0.49.0" } else { "0.60.0" }
    if ($Keg -ne "none") {
        $kegBin = Join-Path $prefix "Cellar/archdev/$kegVersion/bin"
        New-Item -ItemType Directory -Path $kegBin, (Join-Path $prefix "opt") | Out-Null
        $kegArchDev = Join-Path $kegBin "archdev"
        switch ($Keg) {
            "old" { New-FakeArchDev $kegArchDev "0.49.5" }
            "current" { New-FakeArchDev $kegArchDev "0.49.6" }
            # The stub that replaced a real keg: a high version, no commands.
            "stub" { Set-Content -LiteralPath $kegArchDev -Value "#!/bin/sh`necho `"archdev 3.0.0`""; & chmod +x $kegArchDev }
            # A binary that crashes before it can report a version.
            "crash" { Set-Content -LiteralPath $kegArchDev -Value "#!/bin/sh`nexit 139"; & chmod +x $kegArchDev }
            "version-error" { Set-Content -LiteralPath $kegArchDev -Value "#!/bin/sh`necho 'archdev 0.60.0'`nexit 139"; & chmod +x $kegArchDev }
            "missing" { Remove-Item -LiteralPath (Join-Path $prefix "Cellar/archdev") -Recurse -Force }
        }
        & ln -s "../Cellar/archdev/$kegVersion/bin/archdev" (Join-Path $prefixBin "archdev")
        & ln -s "../Cellar/archdev/$kegVersion" (Join-Path $prefix "opt/archdev")
    }
    if ($Brew -ne "no") {
        Copy-Item (Join-Path $repo "scripts/fake-brew") (Join-Path $prefixBin "brew")
        & chmod +x (Join-Path $prefixBin "brew")
    }
    $casePath = "$prefixBin`:/usr/bin:/bin"
    $linked = Join-Path $prefixBin "archdev"
    $otherBrewLog = Join-Path $caseDir "other-brew.log"
    if ($Variant -eq "opt") {
        $casePath = "$(Join-Path $prefix 'opt/archdev/bin')`:$casePath"
        $linked = Join-Path $prefix "opt/archdev/bin/archdev"
    } elseif ($Variant -eq "other-brew") {
        $otherBin = Join-Path $caseDir "other-homebrew/bin"
        New-Item -ItemType Directory -Path $otherBin | Out-Null
        Set-Content -LiteralPath (Join-Path $otherBin "brew") -Value "#!/bin/sh`necho `"`$*`" >>'$otherBrewLog'`necho '$(Join-Path $caseDir "other-homebrew")'"
        & chmod +x (Join-Path $otherBin "brew")
        $casePath = "$otherBin`:$casePath"
    }
    if ($Copy -ne "none") {
        # A previous installer copy that comes first on PATH.
        $copyBin = Join-Path $homeDir ".local/bin"
        New-Item -ItemType Directory -Path $copyBin | Out-Null
        New-FakeArchDev (Join-Path $copyBin "archdev") $(if ($Copy -eq "old") { "0.49.5" } else { "0.49.6" })
        $casePath = "$copyBin`:$casePath"
    }
    $homeBefore = (Get-ChildItem -LiteralPath $homeDir -Recurse -File | ForEach-Object { "$($_.FullName) $((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join "`n"

    foreach ($variable in $caseVariables) { Remove-Item "Env:$variable" -ErrorAction SilentlyContinue }
    $env:HOME = $homeDir
    $env:PATH = $casePath
    $env:ARCHDEV_FAKE_LOG = $setupLog
    $env:ARCHDEV_FAKE_BIN = Join-Path $repo "scripts/fake-archdev"
    $env:FAKE_BREW_LOG = $brewLog
    $env:FAKE_BREW_PREFIX = $prefix
    $env:FAKE_BREW_EXIT = if ($Brew -eq "fail") { "1" } else { "0" }
    $env:ARCHDEV_FAKE_VERBOSE_VERSION = if ($Variant -eq "verbose") { "1" } else { "0" }
    $env:ARCHDEV_INSTALL_DIR = Join-Path $caseDir "install"
    $runner = Join-Path $caseDir "runner.ps1"
    $bootstrap = (Join-Path $repo "$Skill/scripts/bootstrap.ps1").Replace("'", "''")
    Set-Content -LiteralPath $runner -Value @"
`$ErrorActionPreference = 'Stop'
function global:Invoke-WebRequest { throw 'Blocked installer download in bootstrap fixture' }
try { & '$bootstrap' } catch {
    [Console]::Error.WriteLine(`$_.ToString())
    exit 1
}
exit 0
"@
    try {
        $out = & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $runner 2>(Join-Path $caseDir "stderr")
        $exit = $LASTEXITCODE
    } finally {
        $env:PATH = $savedPath
        $env:HOME = $savedHome
        foreach ($name in @("ARCHDEV_FAKE_BIN", "FAKE_BREW_LOG", "FAKE_BREW_PREFIX", "FAKE_BREW_EXIT", "ARCHDEV_FAKE_VERBOSE_VERSION")) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    }
    $errorText = Get-Content (Join-Path $caseDir "stderr") -Raw
    if (-not $errorText) { $errorText = "" }
    $brewCalls = @(Get-Content -LiteralPath $brewLog)
    $homeAfter = (Get-ChildItem -LiteralPath $homeDir -Recurse -File | ForEach-Object { "$($_.FullName) $((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join "`n"
    $problem = $null
    switch ($Expect) {
        { $_ -in "upgrade", "reinstall" } {
            if ($exit -ne 0) { $problem = "exited $exit" }
            elseif (@($out).Count -ne 1 -or @($out)[0] -ne $linked) { $problem = "printed '$out', not the Homebrew archdev" }
            elseif ($brewCalls -notcontains "$Expect archastro/tools/archdev") { $problem = "brew was not asked to ${Expect}: $($brewCalls -join '; ')" }
            elseif (-not $errorText.Contains("brew $Expect archastro/tools/archdev")) { $problem = "the brew command was not shown" }
            elseif ((& $linked --version) -ne "0.60.0") { $problem = "the Homebrew keg was not updated" }
            elseif ((Test-Path -LiteralPath $otherBrewLog) -and (Get-Item $otherBrewLog).Length -ne 0) { $problem = "ran another prefix's brew" }
        }
        { $_ -in "current", "copy" } {
            $want = if ($_ -eq "copy") { Join-Path $homeDir ".local/bin/archdev" } else { $linked }
            if ($exit -ne 0) { $problem = "exited $exit" }
            elseif (@($out).Count -ne 1 -or @($out)[0] -ne $want) { $problem = "printed '$out', not $want" }
            elseif ($brewCalls | Where-Object { $_ -match "^(upgrade|reinstall|install)" }) { $problem = "changed Homebrew: $($brewCalls -join '; ')" }
            elseif ($Expect -eq "current" -and $Copy -ne "none" -and -not $errorText.Contains("comes first on PATH")) { $problem = "did not say which copy it skipped" }
        }
        "error" {
            if ($exit -eq 0 -or @($out).Count -ne 0) { $problem = "continued without a working Homebrew copy" }
            elseif (-not $errorText.Contains($ErrorText)) { $problem = "error does not contain '$ErrorText'" }
        }
        "installer" {
            if ($exit -eq 0 -or -not $errorText.Contains("Blocked installer download")) { $problem = "did not use the pinned installer" }
            elseif ($brewCalls | Where-Object { $_ -match "^(upgrade|reinstall|install)" }) { $problem = "changed Homebrew: $($brewCalls -join '; ')" }
        }
    }
    if (-not $problem -and $Expect -ne "installer") {
        if ($errorText.Contains("Blocked installer download")) { $problem = "downloaded the installer for a second copy" }
        elseif ($homeAfter -ne $homeBefore) { $problem = "changed files under HOME" }
    }
    if (-not $problem -and (Get-Item $setupLog).Length -ne 0) { $problem = "wrote hooks" }
    if ($problem) {
        Write-Host "FAIL ${label}: $problem"
        Write-Host $errorText
        $script:failures++
    } else { Write-Host "ok   $label" }
}

try {
    if (-not $onWindows) {
        foreach ($skill in @("archdev", "tasks", "tasks-execute", "tasks-audit")) {
            Invoke-BrewCase "outdated" $skill -Keg old -Brew yes -Copy none -Expect upgrade
            # The incident: a stub reporting 3.0.0 passed the version check and
            # failed the capability probes, so `brew upgrade` would be a no-op.
            Invoke-BrewCase "verbose-old" $skill -Keg old -Brew yes -Copy none -Expect upgrade -Variant verbose
            Invoke-BrewCase "version-error" $skill -Keg version-error -Brew yes -Copy none -Expect reinstall
            Invoke-BrewCase "broken" $skill -Keg stub -Brew yes -Copy none -Expect reinstall
            Invoke-BrewCase "crash" $skill -Keg crash -Brew yes -Copy none -Expect reinstall
            Invoke-BrewCase "opt" $skill -Keg old -Brew yes -Copy none -Expect upgrade -Variant opt
            Invoke-BrewCase "other-brew" $skill -Keg old -Brew yes -Copy none -Expect upgrade -Variant other-brew
            Invoke-BrewCase "missing" $skill -Keg missing -Brew yes -Copy none -Expect reinstall
            Invoke-BrewCase "behind-copy" $skill -Keg old -Brew yes -Copy old -Expect upgrade
            Invoke-BrewCase "current-behind-copy" $skill -Keg current -Brew yes -Copy current -Expect current
            Invoke-BrewCase "current" $skill -Keg current -Brew yes -Copy none -Expect current
            Invoke-BrewCase "no-brew" $skill -Keg old -Brew no -Copy none -Expect error -ErrorText "is managed by Homebrew, but $(Join-Path $work "brew-$skill-no-brew/homebrew/bin/brew") is missing"
            Invoke-BrewCase "brew-fails" $skill -Keg old -Brew fail -Copy none -Expect error -ErrorText "brew upgrade archastro/tools/archdev failed"
            # Without a Homebrew keg, installer copies and fresh installs keep the
            # pinned installer, and brew is never asked to install anything.
            Invoke-BrewCase "installer-copy" $skill -Keg none -Brew yes -Copy old -Expect installer
            Invoke-BrewCase "working-installer-copy" $skill -Keg none -Brew yes -Copy current -Expect copy
            Invoke-BrewCase "nothing-installed-brew-yes" $skill -Keg none -Brew yes -Copy none -Expect installer
            Invoke-BrewCase "nothing-installed-brew-no" $skill -Keg none -Brew no -Copy none -Expect installer
        }
    }
    foreach ($skill in @("archdev", "tasks", "tasks-execute", "tasks-audit")) {
        Invoke-Case "$skill-claude" "" @{ CLAUDECODE = "1" } $skill
        Invoke-Case "$skill-codex" "" @{ CODEX_THREAD_ID = "019a-thread" } $skill
        Invoke-Case "$skill-grok" "" @{ GROK_SESSION_ID = "grok-session" } $skill
        Invoke-Case "$skill-claude-off" "" @{ CLAUDECODE = "0" } $skill
        Invoke-Case "$skill-factory" "" @{ CLAUDECODE = "1"; ARCHDEV_FACTORY_AGENT_ROLE = "worker" } $skill
        Invoke-Case "$skill-job" "" @{ CLAUDECODE = "1"; ARCHDEV_JOB_ID = "job-1" } $skill
        Invoke-Case "$skill-step" "" @{ CLAUDECODE = "1"; ARCHDEV_STEP_ID = "step-1" } $skill
        Invoke-Case "$skill-unknown" "" @{} $skill
        Invoke-Case "$skill-setup-would-fail" "" @{ CLAUDECODE = "1"; ARCHDEV_FAKE_SETUP_EXIT = "1" } $skill
        Invoke-Case "$skill-no-local" "" @{ ARCHDEV_FAKE_NO_LOCAL = "1" } $skill $true
        Invoke-Case "$skill-old-version" "" @{ ARCHDEV_FAKE_VERSION = "0.46.0" } $skill $true
    }
    Invoke-Case "archdev-verbose-version" "" @{ ARCHDEV_FAKE_VERBOSE_VERSION = "1" } "archdev"
    Invoke-Case "tasks-execute-no-heartbeat" "" @{ ARCHDEV_FAKE_NO_HEARTBEAT = "1" } "tasks-execute" $true
    Invoke-Case "tasks-audit-no-inbox" "" @{ ARCHDEV_FAKE_NO_INBOX = "1" } "tasks-audit" $true
} finally {
    foreach ($name in $caseVariables) {
        if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { Set-Item "Env:$name" $saved[$name] }
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
    Write-Host "$failures bootstrap case(s) failed"
    exit 1
}
Write-Host "All bootstrap cases passed"
# GitHub's PowerShell wrapper inherits LASTEXITCODE; negative cases must not
# turn a successful fixture suite into a failed job.
exit 0
