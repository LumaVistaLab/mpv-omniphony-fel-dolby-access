[CmdletBinding()]
param(
    [string]$HarlettySource,
    [string]$OmniphonySource,
    [string]$OutputRoot
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

function Get-RepositoryRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $repositoryPrefix = $repositoryRoot.TrimEnd("\", "/") + [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Output target must remain inside the repository so patches can be applied safely: $fullPath"
    }
    return $fullPath.Substring($repositoryPrefix.Length)
}

if (-not $HarlettySource) {
    $HarlettySource = Join-Path $repositoryRoot "sources/harletty-bridge-0.7.1"
} else {
    $HarlettySource = Resolve-RepositoryPath $HarlettySource
}
if (-not $OmniphonySource) {
    $OmniphonySource = Join-Path $repositoryRoot "sources/Omniphony-0.4.1"
} else {
    $OmniphonySource = Resolve-RepositoryPath $OmniphonySource
}
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repositoryRoot "build_temp/harletty-ddplus-fix"
} else {
    $OutputRoot = Resolve-RepositoryPath $OutputRoot
}

foreach ($source in @($HarlettySource, $OmniphonySource)) {
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Source directory not found: $source"
    }
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "Output already exists; choose a new -OutputRoot or remove it explicitly: $OutputRoot"
}

$harlettyTarget = Join-Path $OutputRoot "harletty-bridge"
$omniphonyTarget = Join-Path $OutputRoot "Omniphony"
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
Copy-Item -LiteralPath $HarlettySource -Destination $harlettyTarget -Recurse
Copy-Item -LiteralPath $OmniphonySource -Destination $omniphonyTarget -Recurse

$patchSets = @(
    [pscustomobject]@{
        Target = $harlettyTarget
        Patches = @(
            (Join-Path $repositoryRoot "development/harletty/0001-fix-eac3-joc-reconstruction.patch"),
            (Join-Path $repositoryRoot "development/harletty/0002-fix-eac3-oamd-rendering.patch")
        )
    },
    [pscustomobject]@{
        Target = $omniphonyTarget
        Patches = @(
            (Join-Path $repositoryRoot "development/omniphony/0001-fix-live-log-record-lifetime.patch"),
            (Join-Path $repositoryRoot "development/omniphony/0002-fix-spatial-metadata-timing-and-gain.patch")
        )
    }
)

foreach ($patchSet in $patchSets) {
    $targetRelative = Get-RepositoryRelativePath $patchSet.Target
    $targetRelative = $targetRelative.Replace("\", "/")
    foreach ($patch in $patchSet.Patches) {
        if (-not (Test-Path -LiteralPath $patch -PathType Leaf)) {
            throw "Patch not found: $patch"
        }
        Write-Host "Applying patch: $patch"
        & git -C $repositoryRoot apply --check --whitespace=error-all "--directory=$targetRelative" $patch
        if ($LASTEXITCODE -ne 0) {
            throw "Patch does not apply cleanly: $patch"
        }
        & git -C $repositoryRoot apply --whitespace=error-all "--directory=$targetRelative" $patch
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to apply patch: $patch"
        }
    }
}

Write-Host "Prepared Harletty source: $harlettyTarget"
Write-Host "Prepared Omniphony source: $omniphonyTarget"
