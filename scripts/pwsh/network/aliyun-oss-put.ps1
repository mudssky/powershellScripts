#!/usr/bin/env pwsh

<#
.SYNOPSIS
    使用 PowerShell 将单个文件或整个目录上传到阿里云 OSS。

.DESCRIPTION
    该脚本是 `psutils/modules/oss.psm1` 的薄入口，负责把 PowerShell 风格的参数
    映射到可复用的 OSS 模块 API。

    功能特点：
    - 支持单文件上传与目录递归上传两个参数集。
    - 默认不覆盖已有对象，只有显式传入 `-Force` 时才允许覆盖。
    - 支持 `AccessKeyId + AccessKeySecret`，并可选支持 `SecurityToken`。
    - 支持自定义 `Endpoint` 或 `Host`，以兼容标准 OSS endpoint 与自定义域名。
    - 支持 `-WhatIf` / `-Confirm` 预览脚本级别的上传操作。

.PARAMETER FilePath
    单文件上传时的本地文件路径。

.PARAMETER ObjectKey
    单文件上传时的目标 OSS 对象键。

.PARAMETER DirectoryPath
    目录上传时的本地目录路径。脚本会递归上传目录中的所有文件。

.PARAMETER Prefix
    目录上传时的远端对象前缀。若为空，则直接使用本地相对路径作为对象键。

.PARAMETER Bucket
    目标 OSS bucket 名称。

.PARAMETER Region
    OSS 区域标识，例如 `cn-hangzhou` 或 `oss-cn-hangzhou`。

.PARAMETER AccessKeyId
    阿里云 AccessKeyId。

.PARAMETER AccessKeySecret
    阿里云 AccessKeySecret。

.PARAMETER SecurityToken
    可选 STS 临时凭证 Token。

.PARAMETER Endpoint
    可选 endpoint 或自定义域名，不能与 `Host` 同时指定。

.PARAMETER Host
    可选实际请求 host，不能与 `Endpoint` 同时指定。

.PARAMETER ContentType
    可选内容类型。若不指定，模块会按扩展名做轻量推断并回退到 `application/octet-stream`。

.PARAMETER Metadata
    可选对象元数据哈希表，会映射为 `x-oss-meta-*` 请求头。

.PARAMETER Tags
    可选对象标签哈希表，会映射为 `x-oss-tagging` 请求头。

.PARAMETER StorageClass
    可选存储类型。

.PARAMETER ObjectAcl
    可选对象 ACL。

.PARAMETER Force
    显式允许覆盖已有对象。未指定时，脚本会保持“默认不覆盖”策略。

.EXAMPLE
    ./scripts/pwsh/network/aliyun-oss-put.ps1 `
      -FilePath ./dist/app.js `
      -ObjectKey assets/app.js `
      -Bucket examplebucket `
      -Region cn-hangzhou `
      -AccessKeyId $env:ALIYUN_ACCESS_KEY_ID `
      -AccessKeySecret $env:ALIYUN_ACCESS_KEY_SECRET

    上传单个本地文件到 OSS。

.EXAMPLE
    ./scripts/pwsh/network/aliyun-oss-put.ps1 `
      -DirectoryPath ./dist `
      -Prefix site-assets `
      -Bucket examplebucket `
      -Region cn-hangzhou `
      -Host static.example.com `
      -AccessKeyId $env:ALIYUN_ACCESS_KEY_ID `
      -AccessKeySecret $env:ALIYUN_ACCESS_KEY_SECRET `
      -Force

    递归上传整个目录到指定前缀，并显式允许覆盖已有对象。
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'File')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'File')]
    [string]$FilePath,

    [Parameter(Mandatory = $true, ParameterSetName = 'File')]
    [string]$ObjectKey,

    [Parameter(Mandatory = $true, ParameterSetName = 'Directory')]
    [string]$DirectoryPath,

    [Parameter(ParameterSetName = 'Directory')]
    [string]$Prefix,

    [Parameter(Mandatory = $true)]
    [string]$Bucket,

    [Parameter(Mandatory = $true)]
    [string]$Region,

    [Parameter(Mandatory = $true)]
    [string]$AccessKeyId,

    [Parameter(Mandatory = $true)]
    [string]$AccessKeySecret,

    [string]$SecurityToken,
    [string]$Endpoint,
    [Alias('Host')]
    [string]$RequestHost,
    [string]$ContentType,
    [hashtable]$Metadata,
    [hashtable]$Tags,

    [ValidateSet('Standard', 'IA', 'Archive', 'ColdArchive', 'DeepColdArchive')]
    [string]$StorageClass,

    [ValidateSet('default', 'private', 'public-read', 'public-read-write')]
    [string]$ObjectAcl,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-AliyunOssPutDependencies {
    <#
    .SYNOPSIS
        导入脚本所需的 OSS 模块。

    .DESCRIPTION
        该函数把模块路径解析集中在一处，便于脚本测试时通过 Mock 屏蔽真实导入，
        也避免入口逻辑和路径计算混在一起。
    #>
    [CmdletBinding()]
    param()

    $modulePath = Join-Path $PSScriptRoot '..' '..' '..' 'psutils' 'modules' 'oss.psm1'
    Import-Module $modulePath -Force | Out-Null
}

function Write-AliyunOssPutSummary {
    <#
    .SYNOPSIS
        输出脚本级别的简短上传摘要。

    .DESCRIPTION
        模块本身返回结构化对象；这个函数只负责在脚本入口中输出一份适合人看的简洁摘要，
        避免调用方必须自己逐个字段展开结果。
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$Result
    )

    if ($null -eq $Result) {
        return
    }

    if ($Result.PSObject.Properties.Name -contains 'Results') {
        Write-Host ("目录上传完成：{0}/{1} 个文件已处理，前缀 {2}" -f $Result.UploadedCount, $Result.FileCount, $Result.Prefix)
        return
    }

    if ($Result.PSObject.Properties.Name -contains 'ObjectKey') {
        Write-Host ("对象上传完成：{0} (request-id: {1})" -f $Result.ObjectKey, $Result.RequestId)
    }
}

function Invoke-AliyunOssPutCommand {
    <#
    .SYNOPSIS
        执行脚本入口对应的 OSS 上传命令。

    .DESCRIPTION
        该函数是脚本的主执行入口。它负责：
        - 导入 OSS 模块依赖。
        - 创建标准化的 OSS 上下文对象。
        - 根据参数集路由到单文件或目录上传 API。
        - 在脚本层提供一次聚合的 `ShouldProcess` 提示，避免预览模式下继续触发模块内的真实上传流程。
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'File')]
        [string]$FilePath,

        [Parameter(Mandatory = $true, ParameterSetName = 'File')]
        [string]$ObjectKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'Directory')]
        [string]$DirectoryPath,

        [Parameter(ParameterSetName = 'Directory')]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [string]$Bucket,

        [Parameter(Mandatory = $true)]
        [string]$Region,

        [Parameter(Mandatory = $true)]
        [string]$AccessKeyId,

        [Parameter(Mandatory = $true)]
        [string]$AccessKeySecret,

        [string]$SecurityToken,
        [string]$Endpoint,
        [Alias('Host')]
        [string]$RequestHost,
        [string]$ContentType,
        [hashtable]$Metadata,
        [hashtable]$Tags,

        [ValidateSet('Standard', 'IA', 'Archive', 'ColdArchive', 'DeepColdArchive')]
        [string]$StorageClass,

        [ValidateSet('default', 'private', 'public-read', 'public-read-write')]
        [string]$ObjectAcl,

        [switch]$Force
    )

    Import-AliyunOssPutDependencies

    $context = New-OssContext `
        -Bucket $Bucket `
        -Region $Region `
        -AccessKeyId $AccessKeyId `
        -AccessKeySecret $AccessKeySecret `
        -SecurityToken $SecurityToken `
        -Endpoint $Endpoint `
        -Host $RequestHost

    $sharedParameters = @{
        Context = $context
        Force   = $Force.IsPresent
    }

    if (-not [string]::IsNullOrWhiteSpace($ContentType)) {
        $sharedParameters.ContentType = $ContentType
    }
    if ($null -ne $Metadata) {
        $sharedParameters.Metadata = $Metadata
    }
    if ($null -ne $Tags) {
        $sharedParameters.Tags = $Tags
    }
    if (-not [string]::IsNullOrWhiteSpace($StorageClass)) {
        $sharedParameters.StorageClass = $StorageClass
    }
    if (-not [string]::IsNullOrWhiteSpace($ObjectAcl)) {
        $sharedParameters.ObjectAcl = $ObjectAcl
    }

    if ($PSCmdlet.ParameterSetName -eq 'Directory') {
        $normalizedPrefix = if ([string]::IsNullOrWhiteSpace($Prefix)) { '' } else { $Prefix.Trim() }
        $previewTarget = if ([string]::IsNullOrWhiteSpace($normalizedPrefix)) {
            "$Bucket/<directory-root>"
        }
        else {
            "$Bucket/$normalizedPrefix"
        }

        if (-not $PSCmdlet.ShouldProcess($previewTarget, "递归上传目录 $DirectoryPath")) {
            return $null
        }

        $publishDirectoryParameters = $sharedParameters.Clone()
        $publishDirectoryParameters.DirectoryPath = $DirectoryPath
        $publishDirectoryParameters.Prefix = $normalizedPrefix

        $result = Publish-OssDirectory @publishDirectoryParameters
        Write-AliyunOssPutSummary -Result $result
        return $result
    }

    if (-not $PSCmdlet.ShouldProcess("$Bucket/$ObjectKey", "上传文件 $FilePath")) {
        return $null
    }

    $publishObjectParameters = $sharedParameters.Clone()
    $publishObjectParameters.FilePath = $FilePath
    $publishObjectParameters.ObjectKey = $ObjectKey

    $result = Publish-OssObject @publishObjectParameters
    Write-AliyunOssPutSummary -Result $result
    return $result
}

if ($env:PWSH_TEST_SKIP_ALIYUN_OSS_PUT_MAIN -ne '1') {
    Invoke-AliyunOssPutCommand @PSBoundParameters
}
