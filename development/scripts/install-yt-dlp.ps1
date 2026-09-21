[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[System.Net.ServicePointManager]::SecurityProtocol =
    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

function Get-YtDlpVersion {
    param([Parameter(Mandatory)][string]$ExecutablePath)

    $versionOutput = & $ExecutablePath --version
    if ($LASTEXITCODE -ne 0 -or -not $versionOutput) {
        throw "yt-dlp could not be started after installation: $ExecutablePath"
    }
    return ($versionOutput | Select-Object -First 1)
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot 'distribution\tools\yt-dlp.exe'
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if ((Test-Path -LiteralPath $OutputPath -PathType Leaf) -and -not $Force) {
    $installedVersion = Get-YtDlpVersion -ExecutablePath $OutputPath
    Write-Host "yt-dlp is already installed: $OutputPath"
    Write-Host "Version: $installedVersion"
    Write-Host 'Run this script with -Force to replace it with the latest release.'
    exit 0
}

$headers = @{
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'mpv-omniphony-yt-dlp-installer'
}

Write-Host 'Reading the latest official yt-dlp release metadata...'
$release = Invoke-RestMethod `
    -Uri 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest' `
    -Headers $headers

$exeAsset = $release.assets | Where-Object { $_.name -eq 'yt-dlp.exe' } | Select-Object -First 1
$sumAsset = $release.assets | Where-Object { $_.name -eq 'SHA2-256SUMS' } | Select-Object -First 1
if (-not $exeAsset -or -not $sumAsset) {
    throw 'The official release does not contain yt-dlp.exe and SHA2-256SUMS.'
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$temporaryExe = [System.IO.Path]::GetTempFileName()

try {
    Write-Host "Downloading yt-dlp $($release.tag_name)..."
    Invoke-WebRequest -UseBasicParsing -Uri $exeAsset.browser_download_url `
        -Headers $headers -OutFile $temporaryExe
    $sumResponse = Invoke-WebRequest -UseBasicParsing `
        -Uri $sumAsset.browser_download_url -Headers $headers
    $sumText = if ($sumResponse.Content -is [byte[]]) {
        [System.Text.Encoding]::UTF8.GetString($sumResponse.Content)
    } else {
        [string]$sumResponse.Content
    }
    $sumLine = $sumText -split "`r?`n" |
        Where-Object { $_ -match '\s\*?yt-dlp\.exe\s*$' } |
        Select-Object -First 1
    if (-not $sumLine -or $sumLine -notmatch '^([0-9a-fA-F]{64})\s+\*?yt-dlp\.exe\s*$') {
        throw 'Could not find the yt-dlp.exe checksum in SHA2-256SUMS.'
    }

    $expectedHash = $Matches[1].ToUpperInvariant()
    $actualHash = (Get-FileHash -LiteralPath $temporaryExe -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "yt-dlp checksum mismatch. Expected $expectedHash but received $actualHash."
    }

    if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
        if (-not $Force) {
            throw "Output already exists: $OutputPath"
        }
        Copy-Item -LiteralPath $temporaryExe -Destination $OutputPath -Force
    } else {
        Copy-Item -LiteralPath $temporaryExe -Destination $OutputPath
    }

    $installedVersion = Get-YtDlpVersion -ExecutablePath $OutputPath
    Write-Host "Installed and SHA-256 verified: $OutputPath"
    Write-Host "Version: $installedVersion"
} finally {
    if (Test-Path -LiteralPath $temporaryExe -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryExe -Force
    }
}
