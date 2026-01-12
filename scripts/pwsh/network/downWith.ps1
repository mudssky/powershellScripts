#!/usr/bin/env pwsh

<#
.SYNOPSIS
 使用yt-dlp下载视频
.DESCRIPTION
使用yt-dlp或其他工具批量下载视频链接。支持从参数或剪贴板获取链接列表。
.EXAMPLE
指定下载工具
downWith.ps1 -startNum 0 -paramStr '-i' -tool you-get
.EXAMPLE 
下载前3个
downWith.ps1 -endNum 3 -paramStr '--playlist' -tool you-get
.EXAMPLE
带有cookie下载
downWith.ps1  -paramStr  '--cookies-from-browser chrome'
或者
downWith.ps1  -withCookie
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [int]$startNum = 0,
    [int]$endNum = -1,
    [string]$paramStr = '',
    [string]$tool = 'yt-dlp',
    [string]$url = '',
    [switch]$withCookie
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# 获取链接内容
$content = if (-not [string]::IsNullOrWhiteSpace($url)) {
    $url
}
else {
    Get-Clipboard
}

if ([string]::IsNullOrWhiteSpace($content)) {
    Write-Warning "未提供 URL 且剪贴板为空。"
    return
}

# 处理链接列表：分割行，去除空白字符，去除空行
$linkList = @($content -split '\r?\n' | 
        ForEach-Object { $_.Trim() } | 
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

if ($linkList.Count -eq 0) {
    Write-Warning "未找到有效的链接。"
    return
}

# 调整结束索引
if ($endNum -eq -1 -or $endNum -gt $linkList.Count) {
    $endNum = $linkList.Count
}

# 验证开始索引
if ($startNum -lt 0) { $startNum = 0 }
if ($startNum -ge $endNum) {
    Write-Warning "开始索引 ($startNum) 大于或等于结束索引 ($endNum)，无任务需执行。"
    return
}

# 处理 Cookie 参数
if ($withCookie) {
    $paramStr += ' --cookies-from-browser chrome'
}

# 执行下载
for ($i = $startNum; $i -lt $endNum; $i++) {
    $link = $linkList[$i]
    $current = $i - $startNum + 1
    $total = $endNum - $startNum
    
    Write-Host -ForegroundColor Green "[${current}/${total}] Downloading: $link"
    
    if ($PSCmdlet.ShouldProcess($link, "使用 $tool 下载")) {
        try {
            # 使用 Start-Process 替代 Invoke-Expression 以提高安全性
            # 注意：ArgumentList 接受字符串，这允许 $paramStr 包含多个参数
            $argsStr = "$paramStr `"$link`""
            Start-Process -FilePath $tool -ArgumentList $argsStr -NoNewWindow -Wait
        }
        catch {
            Write-Error "下载失败: $_"
        }
    }
}

Write-Host -ForegroundColor Green "所有任务完成。"
