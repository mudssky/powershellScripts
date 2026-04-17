Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    在受控作用域内临时覆盖进程环境变量。

.DESCRIPTION
    执行脚本块前注入给定环境变量，结束后无论成功还是失败都恢复原值，
    适合包装外部命令调用而不污染调用方会话。

.PARAMETER Variables
    要临时设置的环境变量键值对。

.PARAMETER ScriptBlock
    在覆盖后的环境中执行的脚本块。

.OUTPUTS
    object
    返回脚本块的原始执行结果。
#>
function Invoke-WithScopedEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Variables,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $previousValues = @{}
    $missingKeys = New-Object 'System.Collections.Generic.HashSet[string]'

    foreach ($entry in $Variables.GetEnumerator()) {
        $existingValue = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        if ($null -eq $existingValue) {
            $missingKeys.Add($entry.Key) | Out-Null
        }
        else {
            $previousValues[$entry.Key] = $existingValue
        }

        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }

    try {
        return & $ScriptBlock
    }
    finally {
        foreach ($entry in $Variables.GetEnumerator()) {
            if ($missingKeys.Contains($entry.Key)) {
                [Environment]::SetEnvironmentVariable($entry.Key, $null, 'Process')
                Remove-Item -Path ("Env:{0}" -f $entry.Key) -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($entry.Key, $previousValues[$entry.Key], 'Process')
            }
        }
    }
}
