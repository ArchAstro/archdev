# Canonical Windows proof: resolve the real executable, then configure only
# the approved placement and execute an installed callback through cmd.exe.
# Requires a compatible released CLI and Node on PATH; no native agent trust
# or browser sign-in is claimed by this process/configuration proof.
$ErrorActionPreference = "Stop"
if ($env:OS -ne "Windows_NT") { throw "This proof requires Windows" }
$repo = Split-Path -Parent $PSScriptRoot
$binary = (Get-Command archdev).Source
$node = (Get-Command node).Source
$work = Join-Path ([IO.Path]::GetTempPath()) ("archdev-cli-proof-" + [Guid]::NewGuid().ToString("N"))
$homeDir = Join-Path $work "home"
$checkout = Join-Path $work "checkout"
$nodeOnly = Join-Path $work "node-only"
$variables = @("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "PATH", "CLAUDECODE", "CODEX_THREAD_ID", "GROK_SESSION_ID", "GROK_HOOK_EVENT", "ARCHDEV_FACTORY_AGENT_ROLE", "ARCHDEV_JOB_ID", "ARCHDEV_STEP_ID")
$saved = @{}
foreach ($name in $variables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
function Assert-Proof([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Snapshot([string]$Root) {
    return ((Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length + 1)
        if ($relative -notmatch '^(\.archdev[\\/]logs|\.cache[\\/]archdev)[\\/]') {
            "$relative $((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
        }
    }) -join "`n")
}
function Invoke-Callback([string]$Command, [string]$Payload) {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $env:COMSPEC
    $start.Arguments = '/d /s /c "' + $Command + '"'
    $start.WorkingDirectory = $checkout
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($start)
    $process.StandardInput.Write($Payload)
    $process.StandardInput.Close()
    $output = $process.StandardOutput.ReadToEnd()
    $errors = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    Assert-Proof ($process.ExitCode -eq 0) "Callback failed: $errors"
    $process.Dispose()
    return $output
}
New-Item -ItemType Directory -Path (Join-Path $homeDir ".claude"), $checkout, $nodeOnly | Out-Null
Copy-Item -LiteralPath $node -Destination (Join-Path $nodeOnly "node.exe")
try {
    # Agent configuration is personal; prepare an isolated HOME and checkout,
    # retaining an unrelated existing hook to detect destructive setup.
    foreach ($name in $variables) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    $env:HOME = $homeDir
    $env:USERPROFILE = $homeDir
    $env:APPDATA = Join-Path $homeDir "AppData\Roaming"
    $env:LOCALAPPDATA = Join-Path $homeDir "AppData\Local"
    $env:PATH = "$nodeOnly;$(Split-Path -Parent $binary);$($saved['PATH'])"
    Set-Content -LiteralPath (Join-Path $homeDir ".claude\settings.json") -Encoding ASCII -Value '{"permissions":{"allow":["Read"]},"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo teammate"}]}]}}'
    New-Item -ItemType Directory -Path (Join-Path $homeDir '.config/archdev') | Out-Null
    Set-Content -LiteralPath (Join-Path $homeDir '.config/archdev/config.json') -Encoding ASCII -Value '{"defaultApp":"dap_033y70rWJriCRNyb9uL0Pm"}'
    Push-Location $checkout
    try {
        & git -c core.hooksPath=NUL -c init.templateDir= init --quiet
        Assert-Proof ($LASTEXITCODE -eq 0) "Git fixture initialization failed"
        $before = Snapshot $homeDir
        $projectBefore = Snapshot $checkout
        foreach ($skill in @("archdev", "tasks")) {
            $resolved = & (Join-Path $repo "$skill/scripts/bootstrap.ps1")
            Assert-Proof ($resolved -eq $binary) "Bootstrap did not resolve the installed binary"
        }
        foreach ($marker in @('CLAUDECODE', 'CODEX_THREAD_ID')) {
            Set-Item "Env:$marker" '1'
            try {
                & $binary auth status *> $null
                & $binary tasks guide *> $null
                Assert-Proof ($LASTEXITCODE -eq 0) "Tasks guide failed"
                Assert-Proof ((Snapshot $homeDir) -eq $before) "Ordinary commands changed personal configuration"
                Assert-Proof ((Snapshot $checkout) -eq $projectBefore) "Bootstrap changed repository configuration"
            } finally { Remove-Item "Env:$marker" }
        }

        # Explicit repository/reporting approval crosses the real CLI boundary.
        & $binary repo hook setup --local
        Assert-Proof ($LASTEXITCODE -eq 0) "Repository setup failed"
        Assert-Proof ((Snapshot $homeDir) -eq $before) "Repository setup changed personal configuration"
        foreach ($file in @('.claude/settings.json', '.codex/hooks.json', '.grok/hooks/archdev.json', '.pi/extensions/archdev.js', '.archdev/hooks.json')) {
            Assert-Proof (Test-Path (Join-Path $checkout $file)) "Missing shared hook $file"
        }
        $settings = Get-Content (Join-Path $checkout '.claude/settings.json') -Raw | ConvertFrom-Json
        $command = @($settings.hooks.SessionStart | ForEach-Object { $_.hooks } | Where-Object { $_.command -match 'archdev repo hook ' })[0].command
        $payload = @{ hook_event_name = 'SessionStart'; source = 'startup'; cwd = $checkout } | ConvertTo-Json -Compress
        Assert-Proof ((Invoke-Callback $command $payload) -match 'Load the `archdev` skill') "Installed callback did not delegate to the CLI"
        $personalBefore = Snapshot $homeDir
        $projectBefore = Snapshot $checkout
        $normalPath = $env:PATH
        try {
            $env:PATH = "$nodeOnly;$env:SystemRoot\System32;$env:SystemRoot"
            Assert-Proof ((Invoke-Callback $command $payload) -match 'https://archdev.ai/install.md') "Missing binary did not deliver guidance"
        } finally { $env:PATH = $normalPath }
        Assert-Proof ((Snapshot $homeDir) -eq $personalBefore) "Missing-binary callback changed configuration"
        Assert-Proof ((Snapshot $checkout) -eq $projectBefore) "Missing-binary callback changed repository files"

        # Machine-wide placement requires its own explicit action. Uninstall
        # followed by either skill bootstrap must retain the personal opt-out.
        & $binary repo hook setup
        Assert-Proof ($LASTEXITCODE -eq 0) "Personal setup failed"
        $personal = Get-Content (Join-Path $homeDir '.claude/settings.json') -Raw | ConvertFrom-Json
        Assert-Proof ($personal.permissions.allow -contains 'Read') "Unrelated permissions were lost"
        Assert-Proof (@($personal.hooks.SessionStart | ForEach-Object { $_.hooks.command }) -contains 'echo teammate') "Unrelated hook was lost"
        $commands = @($personal.hooks.SessionStart | ForEach-Object { $_.hooks.command })
        Assert-Proof (@($commands | Where-Object { $_ -match '^archdev repo hook start' }).Count -gt 0) "Personal setup did not install an ArchDev hook"
        & $binary repo hook setup --uninstall --harness claude
        Assert-Proof ($LASTEXITCODE -eq 0) "Uninstall failed"
        $removed = Get-Content (Join-Path $homeDir '.claude/settings.json') -Raw | ConvertFrom-Json
        Assert-Proof (@($removed.hooks.SessionStart | ForEach-Object { $_.hooks.command } | Where-Object { $_ -match '^archdev repo hook start' }).Count -eq 0) "Uninstall left an ArchDev hook"
        $optOut = Get-Content (Join-Path $homeDir '.archdev/hook-opt-out.json') -Raw | ConvertFrom-Json
        Assert-Proof ($optOut.harnesses -contains 'claude') "Uninstall did not record the opt-out"
        $uninstalled = Snapshot $homeDir
        foreach ($skill in @("archdev", "tasks")) { & (Join-Path $repo "$skill/scripts/bootstrap.ps1") | Out-Null }
        Assert-Proof ((Snapshot $homeDir) -eq $uninstalled) "Bootstrap cleared an opt-out"
        Assert-Proof ((Snapshot $checkout) -eq $projectBefore) "Personal setup changed repository files"
    } finally { Pop-Location }
    Write-Host "All Windows explicit-placement bootstrap CLI cases passed"
} finally {
    foreach ($name in $variables) {
        if ($null -eq $saved[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { Set-Item "Env:$name" $saved[$name] }
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
