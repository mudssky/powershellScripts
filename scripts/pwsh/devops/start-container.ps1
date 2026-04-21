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
        "qdrant", "paradedb", "your-new-service")]
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
    - paradedb: 基于 PostgreSQL 17 的 ParadeDB 搜索数据库
    - rustdesk-hbbs: RustDesk HBBS服务器（ID注册和心跳服务）
    - rustdesk-hbbr: RustDesk HBBR服务器（中继服务）
    - rustdesk: 同时启动 RustDesk HBBS 和 HBBR
    - rustfs: RustFS对象存储服务
    - beszel: 轻量级服务器监控 Hub
    - gotify: 简单的消息推送服务器
    - open-webui: 适用于 LLM 的 WebUI

.PARAMETER RestartPolicy
    容器重启策略，默认为'unless-stopped'。可选值：
    - always: 总是重启
    - unless-stopped: 除非手动停止否则重启
    - on-failure: 失败时重启
    - on-failure:3: 失败时最多重启3次
    - no: 不自动重启

.PARAMETER DataPath
    数据存储目录。未显式传入时，会按当前系统自动选择默认值：
    - Windows: `C:\docker_data`
    - Linux: `/var/lib/docker_data`
    - macOS: `/Volumes/Data/docker_data`

    volume路径示例（遵循当前默认值）：
    - Windows: `${DATA_PATH}/redis:/data` -> `C:\docker_data\redis:/data`
    - Linux: `${DATA_PATH}/redis:/data` -> `/var/lib/docker_data/redis:/data`
    - macOS: `${DATA_PATH}/redis:/data` -> `/Volumes/Data/docker_data/redis:/data`

.PARAMETER DefaultUser
    默认用户名。未显式传入时，`postgre` / `paradedb` 默认使用"postgres"，
    其他服务默认使用"root"。

.PARAMETER DefaultPassword
    默认密码，默认为"12345678"

.PARAMETER BindLocalhost
    控制宿主机端口是否只绑定到 `127.0.0.1`。
    未显式传入时，脚本会读取 `config/dockerfiles/compose/.env.local` 中的 `BIND_LOCALHOST`；
    若两者都未设置，则默认对外发布端口。

.EXAMPLE
    .\start-container.ps1 -ServiceName redis
    启动Redis容器服务

.EXAMPLE
    .\start-container.ps1 -ServiceName mongodb -RestartPolicy always -DataPath "D:/data"
    启动MongoDB服务并自定义重启策略和数据目录

.EXAMPLE
    # Windows 默认 volume 根路径
    .\start-container.ps1 -ServiceName redis
    等效数据目录示例：C:\docker_data\redis

.EXAMPLE
    # Linux 默认 volume 根路径
    ./start-container.ps1 -ServiceName redis
    等效数据目录示例：/var/lib/docker_data/redis

.EXAMPLE
    # macOS 默认 volume 根路径
    ./start-container.ps1 -ServiceName redis
    等效数据目录示例：/Volumes/Data/docker_data/redis

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

.EXAMPLE
    ./start-container.ps1 -ServiceName postgre -BindLocalhost
    以 localhost 绑定模式启动 PostgreSQL，仅允许宿主机本机访问

	.NOTES
    需要安装Docker
    脚本会自动创建必要的数据目录
    某些服务可能需要额外的配置文件
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet(
        "minio", 
        "redis",
        "postgre", 
        "etcd", 
        "nacos", 
        "rabbitmq", 
        "mongodb", 
        "one-api", 
        "mongodb-replica", 
        # tts
        "kokoro-fastapi", 
        "kokoro-fastapi-cpu", 
        "cadvisor", 
        "prometheus", 
        "noco", 
        "n8n", 
        "crawl4ai", 
        "pageSpy", 
        "new-api", 
        "qdrant", 
        "paradedb",
        "rustdesk-hbbs", 
        "rustdesk-hbbr", 
        "rustfs", 
        "beszel", 
        "rustdesk", 
        "gotify",
        "sillytavern",
        "open-webui"
    )]
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
    [AllowNull()]
    [Nullable[bool]]$BindLocalhost = $null,
    [hashtable]$Env,
    [switch]$UseEnvFile,
    [switch]$AskPass
)
  
# 设置默认 docker 映射路径
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StartContainerConfigModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\psutils\modules\config.psm1'))
Import-Module $script:StartContainerConfigModulePath -Force

function Get-PlainTextFromSecure {
    param([SecureString]$Secure)
    if ($null -eq $Secure) { return "" }
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Initialize-DataPath {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($IsWindows) { $Path = "C:\\docker_data" }
        elseif ($IsLinux) { $Path = "/var/lib/docker_data" }
        elseif ($IsMacOS) { $Path = "/Volumes/Data/docker_data" }
    }
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            if ($PSCmdlet.ShouldProcess($Path, 'Create data directory')) {
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
            }
            else {
                return $Path
            }
        }
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
        if (-not [string]::IsNullOrWhiteSpace($ServiceName)) { $name = ("dev-" + $ServiceName) } else { $name = "compose" }
    }
    $normalized = ($name.ToLower() -replace '[^a-z0-9\-]', '-')
    if ($normalized.Length -gt 40) { $normalized = $normalized.Substring(0, 40) }
    return $normalized
}

function ConvertTo-NullableBooleanPreference {
    <#
    .SYNOPSIS
        将 CLI 或 env 中的布尔偏好统一解析为可空布尔值。

    .DESCRIPTION
        接受布尔值本身，以及 `true/false`、`1/0`、`yes/no`、`on/off` 这些字符串。
        对非法值直接抛错，避免因为配置拼写错误导致端口暴露策略失真。

    .PARAMETER Value
        待解析的原始值，可为 `$null`、布尔值或字符串。

    .PARAMETER SettingName
        报错时使用的配置名称，便于定位问题来源。

    .OUTPUTS
        System.Nullable[System.Boolean]
        返回解析后的布尔值；若未提供值则返回 `$null`。
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,
        [string]$SettingName
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $normalized = ([string]$Value).Trim().ToLowerInvariant()
    switch ($normalized) {
        'true' { return $true }
        '1' { return $true }
        'yes' { return $true }
        'on' { return $true }
        'false' { return $false }
        '0' { return $false }
        'no' { return $false }
        'off' { return $false }
        default { throw "$SettingName 只能是 true/false、1/0、yes/no 或 on/off，当前值为: $Value" }
    }
}

function Resolve-BindLocalhostPreference {
    <#
    .SYNOPSIS
        解析本次 compose 调用是否启用 localhost 端口绑定。

    .DESCRIPTION
        优先使用 CLI 显式传入值；未传入时回退到 compose 配置来源中的 `BIND_LOCALHOST`；
        两者都没有时默认返回 `$false`。

    .PARAMETER CliBindLocalhost
        通过命令行显式传入的绑定偏好；允许为 `$null` 以表示“不覆盖配置文件”。

    .PARAMETER ComposeEnvironment
        `Resolve-ServiceComposeConfiguration` 合并后的配置字典。

    .OUTPUTS
        System.Boolean
        返回最终是否启用 localhost 绑定。
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [Nullable[bool]]$CliBindLocalhost,
        [hashtable]$ComposeEnvironment
    )

    if ($null -ne $CliBindLocalhost) {
        return [bool]$CliBindLocalhost
    }

    $rawSetting = if ($ComposeEnvironment.ContainsKey('BIND_LOCALHOST')) {
        $ComposeEnvironment.BIND_LOCALHOST
    }
    else {
        $null
    }

    $resolved = ConvertTo-NullableBooleanPreference -Value $rawSetting -SettingName 'BIND_LOCALHOST'
    if ($null -ne $resolved) {
        return [bool]$resolved
    }

    return $false
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$File,
        [string[]]$AdditionalFiles,
        [string]$Project,
        [string[]]$Profiles,
        [string[]]$Services,
        [string]$Action,
        [string[]]$ExtraArgs,
        [switch]$DryRun,
        [hashtable]$Environment
    )
    $mode = $null
    if (-not $DryRun -and -not $WhatIfPreference) { $mode = Test-DockerAvailable } else { $mode = 'sub' }
    $dcArgs = @()
    if ($mode -eq 'sub') { $dcArgs += 'compose' }
    if ($File) { $dcArgs += @('-f', $File) }
    if ($AdditionalFiles) {
        foreach ($additionalFile in $AdditionalFiles) {
            if (-not [string]::IsNullOrWhiteSpace($additionalFile)) {
                $dcArgs += @('-f', $additionalFile)
            }
        }
    }
    if ($Project) { $dcArgs += @('-p', $Project) }
    if ($Profiles) { foreach ($p in $Profiles) { if (-not [string]::IsNullOrWhiteSpace($p)) { $dcArgs += @('--profile', $p) } } }
    if ($Action) { $dcArgs += ($Action -split ' ') }
    if ($Services) { $dcArgs += $Services }
    if ($ExtraArgs) { $dcArgs += $ExtraArgs }
    $preview = if ($mode -eq 'sub') { "docker " + ($dcArgs -join ' ') } else { "docker-compose " + ($dcArgs -join ' ') }
    $invokeCompose = {
        if ($DryRun) {
            $preview
        }
        elseif ($mode -eq 'sub') {
            & docker @dcArgs
        }
        else {
            & docker-compose @dcArgs
        }
    }

    if (-not $DryRun -and -not $PSCmdlet.ShouldProcess($preview, 'Execute Docker Compose')) {
        return
    }

    if ($Environment -and $Environment.Count -gt 0) {
        return Invoke-WithScopedEnvironment -Variables $Environment -ScriptBlock $invokeCompose
    }

    return & $invokeCompose
}

function Get-NetworkExists {
    param([string]$Name)
    try { & docker network ls -q -f name=$Name } catch { return $null }
}

function Import-EnvFile {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        Write-Verbose "Loading environment file: $FilePath"
        foreach ($line in Get-Content -LiteralPath $FilePath) {
            $line = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
            $index = $line.IndexOf('=')
            if ($index -gt 0) {
                $key = $line.Substring(0, $index).Trim()
                $value = $line.Substring($index + 1).Trim()
                # 移除可能的引号
                if ($value.StartsWith('"') -and $value.EndsWith('"')) { $value = $value.Substring(1, $value.Length - 2) }
                elseif ($value.StartsWith("'") -and $value.EndsWith("'")) { $value = $value.Substring(1, $value.Length - 2) }
                
                if (-not [string]::IsNullOrWhiteSpace($key)) {
                    [System.Environment]::SetEnvironmentVariable($key, $value)
                }
            }
        }
    }
}

function New-NetworkIfMissing {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $exists = Get-NetworkExists -Name $Name
    if ([string]::IsNullOrWhiteSpace($exists)) {
        try {
            if ($PSCmdlet.ShouldProcess($Name, 'Create Docker network')) {
                & docker network create $Name | Out-Null
            }
        }
        catch {}
    }
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$ServiceName, [string]$DataPath)
    if ($ServiceName -eq 'rustfs') {
        $rustfsDataPath = Join-Path $DataPath "rustfs/data"
        # Ensure parent directory exists first
        $parent = Split-Path $rustfsDataPath -Parent
        if (-not (Test-Path -LiteralPath $parent)) {
            if ($PSCmdlet.ShouldProcess($parent, 'Create RustFS parent directory')) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
        }
        if (-not (Test-Path -LiteralPath $rustfsDataPath)) {
            if ($PSCmdlet.ShouldProcess($rustfsDataPath, 'Create RustFS data directory')) {
                New-Item -ItemType Directory -Path $rustfsDataPath -Force | Out-Null
            }
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
                    if ($PSCmdlet.ShouldProcess($rustfsDataPath, 'Set RustFS directory ownership to 10001:10001')) {
                        & sudo chown -R 10001:10001 $rustfsDataPath
                    }
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


function Get-LanIpAddress {
    try {
        $hostEntry = [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName())
        $ip = $hostEntry.AddressList | 
            Where-Object { $_.AddressFamily -eq 'InterNetwork' } | 
            Select-Object -ExpandProperty IPAddressToString -First 1
        return $ip
    }
    catch {
        return $null
    }
}

function Get-ServiceAccessDisplayInfo {
    <#
    .SYNOPSIS
        生成单个端口映射的用户可读访问信息。

    .DESCRIPTION
        统一处理 `0.0.0.0`、`::`、`127.0.0.1` 与 `::1` 这些常见绑定地址，
        保证 localhost 模式下不再误导性输出局域网访问地址。

    .PARAMETER HostIp
        `docker port` 返回的宿主机监听地址。

    .PARAMETER HostPort
        `docker port` 返回的宿主机端口。

    .PARAMETER ContainerPort
        容器内部端口。

    .PARAMETER Protocol
        端口协议，例如 `tcp` 或 `udp`。

    .PARAMETER LanIp
        当前宿主机推断出的局域网 IPv4 地址。

    .OUTPUTS
        PSCustomObject
        返回 `Local` 与 `Lan` 两个已格式化的访问地址。
    #>
    [CmdletBinding()]
    param(
        [string]$HostIp,
        [string]$HostPort,
        [string]$ContainerPort,
        [string]$Protocol,
        [string]$LanIp
    )

    $isBindAll = ($HostIp -eq '0.0.0.0' -or $HostIp -eq '::')
    $isLoopback = ($HostIp -eq '127.0.0.1' -or $HostIp -eq '::1')
    $displayHost = if ($isBindAll -or $isLoopback) { 'localhost' } else { $HostIp }

    $formatUrl = {
        param($ip, $port, $cPort, $proto)
        $u = "${ip}:${port}"
        if ($proto -eq 'tcp') {
            if ($cPort -eq '80' -or $cPort -match '^(3000|5000|8000|8080|8888|9000|9999)$') {
                return "http://$u"
            }
            elseif ($cPort -eq '443') {
                return "https://$u"
            }
        }
        return $u
    }

    $lanUrl = $null
    if ($isBindAll -and -not [string]::IsNullOrWhiteSpace($LanIp) -and $LanIp -ne '127.0.0.1') {
        $lanUrl = & $formatUrl -ip $LanIp -port $HostPort -cPort $ContainerPort -proto $Protocol
    }

    return [pscustomobject]@{
        Local = (& $formatUrl -ip $displayHost -port $HostPort -cPort $ContainerPort -proto $Protocol)
        Lan   = $lanUrl
    }
}

function Show-ServiceAccessInfo {
    param(
        [string[]]$Services,
        [string]$ProjectName
    )
    if (-not $Services) { return }

    $lanIp = Get-LanIpAddress
    $hasPrintedHeader = $false

    foreach ($svc in $Services) {
        try {
            $psArgs = @('ps', '-q', '--filter', "label=com.docker.compose.service=$svc")
            if ($ProjectName) { $psArgs += @('--filter', "label=com.docker.compose.project=$ProjectName") }
            
            $containerIds = & docker @psArgs
            if ([string]::IsNullOrWhiteSpace($containerIds)) { continue }
            
            foreach ($cid in ($containerIds -split '\s+')) {
                if ([string]::IsNullOrWhiteSpace($cid)) { continue }
                
                $portOutput = & docker port $cid 2>$null
                if ([string]::IsNullOrWhiteSpace($portOutput)) { continue }
                
                if (-not $hasPrintedHeader) {
                    Write-Host "`n=== 服务访问信息 ($ProjectName) ===" -ForegroundColor Cyan
                    $hasPrintedHeader = $true
                }

                Write-Host "Service: $svc" -ForegroundColor Green
                
                $lines = $portOutput -split '\r?\n'
                foreach ($line in $lines) {
                    if ($line -match '^(\d+)/(\w+)\s*->\s*(.+):(\d+)$') {
                        $containerPort = $Matches[1]
                        $proto = $Matches[2]
                        $hostIp = $Matches[3]
                        $hostPort = $Matches[4]
                        $accessInfo = Get-ServiceAccessDisplayInfo `
                            -HostIp $hostIp `
                            -HostPort $hostPort `
                            -ContainerPort $containerPort `
                            -Protocol $proto `
                            -LanIp $lanIp
                        Write-Host "  - Port $containerPort/$proto"
                        Write-Host "    Local: $($accessInfo.Local)"
                        
                        if (-not [string]::IsNullOrWhiteSpace($accessInfo.Lan)) {
                            Write-Host "    LAN:   $($accessInfo.Lan)"
                        }
                    }
                    else {
                        Write-Host "  - $line"
                    }
                }
            }
        }
        catch {
            Write-Verbose "Error getting info for ${svc}: $_"
        }
    }
    if ($hasPrintedHeader) {
        Write-Host "================================`n" -ForegroundColor Cyan
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

function Get-ComposeServiceDefinitionText {
    <#
    .SYNOPSIS
        读取 compose 文件中的单个服务定义块。

    .DESCRIPTION
        按仓库当前受控的 YAML 缩进格式截取服务文本，
        供端口重写和静态分析逻辑复用，避免为这类受限格式引入完整 YAML 解析依赖。

    .PARAMETER ComposePath
        基础 compose 文件路径。

    .PARAMETER ServiceName
        需要读取的服务名。

    .OUTPUTS
        System.String
        服务定义对应的原始文本块。
    #>
    [CmdletBinding()]
    param(
        [string]$ComposePath,
        [string]$ServiceName
    )

    $lines = Get-Content -LiteralPath $ComposePath
    $startIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^\s{2}$([regex]::Escape($ServiceName)):\s*$") {
            $startIndex = $index
            break
        }
    }

    if ($startIndex -lt 0) {
        throw "未找到 compose 服务块: $ServiceName"
    }

    $blockLines = New-Object 'System.Collections.Generic.List[string]'
    for ($index = $startIndex; $index -lt $lines.Count; $index++) {
        if ($index -gt $startIndex -and $lines[$index] -match '^\s{2}[A-Za-z0-9\-_]+:\s*$') {
            break
        }

        $blockLines.Add($lines[$index])
    }

    return ($blockLines -join "`n")
}

function Get-ComposeServicePortMappings {
    <#
    .SYNOPSIS
        提取 compose 服务块中可重写的端口映射。

    .DESCRIPTION
        仅支持仓库当前实际使用的两类 `ports:` 写法：
        行内数组写法与多行字符串列表写法。若命中 `network_mode: host`，
        会直接抛错，明确告知 localhost 绑定不适用于该服务。

    .PARAMETER ComposePath
        基础 compose 文件路径。

    .PARAMETER ServiceName
        需要提取端口映射的服务名。

    .OUTPUTS
        System.String[]
        服务定义中的宿主机端口映射字符串。
    #>
    [CmdletBinding()]
    param(
        [string]$ComposePath,
        [string]$ServiceName
    )

    $block = Get-ComposeServiceDefinitionText -ComposePath $ComposePath -ServiceName $ServiceName
    if ($block -match '(?m)^\s{4}network_mode:\s*host\s*$') {
        throw "服务 $ServiceName 使用 network_mode: host，-BindLocalhost 只支持 ports: 服务"
    }

    $blockLines = $block -split '\r?\n'
    $inlinePortLine = $blockLines | Where-Object { $_ -match '^\s{4}ports:\s*\[(.+)\]\s*$' } | Select-Object -First 1
    if ($null -ne $inlinePortLine) {
        $inlineMatch = [regex]::Match($inlinePortLine, '^\s{4}ports:\s*\[(.+)\]\s*$')
        return @(($inlineMatch.Groups[1].Value -split ',') | ForEach-Object {
            $_.Trim().Trim('"').Trim("'")
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $portStartIndex = -1
    for ($index = 0; $index -lt $blockLines.Count; $index++) {
        if ($blockLines[$index] -match '^\s{4}ports:\s*$') {
            $portStartIndex = $index
            break
        }
    }

    if ($portStartIndex -lt 0) {
        return @()
    }

    $mappings = New-Object 'System.Collections.Generic.List[string]'
    for ($index = $portStartIndex + 1; $index -lt $blockLines.Count; $index++) {
        $line = $blockLines[$index]
        if ($line -match '^\s{4}[A-Za-z0-9\-_]+:\s*$') {
            break
        }

        if ($line -match '^\s{6}-\s*"?([^"\r\n]+)"?\s*$') {
            $mappings.Add($Matches[1].Trim())
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($line) -and $line -notmatch '^\s*$') {
            throw "服务 $ServiceName 包含暂不支持的 ports: 行格式: $line"
        }
    }

    return @($mappings.ToArray())
}

function Convert-PortMappingToLocalhost {
    <#
    .SYNOPSIS
        将宿主机端口映射转换为 localhost 绑定形式。

    .DESCRIPTION
        仅接受当前仓库模板里使用的简单 `host:container` 与 `host:container/protocol` 格式，
        避免在不明确的映射语法上做静默推断。

    .PARAMETER Mapping
        原始端口映射字符串。

    .OUTPUTS
        System.String
        加上 `127.0.0.1:` 前缀后的端口映射。
    #>
    [CmdletBinding()]
    param([string]$Mapping)

    if ([string]::IsNullOrWhiteSpace($Mapping)) {
        throw '端口映射不能为空'
    }

    if ($Mapping -match '^\d+:\d+(/\w+)?$') {
        return "127.0.0.1:$Mapping"
    }

    throw "暂不支持的 ports 映射格式: $Mapping"
}

function New-LocalhostComposeOverrideFile {
    <#
    .SYNOPSIS
        为目标服务生成一次性的 localhost override compose 文件。

    .DESCRIPTION
        通过追加一个临时 compose 文件覆写指定服务的 `ports:`，
        让现有基础模板在不改默认暴露策略的前提下支持本次调用的 localhost 绑定。

    .PARAMETER ComposePath
        基础 compose 文件路径。

    .PARAMETER ServiceNames
        需要改写端口映射的服务名集合。

    .OUTPUTS
        System.String
        临时 override compose 文件路径。
    #>
    [CmdletBinding()]
    param(
        [string]$ComposePath,
        [string[]]$ServiceNames
    )

    $overrideLines = New-Object 'System.Collections.Generic.List[string]'
    $overrideLines.Add('services:')

    foreach ($serviceName in $ServiceNames) {
        $portMappings = @(Get-ComposeServicePortMappings -ComposePath $ComposePath -ServiceName $serviceName)
        if ($portMappings.Count -eq 0) {
            throw "服务 $serviceName 没有可改写的 ports: 配置"
        }

        $overrideLines.Add("  ${serviceName}:")
        $overrideLines.Add('    ports:')
        foreach ($mapping in $portMappings) {
            $overrideLines.Add("      - `"$((Convert-PortMappingToLocalhost -Mapping $mapping))`"")
        }
    }

    $overridePath = Join-Path ([System.IO.Path]::GetTempPath()) ("start-container.localhost.override.{0}.yml" -f ([System.Guid]::NewGuid().ToString('N')))
    Set-Content -LiteralPath $overridePath -Value ($overrideLines -join [Environment]::NewLine) -Encoding utf8NoBOM
    return $overridePath
}

function Get-ServiceDefaultUser {
    <#
    .SYNOPSIS
        返回服务级默认用户名。

    .DESCRIPTION
        为 PostgreSQL 系服务提供更符合约定的默认用户名，
        同时保持其他服务继续沿用通用的 `root` 默认值。

    .PARAMETER ServiceName
        需要解析默认用户名的服务名。

    .OUTPUTS
        System.String
        服务在未显式传入用户名时应使用的默认用户名。
    #>
    param([string]$ServiceName)

    if ($ServiceName -in @('postgre', 'paradedb')) {
        return 'postgres'
    }

    return 'root'
}

function Resolve-ServiceDefaultUser {
    <#
    .SYNOPSIS
        按优先级解析服务最终使用的默认用户名。

    .DESCRIPTION
        解析顺序为显式命令行参数、现有环境变量、服务级默认值，
        保证 PostgreSQL 系服务在未覆写时回落到 `postgres`。

    .PARAMETER ServiceName
        当前要启动的服务名。

    .PARAMETER CliDefaultUser
        通过命令行显式传入的默认用户名。

    .PARAMETER EnvironmentDefaultUser
        已经从 shell、`.env`、`.env.local` 或 `-Env` 注入的 `DEFAULT_USER`。

    .OUTPUTS
        System.String
        解析后的最终默认用户名。
    #>
    param(
        [string]$ServiceName,
        [string]$CliDefaultUser,
        [string]$EnvironmentDefaultUser
    )

    if (-not [string]::IsNullOrWhiteSpace($CliDefaultUser)) {
        return $CliDefaultUser
    }

    if (-not [string]::IsNullOrWhiteSpace($EnvironmentDefaultUser)) {
        return $EnvironmentDefaultUser
    }

    return Get-ServiceDefaultUser -ServiceName $ServiceName
}

function Get-ServiceConfigDefaults {
    [CmdletBinding()]
    param(
        [string]$ServiceName,
        [string]$DataPath,
        [string]$DefaultUser,
        [string]$DefaultPassword,
        [string]$RestartPolicy,
        [string]$ProjectName
    )

    $resolvedDefaultUser = if ([string]::IsNullOrWhiteSpace($DefaultUser)) {
        Get-ServiceDefaultUser -ServiceName $ServiceName
    }
    else {
        $DefaultUser
    }

    return @{
        DATA_PATH            = $DataPath
        DEFAULT_USER         = $resolvedDefaultUser
        DEFAULT_PASSWORD     = $DefaultPassword
        # 默认保持当前对外发布行为，只有显式配置时才切到 localhost 绑定。
        BIND_LOCALHOST       = $false
        RESTART_POLICY       = $RestartPolicy
        COMPOSE_PROJECT_NAME = $ProjectName
    }
}

function Resolve-ServiceComposeConfiguration {
    [CmdletBinding()]
    param(
        [string]$ServiceName,
        [string]$ComposeDir,
        [hashtable]$CliEnv,
        [string]$DataPath,
        [string]$DefaultUser,
        [string]$DefaultPassword,
        [string]$RestartPolicy,
        [string]$ProjectName
    )

    $sources = @(
        @{ Type = 'Hashtable'; Name = 'ServiceDefaults'; Data = (Get-ServiceConfigDefaults -ServiceName $ServiceName -DataPath $DataPath -DefaultUser $DefaultUser -DefaultPassword $DefaultPassword -RestartPolicy $RestartPolicy -ProjectName $ProjectName) }
    )

    if ($ServiceName -notin @('postgre', 'paradedb')) {
        $sources += @{ Type = 'ProcessEnv'; Name = 'ProcessEnv' }
    }

    $sources += @(
        @{ Type = 'EnvFile'; Name = '.env'; Path = (Join-Path $ComposeDir '.env') }
        @{ Type = 'EnvFile'; Name = '.env.local'; Path = (Join-Path $ComposeDir '.env.local') }
        @{ Type = 'Hashtable'; Name = 'CliEnv'; Data = $CliEnv }
    )

    return Resolve-ConfigSources -Sources $sources -BasePath $ComposeDir -IncludeTrace
}

function Get-DatabaseStateWarningMessage {
    [CmdletBinding()]
    param(
        [string]$ServiceName,
        [string]$DataPath
    )

    $candidateFiles = switch ($ServiceName) {
        'postgre' {
            @(
                [System.IO.Path]::Combine($DataPath, 'postgresql', 'data', 'PG_VERSION'),
                [System.IO.Path]::Combine($DataPath, 'postgresql', 'PG_VERSION')
            )
        }
        'paradedb' {
            @(
                [System.IO.Path]::Combine($DataPath, 'paradedb', 'data', 'PG_VERSION'),
                [System.IO.Path]::Combine($DataPath, 'paradedb', 'PG_VERSION')
            )
        }
        default {
            @()
        }
    }

    foreach ($candidate in $candidateFiles) {
        if (Test-Path -LiteralPath $candidate) {
            return "检测到已初始化的 $ServiceName 数据目录 ($candidate)。当前用户名、密码、库名配置仅影响新初始化实例；已有数据目录不会自动迁移内部角色、密码或默认库。"
        }
    }

    return $null
}

# 测试加载脚本时跳过主流程，避免 dot-source 触发真实 Docker 调用。
if ($env:PWSH_TEST_SKIP_START_CONTAINER_MAIN -eq '1') {
    return
}

try {
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

    if ($AskPass) {
        $DefaultPassword = Read-Host -AsSecureString -Prompt "请输入默认密码 (DefaultPassword)"
    }

    $plainPwd = (Get-PlainTextFromSecure -Secure $DefaultPassword)
    $cliDefaultUser = if ($PSBoundParameters.ContainsKey('DefaultUser')) { $DefaultUser } else { $null }
    $projectName = Get-DefaultProjectName -ServiceName $ServiceName -ProjectNameInput $ProjectName
    $cliEnv = if ($Env) { @{} + $Env } else { @{} }
    $composeConfig = Resolve-ServiceComposeConfiguration `
        -ServiceName $ServiceName `
        -ComposeDir $composeDir `
        -CliEnv $cliEnv `
        -DataPath $DataPath `
        -DefaultUser $cliDefaultUser `
        -DefaultPassword $plainPwd `
        -RestartPolicy $RestartPolicy `
        -ProjectName $projectName
    $composeEnvironment = $composeConfig.Values
    $bindLocalhostEnabled = Resolve-BindLocalhostPreference -CliBindLocalhost $BindLocalhost -ComposeEnvironment $composeEnvironment
    $projectName = [string]$composeEnvironment.COMPOSE_PROJECT_NAME

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
        if ($bindLocalhostEnabled) {
            Write-Warning 'mongodb-replica 当前仍使用独立 compose 分支，暂不支持 -BindLocalhost。'
        }

        if ($PSBoundParameters.ContainsKey('DataPath')) { ${env:DOCKER_DATA_PATH} = $DataPath }
        if ($PSBoundParameters.ContainsKey('DefaultUser')) { ${env:MONGO_USER} = $DefaultUser }
        if ($PSBoundParameters.ContainsKey('DefaultPassword')) { ${env:MONGO_PASSWORD} = $plainPwd }

        if ([string]::IsNullOrWhiteSpace(${env:DOCKER_DATA_PATH})) { ${env:DOCKER_DATA_PATH} = $DataPath }
        if ([string]::IsNullOrWhiteSpace(${env:MONGO_USER})) { ${env:MONGO_USER} = $DefaultUser }
        if ([string]::IsNullOrWhiteSpace(${env:MONGO_PASSWORD})) { ${env:MONGO_PASSWORD} = $plainPwd }
        Invoke-DockerCompose -File $mongoReplComposePath -Project $projectName -Action 'up -d' -DryRun:$DryRun
        if (-not $DryRun -and -not $WhatIfPreference) { [void](Wait-ServiceHealthy -Service 'mongo1' -Project $projectName) }
        return
    }
    if (Test-Path $composePath) {
        $available = Get-ComposeServiceNames -ComposePath $composePath -ReplicaComposePath $mongoReplComposePath
        
        # 处理组合服务 (Suite)
        $targetProfiles = @($ServiceName)
        if ($ServiceName -eq 'rustdesk') {
            $targetProfiles = @('rustdesk-hbbs', 'rustdesk-hbbr')
        }

        $additionalComposeFiles = @()
        $localhostOverridePath = $null

        try {
            if ($bindLocalhostEnabled -and $ServiceName) {
                $localhostOverridePath = New-LocalhostComposeOverrideFile -ComposePath $composePath -ServiceNames $targetProfiles
                $additionalComposeFiles += $localhostOverridePath
            }

            if ($Update) {
                $databaseWarning = Get-DatabaseStateWarningMessage -ServiceName $ServiceName -DataPath $composeEnvironment.DATA_PATH
                if (-not [string]::IsNullOrWhiteSpace($databaseWarning)) { Write-Warning $databaseWarning }
                Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Profiles $targetProfiles -Action 'pull' -Environment $composeEnvironment -DryRun:$DryRun
                Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Profiles $targetProfiles -Action 'up -d' -Environment $composeEnvironment -DryRun:$DryRun
                if (-not $DryRun -and -not $WhatIfPreference -and $ServiceName) {
                    # 简单检查每个服务
                    foreach ($tp in $targetProfiles) {
                        [void](Wait-ServiceHealthy -Service $tp -Project $projectName)
                    }
                    Show-RustDeskInfo -ServiceName $ServiceName -DataPath $DataPath
                    Show-ServiceAccessInfo -Services $targetProfiles -ProjectName $projectName
                }
                return
            }
            if ($PullAlways) {
                $modeForUp = Test-DockerAvailable
                if ($modeForUp -eq 'sub') {
                    $databaseWarning = Get-DatabaseStateWarningMessage -ServiceName $ServiceName -DataPath $composeEnvironment.DATA_PATH
                    if (-not [string]::IsNullOrWhiteSpace($databaseWarning)) { Write-Warning $databaseWarning }
                    Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Profiles $targetProfiles -Action 'up -d' -ExtraArgs @('--pull', 'always') -Environment $composeEnvironment -DryRun:$DryRun
                    if (-not $DryRun -and -not $WhatIfPreference -and $ServiceName) {
                        foreach ($tp in $targetProfiles) {
                            [void](Wait-ServiceHealthy -Service $tp -Project $projectName)
                        }
                        Show-RustDeskInfo -ServiceName $ServiceName -DataPath $DataPath
                        Show-ServiceAccessInfo -Services $targetProfiles -ProjectName $projectName
                    }
                }
                else {
                    $databaseWarning = Get-DatabaseStateWarningMessage -ServiceName $ServiceName -DataPath $composeEnvironment.DATA_PATH
                    if (-not [string]::IsNullOrWhiteSpace($databaseWarning)) { Write-Warning $databaseWarning }
                    Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Profiles $targetProfiles -Action 'pull' -Environment $composeEnvironment -DryRun:$DryRun
                    Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Profiles $targetProfiles -Action 'up -d' -Environment $composeEnvironment -DryRun:$DryRun
                    if (-not $DryRun -and -not $WhatIfPreference -and $ServiceName) {
                        foreach ($tp in $targetProfiles) {
                            [void](Wait-ServiceHealthy -Service $tp -Project $projectName)
                        }
                        Show-RustDeskInfo -ServiceName $ServiceName -DataPath $DataPath
                        Show-ServiceAccessInfo -Services $targetProfiles -ProjectName $projectName
                    }
                }
                return
            }
            if ($Down) {
                if ($ServiceName) {
                    # 针对组合服务，需要找出实际的服务名（通常与profile同名）
                    # 这里假设 profile 名即为 service 名，或者在 docker-compose 中 profile 和 service 是一一对应的
                    Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Action 'stop' -Services $targetProfiles -Environment $composeEnvironment -DryRun:$DryRun
                    Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Action 'rm -f -s' -Services $targetProfiles -Environment $composeEnvironment -DryRun:$DryRun
                }
                else {
                    Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Action 'down' -Environment $composeEnvironment -DryRun:$DryRun
                }
                return
            }
            if ($Pull) {
                Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Profiles $targetProfiles -Action 'pull' -Environment $composeEnvironment -DryRun:$DryRun
                return
            }
            if ($Build) {
                Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Profiles $targetProfiles -Action 'build' -Environment $composeEnvironment -DryRun:$DryRun
                return
            }
            
            # 检查服务是否存在 (对于 suite，只要不是未定义即可，这里稍微放宽检查或者针对 suite 特殊处理)
            $isValidService = ($available -contains $ServiceName)
            if ($ServiceName -eq 'beszel-suite' -or $ServiceName -eq 'rustdesk') { $isValidService = $true }

            if ($isValidService) {
                $databaseWarning = Get-DatabaseStateWarningMessage -ServiceName $ServiceName -DataPath $composeEnvironment.DATA_PATH
                if (-not [string]::IsNullOrWhiteSpace($databaseWarning)) { Write-Warning $databaseWarning }
                Invoke-DockerCompose -File $composePath -AdditionalFiles $additionalComposeFiles -Project $projectName -Profiles $targetProfiles -Action 'up -d' -Environment $composeEnvironment -DryRun:$DryRun
                if (-not $DryRun -and -not $WhatIfPreference) {
                    foreach ($tp in $targetProfiles) {
                        [void](Wait-ServiceHealthy -Service $tp -Project $projectName)
                    }
                    Show-RustDeskInfo -ServiceName $ServiceName -DataPath $DataPath
                    Show-ServiceAccessInfo -Services $targetProfiles -ProjectName $projectName
                }
                return
            }
            else {
                $suggest = @($available | Where-Object { $_ -like "*${ServiceName}*" })
                if ($suggest.Count -gt 0) { throw "未找到服务: $ServiceName, 是否指: $($suggest -join ', ')" }
            }
        }
        finally {
            if (-not [string]::IsNullOrWhiteSpace($localhostOverridePath) -and (Test-Path -LiteralPath $localhostOverridePath)) {
                Remove-Item -LiteralPath $localhostOverridePath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    throw "未找到可用的容器配置: $ServiceName"
}
catch {
    Write-Error "容器启动脚本执行失败: $($_.Exception.Message)"
    Write-Verbose "错误详情: $($_.Exception.ToString())"
    exit 1
}
