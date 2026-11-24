<#
Read-only freshness/integrity check for a separately produced backup manifest.
It does not connect to TiDB, create backups, verify age authentication, or test
restore. No scheduler or credentials are installed by this script.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $BackupDirectory,
    [ValidateRange(1, 720)]
    [int] $MaxAgeHours = 30,
    [ValidateRange(0, 60)]
    [int] $ClockSkewMinutes = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    if (-not [System.IO.Path]::IsPathRooted($BackupDirectory) -or $BackupDirectory.StartsWith('\\')) {
        throw 'Destino inválido.'
    }
    $directory = Get-Item -LiteralPath $BackupDirectory -Force
    if (-not $directory.PSIsContainer -or
        (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'Destino inválido.'
    }
    $manifestPath = Join-Path -Path $directory.FullName -ChildPath 'latest-success.json'
    $manifestItem = Get-Item -LiteralPath $manifestPath -Force
    if ($manifestItem.PSIsContainer -or $manifestItem.Length -gt 4096 -or
        (($manifestItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'Estado inválido.'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($required in @('format', 'status', 'fileName', 'sha256', 'snapshotAtEpochSeconds', 'completedAtEpochSeconds')) {
        if ($manifest.PSObject.Properties.Name -cnotcontains $required) { throw 'Estado incompleto.' }
    }
    if ($manifest.format -cne 'abigail-backup-manifest-v1' -or $manifest.status -cne 'complete' -or
        $manifest.fileName -isnot [string] -or
        $manifest.fileName -cnotmatch '^abigailovos_[0-9]{8}T[0-9]{6}Z_[0-9a-f]{32}\.age$' -or
        $manifest.sha256 -isnot [string] -or $manifest.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        ($manifest.completedAtEpochSeconds -isnot [int] -and $manifest.completedAtEpochSeconds -isnot [long]) -or
        ($manifest.snapshotAtEpochSeconds -isnot [int] -and $manifest.snapshotAtEpochSeconds -isnot [long])) {
        throw 'Estado inválido.'
    }

    $completed = [DateTimeOffset]::FromUnixTimeSeconds([long] $manifest.completedAtEpochSeconds)
    $snapshot = [DateTimeOffset]::FromUnixTimeSeconds([long] $manifest.snapshotAtEpochSeconds)
    $now = [DateTimeOffset]::UtcNow
    if ($completed -gt $now.AddMinutes($ClockSkewMinutes) -or $completed -lt $now.AddHours(-$MaxAgeHours) -or
        $snapshot -gt $completed.AddMinutes($ClockSkewMinutes) -or $snapshot -gt $now.AddMinutes($ClockSkewMinutes) -or
        $snapshot -lt $now.AddHours(-$MaxAgeHours)) {
        throw 'Cópia desatualizada ou relógio incorreto.'
    }

    $archivePath = Join-Path -Path $directory.FullName -ChildPath $manifest.fileName
    $archive = Get-Item -LiteralPath $archivePath -Force
    if ($archive.PSIsContainer -or $archive.Length -le 0 -or
        (($archive.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'Ficheiro inválido.'
    }
    $header = [System.Text.Encoding]::ASCII.GetBytes("age-encryption.org/v1`n")
    $actualHeader = New-Object byte[] $header.Length
    $stream = [System.IO.File]::OpenRead($archive.FullName)
    try { $read = $stream.Read($actualHeader, 0, $actualHeader.Length) } finally { $stream.Dispose() }
    if ($read -ne $header.Length -or
        [Convert]::ToBase64String($actualHeader) -cne [Convert]::ToBase64String($header)) {
        throw 'Formato inválido.'
    }
    $actualHash = (Get-FileHash -LiteralPath $archive.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne $manifest.sha256) { throw 'Integridade inválida.' }
    Write-Output 'Ficheiro recente e hash conferido. A autenticidade e o restauro continuam por verificar.'
    exit 0
} catch {
    # Do not print paths, personal data, credentials or provider output.
    [Console]::Error.WriteLine('ALERTA: não foi possível confirmar uma cópia recente e íntegra. Verifique o destino e o processo de backup.')
    exit 1
}
