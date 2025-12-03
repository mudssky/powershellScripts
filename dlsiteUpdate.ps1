#!/usr/bin/env pwsh

<#
.SYNOPSIS
    更新DLsite产品信息的脚本

.DESCRIPTION
    该脚本用于调用Python爬虫程序来更新DLsite已拥有产品的信息。
    脚本会切换到指定的爬虫项目目录，激活虚拟环境，然后执行更新操作。

.PARAMETER path
    要更新产品信息的目录路径，默认为当前目录

.EXAMPLE
    .\dlsiteUpdate.ps1
    使用默认路径（当前目录）更新产品信息

.EXAMPLE
    .\dlsiteUpdate.ps1 -path "D:\DLsite\Products"
    更新指定目录下的产品信息

.NOTES
    需要确保Python爬虫项目存在于指定路径：D:\coding\Projects\python\python3Spiders\dlsiteSpider
    需要安装pdm包管理器和相应的Python依赖
#>
param(
    # [Parameter(Mandatory=$true)][int]$startNum,
    # [int]$endNum=$startNum
    [string]$path = '.'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 由相对路径获取绝对路径
$path = (Resolve-Path $path).path
$spiderPath = 'D:\coding\Projects\python\python3Spiders\dlsiteSpider'
# Write-Host -ForegroundColor Red $path

if (-not (Test-Path $spiderPath)) {
    Write-Host -ForegroundColor red ('{} is not exist' -f $spiderPath)
    exit 1
}
Set-Location $spiderPath
Invoke-Expression (pdm venv activate)
python .\updateOwnedProduct.py main $path


