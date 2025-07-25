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

Export-ModuleMember -Function Close-Proxy, Start-Proxy
