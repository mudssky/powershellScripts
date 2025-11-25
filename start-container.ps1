
<#
.SYNOPSIS
    Docker容器服务启动脚本

.DESCRIPTION
    该脚本用于快速启动各种常用的Docker容器服务，包括数据库、消息队列、
    监控工具等。支持自定义重启策略、数据目录和认证信息。

.PARAMETER ServiceName
    要启动的服务名称，支持的服务包括：
    - minio: 对象存储服务
    - redis: 内存数据库
    - postgre: PostgreSQL数据库
    - etcd: 分布式键值存储
    - nacos: 服务发现和配置管理
    - rabbitmq: 消息队列
    - mongodb: 文档数据库
    - one-api: API网关
    - mongodb-replica: MongoDB副本集
    - kokoro-fastapi: FastAPI服务
    - cadvisor: 容器监控
    - prometheus: 监控系统
    - noco: 无代码平台

.PARAMETER RestartPolicy
    容器重启策略，默认为'unless-stopped'。可选值：
    - always: 总是重启
    - unless-stopped: 除非手动停止否则重启
    - on-failure: 失败时重启
    - on-failure:3: 失败时最多重启3次
    - no: 不自动重启

.PARAMETER DataPath
    数据存储目录，默认为"C:/docker_data"

.PARAMETER DefaultUser
    默认用户名，默认为"root"

.PARAMETER DefaultPassword
    默认密码，默认为"12345678"

.EXAMPLE
    .\start-container.ps1 -ServiceName redis
    启动Redis容器服务

.EXAMPLE
    .\start-container.ps1 -ServiceName mongodb -RestartPolicy always -DataPath "D:/data"
    启动MongoDB服务并自定义重启策略和数据目录

.NOTES
    需要安装Docker
    脚本会自动创建必要的数据目录
    某些服务可能需要额外的配置文件
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("minio", "redis", 'postgre', 'etcd', 'nacos', 'rabbitmq', 'mongodb', 'one-api', 'mongodb-replica', 'kokoro-fastapi', 
        'kokoro-fastapi-cpu', 'cadvisor', 'prometheus', 'noco', 'n8n', 'crawl4ai', 'pageSpy', 'new-api')]
    [string]$ServiceName, # 更合理的参数名
    
    [ValidateSet("always", "unless-stopped", 'on-failure', 'on-failure:3', 'no')]
    [string]$RestartPolicy = 'unless-stopped', # 更明确的参数名
    
    [string]$DataPath   ,# 允许自定义数据目录
    [string]$DefaultUser = "root",  # 默认用户名
    [string]$DefaultPassword = "12345678"  # 默认密码
)
  
# 设置默认 docker 映射路径
if (!$DataPath) {
    if ($IsWindows) {
        $DataPath = "C:/docker_data"
    }
    elseif ($IsLinux) {
        $DataPath = "/var/lib/docker_data"
    }
    elseif ($IsMacOS) {
        $DataPath = "/Volumes/Data/docker_data"
    }
}
# 可以添加统一网络配置
# $networkName = "dev-net"
# if (-not (docker network ls -q -f name="$networkName")) {
#     docker network create $networkName
# }

# 使用数组存储日志配置参数
$commonParams = @(
    # 日志相关参数
    "--log-driver", "json-file",
    "--log-opt", "max-size=10m",
    "--log-opt", "max-file=3"
    # 网络配置
    # "--network","dev-net"
)
$pgHealthCheck = @(
    "--health-cmd", "pg_isready -U postgres",
    "--health-interval", "10s",
    "--health-timeout", "5s",
    "--health-retries", "3"
)


function Get-ComposeServiceNames {
    param(
        [string]$ComposePath,
        [string]$ReplicaComposePath
    )
    $names = @()
    if (Test-Path $ComposePath) {
        $inServices = $false
        foreach ($line in Get-Content -LiteralPath $ComposePath) {
            if ($line -match '^\s*services:\s*$') { $inServices = $true; continue }
            if ($inServices) {
                if ($line -match '^\s{2}([A-Za-z0-9\-_]+):\s*$') { $names += $Matches[1]; continue }
                if ($line -match '^\S') { $inServices = $false }
            }
        }
    }
    $result = @($names | Sort-Object -Unique)
    if (Test-Path $ReplicaComposePath) { $result += 'mongodb-replica' }
    $result | Sort-Object -Unique
}


${env:DATA_PATH} = $DataPath
${env:DEFAULT_USER} = $DefaultUser
${env:DEFAULT_PASSWORD} = $DefaultPassword
${env:RESTART_POLICY} = $RestartPolicy
$composeDir = Join-Path $PSScriptRoot "config/dockerfiles/compose"
$composePath = Join-Path $composeDir "docker-compose.yml"
$mongoReplComposePath = Join-Path $composeDir "mongo-repl.compose.yml"
if ($ServiceName -eq 'mongodb-replica' -and (Test-Path $mongoReplComposePath)) {
    $env:DOCKER_DATA_PATH = $DataPath
    $env:MONGO_USER = $DefaultUser
    $env:MONGO_PASSWORD = $DefaultPassword
    docker compose -p mongo-repl-dev -f $mongoReplComposePath up -d
    return
}
if (Test-Path $composePath) {
    $available = Get-ComposeServiceNames -ComposePath $composePath -ReplicaComposePath $mongoReplComposePath
    if ($available -contains $ServiceName) {
        docker compose -f $composePath --profile $ServiceName up -d
        return
    }
}

throw "未找到可用的容器配置: $ServiceName"
