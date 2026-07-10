# Profile 系统

PowerShell 7+ 跨平台 profile 系统，支持 Windows/Linux/macOS。提供模块化加载、工具初始化、别名管理和性能优化。

## 目录结构

```text
profile/
├── profile.ps1              # 主入口（Windows & Linux/macOS 共用）
├── profile_unix.ps1         # Unix 入口（向后兼容 shim，转发到 profile.ps1）
├── core/                    # 核心加载层
│   ├── encoding.ps1         # UTF-8 编码设置
│   ├── bootstrap.ps1        # 最小环境与仓库 PATH 初始化
│   ├── mode.ps1             # 模式判定（Full/Minimal/UltraMinimal）
│   ├── platform.ps1         # 平台能力上下文
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

```text
profile.ps1
    │
    ├── bootstrap-definitions
    │   encoding + bootstrap + mode + platform
    │
    ├── mode-and-platform-decision
    │   判定 Full / Minimal / UltraMinimal 与平台能力
    │
    ├── public-api-definitions
    │   定义 Help、Install 与 UltraMinimal 轻量初始化入口
    │
    ├── UltraMinimal
    │   └── UTF-8 + POWERSHELL_SCRIPTS_ROOT + 仓库 bin PATH
    │
    └── Full / Minimal
        ├── runtime-definitions
        ├── core-loaders
        │   ├── Windows 同步加载 5 个核心模块
        │   ├── macOS/Linux 同步加载 6 个核心模块
        │   ├── 仅 Full 加载用户别名配置
        │   └── 幂等注册 OnIdle
        └── initialize-environment
            ├── Minimal 在公共环境初始化后返回
            └── Full 执行工具探测、初始化与别名注册
```

### OnIdle 延迟加载

以下操作在用户首次空闲时执行，不阻塞启动：

- `Import-Module psutils.psd1 -Force` — 全量加载 psutils（70+ 函数）
- `wrapper.ps1` — yaz, Add-CondaEnv 等包装函数
- `Register-FzfHistorySmartKeyBinding` — fzf 历史搜索键绑定
- `Set-PSReadLineKeyHandler -Key Tab` — Tab 补全模式设置

Profile 使用会话级注册状态保证幂等；同一会话重复加载 Profile 不会创建第二个相同 OnIdle 任务。

## 模式

| 模式 | 触发方式 | 加载内容 |
|------|----------|----------|
| **Full** | 默认 | 全部加载 |
| **Minimal** | `POWERSHELL_PROFILE_MODE=minimal` | 核心模块立即可用；跳过工具探测、初始化、安装提示和别名 |
| **UltraMinimal** | `POWERSHELL_PROFILE_MODE=ultra` 或 Codex 环境自动降级 | UTF-8 + 仓库路径；保留 Help/Install/Initialize 公共函数，不加载 psutils |

## 性能诊断

### 快速查看阶段耗时

```powershell
# 设置环境变量启用计时报告
$env:POWERSHELL_PROFILE_TIMING='1'
pwsh -NoLogo
```

输出示例：

```text
=== Profile 加载计时 ===
  bootstrap-definitions             148ms
  mode-and-platform-decision         15ms
  public-api-definitions              1ms
  runtime-definitions                 2ms
  core-loaders                       40ms
  initialize-environment            160ms
  total                             366ms
```

### 详细分步诊断

使用 `Debug-ProfilePerformance.ps1` 启动多个全新的 `pwsh -NoProfile` 子进程，并执行真实 `profile.ps1` 调用链：

```powershell
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode Full -Iterations 5
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode Minimal -Iterations 5
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode UltraMinimal -Iterations 5
```

输出示例：

```text
=== Profile 真实入口性能诊断 ===
Platform: macos | PowerShell: 7.5.4 | Mode: Full | Samples: 5
Profile internal  avg=...ms median=...ms min=...ms max=...ms
Process elapsed   avg=...ms median=...ms min=...ms max=...ms

=== 阶段中位数 ===
  bootstrap-definitions                  ...ms
  mode-and-platform-decision             ...ms
  public-api-definitions                 ...ms
  runtime-definitions                    ...ms
  core-loaders                           ...ms
  initialize-environment                 ...ms
```

可选参数：

- `-Mode Full|Minimal|UltraMinimal` — 指定模式
- `-Iterations <N>` — 指定新进程样本数
- `-SkipStarship`, `-SkipZoxide`, `-SkipProxy`, `-SkipAliases` — 透传给真实 Profile 入口
- `-Phase <N>` — 人类可读输出只显示指定阶段
- `-AsJson`, `-OutputPath <path>` — 输出稳定 JSON 报告

报告同时区分 Profile 内部耗时与完整子进程耗时，不应把两种口径混为同一个启动数字。

### 缓存管理

工具初始化缓存位于 `profile/.cache/`，按平台隔离：

```text
.cache/
├── starship-init-powershell-win-v2.ps1   # Windows starship 缓存
├── starship-init-powershell-macos-v2.ps1 # macOS starship 缓存
├── starship-init-powershell-linux-v2.ps1 # Linux starship 缓存
├── zoxide-init-powershell-win.ps1        # Windows zoxide 缓存
├── zoxide-init-powershell-macos.ps1      # macOS zoxide 缓存
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

```text
同步路径（阻塞启动）          OnIdle 路径（不阻塞启动）
─────────────────────         ──────────────────────────
encoding.ps1                  loadModule.ps1 OnIdle Action
bootstrap.ps1                 wrapper.ps1
mode.ps1                      fzf / PSReadLine 键绑定
platform.ps1
help.ps1 / install.ps1（仅定义）
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

在 `Register-ProfileOnIdle` 创建的 Action 脚本块中增加独立的 `try/catch`：

```powershell
try {
    # 你的延迟初始化代码
}
catch {
    Write-Warning "[profile/core/loadModule.ps1] OnIdle 你的任务失败: $($_.Exception.Message)"
}
```

**注意**:

- 路径通过 `[scriptblock]::Create()` 内联为稳定字面量，不使用 `.GetNewClosure()` 或 `-MessageData`
- 失败必须用 `try/catch` + `Write-Warning`，不得影响终端
- OnIdle 仅触发一次（`-MaxTriggerCount 1`）
- 不绕过 `Register-ProfileOnIdle` 的会话级幂等状态

### 添加核心 psutils 子模块到同步路径

如果你的代码在启动期间（Initialize-Environment 执行时）被调用，需要的 psutils 函数必须在核心模块中。

当前核心模块（`core/loadModule.ps1` 第 1 层同步加载，按平台条件化）：

**全平台：**

- `os.psm1` → `Get-OperatingSystem`, `Test-Administrator`
- `cache.psm1` → `Invoke-WithCache`, `Invoke-WithFileCache`
- `commandDiscovery.psm1` → `Find-ExecutableCommand`
- `proxy.psm1` → `Set-Proxy`
- `wrapper.psm1` → `Set-CustomAlias`, `Get-CustomAlias`

**仅 Linux/macOS 额外加载：**

- `env.psm1` → `Sync-PathFromBash`, `Add-EnvPath`

**已移出同步路径（通过 OnIdle 全量加载覆盖）：**

- `test.psm1` — `Test-EXEProgram` 已被 `Find-ExecutableCommand` 替代

**⚠️ 禁止在同步路径中调用非核心模块函数**（如 `Get-Tree`、`Register-FzfHistorySmartKeyBinding`），否则会触发 PSModulePath 自动导入 psutils 全量模块（~600ms 回退）。延迟加载防护栏会在 `POWERSHELL_PROFILE_TIMING=1` 时检测并警告。

### 修改验证流程

**每次修改后必须验证**：

```powershell
# 1. 快速检查：总耗时是否回退
$env:POWERSHELL_PROFILE_TIMING='1'; pwsh -NoLogo -c 'exit'

# 2. 真实入口多样本检查
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode Full -Iterations 5
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode Minimal -Iterations 5
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode UltraMinimal -Iterations 5

# 3. 防护栏检查：延迟加载是否被破坏
# 如果看到 "[性能守卫]" 警告，说明同步路径中引用了非核心模块函数

# 4. 运行测试与质量检查
pnpm qa
pnpm test:pwsh:all
```

**历史性能基线**（2026-02，仅作旧机器参考）：

| 平台 | 总耗时 | initialize-environment |
|------|--------|----------------------|
| Windows | ~750ms | ~350ms |
| Linux | ~550ms | ~200ms |

**2026-07-11 macOS / PowerShell 7.5.4 实测**（每种模式 5 个新进程交替采样）：

| 模式 | Profile internal 中位数 | Process elapsed 中位数 |
|------|-------------------------|------------------------|
| Full | 417ms | 688ms |
| Minimal | 236ms | 503ms |
| UltraMinimal | 189ms | 452ms |

相对同机改动前内部中位数（Full 411ms、Minimal 290ms、UltraMinimal 200ms），Full 无显著回归，Minimal 降低约 18.6%，UltraMinimal 降低约 5.5%。

性能比较应在同一机器、同一缓存状态下按模式交替采样，优先比较中位数，并同时报告平均值、最小值和最大值。
