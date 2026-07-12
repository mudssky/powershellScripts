---
title: feat: consolidate profile install hints
type: feat
status: completed
date: 2026-03-14
origin: docs/brainstorms/2026-03-14-environment-install-hint-brainstorm.md
---

# feat: consolidate profile install hints

## Overview

将 `profile/features/environment.ps1` 中按工具分散输出的缺失安装提示重构为一次性聚合输出，减少 Profile 启动噪音，同时保留“只提示、不自动执行”的行为边界。本计划直接承接 brainstorm 中已确认的决策：聚合提示、只包含当前缺失工具、按平台优先级选择包管理器、实现采用轻量元数据表而非直接耦合 `apps-config.json`（see brainstorm: `docs/brainstorms/2026-03-14-environment-install-hint-brainstorm.md`）。

这次改动聚焦提示体验与可维护性，不改变现有工具初始化顺序、缓存策略、懒加载行为，也不引入新的安装脚本执行路径。

## Problem Statement / Motivation

当前 `Initialize-Environment` 在工具缺失时直接在 `switch ($tool.Key)` 中输出多段平台特定文案，导致几个问题：

- 提示分散：同一次 shell 启动可能连续输出多段缺失说明，阅读成本高。
- 维护分散：描述文案、平台分支、安装命令都散落在 `switch` 分支中，新增工具时容易继续扩散。
- 跨平台逻辑不一致：Windows、macOS、Linux 的包管理器选择没有统一入口，Linux 新增 `brew > apt` 优先级后更需要集中处理。
- 用户行动路径不够直接：当前输出是按工具分别提示，无法给出“一次性安装当前缺失工具”的单行命令。

仓库约束也要求这次重构保持保守：Profile 直接影响启动性能，不能为提示逻辑增加同步网络调用，也不能让提示失败影响 shell 启动（`CLAUDE.md:297`, `CLAUDE.md:298`）。

## Proposed Solution

### 1. 抽出轻量提示元数据

在 `profile/features/environment.ps1` 中为运行时“可提示的关键工具”增加一个小型元数据表，至少包含：

- 工具名与展示名
- 简短说明文案
- 当前平台是否应参与提示
- 各支持包管理器对应的包名或安装片段

这个表只服务于 Profile 启动提示，不直接复用 `profile/installer/apps-config.json`，避免把完整安装器配置与启动路径耦合在一起。`apps-config.json` 仍可作为命名参考来源，特别是 `starship`、`zoxide`、`fnm` 在 `scoop` / `brew` 下的现有配置（`profile/installer/apps-config.json:92`, `profile/installer/apps-config.json:158`, `profile/installer/apps-config.json:182`, `profile/installer/apps-config.json:517`, `profile/installer/apps-config.json:646`, `profile/installer/apps-config.json:689`）。

### 2. 将“即时输出”改为“先收集后统一输出”

保留当前工具探测主流程和初始化闭包结构（`profile/features/environment.ps1:192`, `profile/features/environment.ps1:203`），但将缺失工具分支从“立即 `Write-Host`”改为“记录当前缺失且应提示的工具”。循环结束后再统一：

- 拼接缺失工具列表
- 解析当前平台的首选包管理器
- 基于缺失工具生成一条安装命令
- 输出一句聚合提示和一行命令

当前分散提示的 `switch ($tool.Key)` 区域就是本次主要收敛点（`profile/features/environment.ps1:295`）。

### 3. 统一包管理器选择规则

将包管理器选择封装为明确规则：

- Windows：`scoop > winget > choco`
- macOS：`brew`
- Linux：`brew > apt`

只在当前机器检测到对应包管理器时才生成命令。若当前平台没有受支持的包管理器，或者所选包管理器缺少某个工具的映射，则仍输出单句缺失提示，但不输出命令，也不报错。

### 4. 保持手动安装边界

提示只提供用户可复制执行的一行命令，例如：

```powershell
scoop install starship fnm
```

或：

```powershell
brew install starship zoxide fnm
```

Profile 本身不调用安装脚本、不触发包管理器命令，也不自动修复环境。

## Flow & Edge Cases

本次计划按以下用户流覆盖：

1. 无缺失工具：不输出安装提示。
2. 存在一个或多个缺失工具，且有受支持包管理器：输出一条聚合说明 + 一行安装命令。
3. 存在缺失工具，但无受支持包管理器：仅输出一条聚合说明，不输出命令。
4. 用户通过 `-SkipTools`、`-SkipStarship`、`-SkipZoxide` 等显式跳过工具初始化时：这些被跳过的工具不应继续制造额外提示噪音。
5. 当前平台不适用的工具：保持现有平台边界，不因为聚合逻辑而扩大提示范围。

默认假设：

- Linux 的 `apt` 命令采用人工执行场景友好的单行形式，例如 `sudo apt install <packages>`，不依赖额外交互脚本。
- 若首选包管理器只覆盖部分缺失工具，则优先保证“单句缺失说明”可用，再决定是否仅为可映射工具生成命令；实现时应避免同一次启动再次退回到逐项提示。

## Technical Considerations

- 性能：聚合逻辑必须建立在现有批量 `Get-Command` 检测之上，不增加外部进程调用，也不引入同步网络访问。
- 健壮性：提示辅助函数若出现异常，必须安全降级为“安静失败”或仅输出缺失工具名，不能阻塞 `Initialize-Environment` 正常完成。
- 结构：建议引入小型辅助函数，例如“选择包管理器”“格式化聚合命令”“生成缺失提示文案”，避免继续扩张单个 `switch`。
- 可维护性：元数据表应只覆盖当前真正需要提示的工具，先服务现有需求，不一次性抽象成通用安装框架。
- 一致性：生成的一行命令只包含“当前缺失”的工具，不能把已安装工具一并塞入命令。

## System-Wide Impact

- **Interaction graph**：`Initialize-Environment` 在完成工具存在性检查后，新增一段“聚合提示收尾”逻辑；不会改变工具初始化、别名注册和 `z` 懒加载路径。
- **Error propagation**：提示构建失败不得影响后续 `Set-AliasProfile`、`Write-ProfileModeDecisionSummary` 等收尾步骤。
- **State lifecycle risks**：本次变更只影响当前会话控制台输出，不写磁盘、不改缓存、不改环境变量持久层。
- **API surface parity**：`profile/installer/installApp.ps1` 继续承担“完整安装”入口，Profile 运行时提示仅承担“发现缺失并给出手动命令”职责。
- **Integration test scenarios**：
  - Windows 下缺失单工具，且 `scoop` 可用时，输出单命令。
  - Linux 下 `brew` 不可用、`apt` 可用时，回退为 `apt` 命令。
  - 缺失工具存在，但没有任何支持的包管理器时，不应抛错。
  - Skip 标志存在时，不应出现与被跳过工具相关的噪音提示。

## Acceptance Criteria

- [x] `Initialize-Environment` 在同一次启动中最多输出一组聚合安装提示，不再按工具逐项输出编号列表。
- [x] 聚合提示只包含当前实际缺失且在当前平台应提示的工具。
- [x] 安装命令按平台优先级自动选择包管理器：Windows `scoop > winget > choco`，macOS `brew`，Linux `brew > apt`。
- [x] 生成的安装命令只包含当前缺失工具，不包含已安装工具。
- [x] 当没有受支持的包管理器或缺少包映射时，Profile 仍能正常启动，并退化为单句提示而不是报错或逐项刷屏。
- [x] 保持“只提示，不自动执行”；运行时不调用 `installApp.ps1`，不调用包管理器安装命令。
- [x] 添加或更新 Pester 测试，覆盖包管理器优先级、缺失工具聚合、无命令回退、Skip 标志抑制提示等场景。
- [x] 根目录 `pnpm qa` 通过。

## Success Metrics

- 缺失工具场景下，启动输出从多段分散提示收敛为最多两行高信号输出。
- 后续新增提示工具时，只需在元数据表和极少量辅助逻辑中补充信息，而不是继续扩张 `switch` 分支。
- 现有 Profile 加载能力无回归，尤其是启动成功率和基本性能不退化。

## Dependencies & Risks

- 风险：提示元数据与 `apps-config.json` 中的包名可能长期漂移。
  缓解：把元数据表范围控制在少量关键工具，并在注释中标明 `apps-config.json` 为命名参考源。

- 风险：Linux 的 `apt` 映射当前不在现有安装清单中，需要本次自行定义最小支持集。
  缓解：只覆盖当前明确需要的工具，不扩展到所有包管理器。

- 风险：若不处理 Skip 标志，聚合后仍可能在“用户主动禁用工具初始化”的场景下输出不必要噪音。
  缓解：把 Skip 场景纳入 acceptance criteria 和测试。

- 风险：Profile 测试目前更偏模式与性能，新增提示逻辑若无专门测试，后续容易回归。
  缓解：为环境提示逻辑补充专门的单元测试，可选择新增测试文件，或在 `tests/ProfileMode.Tests.ps1` 基础上扩展。

## Sources & References

- **Origin brainstorm:** `docs/brainstorms/2026-03-14-environment-install-hint-brainstorm.md`
  - 延续的关键决策：聚合提示、只提示不执行、命令只覆盖当前缺失工具、按平台选择包管理器、Linux 仅支持 `brew > apt`。
- **Current implementation:** `profile/features/environment.ps1:192`, `profile/features/environment.ps1:203`, `profile/features/environment.ps1:295`, `profile/features/environment.ps1:314`
- **Installer config reference:** `profile/installer/apps-config.json:92`, `profile/installer/apps-config.json:158`, `profile/installer/apps-config.json:182`, `profile/installer/apps-config.json:517`, `profile/installer/apps-config.json:646`, `profile/installer/apps-config.json:689`
- **Repository constraints:** `CLAUDE.md:297`, `CLAUDE.md:298`
- **Existing profile tests:** `tests/ProfileMode.Tests.ps1`, `tests/ProfileInstallHints.Tests.ps1`
