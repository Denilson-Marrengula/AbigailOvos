<# Synthetic files only; -NoDialog verifies status, not delivery of a Windows alert. #>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$parent = Join-Path ([System.IO.Path]::GetTempPath()) 'opencode'
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Pasta temporária indisponível.' }
$root = Join-Path $parent ('abigail-alert-test-' + [Guid]::NewGuid().ToString('N'))
$manifestPath = Join-Path $root 'latest-success.json'
$fileName = 'abigailovos_20261115T000000Z_' + [Guid]::NewGuid().ToString('N') + '.age'
$archivePath = Join-Path $root $fileName
$monitor = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Show-BackupAlert.ps1'))
$created = $false

function Check-Status([bool] $expectedPass) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -BackupDirectory "{1}" -NoDialog' -f $monitor, $root
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $out = $process.StandardOutput.ReadToEndAsync()
        $err = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Teste excedeu o prazo.' }
        if (($process.ExitCode -eq 0) -ne $expectedPass) { throw 'Estado inesperado do alerta.' }
    } finally { $process.Dispose() }
}

try {
    if (Test-Path -LiteralPath $root) { throw 'Diretório de teste já existe.' }
    New-Item -ItemType Directory -Path $root | Out-Null
    $created = $true
    Check-Status $false
    # Deliberately not an actual age archive; validates only checker plumbing.
    [System.IO.File]::WriteAllBytes($archivePath, [System.Text.Encoding]::ASCII.GetBytes("age-encryption.org/v1`nficcao"))
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $state = [ordered]@{
        format = 'abigail-backup-manifest-v1'
        status = 'complete'
        fileName = $fileName
        sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        snapshotAtEpochSeconds = $now
        completedAtEpochSeconds = $now
    }
    $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Check-Status $true
    $state.snapshotAtEpochSeconds = $now - (31 * 3600)
    $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Check-Status $false
    Write-Output 'Estados sintéticos preparados; a apresentação da janela ainda requer validação interativa.'
} finally {
    if ($created) {
        foreach ($path in @($manifestPath, $archivePath)) {
            if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path }
        }
        if (Test-Path -LiteralPath $root -PathType Container) { Remove-Item -LiteralPath $root }
    }
}
