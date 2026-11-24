<#
SYNTHETIC FIXTURES ONLY. Compares an invented, sanitized manifest with local
filenames and sizes. Does not read TiDB output, connect to a server, export,
download, hash contents, encrypt, restore, write a success marker or schedule
anything. Matching sizes do not prove content integrity or backup completeness.
Hard links, empty directories and concurrent modifications are not verified.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $ExportDirectory,
    [Parameter(Mandatory = $true)] [string] $ManifestPath,
    [Parameter(Mandatory = $true)] [switch] $SyntheticDataOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
            throw 'Ligação não permitida.'
        }
        $parent = [System.IO.Directory]::GetParent($item.FullName)
        if ($null -eq $parent) { break }
        $item = Get-Item -LiteralPath $parent.FullName -Force
    }
}

function Require-Name([object] $Name) {
    if ($Name -isnot [string] -or $Name.Length -eq 0 -or $Name.Length -gt 512) {
        throw 'Nome inválido.'
    }
    # Intentionally conservative fixture format, not the TiDB API schema.
    # Disallow traversal, Windows device names, ADS, ambiguous separators and
    # trailing dots/spaces; real provider filenames remain to be investigated.
    foreach ($part in $Name.Split('/')) {
        if ($part.Length -gt 120 -or
            $part -cnotmatch '^[A-Za-z0-9_](?:[A-Za-z0-9_.-]*[A-Za-z0-9_-])?$' -or
            $part -imatch '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') {
            throw 'Nome inválido.'
        }
    }
    return $Name
}

try {
    if (-not $SyntheticDataOnly) { throw 'Apenas dados fictícios.' }
    $source = (Require-LocalPath $ExportDirectory).TrimEnd('\')
    $manifestFile = Require-LocalPath $ManifestPath
    if ($source.Length -lt 3 -or
        $manifestFile.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Origem ou manifesto inválido.'
    }
    $sourceItem = Get-Item -LiteralPath $source -Force
    $manifestItem = Get-Item -LiteralPath $manifestFile -Force
    if (-not $sourceItem.PSIsContainer -or $manifestItem.PSIsContainer -or
        $manifestItem.Length -le 0 -or $manifestItem.Length -gt 1048576) {
        throw 'Origem ou manifesto inválido.'
    }
    Require-NoReparseAncestors $source
    Require-NoReparseAncestors $manifestFile

    $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $manifest -or @($manifest.PSObject.Properties).Count -ne 2 -or
        $manifest.PSObject.Properties.Name -cnotcontains 'format' -or
        $manifest.PSObject.Properties.Name -cnotcontains 'files' -or
        $manifest.format -cne 'synthetic-export-inventory-v1' -or
        $manifest.files -isnot [array] -or $manifest.files.Count -eq 0 -or
        $manifest.files.Count -gt 10000) {
        throw 'Inventário sintético inválido.'
    }

    $expected = [System.Collections.Generic.Dictionary[string,long]]::new([StringComparer]::Ordinal)
    $expectedWindowsNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $manifest.files) {
        if ($null -eq $entry -or @($entry.PSObject.Properties).Count -ne 2 -or
            $entry.PSObject.Properties.Name -cnotcontains 'name' -or
            $entry.PSObject.Properties.Name -cnotcontains 'size' -or
            ($entry.size -isnot [int] -and $entry.size -isnot [long]) -or $entry.size -lt 0) {
            throw 'Entrada inválida.'
        }
        $name = Require-Name $entry.name
        if (-not $expectedWindowsNames.Add($name)) { throw 'Nome duplicado.' }
        $expected.Add($name, [long] $entry.size)
    }

    $seenWindowsNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $directories = [System.Collections.Generic.Stack[string]]::new()
    $directories.Push($sourceItem.FullName.TrimEnd('\'))
    $prefix = $sourceItem.FullName.TrimEnd('\') + '\'
    $fileCount = 0
    while ($directories.Count -gt 0) {
        $current = $directories.Pop()
        foreach ($path in [System.IO.Directory]::EnumerateFileSystemEntries($current)) {
            $item = Get-Item -LiteralPath $path -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Ligação não permitida.'
            }
            if ($item.PSIsContainer) {
                $directories.Push($item.FullName)
            } else {
                $name = Require-Name ($item.FullName.Substring($prefix.Length).Replace('\', '/'))
                if (-not $seenWindowsNames.Add($name) -or -not $expected.ContainsKey($name) -or
                    $item.Length -ne $expected[$name]) {
                    throw 'Ficheiro inesperado ou tamanho diferente.'
                }
                $fileCount++
            }
        }
    }
    if ($fileCount -ne $expected.Count) { throw 'Faltam ficheiros.' }
    Write-Output 'Inventário sintético corresponde em nomes e tamanhos. Integridade, origem e restauro não foram verificados.'
    exit 0
} catch {
    # Do not print filenames, provider responses, paths, URLs or secrets.
    [Console]::Error.WriteLine('Falha na comparação do inventário sintético. Nenhuma cópia válida foi confirmada.')
    exit 1
}
