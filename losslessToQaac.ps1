
[CmdletBinding()]
param(
    [string]$qaacParam = '--verbose --rate keep -v320 -q2 --copy-artwork',
    [string]$targetPath = '.',
    [int]$ThrottleLimit = 6,
    [switch]$nodelete,
    [switch]$he
)


# 记录开始时间，用于计算脚本执行时间
# 这个其实可以不加，其实可以用Measure-Command计算命令执行的时间
# 而且我是用的starship直接就有命令执行时间。
$startTime = Get-Date

if ($he) {
    $qaacParam = '--verbose --copy-artwork --rate keep --he -v320 -q2 '
}



$losslessFiles = Get-ChildItem -Recurse -File  -LiteralPath $targetPath | Where-Object { ($_.Extension -eq '.flac') -or ($_.Extension -eq '.wav') }
$fileCounts = $losslessFiles.Length
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
        # 目前flac与wav命令相同
        # $commandStr = ('qaac64.exe  ' + $qaacParam + ' "' + $audiofilePath + '" -o "' + $newfilepath + '"')
        # > $null 2>$null 分别是忽略stdout 和stderr
        $commandStr = ('qaac.exe  {0} ''{1}'' -o ''{2}''  > $null 2>$null' -f $qaacParam, $escapedAudiofilePath , $escapedNewfilepath)
        Write-Host $commandStr
        Invoke-Expression $commandStr  
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
            Write-Host -Verbose -ForegroundColor   Cyan ('convert finshed, deleting source audio file: {0}' -f $losslessFile)
            Remove-Item -Force -LiteralPath  $audiofilePath
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