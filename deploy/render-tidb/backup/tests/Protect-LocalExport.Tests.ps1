<#
Not executed. Requires preinstalled, independently verified age, age-keygen
and Windows-compatible tar. Only synthetic fixtures are created. The test
creates a synthetic private key; never supply or use a production key here.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $AgeExe,
    [Parameter(Mandatory = $true)] [string] $AgeSha256,
    [Parameter(Mandatory = $true)] [string] $AgeKeygenExe,
    [Parameter(Mandatory = $true)] [string] $AgeKeygenSha256,
    [Parameter(Mandatory = $true)] [string] $TarExe,
    [Parameter(Mandatory = $true)] [string] $TarSha256
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$parent = Join-Path ([System.IO.Path]::GetTempPath()) 'opencode'
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Pasta temporária indisponível.' }
$root = Join-Path $parent ('abigail-protect-test-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'exportacao ficticia'
$destination = Join-Path $root 'arquivos teste'
$restored = Join-Path $root 'restaurado teste'
$sourceFile = Join-Path $source 'dados.bin'
$restoredFile = Join-Path $restored 'dados.bin'
$key = Join-Path $root 'chave-teste.txt'
$tarArchive = Join-Path $root 'restauro-teste.tar'
$producer = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Protect-LocalExport.ps1'))
$archive = $null
$created = $false

function Invoke-Producer([string] $Recipient, [string] $Hash) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ExportDirectory "{1}" -BackupDirectory "{2}" -Recipient "{3}" -AgeExe "{4}" -AgeSha256 "{5}" -TarExe "{6}" -TarSha256 "{7}" -TimeoutSeconds 60 -SyntheticDataOnly' -f $producer, $source, $destination, $Recipient, $AgeExe, $Hash, $TarExe, $TarSha256
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $out = $process.StandardOutput.ReadToEndAsync()
        $err = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'Teste excedeu o prazo.' }
        return $process.ExitCode
    } finally { $process.Dispose() }
}

try {
    foreach ($tool in @(@($AgeExe, $AgeSha256), @($AgeKeygenExe, $AgeKeygenSha256), @($TarExe, $TarSha256))) {
        if ($tool[1] -cnotmatch '^[0-9a-f]{64}$' -or
            (Get-FileHash -LiteralPath $tool[0] -Algorithm SHA256).Hash.ToLowerInvariant() -cne $tool[1]) {
            throw 'Ferramenta não corresponde ao hash esperado.'
        }
    }
    if (Test-Path -LiteralPath $root) { throw 'Diretório de teste já existe.' }
    New-Item -ItemType Directory -Path $root | Out-Null
    $created = $true
    New-Item -ItemType Directory -Path $source, $destination, $restored | Out-Null
    [System.IO.File]::WriteAllBytes($sourceFile, [byte[]](0, 1, 10, 13, 127, 128, 255))
    & $AgeKeygenExe -o $key 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível criar chave sintética.' }
    $recipient = (& $AgeKeygenExe -y $key | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $recipient -cnotmatch '^age1[023456789acdefghjklmnpqrstuvwxyz]{58}$') {
        throw 'Destinatário sintético inválido.'
    }
    if ((Invoke-Producer $recipient ('0' * 64)) -eq 0) { throw 'Aceitou hash incorreto.' }
    if (@(Get-ChildItem -LiteralPath $destination -Filter '*.age').Count -ne 0) { throw 'Criou arquivo indevido.' }
    if ((Invoke-Producer $recipient $AgeSha256) -ne 0) { throw 'Falha na cifra de teste.' }
    $archives = @(Get-ChildItem -LiteralPath $destination -Filter '*.age')
    if ($archives.Count -ne 1) { throw 'Número de arquivos inesperado.' }
    $archive = $archives[0].FullName
    if (Test-Path -LiteralPath (Join-Path $destination 'latest-success.json')) { throw 'Não deve criar manifesto de sucesso.' }
    & $AgeExe --decrypt --identity $key --output $tarArchive $archive 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível decifrar o arquivo sintético.' }
    & $TarExe -xf $tarArchive -C $restored 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $restoredFile)) { throw 'Restauro sintético falhou.' }
    if ((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath $restoredFile -Algorithm SHA256).Hash) { throw 'Dados diferentes após restauro.' }
    Write-Output 'Cifra e restauro sintéticos concluídos. Isto não valida uma exportação TiDB.'
} finally {
    # Remove only named fixtures created inside this invocation, never recurse.
    if ($created) {
        foreach ($path in @($sourceFile, $restoredFile, $key, $tarArchive, $archive)) {
            if ($null -ne $path -and (Test-Path -LiteralPath $path -PathType Leaf)) { Remove-Item -LiteralPath $path }
        }
        foreach ($path in @($source, $destination, $restored, $root)) {
            if (Test-Path -LiteralPath $path -PathType Container) { Remove-Item -LiteralPath $path }
        }
    }
}
