#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Jupyter Notebook格式转换脚本

.DESCRIPTION
    该脚本使用jupytext工具将指定目录下的所有Jupyter Notebook文件（.ipynb）
    转换为同时支持notebook和Python脚本格式的双格式文件。
    转换后的文件可以同时以.ipynb和.py格式进行编辑和同步。

.PARAMETER Path
    要处理的目录路径，默认为当前目录。脚本会递归处理该目录下的所有.ipynb文件

.EXAMPLE
    .\jupyconvert.ps1
    转换当前目录下的所有Jupyter Notebook文件

.EXAMPLE
    .\jupyconvert.ps1 -Path "C:\Projects\Notebooks"
    转换指定目录下的所有Jupyter Notebook文件

.NOTES
    需要安装jupytext工具：pip install jupytext
    转换后的文件将支持ipynb和py:percent两种格式
    包含错误处理机制
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Path = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Get-ChildItem -Recurse -Path $Path -Filter *.ipynb | ForEach-Object {
    $nb = $_.FullName
    if ($PSCmdlet.ShouldProcess($nb, '转换为双格式')) {
        jupytext --set-formats 'ipynb,py:percent' $nb
    }
}
