#!/usr/bin/env pwsh

<#
.SYNOPSIS
    无损音频文件转换为AAC格式的脚本

.DESCRIPTION
    该脚本使用qaac编码器将无损音频文件（如FLAC、WAV等）批量转换为AAC格式。
    支持并行处理以提高转换效率，并可选择保留或删除原始文件。
    支持标准AAC和HE-AAC两种编码模式。

.PARAMETER qaacParam
    qaac编码器的参数，默认为'--verbose --rate keep -v320 -q2 --copy-artwork'

.PARAMETER targetPath
    要处理的目标目录路径，默认为当前目录

.PARAMETER ThrottleLimit
    并行处理的最大线程数，默认为6

.PARAMETER nodelete
    开关参数，如果指定则保留原始无损音频文件

.PARAMETER he
    开关参数，如果指定则使用HE-AAC编码模式

.EXAMPLE
    .\losslessToQaac.ps1
    使用默认设置转换当前目录下的无损音频文件

.EXAMPLE
    .\losslessToQaac.ps1 -targetPath "C:\Music" -nodelete
    转换指定目录下的文件并保留原始文件

.EXAMPLE
    .\losslessToQaac.ps1 -he -ThrottleLimit 4
    使用HE-AAC模式和4个并行线程进行转换

.EXAMPLE
    .\losslessToQaac.ps1 -WhatIf
    使用预演模式（不实际执行），在并行处理下通过 `$using:WhatIfPreference` 控制执行与删除行为

.NOTES
    需要安装qaac编码器
    脚本会记录执行时间
    支持多线程并行处理以提高效率
    在并行执行环境中（`ForEach-Object -Parallel`），`$PSCmdlet` 不可用；`-WhatIf` 语义通过 `$using:WhatIfPreference` 在并行块内实现，不会实际执行转换或删除操作
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


# 记录开始时间，用于计算脚本执行时间
# 这个其实可以不加，其实可以用Measure-Command计算命令执行的时间
# 而且我是用的starship直接就有命令执行时间。
$startTime = Get-Date

if ($he) {
    $qaacParam = '--verbose --copy-artwork --rate keep --he -v320 -q2 '
}



$losslessFiles = @(Get-ChildItem -Recurse -File -LiteralPath $targetPath | Where-Object { ($_.Extension -eq '.flac') -or ($_.Extension -eq '.wav') })
$fileCounts = $losslessFiles.Count
Write-Host -ForegroundColor Green ('Totally found ' + $fileCounts + ' lossless audio files')

# 创建同步哈希表，用于在并发的进程中统计进度
$origin = @{index = 0 }
$sync = [System.Collections.Hashtable]::Synchronized($origin)

$losslessFiles | ForEach-Object  -ThrottleLimit $ThrottleLimit -Parallel {
    
    function Convert-DoubleQuotes {
        param (
            [string]$inputString
        )
        # 使用反引号（`）对双引号进行转义
        # 连续两个双引号也可以代表一个双引号
        $escapedString = $inputString -replace '"', '""'
    
        return $escapedString
    }
    function Convert-SingleQuotes {
        param (
            [string]$inputString
        )
        # 连续两个引号，可以表示一个引号，这里替换左引号
        $escapedString = $inputString -replace "‘", "‘‘"
    
        return $escapedString
    }
    function Remove-IllegalCharacters {
        param(
            [string]$inputString,
            [string]$replaceStr = '',
            # Windows 文件名中不允许的字符列表,另外加上单引号和双引号
            [string]$illegalCharacters = '[\\/:*?"<>|"'']'
        )

       

        # 移除不合法字符
        $cleanedString = $inputString -replace $illegalCharacters, $replaceStr
        return $cleanedString
    }
    $losslessFile = $_
    $fileCountsCopy = $using:fileCounts
    # 引用拷贝，方便后续使用
    $syncCopy = $using:sync

    $qaacParam = $using:qaacParam

    $audiofilePath = $losslessFile.FullName
    Write-Verbose  ('audio path:' + $audiofilePath) 
    
    $audiofileExt = $losslessFile.Extension
    $newfilepath = $audiofilePath.SubString(0, $audiofilePath.Length - $audiofileExt.Length) + '.m4a'
    # 安装了flac解码的模块以后，qaac就可以直接接受flac文件了，所以不用通过cmd转码了和wav是一样的操作
    #  cmd /c 'ffmpeg  -i $($a) qaac64.exe   --verbose --rate keep -v320 -q2 -loglevel quiet '
    #cmd /c ('ffmpeg -loglevel quiet -i "'+$audiofilePath +'" -f wav - | qaac64.exe '+$qaacParam+'  - -o "'+$newfilepath+'"')
    $escapedAudiofilePath = Convert-SingleQuotes $audiofilePath
    $escapedNewfilepath = Convert-SingleQuotes $newfilepath
    Write-Host -ForegroundColor Green ('converting file: {0}' -f $escapedAudiofilePath)
    Write-Host -ForegroundColor Green ('new file path: {0}' -f $escapedNewfilepath)
    if ($audiofileExt -in '.wav', '.flac' ) {
        try {
            # 目前flac与wav命令相同；抑制标准输出/错误输出，失败时在 catch 分支打印上下文信息
            $commandStr = ('qaac.exe  {0} ''{1}'' -o ''{2}''  > $null 2>$null' -f $qaacParam, $escapedAudiofilePath , $escapedNewfilepath)
            if (-not $using:WhatIfPreference) {
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
    
    # 执行完后再处理进度
    ($syncCopy).index += 1

    $progeressPercent = [int](($syncCopy).index / $fileCountsCopy * 100)
    $restCounts = $fileCountsCopy - ($syncCopy).index
    Write-Host  -BackgroundColor Gray -ForegroundColor Black ('converting {0} audio file ,progressing {1}% , {2} rest files' -f ($syncCopy).index, $progeressPercent, $restCounts )
    # 清理工作，检查新文件，删除原文件
    if (Test-Path -LiteralPath  $newfilepath ) {
        if ($nodelete) {
            Write-Host -BackgroundColor Yellow -ForegroundColor Green 'no-delete flag is open'
        }
        else {
            if (-not $using:WhatIfPreference) {
                Write-Host -Verbose -ForegroundColor Cyan ('convert finshed, deleting source audio file: {0}' -f $losslessFile)
                Remove-Item -Force -LiteralPath  $audiofilePath
            }
            else {
                Write-Host -BackgroundColor Yellow -ForegroundColor Green ('WhatIf: would delete source audio file: {0}' -f $audiofilePath)
            }
        }
    }
    else {
        # 新文件没有创建成功，说明转换没有成功
        Write-Host -ForegroundColor Red 'convert file failed'
        
    }
    
}

# 记录结束时间 
$endTime = Get-Date
# {0:N2} 保留两位小数
Write-Host -ForegroundColor Green ('Done,total time: {0:N1} s' -f ($endTime - $startTime).TotalSeconds)
