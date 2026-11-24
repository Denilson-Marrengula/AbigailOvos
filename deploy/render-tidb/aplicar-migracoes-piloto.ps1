# Aplica as migrações V1-V17 à base do piloto, uma única vez, em modo nao Web.
# Nao cria administrador, nao altera o servico Render e nao executa testes.
# Requer consola interativa. Nenhum segredo e gravado em ficheiro, argumento ou log.

$ErrorActionPreference = 'Stop'

if (-not [Environment]::UserInteractive) {
    throw 'Execute este script numa consola interativa.'
}

$expectedDb = 'abigailovos_tidb_test_4292b79106cb4fac'
$confirm = Read-Host "Escreva $expectedDb para confirmar"
if ($confirm -ne $expectedDb) {
    throw 'Confirmacao incorreta. Nada foi alterado.'
}

$dbUrl = Read-Host 'DB_URL (jdbc:mysql://...?sslMode=VERIFY_IDENTITY)'
if ($dbUrl -notmatch '^jdbc:mysql://') {
    throw 'DB_URL deve comecar por jdbc:mysql://'
}
if ($dbUrl -notmatch "/$expectedDb(?:\?|$)") {
    throw "DB_URL nao aponta para $expectedDb"
}
if ($dbUrl -notmatch '(?i)sslMode=VERIFY_IDENTITY') {
    throw 'DB_URL exige sslMode=VERIFY_IDENTITY'
}
if ($dbUrl -match '(?i)(user|password)=' -or $dbUrl -match '(?i)allowPublicKeyRetrieval=true' -or $dbUrl.Contains('@')) {
    throw 'DB_URL nao pode conter credenciais nem allowPublicKeyRetrieval'
}

$dbUser = Read-Host 'DB_USERNAME (conta de migracoes, nao a conta de execucao)'
if ([string]::IsNullOrWhiteSpace($dbUser)) {
    throw 'DB_USERNAME e obrigatorio.'
}

$secure = Read-Host 'DB_PASSWORD' -AsSecureString
$plain = [System.Net.NetworkCredential]::new('', $secure).Password
if ([string]::IsNullOrEmpty($plain)) {
    throw 'DB_PASSWORD e obrigatorio.'
}

$names = @(
    'DB_URL',
    'DB_USERNAME',
    'DB_PASSWORD',
    'DB_MIGRATIONS_ENABLED',
    'ABIGAIL_BOOTSTRAP_ENABLED',
    'SPRING_MAIN_WEB_APPLICATION_TYPE',
    'SPRING_PROFILES_ACTIVE'
)
$old = @{}
foreach ($name in $names) {
    $old[$name] = [Environment]::GetEnvironmentVariable($name)
}

try {
    $env:DB_URL = $dbUrl
    $env:DB_USERNAME = $dbUser
    $env:DB_PASSWORD = $plain
    $env:DB_MIGRATIONS_ENABLED = 'true'
    $env:ABIGAIL_BOOTSTRAP_ENABLED = 'false'
    $env:SPRING_MAIN_WEB_APPLICATION_TYPE = 'none'
    Remove-Item env:SPRING_PROFILES_ACTIVE -ErrorAction SilentlyContinue

    $backend = Join-Path $PSScriptRoot '..\..\backend'
    Push-Location $backend
    try {
        mvn -B -DskipTests package
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o backend.' }

        java -jar (Join-Path $backend 'target\backend-0.0.1-SNAPSHOT.jar')
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao aplicar as migracoes.' }
    }
    finally {
        Pop-Location
    }

    Write-Host 'Migracoes V1-V17 aplicadas. O servico Render continua com migracoes desativadas.'
}
finally {
    foreach ($name in $names) {
        if ($null -eq $old[$name]) {
            Remove-Item "env:$name" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item "env:$name" -Value $old[$name]
        }
    }
    $plain = $null
    $secure = $null
}
