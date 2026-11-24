<#
PREPARATION ONLY. Checks the separate manifest-based freshness checker and can
show a local interactive Windows alert on failure. No tasks are installed, no
backup is created, and a passing check does not verify source or restore.
Run -NoDialog only for synthetic automated tests; it cannot alert a person.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $BackupDirectory,
    [ValidateRange(1, 720)] [int] $MaxAgeHours = 30,
    [ValidateRange(10, 86400)] [int] $TimeoutSeconds = 600,
    [switch] $NoDialog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$checker = Join-Path $PSScriptRoot 'Test-BackupFreshness.ps1'
$needsAlert = $true
$process = $null

try {
    if (-not [System.IO.Path]::IsPathRooted($BackupDirectory) -or $BackupDirectory.StartsWith('\\') -or
        $BackupDirectory.Contains('"') -or $BackupDirectory.Contains("`r") -or $BackupDirectory.Contains("`n") -or
        $checker.Contains('"') -or $checker.EndsWith('\')) {
        throw 'Caminho inválido.'
    }
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $windowsPowerShell
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -BackupDirectory "{1}" -MaxAgeHours {2}' -f $checker, $BackupDirectory.TrimEnd('\'), $MaxAgeHours
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    $out = $process.StandardOutput.ReadToEndAsync()
    $err = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { throw 'Verificação excedeu o prazo.' }
    $needsAlert = $process.ExitCode -ne 0
} catch {
    # Missing files, an unavailable checker and timeouts all require attention.
    $needsAlert = $true
} finally {
    if ($null -ne $process) {
        try { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } catch {}
        $process.Dispose()
    }
}

if (-not $needsAlert) { exit 0 }
if (-not $NoDialog) {
    try {
        if (-not [Environment]::UserInteractive) { throw 'Não há sessão interativa.' }
        Add-Type -AssemblyName System.Windows.Forms
        [void] [System.Windows.Forms.MessageBox]::Show(
            'Não foi possível confirmar um ficheiro de cópia recente. Verifique a tarefa de cópia, a ligação e o destino. A existência de um ficheiro não confirma que o restauro funciona.',
            'AbigailOvos: verificar cópia de segurança',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
    } catch {
        [Console]::Error.WriteLine('ALERTA: não foi possível apresentar o aviso de cópia neste Windows.')
        exit 2
    }
}
exit 1
