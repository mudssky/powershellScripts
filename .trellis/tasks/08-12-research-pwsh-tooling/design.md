# 技术设计

## 1. 边界与顺序

本任务包含两个可独立回滚、按顺序执行的改动面：

1. 模块安装边界从 PowerShellGet v2 收敛到 PSResourceGet。
2. Pester 从 6.0.1 升级到 6.1.0，并验证原生并行 coverage。

先完成安装边界迁移，使 Pester 6.1.0 的安装入口本身使用新事实来源；再执行 Pester 升级与性能门禁。

## 2. PSResourceGet 迁移设计

### 2.1 统一边界

`psutils/modules/install.psm1` 的 `Invoke-InstallModuleCommand` 继续作为通用安装包装函数，不向调用方暴露具体包管理器命令。函数内部改用 `Install-PSResource`，并保持：

- `Scope CurrentUser`
- terminating error
- 安装后由 `Import-InstalledModule` 显式导入
- `Install-RequiredModule` 的逐项状态、失败后继续和 `ShouldProcess`

`profile/installer/installModules.ps1` 继续只声明平台模块集合，不直接调用 PSResourceGet。

### 2.2 精确版本接口

扩展通用包装边界以接受可选精确版本，但不把任意版本范围暴露给现有 Profile 调用方：

```text
Invoke-InstallModuleCommand -ModuleName <name> [-Version <exact-semver>] [-Scope CurrentUser|AllUsers] [-Reinstall]
```

- 未指定版本：安装最新稳定版。
- 指定版本：传给 `Install-PSResource -Version`，调用方负责固定值。
- `-Reinstall` 仅在调用方明确请求覆盖同版本时传递。
- 默认不传 `-TrustRepository`、`-AcceptLicense` 或跳过签名检查；仓库不以迁移为由降低供应链校验。

`Install-RequiredModule` 首期保持 `string[] ModuleNames` 公共签名，避免把 Profile 模块清单迁移扩大为新的依赖锁文件设计。Pester 精确版本继续由专用安装脚本读取 `.pester-version`。

### 2.3 Pester 专用安装入口

`scripts/pwsh/devops/Install-Pester.ps1` 直接使用：

```powershell
Install-PSResource -Name Pester -Version $pesterVersion -Scope $Scope -Reinstall
```

但已存在精确版本时继续幂等返回，不执行重装。这里不复用 `psutils`，因为 Dockerfile 只复制该安装脚本与 `.pester-version`，保持独立 bootstrap 能力比跨目录复制整个模块更深、更稳定。

### 2.4 其他活动直调入口

活动代码中的其他 `Install-Module` 调用一并清理，避免第二事实来源：

- `scripts/pwsh/misc/install.ps1`：Pester 安装改为调用规范 `Install-Pester.ps1`，不再安装浮动 latest。
- `scripts/pwsh/misc/pslint.ps1`：`-Install` 改用 `Install-PSResource PSScriptAnalyzer`；不改变 lint 行为。
- `psutils/modules/functions.psm1` 的 `Start-PSReadline`：改为复用 `Install-RequiredModule` 或 PSResourceGet 包装边界，不保留直接安装。

若搜索发现其他活动 `Install-Module`，按同一原则迁移；归档目录、历史任务和文档示例不作为生产调用修改目标，除非它们描述当前活动入口。

### 2.5 测试合同

测试观察行为而非源码字符串：

- `Invoke-InstallModuleCommand` 向 `Install-PSResource` 传递模块名、Scope、可选精确版本和 Reinstall。
- 未指定版本不传空 `Version`。
- `Install-RequiredModule -WhatIf` 不调用安装命令。
- 安装成功后显式导入；失败后继续下一模块。
- Pester 安装脚本读取 `.pester-version`，已安装精确版本时不安装，缺失时传精确 6.1.0。

## 3. Pester 6.1.0 升级设计

### 3.1 版本单一事实来源

`.pester-version` 从 `6.0.1` 改为 `6.1.0`。以下入口继续读取它：

- `scripts/pwsh/devops/Install-Pester.ps1`
- `scripts/pwsh/devops/Invoke-PesterMode.ps1`
- `Dockerfile.pester`
- `.github/workflows/test.yml`
- `scripts/pester-duration-report.mjs`

Pester 5.7.1 仅作为显式回退版本保留，不成为默认值。

### 3.2 配置能力探测

删除 `PesterConfiguration.ps1` 中基于 6.0.1 的“coverage + parallel 必须拒绝”规则，改为能力驱动：

- 请求 parallel 时，目标 Pester 必须存在 `Run.Parallel`。
- coverage + parallel 时，目标版本必须至少为 6.1.0，且配置对象支持该组合；旧版本请求仍明确失败，不能静默串行。
- `ParallelThrottleLimit` 继续校验 0..128。

测试不得只读取当前机器最高版本；必须在 runner 已显式导入目标 Pester 后创建配置。

### 3.3 可观察入口

保留现有入口并新增明确的并行 coverage 候选入口：

```text
test:pwsh:full                 -> 验收前仍指向串行 coverage
test:pwsh:full:serial          -> Pester 6.1.0 串行 coverage
test:pwsh:full:pester5         -> Pester 5.7.1 串行 coverage 回退
test:pwsh:full:parallel:poc    -> Pester 6.1.0 assertions 并行
test:pwsh:coverage:parallel:poc -> Pester 6.1.0 coverage 并行，默认 throttle 2
```

只有并行 coverage 门禁全部通过，才把 `test:pwsh:full` 切到选定 throttle；`test:pwsh:full:serial` 永久保留为诊断与回滚入口。

### 3.4 兼容性门禁

升级分两步：

#### 串行兼容

对 6.1.0 运行配置窄测、runner 窄测、QA、full assertions 和 full coverage，检查：

- discovery/test 数量
- 失败集合和既有失败归属
- Skip/NotRun
- NUnit suite/test-case 字段
- JaCoCo instruction/line covered、missed 和百分比
- Mock、InModuleScope、TestDrive 生命周期
- 环境变量、模块和子进程清理

#### 原生并行 coverage

对 throttle 自动值 0、2、4 分别采样。每档：

- 使用唯一 NUnit、coverage 和 duration JSON 路径；coverage 路径需增加可覆盖环境变量或 runner 参数，不能共享默认 `coverage.xml`。
- 先做一次正确性试跑，再做连续三轮正式性能样本。
- 采样期间不得运行其他 Pester/QA。
- 记录 PowerShell/Pester 版本、CPU、Discovery、Run、coverage 阶段和 Top 文件。

### 3.5 等价与提升门禁

候选并行路径必须同时满足：

- 与同 commit 串行 6.1.0 的 discovered/run/test-case 集合一致；`#pester:no-parallel` 产生的执行顺序差异允许，但不能漏跑。
- 新增失败为 0；既有失败集合一致。
- JaCoCo instruction 与 line 总数一致；covered/missed 差异必须为 0。若 Pester 自身存在确定性顺序差异，必须先形成最小复现和测试锁定，不能只接受百分比接近。
- coverage 不低于 50%。
- 三轮中位数 `<=240s`，最慢值 `<=270s`。
- 连续运行后没有残留测试进程、fixture 子进程或被污染的进程环境。

若多个 throttle 都通过，选择中位数最低且最慢值稳定的档位；性能接近时选择更保守的较低并发。

### 3.6 外层分片任务处理

`.trellis/tasks/08-12-design-pwsh-coverage-sharding` 不立即删除：

- 原生并行 coverage 通过全部门禁：将其标记为被 Pester 6.1.0 原生能力替代，并记录实测依据。
- 原生方案正确但性能未达标，或存在不可接受的隔离/报告问题：继续该任务，复用本任务产出的串行/并行 artifacts 作为基线。

## 4. 风险与回滚

- PSResourceGet 参数并非一一对应：通过包装函数测试锁定语义，不保留 `Install-Module` fallback 双轨。
- `Install-PSResource` 不自动导入：保留显式导入合同。
- Pester 6.1.0 并行仍属实验能力：默认入口提升必须晚于完整三轮门禁。
- 新版本 coverage tracer 可能改变计数：以同版本串行/并行等价为主，同时保留与 6.0.1 历史差异说明。
- 回滚只需把默认入口恢复串行并将 `.pester-version` 恢复 6.0.1；5.7.1 回退入口始终可用。
