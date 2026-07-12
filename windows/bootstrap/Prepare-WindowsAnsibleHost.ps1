<#
.SYNOPSIS
    准备 Windows 主机供 Ansible 首次通过 SSH 接管。

.DESCRIPTION
    默认只输出 Preview。使用 -Apply 后自动安装 Tailscale 和 Microsoft OpenSSH Server，
    设置 sshd 为 Automatic/Running，并把 OpenSSH DefaultShell 设置为 Windows PowerShell 5.1。
    账号登录、系统重启等交互步骤会完整写入 ManualSteps。

.PARAMETER TailscaleIPv4
    可选显式 Tailscale IPv4。

.PARAMETER SshPort
    SSH 端口，默认 22。

.PARAMETER Apply
    执行真实安装和配置。

.PARAMETER OutputFormat
    Text 或 Json；Json stdout 只输出一个 document。

.PARAMETER SourceRevision
    单文件运行时从公开 GitHub 下载依赖模块使用的 branch、tag 或 commit，默认 master。

.OUTPUTS
    文本摘要或单个 JSON document。进程退出码为 0、1、2 或 10。
#>
[CmdletBinding()]
param(
    [string]$TailscaleIPv4 = '',

    [ValidateRange(1, 65535)]
    [int]$SshPort = 22,

    [switch]$Apply,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [ValidatePattern('^[0-9A-Za-z._/-]+$')]
    [string]$SourceRevision = 'master'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-WindowsAnsiblePreparationModulePath {
    <#
    .SYNOPSIS
        解析本地模块，或为单文件入口下载公开依赖模块。

    .PARAMETER Revision
        GitHub branch、tag 或 commit。

    .OUTPUTS
        System.String。WindowsAnsibleHostPreparation.psm1 的绝对路径。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Revision
    )

    $localModule = Join-Path $PSScriptRoot 'WindowsAnsibleHostPreparation.psm1'
    if (Test-Path -LiteralPath $localModule -PathType Leaf) {
        return [System.IO.Path]::GetFullPath($localModule)
    }

    $cacheRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("powershellScripts-ansible-host-preparation\{0}" -f ($Revision -replace '[/\\]', '_'))
    if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
    }
    $baseUri = "https://raw.githubusercontent.com/mudssky/powershellScripts/$Revision/windows/bootstrap"
    foreach ($fileName in @(
            'WindowsAnsibleHostPreparation.psm1',
            'WindowsBootstrap.psm1',
            'WindowsRemotePsRemoting.psm1'
        )) {
        $destination = Join-Path $cacheRoot $fileName
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            Invoke-WebRequest -Uri "$baseUri/$fileName" -UseBasicParsing -OutFile $destination
        }
        if ((Get-Item -LiteralPath $destination).Length -eq 0) {
            throw "下载的依赖模块为空: $fileName"
        }
    }
    return Join-Path $cacheRoot 'WindowsAnsibleHostPreparation.psm1'
}

$modulePath = Resolve-WindowsAnsiblePreparationModulePath -Revision $SourceRevision
Import-Module $modulePath -Force

$rerunCommand = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Apply -SshPort $SshPort -OutputFormat Json"
if ($TailscaleIPv4) {
    $rerunCommand += " -TailscaleIPv4 $TailscaleIPv4"
}
$rerunCommand += " -SourceRevision $SourceRevision"
$document = Invoke-WindowsAnsibleHostPreparation -TailscaleIPv4 $TailscaleIPv4 -SshPort $SshPort -Apply:$Apply -RerunCommand $rerunCommand

if ($OutputFormat -eq 'Json') {
    [Console]::Out.WriteLine(($document | ConvertTo-Json -Depth 12 -Compress))
}
else {
    Write-Output "[$($document.Status)] platform=$($document.Platform) operation=$($document.Operation) exit=$($document.ExitCode) host=$($document.HostName) tailscale=$($document.TailscaleIPv4)"
    foreach ($result in @($document.Results)) {
        Write-Output ("- {0}: {1} - {2}" -f $result.Name, $result.Status, $result.Message)
    }
    if (@($document.ManualSteps).Count -gt 0) {
        Write-Output 'Manual steps:'
        foreach ($step in @($document.ManualSteps)) {
            Write-Output ("- {0} @ {1}" -f $step.Name, $step.Location)
            Write-Output "  操作: $($step.Command)"
            Write-Output "  验证: $($step.VerifyCommand)"
            Write-Output "  原因: $($step.Reason)"
        }
    }
    foreach ($command in @($document.NextCommands)) {
        Write-Output "Next: $command"
    }
    Write-Output "Rerun: $($document.RerunCommand)"
}

exit [int]$document.ExitCode
