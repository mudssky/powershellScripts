

<#
.SYNOPSIS
    下载AI模型脚本，支持GPU显存和系统内存检测

.DESCRIPTION
    该脚本会检测系统的GPU显存和内存情况，根据可用资源智能选择合适的模型进行下载。
    - 有GPU时：检查显存是否足够运行模型
    - 无GPU时：限制下载小于8GB的模型，使用系统内存运行
    - macOS系统：使用系统内存作为显存计算基准
    - 支持从JSON配置文件读取模型列表
    - 支持skip参数跳过指定模型

.PARAMETER ListOnly
    仅列出符合条件的“计划下载”模型，不实际下载。适合预览资源评估结果。

.PARAMETER ConfigPath
    模型配置文件路径（JSON），默认使用脚本目录下的 `models.json`。

.PARAMETER CpuMaxModelGB
    CPU模式下允许的最大模型大小（GB）。超过该值的模型在无GPU时不下载。

.PARAMETER MemoryMultiplier
    CPU模式内存建议系数：建议内存 = 模型大小 × 系数。用于判定系统内存是否足够。

.PARAMETER MinVramGB
    有GPU时的最低显存下限（GB），用于规范化显存值，避免过低估计。

.PARAMETER Provider
    下载提供者命令名称，例如 `ollama`。需确保该命令已安装可用。

.PARAMETER Skip
    额外跳过的模型名称或ID（数组）。与配置项中的 `skip: true` 合并处理。

.PARAMETER OutputPath
    在 `-ListOnly` 模式下，将计划下载列表导出为 JSON 到该路径。

.EXAMPLE
    .\downloadModels.ps1
    运行脚本自动检测系统资源并下载合适的模型

.EXAMPLE
    .\downloadModels.ps1 -ListOnly -Verbose -OutputPath ./plan.json
    仅列出计划下载的模型并导出为 JSON，显示详细评估信息。

.EXAMPLE
    .\downloadModels.ps1 -CpuMaxModelGB 10 -MemoryMultiplier 1.3 -Skip qwen3:14b
    调整策略并跳过指定模型，便于在不同机器上复用脚本。

.EXAMPLE
    .\downloadModels.ps1 -WhatIf -Confirm
    安全演练下载流程，触发确认但不实际执行拉取。
#>


[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$ListOnly,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'models.json'),
    [double]$CpuMaxModelGB = 8,
    [double]$MemoryMultiplier = 1.5,
    [double]$MinVramGB = 8,
    [string]$Provider = 'ollama',
    [string[]]$Skip = @(),
    [string]$OutputPath
)
Set-StrictMode -Version Latest
$DEFAULTS = @{ CpuMaxModelGB = $CpuMaxModelGB; MemoryMultiplier = $MemoryMultiplier; MinVramGB = $MinVramGB }
# 导入硬件检测模块和操作系统检测模块
Import-Module "$PSScriptRoot\..\psutils\index.psm1" -Force

function Write-ProgressMessage {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    if (-not $ListOnly) { Write-Host $Message -ForegroundColor $Color }
    elseif ($VerbosePreference -eq 'Continue') { Write-Verbose $Message }
}

function Write-Log {
    param(
        [ValidateSet('Info', 'Warn', 'Error', 'Verbose')] [string]$Level,
        [string]$Message,
        [string]$Color = 'White'
    )
    switch ($Level) {
        'Info' { if (-not $ListOnly) { Write-Host $Message -ForegroundColor $Color } else { Write-Verbose $Message } }
        'Warn' { Write-Warning $Message }
        'Error' { Write-Error $Message }
        'Verbose' { Write-Verbose $Message }
    }
}


<#
.SYNOPSIS
    从JSON配置文件加载模型列表

.DESCRIPTION
    读取models.json文件并返回模型配置数组

.OUTPUTS
    返回模型配置数组
#>
function Get-ModelListFromConfig {
    <#
    .SYNOPSIS
        加载并校验模型配置
    .DESCRIPTION
        读取 JSON 配置，校验必填字段并为缺失字段提供合理默认值或估算；返回标准化对象数组。
    .PARAMETER ConfigPath
        配置文件路径
    .OUTPUTS
        PSCustomObject[]，字段：name, modelId, size, vramRequired, skip
    #>
    param([string]$ConfigPath)
    if (-not (Test-Path $ConfigPath)) {
        Write-Error "配置文件不存在: $ConfigPath"
        return @()
    }
    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $raw = @($config.models)
        $result = @()
        foreach ($m in $raw) {
            $name = $m.name
            $id = $m.modelId
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($id)) {
                Write-Warning "模型项缺少必填字段，已跳过"
                continue
            }
            $size = if ($null -ne $m.size -and $m.size -gt 0) { [double]$m.size } else { $CpuMaxModelGB }
            $vram = if ($null -ne $m.vramRequired -and $m.vramRequired -ge 0) { [double]$m.vramRequired } else { [math]::Max(4, [int]([double]$size / 2)) }
            $skipFlag = [bool]$m.skip
            $result += [pscustomobject]@{ name = $name; modelId = $id; size = $size; vramRequired = $vram; skip = $skipFlag }
        }
        return $result
    }
    catch {
        Write-Error "读取配置文件失败: $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    检查模型是否可以下载

.DESCRIPTION
    根据系统资源情况判断模型是否可以下载和运行

.PARAMETER Model
    要检查的模型信息

.PARAMETER GpuInfo
    GPU信息

.PARAMETER MemoryInfo
    内存信息

.OUTPUTS
    返回布尔值表示是否可以下载
#>
function Test-ModelCanDownload {
    param(
        [hashtable]$Model,
        [hashtable]$GpuInfo,
        [hashtable]$MemoryInfo,
        [hashtable]$Policy
    )
    

    $modelMemoryGB = if ($Model.Size ) { [double]$Model.Size } else { [double]$Policy.CpuMaxModelGB }
    $modelVramGB = if ($Model.VramRequired) { $Model.VramRequired } else { 4 }
    
    if ($GpuInfo.HasGpu) {
        # 有GPU时检查显存
        return ($GpuInfo.VramGB -ge $modelVramGB)
    }
    else {
        # 无GPU时限制下载小于8GB的模型，并检查系统内存
        if ($modelMemoryGB -gt [double]$Policy.CpuMaxModelGB) { return $false }
        $requiredMemory = $modelMemoryGB * [double]$Policy.MemoryMultiplier
        return ($MemoryInfo.TotalGB -ge $requiredMemory)
    }
}

function Preprocess-Resources {
    <#
    .SYNOPSIS
        根据操作系统规范化资源信息
    .DESCRIPTION
        macOS 走统一内存路径：以系统内存估算显存；其他系统强制应用最低显存下限。
    .PARAMETER GpuInfo
        GPU信息哈希表
    .PARAMETER MemoryInfo
        内存信息哈希表
    .PARAMETER OsType
        操作系统类型（Get-OperatingSystem）
    .PARAMETER Policy
        策略字典（包含 MinVramGB）
    .OUTPUTS
        规范化后的 GPU 信息哈希表
    #>
    param(
        [hashtable]$GpuInfo,
        [hashtable]$MemoryInfo,
        [string]$OsType,
        [hashtable]$Policy
    )
    if ($OsType -eq 'macOS') {
        Write-ProgressMessage '检测到macOS系统，使用系统内存作为显存计算基准' 'Yellow'
        $GpuInfo.VramGB = [math]::Max(0, $MemoryInfo.TotalGB - 2)
        $GpuInfo.HasGpu = $true
    }
    else {
        $GpuInfo.VramGB = [math]::Max($GpuInfo.VramGB, $Policy.MinVramGB)
    }
    return $GpuInfo
}

function Select-EligibleModels {
    <#
    .SYNOPSIS
        结合跳过规则与资源评估，生成可下载列表
    .DESCRIPTION
        将原始模型配置转为供下载阶段使用的精简对象，并统计跳过数（在主流程中处理）。
    .PARAMETER Models
        原始模型配置数组
    .PARAMETER GpuInfo
        GPU信息
    .PARAMETER MemoryInfo
        内存信息
    .PARAMETER Policy
        策略字典
    .PARAMETER Skip
        额外跳过的模型名称或ID
    .OUTPUTS
        PSCustomObject[]，字段：Name, Id, SizeGB, VramGB
    #>
    param(
        [object[]]$Models,
        [hashtable]$GpuInfo,
        [hashtable]$MemoryInfo,
        [hashtable]$Policy,
        [string[]]$Skip
    )
    $eligible = @()
    foreach ($m in $Models) {
        if ($m.skip -or ($Skip -and ($Skip -contains $m.name -or $Skip -contains $m.modelId))) { continue }
        $ht = @{ Name = $m.name; Size = $m.size; VramRequired = $m.vramRequired; ModelId = $m.modelId }
        if (Test-ModelCanDownload -Model $ht -GpuInfo $GpuInfo -MemoryInfo $MemoryInfo -Policy $DEFAULTS) {
            $eligible += [pscustomobject]@{ Name = $m.name; Id = $m.modelId; SizeGB = $m.size; VramGB = $m.vramRequired }
        }
    }
    return $eligible
}

function Invoke-ModelDownload {
    [CmdletBinding(SupportsShouldProcess = $true)]
    <#
    .SYNOPSIS
        执行模型下载并内置失败重试与确认语义
    .DESCRIPTION
        使用提供者命令拉取模型，失败最多重试3次（指数退避）。支持 `-WhatIf/-Confirm`。
    .PARAMETER Models
        可下载模型列表（Select-EligibleModels 输出）
    .PARAMETER Provider
        提供者命令名称（如 ollama）。需本机可用。
    .OUTPUTS
        哈希表：Downloaded（成功数）、Failed（失败数）
    #>
    param(
        [object[]]$Models,
        [string]$Provider
    )
    $ok = 0; $fail = 0
    if (-not (Get-Command $Provider -ErrorAction SilentlyContinue)) {
        Write-Error "命令不可用: $Provider。请先安装或配置环境。"
        return @{ Downloaded = $ok; Failed = $fail }
    }
    if (-not $ListOnly) {
        Write-Host "`n=== 下载计划 ===" -ForegroundColor Cyan
        Write-Host "目标模型: $(@($Models).Count) 个" -ForegroundColor Green
    }
    foreach ($m in $Models) {
        if ($PSCmdlet.ShouldProcess($m.Name, "Pull model via provider $Provider")) {
            Write-ProgressMessage "准备下载: $($m.Name) (ID: $($m.Id), 大小: $($m.SizeGB)GB, 显存需求: $($m.VramGB)GB)" 'Green'
            $attempt = 0
            while ($attempt -lt 3) {
                try {
                    & $Provider pull $m.Id
                    if ($LASTEXITCODE -eq 0) { $ok++; break }
                    $attempt++
                    Start-Sleep -Seconds ([math]::Pow(2, $attempt))
                }
                catch {
                    $attempt++
                    Start-Sleep -Seconds ([math]::Pow(2, $attempt))
                }
            }
            if ($attempt -ge 3) { $fail++ }
        }
    }
    return @{ Downloaded = $ok; Failed = $fail }
}

function Get-InstalledModels {
    [CmdletBinding()]
    param(
        [string]$Provider
    )
    $models = @()
    if (-not (Get-Command $Provider -ErrorAction SilentlyContinue)) { return $models }
    try {
        $output = & $Provider ls
        $lines = @($output) | Where-Object { $_ -and ($_ -notmatch '^\s*NAME\s+') }
        foreach ($line in $lines) {
            $parts = ($line -split '\s+')
            if ($parts.Count -gt 0) { $models += [pscustomobject]@{ Id = $parts[0] } }
        }
    }
    catch { }
    return $models
}

function Select-RemovableModels {
    [CmdletBinding()]
    param(
        [object[]]$Installed,
        [object[]]$Eligible
    )
    $eligibleIds = @(@($Eligible) | Where-Object { $_ -and $_.PSObject.Properties['Id'] } | ForEach-Object { $_.Id })
    $toRemove = @()
    foreach ($m in $Installed) {
        if ($eligibleIds -notcontains $m.Id) { $toRemove += [pscustomobject]@{ Id = $m.Id } }
    }
    return $toRemove
}

function Invoke-ModelRemoval {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [object[]]$Models,
        [string]$Provider
    )
    $ok = 0; $fail = 0
    if (-not (Get-Command $Provider -ErrorAction SilentlyContinue)) { return @{ Removed = $ok; Failed = $fail } }
    foreach ($m in $Models) {
        if ($PSCmdlet.ShouldProcess($m.Id, "Remove model via provider $Provider")) {
            $attempt = 0
            while ($attempt -lt 3) {
                try {
                    & $Provider rm $m.Id
                    if ($LASTEXITCODE -eq 0) { $ok++; break }
                    $attempt++
                    Start-Sleep -Seconds ([math]::Pow(2, $attempt))
                }
                catch {
                    $attempt++
                    Start-Sleep -Seconds ([math]::Pow(2, $attempt))
                }
            }
            if ($attempt -ge 3) { $fail++ }
        }
    }
    return @{ Removed = $ok; Failed = $fail }
}

# 主程序开始
Write-ProgressMessage "=== AI模型下载脚本 ===" 'Cyan'
Write-ProgressMessage "正在检测系统资源..." 'Yellow'

# 检测操作系统
$osType = Get-OperatingSystem
Write-ProgressMessage "操作系统: $osType" 'White'

# 获取系统信息
$gpuInfo = Get-GpuInfo
$memoryInfo = Get-SystemMemoryInfo
$gpuInfo = Preprocess-Resources -GpuInfo $gpuInfo -MemoryInfo $memoryInfo -OsType $osType -Policy $DEFAULTS

# 从配置文件加载模型列表
$modelList = Get-ModelListFromConfig -ConfigPath $ConfigPath
if ($modelList.Count -eq 0) {
    Write-Error "无法加载模型配置，脚本退出"
    exit 1
}

# 显示系统信息
Write-ProgressMessage "`n系统资源信息:" 'Cyan'
Write-ProgressMessage "GPU状态: $($gpuInfo.GpuType)" 'White'
if ($gpuInfo.HasGpu) {
    Write-ProgressMessage "显存大小: $($gpuInfo.VramGB)GB" 'White'
}
Write-ProgressMessage "系统内存: $($memoryInfo.TotalGB)GB (可用: $($memoryInfo.AvailableGB)GB)" 'White'

Write-ProgressMessage "`n开始检查模型..." 'Cyan'
$eligible = Select-EligibleModels -Models $modelList -GpuInfo $gpuInfo -MemoryInfo $memoryInfo -Policy $DEFAULTS -Skip $Skip
$skippedCount = (@($modelList).Count - @($eligible).Count)

$installed = Get-InstalledModels -Provider $Provider
$toRemove = Select-RemovableModels -Installed $installed -Eligible $eligible

# 显示总结
if ($ListOnly) {
    Write-Host "`n=== 计划下载列表 ===" -ForegroundColor Cyan
    Write-Host "计划下载: $(@($eligible).Count) 个模型" -ForegroundColor Green
    foreach ($item in $eligible) {
        Write-Host "- $($item.Name) (ID: $($item.Id), 大小: $($item.SizeGB)GB, 显存需求: $($item.VramGB)GB)" -ForegroundColor Green
    }
    if ($OutputPath) { $eligible | ConvertTo-Json -Depth 4 | Set-Content -Path $OutputPath }
    Write-Host "跳过模型: $skippedCount 个模型" -ForegroundColor Yellow
    Write-Host "`n=== 计划删除列表 ===" -ForegroundColor Cyan
    Write-Host "计划删除: $(@($toRemove).Count) 个模型" -ForegroundColor Red
    foreach ($r in $toRemove) { Write-Host "- $($r.Id)" -ForegroundColor Red }
}
else {
    $invokeWhatIf = $PSBoundParameters.ContainsKey('WhatIf')
    $result = Invoke-ModelDownload -Models $eligible -Provider $Provider -WhatIf:$invokeWhatIf
    $removeResult = Invoke-ModelRemoval -Models $toRemove -Provider $Provider -WhatIf:$invokeWhatIf
    Write-Host "`n=== 下载完成 ===" -ForegroundColor Cyan
    Write-Host "成功下载: $($result['Downloaded']) 个模型" -ForegroundColor Green
    Write-Host "跳过/失败: $($skippedCount + $result['Failed']) 个模型" -ForegroundColor Yellow
    Write-Host "删除完成: $($removeResult.Removed) 个模型" -ForegroundColor Red
    Write-Host "删除失败: $($removeResult.Failed) 个模型" -ForegroundColor Yellow
}

if (-not $ListOnly -and @($eligible).Count -eq 0) {
    Write-Host "`n建议:" -ForegroundColor Yellow
    if (-not $gpuInfo.HasGpu) {
        Write-Host "- 考虑升级显卡或增加系统内存" -ForegroundColor White
    }
    else {
        Write-Host "- 考虑升级显存以支持更大的模型" -ForegroundColor White
    }
}
