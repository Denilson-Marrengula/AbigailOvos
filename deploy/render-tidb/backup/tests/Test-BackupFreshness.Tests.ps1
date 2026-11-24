<# Synthetic fixtures only. This file has not been executed. #>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'opencode'
if (-not (Test-Path -LiteralPath $testRoot -PathType Container)) {
    throw 'A pasta temporária de teste deve existir antes da execução.'
}
$testDirectory = Join-Path $testRoot ('abigail-backup-test-' + [Guid]::NewGuid().ToString('N'))
$checker = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Test-BackupFreshness.ps1'))
$manifestPath = Join-Path $testDirectory 'latest-success.json'
$archiveName = 'abigailovos_20261114T000000Z_' + [Guid]::NewGuid().ToString('N') + '.age'
$archivePath = Join-Path $testDirectory $archiveName
$created = $false

function Assert-Status([bool] $shouldPass) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -BackupDirectory "{1}"' -f $checker, $testDirectory
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $null = $process.StandardOutput.ReadToEnd()
        $null = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if (($process.ExitCode -eq 0) -ne $shouldPass) { throw 'Resultado inesperado do verificador.' }
    } finally { $process.Dispose() }
}

try {
    if (Test-Path -LiteralPath $testDirectory) { throw 'Diretório de teste já existe.' }
    New-Item -ItemType Directory -Path $testDirectory | Out-Null
    $created = $true
    # This is deliberately not a real encrypted backup; the checker cannot prove restore.
    [System.IO.File]::WriteAllBytes($archivePath, [System.Text.Encoding]::ASCII.GetBytes("age-encryption.org/v1`nficcao"))
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $state = [ordered]@{
        format = 'abigail-backup-manifest-v1'
        status = 'complete'
        fileName = $archiveName
        sha256 = $hash
        snapshotAtEpochSeconds = $now
        completedAtEpochSeconds = $now
    }
    function Save-State { $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $manifestPath -Encoding UTF8 }
    Save-State
    Assert-Status $true
    $state.completedAtEpochSeconds = $now - (31 * 3600)
    Save-State
    Assert-Status $false
    $state.completedAtEpochSeconds = $now + 3600
    Save-State
    Assert-Status $false
    $state.completedAtEpochSeconds = $now
    $state.snapshotAtEpochSeconds = $now - (31 * 3600)
    Save-State
    Assert-Status $false
    $state.snapshotAtEpochSeconds = $now
    $state.sha256 = '0' * 64
    Save-State
    Assert-Status $false
    $state.sha256 = $hash
    $state.fileName = '..\outside.age'
    Save-State
    Assert-Status $false
    $state.fileName = $archiveName
    $state.status = 'running'
    Save-State
    Assert-Status $false
    Remove-Item -LiteralPath $manifestPath
    Assert-Status $false
    Write-Output 'Cenários sintéticos concluídos. Isto não testa cifra ou restauro.'
} finally {
    # Remove only the two files and directory created by this test; never recurse.
    if ($created) {
        if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath }
        if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath }
        if (Test-Path -LiteralPath $testDirectory) { Remove-Item -LiteralPath $testDirectory }
    }
}
