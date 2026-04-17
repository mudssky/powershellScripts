Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    严格读取 dotenv 风格配置文件。

.DESCRIPTION
    仅接受 `KEY=VALUE` 形式的非空非注释行；
    遇到非法行时立即抛错，避免静默吞掉配置问题。

.PARAMETER Path
    要读取的 env 文件路径。

.OUTPUTS
    hashtable
    返回按原始键名保存的键值表。
#>
function Read-ConfigEnvFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $pairs = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }

        if ($line -notmatch '^\s*([^=]+)=(.*)$') {
            throw '无效 env 行'
        }

        $pairs[$Matches[1].Trim()] = $Matches[2].Trim()
    }

    return $pairs
}
