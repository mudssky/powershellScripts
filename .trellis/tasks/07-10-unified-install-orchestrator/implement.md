# 统一安装编排器实施计划

## 实施边界

本任务实现根 Stage 1 步骤引擎、注册表、兼容入口、source 生命周期、结构化输出和确定性测试。平台新编号叶子的业务实现不在本任务；真实入口缺失时必须返回 Blocked。

## 有序清单

### 1. 同步最终合同

- [x] 更新 macOS 设计的交接点为 `00/01/02 -> root Stage 1 from 03`，删除“平台先执行 03”的冲突描述。
- [x] 在统一编排规范中记录步骤 ID、状态、退出码、JSON 和 source cleanup 合同。
- [x] 用 `rg` 确认没有其他活动任务继续声明根 Stage 1 从 04 开始。

### 2. 先固定兼容与参数失败测试

- [x] 扩展 `tests/Install.Tests.ps1`，固定无参数调用的 Manage-Bin/Bash 行为与退出码。
- [x] 为 `-installApp` 增加兼容路径和弃用提示测试，使用 fixture 避免真实安装。
- [x] 增加根 CLI 参数组合测试：Preset、ListSteps、Step、FromStep、SkipStep、Unattended/NonInteractive。
- [x] 增加 `-OutputFormat Json` 单文档 stdout 和参数错误退出 2 测试。

### 3. 建立注册表与纯选择逻辑

- [x] 新增 `config/install/steps.psd1`，声明 schema、03～11/99、Preset、依赖和三平台未来路径。
- [x] 新增 `InstallOrchestrator.psm1` 的注册表读取与校验函数。
- [x] 实现平台规范化、Core/Full 选择、Step 精确选择、FromStep、SkipStep 和稳定排序。
- [x] 增加重复 ID/编号、未知依赖、循环依赖、无效 runner、缺失 platform path 测试。

### 4. 实现步骤执行与状态传播

- [x] 使用 `ProcessStartInfo.ArgumentList` 实现 pwsh/zsh/bash 安全调用与 stdout/stderr 异步捕获，避免管道死锁。
- [x] 实现 Supported=false -> Skipped、缺失入口 -> Blocked、退出码状态映射和耗时记录。
- [x] 实现依赖阻断、独立步骤继续、verify 无硬依赖和整体退出码优先级。
- [x] 实现 WhatIf、Unattended、NonInteractive、Preset 与 NetworkMode 参数透传。
- [x] 用临时 fixture 叶子覆盖三平台、0/1/2/10、异常启动、日志捕获、摘要脱敏和精准 Step 依赖提示。

### 5. 接入 source transaction 生命周期

- [x] 为 run 生成稳定且合法的 source transaction ID。
- [x] 解析 sources JSON 子输出并记录 transaction、status 与 rollback。
- [x] Direct 不创建事务；China 保持 active 并输出 Restore；Auto 在 finally 中 Restore。
- [x] 测试 Auto 成功、source 失败、后续步骤失败、执行异常和 Restore 失败；cleanup 失败不能覆盖原始根因。

### 6. 扩展根入口并保持 legacy

- [x] 保留现有仓库工具准备主体原位，保持无参数执行顺序与公开行为。
- [x] 根 `install.ps1` 增加新参数和模式判定，新编排分支在 legacy 主逻辑前完成分流且参数错误在副作用前失败。
- [x] `-installApp` 继续调用旧平台路径，输出弃用提示，不映射 Full。
- [x] 保持 `package.json` 的 `pwsh:install` / `scripts:install` 仍走无参数 legacy 行为。

### 7. 输出、文档与 QA 发现

- [x] 实现 Text 汇总、单文档 JSON、失败步骤重跑命令和 source rollback 提示。
- [x] 更新 README、`docs/INSTALL.md` 与 `docs/scripts-index.md`，说明 Stage 0/1、Preset、重跑和兼容行为。
- [x] 新增 `.trellis/spec/infra/install-orchestrator.md` 并更新 infra index。
- [x] 调整 `scripts/qa.mjs` / `PesterConfiguration.ps1`，确保编排器或注册表变更会运行相关测试。

### 8. 验证门禁

- [x] 运行目标测试：`Install.Tests.ps1` 与 `InstallOrchestrator.Tests.ps1`。
- [x] 运行 `pnpm qa` 并修复格式、文档和 changed-test 发现问题。
- [x] 运行 `pnpm test:pwsh:all`，验证 host 与 Linux Docker 全量 Pester。
- [x] 运行 `git diff --check`，确认没有 JSON stdout 调试输出、真实安装副作用或本机状态文件。
- [x] 记录真实 Core 当前因平台叶子缺失而 Blocked；不将其误报为完整装机验证。

## 高风险文件与回滚点

- `install.ps1`：兼容面最大；先固定子进程测试，再做机械迁移。出现回归时保留 legacy 分支，只回滚显式 Preset 路径。
- `config/install/steps.psd1`：是步骤图真源；schema 变更必须同步 validator 和 fixture。
- source Auto cleanup：所有退出路径必须进入 finally；Restore 失败需要独立测试。
- JSON stdout：任何 Write-Host/子进程直通都会破坏自动化合同，必须通过子进程测试校验；稳定 document 不包含未脱敏的原始日志。

## 开始实施前检查

- [x] 用户已审阅并批准 `prd.md`、`design.md` 与本文件。
- [x] 执行 `task.py start 07-10-unified-install-orchestrator`，状态变为 `in_progress`。
- [x] 加载 `trellis-before-dev`，读取 root/pwsh、config loading、package source 与跨层复用规范。
