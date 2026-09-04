[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PreparedSource,

    [Parameter(Mandatory = $true)]
    [string]$DependencyPrefix,

    [Parameter(Mandatory = $true)]
    [string]$ToolchainBin,

    [Parameter(Mandatory = $true)]
    [string]$PkgConfig,

    [Parameter(Mandatory = $true)]
    [string]$RuntimeBase,

    [string]$BuildDirectory,
    [string]$OutputDirectory,
    [string]$Meson = "meson",
    [string[]]$AdditionalMesonOption = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))

function Get-FullPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Require-Path([string]$Path, [string]$Description, [string]$PathType = "Any") {
    if (-not (Test-Path -LiteralPath $Path -PathType $PathType)) {
        throw "$Description was not found: $Path"
    }
}

function Invoke-CommandChecked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

$sourcePath = Get-FullPath $PreparedSource
$prefixPath = Get-FullPath $DependencyPrefix
$toolchainPath = Get-FullPath $ToolchainBin
$pkgConfigPath = Get-FullPath $PkgConfig
$runtimePath = Get-FullPath $RuntimeBase

if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $repositoryRoot "build/mpv-windows-ucrt"
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot "dist/mpv-omniphony-fel-windows-x86_64-ispatial"
}
$buildPath = Get-FullPath $BuildDirectory
$outputPath = Get-FullPath $OutputDirectory
$nativeFile = Join-Path $repositoryRoot "build/mpv-ucrt-native.ini"

Require-Path $sourcePath "Prepared mpv source" "Container"
Require-Path (Join-Path $sourcePath "meson.build") "mpv meson.build" "Leaf"
Require-Path $prefixPath "Dependency prefix" "Container"
Require-Path $toolchainPath "LLVM-MinGW bin directory" "Container"
Require-Path $pkgConfigPath "pkg-config executable" "Leaf"
Require-Path $runtimePath "Original upstream runtime directory" "Container"

$compiler = Join-Path $toolchainPath "x86_64-w64-mingw32-clang.exe"
$archiver = Join-Path $toolchainPath "x86_64-w64-mingw32-ar.exe"
$stripper = Join-Path $toolchainPath "x86_64-w64-mingw32-strip.exe"
$windres = Join-Path $toolchainPath "x86_64-w64-mingw32-windres.exe"
foreach ($tool in @($compiler, $archiver, $stripper, $windres)) {
    Require-Path $tool "Required UCRT toolchain executable" "Leaf"
}

if (Test-Path -LiteralPath $outputPath) {
    throw "OutputDirectory already exists. Remove it explicitly or choose another path: $outputPath"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $nativeFile) | Out-Null
$mesonPath = {
    param([string]$Path)
    return $Path.Replace("\", "/").Replace("'", "''")
}
$nativeText = @"
[binaries]
c = '$(& $mesonPath $compiler)'
ar = '$(& $mesonPath $archiver)'
strip = '$(& $mesonPath $stripper)'
pkg-config = '$(& $mesonPath $pkgConfigPath)'
windres = '$(& $mesonPath $windres)'
"@
[IO.File]::WriteAllText($nativeFile, $nativeText, [Text.UTF8Encoding]::new($false))

$oldPath = $env:PATH
$oldPkgConfigPath = $env:PKG_CONFIG_PATH
try {
    $env:PATH = "$(Join-Path $prefixPath 'bin');$toolchainPath;$oldPath"
    $pkgDirectory = Join-Path $prefixPath "lib/pkgconfig"
    if ($oldPkgConfigPath) {
        $env:PKG_CONFIG_PATH = "$pkgDirectory;$oldPkgConfigPath"
    } else {
        $env:PKG_CONFIG_PATH = $pkgDirectory
    }

    $setupArguments = @(
        "setup", $buildPath, $sourcePath,
        "--native-file=$nativeFile",
        "-Dbuildtype=release",
        "-Dlibmpv=false",
        "-Dorender=enabled",
        "-Dwasapi=enabled",
        "-Dd3d11=enabled",
        "-Dgl=disabled",
        "-Dvulkan=disabled",
        "-Dlua=lua52",
        "-Dlibavdevice=enabled",
        "-Dwin32-smtc=disabled",
        "-Dmanpage-build=disabled",
        "-Dhtml-build=disabled",
        "-Dpdf-build=disabled"
    )
    $setupArguments += $AdditionalMesonOption

    if (Test-Path -LiteralPath (Join-Path $buildPath "meson-private/coredata.dat")) {
        $setupArguments = @("setup", "--reconfigure", $buildPath, $sourcePath) + $setupArguments[3..($setupArguments.Count - 1)]
    }

    Invoke-CommandChecked $Meson $setupArguments
    Invoke-CommandChecked $Meson @("compile", "-C", $buildPath)
}
finally {
    $env:PATH = $oldPath
    $env:PKG_CONFIG_PATH = $oldPkgConfigPath
}

$builtExe = Join-Path $buildPath "mpv.exe"
$builtCom = Join-Path $buildPath "mpv.com"
Require-Path $builtExe "Built mpv.exe" "Leaf"
Require-Path $builtCom "Built mpv.com" "Leaf"

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
Copy-Item -Path (Join-Path $runtimePath "*") -Destination $outputPath -Recurse -Force
Copy-Item -LiteralPath $builtExe -Destination (Join-Path $outputPath "mpv.exe") -Force
Copy-Item -LiteralPath $builtCom -Destination (Join-Path $outputPath "mpv.com") -Force

Write-Host ""
Write-Host "Runnable package staged at: $outputPath"
Write-Host "The original files in releases/ were not modified."
