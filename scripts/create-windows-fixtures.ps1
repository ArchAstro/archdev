param(
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [Parameter(Mandatory = $true)][string]$Version
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$Source = @"
using System;
public static class Program {
    public static void Main(string[] args) {
        if (args.Length > 0 && args[0] == "--version") Console.WriteLine("$Version");
    }
}
"@
$FixtureBinaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("archdev-fixture-bin-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $FixtureBinaryRoot | Out-Null
$FixtureBinary = Join-Path $FixtureBinaryRoot "archdev.exe"
Add-Type -TypeDefinition $Source -OutputAssembly $FixtureBinary -OutputType ConsoleApplication
foreach ($Arch in @("arm64", "x64")) {
    $Fixture = Join-Path ([IO.Path]::GetTempPath()) ("archdev-fixture-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $Fixture | Out-Null
    Copy-Item $FixtureBinary (Join-Path $Fixture "archdev.exe")
    Copy-Item (Join-Path $Fixture "archdev.exe") (Join-Path $Fixture "archdev-dashboard.exe")
    Compress-Archive -Path (Join-Path $Fixture "archdev.exe"), (Join-Path $Fixture "archdev-dashboard.exe") -DestinationPath (Join-Path $OutputDir "archdev-windows-$Arch.zip")
    Remove-Item $Fixture -Recurse -Force
}
Remove-Item $FixtureBinaryRoot -Recurse -Force
$Lines = Get-ChildItem $OutputDir -Filter "archdev-windows-*.zip" | ForEach-Object {
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
}
$Lines | Set-Content (Join-Path $OutputDir "SHA256SUMS")
