Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    解析 PostgreSQL toolkit 的默认 env 文件来源。

.DESCRIPTION
    按“当前工作目录优先，必要时回退脚本目录”的规则定位 `.env` 与 `.env.local`，
    并且一旦首选目录命中任意默认文件，就不再跨目录补缺。

.PARAMETER WorkingDirectory
    当前工作目录，默认使用 `Get-Location`。

.PARAMETER ScriptDirectory
    脚本目录，默认使用当前脚本所在目录。

.OUTPUTS
    PSCustomObject
    返回包含 `BasePath` 与 `Paths` 的默认 env 文件来源描述。
#>
function Resolve-PgDefaultEnvSource {
    [CmdletBinding()]
    param(
        [string]$WorkingDirectory = (Get-Location).Path,
        [string]$ScriptDirectory = $PSScriptRoot
    )

    return Resolve-DefaultEnvFiles -PrimaryBasePath $WorkingDirectory -FallbackBasePath $ScriptDirectory
}

<#
.SYNOPSIS
    解析一个或多个 PostgreSQL env 文件并按顺序合并。

.DESCRIPTION
    通过共享配置解析器复用严格 dotenv 语义，避免 PostgreSQL toolkit 继续维护独立 parser。

.PARAMETER Paths
    要解析的 env 文件路径列表。

.OUTPUTS
    hashtable
    返回合并后的 `PG*` 变量字典。
#>
function Import-PgEnvFiles {
    [CmdletBinding()]
    param(
        [string[]]$Paths
    )

    if ($null -eq $Paths -or $Paths.Count -eq 0) {
        return @{}
    }

    return (Resolve-ConfigSources -ConfigFile $Paths).Values
}

<#
.SYNOPSIS
    生成统一的 PostgreSQL 连接上下文。

.DESCRIPTION
    按“显式参数 > 连接串 > 显式 env-file > 当前进程环境变量 > 自动发现 env 文件”的优先级合并连接配置，
    让后续命令构建逻辑只依赖一个规范化对象。

.PARAMETER CliOptions
    由 `ConvertFrom-LongOptionList` 返回的参数表。

.PARAMETER WorkingDirectory
    当前工作目录，默认使用 `Get-Location`。

.PARAMETER ScriptDirectory
    脚本目录，默认使用当前脚本所在目录。

.OUTPUTS
    PSCustomObject
    返回统一的连接上下文，至少包含 `Host`、`Port`、`User`、`Password`、`Database`。
#>
function Resolve-PgContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions,

        [string]$WorkingDirectory = (Get-Location).Path,

        [string]$ScriptDirectory = $PSScriptRoot
    )

    $explicitEnvFilePath = if ($CliOptions.ContainsKey('env_file')) { [string]$CliOptions['env_file'] } else { $null }
    $connectionString = if ($CliOptions.ContainsKey('connection_string')) { [string]$CliOptions['connection_string'] } else { $null }
    $explicitEnvValues = if ([string]::IsNullOrWhiteSpace($explicitEnvFilePath)) { @{} } else { Read-ConfigEnvFile -Path $explicitEnvFilePath }
    $defaultEnvSource = if ([string]::IsNullOrWhiteSpace($explicitEnvFilePath)) {
        Resolve-PgDefaultEnvSource -WorkingDirectory $WorkingDirectory -ScriptDirectory $ScriptDirectory
    }
    else {
        [pscustomobject]@{
            BasePath = $null
            Paths    = @()
        }
    }
    $defaultEnvValues = Import-PgEnvFiles -Paths $defaultEnvSource.Paths
    $connectionValues = ConvertFrom-PgConnectionString -ConnectionString $connectionString

    $connectionHost = if ($connectionValues.ContainsKey('Host')) { $connectionValues['Host'] } else { $null }
    $connectionPort = if ($connectionValues.ContainsKey('Port')) { $connectionValues['Port'] } else { $null }
    $connectionUser = if ($connectionValues.ContainsKey('User')) { $connectionValues['User'] } else { $null }
    $connectionPassword = if ($connectionValues.ContainsKey('Password')) { $connectionValues['Password'] } else { $null }
    $connectionDatabase = if ($connectionValues.ContainsKey('Database')) { $connectionValues['Database'] } else { $null }

    $explicitEnvHost = if ($explicitEnvValues.ContainsKey('PGHOST')) { $explicitEnvValues['PGHOST'] } else { $null }
    $explicitEnvPort = if ($explicitEnvValues.ContainsKey('PGPORT')) { $explicitEnvValues['PGPORT'] } else { $null }
    $explicitEnvUser = if ($explicitEnvValues.ContainsKey('PGUSER')) { $explicitEnvValues['PGUSER'] } else { $null }
    $explicitEnvPassword = if ($explicitEnvValues.ContainsKey('PGPASSWORD')) { $explicitEnvValues['PGPASSWORD'] } else { $null }
    $explicitEnvDatabase = if ($explicitEnvValues.ContainsKey('PGDATABASE')) { $explicitEnvValues['PGDATABASE'] } else { $null }

    $defaultEnvHost = if ($defaultEnvValues.ContainsKey('PGHOST')) { $defaultEnvValues['PGHOST'] } else { $null }
    $defaultEnvPort = if ($defaultEnvValues.ContainsKey('PGPORT')) { $defaultEnvValues['PGPORT'] } else { $null }
    $defaultEnvUser = if ($defaultEnvValues.ContainsKey('PGUSER')) { $defaultEnvValues['PGUSER'] } else { $null }
    $defaultEnvPassword = if ($defaultEnvValues.ContainsKey('PGPASSWORD')) { $defaultEnvValues['PGPASSWORD'] } else { $null }
    $defaultEnvDatabase = if ($defaultEnvValues.ContainsKey('PGDATABASE')) { $defaultEnvValues['PGDATABASE'] } else { $null }

    $resolvedHost = if ($CliOptions.ContainsKey('host')) { [string]$CliOptions['host'] } elseif ($connectionHost) { $connectionHost } elseif ($explicitEnvHost) { $explicitEnvHost } elseif ($env:PGHOST) { $env:PGHOST } else { $defaultEnvHost }
    $resolvedPort = if ($CliOptions.ContainsKey('port')) { [int]$CliOptions['port'] } elseif ($connectionPort) { [int]$connectionPort } elseif ($explicitEnvPort) { [int]$explicitEnvPort } elseif ($env:PGPORT) { [int]$env:PGPORT } elseif ($defaultEnvPort) { [int]$defaultEnvPort } else { 5432 }
    $resolvedUser = if ($CliOptions.ContainsKey('user')) { [string]$CliOptions['user'] } elseif ($connectionUser) { $connectionUser } elseif ($explicitEnvUser) { $explicitEnvUser } elseif ($env:PGUSER) { $env:PGUSER } else { $defaultEnvUser }
    $resolvedPassword = if ($CliOptions.ContainsKey('password')) { [string]$CliOptions['password'] } elseif ($connectionPassword) { $connectionPassword } elseif ($explicitEnvPassword) { $explicitEnvPassword } elseif ($env:PGPASSWORD) { $env:PGPASSWORD } else { $defaultEnvPassword }
    $resolvedDatabase = if ($CliOptions.ContainsKey('database')) { [string]$CliOptions['database'] } elseif ($connectionDatabase) { $connectionDatabase } elseif ($explicitEnvDatabase) { $explicitEnvDatabase } elseif ($env:PGDATABASE) { $env:PGDATABASE } else { $defaultEnvDatabase }

    return [PSCustomObject]@{
        Host         = $resolvedHost
        Port         = $resolvedPort
        User         = $resolvedUser
        Password     = $resolvedPassword
        Database     = $resolvedDatabase
        EnvFile      = $explicitEnvFilePath
        AutoEnvFiles = @($defaultEnvSource.Paths)
        AutoEnvBase  = $defaultEnvSource.BasePath
    }
}
