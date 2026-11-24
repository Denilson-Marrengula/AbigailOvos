<# Invented local fixtures only. Does not connect to TiDB or validate a backup. #>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tempParent = Join-Path ([System.IO.Path]::GetTempPath()) 'opencode'
if (-not (Test-Path -LiteralPath $tempParent -PathType Container)) { throw 'Pasta temporária indisponível.' }
$root = Join-Path $tempParent ('abigail-inventory-test-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'exportacao-ficticia'
$nested = Join-Path $source 'partes'
$emptyDir = Join-Path $root 'diretorio-vazio'
$junction = Join-Path $source 'ligacao'
$manifestPath = Join-Path $root 'inventario-ficticio.json'
$schema = Join-Path $source 'schema.sql'
$empty = Join-Path $source 'vazio.sql'
$chunk = Join-Path $nested 'dados.000.sql'
$checker = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Test-SyntheticExportInventory.ps1'))
$created = $false

function Save-Manifest([object[]] $Files) {
    [ordered]@{ format = 'synthetic-export-inventory-v1'; files = @($Files) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

function Assert-Status([bool] $ShouldPass, [bool] $ConfirmSynthetic = $true) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ExportDirectory "{1}" -ManifestPath "{2}"' -f $checker, $source, $manifestPath
    if ($ConfirmSynthetic) { $info.Arguments += ' -SyntheticDataOnly' }
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Teste excedeu o prazo.' }
        if (($process.ExitCode -eq 0) -ne $ShouldPass) { throw 'Resultado inesperado da comparação.' }
    } finally { $process.Dispose() }
}

try {
    if (Test-Path -LiteralPath $root) { throw 'Diretório de teste já existe.' }
    New-Item -ItemType Directory -Path $root | Out-Null
    $created = $true
    New-Item -ItemType Directory -Path $source, $nested, $emptyDir | Out-Null
    [System.IO.File]::WriteAllText($schema, 'ABCD', [System.Text.Encoding]::ASCII)
    [System.IO.File]::WriteAllBytes($empty, [byte[]]@())
    [System.IO.File]::WriteAllText($chunk, '12345', [System.Text.Encoding]::ASCII)
    $files = @(
        @{ name = 'schema.sql'; size = 4 },
        @{ name = 'vazio.sql'; size = 0 },
        @{ name = 'partes/dados.000.sql'; size = 5 }
    )
    Save-Manifest $files
    Assert-Status $true
    Assert-Status $false $false

    # Identical length is not a content-integrity check: this must still pass.
    [System.IO.File]::WriteAllText($schema, 'WXYZ', [System.Text.Encoding]::ASCII)
    Assert-Status $true

    # An empty junction would not change the filenames, but must still be refused.
    New-Item -ItemType Junction -Path $junction -Target $emptyDir | Out-Null
    if (((Get-Item -LiteralPath $junction -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
        throw 'A ligação de teste não foi criada como esperado.'
    }
    Assert-Status $false
    [System.IO.Directory]::Delete($junction)
    Assert-Status $true

    Save-Manifest @($files[0], $files[1])
    Assert-Status $false # unexpected local file
    Save-Manifest @($files + @{ name = 'em-falta.sql'; size = 1 })
    Assert-Status $false # missing local file
    Save-Manifest @(@{ name = 'schema.sql'; size = 3 }, $files[1], $files[2])
    Assert-Status $false # truncated or differently sized
    Save-Manifest @($files + @{ name = 'SCHEMA.SQL'; size = 4 })
    Assert-Status $false # collision on typical Windows filesystems
    Save-Manifest @(@{ name = '../schema.sql'; size = 4 })
    Assert-Status $false
    Save-Manifest @(@{ name = 'partes\dados.000.sql'; size = 5 })
    Assert-Status $false
    Save-Manifest @(@{ name = 'NUL.sql'; size = 0 })
    Assert-Status $false
    Save-Manifest @(@{ name = 'schema.sql'; size = -1 })
    Assert-Status $false
    Save-Manifest @(@{ name = 'schema.sql'; size = '4' })
    Assert-Status $false
    Save-Manifest @(@{ name = 'schema.sql'; size = 4; url = 'inventado' })
    Assert-Status $false # live provider URLs are not accepted as input
    Save-Manifest @()
    Assert-Status $false
    if (Test-Path -LiteralPath (Join-Path $root 'latest-success.json')) { throw 'Não deve criar manifesto de sucesso.' }
    Write-Output 'Cenários de inventário fictício concluídos. Tamanhos iguais não provam integridade ou restauro.'
} finally {
    # Remove only fixtures created by this invocation; never recurse.
    if ($created) {
        if (Test-Path -LiteralPath $junction) {
            $item = Get-Item -LiteralPath $junction -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                throw 'Ligação de teste alterada; limpeza interrompida.'
            }
            [System.IO.Directory]::Delete($junction)
        }
        foreach ($path in @($manifestPath, $schema, $empty, $chunk)) {
            if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path }
        }
        foreach ($path in @($nested, $source, $emptyDir, $root)) {
            if (Test-Path -LiteralPath $path -PathType Container) { Remove-Item -LiteralPath $path }
        }
    }
}
