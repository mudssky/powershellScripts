function Set-ProfileUtf8Encoding {
    [CmdletBinding()]
    param()

    Write-Verbose "设置控制台编码为 UTF8"
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $Global:OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = $utf8
    $Global:PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"

    # PSReadLine 键绑定（Tab 补全、fzf 等）已移至 loadModule.ps1 的 OnIdle 事件中延迟执行。
    # 原因：Set-PSReadLineKeyHandler 在冷启动时触发 PSReadLine 模块完整初始化（~260ms），
    # 延迟到 OnIdle 后 PSReadLine 已自然初始化，键绑定注册接近零成本。
}
