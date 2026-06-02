[CmdletBinding()]
param(
    # 默认管理 client，避免在普通客户端机器上误启动公网监听端口。
    [string]$Action = 'start',

    # 选择要管理的 rathole 角色。
    [ValidateSet('client', 'server')]
    [string]$Role = 'client',

    # 通过 DryRun 直接返回 PM2 预览命令，便于测试与排障。
    [switch]$DryRun,

    # 透传 PM2 原生命令参数，例如 logs 的 --lines。
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Usage {
    <#
    .SYNOPSIS
        返回 rathole PM2 包装脚本的用法说明。

    .OUTPUTS
        System.String
        返回可直接输出到终端的说明文本。
    #>
    return @'
用法:
  ./start.ps1 [start|stop|restart|logs|status|delete|save|config|help] [-Role client|server] [-DryRun] [额外 PM2 参数]

默认行为:
  ./start.ps1                -> pm2 start rathole-client.pm2.config.cjs
  ./start.ps1 -Role server   -> pm2 start rathole-server.pm2.config.cjs
  ./start.ps1 logs           -> pm2 logs rathole-client
  ./start.ps1 config         -> 输出当前角色对应的 PM2 配置与 .local.toml 路径

示例:
  ./start.ps1
  ./start.ps1 -DryRun
  ./start.ps1 logs --lines 100
  ./start.ps1 restart -Role server
  ./start.ps1 save
'@
}

function Get-RatholeRoleConfig {
    <#
    .SYNOPSIS
        获取指定 rathole 角色对应的本地文件与 PM2 app 信息。

    .PARAMETER Role
        需要管理的角色，可选 `client` 或 `server`。

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        返回包含角色、PM2 app 名称、ecosystem 配置路径与 `.local.toml` 路径的对象。
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('client', 'server')]
        [string]$Role
    )

    return [pscustomobject]@{
        Role            = $Role
        AppName         = "rathole-$Role"
        EcosystemPath   = Join-Path $script:ScriptDir "rathole-$Role.pm2.config.cjs"
        LocalConfigPath = Join-Path $script:ScriptDir "$Role.local.toml"
        ExamplePath     = Join-Path $script:ScriptDir "$Role.example.toml"
    }
}

function Assert-RatholePm2Ready {
    <#
    .SYNOPSIS
        检查 PM2 配置文件与执行环境是否满足当前动作。

    .PARAMETER RoleConfig
        `Get-RatholeRoleConfig` 返回的角色配置对象。

    .PARAMETER SkipPm2Check
        为 `$true` 时跳过 PM2 命令可用性检查。

    .OUTPUTS
        System.Void
        校验失败时抛出异常；校验通过时不返回对象。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RoleConfig,

        [bool]$SkipPm2Check
    )

    if (-not (Test-Path -LiteralPath $RoleConfig.EcosystemPath)) {
        throw "未找到 PM2 配置: $($RoleConfig.EcosystemPath)"
    }

    if (-not (Test-Path -LiteralPath $RoleConfig.LocalConfigPath)) {
        Write-Warning "未找到本地配置: $($RoleConfig.LocalConfigPath)。请先复制 $($RoleConfig.ExamplePath) 并填写真实 token。"
    }

    if ($SkipPm2Check) {
        return
    }

    if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
        throw '未找到 pm2 命令，请先安装 PM2，例如 npm install -g pm2。'
    }
}

function Get-Pm2InvocationPlan {
    <#
    .SYNOPSIS
        生成当前动作对应的 PM2 命令计划。

    .PARAMETER Action
        标准化后的动作名。

    .PARAMETER RoleConfig
        `Get-RatholeRoleConfig` 返回的角色配置对象。

    .PARAMETER ExtraArgs
        需要透传给 PM2 子命令的额外参数。

    .OUTPUTS
        System.Object[]
        返回按执行顺序排列的计划项，每项包含 `Pm2Args`。
    #>
    [CmdletBinding()]
    param(
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$RoleConfig,

        [string[]]$ExtraArgs = @()
    )

    $newPlanItem = {
        param(
            [string[]]$Pm2Args
        )

        return [pscustomobject]@{
            Pm2Args = $Pm2Args
        }
    }

    switch ($Action) {
        'start' {
            return ,(& $newPlanItem -Pm2Args (@('start', $RoleConfig.EcosystemPath) + $ExtraArgs))
        }
        'stop' {
            return ,(& $newPlanItem -Pm2Args (@('stop', $RoleConfig.AppName) + $ExtraArgs))
        }
        'restart' {
            return ,(& $newPlanItem -Pm2Args (@('restart', $RoleConfig.AppName) + $ExtraArgs))
        }
        'logs' {
            return ,(& $newPlanItem -Pm2Args (@('logs', $RoleConfig.AppName) + $ExtraArgs))
        }
        'status' {
            return ,(& $newPlanItem -Pm2Args (@('status', $RoleConfig.AppName) + $ExtraArgs))
        }
        'delete' {
            return ,(& $newPlanItem -Pm2Args (@('delete', $RoleConfig.AppName) + $ExtraArgs))
        }
        'save' {
            return ,(& $newPlanItem -Pm2Args (@('save') + $ExtraArgs))
        }
        default {
            throw "不支持的操作: $Action"
        }
    }
}

function Invoke-Pm2Command {
    <#
    .SYNOPSIS
        执行或预览 PM2 命令。

    .PARAMETER Pm2Args
        完整的 PM2 参数数组，不包含最前面的 `pm2`。

    .PARAMETER DryRun
        为 `$true` 时只返回命令预览字符串。

    .OUTPUTS
        System.String
        DryRun 模式下返回可复制的命令文本。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Pm2Args,

        [switch]$DryRun
    )

    $preview = 'pm2 ' + ($Pm2Args -join ' ')
    if ($DryRun) {
        return $preview
    }

    & pm2 @Pm2Args
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Show-RatholeConfig {
    <#
    .SYNOPSIS
        输出当前角色的本地配置与 PM2 配置路径。

    .PARAMETER RoleConfig
        `Get-RatholeRoleConfig` 返回的角色配置对象。

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        返回便于排障和复制命令的路径信息。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RoleConfig
    )

    return [pscustomobject]@{
        Role                    = $RoleConfig.Role
        AppName                 = $RoleConfig.AppName
        EcosystemPath           = $RoleConfig.EcosystemPath
        LocalConfigPath         = $RoleConfig.LocalConfigPath
        ExamplePath             = $RoleConfig.ExamplePath
        LocalConfigExists       = Test-Path -LiteralPath $RoleConfig.LocalConfigPath
        RecommendedCopyCommand  = "Copy-Item -LiteralPath '$($RoleConfig.ExamplePath)' -Destination '$($RoleConfig.LocalConfigPath)'"
        RecommendedStartCommand = "./start.ps1 start -Role $($RoleConfig.Role)"
    }
}

if ($env:PWSH_TEST_SKIP_RATHOLE_START_MAIN -eq '1') {
    return
}

$normalizedAction = $Action.ToLowerInvariant()
if ($normalizedAction -in @('help', '-h', '--help')) {
    Show-Usage | Write-Host
    exit 0
}

$roleConfig = Get-RatholeRoleConfig -Role $Role
if ($normalizedAction -eq 'config') {
    Show-RatholeConfig -RoleConfig $roleConfig
    exit 0
}

Assert-RatholePm2Ready -RoleConfig $roleConfig -SkipPm2Check:$DryRun

try {
    $invocationPlan = Get-Pm2InvocationPlan -Action $normalizedAction -RoleConfig $roleConfig -ExtraArgs $ExtraArgs
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Show-Usage | Write-Host
    exit 1
}

foreach ($planItem in $invocationPlan) {
    $result = Invoke-Pm2Command -Pm2Args $planItem.Pm2Args -DryRun:$DryRun
    if ($DryRun -and -not [string]::IsNullOrWhiteSpace($result)) {
        Write-Host $result
    }
}
