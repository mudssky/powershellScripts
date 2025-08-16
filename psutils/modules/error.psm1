# 错误处理相关方法

<#
.SYNOPSIS
    调试命令执行状态

.DESCRIPTION
    检查上一个命令的执行状态，如果命令失败则输出错误信息并抛出异常，
    如果命令成功则输出成功信息。支持不同的详细程度控制输出。

.PARAMETER CommandName
    要检查的命令名称，用于错误和成功消息中的显示

.PARAMETER Verbosity
    输出详细程度，可选值：Silent（静默）、Normal（正常）、Verbose（详细）
    默认为Normal

.OUTPUTS
    System.Boolean
    返回True表示命令执行成功，False表示命令执行失败

.EXAMPLE
    git init
    Debug-CommandExecution -CommandName "git init"
    检查git init命令的执行状态

.EXAMPLE
    npm install
    Debug-CommandExecution -CommandName "npm install" -Verbosity Silent
    静默检查npm install命令的执行状态

.NOTES
    作者: PowerShell Scripts
    版本: 1.0.0
    创建日期: 2025-01-07
    用途: 用于脚本中的命令执行状态检查和错误处理
#>
function Debug-CommandExecution {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$CommandName,
        
        [ValidateSet('Silent', 'Normal', 'Verbose')]
        [string]$Verbosity = 'Normal'
    )

    begin {
        $ErrorActionPreference = 'Stop'
    }

    process {
        try {
            if (-not $?) {
                # 输出详细错误信息
                $errorMsg = $Error[0].ToString()
                if ($Verbosity -ne 'Silent') {
                    Write-Host -ForegroundColor Red ("命令执行失败: {0}`n错误详情: {1}" -f $CommandName, $errorMsg)
                }
                throw [System.OperationCanceledException]::new("$CommandName 执行失败: $errorMsg")
            }
            else {
                if ($Verbosity -ne 'Silent') {
                    Write-Host -ForegroundColor Green ("命令执行成功: {0}" -f $CommandName)
                }
                return $true
            }
        }
        catch {
            if ($Verbosity -eq 'Verbose') {
                Write-Verbose $_.Exception.Message
            }
            return $false
        }
    }
}


Export-ModuleMember -Function Debug-CommandExecution