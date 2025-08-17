<#
.SYNOPSIS
    比较两个或多个JSON文件的差异

.DESCRIPTION
    使用TypeScript实现的JSON差异比较工具的PowerShell包装器。
    支持JSON、JSONC、JSON5格式文件的比较，提供多种输出格式。
    可以比较单个文件或递归比较目录中的所有JSON文件。

.PARAMETER Path
    要比较的JSON文件路径。支持多个文件路径，至少需要提供两个文件。

.PARAMETER OutputFormat
    输出格式。可选值：table（表格）、json、yaml、tree（树形）。默认为table。

.PARAMETER OutputFile
    将比较结果保存到指定文件。如果不指定，结果将输出到控制台。

.PARAMETER ShowUnchanged
    显示未改变的值。默认只显示差异。

.PARAMETER IgnoreArrayOrder
    忽略数组元素的顺序。默认情况下数组顺序敏感。

.PARAMETER MaxDepth
    比较的最大深度。默认为无限深度。

.PARAMETER FilterPattern
    过滤模式，只显示匹配的差异类型。可选值：added、removed、modified、unchanged。

.PARAMETER Verbose
    显示详细输出信息，包括统计信息。

.PARAMETER Recurse
    递归处理目录中的JSON文件。当Path参数包含目录时使用。

.EXAMPLE
    .\Compare-JsonFiles.ps1 file1.json file2.json
    比较两个JSON文件，使用默认表格格式输出

.EXAMPLE
    .\Compare-JsonFiles.ps1 old.json new.json -OutputFormat json -Verbose
    比较两个文件并以JSON格式输出详细结果

.EXAMPLE
    .\Compare-JsonFiles.ps1 config1.json config2.json -OutputFile diff.txt -ShowUnchanged
    比较文件并将结果（包括未改变的值）保存到文件

.EXAMPLE
    .\Compare-JsonFiles.ps1 dir1\*.json dir2\*.json -Recurse -FilterPattern modified
    递归比较目录中的JSON文件，只显示修改的项

.EXAMPLE
    Get-ChildItem *.json | .\Compare-JsonFiles.ps1 -OutputFormat tree
    通过管道传递文件列表进行比较

.OUTPUTS
    System.String
    输出比较结果，格式取决于OutputFormat参数

.NOTES
    作者: mudssky
    需要Node.js环境和已编译的TypeScript工具
    支持的文件格式：.json, .jsonc, .json5
    工具位置：clis/json-diff-tool/
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true, Mandatory = $true, HelpMessage = "要比较的JSON文件路径（至少两个文件）")]
    [string[]]$Path,
    
    [Parameter(HelpMessage = "输出格式：table、json、yaml、tree")]
    [ValidateSet("table", "json", "yaml", "tree")]
    [string]$OutputFormat = "table",
    
    [Parameter(HelpMessage = "输出文件路径")]
    [string]$OutputFile,
    
    [Parameter(HelpMessage = "显示未改变的值")]
    [switch]$ShowUnchanged,
    
    [Parameter(HelpMessage = "忽略数组元素顺序")]
    [switch]$IgnoreArrayOrder,
    
    [Parameter(HelpMessage = "比较的最大深度")]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$MaxDepth,
    
    [Parameter(HelpMessage = "过滤模式：added、removed、modified、unchanged")]
    [ValidateSet("added", "removed", "modified", "unchanged")]
    [string]$FilterPattern,
    
    [Parameter(HelpMessage = "显示详细输出信息")]
    [switch]$Verbose,
    
    [Parameter(HelpMessage = "递归处理目录")]
    [switch]$Recurse
)

begin {
    # 初始化文件路径数组
    $allFiles = @()
}

process {
    # 收集所有输入的文件路径
    if ($Path) {
        $allFiles += $Path
    }
}

end {
    # 验证输入参数
    if ($allFiles.Count -lt 2) {
        Write-Error "至少需要提供两个文件进行比较"
        Write-Host "使用方法: .\Compare-JsonFiles.ps1 file1.json file2.json" -ForegroundColor Yellow
        exit 1
    }
    
    # 检查Node.js是否可用
    function Test-NodeJs {
        try {
            $nodeVersion = node --version 2>$null
            if ($nodeVersion) {
                Write-Verbose "检测到Node.js版本: $nodeVersion"
                return $true
            }
        }
        catch {
            # 忽略错误
        }
        return $false
    }
    
    # 验证文件是否存在
    function Test-JsonFiles {
        [CmdletBinding()]
        param(
            [string[]]$FilePaths
        )
        
        $validFiles = @()
        $supportedExtensions = @('.json', '.jsonc', '.json5')
        
        foreach ($filePath in $FilePaths) {
            # 展开通配符
            $expandedPaths = @()
            if ($filePath.Contains('*') -or $filePath.Contains('?')) {
                try {
                    $expandedPaths = Get-ChildItem -Path $filePath -File | Select-Object -ExpandProperty FullName
                }
                catch {
                    Write-Warning "无法展开路径模式: $filePath"
                    continue
                }
            }
            else {
                $expandedPaths = @($filePath)
            }
            
            foreach ($expandedPath in $expandedPaths) {
                if (-not (Test-Path $expandedPath -PathType Leaf)) {
                    Write-Warning "文件不存在: $expandedPath"
                    continue
                }
                
                $extension = [System.IO.Path]::GetExtension($expandedPath).ToLower()
                if ($extension -notin $supportedExtensions) {
                    Write-Warning "不支持的文件格式: $expandedPath (支持: $($supportedExtensions -join ', '))"
                    continue
                }
                
                $validFiles += $expandedPath
            }
        }
        
        return $validFiles
    }
    
    # 构建命令行参数
    function Build-CliArguments {
        [CmdletBinding()]
        param(
            [string[]]$Files,
            [hashtable]$Options
        )
        
        $args = @()
        
        # 添加文件路径
        foreach ($file in $Files) {
            $args += "`"$file`""
        }
        
        # 添加选项参数
        if ($Options.OutputFormat) {
            $args += "--output", $Options.OutputFormat
        }
        
        if ($Options.OutputFile) {
            $args += "--file", "`"$($Options.OutputFile)`""
        }
        
        if ($Options.ShowUnchanged) {
            $args += "--show-unchanged"
        }
        
        if ($Options.IgnoreArrayOrder) {
            $args += "--ignore-array-order"
        }
        
        if ($Options.MaxDepth) {
            $args += "--depth", $Options.MaxDepth
        }
        
        if ($Options.FilterPattern) {
            $args += "--filter", $Options.FilterPattern
        }
        
        if ($Options.Verbose) {
            $args += "--verbose"
        }
        
        return $args
    }
    
    try {
        # 检查Node.js环境
        if (-not (Test-NodeJs)) {
            Write-Error "未找到Node.js环境，请确保已安装Node.js并添加到PATH环境变量"
            exit 1
        }
        
        # 验证文件
        $validFiles = Test-JsonFiles -FilePaths $allFiles
        if ($validFiles.Count -lt 2) {
            Write-Error "至少需要两个有效的JSON文件进行比较"
            exit 1
        }
        
        # 确定工具路径
        $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
        $projectRoot = Split-Path -Parent $scriptRoot
        $toolPath = Join-Path $projectRoot "clis\json-diff-tool"
        $indexPath = Join-Path $toolPath "src\index.ts"
        
        if (-not (Test-Path $indexPath)) {
            Write-Error "未找到JSON差异比较工具: $indexPath"
            Write-Host "请确保工具已正确安装在 clis/json-diff-tool/ 目录下" -ForegroundColor Yellow
            exit 1
        }
        
        # 构建选项哈希表
        $options = @{
            OutputFormat = $OutputFormat
        }
        
        if ($OutputFile) { $options.OutputFile = $OutputFile }
        if ($ShowUnchanged) { $options.ShowUnchanged = $true }
        if ($IgnoreArrayOrder) { $options.IgnoreArrayOrder = $true }
        if ($MaxDepth) { $options.MaxDepth = $MaxDepth }
        if ($FilterPattern) { $options.FilterPattern = $FilterPattern }
        if ($Verbose) { $options.Verbose = $true }
        
        # 构建命令行参数
        $cliArgs = Build-CliArguments -Files $validFiles -Options $options
        
        if ($Verbose) {
            Write-Host "正在比较文件:" -ForegroundColor Cyan
            foreach ($file in $validFiles) {
                Write-Host "  - $file" -ForegroundColor Gray
            }
            Write-Host ""
        }
        
        # 执行TypeScript工具
        if ($PSCmdlet.ShouldProcess("JSON文件比较", "执行差异分析")) {
            Push-Location $toolPath
            try {
                # 使用npx tsx直接运行TypeScript文件
                $command = "npx tsx src/index.ts $($cliArgs -join ' ')"
                Write-Verbose "执行命令: $command"
                
                Invoke-Expression $command
                
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "JSON差异比较工具执行失败，退出代码: $LASTEXITCODE"
                    exit $LASTEXITCODE
                }
            }
            finally {
                Pop-Location
            }
        }
    }
    catch {
        Write-Error "执行过程中发生错误: $($_.Exception.Message)"
        Write-Verbose "错误详情: $($_.Exception.ToString())"
        exit 1
    }
}