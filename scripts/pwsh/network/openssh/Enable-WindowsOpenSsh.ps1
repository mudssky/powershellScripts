[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # 注册到 HKLM:\SOFTWARE\OpenSSH\DefaultShell 的默认 Shell。
    # 默认 pwsh 7；若本机没有 pwsh，自动回退到 Windows PowerShell。
    [string]$DefaultShell = 'C:\Program Files\PowerShell\7\pwsh.exe',

    # 防火墙放行端口，同时写入计划输出供核对。
    [int]$Port = 22,

    # sshd_config 模板来源。默认指向仓库 config/network/openssh/sshd_config.example，
    # 相对脚本位置解析，避免依赖当前工作目录。
    [string]$SshdConfigSource,

    # 本机运行态 sshd_config 路径，默认 $env:ProgramData\ssh\sshd_config。
    [string]$SshdConfigTarget,

    # 跳过 sshd_config 应用步骤，只安装服务 + 防火墙 + 默认 Shell。
    [switch]$SkipSshdConfigApply,

    # 只打印将要执行的计划，不改动系统。适合排障和复阅。
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 脚本所在目录，用于解析仓库内模板的相对路径。
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ───────────────────────── 平台与路径解析 ─────────────────────────

function Test-IsWindowsPlatform {
    <#
        .SYNOPSIS
            判断当前是否运行在 Windows 平台。

        .DESCRIPTION
            优先用 pwsh 7+ 的 $IsWindows；在 Windows PowerShell 5.1 下用
            [Environment]::OSVersion.Platform 兜底，保证跨版本判断一致。

        .OUTPUTS
            System.Boolean
    #>
    if ($null -ne $IsWindows) { return [bool]$IsWindows }
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Resolve-SshdPaths {
    <#
        .SYNOPSIS
            解析 sshd_config 模板来源与本机运行态目标路径的最终绝对路径。

        .DESCRIPTION
            模板默认指向仓库 config/network/openssh/sshd_config.example：
            scripts/pwsh/network/openssh/ 向上四层到仓库根，再进 config/network/openssh/。
            目标默认为 $env:ProgramData\ssh\sshd_config。

        .OUTPUTS
            包含 Source 与 Target 两个绝对路径的对象。
    #>
    param(
        [string]$Source,
        [string]$Target
    )

    # 仓库根：scripts/pwsh/network/openssh -> 向上 4 层。
    $repoRoot = (Resolve-Path (Join-Path $script:ScriptDir '..\..\..\..')).Path
    $defaultSource = Join-Path $repoRoot 'config\network\openssh\sshd_config.example'

    $resolvedSource = if ([string]::IsNullOrWhiteSpace($Source)) { $defaultSource } else { $Source }

    $resolvedTarget = if ([string]::IsNullOrWhiteSpace($Target)) {
        Join-Path $env:ProgramData 'ssh\sshd_config'
    }
    else { $Target }

    return [pscustomobject]@{ Source = $resolvedSource; Target = $resolvedTarget }
}

function Resolve-EffectiveDefaultShell {
    <#
        .SYNOPSIS
            确定最终写入注册表的 DefaultShell。

        .DESCRIPTION
            若用户传入的 $DefaultShell 在本机不存在，回退到 Windows PowerShell 5.1，
            保证 OpenSSH 登录后始终有可用 Shell。返回值附带是否发生回退的标记。

        .OUTPUTS
            包含 Shell（最终路径）与 Fallback（bool）的对象。
    #>
    param([string]$Shell)

    if (Test-Path -LiteralPath $Shell) {
        return [pscustomobject]@{ Shell = $Shell; Fallback = $false }
    }
    $fallback = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    return [pscustomobject]@{ Shell = $fallback; Fallback = $true }
}

function New-SshdConfigBackupName {
    <#
        .SYNOPSIS
            按仓库 AGENTS.md 规则生成本机 sshd_config 的时间戳备份文件名。

        .DESCRIPTION
            格式 <base>.<YYYY-MM-DD_HH-mm-ss>.bak，使用连字符分隔时间位，
            避免 Windows 文件名中不允许的冒号，同时保持可读。

        .PARAMETER BasePath
            被备份的本机文件完整路径。

        .OUTPUTS
            System.String  带时间戳的 .bak 绝对路径。
    #>
    param([Parameter(Mandatory)][string]$BasePath)

    $stamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    return "{0}.{1}.bak" -f $BasePath, $stamp
}

# ───────────────────────── 计划生成 ─────────────────────────

function Get-EnablePlan {
    <#
        .SYNOPSIS
            生成启用 Windows OpenSSH Server 的有序步骤计划。

        .DESCRIPTION
            纯函数，不产生副作用。DryRun 与实际执行共用同一计划对象，
            便于先预览再执行，也便于人工核对顺序：
            安装 capability -> 起服务 -> 开机自启 -> 放行防火墙 -> 写 DefaultShell -> 应用 sshd_config（含 .bak 备份）。

        .OUTPUTS
            步骤对象数组，每个元素含 Step / Cmd / Args / 备注。
    #>
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$DefaultShell,
        [Parameter(Mandatory)][bool]$ShellFallback,
        [Parameter(Mandatory)][string]$SshdConfigSource,
        [Parameter(Mandatory)][string]$SshdConfigTarget,
        [Parameter(Mandatory)][bool]$ApplySshdConfig
    )

    $steps = @(
        [pscustomobject]@{
            Step   = 'InstallCapability'
            Cmd    = 'Add-WindowsCapability'
            Args   = @('-Online', '-Name', 'OpenSSH.Server~~~~0.0.1.0')
            Note   = '安装 OpenSSH Server 可选功能'
        },
        [pscustomobject]@{
            Step   = 'StartService'
            Cmd    = 'Start-Service'
            Args   = @('-Name', 'sshd')
            Note   = '启动 sshd 服务'
        },
        [pscustomobject]@{
            Step   = 'AutoStartService'
            Cmd    = 'Set-Service'
            Args   = @('-Name', 'sshd', '-StartupType', 'Automatic')
            Note   = '设为开机自启'
        },
        [pscustomobject]@{
            Step   = 'FirewallAllow'
            Cmd    = 'New-NetFirewallRule'
            Args   = @('-Name', 'sshd', '-DisplayName', 'OpenSSH Server (sshd)',
                '-Enabled', $true, '-Direction', 'Inbound', '-Protocol', 'TCP',
                '-Action', 'Allow', '-LocalPort', $Port)
            Port   = $Port
            Note   = "放行防火墙 TCP $Port"
        },
        [pscustomobject]@{
            Step         = 'SetDefaultShell'
            Cmd          = 'Set-ItemProperty'
            Args         = @('-Path', 'HKLM:\SOFTWARE\OpenSSH', '-Name', 'DefaultShell',
                '-Value', $DefaultShell, '-Type', 'String', '-Force')
            DefaultShell = $DefaultShell
            Note         = if ($ShellFallback) { "设置 DefaultShell（回退到 $DefaultShell）" } else { "设置 DefaultShell" }
        }
    )

    if ($ApplySshdConfig) {
        $steps += [pscustomobject]@{
            Step             = 'ApplySshdConfig'
            Cmd              = 'Copy-Item'
            Args             = @('-LiteralPath', $SshdConfigSource, '-Destination', $SshdConfigTarget, '-Force')
            SshdConfigSource = $SshdConfigSource
            SshdConfigTarget = $SshdConfigTarget
            Note             = "应用 $SshdConfigSource（覆盖前先备份为 .bak）"
        }
    }

    return $steps
}

function Show-Plan {
    <#
        .SYNOPSIS
            把计划对象格式化为可读的多行文本输出。

        .OUTPUTS
            System.String
    #>
    param([Parameter(Mandatory)][array]$Steps)

    $lines = @('执行计划：')
    foreach ($s in $Steps) {
        $argText = ($s.Args | ForEach-Object { if ($null -ne $_) { $_.ToString() } }) -join ' '
        $lines += ("  [{0}] {1} {2}  # {3}" -f $s.Step, $s.Cmd, $argText, $s.Note)
    }
    return ($lines -join "`n")
}

# ───────────────────────── 步骤执行 ─────────────────────────

function Invoke-PlanStep {
    <#
        .SYNOPSIS
            执行单个计划步骤；DryRun 时只打印不改动系统。

        .DESCRIPTION
            执行路径刻意不用数组 splatting：PowerShell 对数组做 splat 只做位置绑定，
            会把 '-Online' 当成位置实参导致 "positional parameter cannot be found"。
            因此每个分支都用命名参数直接调用 cmdlet，动态值从 step 对象的结构化字段读取；
            Args 数组仅用于 DryRun 展示。DryRun 与实走的展示/取值彻底分离，避免解析陷阱。

            ApplySshdConfig 步骤在执行复制前会先备份本机现有 sshd_config，
            备份命名遵守 AGENTS.md 时间戳约定。
            SetDefaultShell 步骤会先确保 HKLM:\SOFTWARE\OpenSSH 注册表键存在。
    #>
    param(
        [Parameter(Mandatory)][pscustomobject]$Step,
        [switch]$DryRun
    )

    Write-Host ("-> [{0}] {1}" -f $Step.Step, $Step.Note)

    switch ($Step.Step) {
        'InstallCapability' {
            if ($DryRun) {
                Write-Host ("   [DryRun] {0} {1}" -f $Step.Cmd, ($Step.Args -join ' '))
                return
            }
            Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
        }
        'StartService' {
            if ($DryRun) {
                Write-Host ("   [DryRun] {0} {1}" -f $Step.Cmd, ($Step.Args -join ' '))
                return
            }
            Start-Service -Name 'sshd'
        }
        'AutoStartService' {
            if ($DryRun) {
                Write-Host ("   [DryRun] {0} {1}" -f $Step.Cmd, ($Step.Args -join ' '))
                return
            }
            Set-Service -Name 'sshd' -StartupType Automatic
        }
        'FirewallAllow' {
            if ($DryRun) {
                Write-Host ("   [DryRun] {0} {1}" -f $Step.Cmd, ($Step.Args -join ' '))
                return
            }
            # 防火墙规则可能已存在（capability 安装时自带），存在则跳过避免重复创建报错。
            if (Get-NetFirewallRule -Name 'sshd' -ErrorAction SilentlyContinue) {
                Write-Host '   防火墙规则 sshd 已存在，跳过'
                return
            }
            New-NetFirewallRule -Name 'sshd' -DisplayName 'OpenSSH Server (sshd)' `
                -Enabled 'True' -Direction Inbound -Protocol TCP -Action Allow `
                -LocalPort $Step.Port | Out-Null
        }
        'SetDefaultShell' {
            if ($DryRun) {
                Write-Host ("   [DryRun] {0} {1}" -f $Step.Cmd, ($Step.Args -join ' '))
                return
            }
            # 首次写入前确保注册表键存在。
            $regPath = 'HKLM:\SOFTWARE\OpenSSH'
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            Set-ItemProperty -Path $regPath -Name 'DefaultShell' `
                -Value $Step.DefaultShell -Type String -Force
        }
        'ApplySshdConfig' {
            $target = $Step.SshdConfigTarget
            if (-not $DryRun -and (Test-Path -LiteralPath $target)) {
                # 覆盖前备份本机现有配置（若存在），遵守 AGENTS.md 时间戳 .bak 规则。
                $bak = New-SshdConfigBackupName -BasePath $target
                Copy-Item -LiteralPath $target -Destination $bak -Force
                Write-Host "   已备份现有配置 -> $bak"
            }
            elseif ($DryRun -and (Test-Path -LiteralPath $target)) {
                $bak = New-SshdConfigBackupName -BasePath $target
                Write-Host "   [DryRun] 将备份现有配置 -> $bak"
            }
            if ($DryRun) {
                Write-Host ("   [DryRun] {0} {1}" -f $Step.Cmd, ($Step.Args -join ' '))
                return
            }
            # 确保目标目录存在（首次安装时 ProgramData\ssh 可能由 capability 刚创建）。
            $targetDir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $Step.SshdConfigSource -Destination $target -Force
        }
        default {
            if ($DryRun) {
                Write-Host ("   [DryRun] {0} {1}" -f $Step.Cmd, ($Step.Args -join ' '))
                return
            }
            throw "未知计划步骤：$($Step.Step)"
        }
    }
}

# ───────────────────────── 主入口 ─────────────────────────

function Invoke-EnableWindowsOpenSsh {
    <#
        .SYNOPSIS
            Enable-WindowsOpenSsh.ps1 的主入口，编排整个启用流程。
    #>
    if (-not (Test-IsWindowsPlatform)) {
        # 非 Windows 平台：脚本依赖 Add-WindowsCapability/Set-Service/注册表等 Windows 专属能力，
        # 没有意义继续。打印友好提示后干净退出（exit 1），而不是抛红色异常堆栈。
        Write-Warning 'Enable-WindowsOpenSsh 仅用于 Windows：它依赖 OpenSSH Server 可选功能、'
        Write-Warning 'Windows 服务、防火墙规则和 HKLM:\SOFTWARE\OpenSSH 注册表，这些在当前平台不可用。'
        Write-Warning 'Linux/macOS 被控端请参考 docs/cheatsheet/vscode/remote/setup-ssh.md 的通用步骤。'
        exit 1
    }

    $paths = Resolve-SshdPaths -Source $SshdConfigSource -Target $SshdConfigTarget
    if (-not (Test-Path -LiteralPath $paths.Source)) {
        throw "找不到 sshd_config 模板：$($paths.Source)"
    }

    $shellInfo = Resolve-EffectiveDefaultShell -Shell $DefaultShell
    if ($shellInfo.Fallback) {
        Write-Warning "未找到 $DefaultShell，DefaultShell 回退到 $($shellInfo.Shell)。"
    }

    $applySshdConfig = -not $SkipSshdConfigApply
    $plan = Get-EnablePlan `
        -Port $Port `
        -DefaultShell $shellInfo.Shell `
        -ShellFallback $shellInfo.Fallback `
        -SshdConfigSource $paths.Source `
        -SshdConfigTarget $paths.Target `
        -ApplySshdConfig $applySshdConfig

    Write-Host (Show-Plan -Steps $plan)
    if ($DryRun) {
        Write-Host ''
        Write-Host 'DryRun 模式：以上仅为计划，未改动系统。去掉 -DryRun 实际执行。'
        return
    }

    foreach ($step in $plan) {
        Invoke-PlanStep -Step $step
    }

    # 应用配置后需要重启 sshd 使其生效。
    if ($applySshdConfig -and (Get-Service -Name sshd -ErrorAction SilentlyContinue)) {
        Write-Host '-> 重启 sshd 以应用新配置'
        Restart-Service -Name sshd -Force
    }

    Write-Host ''
    Write-Host '完成。可用以下命令验证：'
    Write-Host '  Get-Service sshd'
    Write-Host '  Get-NetFirewallRule -Name *ssh*'
    if ($applySshdConfig) {
        Write-Host "  本机配置：$($paths.Target)"
    }
}

# 受此环境变量保护：测试 dot-source 本脚本时不执行主入口。
if (-not $env:PWSH_TEST_SKIP_ENABLE_WINDOWS_SSH_MAIN) {
    Invoke-EnableWindowsOpenSsh
}
