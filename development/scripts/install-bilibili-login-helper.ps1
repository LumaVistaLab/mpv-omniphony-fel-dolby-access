[CmdletBinding()]
param(
    [string]$Python = 'python',
    [string]$OutputDirectory,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot 'distribution\tools\python-qrcode'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$modulePath = Join-Path $OutputDirectory 'qrcode\__init__.py'

if ((Test-Path -LiteralPath $modulePath -PathType Leaf) -and -not $Force) {
    Write-Host "Bilibili QR login dependency is already installed: $OutputDirectory"
    exit 0
}

if ((Test-Path -LiteralPath $OutputDirectory) -and $Force) {
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Write-Host 'Installing the pure-Python qrcode 8.2 runtime...'
& $Python -m pip install `
    --disable-pip-version-check `
    --no-deps `
    --target $OutputDirectory `
    'qrcode==8.2'
if ($LASTEXITCODE -ne 0) {
    throw "qrcode installation failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "qrcode was not installed at the expected path: $modulePath"
}

Write-Host "Installed Bilibili QR login dependency: $OutputDirectory"
