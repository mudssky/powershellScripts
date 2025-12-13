#!/usr/bin/env pwsh

<#
.SYNOPSIS
    启动Aria2c下载服务的脚本

.DESCRIPTION
    该脚本以管理员权限启动Aria2c下载工具，并启用RPC接口。
    Aria2c将在后台隐藏窗口运行，可通过RPC接口进行远程控制。

.EXAMPLE
    .\startaria2c.ps1
    以管理员权限启动Aria2c服务

.NOTES
    需要安装Aria2c下载工具
    脚本会请求管理员权限
    启用RPC接口用于远程控制
    服务在后台隐藏窗口运行
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ShouldProcess('aria2c', '启动 RPC 服务')) {
    Start-Process aria2c -Verb runas -WindowStyle Hidden -ArgumentList "--enable-rpc=true"
}
exit 0
