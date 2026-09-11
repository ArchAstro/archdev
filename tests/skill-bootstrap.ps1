$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$root = Join-Path ([IO.Path]::GetTempPath()) ('archdev-bootstrap-proof-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$previousInstallDir = $env:ARCHDEV_INSTALL_DIR
$previousInstallerUrl = $env:ARCHDEV_INSTALLER_URL
$previousReleaseUrl = $env:ARCHDEV_RELEASE_BASE_URL
try {
    # A runnable CLI fixture crosses the real PowerShell process boundary.
    $fixtureCli = Join-Path $root 'fixture.exe'
    $cliSource = @'
using System;
public static class Program {
    public static void Main(string[] args) {
        Console.WriteLine(args.Length == 1 && args[0] == "--version" ? "fixture" : "Usage: archdev " + string.Join(" ", args) + " --messages");
    }
}
'@
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        $source = Join-Path $root 'fixture.cs'
        Set-Content $source $cliSource
        $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        & $compiler /nologo /target:exe "/out:$fixtureCli" $source
        if ($LASTEXITCODE -ne 0) { throw 'Fixture compilation failed' }
    } else {
        [IO.File]::WriteAllText($fixtureCli, "#!/bin/sh`nprintf 'Usage: archdev %s --messages\n' `"`$*`"`n")
        & chmod +x $fixtureCli
    }
    $env:ARCHDEV_TEST_FIXTURE_CLI = $fixtureCli
    $env:ARCHDEV_TEST_EXECUTED = Join-Path $root 'executed'
    $payload = Join-Path $root 'payload.ps1'
    [IO.File]::WriteAllText($payload, @'
param([switch]$SkipPathUpdate, [switch]$SkipVerify, [string]$InstallDir, [string]$BaseUrl = $env:ARCHDEV_RELEASE_BASE_URL)
if ($BaseUrl -or $SkipVerify) { throw "Bootstrap must use official releases with verification enabled" }
Add-Content $env:ARCHDEV_TEST_EXECUTED 'executed'
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item $env:ARCHDEV_TEST_FIXTURE_CLI (Join-Path $InstallDir 'archdev.exe')
'@)
    $fixtureHash = (Get-FileHash $payload -Algorithm SHA256).Hash.ToLowerInvariant()
    $state = @{ downloads = 0; downloadPath = $null; existingCli = $null; failDownload = $false }
    function Get-Command {
        param([string]$Name, $ErrorAction)
        if ($Name -eq 'archdev') {
            if ($state.existingCli) { return [pscustomobject]@{ Source = $state.existingCli } }
            return $null
        }
        Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction $ErrorAction
    }
    function Invoke-WebRequest {
        param([string]$Uri, [string]$OutFile)
        if ($Uri -ne 'https://raw.githubusercontent.com/ArchAstro/archdev/9d50e7ce1e64a731d88cca8ae15ec2c45b1375df/install.ps1') {
            throw "Unexpected installer URL: $Uri"
        }
        $state.downloads++
        $state.downloadPath = $OutFile
        if ($state.failDownload) { throw "Fixture download failure" }
        Copy-Item $payload $OutFile
    }

    foreach ($skill in @('agents', 'inspect', 'jobs', 'rooms', 'tasks')) {
        $source = Join-Path $repo "skills/$skill/scripts/bootstrap.ps1"
        $copy = Join-Path $root "$skill.ps1"
        $original = Get-Content $source -Raw
        if ($original -notmatch '\$installerSha256 = "([a-f0-9]{64})"') { throw "Missing digest: $skill" }
        # Only this test copy trusts the fixture. Production has no hash/URL override.
        [IO.File]::WriteAllText($copy, $original.Replace($Matches[1], $fixtureHash))
        $env:ARCHDEV_INSTALL_DIR = Join-Path $root "$skill-bin"
        $env:ARCHDEV_INSTALLER_URL = 'https://untrusted.invalid/install.ps1'
        $env:ARCHDEV_RELEASE_BASE_URL = 'https://untrusted.invalid/releases'
        $state.existingCli = $null
        $before = $state.downloads
        $binary = & $copy
        if (-not (Test-Path $binary)) { throw "Missing installed CLI: $skill" }
        if ($state.downloads -ne $before + 1) { throw "Cold install did not download once: $skill" }
        if (Test-Path (Split-Path $state.downloadPath)) { throw "Leaked installer directory: $skill" }

        # A compatible installation avoids the network entirely.
        $state.existingCli = $binary
        $reused = & $copy
        if ($reused -ne $binary -or $state.downloads -ne $before + 1) { throw "Failed reuse: $skill" }

        # Untrusted bytes reach the downloader but must never execute.
        $state.existingCli = $null
        Remove-Item $env:ARCHDEV_TEST_EXECUTED -Force
        [IO.File]::WriteAllText($copy, $original)
        $rejected = $false
        try { & $copy | Out-Null } catch {
            if ($_.Exception.Message -notmatch 'SHA256 mismatch') { throw }
            $rejected = $true
        }
        if (-not $rejected -or (Test-Path $env:ARCHDEV_TEST_EXECUTED)) { throw "Untrusted installer executed: $skill" }
        if (Test-Path (Split-Path $state.downloadPath)) { throw "Leaked rejected installer: $skill" }
        # A download error must clean up and leave no executable side effect.
        $state.failDownload = $true
        $rejected = $false
        try { & $copy | Out-Null } catch {
            if ($_.Exception.Message -notmatch 'Fixture download failure') { throw }
            $rejected = $true
        }
        $state.failDownload = $false
        if (-not $rejected -or (Test-Path $env:ARCHDEV_TEST_EXECUTED)) { throw "Failed download executed: $skill" }
        if (Test-Path (Split-Path $state.downloadPath)) { throw "Leaked failed download: $skill" }
        Write-Host "PASS $skill verified install, existing CLI reuse, URL override ignored, tampering rejected, cleanup"
    }
} finally {
    $env:ARCHDEV_INSTALL_DIR = $previousInstallDir
    $env:ARCHDEV_INSTALLER_URL = $previousInstallerUrl
    $env:ARCHDEV_RELEASE_BASE_URL = $previousReleaseUrl
    Remove-Item Env:ARCHDEV_TEST_FIXTURE_CLI, Env:ARCHDEV_TEST_EXECUTED -ErrorAction SilentlyContinue
    Remove-Item $root -Recurse -Force
}
