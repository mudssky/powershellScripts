# 错误处理相关方法


function Debug-CommandExecution {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$CommandName,
        
        [ValidateSet('Silent','Normal','Verbose')]
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


Export-ModuleMember -Function *