<#
Verificação local de um APK já compilado. Não gera chaves, não assina,
não publica e não contacta a nuvem. No modo de lançamento exige que o
operador indique a impressão digital aprovada, guardada fora deste
repositório. Não prova o servidor configurado no build nem o identificador
da aplicação; isso tem de ser confirmado separadamente.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Apk,
    [string] $ExpectedFingerprintSha256,
    [string] $Apksigner,
    [switch] $InspectOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-LocalFile([string] $Path, [string] $Label) {
    if (-not [System.IO.Path]::IsPathRooted($Path)) { throw "$Label tem de ser um caminho absoluto." }
    $full = [System.IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $full -Force
    if ($null -eq $item -or $item.PSIsContainer) { throw "$Label não é um ficheiro." }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label é uma ligação."
    }
    return $full
}

function Resolve-Apksigner([string] $Configured) {
    if (-not [string]::IsNullOrWhiteSpace($Configured)) {
        return Require-LocalFile $Configured 'apksigner'
    }
    $root = Join-Path $env:LOCALAPPDATA 'Android\sdk\build-tools'
    if (-not (Test-Path -LiteralPath $root)) {
        throw 'Não foi encontrado o Android SDK; indique -Apksigner.'
    }
    $candidates = @(Get-ChildItem -LiteralPath $root -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
        Where-Object { Test-Path -LiteralPath $_ })
    if ($candidates.Count -eq 0) {
        throw 'Não foi encontrado apksigner; indique -Apksigner.'
    }
    return Require-LocalFile $candidates[0] 'apksigner'
}

function Normalize-Fingerprint([string] $Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $hex = ($Value -replace '[\s:]', '').ToUpperInvariant()
    if ($hex -cnotmatch '^[0-9A-F]{64}$') {
        throw 'Impressão digital inválida: esperados 64 caracteres hexadecimais.'
    }
    return $hex
}

function Parse-Signer([string[]] $Lines) {
    $names = @{}
    $digests = @{}
    foreach ($line in $Lines) {
        $dn = [regex]::Match($line, '^Signer #(\d+) certificate DN:\s*(.*)$')
        if ($dn.Success) {
            $names[$dn.Groups[1].Value] = $dn.Groups[2].Value.Trim()
            continue
        }
        $digest = [regex]::Match($line, '^Signer #(\d+) certificate SHA-256 digest:\s*([0-9a-fA-F:]+)$')
        if ($digest.Success) {
            $digests[$digest.Groups[1].Value] = ($digest.Groups[2].Value -replace ':', '')
        }
    }
    $numbers = @($names.Keys | Sort-Object { [int]$_ })
    if ($numbers.Count -eq 0 -or $numbers.Count -ne $digests.Count) {
        throw 'Não foi possível ler os certificados do APK.'
    }
    $parsed = @()
    foreach ($number in $numbers) {
        if ($digests[$number] -cnotmatch '^[0-9a-fA-F]{64}$') {
            throw 'Impressão digital do APK inválida.'
        }
        $parsed += [pscustomobject]@{
            Number      = $number
            Dn          = $names[$number]
            Fingerprint = $digests[$number].ToUpperInvariant()
        }
    }
    return $parsed
}

try {
    $apkPath = Require-LocalFile $Apk 'APK'
    $signer = Resolve-Apksigner $Apksigner
    $expected = Normalize-Fingerprint $ExpectedFingerprintSha256
    if (-not $InspectOnly -and $null -eq $expected) {
        throw 'Indique -ExpectedFingerprintSha256 com a impressão digital aprovada, ou use -InspectOnly.'
    }

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = & $signer 'verify' '--print-certs' $apkPath 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    $lines = @($raw | ForEach-Object { $_.ToString() } | Where-Object { $_ -notmatch '^WARNING:' })
    if ($exitCode -ne 0) {
        throw 'apksigner não confirmou o APK.'
    }

    $signers = @(Parse-Signer $lines)
    if ($signers.Count -ne 1) {
        throw 'Era esperado exatamente um signatário.'
    }
    $found = $signers[0]
    Write-Output ("Signatário: {0}" -f $found.Dn)
    Write-Output ("SHA-256:    {0}" -f $found.Fingerprint)
    $debug = $found.Dn -match 'Android Debug'

    if ($InspectOnly) {
        if ($debug) { Write-Warning 'Certificado de depuração Android: não é um APK de lançamento.' }
        Write-Warning 'Modo inspeção: não confirma a chave aprovada nem o servidor configurado.'
        exit 0
    }
    if ($debug) {
        throw 'O APK usa o certificado de depuração Android; recusado para lançamento.'
    }
    if ($found.Fingerprint -cne $expected) {
        throw 'A impressão digital não corresponde à chave aprovada.'
    }
    Write-Output 'Assinatura verificada contra a impressão digital indicada.'
    Write-Output 'Confirme separadamente o identificador da aplicação e o servidor do build.'
    exit 0
} catch {
    [Console]::Error.WriteLine('Falha: ' + $_.Exception.Message)
    exit 1
}
