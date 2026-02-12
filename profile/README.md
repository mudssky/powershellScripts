# Profile 系统

PowerShell 7+ 跨平台 profile 系统，支持 Windows/Linux/macOS。提供模块化加载、工具初始化、别名管理和性能优化。

## 目录结构

```
profile/
├── profile.ps1              # 主入口（Windows & Linux/macOS 共用）
├── profile_unix.ps1         # Unix 入口（向后兼容 shim，转发到 profile.ps1）
├── core/                    # 核心加载层
│   ├── encoding.ps1         # UTF-8 编码设置
│   ├── mode.ps1             # 模式判定（Full/Minimal/UltraMinimal）
│   ├── loaders.ps1          # 核心加载器（模块 + 别名配置）
│   └── loadModule.ps1       # psutils 分层延迟加载 + OnIdle 事件
├── features/                # 功能模块
│   ├── environment.ps1      # 环境初始化（代理、工具、别名）
│   ├── help.ps1             # 帮助系统
│   └── install.ps1          # Profile 安装到 $PROFILE
├── config/
│   └── aliases/
│       └── user_aliases.ps1 # 用户别名定义（声明式配置）
├── .cache/                  # 工具初始化缓存（自动生成，gitignored）
├── env.ps1                  # 个人环境变量（API keys 等，gitignored）
├── wrapper.ps1              # 包装函数（yaz, Add-CondaEnv 等，OnIdle 加载）
├── installer/               # 环境安装脚本
├── Debug-ProfilePerformance.ps1  # 性能诊断脚本
└── README.md                # 本文件
```

## 加载流程

```
profile.ps1
    │
    ├── Phase 1: dot-source-definitions (~180ms)
    │   定义函数但不执行，加载 6 个文件
    │
    ├── Phase 2: mode-decision (~90ms)
    │   判定 Full / Minimal / UltraMinimal 模式
    │
    ├── Phase 3: core-loaders (~290ms)
    │   ├── 同步加载 6 个核心 psutils 子模块
    │   ├── PSModulePath 兜底（自动发现）
    │   ├── 加载用户别名配置
    │   └── 注册 OnIdle 事件（延迟全量加载）
    │
    └── Phase 4: initialize-environment (~600ms)
        ├── 代理自动检测（缓存 5 分钟）
        ├── UTF-8 编码设置
        ├── 工具初始化（starship, zoxide, fnm, sccache）
        └── 别名注册
```

### OnIdle 延迟加载

以下操作在用户首次空闲时执行，不阻塞启动：

- `Import-Module psutils.psd1 -Force` — 全量加载 psutils（70+ 函数）
- `wrapper.ps1` — yaz, Add-CondaEnv 等包装函数
- `Register-FzfHistorySmartKeyBinding` — fzf 历史搜索键绑定
- `Set-PSReadLineKeyHandler -Key Tab` — Tab 补全模式设置

## 模式

| 模式 | 触发方式 | 加载内容 |
|------|----------|----------|
| **Full** | 默认 | 全部加载 |
| **Minimal** | `POWERSHELL_PROFILE_MODE=minimal` | 模块加载，跳过工具+别名 |
| **UltraMinimal** | `POWERSHELL_PROFILE_MODE=ultra` 或 Codex 环境自动降级 | 仅 UTF-8 + `POWERSHELL_SCRIPTS_ROOT` |

## 性能诊断

### 快速查看阶段耗时

```powershell
# 设置环境变量启用计时报告
$env:POWERSHELL_PROFILE_TIMING='1'
pwsh -NoLogo
```

输出示例：
```
=== Profile 加载计时 ===
  dot-source-definitions            183ms
  mode-decision                      88ms
  core-loaders                      276ms
  initialize-environment            594ms
  total                            1141ms
```

### 详细分步诊断

使用 `Debug-ProfilePerformance.ps1` 获取 `initialize-environment` 内部各子步骤的精确耗时：

```powershell
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1
```

输出示例：
```
=== Initialize-Environment 分步计时 ===
  prerequisites (phases 1-3)             190ms
  1-env-root                               0ms
  2-proxy-detect                          34ms
  3-env-ps1                                1ms
  4-utf8-encoding                          4ms
  5-get-command                           68ms
  6-starship                             120ms
  7-zoxide                                47ms
  8-sccache                                0ms
  9-fnm                                    0ms
  10-alias-profile                        45ms
  TOTAL                                  509ms
```

可选参数：`-SkipStarship`, `-SkipZoxide`, `-SkipProxy`, `-SkipAliases`（用于隔离排查）。

### 缓存管理

工具初始化缓存位于 `profile/.cache/`，按平台隔离：

```
.cache/
├── starship-init-powershell-win.ps1      # Windows starship 缓存
├── starship-init-powershell-linux.ps1    # Linux starship 缓存
├── zoxide-init-powershell-win.ps1        # Windows zoxide 缓存
└── zoxide-init-powershell-linux.ps1      # Linux zoxide 缓存
```

缓存有效期 7 天，自动过期重新生成。手动清除：

```powershell
# 清除所有缓存（下次启动自动重建）
Remove-Item ./profile/.cache/*.ps1

# 清除特定平台
Remove-Item ./profile/.cache/*-win.ps1
```

## 如何添加新内容

### ⚠️ 性能原则

Profile 直接影响每次终端启动速度。**任何修改前请先理解以下分类**：

```
同步路径（阻塞启动）          OnIdle 路径（不阻塞启动）
─────────────────────         ──────────────────────────
encoding.ps1                  loadModule.ps1 OnIdle Action
mode.ps1                      wrapper.ps1
loaders.ps1
features/environment.ps1
```

**核心规则**：如果你添加的内容在启动后 2-3 秒内不需要立即可用，就应该放在 OnIdle 路径中。

### 添加别名

在 `config/aliases/user_aliases.ps1` 中添加配置对象：

```powershell
# 简单别名（命令 → 命令映射）
[PSCustomObject]@{
    cliName     = 'bat'            # 依赖的 CLI 工具名（用于检测是否安装）
    aliasName   = 'cat'            # 别名名称
    aliasValue  = 'bat'            # 目标命令
    description = 'bat 是 cat 的增强版。'
}

# 带参数的函数别名
[PSCustomObject]@{
    cliName     = 'eza'
    aliasName   = 'll'
    aliasValue  = ''               # 留空，使用 command + commandArgs
    description = '详细文件列表'
    command     = 'eza'            # 实际命令
    commandArgs = @('--long', '--header', '--icons')  # 默认参数
}
```

**性能影响**: 极小（~5ms/个别名）。每个别名通过 `Set-CustomAlias` 或 `New-Item Function:` 注册，总量控制在 15 个以内即可。

### 添加工具初始化

在 `features/environment.ps1` 的 `$tools` 哈希表中添加：

```powershell
$tools = @{
    # 已有工具...

    newtool = {
        if ($SkipTools) { return }
        Write-Verbose "初始化 NewTool"
        # 你的初始化代码
    }
}
```

同时将工具名添加到 `$toolNames` 数组中进行批量检测。

**⚠️ 性能检查清单**:

| 操作 | 影响 | 建议 |
|------|------|------|
| `& newtool init` (启动外部进程) | **高** (~50-200ms) | 用 `Invoke-WithFileCache` 缓存输出 |
| `Set-PSReadLineOption/KeyHandler` | **高** (~200ms 首次) | 移到 OnIdle |
| `Import-Module` | **中** (~30-100ms) | 仅导入到 OnIdle，或加到核心模块列表 |
| `Set-Alias` / `New-Item Function:` | **低** (~5ms) | 可直接添加 |
| 环境变量赋值 | **极低** (<1ms) | 可直接添加 |

### 添加 OnIdle 延迟任务

在 `core/loadModule.ps1` 的 OnIdle Action 脚本块中添加：

```powershell
Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
    # 已有任务...

    try {
        # 你的延迟初始化代码
    }
    catch {
        Write-Warning "[profile/loadModule.ps1] OnIdle 你的任务 失败: $($_.Exception.Message)"
    }
}.GetNewClosure() | Out-Null
```

**注意**:
- 使用 `.GetNewClosure()` 捕获闭包变量（PowerShell 7.5 OnIdle `-MessageData` 有 bug）
- 失败必须用 `try/catch` + `Write-Warning`，不得影响终端
- OnIdle 仅触发一次（`-MaxTriggerCount 1`）

### 添加核心 psutils 子模块到同步路径

如果你的代码在启动期间（Initialize-Environment 执行时）被调用，需要的 psutils 函数必须在核心模块中。

当前核心模块（`core/loadModule.ps1` 第 1 层同步加载）：
- `os.psm1` → `Get-OperatingSystem`, `Test-Administrator`
- `cache.psm1` → `Invoke-WithCache`, `Invoke-WithFileCache`
- `test.psm1` → `Test-EXEProgram`
- `env.psm1` → `Sync-PathFromBash`, `Add-EnvPath`
- `proxy.psm1` → `Set-Proxy`
- `wrapper.psm1` → `Set-CustomAlias`, `Get-CustomAlias`

**⚠️ 禁止在同步路径中调用非核心模块函数**（如 `Get-Tree`、`Register-FzfHistorySmartKeyBinding`），否则会触发 PSModulePath 自动导入 psutils 全量模块（~600ms 回退）。延迟加载防护栏会在 `POWERSHELL_PROFILE_TIMING=1` 时检测并警告。

### 修改验证流程

**每次修改后必须验证**：

```powershell
# 1. 快速检查：总耗时是否回退
$env:POWERSHELL_PROFILE_TIMING='1'; pwsh -NoLogo -c 'exit'

# 2. 详细检查：哪个步骤变慢了
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1

# 3. 防护栏检查：延迟加载是否被破坏
# 如果看到 "[性能守卫]" 警告，说明同步路径中引用了非核心模块函数

# 4. 运行测试
pnpm qa
```

**性能基线**（2026-02 实测参考值）：

| 平台 | 总耗时 | initialize-environment |
|------|--------|----------------------|
| Windows | ~1150ms | ~600ms |
| Linux | ~1100ms | ~850ms（含 PATH 同步 + fnm） |

如果总耗时超过基线 200ms 以上，使用 `Debug-ProfilePerformance.ps1` 定位具体步骤。
