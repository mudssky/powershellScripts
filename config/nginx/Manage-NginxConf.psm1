Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-NginxConfig {
    [CmdletBinding()]
    param()
    <#
    .SYNOPSIS
    校验 Nginx 配置语法是否正确
    .DESCRIPTION
    运行 `nginx -t` 并返回结构化结果（Success/ExitCode/StdOut/StdErr），用于在启用/禁用前后验证配置。
    .EXAMPLE
    Test-NginxConfig
    #>
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath 'nginx' -ArgumentList '-t' -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $proc.WaitForExit()
        $stdout = Get-Content -Raw -Path $stdoutPath
        $stderr = Get-Content -Raw -Path $stderrPath
        $success = ($proc.ExitCode -eq 0)
        [PSCustomObject]@{
            Success = $success
            ExitCode = $proc.ExitCode
            StdOut  = $stdout
            StdErr  = $stderr
        }
    } catch {
        [PSCustomObject]@{
            Success = $false
            ExitCode = -1
            StdOut  = ''
            StdErr  = $_.Exception.Message
        }
    } finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $stdoutPath, $stderrPath
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
    .PARAMETER UseSystemctl
    强制使用 systemctl 控制 Nginx。
    .EXAMPLE
    Reload-Nginx
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
    } catch {}
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
    检查服务状态并在未运行时启动；优先使用 `systemctl`。
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
    } catch {}
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
    启用仓库中的某个 Nginx 配置（方案二：sites-available/enabled）
    .DESCRIPTION
    将仓库内 `.conf` 文件复制到 `/etc/nginx/sites-available/<Name>` 并在 `/etc/nginx/sites-enabled/<Name>` 创建软链接；校验通过后平滑重载。
    .PARAMETER Name
    配置名（不带扩展名）。
    .PARAMETER RepoConfPath
    仓库内 `.conf` 文件路径；默认 `config/nginx/sites-available/<Name>.conf`。
    .PARAMETER OverwriteAvailable
    目标已存在时允许覆盖。
    .PARAMETER UseSystemctl
    重载时强制使用 systemctl。
    .EXAMPLE
    Enable-NginxConf -Name ollama-basic
    #>
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..') | Select-Object -ExpandProperty Path
    if (-not $RepoConfPath) {
        $RepoConfPath = Join-Path $repoRoot ("config/nginx/sites-available/$Name.conf")
    }
    if (-not (Test-Path -Path $RepoConfPath)) {
        throw "找不到仓库配置文件: $RepoConfPath"
    }

    $availablePath = "/etc/nginx/sites-available/$Name"
    $enabledPath   = "/etc/nginx/sites-enabled/$Name"

    if ((Test-Path -Path $availablePath) -and -not $OverwriteAvailable.IsPresent) {
        throw "目标已存在: $availablePath。若需覆盖，请添加 -OverwriteAvailable"
    }

    if ($PSCmdlet.ShouldProcess($availablePath, '复制配置')) {
        Copy-Item -LiteralPath $RepoConfPath -Destination $availablePath -Force
    }

    if ($PSCmdlet.ShouldProcess($enabledPath, '创建软链接')) {
        & ln -sfn $availablePath $enabledPath
    }

    $test = Test-NginxConfig
    if (-not $test.Success) {
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
    使用系统的 `htpasswd` 工具创建/更新认证文件；未安装时给出安装建议。
    .PARAMETER User
    用户名。
    .PARAMETER Password
    密码；未提供时进入交互式输入。
    .PARAMETER FilePath
    htpasswd 文件路径（默认 `/etc/nginx/.htpasswd`）。
    .EXAMPLE
    New-NginxHtpasswd -User ollama -Password 'your-secret'
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

    try {
        $Password | & htpasswd @args
    } catch {
        # 针对没有权限写入 /etc/nginx 的场景，给予清晰提示
        throw "创建/更新 htpasswd 失败：请确认有写入权限或使用 sudo。当前路径: $FilePath"
    }
}

Export-ModuleMember -Function Test-NginxConfig, Reload-Nginx, Start-Nginx, Enable-NginxConf, Disable-NginxConf, New-NginxHtpasswd
function Get-NginxEnabledConfs {
    [CmdletBinding()]
    param()
    <#
    .SYNOPSIS
    列出已启用的 Nginx 配置（sites-enabled）
    .DESCRIPTION
    返回软链接名称、路径及目标存在性。
    .OUTPUTS
    PSCustomObject[]
    #>
    $dir = '/etc/nginx/sites-enabled'
    if (-not (Test-Path $dir)) { return @() }
    Get-ChildItem -LiteralPath $dir -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.Name
        $enabledPath = $_.FullName
        $availablePath = "/etc/nginx/sites-available/$name"
        $isSymlink = $_.Attributes -band [IO.FileAttributes]::ReparsePoint
        [PSCustomObject]@{
            Name = $name
            EnabledPath = $enabledPath
            AvailablePath = $availablePath
            IsSymlink = [bool]$isSymlink
            TargetExists = (Test-Path -Path $availablePath)
        }
    }
}

function Get-NginxAvailableConfs {
    [CmdletBinding()]
    param()
    <#
    .SYNOPSIS
    列出已安装的 Nginx 配置（sites-available）
    .OUTPUTS
    PSCustomObject[]
    #>
    $dir = '/etc/nginx/sites-available'
    if (-not (Test-Path $dir)) { return @() }
    Get-ChildItem -LiteralPath $dir -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; AvailablePath = $_.FullName }
    }
}

function Get-NginxConfContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [ValidateSet('available','enabled','repo')] [string]$Source = 'available'
    )
    <#
    .SYNOPSIS
    查看某个配置的内容
    .DESCRIPTION
    从系统 available/enabled 或仓库模板读取文本内容。
    .OUTPUTS
    string
    #>
    switch ($Source) {
        'available' { $path = "/etc/nginx/sites-available/$Name" }
        'enabled'   { $path = "/etc/nginx/sites-enabled/$Name" }
        'repo'      {
            $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..') | Select-Object -ExpandProperty Path
            $path = Join-Path $repoRoot ("config/nginx/sites-available/$Name.conf")
        }
    }
    if (-not (Test-Path -Path $path)) { throw "找不到配置文件: $path" }
    Get-Content -Raw -Path $path
}

function Remove-NginxConf {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [switch]$Force,
        [switch]$UseSystemctl
    )
    <#
    .SYNOPSIS
    移除 available 中的配置文件，可选同时删除 enabled 的软链接
    .DESCRIPTION
    默认仅移除 available 文件；若存在 enabled 链接，需 `-Force` 才会一并删除。
    #>
    $availablePath = "/etc/nginx/sites-available/$Name"
    $enabledPath = "/etc/nginx/sites-enabled/$Name"

    if ((Test-Path $enabledPath) -and -not $Force.IsPresent) {
        throw "发现已启用的软链接: $enabledPath。若要同时删除，请添加 -Force 再试"
    }

    if (Test-Path $enabledPath) {
        if ($PSCmdlet.ShouldProcess($enabledPath, '删除软链接')) { Remove-Item -Force $enabledPath }
    }

    if (Test-Path $availablePath) {
        if ($PSCmdlet.ShouldProcess($availablePath, '删除配置文件')) { Remove-Item -Force $availablePath }
    }

    $test = Test-NginxConfig
    if (-not $test.Success) { throw "Nginx 配置校验失败: $($test.StdErr)`n$($test.StdOut)" }
    Reload-Nginx -UseSystemctl:$UseSystemctl.IsPresent | Out-Null
}

function Test-NginxEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Url,
        [string]$BasicUser,
        [string]$BasicPassword,
        [string]$BearerToken,
        [int]$TimeoutSec = 10
    )
    <#
    .SYNOPSIS
    对指定 URL 进行 HTTP 冒烟测试
    .DESCRIPTION
    支持 Basic Auth 或 Bearer Token；返回状态码与响应片段。
    .OUTPUTS
    PSCustomObject
    #>
    try {
        $headers = @{}
        if ($BearerToken) { $headers['Authorization'] = "Bearer $BearerToken" }
        $params = @{ Uri = $Url; Headers = $headers; TimeoutSec = $TimeoutSec; ErrorAction = 'Stop' }
        if ($BasicUser) { $params['Authentication'] = 'basic'; $params['Credential'] = New-Object System.Management.Automation.PSCredential($BasicUser, (ConvertTo-SecureString $BasicPassword -AsPlainText -Force)) }
        $resp = Invoke-WebRequest @params
        [PSCustomObject]@{ StatusCode = $resp.StatusCode; Success = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300); BodyPreview = ($resp.Content.Substring(0, [Math]::Min(200, $resp.Content.Length))) ; Error = '' }
    } catch {
        [PSCustomObject]@{ StatusCode = 0; Success = $false; BodyPreview = ''; Error = $_.Exception.Message }
    }
}

function Verify-NginxConf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$Url,
        [string]$BasicUser,
        [string]$BasicPassword,
        [string]$BearerToken
    )
    <#
    .SYNOPSIS
    综合验证指定配置是否生效
    .DESCRIPTION
    检查软链接存在性、目标存在性、语法校验；若提供 URL 与认证信息，执行 HTTP 冒烟测试。
    .OUTPUTS
    PSCustomObject
    #>
    $enabledPath = "/etc/nginx/sites-enabled/$Name"
    $availablePath = "/etc/nginx/sites-available/$Name"
    $hasSymlink = Test-Path -Path $enabledPath
    $targetExists = Test-Path -Path $availablePath
    $syntax = Test-NginxConfig
    $http = $null
    if ($Url) { $http = Test-NginxEndpoint -Url $Url -BasicUser $BasicUser -BasicPassword $BasicPassword -BearerToken $BearerToken }
    [PSCustomObject]@{
        HasSymlink = $hasSymlink
        TargetExists = $targetExists
        SyntaxOk = $syntax.Success
        HttpOk = if ($http) { $http.Success } else { $null }
        Diagnostics = @{ NginxTest = $syntax; Endpoint = $http }
    }
}

Export-ModuleMember -Function Get-NginxEnabledConfs, Get-NginxAvailableConfs, Get-NginxConfContent, Remove-NginxConf, Test-NginxEndpoint, Verify-NginxConf
