[CmdletBinding()]
param(
    [string]$ToolchainBin,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$source = Join-Path $repositoryRoot "development/tools/ispatialaudio-probe.c"
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot "distribution/tools"
}
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)

if ($ToolchainBin) {
    $compiler = Join-Path ([IO.Path]::GetFullPath($ToolchainBin)) "x86_64-w64-mingw32-clang.exe"
} else {
    $compiler = "clang"
}

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
$output = Join-Path $outputPath "ispatialaudio-probe.exe"

& $compiler -std=c11 -O2 -Wall -Wextra -municode $source -o $output -lole32
if ($LASTEXITCODE -ne 0) {
    throw "Probe compilation failed with exit code $LASTEXITCODE"
}

Write-Host "Built: $output"
