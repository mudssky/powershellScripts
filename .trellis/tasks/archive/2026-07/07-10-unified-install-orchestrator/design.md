# 统一安装编排器技术设计

## 目标与边界

根 `install.ps1` 同时承担两个兼容入口和一个新增 Stage 1 入口：

```text
无参数                  -> 原仓库工具准备流程
-installApp             -> 原平台应用安装流程 + 弃用提示
-Preset Core|Full       -> 新 Stage 1 编排器
```

Stage 0 由平台原生入口拥有，先获得 Git、平台包管理器和 PowerShell 7。PowerShell 7 可用后才调用根 Stage 1，从 `03 sources` 开始。根编排器不复制平台安装命令，也不临时映射旧编号脚本。

## 总体架构

```text
install.ps1
  -> 兼容参数判定
     -> legacy repo-tools（保留现有主体原位）
     -> legacy installApp
     -> InstallOrchestrator.psm1
          -> 读取/验证 config/install/steps.psd1
          -> 解析 platform + preset + step filters
          -> 建立有序执行计划
          -> 逐步启动隔离子进程
          -> 传播 Failed/Blocked
          -> Auto source finally restore
          -> Text 或单文档 JSON 汇总
```

新增编排分支保持薄：参数声明、模式判定、模块加载、输出与最终 `exit`。现有 legacy 主体保留原位，避免无收益的机械搬迁；步骤图、验证、执行和结果格式全部位于模块中，便于 Pester 直接测试。

## 文件边界

- `install.ps1`
  - 保留公开入口与 legacy 参数。
  - 新增 Preset、步骤选择、网络模式、输出和交互参数。
  - 不保存平台路径或步骤依赖。
- `config/install/steps.psd1`
  - Stage 1 步骤、编号、Preset、依赖和各平台入口的唯一注册表。
  - 只含 PowerShell data literal，不含脚本块或副作用。
- `scripts/pwsh/install/InstallOrchestrator.psm1`
  - 注册表验证、选择、执行、状态传播、source cleanup 与汇总。
- `tests/InstallOrchestrator.Tests.ps1`
  - 模块级步骤模型、过滤、失败传播、source 生命周期与 JSON 合同测试。
- `tests/Install.Tests.ps1`
  - 根 CLI 子进程回归：无参数、legacy installApp、参数错误、ListSteps 和 JSON stdout。
- `scripts/qa.mjs` / `PesterConfiguration.ps1`
  - 确保改动注册表或编排模块时，changed QA 会选中新增测试。
- `docs/INSTALL.md`、`README.md`、`docs/scripts-index.md`
  - 新 CLI、Stage 0/1 边界、兼容和重跑说明。

## Stage 1 注册表

`steps.psd1` 使用 schema version 和有序 Steps 数组。每个步骤包含：

```powershell
@{
    Id        = 'sources'
    Number    = '03'
    Presets   = @('Core', 'Full')
    DependsOn = @()
    Platforms = @{
        macos = @{
            Supported       = $true
            Path            = 'macos/03configureSources.zsh'
            Runner          = 'zsh'
            PreviewArgument = '--dry-run'
        }
        linux = @{
            Supported       = $true
            Path            = 'linux/03configureSources.sh'
            Runner          = 'bash'
            PreviewArgument = '--dry-run'
        }
        windows = @{
            Supported       = $true
            Path            = 'windows/03configureSources.ps1'
            Runner          = 'pwsh'
            PreviewArgument = '-WhatIf'
        }
    }
}
```

注册表固定顺序：

| ID | 编号 | Preset | 主要依赖 |
|---|---:|---|---|
| `sources` | 03 | Core/Full | 无 |
| `shell` | 04 | Core/Full | 无；source 失败时仍可部署本地 shell |
| `core-cli` | 05 | Core/Full | sources |
| `fonts` | 06 | Core/Full | sources |
| `profile-tools` | 07 | Core/Full | core-cli |
| `full-apps` | 08 | Full | sources |
| `platform-automation` | 09 | Full | full-apps |
| `login-items` | 10 | Full | full-apps |
| `desktop-integration` | 11 | Full | full-apps |
| `verify` | 99 | Core/Full | 无硬依赖，叶子验证可用子集 |

注册表校验拒绝重复 ID/编号、未知依赖、循环依赖、无效 Preset、未知 Runner、Supported 但缺少 Path，以及不稳定的步骤顺序。

## CLI 合同

```powershell
./install.ps1
./install.ps1 -installApp
./install.ps1 -ListSteps [-OutputFormat Text|Json]
./install.ps1 -Preset Core|Full `
  [-Step <id[]> | -FromStep <id>] `
  [-SkipStep <id[]>] `
  [-NetworkMode Direct|China|Auto] `
  [-OutputFormat Text|Json] `
  [-Unattended | -NonInteractive] `
  [-WhatIf]
```

验证规则：

- 无新参数时进入 legacy repo-tools。
- `-installApp` 不能和 Preset/步骤参数组合。
- Step、FromStep、SkipStep、NetworkMode 的执行用法必须有 Preset；ListSteps 除外。
- Step 与 FromStep 互斥。
- Step/FromStep/SkipStep 中的 ID 必须存在且属于所选 Preset。
- Unattended 与 NonInteractive 互斥。

## 选择算法

1. 根据 Preset 获取初始步骤集合。
2. `-Step` 存在时只保留显式 ID，不展开依赖。
3. `-FromStep` 存在时保留该步骤及其后的 Preset 步骤。
4. 应用 `-SkipStep`。
5. 保持注册表编号顺序，不按用户参数顺序执行。
6. 生成每步的依赖状态说明；精准 Step 标记 `DependenciesVerifiedInRun=false`。

## 执行模型

所有步骤串行执行。每一步执行前：

1. 平台声明不支持 -> `Skipped`。
2. 入口声明支持但文件不存在 -> `Blocked`。
3. 依赖结果为 Failed/Blocked/Skipped -> `Blocked`，但精准 `-Step` 不自动验证未选依赖。
4. 否则启动叶子子进程并计时。

叶子使用 `System.Diagnostics.ProcessStartInfo.ArgumentList` 构建参数数组：

- `pwsh` -> `pwsh -NoProfile -File <path> ...`
- `zsh` / `bash` -> `<runner> <path> ...`

stdout/stderr 使用异步读取完整捕获，避免管道缓冲导致死锁，并防止 JSON 模式被污染。Text 模式在步骤结束后按 stdout/stderr 语义转发；JSON 模式只把诊断转发到 stderr，稳定 document 不默认嵌入原始日志。结果对象仅保存经过长度限制与脱敏的错误摘要。不得使用 `Invoke-Expression` 或拼接 shell command line。

状态映射：

- exit 0 -> `Succeeded` 或 `Preview`
- exit 1 -> `Failed`
- exit 2 -> `Failed`，并保留 `InvalidArguments` message
- exit 10 -> `Blocked`
- 启动失败/未知退出码 -> `Failed`

独立步骤继续执行；依赖步骤阻断；verify 无硬依赖并尽可能运行。

## 参数透传

- sources：NetworkMode、transaction ID、OutputFormat Json、WhatIf。
- 所有写步骤：WhatIf 转为叶子 PreviewArgument。
- Unattended/NonInteractive：按注册表声明的叶子参数名透传。
- Preset：需要平台叶子选择应用或验证范围时透传 Core/Full。

平台叶子的详细参数合同由平台任务实现；注册表只记录参数名，不内嵌业务命令。

## Source 生命周期

编排器为每次运行生成 run ID，并派生合法的 source transaction ID。

- Direct：不创建事务。
- China：保留 active transaction；汇总写入 transaction ID 和 Restore 命令。
- Auto：在 `try/finally` 中执行；只要获得 transaction ID，就在 finally 调用共享 Restore。Restore 失败将 run 状态提升为 Blocked，且不能覆盖原始 Failed 根因。

source 步骤使用 JSON 子输出并解析 transaction、status、rollback。任何解析失败均视为 Failed，不能从展示文本猜测状态。

## 输出合同

顶层 JSON：

```text
SchemaVersion, RunId, Platform, Preset, NetworkMode, Preview,
Status, ExitCode, StartedAt, FinishedAt, DurationMs,
Results[], SourceTransactionId, Rollback
```

步骤 JSON：

```text
Id, Number, Status, ExitCode, DurationMs, Message,
DependsOn[], DependenciesVerifiedInRun, Command,
RerunCommand
```

整体状态优先级：Failed > Blocked > Succeeded。只含 Preview/Skipped/Succeeded 时退出 0；参数校验在 run document 创建前失败时退出 2，并在 JSON 请求下仍返回结构化错误 document。

## 兼容迁移

- 无参数路径保留现有主体、输出和副作用顺序；新编排分支在 legacy 主逻辑前完成显式分流。
- `-installApp` 保留原路径并输出弃用提示，不调用新 Full。
- 现有 pnpm scripts 暂不改为 Preset，以免日常开发命令触发装机。
- 平台任务落地真实叶子后只更新注册表目标文件，不修改步骤引擎。

## 测试策略

- 模块测试使用临时注册表和 fixture 叶子，不访问网络、不安装软件、不写真实 HOME。
- fixture 覆盖 pwsh、bash/zsh runner、stdout/stderr、退出 0/1/2/10、缺失文件和不支持平台。
- Pester Mock 覆盖 Auto Restore 的成功、source 失败、后续异常与 Restore 失败。
- 子进程测试验证根 JSON stdout 单文档、legacy 无参数和非法参数退出码。
- 三个平台通过 registry platform override 在测试中解析，不依赖测试主机平台。

## 回滚与分阶段接入

- 新编排分支仅在显式 Preset 时触发；出现问题可删除 Preset 分支而不影响无参数和 installApp。
- 首期真实 Core 因叶子缺失返回 Blocked 是预期行为，不增加旧路径映射。
- macOS 任务首先接入真实路径并更新 Stage 0：`00 -> 01 -> 02 -> root Stage 1 from 03`；Linux/WSL、Windows 后续复用同一合同。
