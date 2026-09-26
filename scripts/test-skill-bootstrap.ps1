# Runs archdev/scripts/bootstrap.ps1 against scripts/fake-archdev in a
# throwaway HOME for each case, and checks which `repo hook setup` call the
# bootstrap made for the harness that ran it. What those calls do to hook
# files is the CLI's job; scripts/test-skill-bootstrap-cli.sh checks that
# against a real archdev. The fake CLI is a Bash script;
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
    "ARCHDEV_FAKE_SETUP_EXIT", "ARCHDEV_FAKE_LOG"
)
$savedPath = $env:PATH
$savedHome = $env:HOME
$saved = @{}
foreach ($name in $caseVariables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }

function Invoke-Case {
    param(
        [string]$Name,
        [string]$Expected,
        [hashtable]$Environment = @{}
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
    foreach ($key in $Environment.Keys) { Set-Item "Env:$key" $Environment[$key] }
    try {
        $out = & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo "archdev/scripts/bootstrap.ps1") 2>(Join-Path $caseDir "stderr")
        $exit = $LASTEXITCODE
    } finally {
        $env:PATH = $savedPath
        $env:HOME = $savedHome
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

$install = { param($harness) "repo hook setup --harness $harness`nrepo hook setup --refresh" }
$refreshOnly = "repo hook setup --refresh"

try {
    # Each harness installs its own hooks, then every hooked harness refreshes.
    Invoke-Case "claude" (& $install "claude") @{ CLAUDECODE = "1" }
    Invoke-Case "codex" (& $install "codex") @{ CODEX_THREAD_ID = "019a-thread" }
    Invoke-Case "grok" (& $install "grok") @{ GROK_SESSION_ID = "grok-session" }
    # CLAUDECODE is a flag: only the value 1 marks Claude Code.
    Invoke-Case "claude-flag-off" $refreshOnly @{ CLAUDECODE = "0" }
    # Factory workers and daemon pipeline steps leave harness config to their
    # host, so only refresh.
    Invoke-Case "factory-worker" $refreshOnly @{ CLAUDECODE = "1"; ARCHDEV_FACTORY_AGENT_ROLE = "worker" }
    Invoke-Case "daemon-job" $refreshOnly @{ CLAUDECODE = "1"; ARCHDEV_JOB_ID = "job-1" }
    Invoke-Case "daemon-step" $refreshOnly @{ CLAUDECODE = "1"; ARCHDEV_STEP_ID = "step-1" }
    # No harness marker: nothing to install for, so only refresh.
    Invoke-Case "unknown-harness" $refreshOnly
    # A failing setup is reported but does not fail the bootstrap, and the
    # refresh still runs.
    Invoke-Case "setup-fails" (& $install "claude") @{ CLAUDECODE = "1"; ARCHDEV_FAKE_SETUP_EXIT = "1" }
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
