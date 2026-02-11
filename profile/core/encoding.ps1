function Set-ProfileUtf8Encoding {
    [CmdletBinding()]
    param()

    Write-Verbose "设置控制台编码为 UTF8"
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $Global:OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = $utf8
    $Global:PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"

    # PSReadLine 是 PowerShell 7+ 内置模块，无需 Get-Command 检查
    Set-PSReadLineKeyHandler -Key Tab -Function Complete
    if (Get-Command -Name Register-FzfHistorySmartKeyBinding -CommandType Function -ErrorAction SilentlyContinue) {
        Register-FzfHistorySmartKeyBinding | Out-Null
    }
}
