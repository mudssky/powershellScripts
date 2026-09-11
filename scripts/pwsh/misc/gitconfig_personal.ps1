#!/usr/bin/env pwsh

<#
.SYNOPSIS
    按 profile 管理 Git 提交身份：安装 includeIf 规则、审计实际生效身份、清理仓库级覆盖。

.DESCRIPTION
    身份数据不写在脚本里，而是来自 `config/git/gitconfig.local.json`（不提交，
    照同目录 `gitconfig.local.example.json` 自建）。配置声明若干 profile，
    带 `hosts` 的 profile 可渲染成 `includeIf "hasconfig:remote.*.url:..."` 规则，
    让 Git 按 remote 地址自动选择身份，不再需要逐仓手工写入。

    默认（不带参数或带 -ShowCurrent）执行只读审计，不修改任何配置。

.PARAMETER ShowCurrent
    只读审计。对比 remote 匹配出的期望 profile 与实际生效的 user.name / user.email，
    并报告实际值的来源文件，用于区分"规则生效"和"仓库级覆盖顶着"。

.PARAMETER Recurse
    与 -ShowCurrent 搭配，递归审计 -Path 下的所有 Git 仓库。只读，不批量写入。

.PARAMETER Path
    审计起点，默认当前目录。

.PARAMETER InstallRules
    把配置中各 profile 的 hosts 渲染成 includeIf 规则写入当前平台的 ~/.gitconfig，
    并生成对应的 ~/.gitconfig-<profile> 身份文件。写入前自动备份 ~/.gitconfig。

.PARAMETER ClearLocal
    清除当前仓库的仓库级 [user] 覆盖，把身份判定交还给 includeIf 规则。不递归。

.PARAMETER ProfileName
    兜底手工写入指定 profile 的身份，用于 includeIf 规则覆盖不到的 remote（如 IP 形式地址）。

.PARAMETER Local
    与 -ProfileName 搭配时只写当前仓库；不指定则写全局配置。

.PARAMETER ConfigPath
    覆盖默认的配置文件路径。

.EXAMPLE
    .\gitconfig_personal.ps1
    审计当前仓库的身份来源。

.EXAMPLE
    .\gitconfig_personal.ps1 -ShowCurrent -Recurse -Path ~/projects
    递归审计所有仓库，找出身份不符或靠仓库级覆盖顶着的仓库。

.EXAMPLE
    .\gitconfig_personal.ps1 -InstallRules -WhatIf
    预演规则安装，不实际写入。

.EXAMPLE
    .\gitconfig_personal.ps1 -ClearLocal
    清掉当前仓库的仓库级身份覆盖。

.NOTES
    需要已安装 Git；-Recurse 额外需要 fd。
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Audit')]
param(
    [Parameter(ParameterSetName = 'Audit')]
    [switch]$ShowCurrent,

    [Parameter(ParameterSetName = 'Audit')]
    [switch]$Recurse,

    [Parameter(ParameterSetName = 'Audit')]
    [string]$Path,

    [Parameter(ParameterSetName = 'InstallRules', Mandatory)]
    [switch]$InstallRules,

    [Parameter(ParameterSetName = 'ClearLocal', Mandatory)]
    [switch]$ClearLocal,

    [Parameter(ParameterSetName = 'WriteProfile', Mandatory)]
    [string]$ProfileName,

    [Parameter(ParameterSetName = 'WriteProfile')]
    [switch]$Local,

    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GitConfigRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' '..'))

Import-Module (Join-Path $script:GitConfigRepoRoot 'psutils/modules/config.psm1') -Force

<#
.SYNOPSIS
    读取并规范化身份配置。

.DESCRIPTION
    通过共享配置解析器合并默认值、JSON 配置文件与 CLI 覆盖，再把 profile 定义
    规范化成统一结构。配置缺失时抛出带自建指引的错误，不静默回退到内置身份。

.PARAMETER ConfigPath
    配置文件路径；省略时使用 `config/git/gitconfig.local.json`。

.OUTPUTS
    hashtable
    形如 @{ Profiles = @{ <name> = @{ Name; Email; Hosts } }; Default = <name>; Path = <file> }。
#>
function Get-GitIdentityConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    $defaultPath = Join-Path $script:GitConfigRepoRoot 'config/git/gitconfig.local.json'
    $resolvedPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $defaultPath } else { $ConfigPath }

    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        $examplePath = Join-Path $script:GitConfigRepoRoot 'config/git/gitconfig.local.example.json'
        throw "身份配置不存在: $resolvedPath`n请复制 $examplePath 并填入真实值（该文件不会被提交）。"
    }

    $sources = @(
        @{ Type = 'Hashtable'; Name = 'Defaults'; Data = @{ profiles = @{}; default = 'personal' } }
        @{ Type = 'JsonFile'; Name = 'ConfigFile'; Path = $resolvedPath }
    )

    $values = (Resolve-ConfigSources -Sources $sources -BasePath $script:GitConfigRepoRoot -ErrorOnMissing).Values

    $rawProfiles = ConvertTo-ConfigHashtable -InputObject (Get-ConfigValue -Values $values -Name 'profiles')
    if ($rawProfiles.Count -eq 0) {
        throw "身份配置 $resolvedPath 中没有任何 profile。"
    }

    $profiles = @{}
    foreach ($entry in $rawProfiles.GetEnumerator()) {
        $definition = ConvertTo-ConfigHashtable -InputObject $entry.Value

        $name = Get-ConfigValue -Values $definition -Name 'name'
        $email = Get-ConfigValue -Values $definition -Name 'email'
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($email)) {
            throw "profile '$($entry.Key)' 缺少 name 或 email。"
        }

        # hosts 可选：没有 hosts 的 profile 不参与自动匹配，只能由 -ProfileName 手工指定。
        $hosts = @()
        $rawHosts = Get-ConfigValue -Values $definition -Name 'hosts'
        if ($null -ne $rawHosts) {
            $hosts = @($rawHosts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
        }

        $profiles[$entry.Key] = @{
            Name  = [string]$name
            Email = [string]$email
            Hosts = $hosts
        }
    }

    $defaultProfile = [string](Get-ConfigValue -Values $values -Name 'default')
    if ([string]::IsNullOrWhiteSpace($defaultProfile) -or -not $profiles.ContainsKey($defaultProfile)) {
        throw "默认 profile '$defaultProfile' 未在配置中定义。"
    }

    return @{
        Profiles = $profiles
        Default  = $defaultProfile
        Path     = $resolvedPath
    }
}

<#
.SYNOPSIS
    从 Git remote 地址中提取主机名。

.DESCRIPTION
    同时识别 scp 简写（git@host:path）、ssh:// 与 http(s):// 三种形态，并剥离端口。

.PARAMETER RemoteUrl
    remote 地址；为空时返回 $null。

.OUTPUTS
    System.String
    小写主机名；无法识别时返回 $null。
#>
function Get-GitRemoteHost {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$RemoteUrl
    )

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
        return $null
    }

    $url = $RemoteUrl.Trim()

    # scp 简写没有 scheme，必须先于 URI 解析判断，否则 "git@host:path" 会被当成 scheme 为 "git@host" 的 URI。
    if ($url -match '^[^/]+@([^:/]+):') {
        return $Matches[1].ToLowerInvariant()
    }

    if ($url -match '^[a-zA-Z][a-zA-Z0-9+.-]*://(?:[^@/]+@)?([^:/]+)') {
        return $Matches[1].ToLowerInvariant()
    }

    return $null
}

<#
.SYNOPSIS
    渲染某主机对应的 includeIf 条件模式。

.DESCRIPTION
    Git 的 `**` 只有紧跟 `/` 或位于模式开头时才跨路径分隔符。scp 简写
    `git@host:group/repo.git` 中 `**` 前面是 `:`，会退化成普通 `*` 而匹配不到
    带分组的路径，因此必须把 scp 形态拆成单级 `:*` 与多级 `:*/**` 两条。

.PARAMETER GitHost
    主机名。

.OUTPUTS
    System.String[]
    四条 hasconfig 条件模式。
#>
function Get-GitIdentityIncludePattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GitHost
    )

    $normalized = $GitHost.Trim().ToLowerInvariant()

    return @(
        "git@${normalized}:*"
        "git@${normalized}:*/**"
        "ssh://git@${normalized}/**"
        "https://${normalized}/**"
    )
}

<#
.SYNOPSIS
    按 remote 主机推导期望使用的 profile 名。

.PARAMETER RemoteUrl
    仓库的 remote 地址。

.PARAMETER Config
    Get-GitIdentityConfig 的返回值。

.OUTPUTS
    System.String
    命中的 profile 名；没有任何 hosts 命中时返回默认 profile。
#>
function Resolve-GitIdentityProfileName {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$RemoteUrl,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $gitHost = Get-GitRemoteHost -RemoteUrl $RemoteUrl
    if ($null -eq $gitHost) {
        return $Config.Default
    }

    foreach ($entry in $Config.Profiles.GetEnumerator()) {
        if ($entry.Value.Hosts -contains $gitHost) {
            return $entry.Key
        }
    }

    return $Config.Default
}

<#
.SYNOPSIS
    读取单个仓库当前生效的提交身份及其来源。

.DESCRIPTION
    使用 `git config --show-origin` 取值与来源文件，据此区分身份来自 includeIf
    身份文件还是仓库自身的 .git/config。

.PARAMETER RepositoryPath
    仓库工作目录。

.OUTPUTS
    hashtable
    包含 Name、Email、EmailOrigin、RemoteUrl 与 HasLocalOverride。
#>
function Get-GitRepositoryIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryPath
    )

    $readConfig = {
        param([string[]]$GitArgs)

        $output = & git -C $RepositoryPath @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
            return $null
        }

        return ($output | Select-Object -Last 1)
    }

    $remoteUrl = & $readConfig @('remote', 'get-url', 'origin')
    $name = & $readConfig @('config', '--get', 'user.name')
    $email = & $readConfig @('config', '--get', 'user.email')

    # --show-origin 的输出是 "<来源>\t<值>"，来源形如 file:/home/x/.gitconfig 或 file:.git/config。
    $emailOrigin = $null
    $rawOrigin = & $readConfig @('config', '--show-origin', '--get', 'user.email')
    if ($null -ne $rawOrigin -and $rawOrigin -match '^file:(?<file>.*?)\t') {
        $emailOrigin = $Matches['file']
    }

    $localEmail = & $readConfig @('config', '--local', '--get', 'user.email')
    $localName = & $readConfig @('config', '--local', '--get', 'user.name')

    return @{
        Name             = $name
        Email            = $email
        EmailOrigin      = $emailOrigin
        RemoteUrl        = $remoteUrl
        HasLocalOverride = (-not [string]::IsNullOrWhiteSpace($localEmail)) -or (-not [string]::IsNullOrWhiteSpace($localName))
    }
}

<#
.SYNOPSIS
    判定单个仓库的身份健康状态。

.DESCRIPTION
    状态语义：
    - OK          规则生效，身份正确
    - LocalOverride 身份正确，但靠仓库级覆盖维持，可清理后交还规则
    - RuleGap     身份被仓库级覆盖改成了与规则期望不同的值，说明 includeIf 没覆盖这个 remote
    - Mismatch    身份与期望 profile 不符，且不是仓库级覆盖造成的
    - NoIdentity  读不到 user.email

.PARAMETER Identity
    Get-GitRepositoryIdentity 的返回值。

.PARAMETER Config
    Get-GitIdentityConfig 的返回值。

.OUTPUTS
    hashtable
    包含 Status、ExpectedProfile 与 Detail。
#>
function Get-GitIdentityStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Identity,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $expectedProfile = Resolve-GitIdentityProfileName -RemoteUrl $Identity.RemoteUrl -Config $Config
    $expected = $Config.Profiles[$expectedProfile]

    if ([string]::IsNullOrWhiteSpace($Identity.Email)) {
        return @{
            Status          = 'NoIdentity'
            ExpectedProfile = $expectedProfile
            Detail          = '未配置 user.email'
        }
    }

    $matchesExpected = ($Identity.Email -eq $expected.Email) -and ($Identity.Name -eq $expected.Name)

    if ($matchesExpected) {
        if ($Identity.HasLocalOverride) {
            return @{
                Status          = 'LocalOverride'
                ExpectedProfile = $expectedProfile
                Detail          = '身份正确但来自仓库级覆盖，可用 -ClearLocal 交还规则'
            }
        }

        return @{
            Status          = 'OK'
            ExpectedProfile = $expectedProfile
            Detail          = ''
        }
    }

    if ($Identity.HasLocalOverride) {
        return @{
            Status          = 'RuleGap'
            ExpectedProfile = $expectedProfile
            Detail          = "规则期望 $expectedProfile，实际靠仓库级覆盖维持其它身份；该 remote 未被任何 profile 的 hosts 覆盖"
        }
    }

    return @{
        Status          = 'Mismatch'
        ExpectedProfile = $expectedProfile
        Detail          = "期望 $($expected.Email)，实际 $($Identity.Email)"
    }
}

<#
.SYNOPSIS
    递归查找 Git 仓库根目录。

.DESCRIPTION
    子模块与 worktree 的 .git 常是文件，普通仓库的 .git 是目录，两种形态都需要识别。

.PARAMETER Path
    搜索起点。

.OUTPUTS
    System.String[]
    仓库根目录的绝对路径列表。
#>
function Get-GitRepositoryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Get-Command fd -ErrorAction SilentlyContinue)) {
        throw '递归审计需要 fd，请先安装或去掉 -Recurse。'
    }

    $gitEntries = fd '^.git$' $Path --hidden --exclude 'node_modules' --no-ignore --absolute-path
    $repositoryPaths = foreach ($gitEntry in $gitEntries) {
        Split-Path $gitEntry -Parent
    }

    return @($repositoryPaths | Sort-Object -Unique)
}

<#
.SYNOPSIS
    审计一个或多个仓库的提交身份。

.PARAMETER Path
    审计起点，默认当前目录。

.PARAMETER Recurse
    递归审计该路径下的所有仓库。

.PARAMETER Config
    Get-GitIdentityConfig 的返回值。

.OUTPUTS
    System.Management.Automation.PSCustomObject[]
    每个仓库一行审计结果。
#>
function Get-GitIdentityAudit {
    [CmdletBinding()]
    param(
        [string]$Path,

        [switch]$Recurse,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $root = if ([string]::IsNullOrWhiteSpace($Path)) { (Get-Location).Path } else { (Resolve-Path -LiteralPath $Path).Path }

    $repositories = if ($Recurse) { Get-GitRepositoryPath -Path $root } else { @($root) }

    $results = foreach ($repository in $repositories) {
        $identity = Get-GitRepositoryIdentity -RepositoryPath $repository
        $status = Get-GitIdentityStatus -Identity $identity -Config $Config

        # 递归审计时完整路径会挤垮表格宽度，另存一个相对名用于显示，完整路径仍保留在对象里。
        $displayName = if ($repository -eq $root) {
            Split-Path $repository -Leaf
        }
        else {
            [System.IO.Path]::GetRelativePath($root, $repository)
        }

        [pscustomobject]@{
            Name       = $displayName
            Repository = $repository
            Remote     = $identity.RemoteUrl
            Expected   = $status.ExpectedProfile
            Email      = $identity.Email
            Origin     = $identity.EmailOrigin
            OriginFile = if ([string]::IsNullOrWhiteSpace($identity.EmailOrigin)) { '' } else { Split-Path $identity.EmailOrigin -Leaf }
            Status     = $status.Status
            Detail     = $status.Detail
        }
    }

    return @($results)
}

<#
.SYNOPSIS
    为本地配置文件创建带时间戳的备份。

.PARAMETER Path
    待备份的文件路径；文件不存在时跳过。

.OUTPUTS
    System.String
    备份文件路径；未备份时返回 $null。
#>
function Backup-LocalConfigFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $backupPath = "$Path.$timestamp.bak"

    if ($PSCmdlet.ShouldProcess($backupPath, '创建备份')) {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        return $backupPath
    }

    return $null
}

<#
.SYNOPSIS
    解析当前平台的全局 gitconfig 路径。

.DESCRIPTION
    WSL 与 Windows 各有独立的 HOME 和 ~/.gitconfig，规则必须分别安装；本函数
    只解析当前进程所在平台的那一份。

.OUTPUTS
    System.String
    全局 gitconfig 的绝对路径。
#>
function Get-GitGlobalConfigPath {
    [CmdletBinding()]
    param()

    $homePath = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($homePath)) {
        $homePath = $HOME
    }

    return (Join-Path $homePath '.gitconfig')
}

<#
.SYNOPSIS
    把配置中的 profile 规则安装成 includeIf 条件包含。

.DESCRIPTION
    为每个带 hosts 的 profile 生成独立身份文件，并在全局 gitconfig 中按 remote
    地址形态写入四条 includeIf 规则。全局默认身份保持原样，不被本函数改写。

.PARAMETER Config
    Get-GitIdentityConfig 的返回值。

.PARAMETER GitConfigPath
    目标全局配置文件，默认为当前平台的 ~/.gitconfig。

.OUTPUTS
    System.Management.Automation.PSCustomObject[]
    每条已安装规则一行。
#>
function Install-GitIdentityRule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [string]$GitConfigPath
    )

    $targetConfig = if ([string]::IsNullOrWhiteSpace($GitConfigPath)) { Get-GitGlobalConfigPath } else { $GitConfigPath }
    $homePath = Split-Path $targetConfig -Parent

    Backup-LocalConfigFile -Path $targetConfig | Out-Null

    $installed = foreach ($entry in $Config.Profiles.GetEnumerator()) {
        $profileName = $entry.Key
        $definition = $entry.Value

        if ($definition.Hosts.Count -eq 0) {
            continue
        }

        $identityFile = Join-Path $homePath ".gitconfig-$profileName"

        if ($PSCmdlet.ShouldProcess($identityFile, "写入 $profileName 身份")) {
            & git config -f $identityFile user.name $definition.Name
            & git config -f $identityFile user.email $definition.Email
        }

        foreach ($gitHost in $definition.Hosts) {
            foreach ($pattern in (Get-GitIdentityIncludePattern -GitHost $gitHost)) {
                $key = "includeIf.hasconfig:remote.*.url:$pattern.path"

                if ($PSCmdlet.ShouldProcess("$targetConfig [$pattern]", "安装 $profileName 规则")) {
                    & git config -f $targetConfig $key $identityFile
                }

                [pscustomobject]@{
                    Profile      = $profileName
                    Pattern      = $pattern
                    IdentityFile = $identityFile
                }
            }
        }
    }

    return @($installed)
}

<#
.SYNOPSIS
    清除当前仓库的仓库级身份覆盖。

.PARAMETER RepositoryPath
    仓库工作目录，默认当前目录。

.OUTPUTS
    System.Boolean
    实际执行清除时返回 $true。
#>
function Clear-GitIdentityLocalOverride {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RepositoryPath
    )

    $repository = if ([string]::IsNullOrWhiteSpace($RepositoryPath)) { (Get-Location).Path } else { $RepositoryPath }

    $identity = Get-GitRepositoryIdentity -RepositoryPath $repository
    if (-not $identity.HasLocalOverride) {
        Write-Host "当前仓库没有仓库级 [user] 覆盖：$repository"
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($repository, '清除仓库级 [user] 覆盖')) {
        return $false
    }

    & git -C $repository config --local --unset-all user.name 2>$null | Out-Null
    & git -C $repository config --local --unset-all user.email 2>$null | Out-Null

    return $true
}

<#
.SYNOPSIS
    手工写入指定 profile 的身份。

.DESCRIPTION
    用于 includeIf 规则覆盖不到的 remote（例如 IP 形式的地址）。优先使用规则，
    只在确有缺口时使用本函数。

.PARAMETER ProfileName
    profile 名。

.PARAMETER Config
    Get-GitIdentityConfig 的返回值。

.PARAMETER Local
    只写当前仓库；不指定则写全局配置。

.OUTPUTS
    System.Boolean
    实际写入时返回 $true。
#>
function Set-GitIdentityProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [switch]$Local
    )

    if (-not $Config.Profiles.ContainsKey($ProfileName)) {
        throw "profile '$ProfileName' 未在 $($Config.Path) 中定义。"
    }

    $definition = $Config.Profiles[$ProfileName]
    $scope = if ($Local) { '当前仓库' } else { '全局' }

    if (-not $PSCmdlet.ShouldProcess($scope, "写入 $ProfileName 身份 ($($definition.Email))")) {
        return $false
    }

    if ($Local) {
        & git config user.name $definition.Name
        & git config user.email $definition.Email
    }
    else {
        & git config --global user.name $definition.Name
        & git config --global user.email $definition.Email
    }

    return $true
}

<#
.SYNOPSIS
    检查配置中的 profile 规则是否已安装到全局 gitconfig。

.DESCRIPTION
    规则安装是一次性动作：装好之后由 Git 自己按 remote 选身份，脚本不需要常驻。
    审计时据此提示"配置有了但规则还没装"，避免把未安装误读成身份写错。

.PARAMETER Config
    Get-GitIdentityConfig 的返回值。

.PARAMETER GitConfigPath
    目标全局配置文件，默认为当前平台的 ~/.gitconfig。

.OUTPUTS
    hashtable
    包含 Expected、Missing 两个模式列表。
#>
function Test-GitIdentityRuleInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [string]$GitConfigPath
    )

    $targetConfig = if ([string]::IsNullOrWhiteSpace($GitConfigPath)) { Get-GitGlobalConfigPath } else { $GitConfigPath }

    $installedKeys = @()
    if (Test-Path -LiteralPath $targetConfig) {
        $output = & git config -f $targetConfig --name-only --get-regexp '^includeif\.' 2>$null
        if ($LASTEXITCODE -eq 0 -and $null -ne $output) {
            # git 会把 section 名小写化，subsection 原样保留，因此只做整体小写比较。
            $installedKeys = @($output | ForEach-Object { ([string]$_).ToLowerInvariant() })
        }
    }

    $expected = @()
    foreach ($entry in $Config.Profiles.GetEnumerator()) {
        foreach ($gitHost in $entry.Value.Hosts) {
            $expected += Get-GitIdentityIncludePattern -GitHost $gitHost
        }
    }

    $missing = @($expected | Where-Object {
            $key = "includeif.hasconfig:remote.*.url:$_.path".ToLowerInvariant()
            $installedKeys -notcontains $key
        })

    return @{
        Expected = @($expected)
        Missing  = $missing
    }
}

<#
.SYNOPSIS
    脚本主入口，按参数集分派到审计、规则安装、覆盖清理或手工写入。

.OUTPUTS
    System.Object
    各分支自身的返回值。
#>
function Invoke-GitConfigPersonalCommand {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$ShowCurrent,
        [switch]$Recurse,
        [string]$Path,
        [switch]$InstallRules,
        [switch]$ClearLocal,
        [string]$ProfileName,
        [switch]$Local,
        [string]$ConfigPath
    )

    $config = Get-GitIdentityConfig -ConfigPath $ConfigPath

    if ($InstallRules) {
        $rules = Install-GitIdentityRule -Config $config
        if ($rules.Count -gt 0) {
            $rules | Format-Table -AutoSize | Out-String | Write-Host
        }
        else {
            Write-Host "配置中没有任何带 hosts 的 profile，未安装规则。"
        }
        return $rules
    }

    if ($ClearLocal) {
        return Clear-GitIdentityLocalOverride
    }

    if (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
        return Set-GitIdentityProfile -ProfileName $ProfileName -Config $config -Local:$Local
    }

    # 默认行为是只读审计；旧版本"无参数即写全局个人身份"已移除。
    $audit = Get-GitIdentityAudit -Path $Path -Recurse:$Recurse -Config $config
    # 固定宽度输出，避免窄终端把 Status / OriginFile 列挤成竖排或直接截掉。
    $audit | Format-Table -AutoSize Name, Expected, Email, Status, OriginFile | Out-String -Width 200 | Write-Host

    $ruleState = Test-GitIdentityRuleInstalled -Config $config
    if ($ruleState.Missing.Count -gt 0) {
        Write-Host "规则未安装或不完整（缺 $($ruleState.Missing.Count) / $($ruleState.Expected.Count) 条），本平台执行一次 -InstallRules 后即由 Git 自动按 remote 选身份。"
    }

    $problems = @($audit | Where-Object { $_.Status -ne 'OK' })
    if ($problems.Count -gt 0) {
        Write-Host "需要关注的仓库：$($problems.Count) / $($audit.Count)"
        foreach ($problem in $problems) {
            Write-Host "  [$($problem.Status)] $($problem.Repository) — $($problem.Detail)"
        }
    }

    return $audit
}

if (-not $env:PWSH_TEST_SKIP_GITCONFIG_MAIN) {
    # 各分支已把可读结果写到 host；返回值只服务于函数级调用（测试），不重复打印到终端。
    Invoke-GitConfigPersonalCommand @PSBoundParameters | Out-Null
}
