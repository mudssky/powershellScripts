Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'WindowsBootstrap.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'WindowsRemotePsRemoting.psm1') -Force

$script:OpenSshCapabilityName = 'OpenSSH.Server~~~~0.0.1.0'
$script:WindowsPowerShellPath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$script:TailscaleFirewallRuleName = 'powershellScripts-Ansible-SSH-Tailscale'
$script:TailscaleRange = '100.64.0.0/10'

function Write-WindowsAnsiblePreparationProgress {
    <#
    .SYNOPSIS
        输出 Windows Ansible 主机准备阶段进度。

    .PARAMETER Stage
        当前固定阶段，例如 2/5 安装依赖。

    .PARAMETER Message
        当前操作及预期等待信息。

    .PARAMETER State
        Start、Done、Info 或 Failed 状态标签。

    .OUTPUTS
        无。进度写入 stderr，避免污染 JSON stdout。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Stage,

        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Start', 'Done', 'Info', 'Failed')]
        [string]$State = 'Info'
    )

    [Console]::Error.WriteLine(('[prepare][{0:HH:mm:ss}][{1}][阶段 {2}] {3}' -f [DateTime]::Now, $State, $Stage, $Message))
}

function New-WindowsAnsiblePreparationResult {
    <#
    .SYNOPSIS
        创建 Windows Ansible 准备结果项。

    .PARAMETER Name
        检查或操作名称。

    .PARAMETER Status
        结果状态。

    .PARAMETER Message
        可操作摘要。

    .PARAMETER ExitCode
        结果退出码。

    .PARAMETER Changed
        本次是否修改系统。

    .OUTPUTS
        PSCustomObject。包含 Name、Status、Message、ExitCode 和 Changed。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Succeeded', 'AlreadyPresent', 'Preview', 'Skipped', 'Failed', 'Blocked', 'RestartRequired')]
        [string]$Status,

        [string]$Message = '',

        [int]$ExitCode = 0,

        [bool]$Changed = $false
    )

    return [pscustomobject][ordered]@{
        Name     = $Name
        Status   = $Status
        Message  = $Message
        ExitCode = $ExitCode
        Changed  = $Changed
    }
}

function New-WindowsAnsibleManualStep {
    <#
    .SYNOPSIS
        创建需要用户完成的 Windows 操作步骤。

    .PARAMETER Name
        步骤名称。

    .PARAMETER Location
        执行位置或 Windows 设置页面。

    .PARAMETER Command
        需要执行的完整命令或操作。

    .PARAMETER VerifyCommand
        完成后的验证命令。

    .PARAMETER Reason
        无法由脚本可靠完成的原因。

    .OUTPUTS
        PSCustomObject。结构化人工步骤。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Location,

        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$VerifyCommand,

        [Parameter(Mandatory)]
        [string]$Reason
    )

    return [pscustomobject][ordered]@{
        Name          = $Name
        Location      = $Location
        Command       = $Command
        VerifyCommand = $VerifyCommand
        Reason        = $Reason
    }
}

function Get-WindowsAnsiblePreparationExitCode {
    <#
    .SYNOPSIS
        汇总准备结果退出码。

    .PARAMETER Result
        准备结果数组。

    .OUTPUTS
        System.Int32。Failed 为 1，Blocked/RestartRequired 为 10，其余为 0。
    #>
    [CmdletBinding()]
    param(
        [object[]]$Result
    )

    if (@($Result | Where-Object Status -eq 'Failed').Count -gt 0) {
        return 1
    }
    if (@($Result | Where-Object { $_.Status -in @('Blocked', 'RestartRequired') }).Count -gt 0) {
        return 10
    }
    return 0
}

function New-WindowsAnsibleControllerConfig {
    <#
    .SYNOPSIS
        创建与 self-hosted-compose inventory 对齐的控制端配置数据。

    .PARAMETER InventoryHost
        inventory 主机别名；省略时根据 Windows 计算机名生成。

    .PARAMETER HostName
        Windows 计算机名。

    .PARAMETER UserName
        Windows 普通用户名称。

    .PARAMETER TailscaleIPv4
        已验证的 Tailscale IPv4；为空时配置标记为未就绪。

    .PARAMETER SshPort
        首次 SSH bootstrap 端口。

    .PARAMETER SshReady
        OpenSSH capability、sshd 服务和监听端口是否已满足首次连接。

    .OUTPUTS
        PSCustomObject。包含公开 inventory、SSH bootstrap、私有凭据键和控制端命令。
    #>
    [CmdletBinding()]
    param(
        [string]$InventoryHost = '',

        [Parameter(Mandatory)]
        [string]$HostName,

        [Parameter(Mandatory)]
        [string]$UserName,

        [string]$TailscaleIPv4 = '',

        [ValidateRange(1, 65535)]
        [int]$SshPort = 22,

        [bool]$SshReady = $false
    )

    $resolvedInventoryHost = $InventoryHost
    if ([string]::IsNullOrWhiteSpace($resolvedInventoryHost)) {
        $resolvedInventoryHost = ($HostName.ToLowerInvariant() -replace '[^0-9a-z_.-]', '-')
    }
    if ([string]::IsNullOrWhiteSpace($resolvedInventoryHost)) {
        $resolvedInventoryHost = 'windows-host'
    }

    $controllerCommands = @()
    $controllerReady = -not [string]::IsNullOrWhiteSpace($TailscaleIPv4) -and $SshReady
    if ($controllerReady) {
        $controllerCommands = @(
            'cd deployments/ansible',
            "./scripts/ansible-with-secrets ansible-inventory --host $resolvedInventoryHost --yaml",
            "./scripts/ansible-with-secrets ansible-playbook playbooks/powershell-scripts-bootstrap.yml --limit $resolvedInventoryHost",
            "./scripts/ansible-with-secrets ansible-playbook playbooks/powershell-scripts-bootstrap.yml --limit $resolvedInventoryHost -e powershell_scripts_apply=true",
            "./scripts/ansible-with-secrets ansible-playbook playbooks/powershell-scripts-provision.yml --limit $resolvedInventoryHost",
            "./scripts/ansible-with-secrets ansible-playbook playbooks/powershell-scripts-provision.yml --limit $resolvedInventoryHost -e powershell_scripts_apply=true",
            "./scripts/ansible-with-secrets ansible-playbook playbooks/powershell-scripts-verify.yml --limit $resolvedInventoryHost"
        )
    }

    return [pscustomobject][ordered]@{
        Ready             = $controllerReady
        InventoryHost     = $resolvedInventoryHost
        Groups            = @('windows', 'powershell_scripts_targets')
        PublicHostVars    = [pscustomobject][ordered]@{
            ansible_host                        = $TailscaleIPv4
            ansible_user                        = $UserName
            powershell_scripts_tailscale_ipv4  = $TailscaleIPv4
            workstation_user                    = $UserName
        }
        SshBootstrapVars  = [pscustomobject][ordered]@{
            ansible_connection = 'ssh'
            ansible_port       = $SshPort
            ansible_shell_type = 'powershell'
        }
        PrivateHostVarKeys = @('ansible_password', 'workstation_user_password')
        ControllerCommands = $controllerCommands
    }
}

function Resolve-WindowsAnsibleSshdServiceOperation {
    <#
    .SYNOPSIS
        解析 sshd 服务需要执行的幂等操作。

    .PARAMETER SshdAutomatic
        sshd 当前是否为 Automatic。

    .PARAMETER SshdRunning
        sshd 当前是否为 Running。

    .OUTPUTS
        PSCustomObject。包含 SetAutomatic、Start、Changed、Status 和 Message。
    #>
    [CmdletBinding()]
    param(
        [bool]$SshdAutomatic,

        [bool]$SshdRunning
    )

    $changed = -not $SshdAutomatic -or -not $SshdRunning
    return [pscustomobject][ordered]@{
        SetAutomatic = -not $SshdAutomatic
        Start        = -not $SshdRunning
        Changed      = $changed
        Status       = if ($changed) { 'Succeeded' } else { 'AlreadyPresent' }
        Message      = if ($changed) { 'sshd 已设为 Automatic 并启动' } else { 'sshd 已为 Automatic 且 Running，无需修改' }
    }
}

function Get-WindowsAnsibleTailscaleCommand {
    <#
    .SYNOPSIS
        定位 Windows Tailscale CLI。

    .OUTPUTS
        System.String 或 null。返回 tailscale.exe 绝对路径。
    #>
    [CmdletBinding()]
    param()

    foreach ($name in @('tailscale.exe', 'tailscale')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return [string]$command.Source
        }
    }
    $standardPath = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path -LiteralPath $standardPath -PathType Leaf) {
        return $standardPath
    }
    return $null
}

function Test-WindowsAnsibleLocalAdministratorsMember {
    <#
    .SYNOPSIS
        判断当前用户是否属于本机 Administrators 组。

    .OUTPUTS
        System.Boolean。能确认属于本地管理员组时返回 true。
    #>
    [CmdletBinding()]
    param()

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        return $false
    }
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $currentSid = [string]$identity.User.Value
        if (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue) {
            return @(
                Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop |
                    Where-Object { [string]$_.SID.Value -eq $currentSid }
            ).Count -gt 0
        }
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-WindowsAnsibleHostPreparationState {
    <#
    .SYNOPSIS
        读取 Windows Ansible 首次接管前置状态。

    .PARAMETER TailscaleIPv4
        可选显式 Tailscale IPv4。

    .PARAMETER SshPort
        SSH 监听端口。

    .OUTPUTS
        PSCustomObject。包含权限、Tailscale、OpenSSH、服务、listener 和防火墙状态。
    #>
    [CmdletBinding()]
    param(
        [string]$TailscaleIPv4 = '',

        [ValidateRange(1, 65535)]
        [int]$SshPort = 22
    )

    $isWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    if (-not $isWindows) {
        return [pscustomobject][ordered]@{
            IsWindows             = $false
            HostName              = [Environment]::MachineName
            UserName              = [Environment]::UserName
            IsAdministrator       = $false
            IsAdministratorsMember = $false
            WingetAvailable       = $false
            TailscaleInstalled    = $false
            TailscaleCommand      = $null
            TailscaleIPv4         = $TailscaleIPv4
            OpenSshInstalled      = $false
            SshdExists            = $false
            SshdRunning           = $false
            SshdAutomatic         = $false
            DefaultShell          = ''
            PortListening         = $false
            FirewallEnabled       = $false
            FirewallRuleExists    = $false
        }
    }

    $tailscaleCommand = Get-WindowsAnsibleTailscaleCommand
    $resolvedIp = ''
    if (-not [string]::IsNullOrWhiteSpace($TailscaleIPv4)) {
        $resolvedIp = Select-WindowsTailscaleIPv4 -Candidate @($TailscaleIPv4)
    }
    elseif ($tailscaleCommand) {
        try {
            $resolvedIp = Select-WindowsTailscaleIPv4 -Candidate @(& $tailscaleCommand ip -4 2>$null)
        }
        catch {
            $resolvedIp = ''
        }
    }

    $capability = Get-WindowsCapability -Online -Name $script:OpenSshCapabilityName -ErrorAction SilentlyContinue
    $service = Get-Service -Name sshd -ErrorAction SilentlyContinue
    $serviceConfig = Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
    $defaultShell = ''
    try {
        $defaultShell = [string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -ErrorAction Stop)
    }
    catch {
        $defaultShell = ''
    }
    $portListening = $false
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        $portListening = @(Get-NetTCPConnection -State Listen -LocalPort $SshPort -ErrorAction SilentlyContinue).Count -gt 0
    }
    $firewallEnabled = $false
    $firewallRuleExists = $false
    if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
        $firewallEnabled = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue | Where-Object Enabled).Count -gt 0
        $firewallRuleExists = $null -ne (Get-NetFirewallRule -Name $script:TailscaleFirewallRuleName -ErrorAction SilentlyContinue)
    }

    return [pscustomobject][ordered]@{
        IsWindows              = $true
        HostName               = [Environment]::MachineName
        UserName               = [Environment]::UserName
        IsAdministrator        = Test-WindowsBootstrapAdministrator
        IsAdministratorsMember = Test-WindowsAnsibleLocalAdministratorsMember
        WingetAvailable        = $null -ne (Get-Command winget.exe -ErrorAction SilentlyContinue)
        TailscaleInstalled     = $null -ne $tailscaleCommand
        TailscaleCommand       = $tailscaleCommand
        TailscaleIPv4          = $resolvedIp
        OpenSshInstalled       = $null -ne $capability -and [string]$capability.State -eq 'Installed'
        SshdExists             = $null -ne $service
        SshdRunning            = $null -ne $service -and [string]$service.Status -eq 'Running'
        SshdAutomatic          = $null -ne $serviceConfig -and [string]$serviceConfig.StartMode -eq 'Auto'
        DefaultShell           = $defaultShell
        PortListening          = $portListening
        FirewallEnabled        = $firewallEnabled
        FirewallRuleExists     = $firewallRuleExists
    }
}

function New-WindowsAnsibleHostPreparationPlan {
    <#
    .SYNOPSIS
        根据状态生成 Windows 准备计划。

    .PARAMETER State
        Get-WindowsAnsibleHostPreparationState 返回的状态。

    .PARAMETER Apply
        是否为真实执行计划。

    .PARAMETER SshPort
        SSH 端口。

    .OUTPUTS
        PSCustomObject。包含 Results 和 ManualSteps。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,

        [switch]$Apply,

        [ValidateRange(1, 65535)]
        [int]$SshPort = 22
    )

    $results = New-Object System.Collections.Generic.List[object]
    $manualSteps = New-Object System.Collections.Generic.List[object]
    if (-not $State.IsWindows) {
        $results.Add((New-WindowsAnsiblePreparationResult -Name Platform -Status Blocked -ExitCode 10 -Message '该入口只能在 Windows 目标机运行'))
        return [pscustomobject]@{ Results = $results.ToArray(); ManualSteps = $manualSteps.ToArray() }
    }

    if ($Apply -and -not $State.IsAdministrator) {
        $results.Add((New-WindowsAnsiblePreparationResult -Name Administrator -Status Blocked -ExitCode 10 -Message 'Apply 必须在管理员 PowerShell 中运行'))
        $manualSteps.Add((New-WindowsAnsibleManualStep -Name RunElevated -Location 'Windows Terminal 或 Windows PowerShell（管理员）' `
                -Command 'Start-Process powershell.exe -Verb RunAs' -VerifyCommand 'whoami /groups | findstr S-1-5-32-544' `
                -Reason '安装 Windows capability、服务和 HKLM 配置需要提升权限'))
    }
    else {
        $results.Add((New-WindowsAnsiblePreparationResult -Name Administrator `
                -Status $(if ($Apply) { 'AlreadyPresent' } else { 'Preview' }) `
                -Message $(if ($State.IsAdministratorsMember) { '当前用户属于本地 Administrators 组' } else { '尚未确认当前用户属于本地 Administrators 组' })))
    }

    if ($State.TailscaleInstalled) {
        $results.Add((New-WindowsAnsiblePreparationResult -Name TailscaleInstall -Status AlreadyPresent -Message "Tailscale CLI: $($State.TailscaleCommand)"))
    }
    elseif ($State.WingetAvailable) {
        $results.Add((New-WindowsAnsiblePreparationResult -Name TailscaleInstall -Status Preview -Message 'winget install --id Tailscale.Tailscale --exact'))
    }
    else {
        $results.Add((New-WindowsAnsiblePreparationResult -Name TailscaleInstall -Status Blocked -ExitCode 10 -Message '缺少 Tailscale 且 winget 不可用'))
        $manualSteps.Add((New-WindowsAnsibleManualStep -Name InstallTailscale -Location '浏览器和 Tailscale Windows 安装器' `
                -Command '打开 https://tailscale.com/download/windows，下载安装后从开始菜单启动 Tailscale 并登录' `
                -VerifyCommand '& "C:\Program Files\Tailscale\tailscale.exe" ip -4' `
                -Reason '当前系统没有可用的 winget 自动安装通道'))
    }
    if ([string]::IsNullOrWhiteSpace([string]$State.TailscaleIPv4)) {
        $status = if ($Apply -and $State.TailscaleInstalled) { 'Blocked' } else { 'Preview' }
        $exitCode = if ($status -eq 'Blocked') { 10 } else { 0 }
        $results.Add((New-WindowsAnsiblePreparationResult -Name TailscaleLogin -Status $status -ExitCode $exitCode -Message '需要登录 tailnet 并获得唯一 Tailscale IPv4'))
        $manualSteps.Add((New-WindowsAnsibleManualStep -Name LoginTailscale -Location 'Windows 系统托盘中的 Tailscale' `
                -Command '打开 Tailscale，选择 Log in，在浏览器完成账号授权' `
                -VerifyCommand '& "C:\Program Files\Tailscale\tailscale.exe" ip -4' `
                -Reason '账号授权和设备批准需要用户交互'))
    }
    else {
        $results.Add((New-WindowsAnsiblePreparationResult -Name TailscaleLogin -Status AlreadyPresent -Message "Tailscale IPv4: $($State.TailscaleIPv4)"))
    }

    $results.Add((New-WindowsAnsiblePreparationResult -Name OpenSshServer `
            -Status $(if ($State.OpenSshInstalled) { 'AlreadyPresent' } else { 'Preview' }) `
            -Message $(if ($State.OpenSshInstalled) { 'Microsoft OpenSSH Server capability 已安装' } else { "Add-WindowsCapability -Online -Name $script:OpenSshCapabilityName" })))
    $results.Add((New-WindowsAnsiblePreparationResult -Name SshdService `
            -Status $(if ($State.SshdRunning -and $State.SshdAutomatic) { 'AlreadyPresent' } else { 'Preview' }) `
            -Message $(if ($State.SshdRunning -and $State.SshdAutomatic) { 'sshd 为 Automatic 且 Running' } else { '设置 sshd Automatic 并启动' })))
    $results.Add((New-WindowsAnsiblePreparationResult -Name DefaultShell `
            -Status $(if ([string]$State.DefaultShell -eq $script:WindowsPowerShellPath) { 'AlreadyPresent' } else { 'Preview' }) `
            -Message "HKLM:\SOFTWARE\OpenSSH\DefaultShell=$script:WindowsPowerShellPath"))
    $results.Add((New-WindowsAnsiblePreparationResult -Name SshListener `
            -Status $(if ($State.PortListening) { 'AlreadyPresent' } else { 'Preview' }) `
            -Message "验证 TCP $SshPort listener；默认可能监听 LAN 和 Tailscale 接口"))

    if ($State.FirewallEnabled -and -not $State.FirewallRuleExists) {
        $results.Add((New-WindowsAnsiblePreparationResult -Name FirewallRule -Status Preview `
                -Message '防火墙开启时创建仅允许 tailnet 到当前 Tailscale IPv4 的 SSH rule'))
    }
    elseif ($State.FirewallEnabled) {
        $results.Add((New-WindowsAnsiblePreparationResult -Name FirewallRule -Status AlreadyPresent -Message 'Tailscale scoped SSH rule 已存在'))
    }
    else {
        $results.Add((New-WindowsAnsiblePreparationResult -Name FirewallRule -Status Skipped -Message 'Windows Firewall profile 全部关闭；保持全局状态'))
    }

    return [pscustomobject]@{ Results = $results.ToArray(); ManualSteps = $manualSteps.ToArray() }
}

function Invoke-WindowsAnsibleHostPreparation {
    <#
    .SYNOPSIS
        准备 Windows 主机供 Ansible 首次通过 SSH 接管。

    .PARAMETER TailscaleIPv4
        可选显式 Tailscale IPv4。

    .PARAMETER SshPort
        SSH 端口，默认 22。

    .PARAMETER Apply
        执行真实安装和配置；省略时只预览。

    .PARAMETER RerunCommand
        输出给用户的精确重跑命令。

    .PARAMETER InventoryHost
        控制端 inventory 使用的主机别名。

    .OUTPUTS
        PSCustomObject。统一准备结果 document。
    #>
    [CmdletBinding()]
    param(
        [string]$TailscaleIPv4 = '',

        [ValidateRange(1, 65535)]
        [int]$SshPort = 22,

        [switch]$Apply,

        [string]$RerunCommand = '.\windows\bootstrap\Prepare-WindowsAnsibleHost.ps1 -Apply -OutputFormat Json',

        [ValidatePattern('^(?:|[0-9A-Za-z][0-9A-Za-z_.-]*)$')]
        [string]$InventoryHost = ''
    )

    $operation = if ($Apply) { 'Apply' } else { 'Preview' }
    if (-not [string]::IsNullOrWhiteSpace($TailscaleIPv4)) {
        try {
            $TailscaleIPv4 = Select-WindowsTailscaleIPv4 -Candidate @($TailscaleIPv4)
        }
        catch [System.ArgumentException] {
            return [pscustomobject][ordered]@{
                SchemaVersion  = 1
                Platform       = 'Windows'
                Operation      = $operation
                Status         = 'Invalid'
                ExitCode       = 2
                HostName       = [Environment]::MachineName
                UserName       = [Environment]::UserName
                TailscaleIPv4  = $TailscaleIPv4
                SshPort        = $SshPort
                PythonPath     = $null
                Results        = @(
                    New-WindowsAnsiblePreparationResult -Name TailscaleIPv4 -Status Failed -ExitCode 2 -Message $_.Exception.Message
                )
                ManualSteps    = @()
                NextCommands   = @()
                RerunCommand   = $RerunCommand
                AnsibleControllerConfig = New-WindowsAnsibleControllerConfig -InventoryHost $InventoryHost `
                    -HostName ([Environment]::MachineName) -UserName ([Environment]::UserName) -SshPort $SshPort
                FirewallGlobalStateUnchanged = $true
                SshAuthenticationUnchanged   = $true
            }
        }
    }
    Write-WindowsAnsiblePreparationProgress -Stage '1/5 预检' -State Start -Message '正在检查管理员权限、Tailscale、OpenSSH、sshd、监听端口和防火墙状态'
    $state = Get-WindowsAnsibleHostPreparationState -TailscaleIPv4 $TailscaleIPv4 -SshPort $SshPort
    $plan = New-WindowsAnsibleHostPreparationPlan -State $state -Apply:$Apply -SshPort $SshPort
    Write-WindowsAnsiblePreparationProgress -Stage '1/5 预检' -State Done -Message ("检查完成：Tailscale={0}，OpenSSH={1}，sshd={2}" -f $state.TailscaleInstalled, $state.OpenSshInstalled, $state.SshdRunning)
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($result in @($plan.Results)) { $results.Add($result) }
    $manualSteps = New-Object System.Collections.Generic.List[object]
    foreach ($step in @($plan.ManualSteps)) { $manualSteps.Add($step) }

    $restartRequired = $false
    if ($Apply -and $state.IsWindows -and $state.IsAdministrator) {
        try {
            if (-not $state.TailscaleInstalled) {
                if ($state.WingetAvailable) {
                    Write-WindowsAnsiblePreparationProgress -Stage '2/5 安装依赖' -State Start -Message '正在通过 winget 安装 Tailscale，安装器可能需要几分钟'
                    $tailscaleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    & winget.exe install --id Tailscale.Tailscale --exact --accept-source-agreements --accept-package-agreements --silent
                    if ($LASTEXITCODE -ne 0) { throw "winget 安装 Tailscale 失败，exit=$LASTEXITCODE" }
                    $tailscaleStopwatch.Stop()
                    Write-WindowsAnsiblePreparationProgress -Stage '2/5 安装依赖' -State Done -Message ("Tailscale 安装完成，耗时 {0:n1} 秒" -f $tailscaleStopwatch.Elapsed.TotalSeconds)
                    $results.Add((New-WindowsAnsiblePreparationResult -Name TailscaleInstallApply -Status Succeeded -Changed $true -Message '已通过 winget 安装 Tailscale'))
                }
            }

            if (-not $state.OpenSshInstalled) {
                Write-WindowsAnsiblePreparationProgress -Stage '2/5 安装依赖' -State Start -Message '正在安装 Microsoft OpenSSH Server capability；下方标题为 Operation 的系统进度条属于此步骤，常见耗时 5-20 分钟'
                $capabilityStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $capabilityResult = Add-WindowsCapability -Online -Name $script:OpenSshCapabilityName -ErrorAction Stop
                $capabilityStopwatch.Stop()
                Write-WindowsAnsiblePreparationProgress -Stage '2/5 安装依赖' -State Done -Message ("OpenSSH Server capability 安装完成，耗时 {0:n1} 秒" -f $capabilityStopwatch.Elapsed.TotalSeconds)
                $restartNeeded = [bool]$capabilityResult.RestartNeeded
                $restartRequired = $restartNeeded
                $results.Add((New-WindowsAnsiblePreparationResult -Name OpenSshServerApply `
                        -Status $(if ($restartNeeded) { 'RestartRequired' } else { 'Succeeded' }) `
                        -ExitCode $(if ($restartNeeded) { 10 } else { 0 }) -Changed $true `
                        -Message $(if ($restartNeeded) { 'OpenSSH Server 已安装，需要重启 Windows' } else { '已安装 Microsoft OpenSSH Server capability' })))
                if ($restartNeeded) {
                    $manualSteps.Add((New-WindowsAnsibleManualStep -Name RestartWindows -Location '管理员 PowerShell' `
                            -Command 'Restart-Computer' -VerifyCommand 'Get-WindowsCapability -Online -Name OpenSSH.Server*' `
                            -Reason 'Windows capability 返回 RestartNeeded'))
                }
            }

            $service = Get-Service -Name sshd -ErrorAction SilentlyContinue
            if ($null -ne $service) {
                Write-WindowsAnsiblePreparationProgress -Stage '3/5 配置服务' -State Start -Message '正在检查 sshd 的启动类型和运行状态'
                $serviceOperation = Resolve-WindowsAnsibleSshdServiceOperation `
                    -SshdAutomatic $state.SshdAutomatic -SshdRunning $state.SshdRunning
                if ($serviceOperation.SetAutomatic) {
                    Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
                }
                if ($serviceOperation.Start) {
                    Start-Service -Name sshd -ErrorAction Stop
                }
                Write-WindowsAnsiblePreparationProgress -Stage '3/5 配置服务' -State Done -Message $serviceOperation.Message
                $results.Add((New-WindowsAnsiblePreparationResult -Name SshdServiceApply -Status $serviceOperation.Status `
                        -Changed $serviceOperation.Changed -Message $serviceOperation.Message))
            }

            Write-WindowsAnsiblePreparationProgress -Stage '4/5 配置访问' -State Start -Message '正在检查 OpenSSH DefaultShell 和 Tailscale SSH 防火墙例外'
            if (-not (Test-Path -LiteralPath 'HKLM:\SOFTWARE\OpenSSH')) {
                New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
            }
            $currentShell = ''
            try {
                $currentShell = [string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -ErrorAction Stop)
            }
            catch { $currentShell = '' }
            if ($currentShell -ne $script:WindowsPowerShellPath) {
                New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $script:WindowsPowerShellPath `
                    -PropertyType String -Force | Out-Null
                $results.Add((New-WindowsAnsiblePreparationResult -Name DefaultShellApply -Status Succeeded -Changed $true -Message '已设置 Windows PowerShell 5.1 DefaultShell'))
            }

            $refreshed = Get-WindowsAnsibleHostPreparationState -TailscaleIPv4 $TailscaleIPv4 -SshPort $SshPort
            if ($refreshed.FirewallEnabled -and -not $refreshed.FirewallRuleExists -and $refreshed.TailscaleIPv4) {
                New-NetFirewallRule -Name $script:TailscaleFirewallRuleName -DisplayName 'powershellScripts Ansible SSH via Tailscale' `
                    -Enabled True -Direction Inbound -Action Allow -Protocol TCP -LocalPort $SshPort `
                    -LocalAddress $refreshed.TailscaleIPv4 -RemoteAddress $script:TailscaleRange -Profile Any -ErrorAction Stop | Out-Null
                $results.Add((New-WindowsAnsiblePreparationResult -Name FirewallRuleApply -Status Succeeded -Changed $true `
                        -Message "已允许 tailnet -> $($refreshed.TailscaleIPv4):$SshPort；未改变防火墙全局开关"))
            }
            elseif (-not $refreshed.FirewallEnabled) {
                $results.Add((New-WindowsAnsiblePreparationResult -Name FirewallRuleApply -Status Skipped -Message '防火墙全局关闭，保持关闭'))
            }
            Write-WindowsAnsiblePreparationProgress -Stage '4/5 配置访问' -State Done -Message '访问配置检查完成，未改变防火墙全局开关或 SSH 认证策略'

            Write-WindowsAnsiblePreparationProgress -Stage '5/5 验证' -State Start -Message "正在重新检查 Tailscale、sshd 和 TCP $SshPort listener"
            $state = Get-WindowsAnsibleHostPreparationState -TailscaleIPv4 $TailscaleIPv4 -SshPort $SshPort
            if (-not $state.TailscaleInstalled -or [string]::IsNullOrWhiteSpace([string]$state.TailscaleIPv4)) {
                $results.Add((New-WindowsAnsiblePreparationResult -Name TailscaleFinal -Status Blocked -ExitCode 10 -Message 'Tailscale 已安装但尚未完成登录或设备批准'))
                if (@($manualSteps | Where-Object Name -eq LoginTailscale).Count -eq 0) {
                    $manualSteps.Add((New-WindowsAnsibleManualStep -Name LoginTailscale -Location 'Windows 系统托盘中的 Tailscale' `
                            -Command '打开 Tailscale，选择 Log in，在浏览器完成账号授权' `
                            -VerifyCommand '& "C:\Program Files\Tailscale\tailscale.exe" ip -4' `
                            -Reason '账号授权和设备批准需要用户交互'))
                }
            }
            elseif ($restartRequired) {
                $results.Add((New-WindowsAnsiblePreparationResult -Name Verification -Status Skipped -Message '等待 Windows 重启后验证 sshd 与 listener'))
            }
            elseif (-not $state.SshdRunning -or -not $state.SshdAutomatic -or -not $state.PortListening) {
                $results.Add((New-WindowsAnsiblePreparationResult -Name Verification -Status Failed -ExitCode 1 -Message "sshd 服务或 TCP $SshPort listener 验证失败"))
            }
            else {
                $results.Add((New-WindowsAnsiblePreparationResult -Name Verification -Status Succeeded -Message "SSH 已就绪: ssh $($state.UserName)@$($state.TailscaleIPv4)"))
            }
            Write-WindowsAnsiblePreparationProgress -Stage '5/5 验证' -State Done -Message ("验证完成：Tailscale={0}，sshd={1}，TCP {2}={3}" -f $state.TailscaleIPv4, $state.SshdRunning, $SshPort, $state.PortListening)
        }
        catch {
            Write-WindowsAnsiblePreparationProgress -Stage '执行' -State Failed -Message $_.Exception.Message
            $results.Add((New-WindowsAnsiblePreparationResult -Name Runtime -Status Failed -ExitCode 1 -Message $_.Exception.Message))
        }
    }

    $exitCode = if (-not $state.IsWindows) {
        10
    }
    elseif ($Apply) {
        Get-WindowsAnsiblePreparationExitCode -Result $results.ToArray()
    }
    else {
        0
    }
    $status = if (-not $state.IsWindows) { 'Blocked' } elseif (-not $Apply) { 'Preview' } elseif ($exitCode -eq 1) { 'Failed' } elseif ($exitCode -eq 10) { 'Blocked' } else { 'Succeeded' }
    $nextCommands = New-Object System.Collections.Generic.List[string]
    if ($state.TailscaleIPv4) {
        $nextCommands.Add("ssh $($state.UserName)@$($state.TailscaleIPv4)")
        $nextCommands.Add("powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\windows\bootstrap\Enable-WindowsRemotePsRemoting.ps1 -TailscaleIPv4 $($state.TailscaleIPv4) -WhatIf")
    }

    return [pscustomobject][ordered]@{
        SchemaVersion  = 1
        Platform       = 'Windows'
        Operation      = $operation
        Status         = $status
        ExitCode       = $exitCode
        HostName       = $state.HostName
        UserName       = $state.UserName
        TailscaleIPv4  = [string]$state.TailscaleIPv4
        SshPort        = $SshPort
        PythonPath     = $null
        Results        = $results.ToArray()
        ManualSteps    = $manualSteps.ToArray()
        NextCommands   = $nextCommands.ToArray()
        RerunCommand   = $RerunCommand
        AnsibleControllerConfig = New-WindowsAnsibleControllerConfig -InventoryHost $InventoryHost `
            -HostName $state.HostName -UserName $state.UserName -TailscaleIPv4 ([string]$state.TailscaleIPv4) `
            -SshPort $SshPort -SshReady ($state.OpenSshInstalled -and $state.SshdRunning -and $state.SshdAutomatic -and $state.PortListening)
        FirewallGlobalStateUnchanged = $true
        SshAuthenticationUnchanged   = $true
    }
}

Export-ModuleMember -Function @(
    'New-WindowsAnsiblePreparationResult',
    'New-WindowsAnsibleManualStep',
    'Get-WindowsAnsiblePreparationExitCode',
    'New-WindowsAnsibleControllerConfig',
    'Resolve-WindowsAnsibleSshdServiceOperation',
    'Test-WindowsAnsibleLocalAdministratorsMember',
    'Get-WindowsAnsibleHostPreparationState',
    'New-WindowsAnsibleHostPreparationPlan',
    'Invoke-WindowsAnsibleHostPreparation'
)
