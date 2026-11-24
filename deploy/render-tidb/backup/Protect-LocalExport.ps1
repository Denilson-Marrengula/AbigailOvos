<#
PREPARATION FOR SYNTHETIC DATA ONLY. Does not connect to TiDB, obtain a
snapshot, verify completeness, decrypt, restore, create a success manifest,
schedule a task or remove the input. Uses tar -> age through binary streams;
the already-downloaded input itself remains in plaintext. Do not use for real
data until staging protection, tools, export and restore have been validated.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $ExportDirectory,
    [Parameter(Mandatory = $true)] [string] $BackupDirectory,
    [Parameter(Mandatory = $true)] [string] $Recipient,
    [Parameter(Mandatory = $true)] [string] $AgeExe,
    [Parameter(Mandatory = $true)] [string] $AgeSha256,
    [Parameter(Mandatory = $true)] [string] $TarExe,
    [Parameter(Mandatory = $true)] [string] $TarSha256,
    [ValidateRange(10, 86400)] [int] $TimeoutSeconds = 3600,
    [Parameter(Mandatory = $true)] [switch] $SyntheticDataOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$age = $null
$tar = $null
$partialPath = $null

function Require-LocalPath([string] $Path) {
    if (-not [System.IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or
        $Path.Contains('"') -or $Path.Contains("`r") -or $Path.Contains("`n")) {
        throw 'Caminho inválido.'
    }
    return [System.IO.Path]::GetFullPath($Path)
}

function Require-NoReparseAncestors([string] $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    while ($null -ne $item) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Ligação ou ponto de montagem não permitido.'
        }
        $parent = [System.IO.Directory]::GetParent($item.FullName)
        if ($null -eq $parent) { break }
        $item = Get-Item -LiteralPath $parent.FullName -Force
    }
}

function Require-TrustedExe([string] $Path, [string] $Expected) {
    $full = Require-LocalPath $Path
    if ($Expected -cnotmatch '^[0-9a-f]{64}$') { throw 'Hash inválido.' }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.PSIsContainer) { throw 'Ferramenta inválida.' }
    Require-NoReparseAncestors $full
    if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Expected) {
        throw 'Ferramenta diferente da esperada.'
    }
    return $full
}

function Quote-WindowsPath([string] $Path) {
    # All paths passed here are absolute, cannot contain a quote and do not end
    # with a backslash. This avoids Windows command-line quoting ambiguity.
    if ($Path.Contains('"') -or $Path.EndsWith('\')) { throw 'Caminho inválido.' }
    return '"' + $Path + '"'
}

function New-ProcessInfo([string] $Exe, [string] $Arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Exe
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardError = $true
    return $info
}

try {
    if (-not $SyntheticDataOnly) { throw 'Apenas dados fictícios.' }
    if ($Recipient -cnotmatch '^age1[023456789acdefghjklmnpqrstuvwxyz]{58}$') { throw 'Destinatário inválido.' }
    $source = (Require-LocalPath $ExportDirectory).TrimEnd('\')
    $destination = (Require-LocalPath $BackupDirectory).TrimEnd('\')
    if ($source.Length -lt 3 -or $destination.Length -lt 3) { throw 'Não usar a raiz do disco.' }
    if ($source.Equals($destination, [StringComparison]::OrdinalIgnoreCase) -or
        $source.StartsWith($destination + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $destination.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Origem e destino devem estar separados.'
    }
    $sourceItem = Get-Item -LiteralPath $source -Force
    $destItem = Get-Item -LiteralPath $destination -Force
    if (-not $sourceItem.PSIsContainer -or -not $destItem.PSIsContainer) { throw 'Diretório inválido.' }
    Require-NoReparseAncestors $source
    Require-NoReparseAncestors $destination
    $agePath = Require-TrustedExe $AgeExe $AgeSha256
    $tarPath = Require-TrustedExe $TarExe $TarSha256

    # Explicit traversal avoids following junctions/symlinks into unrelated data.
    $directories = New-Object 'System.Collections.Generic.Stack[string]'
    $directories.Push($source)
    $fileCount = 0
    while ($directories.Count -gt 0) {
        $current = $directories.Pop()
        foreach ($path in [System.IO.Directory]::EnumerateFileSystemEntries($current)) {
            $item = Get-Item -LiteralPath $path -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'A exportação contém uma ligação.'
            }
            if ($item.PSIsContainer) { $directories.Push($item.FullName) } else { $fileCount++ }
        }
    }
    if ($fileCount -eq 0) { throw 'Exportação vazia.' }

    $name = 'abigailovos_' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ', [Globalization.CultureInfo]::InvariantCulture) + '_' + [Guid]::NewGuid().ToString('N') + '.age'
    $finalPath = Join-Path $destination $name
    $partialPath = $finalPath + '.partial'
    if (Test-Path -LiteralPath $partialPath) { throw 'Destino já existe.' }
    $ageInfo = New-ProcessInfo $agePath ('--encrypt --recipient {0} --output {1}' -f $Recipient, (Quote-WindowsPath $partialPath))
    $ageInfo.RedirectStandardInput = $true
    $tarInfo = New-ProcessInfo $tarPath ('-C {0} -cf - .' -f (Quote-WindowsPath $source))
    $tarInfo.RedirectStandardOutput = $true
    $age = [System.Diagnostics.Process]::Start($ageInfo)
    $ageErrors = $age.StandardError.ReadToEndAsync()
    $tar = [System.Diagnostics.Process]::Start($tarInfo)
    $tarErrors = $tar.StandardError.ReadToEndAsync()
    $copy = $tar.StandardOutput.BaseStream.CopyToAsync($age.StandardInput.BaseStream)
    if (-not $copy.Wait($TimeoutSeconds * 1000)) { throw 'Prazo excedido.' }
    $age.StandardInput.Close()
    if (-not $tar.WaitForExit($TimeoutSeconds * 1000) -or -not $age.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Prazo excedido.'
    }
    if ($tar.ExitCode -ne 0 -or $age.ExitCode -ne 0) { throw 'Não foi possível cifrar.' }
    $result = Get-Item -LiteralPath $partialPath -Force
    if ($result.PSIsContainer -or $result.Length -le 0 -or
        (($result.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'Resultado inválido.' }
    # Same-directory move will not overwrite a previously published archive.
    [System.IO.File]::Move($partialPath, $finalPath)
    Write-Output 'Arquivo cifrado de teste criado. A origem não foi removida; exportação e restauro não foram verificados.'
    exit 0
} catch {
    [Console]::Error.WriteLine('Falha ao preparar o arquivo de teste. Nenhuma cópia válida foi confirmada.')
    exit 1
} finally {
    foreach ($process in @($tar, $age)) {
        if ($null -ne $process) {
            try { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } catch {}
            $process.Dispose()
        }
    }
    # Do not delete even a partial file: another process could have created it
    # after the existence check. Partials are never named as completed archives.
}
