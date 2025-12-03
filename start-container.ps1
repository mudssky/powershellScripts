
#!/usr/bin/env pwsh

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
    - qdrant: 向量数据库

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

.EXAMPLE
    .\start-container.ps1 -List
    列出可用服务与配置

.EXAMPLE
    .\start-container.ps1 -ServiceName redis -DryRun
    以干运行模式打印将执行的命令

.EXAMPLE
    .\start-container.ps1 -ServiceName redis -Down -DryRun
    停止并移除指定服务（不执行，仅预览）

.EXAMPLE
    .\start-container.ps1 -ServiceName redis -Pull -DryRun
    拉取镜像（不执行，仅预览）

.EXAMPLE
    .\start-container.ps1 -ServiceName new-api -Update
    先拉取最新镜像，再启动服务

.EXAMPLE
    .\start-container.ps1 -ServiceName new-api -PullAlways
    在 Compose v2 环境下通过 `up -d --pull always` 拉取并启动；在 legacy 环境自动回退为先拉取后启动

.NOTES
    需要安装Docker
    脚本会自动创建必要的数据目录
    某些服务可能需要额外的配置文件
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("minio", "redis", 'postgre', 'etcd', 'nacos', 'rabbitmq', 'mongodb', 'one-api', 'mongodb-replica', 'kokoro-fastapi', 
        'kokoro-fastapi-cpu', 'cadvisor', 'prometheus', 'noco', 'n8n', 'crawl4ai', 'pageSpy', 'new-api', 'qdrant')]
    [string]$ServiceName, # 更合理的参数名
    
    [ValidateSet("always", "unless-stopped", 'on-failure', 'on-failure:3', 'no')]
    [string]$RestartPolicy = 'unless-stopped', # 更明确的参数名
    
    [string]$DataPath   ,# 允许自定义数据目录
    [string]$DefaultUser = "root",  # 默认用户名
    [SecureString]$DefaultPassword = (ConvertTo-SecureString "12345678" -AsPlainText -Force),  # 默认密码（安全）
    [switch]$List,
    [switch]$DryRun,
    [switch]$Down,
    [switch]$Pull,
    [switch]$Build,
    [switch]$Update,
    [switch]$PullAlways,
    [string]$ProjectName,
    [string]$NetworkName,
    [hashtable]$Env,
    [switch]$UseEnvFile
)
  
# 设置默认 docker 映射路径
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PlainTextFromSecure {
    param([SecureString]$Secure)
    if ($null -eq $Secure) { return "" }
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Initialize-DataPath {
    param(
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($IsWindows) { $Path = "C:\\docker_data" }
        elseif ($IsLinux) { $Path = "/var/lib/docker_data" }
        elseif ($IsMacOS) { $Path = "/Volumes/Data/docker_data" }
    }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        return $resolved
    }
    catch { return $Path }
}

function Get-DefaultProjectName {
    param(
        [string]$ServiceName,
        [string]$ProjectNameInput
    )
    $name = $ProjectNameInput
    if ([string]::IsNullOrWhiteSpace($name)) {
        if (-not [string]::IsNullOrWhiteSpace(${env:COMPOSE_PROJECT_NAME})) { $name = ${env:COMPOSE_PROJECT_NAME} }
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        if (-not [string]::IsNullOrWhiteSpace($ServiceName)) { $name = ("dev-" + $ServiceName) } else { $name = "compose" }
    }
    $normalized = ($name.ToLower() -replace '[^a-z0-9\-]', '-')
    if ($normalized.Length -gt 40) { $normalized = $normalized.Substring(0, 40) }
    return $normalized
}

$DataPath = Initialize-DataPath -Path $DataPath
# 可以添加统一网络配置
# $networkName = "dev-net"
# if (-not (docker network ls -q -f name="$networkName")) {
#     docker network create $networkName
# }

function Test-DockerAvailable {
    $composeSub = $false
    $legacyCompose = $false
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        try {
            & docker compose version *> $null
            if ($LASTEXITCODE -eq 0 -or $?) { $composeSub = $true }
        }
        catch {}
    }
    if (-not $composeSub) {
        if (Get-Command docker-compose -ErrorAction SilentlyContinue) { $legacyCompose = $true }
    }
    if (-not ($composeSub -or $legacyCompose)) { throw "Docker 未安装或 compose 不可用" }
    if ($composeSub) { return 'sub' } else { return 'legacy' }
}

function Invoke-DockerCompose {
    param(
        [string]$File,
        [string]$Project,
        [string[]]$Profiles,
        [string[]]$Services,
        [string]$Action,
        [string[]]$ExtraArgs,
        [switch]$DryRun
    )
    $mode = $null
    if (-not $DryRun) { $mode = Test-DockerAvailable } else { $mode = 'sub' }
    $dcArgs = @()
    if ($mode -eq 'sub') { $dcArgs += 'compose' }
    if ($File) { $dcArgs += @('-f', $File) }
    if ($Project) { $dcArgs += @('-p', $Project) }
    if ($Profiles) { foreach ($p in $Profiles) { if (-not [string]::IsNullOrWhiteSpace($p)) { $dcArgs += @('--profile', $p) } } }
    if ($Action) { $dcArgs += ($Action -split ' ') }
    if ($Services) { $dcArgs += $Services }
    if ($ExtraArgs) { $dcArgs += $ExtraArgs }
    if ($DryRun) {
        if ($mode -eq 'sub') { Write-Output ("docker " + ($dcArgs -join ' ')) } else { Write-Output (("docker-compose " + ($dcArgs -join ' '))) }
        return
    }
    if ($mode -eq 'sub') { & docker @dcArgs } else { & docker-compose @dcArgs }
}

function Get-NetworkExists {
    param([string]$Name)
    try { & docker network ls -q -f name=$Name } catch { return $null }
}

function New-NetworkIfMissing {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $exists = Get-NetworkExists -Name $Name
    if ([string]::IsNullOrWhiteSpace($exists)) { try { & docker network create $Name | Out-Null } catch {} }
}

function Wait-ServiceHealthy {
    param([string]$Service, [string]$Project, [int]$TimeoutSec = 60)
    $start = Get-Date
    $elapsed = 0
    while ($elapsed -lt $TimeoutSec) {
        try {
            $psArgs = @('ps', '-q', '--filter', "label=com.docker.compose.service=$Service")
            if ($Project) { $psArgs += @('--filter', "label=com.docker.compose.project=$Project") }
            $ids = & docker @psArgs
            if ([string]::IsNullOrWhiteSpace($ids)) { Start-Sleep -Milliseconds 500; continue }
            $inspect = & docker inspect $ids
            if ($inspect -match '"Status":\s*"healthy"') { return $true }
        }
        catch {}
        Start-Sleep -Seconds 1
        $elapsed = (((Get-Date) - $start).TotalSeconds)
    }
    return $false
}


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


try {
    ${env:DATA_PATH} = $DataPath
    ${env:DEFAULT_USER} = $DefaultUser
    ${env:DEFAULT_PASSWORD} = (Get-PlainTextFromSecure -Secure $DefaultPassword)
    ${env:RESTART_POLICY} = $RestartPolicy
    $projectName = Get-DefaultProjectName -ServiceName $ServiceName -ProjectName $ProjectName
    ${env:COMPOSE_PROJECT_NAME} = $projectName
    $composeDir = Join-Path $PSScriptRoot 'config' 'dockerfiles' 'compose'
    $composePath = Join-Path $composeDir 'docker-compose.yml'
    $mongoReplComposePath = Join-Path $composeDir 'mongo-repl.compose.yml'

    if ($Env) { foreach ($k in $Env.Keys) { ${env:$k} = [string]$Env[$k] } }
    if ($UseEnvFile -and $Env) {
        $envFile = Join-Path $composeDir '.env'
        $lines = @()
        foreach ($k in $Env.Keys) { $lines += ("$k=" + [string]$Env[$k]) }
        Set-Content -LiteralPath $envFile -Value $lines -Encoding utf8
    }

    if ($List) {
        if (Test-Path $composePath) {
            $available = Get-ComposeServiceNames -ComposePath $composePath -ReplicaComposePath $mongoReplComposePath
            $available | ForEach-Object { Write-Output $_ }
            Write-Output ("默认项目名: " + $projectName)
            return
        }
    }

    if ($NetworkName) { New-NetworkIfMissing -Name $NetworkName }
    if ($ServiceName -eq 'mongodb-replica' -and (Test-Path $mongoReplComposePath)) {
        $env:DOCKER_DATA_PATH = $DataPath
        $env:MONGO_USER = $DefaultUser
        $env:MONGO_PASSWORD = (Get-PlainTextFromSecure -Secure $DefaultPassword)
        Invoke-DockerCompose -File $mongoReplComposePath -Project $projectName -Action 'up -d' -DryRun:$DryRun
        if (-not $DryRun) { [void](Wait-ServiceHealthy -Service 'mongo1' -Project $projectName) }
        return
    }
    if (Test-Path $composePath) {
        $available = Get-ComposeServiceNames -ComposePath $composePath -ReplicaComposePath $mongoReplComposePath
        if ($Update) {
            Invoke-DockerCompose -File $composePath -Project $projectName -Profiles @($ServiceName) -Action 'pull' -DryRun:$DryRun
            Invoke-DockerCompose -File $composePath -Project $projectName -Profiles @($ServiceName) -Action 'up -d' -DryRun:$DryRun
            if (-not $DryRun -and $ServiceName) { [void](Wait-ServiceHealthy -Service $ServiceName -Project $projectName) }
            return
        }
        if ($PullAlways) {
            $modeForUp = Test-DockerAvailable
            if ($modeForUp -eq 'sub') {
                Invoke-DockerCompose -File $composePath -Project $projectName -Profiles @($ServiceName) -Action 'up -d' -ExtraArgs @('--pull','always') -DryRun:$DryRun
                if (-not $DryRun -and $ServiceName) { [void](Wait-ServiceHealthy -Service $ServiceName -Project $projectName) }
            }
            else {
                Invoke-DockerCompose -File $composePath -Project $projectName -Profiles @($ServiceName) -Action 'pull' -DryRun:$DryRun
                Invoke-DockerCompose -File $composePath -Project $projectName -Profiles @($ServiceName) -Action 'up -d' -DryRun:$DryRun
                if (-not $DryRun -and $ServiceName) { [void](Wait-ServiceHealthy -Service $ServiceName -Project $projectName) }
            }
            return
        }
        if ($Down) {
            if ($ServiceName) {
                Invoke-DockerCompose -File $composePath -Project $projectName -Action 'stop' -Services @($ServiceName) -DryRun:$DryRun
                Invoke-DockerCompose -File $composePath -Project $projectName -Action 'rm -f -s' -Services @($ServiceName) -DryRun:$DryRun
            }
            else {
                Invoke-DockerCompose -File $composePath -Project $projectName -Action 'down' -DryRun:$DryRun
            }
            return
        }
        if ($Pull) {
            Invoke-DockerCompose -File $composePath -Project $projectName -Profiles @($ServiceName) -Action 'pull' -DryRun:$DryRun
            return
        }
        if ($Build) {
            Invoke-DockerCompose -File $composePath -Project $projectName -Profiles @($ServiceName) -Action 'build' -DryRun:$DryRun
            return
        }
        if ($available -contains $ServiceName) {
            Invoke-DockerCompose -File $composePath -Project $projectName -Profiles @($ServiceName) -Action 'up -d' -DryRun:$DryRun
            if (-not $DryRun) { [void](Wait-ServiceHealthy -Service $ServiceName -Project $projectName) }
            return
        }
        else {
            $suggest = @($available | Where-Object { $_ -like "*${ServiceName}*" })
            if ($suggest.Count -gt 0) { throw "未找到服务: $ServiceName, 是否指: $($suggest -join ', ')" }
        }
    }

    throw "未找到可用的容器配置: $ServiceName"
}
catch {
    Write-Error "容器启动脚本执行失败: $($_.Exception.Message)"
    Write-Verbose "错误详情: $($_.Exception.ToString())"
    exit 1
}
