[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-NginxConfig {
    [CmdletBinding()]
    param()
    <#
    .SYNOPSIS
    校验 Nginx 配置语法是否正确
    .DESCRIPTION
    运行 `nginx -t` 并返回结构化结果（Success/ExitCode/StdOut/StdErr）。
    .EXAMPLE
    Test-NginxConfig
    #>
    <#
    .SYNOPSIS
    校验 Nginx 配置语法是否正确
    .DESCRIPTION
    调用 `nginx -t` 对当前系统上的 Nginx 配置进行语法检查，返回结构化结果。
    .EXAMPLE
    Test-NginxConfig
    .OUTPUTS
    PSCustomObject
    #>
    $stdout = ''
    $stderr = ''
    try {
        $proc = Start-Process -FilePath 'nginx' -ArgumentList '-t' -NoNewWindow -PassThru -RedirectStandardOutput ([System.IO.Path]::GetTempFileName()) -RedirectStandardError ([System.IO.Path]::GetTempFileName())
        $proc.WaitForExit()
        $stdout = Get-Content -Raw -Path $proc.RedirectStandardOutput
        $stderr = Get-Content -Raw -Path $proc.RedirectStandardError
        $success = ($proc.ExitCode -eq 0)
        [PSCustomObject]@{
            Success  = $success
            ExitCode = $proc.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }
    catch {
        [PSCustomObject]@{
            Success  = $false
            ExitCode = -1
            StdOut   = $stdout
            StdErr   = $_.Exception.Message
        }
    }
}

function Reload-Nginx {
    [CmdletBinding()]
    param(
        [switch]$UseSystemctl
    )
    <#
    .SYNOPSIS
    平滑重载 Nginx 配置
    .DESCRIPTION
    优先使用 `systemctl reload nginx`；不可用时回退至 `nginx -s reload`。
    .EXAMPLE
    Reload-Nginx
    #>
    <#
    .SYNOPSIS
    平滑重载 Nginx 配置
    .DESCRIPTION
    优先使用 systemctl reload nginx；若不可用则回退到 `nginx -s reload`。
    .PARAMETER UseSystemctl
    强制使用 systemctl，若系统不支持会抛错。
    .EXAMPLE
    Reload-Nginx
    .EXAMPLE
    Reload-Nginx -UseSystemctl
    #>
    $result = $null
    if ($UseSystemctl.IsPresent) {
        $result = & systemctl reload nginx 2>&1
        return [PSCustomObject]@{ Method = 'systemctl'; Output = $result }
    }
    try {
        $whichSystemctl = & which systemctl 2>$null
        if ($LASTEXITCODE -eq 0 -and $whichSystemctl) {
            $result = & systemctl reload nginx 2>&1
            return [PSCustomObject]@{ Method = 'systemctl'; Output = $result }
        }
    }
    catch {}
    $result = & nginx -s reload 2>&1
    [PSCustomObject]@{ Method = 'nginx -s reload'; Output = $result }
}

function Start-Nginx {
    [CmdletBinding()]
    param(
        [switch]$UseSystemctl
    )
    <#
    .SYNOPSIS
    启动 Nginx 服务（如未运行）
    .DESCRIPTION
    检查服务状态并在未运行时启动。
    .EXAMPLE
    Start-Nginx
    #>
    <#
    .SYNOPSIS
    启动 Nginx 服务（如未运行）
    .DESCRIPTION
    检查 Nginx 运行状态，未运行时启动；优先 systemctl，失败则回退到 `nginx` 命令。
    .PARAMETER UseSystemctl
    强制使用 systemctl。
    .EXAMPLE
    Start-Nginx
    #>
    if ($UseSystemctl.IsPresent) {
        & systemctl start nginx 2>&1 | Out-Null
        return
    }
    try {
        $whichSystemctl = & which systemctl 2>$null
        if ($LASTEXITCODE -eq 0 -and $whichSystemctl) {
            $status = & systemctl is-active nginx 2>&1
            if ($status -ne 'active') { & systemctl start nginx 2>&1 | Out-Null }
            return
        }
    }
    catch {}
    # 回退到直接启动
    & nginx 2>&1 | Out-Null
}

function Enable-NginxConf {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$RepoConfPath,
        [switch]$OverwriteAvailable,
        [switch]$UseSystemctl
    )
    <#
    .SYNOPSIS
    启用仓库中的某个 Nginx 配置（方案二）
    .DESCRIPTION
    将仓库内 `.conf` 文件复制到 `/etc/nginx/sites-available/<Name>` 并在 `/etc/nginx/sites-enabled/<Name>` 创建软链接；校验通过后重载。
    .EXAMPLE
    Enable-NginxConf -Name ollama-basic
    #>
    <#
    .SYNOPSIS
    启用仓库中的某个 Nginx 配置（方案二：sites-available/enabled）
    .DESCRIPTION
    将仓库内 `.conf` 文件复制到 `/etc/nginx/sites-available/<Name>`，并在 `/etc/nginx/sites-enabled/<Name>` 创建软链接；校验后重载。
    .PARAMETER Name
    配置名（不带扩展名），例如 `ollama-basic`。
    .PARAMETER RepoConfPath
    仓库内 `.conf` 文件路径；未指定时默认 `config/nginx/sites-available/<Name>.conf`。
    .PARAMETER OverwriteAvailable
    目标已存在时允许覆盖。
    .PARAMETER UseSystemctl
    重载时强制使用 systemctl。
    .EXAMPLE
    Enable-NginxConf -Name ollama-basic
    .EXAMPLE
    Enable-NginxConf -Name ollama-basic -RepoConfPath "$PSScriptRoot/../config/nginx/sites-available/ollama-basic.conf"
    #>
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..') | Select-Object -ExpandProperty Path
    if (-not $RepoConfPath) {
        $RepoConfPath = Join-Path $repoRoot ("config/nginx/sites-available/$Name.conf")
    }
    if (-not (Test-Path -Path $RepoConfPath)) {
        throw "找不到仓库配置文件: $RepoConfPath"
    }

    $availablePath = "/etc/nginx/sites-available/$Name"
    $enabledPath = "/etc/nginx/sites-enabled/$Name"

    if ((Test-Path -Path $availablePath) -and -not $OverwriteAvailable.IsPresent) {
        throw "目标已存在: $availablePath。若需覆盖，请添加 -OverwriteAvailable"
    }

    if ($PSCmdlet.ShouldProcess($availablePath, '复制配置')) {
        Copy-Item -LiteralPath $RepoConfPath -Destination $availablePath -Force
    }

    if ($PSCmdlet.ShouldProcess($enabledPath, '创建软链接')) {
        # ln -sfn 替换已存在的链接
        & ln -sfn $availablePath $enabledPath
    }

    $test = Test-NginxConfig
    if (-not $test.Success) {
        # 回滚链接
        if (Test-Path -Path $enabledPath) { Remove-Item -Force $enabledPath }
        throw "Nginx 配置校验失败: $($test.StdErr)`n$($test.StdOut)"
    }

    Reload-Nginx -UseSystemctl:$UseSystemctl.IsPresent | Out-Null
}

function Disable-NginxConf {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [switch]$UseSystemctl
    )
    <#
    .SYNOPSIS
    禁用指定的 Nginx 配置（删除 sites-enabled 软链接）
    .DESCRIPTION
    删除软链接并重载。
    .EXAMPLE
    Disable-NginxConf -Name ollama-basic
    #>
    <#
    .SYNOPSIS
    禁用指定的 Nginx 配置（删除 sites-enabled 软链接）
    .DESCRIPTION
    删除 `/etc/nginx/sites-enabled/<Name>` 软链接，保留 `sites-available` 原文件；校验后重载。
    .PARAMETER Name
    配置名（不带扩展名）。
    .PARAMETER UseSystemctl
    重载时强制使用 systemctl。
    .EXAMPLE
    Disable-NginxConf -Name ollama-basic
    #>
    $enabledPath = "/etc/nginx/sites-enabled/$Name"
    if (Test-Path -Path $enabledPath) {
        if ($PSCmdlet.ShouldProcess($enabledPath, '删除软链接')) {
            Remove-Item -Force $enabledPath
        }
    }
    $test = Test-NginxConfig
    if (-not $test.Success) {
        throw "Nginx 配置校验失败: $($test.StdErr)`n$($test.StdOut)"
    }
    Reload-Nginx -UseSystemctl:$UseSystemctl.IsPresent | Out-Null
}

function New-NginxHtpasswd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$User,
        [string]$Password,
        [string]$FilePath = '/etc/nginx/.htpasswd'
    )
    <#
    .SYNOPSIS
    生成或更新 Nginx Basic Auth 的 htpasswd 文件
    .DESCRIPTION
    使用 `htpasswd` 工具创建/更新认证文件。
    .EXAMPLE
    New-NginxHtpasswd -User ollama -Password 'your-secret'
    #>
    <#
    .SYNOPSIS
    生成或更新 Nginx Basic Auth 的 htpasswd 文件
    .DESCRIPTION
    使用系统的 `htpasswd` 工具生成受 Nginx 支持的密码文件；若未安装，抛出明确提示并给出安装建议。
    .PARAMETER User
    用户名。
    .PARAMETER Password
    密码；未提供则交互式输入（推荐）。
    .PARAMETER FilePath
    htpasswd 文件路径（默认 `/etc/nginx/.htpasswd`）。
    .EXAMPLE
    New-NginxHtpasswd -User ollama
    .EXAMPLE
    New-NginxHtpasswd -User ollama -Password 'my-secret' -FilePath '/etc/nginx/.htpasswd'
    #>
    $which = & which htpasswd 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $which) {
        throw "未检测到 htpasswd。请安装: Debian/Ubuntu: sudo apt install apache2-utils；CentOS/RHEL: sudo yum install httpd-tools"
    }

    $args = @('-i')
    if (-not (Test-Path -Path $FilePath)) { $args += '-c' }
    $args += @($FilePath, $User)

    if (-not $Password) {
        & htpasswd @args
        return
    }

    # 将密码通过标准输入传入，避免出现在命令行历史或进程列表中
    $Password | & htpasswd @args
}

Export-ModuleMember -Function Test-NginxConfig, Reload-Nginx, Start-Nginx, Enable-NginxConf, Disable-NginxConf, New-NginxHtpasswd
