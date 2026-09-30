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
    "ARCHDEV_FAKE_SETUP_EXIT", "ARCHDEV_FAKE_LOG", "ARCHDEV_FAKE_NO_LOCAL", "ARCHDEV_FAKE_VERBOSE_HELP", "ARCHDEV_FAKE_VERSION", "ARCHDEV_INSTALL_DIR"
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
    $actual = (Get-Content -LiteralPath $log -Raw)
    $actual = if ($actual) { $actual.Trim() } else { "" }
    if ($actual -eq $Expected) {
        Write-Host "ok   $Name"
    } else {
        Write-Host "FAIL ${Name}`n  expected setup calls: '$Expected'`n  actual setup calls:   '$actual'"
        $script:failures++
    }
}

try {
    foreach ($skill in @("archdev", "tasks")) {
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
