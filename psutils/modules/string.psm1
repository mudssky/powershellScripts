function Get-LineBreak {
    param(
        # 检测的字符串内容
        [Parameter(Mandatory = $true)]
        [string]
        $Content,
        [string]
        $DefaultLineBreak = '`n'
    )

    if ($Content -match "`r`n") {
        Write-Debug "Detected line break: CRLF"
        return "`r`n"
    }
    elseif ($Content -match "`n") {
        Write-Debug "Detected line break: LF"
        return "`n"
    }
    else {
        return $DefaultLineBreak
    }
}
