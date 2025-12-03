#!/usr/bin/env pwsh

<#
.SYNOPSIS
    启动LRC歌词制作工具的Web服务器

.DESCRIPTION
    该脚本使用Caddy Web服务器启动LRC歌词制作工具的本地Web界面。
    服务器将在localhost的2015端口上运行，提供歌词制作和编辑功能。

.EXAMPLE
    .\lrc-maker.ps1
    启动LRC歌词制作工具，访问地址为 http://localhost:2015

.NOTES
    需要安装Caddy Web服务器
    需要确保LRC歌词制作工具存在于指定路径：C:\tools\audio\lrc-maker
    服务器启动后可通过浏览器访问 http://localhost:2015 使用歌词制作工具
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ShouldProcess('http://localhost:2015', '打开浏览器')) {
    Start-Process -FilePath http://localhost:2015
}

caddy --root 'C:\tools\audio\lrc-maker' -host localhost -http-port 2015
