---
title: refactor: consolidate fnos mount manager
type: refactor
status: active
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-fnos-portable-disk-mounting-requirements.md
---

# refactor: consolidate fnos mount manager

## Overview

本计划承接 `docs/brainstorms/2026-04-05-fnos-portable-disk-mounting-requirements.md`，目标是把当前分散在 `linux/fnos/fnos-mount-manager/fstab`、`linux/fnos/remount.sh`、以及机器侧临时 systemd / shell 补救逻辑里的数据盘挂载流程，收敛为一套可复制、可校验、可修复的 FNOS 挂载管理器。

后续补充说明：这份计划已经完成“统一管理器骨架、配置生成、检查、修复”这一层；针对“FNOS 开机后把部分磁盘挂到型号路径、部分磁盘完全未挂”的启动后命名稳定化问题，后续工作已拆分到 `docs/plans/2026-04-05-002-feat-add-fnos-alias-backfill-plan.md`，不再继续堆叠到本计划里。

这次不再把“编辑 `fstab`”和“修复挂载异常”视为两个独立脚本问题，而是统一为一个模块化 shell 工具链：

1. `linux/fnos/` 下维护结构化 shell 配置与模块化源码。
2. `linux/fnos/fnos-mount-manager/build.sh` 生成单文件管理脚本，主产物放在 `bin/fnos-mount-manager`，并在 `linux/fnos/` 下额外保留一份 `.sh` 便携副本。
3. 管理脚本负责 `generate`、`apply`、`check`、`status`、`repair`。
4. 运行时仍然只让 systemd + system fstab 负责实际挂载，不再保留第二套开机重挂载机制。

## Problem Frame

当前 FNOS 外接盘方案的主要问题不是“缺少一个 remount 脚本”，而是配置与运行时边界混乱：

- 仓库里有私有 `linux/fnos/fnos-mount-manager/fstab`，但它本质是机器快照，难以迁移。
- `linux/fnos/remount.sh` 把挂载修复逻辑直接绑在固定 UUID 和固定挂载根目录上，复用面很窄。
- 机器侧曾同时存在 `fstab`、legacy force-remount service、以及 shell 登录时 `mount -a`，导致 systemd 挂载流程被二次打断。
- 现有 Samba 共享已经依赖固定数据盘挂载点，因此新的方案必须保留“固定业务路径”的心智，同时减少启动竞争与手工排障成本。

计划的核心不是把旧脚本“改大”，而是建立一个明确边界：

- 单一真相来源是仓库内的结构化 shell 配置模板与本机私有配置。
- 单一运行时真相来源是 system fstab 中受管理的外接盘区块。
- 管理脚本只负责生成、应用、诊断和修复，不成为常驻调度器。

## Requirements Trace

- R1-R5. 使用 `linux/fnos/` 下的结构化 shell 配置作为单一真相来源，支持 repo 模板、本机私有配置、混合 `LABEL=` / `UUID=`、固定业务挂载点和可配置挂载根目录。
- R6-R9. `linux/fnos/` 采用模块化源码 + `build.sh` 产出单文件管理脚本；管理脚本为唯一推荐入口，并采用显式 `generate` / `apply` 两步流；运行时只依赖 system fstab。
- R10-R12. 默认支持 automount，且允许按盘切换 eager 模式。
- R13-R16. 保持固定挂载点对 Samba / 文件管理访问友好；新脚本内置统一修复与校验能力；移除或隔离重复自动挂载来源；淘汰 `linux/fnos/remount.sh` 的独立入口角色。
- R17-R20. 方案依赖通用 systemd Linux 能力；不引入常驻守护进程；主配置和管理脚本保持纯 shell；构建产物是可分发的单文件脚本。

## Scope Boundaries

- 本次不做自动反向导入 legacy `linux/fnos/fnos-mount-manager/fstab` 到新配置清单的迁移器。
- 本次不试图管理整个 system fstab；只接管外接数据盘区块，保留系统根分区、swap 与其他非受管条目不变。
- 本次不覆盖所有文件系统类型的差异化高级选项；首版优先服务当前 NTFS 外接数据盘场景，同时给后续扩展保留结构。
- 本次不让管理脚本自动改写任意 shell 登录脚本；对这类风险源优先诊断与提示，只有边界明确的 systemd 遗留项才考虑自动修复。
- 本次不引入新的 bash 测试框架；脚本测试沿用现有 Node/Vitest 能力。

## Context & Research

### Relevant Code and Patterns

- `linux/fnos/remount.sh` 是当前唯一的 FNOS 挂载脚本，里面已经暴露出首版修复需求：按磁盘标识定位设备、停止挂载单元、按挂载点重新挂载、输出 `lsblk` 状态。但它把 UUID、挂载点、systemd 交互和激进 `fuser -k -9` 都耦合在一个文件里。
- `linux/fnos/fnos-mount-manager/fstab` 体现了当前磁盘选项基线：`nofail,uid=1000,gid=1000,umask=022,iocharset=utf8,windows_names,big_writes`。这些选项应转成生成器默认值，而不是继续手工复制。
- `linux/ubuntu/apply_config.sh` 展示了仓库内已有的 shell 工具风格：模块化函数、清晰日志、显式命令分支，而不是“一次性脚本里堆逻辑”。
- `.gitignore` 已全局忽略名为 `fstab` 的文件，这允许继续保留本机私有 `linux/fnos/fnos-mount-manager/fstab` 作为生成产物，而不会意外进 Git。
- `scripts/node/tests/cli.test.ts` 与 `scripts/node/tests/rule-loader-installer.test.ts` 已经提供了仓库内的 `vitest + spawnSync` CLI 测试模式，适合复用来验证 shell 管理器的源码入口与单文件构建产物。
- `scripts/qa.mjs` 与 `scripts/qa-turbo.mjs` 目前只覆盖 workspace QA 和 root PowerShell QA。若 `linux/fnos` 增加 `vitest` 测试而不接入这两个入口，后续实现将无法满足仓库现有的 `pnpm qa` 工作流。

### Institutional Learnings

- `.trae/documents/修正 NTFS 自动挂载冲突与启动时密码提示.md` 记录了当前已验证的失败模式：桌面或 NAS 侧自动挂载与 `fstab` 并行存在时，会形成重复挂载冲突；挂载方案必须显式考虑“同一路径只能有一个自动挂载来源”。
- `.trae/documents/消除 pwsh 启动时的 sudo 密码提示（避免 bash 登录脚本触发）.md` 说明“在登录 shell 里补做 `mount -a`”会把挂载副作用带到不相关的终端启动路径中，新的管理器必须把这类动作收回到显式命令。
- 现网 Samba 配置已经把共享直接指向固定外接盘挂载点，而不是父目录扫描；这意味着 automount 模式在“首次访问具体共享时再挂载”的体验上是可行的，但路径稳定性不能退化。

### External References

- `systemd.automount(5)` 说明 automount 路径可在安装时自动创建，且父目录也可按需创建；这意味着管理器可以把“确保挂载点存在”做成一致性动作，而不必依赖旧脚本先手工 `mkdir` 才能工作。 Source: https://man7.org/linux/man-pages/man5/systemd.automount.5.html
- `systemd.mount(5)` 说明 `x-systemd.automount` 会创建 automount unit，`x-systemd.device-timeout=` 可用于 fstab 条目设备等待时间，而在设置 `x-systemd.automount` 时 `auto` / `noauto` 不再改变挂载是否被拉入目标单元。 Source: https://man7.org/linux/man-pages/man5/systemd.mount.5.html
- 本机 systemd 版本为 252，已支持上述 `x-systemd.automount`、`x-systemd.device-timeout=` 等行为，因此首版可以直接按当前 systemd 语义设计，而不是为更老实现做额外兼容层。 Source: local system inspection on 2026-04-05

## Key Technical Decisions

- **管理器只拥有 system fstab 中的受控外接盘区块，不拥有整份 system fstab。**  
  这样可以保留根分区、swap 与其他系统条目，避免把机器特有启动配置重新带回 repo。

- **`linux/fnos/fnos-mount-manager/disks.example.conf` 与 `linux/fnos/fnos-mount-manager/disks.local.conf` 作为主配置，`linux/fnos/fnos-mount-manager/fstab.example` 与 `linux/fnos/fnos-mount-manager/fstab` 仅作为生成产物。**  
  这保留了用户熟悉的 fstab 预览形态，同时避免再把 `fstab` 当手工编辑的真相来源。

- **管理脚本首版子命令固定为 `generate`、`apply`、`check`、`status`、`repair`。**  
  这些命令刚好覆盖配置生成、受控应用、可机读诊断、人工查看状态和异常恢复；首版不额外引入 `import`、`watch`、`daemon` 一类扩展命令。

- **默认 automount 模式生成 `x-systemd.automount` 语义，不再把 `noauto` 当成必需选项。**  
  官方 systemd 文档已经说明在启用 `x-systemd.automount` 时 `auto` / `noauto` 不影响是否生成 automount 依赖，因此生成器应以“语义清晰”为主，而不是延续旧经验里的冗余选项。

- **管理器自己显式确保固定挂载点目录存在，而不是把目录存在性交给 mount helper 的隐式行为。**  
  automount 虽可自动创建路径，但显式创建能让 Samba、文件管理器和诊断输出都更一致，也避免 eager 模式和 automount 模式出现两套目录策略。

- **`apply` 使用带标记区块的合并写入，且以临时文件替换的方式更新 system fstab。**  
  这样能避免部分写入损坏系统配置，并让回滚与差异检查更简单。

- **`repair` 默认非破坏性，只有显式强制模式才会杀掉占用进程或停用 legacy force-remount service。**  
  旧 `remount.sh` 的激进 `fuser -k -9` 只适合作为最后手段，不应成为新的默认恢复行为。

- **自动化测试使用 colocated `vitest` 文件 + Node `spawnSync` 驱动 shell 入口。**  
  这样既不引入新的 bash 测试依赖，也能同时验证源码命令与单文件构建产物。

- **FNOS 测试留在 root 质量门中接入，而不是为 `linux/fnos` 额外创建新的 pnpm workspace 包。**  
  该功能本质是仓库内的一个 shell 工具面，不值得为测试执行单独引入 workspace 边界和包级构建复杂度。

- **根目录 QA 需要显式接入 FNOS 测试。**  
  否则新功能虽然有 `vitest` 用例，但不会进入仓库要求的 `pnpm qa` 流程，实际质量门仍然缺失。

## Open Questions

### Resolved During Planning

- **主配置源继续用 `fstab` 模板还是换成结构化清单？**  
  已定为结构化 shell 清单为主，`fstab.example` / `fstab` 为生成产物。

- **是否需要保留 remount 独立脚本？**  
  不保留。`linux/fnos/remount.sh` 的能力迁入统一管理脚本的 `repair` 子命令。

- **单文件脚本要不要作为最终分发形态？**  
  要。`linux/fnos/fnos-mount-manager/build.sh` 负责从模块化源码构建单文件管理脚本，主产物为 `bin/fnos-mount-manager`，并在 `linux/fnos/fnos-mount-manager/fnos-mount-manager.sh` 保留同内容便携副本。

- **挂载模式是否需要同时支持 automount 与 eager？**  
  需要。默认 automount，按盘可切 eager。

- **shell 管理器测试是否可以用 Vitest 且就近放置？**  
  可以。首版按 `vitest + spawnSync` 方案设计，测试文件与 `linux/fnos/fnos-mount-manager` 中的模块命令邻近放置。

### Deferred to Implementation

- **结构化 shell 清单的最终 DSL 细节。**  
  计划已确定使用 shell-sourceable 配置与显式磁盘声明函数，但最终函数名、字段顺序和注释样式可在编码时细化。

- **`repair` 的强制模式参数颗粒度。**  
  计划已经确定默认安全、强制危险动作显式开启，但 `--force` 是否再细分为“仅停 unit / 杀占用 / 迁移 legacy service”留到实现时根据代码可读性落定。

- **`check` 输出采用纯文本还是额外提供可解析格式。**  
  首版应先保证稳定退出码和清晰文本诊断；是否补 JSON / key-value 输出留待实现后再评估。

- **example 配置与 `fstab.example` 的 drift 校验实现细节。**  
  可以通过生成后比对内容、哈希或时间戳实现；计划只要求首版能稳定发现漂移，不强绑具体机制。

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```text
linux/fnos/fnos-mount-manager/disks.example.conf   linux/fnos/fnos-mount-manager/disks.local.conf
             │                               │
             └──────────────┬────────────────┘
                            ▼
             linux/fnos/fnos-mount-manager/*.sh
                            │
                    linux/fnos/fnos-mount-manager/build.sh
                            ▼
     bin/fnos-mount-manager + linux/fnos/fnos-mount-manager/fnos-mount-manager.sh
                            │
        ┌───────────────────┼────────────────────┐
        ▼                   ▼                    ▼
   generate             check/status          repair
        │                   │                    │
        ▼                   ▼                    ▼
linux/fnos/fstab.*   drift/conflict report   safe remediation
        │
        ▼
      apply
        │
        ▼
system fstab managed block
        │
        ▼
systemd mount/automount units
        │
        ▼
fixed disk mountpoints → Samba / FNOS file manager / CLI access
```

```text
Directional config DSL sketch:

mount_root "<configured-root>"
default_fs "ntfs"
default_mode "automount"
default_options "<shared mount options>"

disk "<business-name>" source="LABEL:<label>" mode="automount"
disk "<business-name>" source="UUID:<uuid>"  mode="eager" options="<override>"
```

## Implementation Units

- [x] **Unit 1: 建立 FNOS 挂载管理器源码布局与配置模型**

**Goal:**  
建立新的 `linux/fnos` 管理器骨架，把“主配置、模块源码、构建产物、示例文档”分层固定下来，为后续命令实现和 legacy 清理提供稳定边界。

**Requirements:**  
R1, R2, R3, R4, R5, R6, R7, R19, R20

**Dependencies:**  
None

**Files:**
- Create: `linux/fnos/README.md`
- Create: `linux/fnos/.gitignore`
- Create: `linux/fnos/fnos-mount-manager/disks.example.conf`
- Create: `linux/fnos/fnos-mount-manager/build.sh`
- Create: `bin/fnos-mount-manager`
- Create: `linux/fnos/fnos-mount-manager/fnos-mount-manager.sh`
- Create: `linux/fnos/fnos-mount-manager/main.sh`
- Create: `linux/fnos/fnos-mount-manager/common.sh`
- Create: `linux/fnos/fnos-mount-manager/config.sh`
- Create: `linux/fnos/fnos-mount-manager/commands/generate.sh`
- Create: `linux/fnos/fnos-mount-manager/commands/apply.sh`
- Create: `linux/fnos/fnos-mount-manager/commands/check.sh`
- Create: `linux/fnos/fnos-mount-manager/commands/status.sh`
- Create: `linux/fnos/fnos-mount-manager/commands/repair.sh`
- Delete: `linux/fnos/remount.sh`
- Test: `linux/fnos/fnos-mount-manager/tests/config.test.ts`
- Test: `linux/fnos/fnos-mount-manager/tests/build.test.ts`

**Approach:**
- 把旧单文件 remount 逻辑拆成“通用函数 + 配置加载 + 子命令实现”的结构，避免后续继续把状态查询、修复、副作用和 CLI 分支堆在一个入口里。
- 新的 shell 配置用显式声明式 DSL 记录磁盘业务名、标识类型、标识值、挂载模式和可选覆盖项；`disks.example.conf` 是可提交模板，`disks.local.conf` 是用户复制出来的私有文件。
- `build.sh` 负责把源码模块按确定顺序拼接为 `bin/fnos-mount-manager`，并同步生成 `linux/fnos/fnos-mount-manager/fnos-mount-manager.sh` 便携副本；两份产物都带一致的帮助文本、版本标记和 shebang。
- `linux/fnos/README.md` 明确声明“不要手改 `fstab.example` / `fstab`，它们是生成产物”。

**Patterns to follow:**
- `linux/ubuntu/apply_config.sh`
- `scripts/node/tests/cli.test.ts`
- `scripts/node/tests/rule-loader-installer.test.ts`

**Test scenarios:**
- Happy path: 加载 `linux/fnos/fnos-mount-manager/disks.example.conf` 时能解析全局默认项和多块磁盘声明，并保持声明顺序稳定。
- Edge case: 同时声明 `LABEL=` 和 `UUID=` 源时，配置加载器能正确区分来源类型，不把冒号分隔内容解析错位。
- Error path: 缺少挂载业务名、来源值、或使用未知挂载模式时，配置加载器应返回清晰错误并阻止继续构建。
- Integration: 运行 `linux/fnos/fnos-mount-manager/build.sh` 后生成的 `bin/fnos-mount-manager` 与 `linux/fnos/fnos-mount-manager/fnos-mount-manager.sh` 都包含可执行 shebang、帮助入口和全部子命令分发，不依赖源码目录仍可启动帮助输出。

**Verification:**
- 仓库内存在清晰的 `linux/fnos` 源码布局与示例配置，且单文件管理器可以从源码稳定构建出来。
- 新旧边界明确：legacy `linux/fnos/remount.sh` 不再是推荐入口。

- [x] **Unit 2: 实现受控 `fstab` 生成与两步应用流程**

**Goal:**  
把结构化磁盘清单转换为稳定的 `fstab` 受控区块与本地预览文件，并用显式 `generate` / `apply` 两步流程安全写入 system fstab。

**Requirements:**  
R1, R2, R3, R4, R5, R8, R9, R10, R11, R12, R17

**Dependencies:**  
Unit 1

**Files:**
- Modify: `linux/fnos/fnos-mount-manager/config.sh`
- Modify: `linux/fnos/fnos-mount-manager/commands/generate.sh`
- Modify: `linux/fnos/fnos-mount-manager/commands/apply.sh`
- Create: `linux/fnos/fnos-mount-manager/fstab.example`
- Create: `linux/fnos/fnos-mount-manager/fstab`
- Test: `linux/fnos/fnos-mount-manager/tests/generate.test.ts`
- Test: `linux/fnos/fnos-mount-manager/tests/apply.test.ts`

**Approach:**
- `generate` 从 `disks.example.conf` 渲染可提交的 `linux/fnos/fnos-mount-manager/fstab.example`，从 `disks.local.conf` 渲染本机私有 `linux/fnos/fnos-mount-manager/fstab`。
- 渲染结果只包含外接数据盘受控区块，而不是完整系统文件；区块包含稳定的 begin/end marker，供 `apply` 做幂等替换。
- 默认 automount 盘生成 `x-systemd.automount` 与推荐设备等待项；eager 盘生成直接挂载选项。两种模式都复用共享 NTFS 默认选项，并允许按盘附加覆盖。
- `apply` 在写入 system fstab 前必须检测本地渲染文件是否存在且与当前配置一致，再以临时文件合并受控区块、保留非受控行、原子替换目标文件。
- `apply` 负责确保固定挂载点目录存在、触发 systemd 重新加载，并在需要时刷新受控 mount / automount 单元状态。

**Execution note:**  
先把“标记区块渲染 + 合并替换”做成可在临时文件上测试的纯逻辑，再接实际系统写入桥接层。

**Technical design:** *(directional guidance, not implementation specification)*

```text
render(managed disks) -> managed block text
read(system fstab) -> preserve unmanaged lines
replace or append managed block markers
write temp file -> validate shape -> replace target
```

**Patterns to follow:**
- `linux/fnos/fnos-mount-manager/fstab`
- `.gitignore`
- `systemd.mount(5)` behavior summary in external references

**Test scenarios:**
- Happy path: `generate` 从 example 配置生成稳定排序的 `linux/fnos/fnos-mount-manager/fstab.example`，输出包含 automount 与 eager 两种磁盘行。
- Edge case: 当某块盘覆盖默认挂载选项时，渲染结果只对该盘附加覆盖，不污染其他盘。
- Edge case: system fstab 已存在受控区块时，`apply` 只替换 marker 内内容，保留根分区、swap 与其他非受控条目原样不动。
- Error path: 本地配置缺失或渲染产物已过期时，`apply` 以非零退出中止，不写任何系统文件。
- Error path: 目标文件没有旧 marker 且无法安全追加时，`apply` 返回明确诊断而不是写入半截内容。
- Integration: automount 模式生成的区块不再依赖 legacy `mount -a` 或开机 remount service 才能被 systemd 识别。

**Verification:**
- `linux/fnos/fnos-mount-manager/fstab.example` 成为可信的 repo 预览产物。
- `apply` 可以安全更新 system fstab 的受控外接盘区块，而不会接管整份系统配置。

- [x] **Unit 3: 实现状态检查与冲突诊断命令**

**Goal:**  
提供 `status` 与 `check` 两种视角，分别覆盖人工查看当前系统状态与 CI/自动化可判定的配置一致性检查。

**Requirements:**  
R7, R8, R9, R13, R15, R16, R17, R18

**Dependencies:**  
Unit 2

**Files:**
- Modify: `linux/fnos/fnos-mount-manager/common.sh`
- Modify: `linux/fnos/fnos-mount-manager/commands/check.sh`
- Modify: `linux/fnos/fnos-mount-manager/commands/status.sh`
- Test: `linux/fnos/fnos-mount-manager/tests/check.test.ts`
- Test: `linux/fnos/fnos-mount-manager/tests/status.test.ts`

**Approach:**
- `status` 输出受管磁盘清单、当前挂载模式、挂载点状态、设备解析结果和当前 mount / automount 单元状态，适合人工排障。
- `check` 则聚焦非零退出条件：示例产物漂移、本地生成文件缺失、配置中的磁盘在系统上找不到、system fstab 的受控区块与本地渲染不一致、legacy force-remount service 仍启用、已知 shell 登录补挂载片段仍存在等。
- 检查逻辑优先用稳定的系统命令选项，例如 `findmnt`、`lsblk`、`systemctl show/list-units`，避免解析人类友好的不稳定输出。
- 对无法安全自动修复的冲突，`check` 给出明确下一步建议，但不直接篡改用户 shell 初始化文件。

**Patterns to follow:**
- `scripts/qa.mjs`
- `scripts/node/tests/cli.test.ts`
- `.trae/documents/修正 NTFS 自动挂载冲突与启动时密码提示.md`

**Test scenarios:**
- Happy path: 所有磁盘都已按配置生成且 system fstab 区块匹配时，`check` 返回成功退出码。
- Edge case: 某块盘采用 automount 且尚未实际挂载时，`status` 仍能显示其配置存在、单元可用，而不是误报失败。
- Error path: example 配置已变更但 `linux/fnos/fnos-mount-manager/fstab.example` 未刷新时，`check` 报告 drift 并返回非零退出码。
- Error path: 本地系统仍启用 legacy force-remount service 时，`check` 报告冲突来源和修复建议。
- Error path: shell 初始化文件中仍包含已知 `mount -a` 片段时，`check` 报告“需要人工清理”的诊断，而不是静默忽略。
- Integration: `status` 的受管磁盘状态能对应到当前系统的 `findmnt` / `lsblk` 结果，而不是只回显配置文件内容。

**Verification:**
- 实现者与运维者都能通过 `status` / `check` 快速区分“配置没生成”“系统没应用”“盘没出现”“有重复挂载来源”这几类问题。

- [x] **Unit 4: 用统一 `repair` 子命令替代 legacy remount 行为**

**Goal:**  
把现有 remount 需求迁移到更安全、更可控的 `repair` 子命令中，覆盖常见恢复动作而不重复发明一套开机自动挂载流程。

**Requirements:**  
R7, R9, R10, R14, R15, R16, R18

**Dependencies:**  
Unit 3

**Files:**
- Modify: `linux/fnos/fnos-mount-manager/commands/repair.sh`
- Modify: `linux/fnos/fnos-mount-manager/common.sh`
- Test: `linux/fnos/fnos-mount-manager/tests/repair.test.ts`
- Modify: `linux/fnos/README.md`

**Approach:**
- `repair` 默认执行安全操作：确保挂载点目录存在、重载 systemd 配置、重置失败的受管 mount 单元、按受管挂载点尝试重新挂载、输出修复后状态。
- 只有显式强制模式才允许停掉已失败的 automount/mount 单元、处理设备占用、或禁用仍指向旧 repo 脚本的 legacy force-remount service。
- `repair` 只自动处理边界清晰、可验证的系统状态；例如对“shell 登录脚本里仍有 `mount -a`”这类文本改写风险，保留诊断与人工步骤。
- 首版不追求“修完所有异常”，而是把最常见且可预测的恢复路径统一进一个命令，避免用户继续回退到旧脚本。

**Execution note:**  
以现有 `linux/fnos/remount.sh` 为反例写测试，优先覆盖默认安全路径与强制路径的分歧，不要先实现激进修复再补安全限制。

**Patterns to follow:**
- `linux/fnos/remount.sh`
- `.trae/documents/消除 pwsh 启动时的 sudo 密码提示（避免 bash 登录脚本触发）.md`

**Test scenarios:**
- Happy path: 某个受管 mount unit 处于 failed 状态时，默认 `repair` 可重置状态并重新尝试挂载受管挂载点。
- Edge case: automount 盘尚未挂载但配置正确时，`repair` 不应把“未触发挂载”误判成失败。
- Error path: 设备占用存在但未传强制模式时，`repair` 返回明确提示并拒绝执行破坏性动作。
- Error path: legacy force-remount service 存在但其 `ExecStart` 不指向旧仓库脚本路径时，`repair` 只报告风险，不自动停用。
- Integration: 强制模式下执行的 legacy 停用与 mount 重试动作只影响受管磁盘，不波及其他非受管挂载条目。

**Verification:**
- `repair` 能覆盖当前 `remount.sh` 的核心恢复需求，但默认行为比旧脚本更安全、范围更可控。

- [x] **Unit 5: 接入 Vitest、QA 与迁移文档**

**Goal:**  
把新的 FNOS 管理器纳入仓库现有质量门和开发文档，避免“功能已存在但没人会跑、QA 也不覆盖”的半完成状态。

**Requirements:**  
R6, R7, R15, R18, R19, R20

**Dependencies:**  
Unit 4

**Files:**
- Create: `linux/fnos/fnos-mount-manager/vitest.config.ts`
- Create: `linux/fnos/fnos-mount-manager/test-utils.ts`
- Modify: `package.json`
- Modify: `scripts/qa.mjs`
- Modify: `scripts/qa-turbo.mjs`
- Modify: `linux/INSTALL.md`
- Modify: `linux/fnos/README.md`
- Test: `linux/fnos/fnos-mount-manager/tests/manager-cli.test.ts`
- Test: `linux/fnos/fnos-mount-manager/tests/source-vs-build.test.ts`

**Approach:**
- 在 `linux/fnos/fnos-mount-manager/vitest.config.ts` 中把测试范围限制在 `linux/fnos/fnos-mount-manager/tests/**/*.test.ts`，避免 root `vitest` 无意扫到其他子项目测试。
- 通过 Node `spawnSync` 驱动源码入口与 `build.sh` 生成的两个单文件产物，验证命令输出、退出码、临时工作目录和 fixture 下的生成结果。
- 根目录 `package.json` 增加专门的 FNOS 测试脚本；`scripts/qa.mjs` 与 `scripts/qa-turbo.mjs` 根据 `linux/fnos/**` 变更决定是否执行该测试集。
- `linux/INSTALL.md` 与 `linux/fnos/README.md` 记录新的标准使用流、legacy 迁移说明、example/local 配置约定，以及“为什么不再保留独立 remount 脚本”。

**Patterns to follow:**
- `scripts/node/tests/cli.test.ts`
- `scripts/node/package.json`
- `scripts/qa.mjs`
- `scripts/qa-turbo.mjs`

**Test scenarios:**
- Happy path: 通过源码入口运行 `generate`，能在临时 fixture 目录中生成 `fstab.example` / `fstab` 预览文件。
- Happy path: 通过 `build.sh` 生成 `bin/fnos-mount-manager` 与 `linux/fnos/fnos-mount-manager/fnos-mount-manager.sh` 后，二者的 `status --help` 都与源码入口保持一致的命令面。
- Edge case: 构建产物与源码入口在同一 fixture 上运行 `check` 时，返回相同退出码和核心诊断语义。
- Error path: 当 `linux/fnos` 相关文件改动时，root QA 能触发 FNOS 测试集；未改动时不会额外放大常规 QA 成本。
- Integration: README 与安装文档中的 generate/apply/check/repair/status 流程与实际 CLI 命令面保持一致。

**Verification:**
- 新增 FNOS 管理器拥有稳定的仓库内测试入口，且 `pnpm qa` 能在相关改动时覆盖它。
- 文档与 CLI 行为一致，后续不需要靠口头说明才能落地。

## System-Wide Impact

- **Interaction graph:** `linux/fnos/disks.*.conf` → `linux/fnos/fnos-mount-manager/build.sh` → `bin/fnos-mount-manager` / `linux/fnos/fnos-mount-manager/fnos-mount-manager.sh` → `linux/fnos/fstab.*` 生成产物 → system fstab 受控区块 → systemd mount/automount 单元 → 固定数据盘挂载点 → Samba / FNOS 文件管理 / CLI 访问。
- **Error propagation:** 配置错误必须在 `generate` 阶段失败；应用错误必须在写入 system fstab 前中止；运行时异常由 `check` / `repair` 报告和处理，而不是偷偷落到 shell 登录流程中。
- **State lifecycle risks:** example 与 local 配置漂移、生成产物过期、legacy systemd service 仍启用、设备标签或 UUID 变化、受管区块与 system fstab 脱钩，都会导致“配置看起来对但系统没按预期挂载”。
- **API surface parity:** 五个子命令构成新的稳定管理面；README、INSTALL 文档、QA 入口和单文件构建产物都必须反映相同命令集合。
- **Integration coverage:** 仅靠单元测试不足以证明构建产物、marker 合并、CLI 退出码和 QA 接入正确，因此需要 fixture 驱动的 source-vs-build 和 generate/apply/check 集成覆盖。
- **Unchanged invariants:** 固定业务挂载点心智不变；现有 Samba 共享仍指向同一批业务路径；system fstab 中根分区、swap 与其他非受管条目不受本工具管理。

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| 受管区块合并逻辑写坏 system fstab，影响系统启动 | 只管理 marker 区块，使用临时文件原子替换，并对“无 marker / 旧内容异常”做失败保护 |
| shell 配置 DSL 或 build 拼接顺序失误导致单文件产物与源码行为不一致 | 用 colocated Vitest 覆盖配置解析、构建产物帮助输出、source-vs-build 行为一致性 |
| 依赖 `findmnt` / `lsblk` / `systemctl` 的输出在不同发行版上细节不同 | 统一使用稳定参数与结构化字段，避免解析彩色或树状人类输出 |
| legacy force-remount service 与 shell 登录补挂载继续存在，导致重复挂载 | `check` 明确报告冲突；`repair` 自动处理边界清晰的 legacy systemd 项；文档提供 shell 初始化的人工清理步骤 |
| automount 与 eager 两种模式共享同一生成器时选项耦合过深 | 用默认选项 + 模式增量选项 + 按盘覆盖三层模型拆开渲染逻辑，并通过 fixture 覆盖混合模式 |
| 新增 FNOS 测试未接入根目录 QA，后续实现失去门禁 | 在同一轮交付中更新 `package.json`、`scripts/qa.mjs`、`scripts/qa-turbo.mjs` |

## Documentation / Operational Notes

- `linux/fnos/README.md` 需要成为该工具的唯一使用说明，覆盖示例配置复制、构建两个单文件产物、generate/apply/check/status/repair 工作流，以及常见故障说明。
- `linux/INSTALL.md` 需要增加“FNOS 外接盘管理”段落，把旧 `linux/fnos/remount.sh` 心智替换为新管理器入口。
- live 机器迁移时，应先使用 `check` 确认 legacy force-remount service 与 shell 登录补挂载片段，再执行 `apply`，避免继续叠加旧冲突源。
- 首版不自动迁移旧的私有 `linux/fnos/fnos-mount-manager/fstab`；文档应明确建议把当前磁盘映射手工回填到 `disks.local.conf`。

## Alternative Approaches Considered

- **继续以 `linux/fnos/fnos-mount-manager/fstab.example` 作为主配置源**：  
  更接近现状，但无法优雅表达“每块盘的模式、来源类型、默认值继承、生成产物 vs 主配置”的关系，后续又会回到手工复制选项字符串。

- **让管理器拥有整份 system fstab**：  
  对新机器看似简单，但会把根分区、swap 与发行版特有条目重新拉进仓库和本地脚本，迁移成本与风险都过高。

- **保留独立 `remount.sh` 并新增一个配置生成器**：  
  会重新形成“两套入口 + 两套逻辑”的分裂模型，违背本次“唯一推荐入口”的目标。

## Sources & References

- **Origin document:** [docs/brainstorms/2026-04-05-fnos-portable-disk-mounting-requirements.md](docs/brainstorms/2026-04-05-fnos-portable-disk-mounting-requirements.md)
- Related code: [linux/fnos/remount.sh](linux/fnos/remount.sh)
- Related code: [linux/fnos/fnos-mount-manager/fstab](linux/fnos/fnos-mount-manager/fstab)
- Related code: [linux/ubuntu/apply_config.sh](linux/ubuntu/apply_config.sh)
- Related code: [scripts/qa.mjs](scripts/qa.mjs)
- Related code: [scripts/qa-turbo.mjs](scripts/qa-turbo.mjs)
- Related code: [scripts/node/tests/cli.test.ts](scripts/node/tests/cli.test.ts)
- Local learnings: [.trae/documents/修正 NTFS 自动挂载冲突与启动时密码提示.md](.trae/documents/修正%20NTFS%20自动挂载冲突与启动时密码提示.md)
- Local learnings: [.trae/documents/消除 pwsh 启动时的 sudo 密码提示（避免 bash 登录脚本触发）.md](.trae/documents/消除%20pwsh%20启动时的%20sudo%20密码提示（避免%20bash%20登录脚本触发）.md)
- External docs: https://man7.org/linux/man-pages/man5/systemd.automount.5.html
- External docs: https://man7.org/linux/man-pages/man5/systemd.mount.5.html
