function Set-ProfileUtf8Encoding {
    [CmdletBinding()]
    param()

    Write-Verbose "设置控制台编码为 UTF8"
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $Global:OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = $utf8
    $Global:PSDefaultParameterValues["Out-File:Encoding"] = "UTF8"

    if (Get-Command -Name Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
        if (Get-Command -Name Register-FzfHistorySmartKeyBinding -ErrorAction SilentlyContinue) {
            Register-FzfHistorySmartKeyBinding | Out-Null
        }
    }
}
