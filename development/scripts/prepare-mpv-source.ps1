[CmdletBinding()]
param(
    [string]$MpvSource,
    [string]$IntegrationSource,
    [string]$Destination,
    [string]$MpvRef = "70894ae0390cf20edac0e68de72ab26725520416"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
if (-not $MpvSource) {
    $MpvSource = Join-Path $repositoryRoot "sources/mpv"
}
if (-not $IntegrationSource) {
    $IntegrationSource = Join-Path $repositoryRoot "sources/mpv-omniphony-0.4.1-fel-beta.4"
}
if (-not $Destination) {
    $Destination = Join-Path $repositoryRoot "build/mpv-ispatial"
}

function Get-FullPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Invoke-Git([string[]]$Arguments) {
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git failed with exit code $LASTEXITCODE`: git $($Arguments -join ' ')"
    }
}

$mpvSourcePath = Get-FullPath $MpvSource
$integrationPath = Get-FullPath $IntegrationSource
$destinationPath = Get-FullPath $Destination
$destinationParent = Split-Path -Parent $destinationPath

if (-not (Test-Path -LiteralPath (Join-Path $mpvSourcePath ".git") -PathType Container)) {
    throw "MpvSource must be an unmodified full mpv Git clone: $mpvSourcePath"
}
if (-not (Test-Path -LiteralPath (Join-Path $integrationPath "patches-master") -PathType Container)) {
    throw "IntegrationSource does not contain patches-master/: $integrationPath"
}
if (-not (Test-Path -LiteralPath (Join-Path $integrationPath "patches-fel") -PathType Container)) {
    throw "IntegrationSource does not contain patches-fel/: $integrationPath"
}
if (Test-Path -LiteralPath $destinationPath) {
    throw "Destination already exists. Choose a new path or remove it explicitly: $destinationPath"
}

$sourceStatus = & git -C $mpvSourcePath status --porcelain
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect mpv source repository: $mpvSourcePath"
}
if ($sourceStatus) {
    throw "MpvSource must stay pristine; it currently has local changes: $mpvSourcePath"
}

& git -C $mpvSourcePath rev-parse --verify "$MpvRef`^{commit}" *> $null
if ($LASTEXITCODE -ne 0) {
    throw "The requested mpv revision is missing. Fetch it in the original clone first: $MpvRef"
}

New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
Invoke-Git @("clone", "--no-hardlinks", "--", $mpvSourcePath, $destinationPath)
Invoke-Git @("-C", $destinationPath, "checkout", "--detach", $MpvRef)

$patches = @()
$patches += Get-ChildItem -LiteralPath (Join-Path $integrationPath "patches-master") -Filter "*.patch" -File | Sort-Object Name
$patches += Get-ChildItem -LiteralPath (Join-Path $integrationPath "patches-fel") -Filter "*.patch" -File | Sort-Object Name
$patches += Get-ChildItem -LiteralPath (Join-Path $repositoryRoot "development/mpv") -Filter "*.patch" -File | Sort-Object Name

if ($patches.Count -eq 0) {
    throw "No patch files were found."
}

foreach ($patch in $patches) {
    Write-Host "Applying $($patch.Name)"
    Invoke-Git @("-C", $destinationPath, "apply", "--3way", "--whitespace=nowarn", "--", $patch.FullName)
}

Write-Host ""
Write-Host "Prepared patched mpv source: $destinationPath"
Write-Host "The original source directories were not modified."
Write-Host "Next: development/scripts/build-mpv-windows.ps1"
