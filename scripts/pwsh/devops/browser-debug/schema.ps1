Set-StrictMode -Version Latest

<##
.SYNOPSIS
    返回 browser-debug 命令树定义。
.OUTPUTS
    System.Collections.IDictionary
    返回帮助、解析和补全共享的命令 schema。
#>
function Get-BrowserDebugCommandSchema {
    [CmdletBinding()]
    param()

    return [ordered]@{
        profile = [ordered]@{
            Description = '管理独立 Chrome 或 Edge 调试 Profile。'
            Actions     = [ordered]@{
                create = @{ Usage = 'profile create <name> --browser chrome|edge [--cdp-port N] [--profile-path PATH] [--source-user-data-path PATH] [--without-extensions] [--shortcut-directory PATH]'; Options = @('--browser', '--cdp-port', '--profile-path', '--source-user-data-path', '--without-extensions', '--shortcut-directory', '--registry-path', '--json'); Required = @('--browser'); Enums = @{ '--browser' = @('chrome', 'edge') } }
                set    = @{ Usage = 'profile set <name> [--cdp-port N] [--browser chrome|edge] [--shortcut-directory PATH]'; Options = @('--cdp-port', '--browser', '--shortcut-directory', '--registry-path', '--json'); Required = @(); Enums = @{ '--browser' = @('chrome', 'edge') } }
                get    = @{ Usage = 'profile get [name] [--json]'; Options = @('--registry-path', '--json'); Required = @(); Enums = @{} }
                list   = @{ Usage = 'profile list [--json]'; Options = @('--registry-path', '--json'); Required = @(); Enums = @{} }
                start  = @{ Usage = 'profile start <name> [--mode local|lan] [--listen-address ADDRESS] [--open-guide]'; Options = @('--mode', '--listen-address', '--open-guide', '--registry-path', '--json'); Required = @(); Enums = @{ '--mode' = @('local', 'lan') } }
                status = @{ Usage = 'profile status <name> [--json]'; Options = @('--registry-path', '--json'); Required = @(); Enums = @{} }
                stop   = @{ Usage = 'profile stop <name> [--json]'; Options = @('--registry-path', '--json'); Required = @(); Enums = @{} }
                shortcut = @{ Usage = 'profile shortcut <name> --mode local|lan [--shortcut-directory PATH]'; Options = @('--mode', '--shortcut-directory', '--registry-path', '--json'); Required = @('--mode'); Enums = @{ '--mode' = @('local', 'lan') } }
            }
        }
        ssh     = [ordered]@{
            Description = '管理与调试 Profile 独立的 SSH 转发配置。'
            Actions     = [ordered]@{
                create = @{ Usage = 'ssh create <name> --profile PROFILE --direction local-forward|reverse-forward --target TARGET --agent-port N [--ssh-config-path PATH] [--verbose]'; Options = @('--profile', '--direction', '--target', '--agent-port', '--ssh-config-path', '--verbose', '--registry-path', '--json'); Required = @('--profile', '--direction', '--target', '--agent-port'); Enums = @{ '--direction' = @('local-forward', 'reverse-forward') } }
                set    = @{ Usage = 'ssh set <name> [--profile PROFILE] [--direction local-forward|reverse-forward] [--target TARGET] [--agent-port N] [--ssh-config-path PATH] [--verbose|--no-verbose]'; Options = @('--profile', '--direction', '--target', '--agent-port', '--ssh-config-path', '--verbose', '--no-verbose', '--registry-path', '--json'); Required = @(); Enums = @{ '--direction' = @('local-forward', 'reverse-forward') } }
                get    = @{ Usage = 'ssh get [name] [--json]'; Options = @('--registry-path', '--json'); Required = @(); Enums = @{} }
                list   = @{ Usage = 'ssh list [--json]'; Options = @('--registry-path', '--json'); Required = @(); Enums = @{} }
                info   = @{ Usage = 'ssh info <name> [--json]'; Options = @('--registry-path', '--json'); Required = @(); Enums = @{} }
                start  = @{ Usage = 'ssh start <name> [--json]'; Options = @('--registry-path', '--json'); Required = @(); Enums = @{} }
                status = @{ Usage = 'ssh status <name> [--json]'; Options = @('--registry-path', '--json'); Required = @(); Enums = @{} }
                stop   = @{ Usage = 'ssh stop <name> [--json]'; Options = @('--registry-path', '--json'); Required = @(); Enums = @{} }
            }
        }
    }
}

<##
.SYNOPSIS
    将传统 CLI 参数解析为统一对象。
.PARAMETER Arguments
    入口收到的原始参数。
.OUTPUTS
    System.Management.Automation.PSCustomObject
    返回资源、动作、名称、选项和 JSON 标记。
#>
function ConvertFrom-BrowserDebugArguments {
    [CmdletBinding()]
    param([string[]]$Arguments)

    $tokens = @($Arguments)
    $options = [ordered]@{}
    $positionals = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $tokens.Count; $index++) {
        $token = $tokens[$index]
        if ($token -eq '--help') {
            if ($options.Contains('help')) { throw '选项重复: --help' }
            $options['help'] = $true
            continue
        }
        if ($token -eq '--json' -or $token -eq '--verbose' -or $token -eq '--no-verbose' -or $token -eq '--without-extensions' -or $token -eq '--open-guide') {
            $optionName = $token.Substring(2)
            if ($options.Contains($optionName)) { throw "选项重复: $token" }
            $options[$optionName] = $true
            continue
        }
        if ($token.StartsWith('--')) {
            if ($index + 1 -ge $tokens.Count -or $tokens[$index + 1].StartsWith('--')) {
                throw "选项缺少值: $token"
            }
            $optionName = $token.Substring(2)
            if ($options.Contains($optionName)) { throw "选项重复: $token" }
            $options[$optionName] = $tokens[++$index]
            continue
        }
        $positionals.Add($token)
    }

    $resource = if ($positionals.Count -gt 0) { $positionals[0] } else { $null }
    $action = if ($positionals.Count -gt 1) { $positionals[1] } else { $null }
    $helpRequested = [bool]$options['help']
    $schema = Get-BrowserDebugCommandSchema
    if ($resource -in 'profile', 'ssh' -and [string]::IsNullOrWhiteSpace($action)) {
        foreach ($optionName in $options.Keys) {
            if ($optionName -notin 'help', 'json', 'registry-path') { throw "未知选项: --$optionName" }
        }
    }
    if ($resource -in 'profile', 'ssh' -and -not [string]::IsNullOrWhiteSpace($action)) {
        $resourceSchema = $schema[$resource]
        if (-not $resourceSchema.Actions.Contains($action)) { throw "未知动作: $resource $action" }
        $actionSchema = $resourceSchema.Actions[$action]
        $allowedOptions = @($actionSchema.Options | ForEach-Object { $_.Substring(2) }) + 'help'
        foreach ($optionName in $options.Keys) {
            if ($optionName -notin $allowedOptions) { throw "未知选项: --$optionName" }
        }

        $maximumPositionals = if ($action -eq 'list') { 2 } else { 3 }
        if ($positionals.Count -gt $maximumPositionals) {
            throw "多余位置参数: $($positionals[$maximumPositionals..($positionals.Count - 1)] -join ' ')"
        }
        if (-not $helpRequested) {
            foreach ($requiredOption in $actionSchema.Required) {
                $requiredName = $requiredOption.Substring(2)
                if (-not $options.Contains($requiredName) -or [string]::IsNullOrWhiteSpace([string]$options[$requiredName])) {
                    throw "缺少必需选项: $requiredOption"
                }
            }
        }
    }

    return [pscustomobject]@{
        Resource    = $resource
        Action      = $action
        Name        = if ($positionals.Count -gt 2) { $positionals[2] } else { $null }
        Positionals = $positionals.ToArray()
        Options     = $options
        AsJson      = [bool]$options['json']
        Help        = [bool]$options['help']
    }
}

<##
.SYNOPSIS
    返回指定层级的帮助文本。
.PARAMETER Resource
    可选资源名称。
.PARAMETER Action
    可选动作名称。
.OUTPUTS
    System.String
    返回中文帮助文本。
#>
function Get-BrowserDebugHelpText {
    [CmdletBinding()]
    param([string]$Resource, [string]$Action)

    $schema = Get-BrowserDebugCommandSchema
    if ([string]::IsNullOrWhiteSpace($Resource)) {
        return @'
browser-debug - 管理 Windows Chromium 独立 CDP 调试 Profile

用法:
  browser-debug profile <action> [arguments]
  browser-debug ssh <action> [arguments]
  browser-debug completion powershell
  browser-debug help [profile|ssh]

资源:
  profile  创建、启动、查询和停止浏览器调试 Profile
  ssh      管理独立的 SSH 转发配置与 Agent 交接信息

全局选项:
  --json            输出 schemaVersion=1 的 JSON
  --registry-path   覆盖注册表路径
  --help            显示当前层级帮助
'@
    }
    if (-not $schema.Contains($Resource)) { throw "未知资源: $Resource" }
    $resourceSchema = $schema[$Resource]
    if ([string]::IsNullOrWhiteSpace($Action)) {
        $lines = @("$Resource - $($resourceSchema.Description)", '', '动作:')
        foreach ($entry in $resourceSchema.Actions.GetEnumerator()) { $lines += "  $($entry.Value.Usage)" }
        return $lines -join [Environment]::NewLine
    }
    if (-not $resourceSchema.Actions.Contains($Action)) { throw "未知动作: $Resource $Action" }
    $actionSchema = $resourceSchema.Actions[$Action]
    $lines = @("用法: browser-debug $($actionSchema.Usage)", '', '选项:')
    $lines += @($actionSchema.Options | ForEach-Object { "  $_" })
    return $lines -join [Environment]::NewLine
}
