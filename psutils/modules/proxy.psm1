$internetSettingPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"


<#
.SYNOPSIS
    关闭系统代理设置。

.DESCRIPTION
    此函数用于禁用Windows系统的Internet代理设置，将ProxyEnable注册表项设置为0。

.EXAMPLE
    Close-Proxy
    关闭当前系统的代理设置。

.NOTES
    此函数直接修改注册表，可能需要管理员权限才能成功执行。
#>
function Close-Proxy() {
    Set-ItemProperty -Path $internetSettingPath -Name ProxyEnable -Value 0
}


<#
.SYNOPSIS
    启动并配置系统代理设置。

.DESCRIPTION
    此函数用于配置Windows系统的Internet代理设置，包括代理服务器地址、用户名和密码，并启用代理。
    它直接修改注册表项以应用设置。

.PARAMETER URL
    代理服务器的URL，例如 'http://127.0.0.1:8080'。

.PARAMETER username
    代理认证所需的用户名（如果代理需要认证）。

.PARAMETER password
    代理认证所需的密码（SecureString类型，如果代理需要认证）。

.EXAMPLE
    Start-Proxy -URL "http://127.0.0.1:8080"
    配置并启用代理服务器为 http://127.0.0.1:8080。

.EXAMPLE
    $securePassword = ConvertTo-SecureString "MyProxyPass" -AsPlainText -Force
    Start-Proxy -URL "http://proxy.example.com:8080" -username "myuser" -password $securePassword
    配置并启用需要认证的代理服务器。

.NOTES
    此函数直接修改注册表，可能需要管理员权限才能成功执行。
    修改后可能需要重启相关服务或系统才能完全生效。
#>
function Start-Proxy() {
    param(
        [string]$URL = 'http://127.0.0.1:8080',
        [string]$username,
        [SecureString]$password
    )
    
    Set-ItemProperty -Path $internetSettingPath -Name ProxyServer -Value $URL
    if ($username -and $password) {
        Set-ItemProperty -Path $internetSettingPath -Name ProxyUser  -Value $username
        Set-ItemProperty -Path $internetSettingPath -Name ProxyPass  -Value $password
    }

    Set-ItemProperty -Path $internetSettingPath -Name ProxyEnable -Value 1
    # Restart-Service -Name WinHttpAutoProxySvc
}

function Set-Proxy {
    <#
    .SYNOPSIS
        管理当前会话及 Docker 的代理设置。

    .DESCRIPTION
        用于快速开启、关闭或查看代理状态，支持当前 Shell 会话、Docker Daemon 和 Docker Container 配置。
        此函数旨在简化在 Linux (Ubuntu) 环境下的代理配置工作。
        
        支持通过环境变量配置默认代理：
        - $env:PROXY_DEFAULT_HOST: 默认代理主机 (默认: 127.0.0.1)
        - $env:PROXY_DEFAULT_PORT: 默认代理端口 (默认: 7890)
        - $env:PROXY_AUTO_ENABLE: 是否允许 auto 自动开启代理 (默认: 1；0/false/off/no/n 表示关闭)
        
    .PARAMETER Command
        操作命令: on, off, status, test, docker, container, auto, help。
        默认值为 'status'。
    
    .PARAMETER Target
        目标主机、端口或完整代理 URL。
        如果仅提供端口 (如 7890)，则主机默认为 127.0.0.1。
        如果提供主机 (如 192.168.1.10)，则需要通过 Port 参数提供端口，或使用默认端口。
        如果提供完整 URL (如 http://192.168.1.10:7890)，则直接使用该地址的协议、主机和端口。
    
    .PARAMETER Port
        代理端口，仅在 Target 为主机时使用。

    .EXAMPLE
        Set-Proxy on 7890
        开启代理，指向 127.0.0.1:7890

    .EXAMPLE
        proxy on 192.168.1.100 1080
        开启代理，指向 192.168.1.100:1080

    .EXAMPLE
        proxy on http://192.168.21.90:7890
        使用完整 URL 开启代理。

    .EXAMPLE
        proxy off
        关闭当前会话代理

    .EXAMPLE
        proxy docker on
        为 Docker Daemon 配置代理 (需要 sudo 权限)
    #>
    [CmdletBinding()]
    [Alias("proxy")]
    param (
        [Parameter(Position = 0)]
        [ValidateSet("on", "enable", "off", "disable", "unset", "status", "info", "show", "test", "help", "auto", "docker", "container")]
        [string]$Command = "status",

        [Parameter(Position = 1)]
        [string]$Target,

        [Parameter(Position = 2)]
        [string]$Port
    )

    begin {
        # 配置常量
        $DefaultHost = if (-not [string]::IsNullOrWhiteSpace($env:PROXY_DEFAULT_HOST)) { $env:PROXY_DEFAULT_HOST } else { "127.0.0.1" }
        $DefaultPort = if (-not [string]::IsNullOrWhiteSpace($env:PROXY_DEFAULT_PORT)) { $env:PROXY_DEFAULT_PORT } else { "7890" }
        $NoProxyList = "localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"

        function Test-ProxyAutoEnable {
            <#
            .SYNOPSIS
                判断是否允许自动探测并开启代理。

            .DESCRIPTION
                通过 PROXY_AUTO_ENABLE 控制 profile 或 auto 命令的自动开启行为；未设置时保持兼容，默认允许自动开启。

            .OUTPUTS
                System.Boolean。返回 $true 表示允许自动开启，返回 $false 表示跳过自动开启。
            #>
            param()

            $rawValue = [System.Environment]::GetEnvironmentVariable('PROXY_AUTO_ENABLE')
            if ([string]::IsNullOrWhiteSpace($rawValue)) { return $true }

            switch ($rawValue.Trim().ToLowerInvariant()) {
                '0' { return $false }
                'false' { return $false }
                'off' { return $false }
                'no' { return $false }
                'n' { return $false }
                default { return $true }
            }
        }
        
        # 内部辅助函数：解析主机和端口
        function Get-ProxyEndpoint {
            <#
            .SYNOPSIS
                解析代理目标参数。

            .DESCRIPTION
                兼容端口、主机加端口、完整 URL 三种输入形式，并统一返回代理环境变量使用的 URL。

            .PARAMETER InputTarget
                端口、主机或完整代理 URL。

            .PARAMETER InputPort
                当 InputTarget 为主机时使用的代理端口。

            .OUTPUTS
                System.Management.Automation.PSCustomObject。包含 Host、Port、Url 三个字段。
            #>
            param ($InputTarget, $InputPort)
            
            $hostName = $DefaultHost
            $portNum = $DefaultPort
            $scheme = "http"

            if (-not [string]::IsNullOrWhiteSpace($InputTarget)) {
                if ($InputTarget -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
                    $uri = [System.Uri]$InputTarget
                    $scheme = $uri.Scheme
                    $hostName = $uri.Host
                    if (-not $uri.IsDefaultPort) {
                        $portNum = [string]$uri.Port
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($InputPort)) {
                        $portNum = $InputPort
                    }
                }
                elseif ($InputTarget -match '^\d+$') {
                    $portNum = $InputTarget
                }
                else {
                    $hostName = $InputTarget
                    if (-not [string]::IsNullOrWhiteSpace($InputPort)) { 
                        $portNum = $InputPort 
                    }
                }
            }
            return [pscustomobject]@{ Host = $hostName; Port = $portNum; Url = "${scheme}://${hostName}:${portNum}" }
        }
    }

    process {
        switch ($Command) {
            { $_ -in "on", "enable" } {
                $endpoint = Get-ProxyEndpoint -InputTarget $Target -InputPort $Port
                $url = $endpoint.Url
                
                # 设置环境变量
                $env:http_proxy = $url
                $env:https_proxy = $url
                $env:ftp_proxy = $url
                $env:rsync_proxy = $url
                $env:all_proxy = $url
                $env:no_proxy = $NoProxyList
                
                # 设置大写环境变量 (Linux 某些程序区分大小写)
                $env:HTTP_PROXY = $url
                $env:HTTPS_PROXY = $url
                $env:FTP_PROXY = $url
                $env:RSYNC_PROXY = $url
                $env:ALL_PROXY = $url
                $env:NO_PROXY = $NoProxyList

                Write-Verbose "✅ 代理已开启: $url"
            }

            { $_ -in "off", "disable", "unset" } {
                $vars = "http_proxy", "https_proxy", "ftp_proxy", "rsync_proxy", "all_proxy", "no_proxy"
                foreach ($var in $vars) {
                    Remove-Item "env:\$var" -ErrorAction SilentlyContinue
                    Remove-Item "env:\$($var.ToUpper())" -ErrorAction SilentlyContinue
                }
                Write-Host "🔴 代理已关闭 (直连模式)" -ForegroundColor Yellow
            }

            "auto" {
                if (-not (Test-ProxyAutoEnable)) {
                    Write-Verbose "PROXY_AUTO_ENABLE 已关闭，跳过代理自动开启。"
                    return
                }

                # 自动尝试连接默认端口，如果通了就开启
                $endpoint = Get-ProxyEndpoint -InputTarget $null -InputPort $null
                try {
                    $client = New-Object System.Net.Sockets.TcpClient
                    $connect = $client.BeginConnect($endpoint.Host, [int]$endpoint.Port, $null, $null)
                    if ($connect.AsyncWaitHandle.WaitOne(50)) {
                        Set-Proxy -Command "on"
                    }
                    $client.Close()
                }
                catch {}
            }

            { $_ -in "status", "info", "show" } {
                if ($env:http_proxy) {
                    Write-Host "🟢 当前状态: 已开启" -ForegroundColor Green
                    Write-Host "   地址: $env:http_proxy"
                    Write-Host "   排除: $env:no_proxy"
                    
                    # 测试连接
                    try {
                        $uri = [System.Uri]$env:http_proxy
                        $client = New-Object System.Net.Sockets.TcpClient
                        $connect = $client.BeginConnect($uri.Host, $uri.Port, $null, $null)
                        if ($connect.AsyncWaitHandle.WaitOne(200)) {
                            Write-Host "   连接: ✅ 正常" -ForegroundColor Green
                        }
                        else {
                            Write-Host "   连接: ❌ 无法连接 (服务未启动?)" -ForegroundColor Red
                        }
                        $client.Close()
                    }
                    catch {
                        Write-Host "   连接: ❌ 无法连接" -ForegroundColor Red
                    }
                }
                else {
                    Write-Host "⚪ 当前状态: 未开启 (直连)" -ForegroundColor Gray
                }
            }

            "test" {
                $testUrl = if (-not [string]::IsNullOrWhiteSpace($Target)) { $Target } else { "https://www.google.com" }
                if (-not $env:http_proxy) {
                    Write-Warning "未开启代理，测试可能直接连接。"
                }
                Write-Host "🔍 正在测试访问: $testUrl"
                
                try {
                    # 优先使用 curl，因为在 Linux 上通常更可靠
                    if (Get-Command curl -ErrorAction SilentlyContinue) {
                        curl -I -s --connect-timeout 3 "$testUrl" | Select-Object -First 1
                    }
                    else {
                        $response = Invoke-WebRequest -Uri $testUrl -Method Head -TimeoutSec 3 -ErrorAction Stop
                        Write-Host "✅ 访问成功: $($response.StatusCode)" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Host "❌ 访问失败: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            
            "docker" {
                # Docker Daemon 配置逻辑 (需要 sudo)
                $subCmd = if ([string]::IsNullOrWhiteSpace($Target)) { "status" } else { $Target }
                $dockerDir = "/etc/systemd/system/docker.service.d"
                $proxyConf = "$dockerDir/http-proxy.conf"
                
                switch ($subCmd) {
                    { $_ -in "on", "enable" } {
                        $dEndpoint = Get-ProxyEndpoint -InputTarget $Port -InputPort $null
                        $pUrl = $dEndpoint.Url
                        $content = "[Service]`nEnvironment=`"HTTP_PROXY=$pUrl`"`nEnvironment=`"HTTPS_PROXY=$pUrl`"`nEnvironment=`"NO_PROXY=$NoProxyList`""
                            
                        Write-Host "⚙️  正在配置 Docker Daemon 代理: $pUrl"
                        if (-not (Test-Path $dockerDir)) { sudo mkdir -p $dockerDir }
                        sudo bash -c "echo '$content' > $proxyConf"
                        sudo systemctl daemon-reload
                        sudo systemctl restart docker
                        Write-Host "✅ Docker Daemon 代理已开启" -ForegroundColor Green
                    }
                    { $_ -in "off", "disable" } {
                        if (Test-Path $proxyConf) {
                            sudo rm -f $proxyConf
                            sudo systemctl daemon-reload
                            sudo systemctl restart docker
                            Write-Host "🔴 Docker Daemon 代理已关闭" -ForegroundColor Yellow
                        }
                        else {
                            Write-Host "Docker Daemon 代理未设置" -ForegroundColor Yellow
                        }
                    }
                    default {
                        if (Test-Path $proxyConf) {
                            Write-Host "🟢 Docker Daemon 代理配置:" -ForegroundColor Green
                            sudo cat $proxyConf
                        }
                        else {
                            Write-Host "⚪ Docker Daemon 代理未开启" -ForegroundColor Gray
                        }
                    }
                }
            }

            "container" {
                # Docker Client (~/.docker/config.json) 配置逻辑
                $subCmd = if ([string]::IsNullOrWhiteSpace($Target)) { "status" } else { $Target }
                $configFile = Join-Path $env:HOME ".docker/config.json"
                    
                switch ($subCmd) {
                    { $_ -in "on", "enable" } {
                        $dEndpoint = Get-ProxyEndpoint -InputTarget $Port -InputPort $null
                        $pUrl = $dEndpoint.Url
                        
                        Write-Host "⚙️  正在配置 Docker Container 代理: $pUrl"
                        
                        $configDir = Split-Path $configFile
                        if (-not (Test-Path $configDir)) { New-Item -Type Directory -Path $configDir -Force | Out-Null }
                        
                        $json = if (Test-Path $configFile) { Get-Content $configFile -Raw | ConvertFrom-Json } else { @{} }
                        if ($json -isnot [PSCustomObject] -and $json -isnot [System.Collections.IDictionary]) { $json = @{} }
                        
                        if (-not $json.proxies) { $json | Add-Member -MemberType NoteProperty -Name "proxies" -Value @{} -Force }
                        if (-not $json.proxies.default) { $json.proxies | Add-Member -MemberType NoteProperty -Name "default" -Value @{} -Force }
                        
                        $json.proxies.default | Add-Member -MemberType NoteProperty -Name "httpProxy" -Value $pUrl -Force
                        $json.proxies.default | Add-Member -MemberType NoteProperty -Name "httpsProxy" -Value $pUrl -Force
                        $json.proxies.default | Add-Member -MemberType NoteProperty -Name "noProxy" -Value $NoProxyList -Force
                        
                        $json | ConvertTo-Json -Depth 5 | Set-Content $configFile
                        Write-Host "✅ Docker Container 代理已开启 (对新容器生效)" -ForegroundColor Green
                    }
                    { $_ -in "off", "disable" } {
                        if (Test-Path $configFile) {
                            $json = Get-Content $configFile -Raw | ConvertFrom-Json
                            if ($json.proxies) {
                                $json.PSObject.Properties.Remove('proxies')
                                $json | ConvertTo-Json -Depth 5 | Set-Content $configFile
                                Write-Host "🔴 Docker Container 代理已关闭" -ForegroundColor Yellow
                            }
                            else {
                                Write-Host "Docker Container 代理未设置" -ForegroundColor Yellow
                            }
                        }
                    }
                    default {
                        if (Test-Path $configFile) {
                            $json = Get-Content $configFile -Raw | ConvertFrom-Json
                            if ($json.proxies) {
                                Write-Host "🟢 Docker Container 代理配置:" -ForegroundColor Green
                                Write-Host ($json.proxies | ConvertTo-Json -Depth 2)
                            }
                            else {
                                Write-Host "⚪ Docker Container 代理未开启" -ForegroundColor Gray
                            }
                        }
                        else {
                            Write-Host "⚪ Docker Container 代理未开启" -ForegroundColor Gray
                        }
                    }
                }
            }
            
            "help" {
                Get-Help Set-Proxy -Detailed
            }
        }
    }
}

Export-ModuleMember -Function Close-Proxy, Start-Proxy, Set-Proxy
