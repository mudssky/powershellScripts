Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    生成统一的 PostgreSQL 连接上下文。

.DESCRIPTION
    按“显式参数 > 连接串 > env-file > 当前进程环境变量”的优先级合并连接配置，
    让后续命令构建逻辑只依赖一个规范化对象。

.PARAMETER CliOptions
    由 `ConvertFrom-LongOptionList` 返回的参数表。

.OUTPUTS
    PSCustomObject
    返回统一的连接上下文，至少包含 `Host`、`Port`、`User`、`Password`、`Database`。
#>
function Resolve-PgContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions
    )

    $envFilePath = if ($CliOptions.ContainsKey('env_file')) { [string]$CliOptions['env_file'] } else { $null }
    $connectionString = if ($CliOptions.ContainsKey('connection_string')) { [string]$CliOptions['connection_string'] } else { $null }
    $envFileValues = Import-PgEnvFile -Path $envFilePath
    $connectionValues = ConvertFrom-PgConnectionString -ConnectionString $connectionString

    $connectionHost = if ($connectionValues.ContainsKey('Host')) { $connectionValues['Host'] } else { $null }
    $connectionPort = if ($connectionValues.ContainsKey('Port')) { $connectionValues['Port'] } else { $null }
    $connectionUser = if ($connectionValues.ContainsKey('User')) { $connectionValues['User'] } else { $null }
    $connectionPassword = if ($connectionValues.ContainsKey('Password')) { $connectionValues['Password'] } else { $null }
    $connectionDatabase = if ($connectionValues.ContainsKey('Database')) { $connectionValues['Database'] } else { $null }

    $envFileHost = if ($envFileValues.ContainsKey('PGHOST')) { $envFileValues['PGHOST'] } else { $null }
    $envFilePort = if ($envFileValues.ContainsKey('PGPORT')) { $envFileValues['PGPORT'] } else { $null }
    $envFileUser = if ($envFileValues.ContainsKey('PGUSER')) { $envFileValues['PGUSER'] } else { $null }
    $envFilePassword = if ($envFileValues.ContainsKey('PGPASSWORD')) { $envFileValues['PGPASSWORD'] } else { $null }
    $envFileDatabase = if ($envFileValues.ContainsKey('PGDATABASE')) { $envFileValues['PGDATABASE'] } else { $null }

    $resolvedHost = if ($CliOptions.ContainsKey('host')) { [string]$CliOptions['host'] } elseif ($connectionHost) { $connectionHost } elseif ($envFileHost) { $envFileHost } else { $env:PGHOST }
    $resolvedPort = if ($CliOptions.ContainsKey('port')) { [int]$CliOptions['port'] } elseif ($connectionPort) { [int]$connectionPort } elseif ($envFilePort) { [int]$envFilePort } elseif ($env:PGPORT) { [int]$env:PGPORT } else { 5432 }
    $resolvedUser = if ($CliOptions.ContainsKey('user')) { [string]$CliOptions['user'] } elseif ($connectionUser) { $connectionUser } elseif ($envFileUser) { $envFileUser } else { $env:PGUSER }
    $resolvedPassword = if ($CliOptions.ContainsKey('password')) { [string]$CliOptions['password'] } elseif ($connectionPassword) { $connectionPassword } elseif ($envFilePassword) { $envFilePassword } else { $env:PGPASSWORD }
    $resolvedDatabase = if ($CliOptions.ContainsKey('database')) { [string]$CliOptions['database'] } elseif ($connectionDatabase) { $connectionDatabase } elseif ($envFileDatabase) { $envFileDatabase } else { $env:PGDATABASE }

    return [PSCustomObject]@{
        Host     = $resolvedHost
        Port     = $resolvedPort
        User     = $resolvedUser
        Password = $resolvedPassword
        Database = $resolvedDatabase
        EnvFile  = $envFilePath
    }
}
