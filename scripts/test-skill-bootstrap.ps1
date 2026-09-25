# Runs archdev/scripts/bootstrap.ps1 against scripts/fake-archdev in a
# throwaway HOME for each case, and checks which `repo hook setup` call the
# bootstrap made for the harness that ran it. Unix pwsh only: the fake CLI is
# a Bash script.

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ("archdev-bootstrap-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$failures = 0

# Every variable a case may set; each case starts with all of them cleared.
$caseVariables = @(
    "CLAUDECODE", "CODEX_THREAD_ID", "GROK_SESSION_ID", "CLAUDE_CONFIG_DIR",
    "CLAUDE_CODE_PLUGIN_CACHE_DIR", "CODEX_HOME", "GROK_HOME", "USERPROFILE",
    "ARCHDEV_FAKE_TRACK1", "ARCHDEV_FAKE_SETUP_EXIT", "ARCHDEV_FAKE_LOG"
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
        [scriptblock]$Prepare = $null
    )
    $caseDir = Join-Path $work $Name
    $homeDir = Join-Path $caseDir "home"
    $bin = Join-Path $caseDir "bin"
    $log = Join-Path $caseDir "setup.log"
    New-Item -ItemType Directory -Path $homeDir, $bin | Out-Null
    Copy-Item (Join-Path $repo "scripts/fake-archdev") (Join-Path $bin "archdev")
    & chmod +x (Join-Path $bin "archdev")
    Set-Content -LiteralPath $log -Value $null -NoNewline
    if ($Prepare) { & $Prepare $homeDir }

    foreach ($variable in $caseVariables) { Remove-Item "Env:$variable" -ErrorAction SilentlyContinue }
    $env:HOME = $homeDir
    $env:PATH = "$bin$([IO.Path]::PathSeparator)/usr/bin$([IO.Path]::PathSeparator)/bin"
    $env:ARCHDEV_FAKE_LOG = $log
    foreach ($key in $Environment.Keys) { Set-Item "Env:$key" $Environment[$key] }
    try {
        $pwsh = (Get-Process -Id $PID).Path
        $out = & $pwsh -NoProfile -File (Join-Path $repo "archdev/scripts/bootstrap.ps1") 2>(Join-Path $caseDir "stderr")
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
    if (@($out).Count -ne 1 -or @($out)[0] -ne (Join-Path $bin "archdev")) {
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

$claudeHooks = {
    param($homeDir)
    $dir = Join-Path $homeDir ".claude"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content (Join-Path $dir "settings.json") '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "archdev repo hook start --harness claude --spec 3"}]}]}}'
}
$claudeHooksElsewhere = {
    param($homeDir)
    & $claudeHooks $homeDir
    Move-Item (Join-Path $homeDir ".claude") (Join-Path $homeDir "claude-config")
}
$claudePlugin = {
    param($homeDir)
    $dir = Join-Path $homeDir ".claude/plugins"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content (Join-Path $dir "installed_plugins.json") '{"version": 2, "plugins": {"archdev@archastro": [{"scope": "user"}]}}'
}
$claudePluginDisabled = {
    param($homeDir)
    & $claudePlugin $homeDir
    Set-Content (Join-Path $homeDir ".claude/settings.json") '{"enabledPlugins": {"archdev@archastro": false}}'
}
$claudePluginProject = {
    param($homeDir)
    $dir = Join-Path $homeDir ".claude/plugins"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content (Join-Path $dir "installed_plugins.json") '{"version": 2, "plugins": {"archdev@archastro": [{"scope": "project", "projectPath": "/elsewhere"}]}}'
}
$foreignHooks = {
    param($homeDir)
    $dir = Join-Path $homeDir ".claude"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content (Join-Path $dir "settings.json") '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "my-wrapper archdev repo hook stop"}]}]}}'
}

try {
    Invoke-Case "claude-no-hooks" "repo hook setup --harness claude`nrepo hook setup --refresh" @{ CLAUDECODE = "1"; ARCHDEV_FAKE_TRACK1 = "1" }
    Invoke-Case "claude-foreign-hooks" "repo hook setup --harness claude`nrepo hook setup --refresh" @{ CLAUDECODE = "1"; ARCHDEV_FAKE_TRACK1 = "1" } $foreignHooks
    Invoke-Case "claude-hooks-present" "repo hook setup --refresh" @{ CLAUDECODE = "1"; ARCHDEV_FAKE_TRACK1 = "1" } $claudeHooks
    Invoke-Case "claude-config-dir" "repo hook setup --refresh" @{
        CLAUDECODE = "1"; ARCHDEV_FAKE_TRACK1 = "1"
        CLAUDE_CONFIG_DIR = (Join-Path $work "claude-config-dir/home/claude-config")
    } $claudeHooksElsewhere
    Invoke-Case "claude-plugin" "repo hook setup --refresh" @{ CLAUDECODE = "1"; ARCHDEV_FAKE_TRACK1 = "1" } $claudePlugin
    Invoke-Case "claude-plugin-disabled" "repo hook setup --harness claude`nrepo hook setup --refresh" @{ CLAUDECODE = "1"; ARCHDEV_FAKE_TRACK1 = "1" } $claudePluginDisabled
    Invoke-Case "claude-plugin-other-project" "repo hook setup --harness claude`nrepo hook setup --refresh" @{ CLAUDECODE = "1"; ARCHDEV_FAKE_TRACK1 = "1" } $claudePluginProject
    Invoke-Case "claude-opted-out-old-cli" "repo hook setup --refresh" @{ CLAUDECODE = "1" }
    Invoke-Case "codex-no-hooks" "repo hook setup --harness codex`nrepo hook setup --refresh" @{ CODEX_THREAD_ID = "019a-thread"; ARCHDEV_FAKE_TRACK1 = "1" }
    Invoke-Case "grok-no-hooks" "repo hook setup --harness grok`nrepo hook setup --refresh" @{ GROK_SESSION_ID = "grok-session"; ARCHDEV_FAKE_TRACK1 = "1" }
    Invoke-Case "unknown-harness" "repo hook setup --refresh" @{ ARCHDEV_FAKE_TRACK1 = "1" }
    Invoke-Case "setup-fails" "repo hook setup --harness claude`nrepo hook setup --refresh" @{ CLAUDECODE = "1"; ARCHDEV_FAKE_TRACK1 = "1"; ARCHDEV_FAKE_SETUP_EXIT = "1" }
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
