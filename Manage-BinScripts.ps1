#!/usr/bin/env pwsh

<#
.SYNOPSIS
    管理 `bin` 目录脚本 shim 的自动化工具。

.DESCRIPTION
    该脚本用于扫描项目中的 PowerShell 与 Python 脚本，并在 `bin` 目录生成可直接执行的 shim。

    主要能力：
    1. 自动扫描脚本，并跳过 `.git`、`node_modules`、`bin` 等无关目录。
    2. 支持使用 `Patterns` 按相对路径筛选要生成 shim 的脚本。
    3. 支持多种重名处理策略，避免生成到 `bin` 时发生文件名冲突。
    4. 生成的 shim 保留相对路径语义，确保源脚本中的 `$PSScriptRoot` 或调用路径正常工作。
    5. 在 `sync` 时自动清理失效的旧 shim：如果源脚本已不存在，或同一源脚本因改名生成了新的目标文件名，会移除旧的自动生成 shim。

.PARAMETER Action
    要执行的操作：
    - `sync`：扫描项目脚本并同步生成 `bin` 下的 shim。
    - `clean`：清理 `bin` 目录下的 `.ps1` 文件。当前实现不会区分是否为自动生成的 shim，会删除匹配到的所有 `.ps1` 文件，请谨慎使用。

.PARAMETER Force
    强制覆盖 `bin` 目录中已存在的目标文件；未指定时，已存在文件会被跳过。

.PARAMETER Patterns
    可选的 Glob 模式列表，用于筛选需要生成 shim 的脚本。
    例如：`scripts/pwsh/*.ps1`、`ai/**/*.ps1`

    如果未指定，则使用脚本内置的默认模式。

.PARAMETER DuplicateStrategy
    重名处理策略：
    - `PrefixParent`（默认）：使用父目录或更深层路径作为前缀生成唯一文件名，例如 `devops_Clean-DockerImages.ps1`
    - `Overwrite`：后扫描到的脚本覆盖同名目标文件
    - `Skip`：遇到重名时仅保留第一个脚本

.EXAMPLE
    .\Manage-BinScripts.ps1 -Action sync
    使用默认模式同步生成 `bin` shim，并自动清理失效的旧 shim。

.EXAMPLE
    .\Manage-BinScripts.ps1 -Action sync -Patterns 'scripts/pwsh/devops/*.ps1' -Force
    仅同步 `scripts/pwsh/devops` 下的脚本，并强制覆盖已存在的目标文件。

.EXAMPLE
    .\Manage-BinScripts.ps1 -Action sync -DuplicateStrategy Overwrite
    同步脚本，并在目标文件重名时使用覆盖策略。
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet('sync', 'clean')]
    [string]$Action = 'sync',
    
    [Parameter(Mandatory = $false)]
    [string[]]$Patterns = @('scripts/pwsh/**/*.ps1', 'scripts/python/*.py', 'scripts/python/**/*.py', 'ai/coding/claude/*.ps1'),

    [Parameter(Mandatory = $false)]
    [ValidateSet('PrefixParent', 'Overwrite', 'Skip')]
    [string]$DuplicateStrategy = 'PrefixParent',

    [switch]$Force
)

# 配置
$ProjectRoot = $PSScriptRoot
$BinDir = Join-Path $ProjectRoot 'bin'
# 忽略的目录列表
$IgnoreDirs = @('.git', 'node_modules', 'bin', 'dist', 'build', 'coverage', '.claude', '.vscode', '.idea')

# 辅助函数：高性能遍历查找 .ps1 文件
function Find-ProjectScripts {
    param (
        [string]$RootPath,
        [string[]]$IgnoreList
    )
    
    Write-Verbose "正在扫描脚本 (Root: $RootPath, Ignore: $($IgnoreList -join ', '))..."
    $results = [System.Collections.Generic.List[string]]::new()
    
    function Walk {
        param ($Dir)
        try {
            # 1. 获取当前目录下的 .ps1 和 .py 文件
            [System.IO.Directory]::EnumerateFiles($Dir, "*.*") | Where-Object { 
                $_.EndsWith('.ps1') -or $_.EndsWith('.py') 
            } | ForEach-Object { 
                $results.Add($_) 
            }
            
            # 2. 遍历子目录（跳过忽略列表）
            [System.IO.Directory]::EnumerateDirectories($Dir) | ForEach-Object {
                $dirName = [System.IO.Path]::GetFileName($_)
                if ($dirName -notin $IgnoreList) {
                    Walk -Dir $_
                }
            }
        }
        catch {
            Write-Warning "无法访问目录: $Dir ($($_))"
        }
    }
    
    if (Test-Path $RootPath) {
        Walk -Dir $RootPath
    }
    
    return $results
}

# 辅助函数：解析目标文件名（处理重名）
function Resolve-ScriptTargetNames {
    param(
        [string[]]$Scripts,
        [string]$RootPath,
        [string]$Strategy
    )
    
    $mapping = @{} # SourcePath -> TargetFileName
    
    if ($Strategy -eq 'Overwrite') {
        foreach ($s in $Scripts) {
            $name = [System.IO.Path]::GetFileName($s)
            if ($name.EndsWith('.py')) {
                $name = [System.IO.Path]::ChangeExtension($name, '.ps1')
            }
            $mapping[$s] = $name
        }
        return $mapping
    }

    # 初始化：全部使用原始文件名
    foreach ($s in $Scripts) {
        $ext = [System.IO.Path]::GetExtension($s)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($s)
        if ($ext -eq '.py') {
            $mapping[$s] = "${baseName}.ps1"
        }
        else {
            $mapping[$s] = [System.IO.Path]::GetFileName($s)
        }
    }
    
    if ($Strategy -eq 'Skip') {
        # Skip 模式下，如果有重名，只保留第一个，其他的从 mapping 中移除
        # 这里需要先分组，然后处理
        $grouped = $mapping.GetEnumerator() | Group-Object Value
        foreach ($g in $grouped) {
            if ($g.Count -gt 1) {
                # 保留第一个，其他的移除
                for ($i = 1; $i -lt $g.Count; $i++) {
                    $mapping.Remove($g.Group[$i].Key)
                }
            }
        }
        return $mapping
    }

    # Strategy: PrefixParent
    # 迭代解决冲突
    $maxIterations = 10
    for ($i = 0; $i -lt $maxIterations; $i++) {
        # 查找当前 mapping 中的冲突
        $grouped = $mapping.GetEnumerator() | Group-Object Value
        $conflicts = $grouped | Where-Object Count -GT 1
        
        if (-not $conflicts) { break }
        
        foreach ($group in $conflicts) {
            # 对冲突组中的每个文件重新计算名称
            foreach ($entry in $group.Group) {
                $sourcePath = $entry.Key
                
                # 计算相对路径部分
                $relPath = [System.IO.Path]::GetRelativePath($RootPath, $sourcePath)
                # 分割路径，统一分隔符
                $parts = $relPath -split '[\\/]'
                
                # $i=0 -> depth=1 (Parent_File)
                # $i=1 -> depth=2 (Grand_Parent_File)
                $depthNeeded = $i + 1
                
                # 如果路径深度足够
                if ($parts.Count -gt ($depthNeeded + 1)) {
                    # 取最后 N 个部分
                    $startIndex = $parts.Count - ($depthNeeded + 1)
                    $newParts = $parts[$startIndex..($parts.Count - 1)]
                    $newName = $newParts -join '_'
                    $mapping[$sourcePath] = $newName
                }
                else {
                    # 深度不足，使用全路径拼接
                    $newName = $parts -join '_'
                    $mapping[$sourcePath] = $newName
                }
            }
        }
    }
    
    return $mapping
}

function Get-ManagedBinShimMetadata {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $headerLines = Get-Content -LiteralPath $Path -TotalCount 8 -ErrorAction SilentlyContinue
    if (-not $headerLines) {
        return $null
    }

    $isManagedShim = $headerLines | Where-Object { $_ -eq '# Auto-generated shim by Manage-BinScripts.ps1' } | Select-Object -First 1
    if (-not $isManagedShim) {
        return $null
    }

    $sourceMatch = $headerLines | ForEach-Object {
        if ($_ -match '^# Source:\s*(.+)$') {
            $Matches[1].Trim()
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1

    if (-not $sourceMatch) {
        return $null
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) {
        return $null
    }

    return [PSCustomObject]@{
        Name       = $item.Name
        FullName   = $item.FullName
        SourcePath = $sourceMatch
    }
}

function Remove-StaleManagedBinScripts {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([hashtable]$CurrentMapping)

    if (-not (Test-Path $BinDir)) {
        return 0
    }

    $removedCount = 0
    $binScripts = Get-ChildItem -Path $BinDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue

    foreach ($binScript in $binScripts) {
        $metadata = Get-ManagedBinShimMetadata -Path $binScript.FullName
        if ($null -eq $metadata) {
            continue
        }

        $shouldRemove = $false
        $removeReason = $null

        if ($CurrentMapping.ContainsKey($metadata.SourcePath)) {
            $expectedName = $CurrentMapping[$metadata.SourcePath]
            if ($metadata.Name -cne $expectedName) {
                $shouldRemove = $true
                $removeReason = "renamed to $expectedName"
            }
        }
        elseif (-not (Test-Path -LiteralPath $metadata.SourcePath -PathType Leaf)) {
            $shouldRemove = $true
            $removeReason = 'source script no longer exists'
        }

        if (-not $shouldRemove) {
            continue
        }

        if ($PSCmdlet.ShouldProcess($metadata.Name, "Remove stale shim ($removeReason)")) {
            Remove-Item -LiteralPath $metadata.FullName -Force
            Write-Host "清理旧 Shim: $($metadata.Name)" -ForegroundColor DarkYellow
            $removedCount++
        }
    }

    return $removedCount
}

function Sync-BinScripts {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([switch]$Force)
    
    Write-Host "开始分析项目脚本..." -ForegroundColor Green
    Write-Host "重名策略: $DuplicateStrategy" -ForegroundColor Cyan
    
    # 1. 查找所有脚本
    $allScripts = Find-ProjectScripts -RootPath $ProjectRoot -IgnoreList $IgnoreDirs
    
    if ($allScripts.Count -eq 0) {
        Write-Warning "未找到任何 .ps1 脚本。"
        return
    }

    # 2. 应用 Patterns 过滤
    $targetScripts = if ($Patterns.Count -gt 0) {
        Write-Host "应用过滤模式: $($Patterns -join ', ')" -ForegroundColor Cyan
        $allScripts | Where-Object {
            $fullPath = $_
            $relPath = [System.IO.Path]::GetRelativePath($ProjectRoot, $fullPath)
            $normalizedRel = $relPath -replace '\\', '/'
            
            $match = $false
            foreach ($p in $Patterns) {
                if ($normalizedRel -like $p) { 
                    $match = $true 
                    break 
                }
            }
            $match
        }
    }
    else {
        $allScripts
    }

    if ($targetScripts.Count -eq 0) {
        Write-Warning "没有脚本匹配指定的模式。"
        return
    }

    # 3. 解析目标文件名 (处理重名)
    $scriptMapping = Resolve-ScriptTargetNames -Scripts $targetScripts -RootPath $ProjectRoot -Strategy $DuplicateStrategy
    
    # 4. 确保 bin 目录存在
    if (-not (Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
        Write-Host "创建bin目录: $BinDir" -ForegroundColor Yellow
    }

    # 5. 生成 Shim
    $syncedCount = 0
    $skippedCount = 0
    
    foreach ($entry in $scriptMapping.GetEnumerator()) {
        $scriptFullPath = $entry.Key
        $targetName = $entry.Value
        
        $targetPath = Join-Path $BinDir $targetName
        $originalName = [System.IO.Path]::GetFileName($scriptFullPath)
        
        # 如果改名了，打印提示
        if ($targetName -ne $originalName) {
            Write-Host "重命名: $originalName -> $targetName" -ForegroundColor Yellow
        }

        # 检查是否已存在
        if ((Test-Path $targetPath) -and -not $Force) {
            Write-Host "跳过已存在: $targetName" -ForegroundColor DarkGray
            $skippedCount++
            continue
        }
        
        if ($PSCmdlet.ShouldProcess($targetName, "Create Shim for $([System.IO.Path]::GetRelativePath($ProjectRoot, $scriptFullPath))")) {
            try {
                # 计算相对路径
                $sourceRelPath = [System.IO.Path]::GetRelativePath($BinDir, $scriptFullPath)
                $extension = [System.IO.Path]::GetExtension($scriptFullPath).ToLower()
                
                $shimContentLines = @()
                
                if ($extension -eq '.py') {
                    # --- Python Script Shim (via uv) ---
                    $shimContentLines += "#!/usr/bin/env pwsh"
                    $shimContentLines += ""
                    $shimContentLines += "# Auto-generated shim by Manage-BinScripts.ps1"
                    $shimContentLines += "# Source: $scriptFullPath"
                    $shimContentLines += ""
                    $shimContentLines += "`$SourcePath = Join-Path `$PSScriptRoot '$sourceRelPath'"
                    $shimContentLines += "if (-not (Test-Path `$SourcePath)) {"
                    $shimContentLines += "    Write-Error ""Cannot find source script at `$SourcePath"""
                    $shimContentLines += "    exit 1"
                    $shimContentLines += "}"
                    $shimContentLines += ""
                    $shimContentLines += "# Check for uv"
                    $shimContentLines += "if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {"
                    $shimContentLines += "    Write-Error ""'uv' is required to run this script. Please install it: https://github.com/astral-sh/uv"""
                    $shimContentLines += "    exit 1"
                    $shimContentLines += "}"
                    $shimContentLines += ""
                    $shimContentLines += "uv run `$SourcePath @args"
                    $shimContentLines += "exit `$LASTEXITCODE"
                }
                elseif ($extension -eq '.ps1') {
                    # --- PowerShell Script Shim ---
                    $sourceContent = Get-Content -Path $scriptFullPath -Raw
                    $tokens = $null
                    $errors = $null
                    $ast = [System.Management.Automation.Language.Parser]::ParseInput($sourceContent, [ref]$tokens, [ref]$errors)
                    
                    $paramBlockText = $null
                    $helpText = $null
                    $hasCmdletBinding = $false
                    $cmdletBindingText = $null
                    $shimProfileMode = 'NoProfile'

                    if ($ast.ParamBlock) {
                        $paramBlockText = $ast.ParamBlock.Extent.Text
                        foreach ($attr in $ast.ParamBlock.Attributes) {
                            if ($attr.TypeName.FullName -match 'CmdletBinding') {
                                $hasCmdletBinding = $true
                                $cmdletBindingText = $attr.Extent.Text
                                break
                            }
                        }
                    }

                    foreach ($token in $tokens) {
                        if ($token.Kind -eq 'Comment' -and $token.Text -match '^\s*<#\s*\.(SYNOPSIS|DESCRIPTION)') {
                            $helpText = $token.Text
                            break
                        }
                        if ($token.Kind -eq 'Comment' -and $token.Text -match '@ShimProfile:\s*(?<mode>\w+)') {
                            $shimProfileMode = $matches['mode']
                        }
                    }

                    $shebangLine = "#!/usr/bin/env pwsh"
                    switch ($shimProfileMode) {
                        'NoProfile' { $shebangLine = "#!/usr/bin/env -S pwsh -NoProfile" }
                        'Silent' { $shebangLine = "#!/usr/bin/env -S pwsh -NoLogo" }
                        'Default' { $shebangLine = "#!/usr/bin/env pwsh" }
                    }

                    # --- 构建 Shim 内容 ---
                    $shimContentLines += $shebangLine
                    $shimContentLines += ""
                    $shimContentLines += "# Auto-generated shim by Manage-BinScripts.ps1"
                    $shimContentLines += "# Source: $scriptFullPath"
                    $shimContentLines += ""
                    
                    if (-not [string]::IsNullOrWhiteSpace($helpText)) {
                        $shimContentLines += $helpText
                        $shimContentLines += ""
                    }
                    
                    if ($hasCmdletBinding) {
                        $shimContentLines += $cmdletBindingText
                    }
                    elseif ($null -ne $paramBlockText) {
                        $shimContentLines += "[CmdletBinding()]"
                    }
                    
                    if (-not [string]::IsNullOrWhiteSpace($paramBlockText)) {
                        $shimContentLines += $paramBlockText
                        $shimContentLines += ""
                    }

                    $shimContentLines += "`$SourcePath = Join-Path `$PSScriptRoot '$sourceRelPath'"
                    $shimContentLines += "if (-not (Test-Path `$SourcePath)) {"
                    $shimContentLines += "    Write-Error ""Cannot find source script at `$SourcePath"""
                    $shimContentLines += "    exit 1"
                    $shimContentLines += "}"
                    
                    if (-not [string]::IsNullOrWhiteSpace($paramBlockText)) {
                        $shimContentLines += "& `$SourcePath @PSBoundParameters"
                    }
                    else {
                        $shimContentLines += "& `$SourcePath @args"
                    }
                    
                    $shimContentLines += "exit `$LASTEXITCODE"
                }

                # 写入文件
                Set-Content -Path $targetPath -Value $shimContentLines -Encoding utf8NoBOM -Force

                # 写入文件
                Set-Content -Path $targetPath -Value $shimContentLines -Encoding utf8NoBOM -Force
                
                if (-not $IsWindows) {
                    chmod +x $targetPath
                }

                Write-Host "生成 Shim: $targetName" -ForegroundColor Cyan
                $syncedCount++
            }
            catch {
                Write-Error "处理脚本失败 $targetName : $($_.Exception.Message)"
            }
        }
    }

    $removedCount = Remove-StaleManagedBinScripts -CurrentMapping $scriptMapping
    
    Write-Host "`n处理完成!" -ForegroundColor Green
    Write-Host "  新增/更新: $syncedCount" -ForegroundColor White
    Write-Host "  跳过(已存在): $skippedCount" -ForegroundColor White
    Write-Host "  清理旧文件: $removedCount" -ForegroundColor White
}

function Clean-BinScripts {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Write-Host "开始清理bin目录..." -ForegroundColor Green
    
    if (-not (Test-Path $BinDir)) {
        Write-Warning "bin目录不存在: $BinDir"
        return
    }
    
    $binScripts = Get-ChildItem -Path $BinDir -Filter '*.ps1'
    if ($binScripts.Count -eq 0) {
        Write-Host "bin目录为空。" -ForegroundColor Yellow
        return
    }
    
    foreach ($script in $binScripts) {
        Remove-Item -Path $script.FullName -Force
        Write-Host "已删除: $($script.Name)" -ForegroundColor Red
    }
}

# 执行分发
switch ($Action) {
    'sync' {
        Sync-BinScripts -Force:$Force
    }
    'clean' {
        Clean-BinScripts
    }
}


