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
    $BuildDirectory = Join-Path $repositoryRoot "build_temp/mpv-windows-ucrt"
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot "distribution/mpv-omniphony-fel-windows-x86_64-ispatial"
}
$buildPath = Get-FullPath $BuildDirectory
$outputPath = Get-FullPath $OutputDirectory
$nativeFile = Join-Path $repositoryRoot "build_temp/mpv-ucrt-native.ini"

Require-Path $sourcePath "Prepared mpv source" "Container"
Require-Path (Join-Path $sourcePath "meson.build") "mpv meson.build" "Leaf"
Require-Path $prefixPath "Dependency prefix" "Container"
Require-Path $toolchainPath "LLVM-MinGW bin directory" "Container"
Require-Path $pkgConfigPath "pkg-config executable" "Leaf"
Require-Path $runtimePath "Original upstream runtime directory" "Container"

$compiler = Join-Path $toolchainPath "x86_64-w64-mingw32-clang.exe"
$cppCompiler = Join-Path $toolchainPath "x86_64-w64-mingw32-clang++.exe"
$archiver = Join-Path $toolchainPath "x86_64-w64-mingw32-ar.exe"
$stripper = Join-Path $toolchainPath "x86_64-w64-mingw32-strip.exe"
$windres = Join-Path $toolchainPath "x86_64-w64-mingw32-windres.exe"
$dlltool = Join-Path $toolchainPath "llvm-dlltool.exe"
$objdump = Join-Path $toolchainPath "llvm-objdump.exe"
foreach ($tool in @($compiler, $cppCompiler, $archiver, $stripper, $windres, $dlltool, $objdump)) {
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
cpp = '$(& $mesonPath $cppCompiler)'
ar = '$(& $mesonPath $archiver)'
strip = '$(& $mesonPath $stripper)'
pkg-config = '$(& $mesonPath $pkgConfigPath)'
windres = '$(& $mesonPath $windres)'
dlltool = '$(& $mesonPath $dlltool)'
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

    # The mpv FEL patch still compiles with an older libplacebo, but the actual
    # enhancement-layer handoff is guarded by PL_API_VER >= 367. Refuse to
    # produce a deceptively runnable base-layer-only build.
    $placeboConfig = Join-Path $prefixPath "include/libplacebo/config.h"
    Require-Path $placeboConfig "libplacebo public configuration header" "Leaf"
    $placeboApiMatch = [regex]::Match(
        [IO.File]::ReadAllText($placeboConfig),
        '(?m)^#define\s+PL_API_VER\s+(\d+)\s*$'
    )
    if (-not $placeboApiMatch.Success) {
        throw "Could not determine PL_API_VER from: $placeboConfig"
    }
    $placeboApi = [int]$placeboApiMatch.Groups[1].Value
    if ($placeboApi -lt 367) {
        throw "libplacebo API $placeboApi cannot render Dolby Vision FEL; API 367 or newer is required."
    }
    $placeboVersion = (& $pkgConfigPath --modversion libplacebo | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "pkg-config could not resolve libplacebo from: $pkgDirectory"
    }
    & $pkgConfigPath --exists dovi
    if ($LASTEXITCODE -ne 0) {
        throw "libdovi is required for Dolby Vision FEL reconstruction."
    }

    # A patched mpv without the matching FFmpeg splitter silently falls back to
    # the base layer. The target ffmpeg.exe is runnable for this native Windows
    # build, so verify the registered bitstream filters before configuring mpv.
    $ffmpeg = Join-Path $prefixPath "bin/ffmpeg.exe"
    Require-Path $ffmpeg "FFmpeg command-line executable" "Leaf"
    $bitstreamFilters = (& $ffmpeg -hide_banner -bsfs 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not query FFmpeg bitstream filters: $ffmpeg"
    }
    if ($bitstreamFilters -notmatch '(?m)^\s*dovi_split\s*$') {
        throw "FFmpeg does not provide the dovi_split bitstream filter required for single-track Profile 7 FEL."
    }
    Write-Host "Verified FEL dependencies: libplacebo $placeboVersion (API $placeboApi), libdovi, FFmpeg dovi_split."

    $setupArguments = @(
        "setup", $buildPath, $sourcePath,
        "--native-file=$nativeFile",
        "-Dbuildtype=release",
        "-Dlibmpv=false",
        "-Dorender=enabled",
        "-Dwasapi=enabled",
        "-Dasio=enabled",
        "-Dd3d11=enabled",
        "-Dgl=enabled",
        "-Dvulkan=enabled",
        "-Dcuda-hwaccel=enabled",
        "-Dlua=lua52",
        "-Dlibavdevice=enabled",
        "-Dlibbluray=enabled",
        "-Ddvdnav=enabled",
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

    # Several mpv options are feature groups rather than strict dependency
    # requirements. Meson can therefore accept "enabled" while omitting the
    # implementation when, for example, the Vulkan loader is installed but
    # its headers are missing. Gate the generated configuration before doing
    # the expensive compile so a reduced-capability package is never staged.
    $generatedConfig = Join-Path $buildPath "config.h"
    Require-Path $generatedConfig "Generated mpv feature configuration" "Leaf"
    $configText = [IO.File]::ReadAllText($generatedConfig)
    $requiredFeatureDefines = @(
        "HAVE_ASIO",
        "HAVE_CUDA_HWACCEL",
        "HAVE_CUDA_INTEROP",
        "HAVE_D3D11",
        "HAVE_DVDNAV",
        "HAVE_GL",
        "HAVE_GL_WIN32",
        "HAVE_LIBBLURAY",
        "HAVE_LIBPLACEBO",
        "HAVE_ORENDER",
        "HAVE_VULKAN",
        "HAVE_WASAPI",
        "HAVE_WASAPI_SPATIAL"
    )
    $missingFeatures = @(
        $requiredFeatureDefines | Where-Object {
            $configText -notmatch "(?m)^#define\s+$([regex]::Escape($_))\s+1\s*$"
        }
    )
    if ($missingFeatures.Count -gt 0) {
        throw "Meson omitted required mpv features: $($missingFeatures -join ', ')"
    }
    Write-Host "Verified required mpv features: $($requiredFeatureDefines -join ', ')."

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
Get-ChildItem -LiteralPath $runtimePath -Force |
    Where-Object { $_.Name -notlike "README*" } |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $outputPath -Recurse -Force
    }
Copy-Item -LiteralPath $builtExe -Destination (Join-Path $outputPath "mpv.exe") -Force
Copy-Item -LiteralPath $builtCom -Destination (Join-Path $outputPath "mpv.com") -Force
$runtimeTools = Join-Path $outputPath "tools"
New-Item -ItemType Directory -Force -Path $runtimeTools | Out-Null
Copy-Item -LiteralPath (Join-Path $sourcePath "player/lua/ytdl_hook.lua") `
    -Destination (Join-Path $runtimeTools "ytdl_hook.lua") -Force

# Bundle the complete non-system DLL graph from the dependency prefix. Copying
# only mpv.exe on top of an older runtime can leave ABI-mismatched FFmpeg or
# libplacebo DLLs, while copying every prefix DLL adds unrelated toolchain data.
$runtimeBin = Join-Path $prefixPath "bin"
$dependencyQueue = [Collections.Generic.Queue[string]]::new()
foreach ($rootName in @("mpv.exe", "orender.dll", "harletty_bridge.dll")) {
    $rootBinary = Join-Path $outputPath $rootName
    if (Test-Path -LiteralPath $rootBinary -PathType Leaf) {
        $dependencyQueue.Enqueue($rootBinary)
    }
}
$scannedBinaries = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$bundledDlls = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
while ($dependencyQueue.Count -gt 0) {
    $binary = $dependencyQueue.Dequeue()
    if (-not $scannedBinaries.Add([IO.Path]::GetFullPath($binary))) {
        continue
    }

    $headers = (& $objdump -p $binary 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect runtime dependencies: $binary"
    }
    foreach ($match in [regex]::Matches($headers, '(?m)^\s*DLL Name:\s*(\S+)\s*$')) {
        $dllName = $match.Groups[1].Value
        $prefixDll = Join-Path $runtimeBin $dllName
        $outputDll = Join-Path $outputPath $dllName
        if (Test-Path -LiteralPath $prefixDll -PathType Leaf) {
            Copy-Item -LiteralPath $prefixDll -Destination $outputDll -Force
            [void]$bundledDlls.Add($dllName)
            $dependencyQueue.Enqueue($outputDll)
        } elseif (Test-Path -LiteralPath $outputDll -PathType Leaf) {
            $dependencyQueue.Enqueue($outputDll)
        }
    }
}

$mpvImports = (& $objdump -p (Join-Path $outputPath "mpv.exe") 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or
    $mpvImports -notmatch "(?m)^\s*DLL Name:\s*libplacebo-$placeboApi\.dll\s*$") {
    throw "Built mpv does not import the verified libplacebo API $placeboApi runtime."
}

$runtimeVersion = (& (Join-Path $outputPath "mpv.com") --no-config --version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw "The staged mpv runtime failed its startup smoke test."
}
if ($runtimeVersion -notmatch "libplacebo version:\s+v?7\.$placeboApi\.") {
    throw "The staged runtime did not load libplacebo API $placeboApi."
}

Write-Host ""
Write-Host "Runnable package staged at: $outputPath"
Write-Host "Bundled dependency DLLs from prefix: $($bundledDlls.Count)"
Write-Host "Verified runtime libplacebo API: $placeboApi"
Write-Host "The original files in releases/ were not modified."
