[CmdletBinding()]
param(
    [string]$PreparedRoot,
    [string]$OutputDirectory,
    [string]$RuntimeBase,
    [string]$RuntimeOutputDirectory,
    [string]$Cargo,
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))

function Resolve-RepositoryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $Path))
}

function Invoke-CargoChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    & $Cargo @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed"
    }
}

if (-not $PreparedRoot) {
    $PreparedRoot = Join-Path $repositoryRoot "build_temp/harletty-ddplus-fix"
} else {
    $PreparedRoot = Resolve-RepositoryPath $PreparedRoot
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot "distribution/harletty-bridge-v0.7.1-ddplus-atmos-fix-windows-x86_64"
} else {
    $OutputDirectory = Resolve-RepositoryPath $OutputDirectory
}
if (-not $RuntimeBase) {
    $RuntimeBase = Join-Path $repositoryRoot "distribution/mpv-omniphony-fel-windows-x86_64-ispatial"
} else {
    $RuntimeBase = Resolve-RepositoryPath $RuntimeBase
}
if (-not $RuntimeOutputDirectory) {
    $RuntimeOutputDirectory = Join-Path $repositoryRoot "distribution/mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix"
} else {
    $RuntimeOutputDirectory = Resolve-RepositoryPath $RuntimeOutputDirectory
}
if (-not $Cargo) {
    $cargoCommand = Get-Command cargo -ErrorAction Stop
    $Cargo = $cargoCommand.Source
} else {
    $Cargo = Resolve-RepositoryPath $Cargo
}

$manifest = Join-Path $PreparedRoot "harletty-bridge/Cargo.toml"
$omniphonyManifest = Join-Path $PreparedRoot "Omniphony/omniphony-renderer/Cargo.toml"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "Prepared Harletty manifest not found: $manifest"
}
if (-not (Test-Path -LiteralPath $Cargo -PathType Leaf)) {
    throw "cargo executable not found: $Cargo"
}
$cargoBin = Split-Path -Parent $Cargo
if (($env:PATH -split ";") -notcontains $cargoBin) {
    $env:PATH = "$cargoBin;$env:PATH"
}
if (-not (Test-Path -LiteralPath $omniphonyManifest -PathType Leaf)) {
    throw "Prepared Omniphony manifest not found: $omniphonyManifest"
}
if (-not (Test-Path -LiteralPath $RuntimeBase -PathType Container)) {
    throw "Base mpv runtime not found: $RuntimeBase"
}
foreach ($output in @($OutputDirectory, $RuntimeOutputDirectory)) {
    if (Test-Path -LiteralPath $output) {
        throw "Output already exists; choose a new output path or remove it explicitly: $output"
    }
}

& $Cargo --version
if ($LASTEXITCODE -ne 0) {
    throw "Unable to run cargo: $Cargo"
}

if (-not $SkipTests) {
    & $Cargo test --manifest-path $manifest --workspace -j 1
    if ($LASTEXITCODE -ne 0) {
        throw "Harletty workspace tests failed"
    }

    Invoke-CargoChecked -Arguments @(
        "test", "--manifest-path", $omniphonyManifest, "-p", "renderer", "gain_ramp"
    ) -Description "Omniphony gain-ramp tests"
    Invoke-CargoChecked -Arguments @(
        "test", "--manifest-path", $omniphonyManifest, "-p", "renderer", "spatial_renderer::tests"
    ) -Description "Omniphony spatial-renderer tests"
    Invoke-CargoChecked -Arguments @(
        "test", "--manifest-path", $omniphonyManifest, "-p", "renderer", "binaural::tests"
    ) -Description "Omniphony binaural tests"
    Invoke-CargoChecked -Arguments @(
        "test", "--manifest-path", $omniphonyManifest, "-p", "orender_engine", "--lib"
    ) -Description "Omniphony engine tests"
}

& $Cargo build --manifest-path $manifest --release -j 1
if ($LASTEXITCODE -ne 0) {
    throw "Harletty release build failed"
}

& $Cargo build --manifest-path $omniphonyManifest --release -p orender_ffi -j 1
if ($LASTEXITCODE -ne 0) {
    throw "Omniphony orender release build failed"
}

$builtDll = Join-Path $PreparedRoot "harletty-bridge/target/release/harletty_bridge.dll"
if (-not (Test-Path -LiteralPath $builtDll -PathType Leaf)) {
    throw "Built DLL not found: $builtDll"
}
$builtOrenderDll = Join-Path $PreparedRoot "Omniphony/omniphony-renderer/target/release/orender.dll"
if (-not (Test-Path -LiteralPath $builtOrenderDll -PathType Leaf)) {
    throw "Built orender DLL not found: $builtOrenderDll"
}

New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$outputDll = Join-Path $OutputDirectory "harletty_bridge.dll"
Copy-Item -LiteralPath $builtDll -Destination $outputDll
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $outputDll

New-Item -ItemType Directory -Path $RuntimeOutputDirectory | Out-Null
Get-ChildItem -LiteralPath $RuntimeBase -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $RuntimeOutputDirectory -Recurse
}
$runtimeOrenderDll = Join-Path $RuntimeOutputDirectory "orender.dll"
$runtimeBridgeDll = Join-Path $RuntimeOutputDirectory "harletty_bridge.dll"
Copy-Item -LiteralPath $builtOrenderDll -Destination $runtimeOrenderDll -Force
Copy-Item -LiteralPath $builtDll -Destination $runtimeBridgeDll -Force
$orenderHash = Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeOrenderDll

Write-Host "Built bridge: $outputDll"
Write-Host "SHA256: $($hash.Hash)"
Write-Host "Staged corrected mpv runtime: $RuntimeOutputDirectory"
Write-Host "orender.dll SHA256: $($orenderHash.Hash)"
