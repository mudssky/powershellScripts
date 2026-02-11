function Set-ProfileUtf8Encoding {
    [CmdletBinding()]
    param()

    Write-Verbose "设置控制台编码为 UTF8"
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $Global:OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = $utf8
    $Global:PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"

    # PSReadLine 是 PowerShell 7+ 内置模块，无需 Get-Command 检查
    Set-PSReadLineKeyHandler -Key Tab -Function Complete
    # 注意：Register-FzfHistorySmartKeyBinding 定义在 functions.psm1（非核心模块），
    # 同步路径中 Get-Command 查找会触发 PSModulePath 自动导入 psutils 全量模块（~1200ms）。
    # 已移至 loadModule.ps1 的 OnIdle 事件中延迟执行。
}
