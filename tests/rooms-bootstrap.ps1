$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('rooms-bootstrap-' + [Guid]::NewGuid().ToString('N'))
$sourceBootstrap = Join-Path $PSScriptRoot '../skills/rooms/scripts/bootstrap.ps1'
$bootstrap = Join-Path $root 'bootstrap.ps1'
$originalPath = $env:PATH
$originalInstallDir = $env:ARCHDEV_INSTALL_DIR
$originalReleaseUrl = $env:ARCHDEV_RELEASE_BASE_URL
New-Item -ItemType Directory $root | Out-Null

try {
    # Native process fixture: lifecycle-only releases and Knowledge releases
    # both exit successfully for help; only the latter exposes --messages.
    foreach ($kind in @('old', 'current')) {
        $dir = Join-Path $root $kind
        New-Item -ItemType Directory $dir | Out-Null
        $binary = Join-Path $dir 'archdev.exe'
        $searchHelp = if ($kind -eq 'current') { '--messages' } else { 'Usage: archdev rooms search <query>' }
        if ($env:OS -eq 'Windows_NT') {
            $source = @"
using System;
class Program {
    static int Main(string[] args) {
        string command = String.Join(" ", args);
        if (command == "--version") { Console.WriteLine("fixture"); return 0; }
        if (command == "rooms start --help") return 0;
        if (command == "rooms search --help") { Console.WriteLine("$searchHelp"); return 0; }
        return 2;
    }
}
"@
            $sourcePath = Join-Path $dir 'Program.cs'
            Set-Content $sourcePath $source
            $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
            & $compiler /nologo /target:exe "/out:$binary" $sourcePath
            if ($LASTEXITCODE -ne 0) { throw 'Fixture compilation failed' }
        } else {
            Set-Content $binary @"
#!/bin/sh
case "`$*" in
  '--version') echo fixture;;
  'rooms start --help') exit 0;;
  'rooms search --help') echo '$searchHelp';;
  *) exit 2;;
esac
"@
            & chmod +x $binary
            & ln -s $binary (Join-Path $dir 'archdev')
        }
    }

    # Replace only the installer-download boundary; the actual bootstrap runs
    # the downloaded script and invokes the exact returned native executable.
    $fixture = @{ Binary = (Join-Path $root 'current/archdev.exe'); Downloads = 0 }
    $payload = Join-Path $root 'installer.ps1'
    function Set-InstallerFixture {
        Set-Content $payload @"
param([switch]`$SkipPathUpdate, [switch]`$SkipVerify, [string]`$InstallDir, [string]`$BaseUrl = `$env:ARCHDEV_RELEASE_BASE_URL)
if (`$BaseUrl -or `$SkipVerify) { throw 'Bootstrap must use official releases with verification enabled' }
New-Item -ItemType Directory `$InstallDir -Force | Out-Null
Copy-Item '$($fixture.Binary)' (Join-Path `$InstallDir 'archdev.exe') -Force
"@
        $original = Get-Content $sourceBootstrap -Raw
        if ($original -notmatch '\$installerSha256 = "([a-f0-9]{64})"') { throw 'Missing installer digest' }
        $fixtureHash = (Get-FileHash $payload -Algorithm SHA256).Hash.ToLowerInvariant()
        # Only the test copy trusts this fixture; production has no URL/hash override.
        [IO.File]::WriteAllText($bootstrap, $original.Replace($Matches[1], $fixtureHash))
    }
    function Invoke-WebRequest($Uri, $OutFile) {
        if ($Uri -ne 'https://raw.githubusercontent.com/ArchAstro/archdev/9d50e7ce1e64a731d88cca8ae15ec2c45b1375df/install.ps1') {
            throw "Unexpected installer URL: $Uri"
        }
        $fixture.Downloads++
        Copy-Item $payload $OutFile
    }
    Set-InstallerFixture
    $env:ARCHDEV_RELEASE_BASE_URL = 'https://untrusted.invalid/releases'
    $env:ARCHDEV_INSTALL_DIR = Join-Path $root 'installed'
    $env:PATH = (Join-Path $root 'old') + [IO.Path]::PathSeparator + $originalPath
    $result = & $bootstrap
    $expected = Join-Path $env:ARCHDEV_INSTALL_DIR 'archdev.exe'
    if ($result -ne $expected -or $fixture.Downloads -ne 1) {
        throw 'Bootstrap accepted a lifecycle-only CLI without upgrading Knowledge search'
    }

    # A current CLI needs no download; a still-incompatible installation fails
    # without returning a misleading usable path.
    $env:PATH = (Join-Path $root 'current') + [IO.Path]::PathSeparator + $originalPath
    $result = & $bootstrap
    $existingPath = (Get-Command archdev).Source
    if ($result -ne $existingPath -or $fixture.Downloads -ne 1) { throw 'Current CLI was unnecessarily installed' }
    $env:PATH = (Join-Path $root 'old') + [IO.Path]::PathSeparator + $originalPath
    $fixture.Binary = Join-Path $root 'old/archdev.exe'
    Set-InstallerFixture
    $failure = $null
    try { $result = & $bootstrap } catch { $failure = $_ }
    if (-not $failure -or "$failure" -notmatch 'Installed ArchDev does not provide') {
        throw 'Bootstrap did not reject an incompatible installer result'
    }
    Write-Output 'Rooms PowerShell bootstrap upgrades old CLI, reuses current CLI, and rejects incompatible installs.'
} finally {
    $env:PATH = $originalPath
    $env:ARCHDEV_INSTALL_DIR = $originalInstallDir
    $env:ARCHDEV_RELEASE_BASE_URL = $originalReleaseUrl
    Remove-Item $root -Recurse -Force
}
