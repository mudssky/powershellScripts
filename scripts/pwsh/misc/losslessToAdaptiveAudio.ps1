#!/usr/bin/env pwsh

<#
.SYNOPSIS
    无损音频文件转换脚本（优先 qaac，缺失时回退 ffmpeg libopus）

.DESCRIPTION
    该脚本会批量转换无损音频文件（如 FLAC、WAV）。
    默认优先使用 qaac 输出 AAC（.m4a）；当 qaac 不存在时自动回退到 ffmpeg libopus 输出 OGG（.ogg）。

.PARAMETER qaacParam
    qaac 编码参数，默认 '--verbose --rate keep -v320 -q2 --copy-artwork'

.PARAMETER targetPath
    要处理的目标目录，默认当前目录

.PARAMETER ThrottleLimit
    并行处理最大线程数，默认 6

.PARAMETER nodelete
    指定后保留原始无损文件

.PARAMETER he
    指定后在 qaac 模式启用 HE-AAC 参数；ffmpeg 回退模式下会忽略该参数

.EXAMPLE
    .\losslessToAdaptiveAudio.ps1

.EXAMPLE
    .\losslessToAdaptiveAudio.ps1 -targetPath "C:\Music" -nodelete

.EXAMPLE
    .\losslessToAdaptiveAudio.ps1 -he -ThrottleLimit 4

.EXAMPLE
    .\losslessToAdaptiveAudio.ps1 -WhatIf

.NOTES
    - 需要安装 qaac 或 ffmpeg。
    - 在并行环境（ForEach-Object -Parallel）中，通过 `$using:WhatIfMode` 维持 WhatIf 语义。
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$qaacParam = '--verbose --rate keep -v320 -q2 --copy-artwork',
    [string]$targetPath = '.',
    [int]$ThrottleLimit = 6,
    [switch]$nodelete,
    [switch]$he
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Convert-SingleQuotes {
    param(
        [string]$InputString
    )

    if ($null -eq $InputString) {
        return ''
    }

    return $InputString -replace "'", "''"
}

function Resolve-EncoderMode {
    if (Get-Command 'qaac.exe' -ErrorAction SilentlyContinue) {
        return 'qaac'
    }

    if (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue) {
        return 'ffmpeg-opus'
    }

    throw 'Neither qaac.exe nor ffmpeg was found in PATH. Please install one of them.'
}

function Get-OutputExtension {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('qaac', 'ffmpeg-opus')]
        [string]$EncoderMode
    )

    if ($EncoderMode -eq 'ffmpeg-opus') {
        return '.ogg'
    }

    return '.m4a'
}

function New-EncodeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('qaac', 'ffmpeg-opus')]
        [string]$EncoderMode,

        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string]$QaacParam
    )

    $escapedInputPath = Convert-SingleQuotes -InputString $InputPath
    $escapedOutputPath = Convert-SingleQuotes -InputString $OutputPath

    if ($EncoderMode -eq 'ffmpeg-opus') {
        return ("ffmpeg -y -i '{0}' -c:a libopus -b:a 256k '{1}' > `$null 2>`$null" -f $escapedInputPath, $escapedOutputPath)
    }

    return ("qaac.exe {0} '{1}' -o '{2}' > `$null 2>`$null" -f $QaacParam, $escapedInputPath, $escapedOutputPath)
}

function Invoke-LosslessToAdaptiveAudio {
    param(
        [string]$QaacParam,
        [string]$TargetPath,
        [int]$ParallelThrottle,
        [bool]$NoDelete,
        [bool]$UseHe,
        [bool]$WhatIfMode
    )

    $startTime = Get-Date

    $encoderMode = Resolve-EncoderMode
    $outputExtension = Get-OutputExtension -EncoderMode $encoderMode

    $effectiveQaacParam = $QaacParam
    if ($UseHe -and $encoderMode -eq 'qaac') {
        $effectiveQaacParam = '--verbose --copy-artwork --rate keep --he -v320 -q2'
    }
    elseif ($UseHe -and $encoderMode -eq 'ffmpeg-opus') {
        Write-Host -ForegroundColor Yellow 'qaac HE mode is ignored in ffmpeg-opus fallback mode.'
    }

    if ($encoderMode -eq 'ffmpeg-opus') {
        Write-Host -ForegroundColor Yellow 'qaac.exe was not found. Falling back to ffmpeg libopus (.ogg).'
    }
    else {
        Write-Host -ForegroundColor Green 'Using qaac encoder (.m4a).'
    }

    $losslessFiles = @(
        Get-ChildItem -Recurse -File -LiteralPath $TargetPath |
            Where-Object { $_.Extension -in '.flac', '.wav' }
    )
    $fileCounts = $losslessFiles.Count
    Write-Host -ForegroundColor Green ('Totally found {0} lossless audio files' -f $fileCounts)

    $origin = @{ index = 0 }
    $sync = [System.Collections.Hashtable]::Synchronized($origin)

    $losslessFiles | ForEach-Object -ThrottleLimit $ParallelThrottle -Parallel {
        $losslessFile = $_
        $fileCountsCopy = $using:fileCounts
        $syncCopy = $using:sync
        $encoderModeCopy = $using:encoderMode
        $outputExtensionCopy = $using:outputExtension
        $effectiveQaacParamCopy = $using:effectiveQaacParam
        $nodeleteCopy = $using:NoDelete
        $whatIfModeCopy = $using:WhatIfMode

        $audiofilePath = $losslessFile.FullName
        $audiofileExt = $losslessFile.Extension
        $newfilepath = $audiofilePath.SubString(0, $audiofilePath.Length - $audiofileExt.Length) + $outputExtensionCopy

        Write-Host -ForegroundColor Green ('converting file: {0}' -f $audiofilePath)
        Write-Host -ForegroundColor Green ('new file path: {0}' -f $newfilepath)

        if ($audiofileExt -in '.wav', '.flac') {
            try {
                $escapedAudiofilePath = $audiofilePath -replace "'", "''"
                $escapedNewfilepath = $newfilepath -replace "'", "''"

                if ($encoderModeCopy -eq 'ffmpeg-opus') {
                    $commandStr = ("ffmpeg -y -i '{0}' -c:a libopus -b:a 256k '{1}' > `$null 2>`$null" -f $escapedAudiofilePath, $escapedNewfilepath)
                }
                else {
                    $commandStr = ("qaac.exe {0} '{1}' -o '{2}' > `$null 2>`$null" -f $effectiveQaacParamCopy, $escapedAudiofilePath, $escapedNewfilepath)
                }

                if (-not $whatIfModeCopy) {
                    Invoke-Expression $commandStr
                }
                else {
                    Write-Host -ForegroundColor Yellow ('WhatIf: would run {0}' -f $commandStr)
                }
            }
            catch {
                Write-Host -ForegroundColor Red ('转换命令执行失败: {0}, 错误: {1}' -f $audiofilePath, $_.Exception.Message)
            }
        }
        else {
            Write-Host -ForegroundColor Red ('Error. Unsupported format:{0}' -f $audiofilePath)
        }

        $syncCopy.index += 1

        $progeressPercent = if ($fileCountsCopy -eq 0) { 100 } else { [int](($syncCopy.index / $fileCountsCopy) * 100) }
        $restCounts = $fileCountsCopy - $syncCopy.index
        Write-Host -BackgroundColor Gray -ForegroundColor Black ('converting {0} audio file ,progressing {1}% , {2} rest files' -f $syncCopy.index, $progeressPercent, $restCounts)

        if (Test-Path -LiteralPath $newfilepath) {
            if ($nodeleteCopy) {
                Write-Host -BackgroundColor Yellow -ForegroundColor Green 'no-delete flag is open'
            }
            else {
                if (-not $whatIfModeCopy) {
                    Write-Host -Verbose -ForegroundColor Cyan ('convert finshed, deleting source audio file: {0}' -f $losslessFile)
                    Remove-Item -Force -LiteralPath $audiofilePath
                }
                else {
                    Write-Host -BackgroundColor Yellow -ForegroundColor Green ('WhatIf: would delete source audio file: {0}' -f $audiofilePath)
                }
            }
        }
        else {
            Write-Host -ForegroundColor Red 'convert file failed'
        }
    }

    $endTime = Get-Date
    Write-Host -ForegroundColor Green ('Done,total time: {0:N1} s' -f ($endTime - $startTime).TotalSeconds)
}

# 允许测试通过 dot-source 加载函数，而不触发主流程
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-LosslessToAdaptiveAudio `
        -QaacParam $qaacParam `
        -TargetPath $targetPath `
        -ParallelThrottle $ThrottleLimit `
        -NoDelete $nodelete.IsPresent `
        -UseHe $he.IsPresent `
        -WhatIfMode $WhatIfPreference
}
