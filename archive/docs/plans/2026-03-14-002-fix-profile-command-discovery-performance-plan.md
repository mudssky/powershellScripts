---
title: fix: restore profile command discovery performance
type: fix
status: completed
date: 2026-03-14
origin: docs/brainstorms/2026-03-14-profile-command-discovery-brainstorm.md
---

# fix: restore profile command discovery performance

## Overview

修复最近一次 Profile 安装提示聚合改动带来的启动性能回归：在保留聚合提示目标的前提下，用一个更轻量、更可控的可执行命令探测 API 替换同步启动路径中的 `Get-Command -CommandType Application` 探测。该 API 作为 `psutils` 的公共能力公开，但第一阶段只在 Profile 启动路径接入（see brainstorm: `docs/brainstorms/2026-03-14-profile-command-discovery-brainstorm.md`）。

本计划直接承接 brainstorm 已确认的边界：公开 API 采用单一函数入口；默认返回对象 `Name`、`Found`、`Path`；默认只返回首个命中路径；支持单个与批量探测；负结果缓存只能由调用方显式开启，不能成为共享默认语义。

## Problem Statement / Motivation

当前回归由 `profile/features/environment.ps1` 在同步启动阶段扩大命令探测范围引起。最近一次聚合提示改动把 `scoop`、`winget`、`choco`、`brew`、`apt` 一并放进 `Get-Command -Name $trackedCommandNames -CommandType Application` 的批量探测中（`profile/features/environment.ps1:393`, `profile/features/environment.ps1:396`, `profile/features/environment.ps1:400`）。

本地复现已经确认：

- 在受影响 Windows 环境中，缺失的 `choco`、`brew`、`apt` 每个都可能让 `Get-Command` 卡住约 20 秒。
- 同一批量探测在全新 `pwsh -NoProfile` 进程里可达到 60 秒以上，直接把 Profile 启动从约 1 秒级拉高到 50 秒级。
- `where.exe` 对相同缺失命令返回很快，说明瓶颈不是简单的 PATH 遍历，而是 PowerShell 的命令发现回退链路。

同时，Profile 还有一个不能绕开的结构约束：启动同步路径只能依赖核心 psutils 子模块。`profile/README.md:246` 已明确说明，`Initialize-Environment` 执行期间使用的 psutils 函数必须位于核心模块；`profile/core/loadModule.ps1:9` 也记录了 `test.psm1` 已从同步路径移出，当前核心同步模块仅按需加载少量子模块（`profile/core/loadModule.ps1:11`, `profile/core/loadModule.ps1:20`）。因此，这次不能只写一个公共 API 然后在 Profile 中直接调用；计划必须同时解决“高性能探测”和“同步加载可达性”。

## Proposed Solution

### 1. 新增统一的轻量命令探测 API

在 `psutils/modules/` 下新增一个专用模块，提供统一的公开函数，例如 `Find-ExecutableCommand`。该函数接受一个或多个命令名，返回统一对象结构：

- `Name`
- `Found`
- `Path`

当输入多个命令时，返回一组同结构对象；当输入单个命令时，返回单个对象即可。默认仅返回首个命中路径；通过显式参数再返回全部命中项，例如增加 `AllPaths` 或等价字段。

该 API 的职责刻意收窄为“按当前 shell 可执行语义查找外部命令”，不处理函数、别名、模块自动导入，也不试图复刻 `Get-Command` 的完整发现语义。

### 2. 采用轻量实现而非 `Get-Command`

底层实现应直接面向可执行文件探测：

- Windows：按 `PATH + PATHEXT` 顺序查找，覆盖 `.exe`、`.cmd`、`.bat` 等真实可执行命令。
- Linux/macOS：按 PATH 目录顺序查找命令文件，避免为探测本身额外启动 shell 进程。
- 默认保持与当前 `Test-EXEProgram` 相近的保守缓存语义：可缓存命中结果，但不默认缓存未命中结果。
- 提供显式参数让调用方开启“当前会话内缓存负结果”，供 Profile 这种性能敏感路径选择性使用。

实现时需要确保对重复、无效、畸形或不存在的 PATH 条目安全跳过，不因为路径拼接异常而抛错或显著放大耗时。

### 3. 让新 API 进入 Profile 同步路径，但不破坏延迟加载设计

由于 `Initialize-Environment` 位于同步启动阶段，这个新模块不能只存在于 `psutils.psd1` 的延迟全量导入路径中。计划必须显式处理以下内容：

- 将新模块加入 `psutils/psutils.psd1` 的模块清单与导出列表。
- 将新模块纳入 `profile/core/loadModule.ps1` 的核心同步加载集合，保证 Profile 可直接调用。
- 保持该模块足够轻量，不依赖当前未进同步路径的 psutils 子模块，避免因为新增核心模块反向吞掉本次性能收益。
- 更新 `profile/README.md` 中关于核心同步模块的说明，避免文档继续宣称“启动阶段只能靠现有四个核心模块”。

这一步是本计划的关键实现约束，否则会重演同步路径误触发全量模块导入的问题（`tests/DeferredLoading.Tests.ps1`）。

### 4. 用新 API 替换 Profile 当前的命令探测

在 `profile/features/environment.ps1` 中，将当前“工具 + 包管理器”批量探测从 `Get-Command` 改为新 API：

- 继续保留当前聚合安装提示的高层逻辑，包括缺失工具收集、包管理器优先级选择、统一输出提示。
- 将 `availableCommands` / `availableTools` 的构建来源改为新 API 的返回对象。
- 只在 Profile 这类明确受益的调用点显式开启负结果缓存，不把该行为扩散到共享默认语义。
- 保持 `Get-ProfilePreferredPackageManager`、`Get-ProfileMissingToolInstallHint` 等聚合提示辅助函数的职责边界，避免这次修复把安装提示逻辑重新拆散。

### 5. 同步更新诊断与测试

现有性能诊断脚本和文档仍把 Phase 4.06 标记为 `Get-Command` 批量检测（`profile/Debug-ProfilePerformance.ps1`, `profile/README.md:94`, `profile/README.md:282`）。本次计划应一并更新：

- `profile/Debug-ProfilePerformance.ps1` 的探测步骤实现与标签，让诊断输出反映新的命令探测路径。
- `profile/README.md` 中关于 `test.psm1`、同步路径命令探测方式和性能验证流程的说明。
- `psutils` 的单元测试与 Profile 侧测试，覆盖新的 API 契约和本次回归场景。

## SpecFlow Analysis

从用户流和系统流角度，这次修复至少需要覆盖以下场景：

- **Flow 1: Windows 启动且多个包管理器缺失**
  - 用户启动 `pwsh`
  - Profile 进入同步探测阶段
  - 缺失的 `choco`、`brew`、`apt` 不应再把启动拖到几十秒
  - 若仍有缺失工具需要提示，聚合提示照常输出

- **Flow 2: Windows 启动且存在可用包管理器**
  - 用户缺失 `starship` / `zoxide` 等工具
  - 系统能快速识别 `scoop` 或 `winget`
  - 最终仍输出一条聚合安装命令

- **Flow 3: 公共 API 被普通调用者使用**
  - 调用者输入单个命令名
  - 默认获得对象结果，但不会因为默认负结果缓存而影响“同会话刚安装命令”的再探测语义

- **Flow 4: Profile 显式启用更激进的缓存**
  - 只有 Profile 或同类性能敏感调用者显式开启时，未命中结果才会在当前会话内缓存
  - 该策略不应悄悄污染其他 `psutils` 调用点

由此得到的补充要求：

- 计划中必须明确“默认语义”和“Profile 显式策略”的区别，避免实现时偷懒直接把负结果缓存做成全局默认。
- 计划中必须覆盖“同步加载可达性”，否则 API 即便本身很快，也会因模块加载路径不当导致新的回归。

## Technical Considerations

- 性能优先级高于抽象完整性：这次目标是把启动时间从几十秒压回到回归前量级，API 设计应围绕这个目标收敛。
- 命令发现语义应刻意比 `Get-Command` 更窄：只处理外部可执行命令，避免 PowerShell 的回退搜索、模块自动导入和 `get-*` 推断路径。
- 新模块进入核心同步加载集合后，其依赖必须可审计且足够小，否则会用固定导入成本替代掉当前的动态回归成本。
- `Test-EXEProgram` 在第一阶段不切换到底层新实现，避免一次改动同时重写过多历史调用语义（`psutils/modules/test.psm1:48`, `psutils/modules/test.psm1:69`, `psutils/modules/test.psm1:110`）。
- 新公共 API 需要有清晰命名和帮助说明，让后续调用者知道它适合“可执行文件探测”，而不是拿来替换所有 `Get-Command` 用法。
- 如果需要会话级缓存，缓存 key 需要考虑大小写不敏感平台、PATH 顺序、PATHEXT 及显式参数差异，避免错误复用。

## System-Wide Impact

- **Interaction graph**：`profile/core/loadModule.ps1` 将同步导入一个新的轻量 psutils 子模块；`Initialize-Environment` 改为调用新 API 获取工具/包管理器可用性，再继续现有聚合提示流程。
- **Error propagation**：命令探测失败时必须安全降级，不得阻塞 Profile 启动；最差结果也应退化为“无法生成安装命令，但 shell 继续可用”。
- **State lifecycle risks**：新增的会话级缓存只应存在于新模块内部，并且默认不缓存负结果；不应影响现有 `Clear-EXEProgramCache` 语义。
- **API surface parity**：第一阶段新增公共 API，但不立即替换 `Test-EXEProgram`；公共 API 与历史布尔型 API 并存，职责边界要写清楚。
- **Integration test scenarios**：
  - Windows 缺失 `choco`、`brew`、`apt` 时，冷启动不再出现数十秒阻塞。
  - Windows 存在 `scoop` 或 `winget` 时，缺失工具仍能输出一条正确的聚合安装命令。
  - PATH 中存在重复、无效或畸形条目时，不抛错且结果稳定。
  - 同名命令多个命中时，默认只返回首个路径；显式参数时返回全部命中。
  - 默认未命中不缓存；显式开启后才在当前会话复用负结果。

## Acceptance Criteria

- [x] `psutils` 新增统一的公开可执行命令探测 API，支持单个与批量输入，并默认返回包含 `Name`、`Found`、`Path` 的对象。
- [x] 新 API 默认只返回首个命中路径；显式参数开启时可返回全部命中项。
- [x] Windows 上的新 API 按 `PATH + PATHEXT` 的真实可执行语义工作，能识别 `.exe`、`.cmd`、`.bat` 等命令。
- [x] 新 API 默认不缓存未命中结果；只有调用方显式开启时，才在当前会话内缓存负结果。
- [x] 新模块被纳入 Profile 同步核心加载路径，且不会触发 psutils 全量自动导入回归。
- [x] `profile/features/environment.ps1` 不再用 `Get-Command -CommandType Application` 批量探测工具与包管理器；聚合安装提示行为保持不变。
- [x] `profile/Debug-ProfilePerformance.ps1` 和相关文档能反映新的命令探测路径，而不是继续显示旧的 `Get-Command` 阶段名称。
- [x] 新增或更新测试，覆盖 API 契约、缓存边界、Windows 可执行语义、Profile 集成路径与延迟加载防护。
- [x] 在受影响 Windows 环境上的手工验证中，Profile 启动时间恢复到回归前的大致量级，不再停留在 50 秒级别。
- [x] 根目录 `pnpm qa` 通过。

## Success Metrics

- 受影响环境中，Profile 启动从“几十秒”回到“约 1 秒量级”，至少恢复到回归前同一数量级。
- Phase 4 的命令探测不再成为主导耗时，性能诊断结果能把热点重新压回 `starship`、模块加载等原有主要项。
- 安装提示聚合功能保留，用户仍能在一条高信号提示中看到当前缺失工具和可执行安装命令。
- 新 API 成为后续命令存在性检测的可复用基础能力，但不会在第一阶段强行扩散到全仓库。

## Dependencies & Risks

- 风险：新模块若依赖过多或实现过重，会把动态回归变成固定同步加载成本。
  缓解：要求模块自包含、轻依赖，并以 `Debug-ProfilePerformance.ps1` 验证净收益。

- 风险：手写 PATH 扫描逻辑可能与 PowerShell 真正执行语义出现边缘差异。
  缓解：范围只收敛到“外部可执行命令”，并用 Windows `PATHEXT`、多后缀与多命中测试覆盖关键行为。

- 风险：如果只修改 `environment.ps1` 而忘记同步核心模块清单，Profile 会因调用新 API 而误触发延迟加载回归。
  缓解：将 `profile/core/loadModule.ps1`、`profile/README.md`、必要的防护栏测试一起纳入计划。

- 风险：默认缓存策略若设计不清晰，后续调用者容易误以为新 API 会自动复用未命中结果。
  缓解：在帮助文本、测试和计划中都明确“负结果缓存必须显式开启”。

- 风险：仓库当前没有 `docs/solutions/` 目录可供检索，本次计划缺少可复用的 institutional learnings。
  缓解：基于现有代码、文档和现场性能复现结果制定方案，并把关键约束写进计划避免丢失。

## Sources & References

- **Origin brainstorm:** `docs/brainstorms/2026-03-14-profile-command-discovery-brainstorm.md`
  - 延续的关键决策：公共 API 采用统一函数入口；默认返回 `Name` / `Found` / `Path`；默认不缓存未命中；只有 Profile 显式开启负结果缓存；第一阶段只修复 Profile。
- **Regression entry point:** `profile/features/environment.ps1:393`, `profile/features/environment.ps1:396`, `profile/features/environment.ps1:400`, `profile/features/environment.ps1:512`
- **Profile sync-load constraints:** `profile/core/loadModule.ps1:9`, `profile/core/loadModule.ps1:11`, `profile/core/loadModule.ps1:20`
- **Profile architecture & performance guidance:** `profile/README.md:94`, `profile/README.md:246`, `profile/README.md:282`, `profile/README.md:289`
- **Existing executable detection contract:** `psutils/modules/test.psm1:48`, `psutils/modules/test.psm1:69`, `psutils/modules/test.psm1:110`, `psutils/modules/test.psm1:544`
- **Existing tests & guardrails:** `psutils/tests/test.Tests.ps1`, `tests/DeferredLoading.Tests.ps1`, `tests/ProfileInstallHints.Tests.ps1`, `tests/ProfileMode.Tests.ps1`
- **Institutional learnings search:** 未发现 `docs/solutions/` 目录，本次未检索到可复用的历史方案
- **External research:** 基于强本地上下文和明确回归点，当前计划未额外引入外部资料
