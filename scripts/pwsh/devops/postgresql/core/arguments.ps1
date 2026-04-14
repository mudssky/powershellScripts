Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    解析 GNU 风格的长参数列表。

.DESCRIPTION
    把 `--flag value`、`--flag=value` 和单独布尔开关转换为 hashtable，
    统一后续子命令读取参数的方式。

.PARAMETER Arguments
    从 CLI 入口透传进来的剩余参数数组。

.OUTPUTS
    hashtable
    返回键名转为下划线风格的参数表，例如 `--env-file` 会变成 `env_file`。
#>
function ConvertFrom-LongOptionList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $result = @{}
    $index = 0

    while ($index -lt $Arguments.Count) {
        $token = $Arguments[$index]
        if (-not $token.StartsWith('--')) {
            throw "仅支持 GNU 风格长参数，收到: $token"
        }

        $trimmed = $token.Substring(2)
        if ($trimmed.Contains('=')) {
            $parts = $trimmed.Split('=', 2)
            $result[$parts[0].Replace('-', '_')] = $parts[1]
            $index++
            continue
        }

        if (($index + 1) -lt $Arguments.Count -and -not $Arguments[$index + 1].StartsWith('--')) {
            $result[$trimmed.Replace('-', '_')] = $Arguments[$index + 1]
            $index += 2
            continue
        }

        $result[$trimmed.Replace('-', '_')] = $true
        $index++
    }

    return $result
}
