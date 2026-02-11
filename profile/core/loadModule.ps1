$moduleParent = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$psutilsRoot = Join-Path $moduleParent 'psutils'
$moduleManifest = Join-Path $psutilsRoot 'psutils.psd1'
$modulesDir = Join-Path $psutilsRoot 'modules'

# ── 第 1 层：同步加载核心子模块（仅 profile 启动路径必需的 6 个） ──
# 使用 Import-Module 逐个加载（.psm1 不支持 dot-source，必须走模块系统）
# 加载顺序按依赖关系：os → cache(依赖 os) → test → env → proxy → wrapper
$coreModules = @('os', 'cache', 'test', 'env', 'proxy', 'wrapper')
foreach ($mod in $coreModules) {
    $modPath = Join-Path $modulesDir "$mod.psm1"
    try {
        Import-Module $modPath -Global -ErrorAction Stop
    }
    catch {
        Write-Error "[profile/core/loadModule.ps1] Import-Module 失败: $modPath :: $($_.Exception.Message)"
        throw
    }
}

# ── 第 2 层：PSModulePath 兜底（确保 PowerShell 自动发现 psutils.psd1） ──
# 需要将 psutils 的父目录加入 PSModulePath（PowerShell 按 ModuleName/ModuleName.psd1 结构查找）
$psutilsParent = Split-Path -Parent $psutilsRoot
$sep = [System.IO.Path]::PathSeparator
$pathComparer = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}

# 将 psutils 父目录追加到 PSModulePath（仅在尚未存在时）
$currentPaths = ($env:PSModulePath -split [string]$sep) | Where-Object { $_ }
$alreadyInPath = $false
foreach ($p in $currentPaths) {
    if ($pathComparer.Equals($p, $psutilsParent)) {
        $alreadyInPath = $true
        break
    }
}
if (-not $alreadyInPath) {
    $env:PSModulePath = $env:PSModulePath + $sep + $psutilsParent
}

# PSModulePath 去重（清理重复条目）
$paths = ($env:PSModulePath -split [string]$sep) | Where-Object { $_ }
$seenPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
$uniquePaths = [System.Collections.Generic.List[string]]::new()

foreach ($path in $paths) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if ($seenPaths.Add($path)) {
        $uniquePaths.Add($path) | Out-Null
    }
}

$env:PSModulePath = ($uniquePaths.ToArray()) -join $sep

# ── 第 3 层：OnIdle 事件延迟全量加载（空闲时静默加载完整 psutils 模块） ──
# 将 wrapper.ps1 的加载也合并到此处
# 注意：PowerShell 7.5 的 Register-EngineEvent -MessageData 对 OnIdle 事件传递为 $null（引擎 bug），
# 因此使用局部变量 + .GetNewClosure() 将值烘焙到脚本块的闭包中
$__idleManifestPath = [string]$moduleManifest
$__idleWrapperPath = [string](Join-Path (Split-Path -Parent $PSScriptRoot) 'wrapper.ps1')
Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
    try {
        # 全量加载 psutils 模块（覆盖单独加载的子模块，补全其余子模块）
        Import-Module $__idleManifestPath -Force -Global -ErrorAction Stop
    }
    catch {
        Write-Warning "[profile/loadModule.ps1] OnIdle psutils 全量加载失败: $($_.Exception.Message)"
    }
    try {
        # 延迟加载 wrapper.ps1（yaz, Add-CondaEnv 等函数）
        if (Test-Path $__idleWrapperPath) {
            . $__idleWrapperPath
        }
    }
    catch {
        Write-Warning "[profile/loadModule.ps1] OnIdle wrapper.ps1 加载失败: $($_.Exception.Message)"
    }
}.GetNewClosure() | Out-Null
