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
        代理管理工具
    .DESCRIPTION
        用于快速开启、关闭或查看代理状态。
        移植自 proxy.sh
    #>
    [CmdletBinding()]
    [Alias("proxy")]
    param (
        [Parameter(Position = 0)]
        [ValidateSet("on", "enable", "off", "disable", "unset", "status", "info", "show", "test", "help", "auto")]
        [string]$Command = "status",

        [Parameter(Position = 1)]
        [string]$HostOrPort,

        [Parameter(Position = 2)]
        [string]$Port
    )

    $DefaultHost = "127.0.0.1"
    $DefaultPort = "7890"
    $NoProxy = "localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"

    switch ($Command) {
        "auto" {
            # 自动检测代理 (移植自 proxy.sh)
            if (-not $env:http_proxy) {
                try {
                    $client = New-Object System.Net.Sockets.TcpClient
                    $connect = $client.BeginConnect($DefaultHost, $DefaultPort, $null, $null)
                    $success = $connect.AsyncWaitHandle.WaitOne(100) # 100ms timeout
                    if ($success) {
                        $url = "http://${DefaultHost}:${DefaultPort}"
                        $env:http_proxy = $url
                        $env:https_proxy = $url
                        $env:all_proxy = "socks5://${DefaultHost}:${DefaultPort}"
                        $env:no_proxy = $NoProxy
                        $env:HTTP_PROXY = $url
                        $env:HTTPS_PROXY = $url
                        $env:ALL_PROXY = $env:all_proxy
                        $env:NO_PROXY = $NoProxy
                        # Write-Verbose "已自动检测并开启代理: $url"
                    }
                    $client.Close()
                }
                catch {}
            }
        }

        { $_ -in "on", "enable" } {
            $targetHost = $DefaultHost
            $targetPort = $DefaultPort

            if (-not [string]::IsNullOrWhiteSpace($HostOrPort)) {
                if ($HostOrPort -match '^\d+$') {
                    $targetPort = $HostOrPort
                }
                else {
                    $targetHost = $HostOrPort
                    if (-not [string]::IsNullOrWhiteSpace($Port)) { $targetPort = $Port }
                }
            }

            $url = "http://${targetHost}:${targetPort}"
            $env:http_proxy = $url
            $env:https_proxy = $url
            $env:ftp_proxy = $url
            $env:rsync_proxy = $url
            $env:all_proxy = $url
            $env:HTTP_PROXY = $url
            $env:HTTPS_PROXY = $url
            $env:FTP_PROXY = $url
            $env:RSYNC_PROXY = $url
            $env:ALL_PROXY = $url
            $env:no_proxy = $NoProxy
            $env:NO_PROXY = $NoProxy

            Write-Host "✅ 代理已开启: $url" -ForegroundColor Green
            
            # 连通性测试
            try {
                $client = New-Object System.Net.Sockets.TcpClient
                $connect = $client.BeginConnect($targetHost, [int]$targetPort, $null, $null)
                $success = $connect.AsyncWaitHandle.WaitOne(200)
                if (-not $success) {
                    Write-Warning "无法连接到代理端口 ${targetHost}:${targetPort}，请检查隧道是否建立。"
                }
                $client.Close()
            }
            catch {
                Write-Warning "无法连接到代理端口 ${targetHost}:${targetPort}，请检查隧道是否建立。"
            }
        }

        { $_ -in "off", "disable", "unset" } {
            "http_proxy", "https_proxy", "ftp_proxy", "rsync_proxy", "all_proxy", "no_proxy" | ForEach-Object {
                Remove-Item "env:$_" -ErrorAction SilentlyContinue
                Remove-Item "env:$($_.ToUpper())" -ErrorAction SilentlyContinue
            }
            Write-Host "🔴 代理已关闭 (直连模式)" -ForegroundColor Yellow
        }

        { $_ -in "status", "info", "show" } {
            if ($env:http_proxy) {
                Write-Host "🟢 当前状态: 已开启" -ForegroundColor Green
                Write-Host "   地址: $env:http_proxy"
                Write-Host "   排除: $env:no_proxy"
                
                # 连通性测试
                try {
                    $uri = [System.Uri]$env:http_proxy
                    $client = New-Object System.Net.Sockets.TcpClient
                    $connect = $client.BeginConnect($uri.Host, $uri.Port, $null, $null)
                    $success = $connect.AsyncWaitHandle.WaitOne(200)
                    if ($success) {
                        Write-Host "   连接: ✅ 正常" -ForegroundColor Green
                    }
                    else {
                        Write-Host "   连接: ❌ 无法连接 (服务未启动?)" -ForegroundColor Red
                    }
                    $client.Close()
                }
                catch {
                    Write-Host "   连接: ❌ 无法连接 (服务未启动?)" -ForegroundColor Red
                }

            }
            else {
                Write-Host "⚪ 当前状态: 未开启 (直连)" -ForegroundColor Gray
            }
        }
        
        "test" {
            $url = if (-not [string]::IsNullOrWhiteSpace($HostOrPort)) { $HostOrPort } else { "https://www.google.com" }
            if (-not $env:http_proxy) {
                Write-Error "请先开启代理 (proxy on)"
                return
            }
            Write-Host "🔍正在测试访问: $url"
            try {
                # 使用 curl 如果可用，因为 Invoke-WebRequest 在某些 linux 环境下可能配置复杂
                if (Get-Command curl -ErrorAction SilentlyContinue) {
                    curl -I -s --connect-timeout 3 "$url" | Select-Object -First 1
                }
                else {
                    $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 3 -ErrorAction Stop
                    Write-Host "✅ 访问成功: $($response.StatusCode)" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "❌ 访问失败: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        "help" {
            Write-Host "用法: proxy [命令]"
            Write-Host "  on [port]        开启代理 (默认 7890)"
            Write-Host "  on [host] [port] 开启自定义代理"
            Write-Host "  off              关闭代理"
            Write-Host "  status           查看状态 (默认)"
            Write-Host "  test [url]       测试连接"
        }
    }
}

Export-ModuleMember -Function Close-Proxy, Start-Proxy, Set-Proxy
