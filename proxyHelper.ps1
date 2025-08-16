
<#
.SYNOPSIS
    代理设置辅助脚本

.DESCRIPTION
    该脚本用于为不同的开发工具（如Git、NPM）设置或取消代理配置。
    支持从环境变量中读取代理设置并应用到指定的工具。

.PARAMETER SetProxyProgram
    要设置代理的程序，支持'git'或'npm'

.PARAMETER UnsetProxyProgram
    要取消代理设置的程序，支持'git'或'npm'

.EXAMPLE
    .\proxyHelper.ps1 -SetProxyProgram git
    为Git设置代理，使用环境变量中的代理配置

.EXAMPLE
    .\proxyHelper.ps1 -UnsetProxyProgram git
    取消Git的代理设置

.NOTES
    需要设置环境变量http_proxy和https_proxy
    目前支持Git和NPM的代理配置
    Git代理仅针对GitHub域名设置
#>

[CmdletBinding()]
param (
    [ValidateSet('git', 'npm')]
    [string]
    $SetProxyProgram = '',
    [ValidateSet('git', 'npm')]
    $UnsetProxyProgram = ''
)

switch ($SetProxyProgram) {
    'git' {
        git config --global http.https://github.com.proxy $env:http_proxy
        git config --global https.https://github.com.proxy $env:https_proxy
    }
    default {}
}