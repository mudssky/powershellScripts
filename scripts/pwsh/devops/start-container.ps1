#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Docker容器服务启动脚本

.DESCRIPTION
    该脚本用于快速启动各种常用的Docker容器服务，包括数据库、消息队列、
    监控工具等。支持自定义重启策略、数据目录和认证信息。

    ## 添加新服务的步骤

    ### 1. 更新脚本参数验证
    在 param 块的 ValidateSet 中添加新的服务名称：
    ```powershell
    [ValidateSet("minio", "redis", "postgre", "etcd", "nacos", "rabbitmq", "mongodb", 
        "one-api", "mongodb-replica", "kokoro-fastapi", "kokoro-fastapi-cpu", 
        "cadvisor", "prometheus", "noco", "n8n", "crawl4ai", "pageSpy", "new-api", 
        "qdrant", "your-new-service")]
    ```

    ### 2. 更新服务列表文档
    在 .PARAMETER ServiceName 部分添加新服务说明：
    ```
    - your-new-service: 新服务描述
    ```

    ### 3. 配置Docker Compose文件
    在项目根目录的 config/dockerfiles/compose/docker-compose.yml 中添加服务配置：
    ```yaml
    services:
      your-new-service:
        image: your-image:tag
        container_name: ${COMPOSE_PROJECT_NAME}-your-new-service
        restart: ${RESTART_POLICY}
        profiles:
          - your-new-service
        environment:
          - ENV_VAR=value
        ports:
          - "8080:8080"
        volumes:
          - ${DATA_PATH}/your-new-service:/data
    ```

    ### 4. 测试新服务
    使用以下命令测试新服务：
    ```powershell
    # 列出可用服务，确认新服务已添加
    .\start-container.ps1 -List
    
    # 干运行模式检查命令
    .\start-container.ps1 -ServiceName your-new-service -DryRun
    
    # 启动新服务
    .\start-container.ps1 -ServiceName your-new-service
    ```

    ### 5. 可选配置项
    - **健康检查**: 在docker-compose.yml中添加healthcheck配置
    - **网络配置**: 如需自定义网络，可使用 -NetworkName 参数
    - **环境变量**: 使用 -Env 参数传递额外环境变量
    - **数据持久化**: 确保volumes映射正确配置

    ### 6. 注意事项
    - 确保Docker镜像存在且可访问
    - 端口映射避免冲突
    - 数据目录权限正确设置
    - 环境变量安全配置
    - 考虑服务依赖关系

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
    - rustdesk-hbbs: RustDesk HBBS服务器（ID注册和心跳服务）
    - rustdesk-hbbr: RustDesk HBBR服务器（中继服务）
    - rustdesk: 同时启动 RustDesk HBBS 和 HBBR
    - rustfs: RustFS对象存储服务
    - beszel: 轻量级服务器监控 Hub
    - beszel-agent: Beszel 监控 Agent (需提供 KEY 环境变量)
    - beszel-suite: 同时启动 Beszel Hub 和 Agent

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
        'kokoro-fastapi-cpu', 'cadvisor', 'prometheus', 'noco', 'n8n', 'crawl4ai', 'pageSpy', 'new-api', 'qdrant', 'rustdesk-hbbs', 'rustdesk-hbbr', 'rustfs', 'beszel', 'beszel-agent', 'beszel-suite', 'rustdesk')]
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

function Initialize-ServiceEnvironment {
    param([string]$ServiceName, [string]$DataPath)
    if ($ServiceName -eq 'rustfs') {
        $rustfsDataPath = Join-Path $DataPath "rustfs/data"
        # Ensure parent directory exists first
        $parent = Split-Path $rustfsDataPath -Parent
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $rustfsDataPath)) {
            New-Item -ItemType Directory -Path $rustfsDataPath -Force | Out-Null
        }
        
        if ($IsLinux) {
            Write-Verbose "Checking ownership for RustFS data directory: $rustfsDataPath"
            try {
                $needsChown = $true
                try {
                    $currentOwner = & stat -c '%u' $rustfsDataPath
                    if ($currentOwner -eq '10001') { $needsChown = $false }
                }
                catch {}

                if ($needsChown) {
                    Write-Host "Setting ownership of $rustfsDataPath to 10001:10001 for RustFS..." -ForegroundColor Cyan
                    & sudo chown -R 10001:10001 $rustfsDataPath
                }
            }
            catch {
                Write-Warning "Could not change ownership of $rustfsDataPath. Please manually run: sudo chown -R 10001:10001 $rustfsDataPath"
            }
        }
    }
}

function Show-RustDeskInfo {
    param([string]$ServiceName, [string]$DataPath)
    if ($ServiceName -in @('rustdesk-hbbs', 'rustdesk-hbbr', 'rustdesk')) {
        $rustdeskPath = Join-Path $DataPath "rustdesk"
        $pubKeyFile = Join-Path $rustdeskPath "id_ed25519.pub"
        
        Write-Host "`n=== RustDesk 配置说明 ===" -ForegroundColor Cyan
        Write-Host "1. ID 服务器 (ID Server): <你的服务器IP>"
        Write-Host "2. 中继服务器 (Relay Server): <你的服务器IP>"
        
        $pubKey = $null
        for ($i = 0; $i -lt 5; $i++) {
            if (Test-Path $pubKeyFile) {
                try {
                    $pubKey = Get-Content -LiteralPath $pubKeyFile -Raw
                    if (-not [string]::IsNullOrWhiteSpace($pubKey)) { break }
                }
                catch {}
            }
            Start-Sleep -Seconds 1
        }
        
        if (-not [string]::IsNullOrWhiteSpace($pubKey)) {
            Write-Host "3. Key: $($pubKey.Trim())" -ForegroundColor Green
            Write-Host "注意：请将上述 Key 填入 RustDesk 客户端的 Key 选项中，以启用加密连接。" -ForegroundColor Yellow
        }
        else {
            Write-Host "3. Key: 未找到公钥文件或文件为空 ($pubKeyFile)" -ForegroundColor Yellow
            Write-Host "   如果这是首次启动，可能需要几秒钟生成密钥。请手动查看该文件。"
        }
        Write-Host "4. 端口映射:"
        Write-Host "   - 21114:21114 (Web Console)"
        Write-Host "   - 21115:21115 (NAT Type Test)"
        Write-Host "   - 21116:21116 (ID Reg & Heartbeat)"
        Write-Host "   - 21116:21116/udp (ID Reg & Heartbeat)"
        Write-Host "   - 21118:21118 (Web Client)"
        Write-Host "   - 21117:21117 (Relay Services)"
        Write-Host "   - 21119:21119 (Web Client)"
        # 云服务器防火墙需要配置开启
        Write-Host "云服务器防火墙需要配置开启 21115 21116 21117，否则无法连接。" -ForegroundColor Yellow
        Write-Host "==========================`n" -ForegroundColor Cyan
    }
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
    
    # 计算项目根目录路径 (动态查找)
    $current = $PSScriptRoot
    $projectRoot = $null
    while ($true) {
        if (Test-Path (Join-Path $current 'install.ps1')) {
            $projectRoot = $current
            break
        }
        $parent = Split-Path $current -Parent
        if ($null -eq $parent -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
    
    if ($null -eq $projectRoot) {
        # Fallback for safety (e.g. if install.ps1 is missing)
        # Default to 3 levels up as per original logic if search fails
        $projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Write-Warning "Could not locate project root via install.ps1, falling back to: $projectRoot"
    }

    $composeDir = Join-Path $projectRoot 'config' 'dockerfiles' 'compose'
    $composePath = Join-Path $composeDir 'docker-compose.yml'
    $mongoReplComposePath = Join-Path $composeDir 'mongo-repl.compose.yml'

    if ($Env) { foreach ($k in $Env.Keys) { ${env:$k} = [string]$Env[$k] } }

    # Beszel Agent 自动处理 Env 变量
    if ($ServiceName -eq 'beszel-agent' -or $ServiceName -eq 'beszel-suite') {
        if (-not $Env -or -not $Env['KEY']) {
            Write-Warning "启动 beszel-agent 建议提供 KEY 环境变量 (公钥)。"
            Write-Warning "示例: .\start-container.ps1 -ServiceName $ServiceName -Env @{KEY='ssh-ed25519 ...'}"
        }
        if ($Env) {
            if ($Env['KEY']) { ${env:BESZEL_AGENT_KEY} = $Env['KEY'] }
            if ($Env['TOKEN']) { ${env:BESZEL_AGENT_TOKEN} = $Env['TOKEN'] }
        }
    }

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
    
    Initialize-ServiceEnvironment -ServiceName $ServiceName -DataPath $DataPath

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
        
        # 处理组合服务 (Suite)
        $targetProfiles = @($ServiceName)
        if ($ServiceName -eq 'beszel-suite') {
            $targetProfiles = @('beszel', 'beszel-agent')
        }
        if ($ServiceName -eq 'rustdesk') {
            $targetProfiles = @('rustdesk-hbbs', 'rustdesk-hbbr')
        }

        if ($Update) {
            Invoke-DockerCompose -File $composePath -Project $projectName -Profiles $targetProfiles -Action 'pull' -DryRun:$DryRun
            Invoke-DockerCompose -File $composePath -Project $projectName -Profiles $targetProfiles -Action 'up -d' -DryRun:$DryRun
            if (-not $DryRun -and $ServiceName) {
                # 简单检查每个服务
                foreach ($tp in $targetProfiles) {
                    [void](Wait-ServiceHealthy -Service $tp -Project $projectName)
                }
                Show-RustDeskInfo -ServiceName $ServiceName -DataPath $DataPath
            }
            return
        }
        if ($PullAlways) {
            $modeForUp = Test-DockerAvailable
            if ($modeForUp -eq 'sub') {
                Invoke-DockerCompose -File $composePath -Project $projectName -Profiles $targetProfiles -Action 'up -d' -ExtraArgs @('--pull', 'always') -DryRun:$DryRun
                if (-not $DryRun -and $ServiceName) {
                    foreach ($tp in $targetProfiles) {
                        [void](Wait-ServiceHealthy -Service $tp -Project $projectName)
                    }
                    Show-RustDeskInfo -ServiceName $ServiceName -DataPath $DataPath
                }
            }
            else {
                Invoke-DockerCompose -File $composePath -Project $projectName -Profiles $targetProfiles -Action 'pull' -DryRun:$DryRun
                Invoke-DockerCompose -File $composePath -Project $projectName -Profiles $targetProfiles -Action 'up -d' -DryRun:$DryRun
                if (-not $DryRun -and $ServiceName) {
                    foreach ($tp in $targetProfiles) {
                        [void](Wait-ServiceHealthy -Service $tp -Project $projectName)
                    }
                    Show-RustDeskInfo -ServiceName $ServiceName -DataPath $DataPath
                }
            }
            return
        }
        if ($Down) {
            if ($ServiceName) {
                # 针对组合服务，需要找出实际的服务名（通常与profile同名）
                # 这里假设 profile 名即为 service 名，或者在 docker-compose 中 profile 和 service 是一一对应的
                Invoke-DockerCompose -File $composePath -Project $projectName -Action 'stop' -Services $targetProfiles -DryRun:$DryRun
                Invoke-DockerCompose -File $composePath -Project $projectName -Action 'rm -f -s' -Services $targetProfiles -DryRun:$DryRun
            }
            else {
                Invoke-DockerCompose -File $composePath -Project $projectName -Action 'down' -DryRun:$DryRun
            }
            return
        }
        if ($Pull) {
            Invoke-DockerCompose -File $composePath -Project $projectName -Profiles $targetProfiles -Action 'pull' -DryRun:$DryRun
            return
        }
        if ($Build) {
            Invoke-DockerCompose -File $composePath -Project $projectName -Profiles $targetProfiles -Action 'build' -DryRun:$DryRun
            return
        }
        
        # 检查服务是否存在 (对于 suite，只要不是未定义即可，这里稍微放宽检查或者针对 suite 特殊处理)
        $isValidService = ($available -contains $ServiceName)
        if ($ServiceName -eq 'beszel-suite' -or $ServiceName -eq 'rustdesk') { $isValidService = $true }

        if ($isValidService) {
            Invoke-DockerCompose -File $composePath -Project $projectName -Profiles $targetProfiles -Action 'up -d' -DryRun:$DryRun
            if (-not $DryRun) {
                foreach ($tp in $targetProfiles) {
                    [void](Wait-ServiceHealthy -Service $tp -Project $projectName)
                }
                Show-RustDeskInfo -ServiceName $ServiceName -DataPath $DataPath
            }
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
