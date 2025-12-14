# 基于函数回调的过滤功能设计方案

## 🎯 核心设计理念

**函数式过滤** - 直接接受脚本块(ScriptBlock)作为过滤条件，最大化灵活性

## 🏗️ 新增参数设计

```powershell
[Parameter()]
[ScriptBlock]$FilterPredicate,

[Parameter()]
[ScriptBlock[]]$FilterPredicates,

[Parameter()]
[string]$FilterMode = "And"  # "And" | "Or"
```

## 📋 使用示例

### 1. 单一过滤函数
```powershell
Install-PackageManagerApps -PackageManager "homebrew" -FilterPredicate {
    param($app)
    $app.tag -and "linuxserver" -in $app.tag
}
```

### 2. 多过滤函数组合
```powershell
Install-PackageManagerApps -PackageManager "homebrew" -FilterPredicates @(
    { param($app) $app.supportOs -contains "Linux" },
    { param($app) -not $app.skipInstall },
    { param($app) $app.name -like "*git*" }
) -FilterMode "And"
```

### 3. 复杂业务逻辑
```powershell
Install-PackageManagerApps -PackageManager "homebrew" -FilterPredicate {
    param($app)
    # 自定义复杂逻辑
    $isLinuxCompatible = $app.supportOs -contains "Linux"
    $notSkipped = -not $app.skipInstall
    $isServerTool = $app.tag -and "linuxserver" -in $app.tag
    
    $isLinuxCompatible -and $notSkipped -and $isServerTool
}
```

### 4. 预设过滤器函数
```powershell
# 创建可复用的过滤器
$linuxServerFilter = {
    param($app)
    $app.supportOs -contains "Linux" -and 
    $app.tag -and "linuxserver" -in $app.tag -and
    -not $app.skipInstall
}

$developmentToolsFilter = {
    param($app)
    $devTags = @("development", "cli", "tool")
    $app.tag -and ($devTags | Where-Object { $_ -in $app.tag }).Count -gt 0
}

Install-PackageManagerApps -PackageManager "homebrew" -FilterPredicate $linuxServerFilter
```

## 🔧 实现要点

### 1. 过滤执行逻辑
```powershell
function Test-AppFilter {
    param(
        [PSCustomObject]$AppInfo,
        [ScriptBlock[]]$Predicates,
        [string]$Mode = "And"
    )
    
    $results = foreach ($predicate in $Predicates) {
        try {
            & $predicate $AppInfo
        }
        catch {
            Write-Warning "过滤函数执行失败: $($_.Exception.Message)"
            $false
        }
    }
    
    if ($Mode -eq "And") {
        return $results -notcontains $false
    } else {
        return $results -contains $true
    }
}
```

### 2. 集成到现有函数
```powershell
# 在 Install-PackageManagerApps 中添加过滤逻辑
if ($FilterPredicate -or $FilterPredicates) {
    $predicates = @()
    if ($FilterPredicate) { $predicates += $FilterPredicate }
    if ($FilterPredicates) { $predicates += $FilterPredicates }
    
    $InstallList = $InstallList | Where-Object {
        Test-AppFilter -AppInfo $_ -Predicates $predicates -Mode $FilterMode
    }
}
```

## 🎯 优势对比

| 方案 | 灵活性 | 类型安全 | 性能 | 易用性 |
|------|--------|----------|------|--------|
| 当前硬编码 | ❌ 低 | ✅ 高 | ✅ 高 | ❌ 低 |
| 配置对象过滤 | ⚠️ 中 | ⚠️ 中 | ⚠️ 中 | ✅ 高 |
| **函数回调** | ✅ **极高** | ✅ **高** | ✅ **高** | ⚠️ **中** |

## 🚀 扩展能力

### 1. 动态过滤条件
```powershell
# 根据运行时条件动态生成过滤器
$dynamicFilter = {
    param($app)
    $shouldInstall = $true
    
    if ($IsServerEnvironment) {
        $shouldInstall = $app.tag -contains "server"
    }
    
    if ($IsDevelopmentMachine) {
        $shouldInstall = $app.tag -contains "development"
    }
    
    return $shouldInstall
}
```

### 2. 外部数据源过滤
```powershell
# 结合外部配置或API
$externalFilter = {
    param($app)
    $approvedApps = Get-ApprovedAppsFromApi
    return $app.name -in $approvedApps
}
```

### 3. 复杂业务规则
```powershell
$businessRuleFilter = {
    param($app)
    # 实现任意复杂的业务逻辑
    switch ($app.category) {
        "database" { return $IsDatabaseServer }
        "web" { return $IsWebServer }
        "development" { return $IsDevelopmentEnvironment }
        default { return $true }
    }
}
```

## 📝 实施计划

1. **添加 ScriptBlock 参数** - 扩展函数签名
2. **实现 Test-AppFilter** - 核心过滤引擎  
3. **集成过滤逻辑** - 修改现有流程
4. **向后兼容测试** - 确保不破坏现有功能
5. **文档和示例** - 提供使用指南

这种设计提供了最大的灵活性，用户可以实现任意复杂的过滤逻辑，同时保持了代码的简洁性和性能。