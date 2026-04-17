Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    解析 PostgreSQL 连接串为结构化字段。

.DESCRIPTION
    目前按 URI 方式解析 `postgresql://user:password@host:port/database`，
    供统一连接上下文组装逻辑复用。

.PARAMETER ConnectionString
    PostgreSQL 连接串；为空时返回空结果。

.OUTPUTS
    hashtable
    返回 `Host`、`Port`、`User`、`Password`、`Database` 字段。
#>
function ConvertFrom-PgConnectionString {
    [CmdletBinding()]
    param(
        [string]$ConnectionString
    )

    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        return @{}
    }

    $builder = [System.Uri]$ConnectionString
    $userInfoParts = $builder.UserInfo.Split(':', 2)
    return @{
        Host     = $builder.Host
        Port     = if ($builder.Port -gt 0) { $builder.Port } else { $null }
        User     = $userInfoParts[0]
        Password = if ($userInfoParts.Count -gt 1) { $userInfoParts[1] } else { $null }
        Database = $builder.AbsolutePath.TrimStart('/')
    }
}

<#
.SYNOPSIS
    在日志里屏蔽敏感值。

.DESCRIPTION
    当前主要用于密码等敏感信息展示时的统一脱敏处理。

.PARAMETER Value
    待脱敏的原始字符串。

.OUTPUTS
    string
    当输入非空时返回 `***`，否则返回原值。
#>
function Mask-PgSecret {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    return '***'
}
