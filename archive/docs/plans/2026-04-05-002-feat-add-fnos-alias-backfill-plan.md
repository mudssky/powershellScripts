---
title: feat: add fnos alias backfill
type: feat
status: completed
date: 2026-04-05
origin: docs/brainstorms/2026-04-05-fnos-disk-alias-and-backfill-requirements.md
---

# feat: add fnos alias backfill

## Overview

本计划承接 `docs/brainstorms/2026-04-05-fnos-disk-alias-and-backfill-requirements.md`，目标是在现有 `linux/fnos/fnos-mount-manager` 基础上增加一层“启动后协调器”：

1. 对已经被 FNOS 原生自动挂载到型号路径的磁盘，建立稳定的业务名 bind mount 别名。
2. 对 FNOS 未成功挂载的磁盘，执行单独补挂。
3. 提供组合入口，让一次运行能同时完成“已挂盘别名同步 + 失败盘补挂”。

它不是要替换 FNOS 原生自动挂载，而是承认 `trim_main.service` 是底层事实来源，并在其之上叠加稳定的业务名访问层。这样可以避免继续把所有盘都当成“必须抢赢 FNOS 首次挂载”的问题。

这份计划也显式收敛掉几条已被实机证明无效或需要降级的旧设计：

- 不再把“只靠 `fstab` 赢过 FNOS 原生自动挂载”当作主目标。
- 不再把所有磁盘都视为同一种问题统一处理。
- 不再让 `repair` 承担“重启后主入口纠偏命令”的角色。
- 不再要求业务名路径成为系统里唯一真实的底层挂载路径。

## Problem Frame

当前机器上的真实状态已经暴露出仅靠 `fstab` 的局限：

- `animeDisk`、`debutDisk`、`galDisk` 在重启后会被 FNOS 原生服务挂到 `/vol00/ST4000VX007-2DT166`、`/vol00/ST8000NM017B-2TJ103`、`/vol00/WDC WD40EZRZ-00GXCB0` 这类型号路径。
- `bookDisk` 没有被成功挂上，属于真正的失败盘。
- `RemovableDisk` 是当前唯一既被挂上、又按业务名成功挂载的盘。

这说明我们面对的不是单一的“挂载失败”问题，而是两类问题同时存在：

- **命名偏差**：底层盘挂上了，但路径不是业务名。
- **挂载缺失**：盘没有挂上。

继续只增强 `fstab`、`tmpfiles` 或 `remount`，本质上仍在试图和 FNOS 原生自动挂载竞争首挂时机。更现实的路线是：

- 已挂上的盘不卸载、不重挂，而是保留原始路径，再叠加业务名别名。
- 失败的盘才进入补挂分支。

## Requirements Trace

- R1-R4. 保留 FNOS 原始型号路径，对已挂上的盘建立稳定 bind mount 业务名别名，不对未挂原始路径创建空壳别名。
- R5-R7. 对失败盘单独补挂，且补挂失败不应破坏其他盘的别名同步结果。
- R8-R10. 业务名路径继续来自结构化配置，并成为推荐访问入口；Samba 等上层应能切到业务名路径。
- R11-R14. 新增显式别名同步能力、失败盘补挂能力，以及一个组合入口；组合入口默认不对已健康挂上的盘做卸载重挂。

## Scope Boundaries

- 本次不尝试让 FNOS 原生自动挂载直接按业务名命名。
- 本次不禁用、替换或 patch `trim_main.service`。
- 本次不删除 FNOS 原始型号路径。
- 本次不在这一轮引入对 Samba 配置文件的自动修改；只要求业务名路径具备切换条件，并把共享层改动作为明确的后续单位。
- 本次不处理非 NTFS 数据盘的文件系统差异。

## Context & Research

### Relevant Code and Patterns

- `linux/fnos/fnos-mount-manager/commands/status.sh` 已经能区分三种状态：按业务名挂上、挂到错误路径、完全未挂上。这是新协调器做分支判断的核心观测面。
- `linux/fnos/fnos-mount-manager/commands/repair.sh` 负责安全修复，遇到 “mounted elsewhere” 只报告不接管；`commands/remount.sh` 则会主动卸载错误路径并重挂到业务名路径。这两者已经提供了“保守修复”和“主动接管”的命令语义基线。
- `linux/fnos/fnos-mount-manager/common.sh` 里已有设备解析、mountpoint 判断、`findmnt` 设备目标发现、受管区块合并等可复用 helper，适合扩展出“原始路径发现”和“bind mount 同步”。
- `linux/fnos/fnos-mount-manager/tests/` 已经建立起 `vitest + spawnSync` 的 shell 集成测试模式，覆盖 `generate`、`apply`、`check`、`status`、`repair`、`remount`。新的协调器能力应继续沿用这套测试基线，而不是引入新的测试框架。
- 当前本机 Samba 用户共享配置没有暴露外接盘共享项，说明“共享层切业务名”不能假设一定存在固定模板；更适合作为独立可选单元。

### Institutional Learnings

- 现机观察显示 FNOS 原生自动挂载的真正对手是 `trim_main.service`，它会把部分 NTFS 盘挂到型号路径；把这一层当成底层事实来源比继续和它抢首挂更符合现实。
- 之前为了让 `fstab` 更早成功，已经补了 `tmpfiles` 规则，但实机结果表明这只能解决“目录不存在导致失败”的子问题，不能解决“原生服务命名不同”的主问题。
- 对于重复型号或被 FNOS 错挂的盘，强行统一 `remount` 全盘重挂虽然能接管，但风险高于“已挂盘 bind mount 别名、失败盘再补挂”的组合。

### External References

- Linux bind mount 允许在不改变底层设备原始挂载的前提下，为同一目录树提供第二个稳定路径入口。这使得“保留型号路径 + 新增业务名路径”在技术上成立，并且比 symlink 更适合需要真实目录树语义的共享与工具。 Source: mount(8) semantics, locally validated system behavior
- 当前 FNOS 上的 `mount.ntfs` 进程显示，多块盘是在 `trim_main.service` 的 cgroup 中启动的，而不是 `fstab` 生成的 mount unit。这直接支持“先接受 FNOS 原挂载，再叠加别名/补挂”的方向。 Source: local process and cgroup inspection on 2026-04-05

## Key Technical Decisions

- **新增协调层优先采用 bind mount 别名，而不是默认卸载重挂。**  
  已挂上的盘不应因为名字不对就触发底层设备重挂；别名层能以更低风险提供稳定业务名。

- **把磁盘分成“原始挂载已存在”和“原始挂载缺失”两类。**  
  前者走别名同步，后者走补挂。不要把两类盘都塞进同一条底层重挂路径。

- **组合入口以“先别名同步，再失败盘补挂”为默认顺序。**  
  这样能最大化保存已经存在的健康状态，并把破坏性动作收缩到确实失败的盘。

- **现有 `generate` / `apply` / `check` 继续保留，但它们被重新定位为“基础配置与诊断层”，不再承诺单独解决重启后命名稳定化。**  
  这几条命令仍有价值，但不该再被文档或实现暗示成完整答案。

- **现有 `repair` 降级为保守修复工具，`remount` 保留为手工接管工具；两者都不是重启后默认主路径。**  
  重启后的主路径应切到新的 `alias` / `backfill` / `reconcile` 组合，而不是继续让旧命令承担错误的职责。

- **业务名路径被定义为“稳定推荐入口”，而不是“唯一真实底层挂载点”。**  
  这让方案能接受 FNOS 原始型号路径继续存在，从而避免无谓地和系统内建挂载机制硬碰硬。

- **首版不自动改 Samba 配置，但设计上要让业务名路径可直接被 Samba 配置引用。**  
  这能把共享层切换作为独立后续动作，而不把当前实现复杂度一下子拉高。

- **原始型号路径仍然保留且可见。**  
  业务名路径是推荐入口，不是用来替代 FNOS 内部真实挂载标识。

## Open Questions

### Resolved During Planning

- **业务名同步是直接改名还是卸载重挂？**  
  都不是。已挂上的盘优先采用 bind mount 别名层。

- **失败盘是否要和已挂盘走同一条重挂路径？**  
  不要。失败盘单独补挂，已挂盘不默认进入底层 remount。

- **是否保留原始型号路径？**  
  保留。业务名路径和原始路径并存，业务名成为推荐入口。

### Deferred to Implementation

- **原始路径发现策略的最终优先级。**  
  例如是优先读 `findmnt -S <device>` 结果，还是结合 `/vol00/*` 模式与共享服务日志做辅助校验，留到编码时在可读性和鲁棒性之间取舍。
- **bind mount 的持久化方式。**  
  首版可以通过显式命令建立，也可以额外生成持久化配置（如受管 `fstab` bind 行或 oneshot service）；最终落点在实现时根据副作用边界决定。
- **补挂分支是否直接复用现有 `repair` / `remount` helper，还是抽更细的内部函数。**  
  计划倾向复用并下沉 helper，但不强绑具体重构形态。
- **Samba 配置切换是否要在同一轮落地。**  
  当前倾向分离成后续单元，但如果实现过程中发现改动极小，也可以在最后一单元追加。

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```text
per disk:
  discover device -> discover current target

  if current target == business mountpoint:
    mark healthy
    continue

  if current target exists and current target != business mountpoint:
    ensure business mountpoint dir exists
    create/reconcile bind mount alias
    mark alias_synced
    continue

  if current target missing:
    attempt targeted backfill mount to business mountpoint
    if success:
      mark backfilled
    else:
      mark failed with reason
```

```text
reconcile command:
  alias phase:
    already-mounted-elsewhere -> bind mount business alias
  backfill phase:
    not-mounted -> mount business target
  summary:
    aliases synced / backfilled / unchanged / failed
```

## Implementation Units

- [x] **Unit 1: 扩展状态模型，显式区分别名同步候选盘与补挂候选盘**

**Goal:**  
把当前 `status` / `check` 的状态判断提升为可复用的内部分类模型，让后续命令能稳定区分“已挂错路径”“完全未挂”“已正确挂上”三类磁盘。

**Requirements:**  
R2, R4, R5, R6, R13

**Dependencies:**  
None

**Files:**
- Modify: `linux/fnos/fnos-mount-manager/common.sh`
- Modify: `linux/fnos/fnos-mount-manager/commands/status.sh`
- Modify: `linux/fnos/fnos-mount-manager/commands/check.sh`
- Test: `linux/fnos/fnos-mount-manager/tests/status.test.ts`
- Test: `linux/fnos/fnos-mount-manager/tests/check.test.ts`

**Approach:**
- 在 `common.sh` 中新增面向单块盘的状态解析 helper，返回至少这些分类：`mounted_expected`、`mounted_elsewhere`、`not_mounted`、`device_missing`。
- `status` 输出要复用这个分类结果，不再自行拼状态；`check` 也复用同一分类结果，避免多套逻辑漂移。
- 对 “mounted_elsewhere” 继续保留原始路径信息，作为后续 bind mount 同步的输入。

**Patterns to follow:**
- `linux/fnos/fnos-mount-manager/commands/status.sh`
- `linux/fnos/fnos-mount-manager/commands/check.sh`

**Test scenarios:**
- Happy path: 设备已挂在业务名路径时，分类结果为 `mounted_expected`，`status` 输出显示 `mounted: yes`。
- Edge case: 设备已挂在型号路径时，分类结果为 `mounted_elsewhere`，输出包含原始路径。
- Error path: 设备存在但未挂载时，分类结果为 `not_mounted`，且不会误报为 `mounted_elsewhere`。
- Error path: 设备软链接不存在时，分类结果为 `device_missing`，并在 `check` 中计为错误。

**Verification:**
- 新的内部状态模型足够稳定，后续别名同步和失败盘补挂都不需要自己重新猜状态。

- [x] **Unit 2: 新增 bind mount 别名同步能力**

**Goal:**  
为已经被 FNOS 原生挂上的盘建立稳定业务名 bind mount 别名，而不扰动 FNOS 原始挂载。

**Requirements:**  
R1, R2, R3, R4, R8, R10, R11, R14

**Dependencies:**  
Unit 1

**Files:**
- Modify: `linux/fnos/fnos-mount-manager/common.sh`
- Create: `linux/fnos/fnos-mount-manager/commands/alias.sh`
- Modify: `linux/fnos/fnos-mount-manager/main.sh`
- Modify: `linux/fnos/fnos-mount-manager/build.sh`
- Modify: `linux/fnos/fnos-mount-manager/README.md`
- Test: `linux/fnos/fnos-mount-manager/tests/alias.test.ts`
- Test: `linux/fnos/fnos-mount-manager/tests/manager-cli.test.ts`

**Approach:**
- 新增显式 `alias` 子命令，只处理 `mounted_elsewhere` 的磁盘。
- 对每块候选盘，先确保业务名挂载点目录存在，再检查该业务名路径是否已经是一个 bind mount 入口；若未建立，则执行 bind mount。
- 若业务名路径已经绑定到正确原始路径，命令应报告已同步而不是重复执行。
- 不要在 `alias` 命令里做底层设备卸载或重挂。

**Execution note:**  
Start with a failing integration-style CLI test for “mounted elsewhere -> business alias created” before wiring the command into `main.sh`.

**Patterns to follow:**
- `linux/fnos/fnos-mount-manager/commands/remount.sh`
- `linux/fnos/fnos-mount-manager/tests/remount.test.ts`

**Test scenarios:**
- Happy path: 设备已挂在型号路径时，`alias` 会把该路径 bind mount 到业务名路径。
- Edge case: 业务名路径已经正确 bind 到原始路径时，命令返回成功且不重复执行。
- Edge case: 原始路径不存在时，不创建空业务名路径别名，而是报告跳过。
- Error path: bind mount 失败时，命令返回非零退出码并保留失败原因。
- Integration: `alias` 只处理 `mounted_elsewhere` 的盘，不会对 `not_mounted` 或 `mounted_expected` 的盘执行底层动作。

**Verification:**
- 已被 FNOS 原始挂上的盘能通过业务名路径稳定访问，同时原始型号路径保持可用。

- [x] **Unit 3: 为失败盘新增独立 backfill 分支**

**Goal:**  
为 FNOS 未成功挂载的盘提供单独补挂能力，而不扰动已经健康或已别名同步的磁盘。

**Requirements:**  
R5, R6, R7, R12, R13, R14

**Dependencies:**  
Unit 1

**Files:**
- Create: `linux/fnos/fnos-mount-manager/commands/backfill.sh`
- Modify: `linux/fnos/fnos-mount-manager/common.sh`
- Modify: `linux/fnos/fnos-mount-manager/main.sh`
- Modify: `linux/fnos/fnos-mount-manager/build.sh`
- Test: `linux/fnos/fnos-mount-manager/tests/backfill.test.ts`

**Approach:**
- 新增显式 `backfill` 子命令，只处理 `not_mounted` 的磁盘。
- 优先复用现有 `repair` / `remount` 中已经存在的 mount helper，而不是重新复制设备处理逻辑。
- 成功补挂后，状态应转换成 `mounted_expected`；补挂失败则记录失败盘列表并继续处理其他失败盘。
- 不对 `mounted_elsewhere` 的盘直接做 backfill，避免把别名同步场景误判成失败盘场景。

**Patterns to follow:**
- `linux/fnos/fnos-mount-manager/commands/repair.sh`
- `linux/fnos/fnos-mount-manager/tests/repair.test.ts`

**Test scenarios:**
- Happy path: `not_mounted` 的磁盘能被成功挂到业务名路径。
- Edge case: 某块失败盘补挂成功，其他健康盘保持不变。
- Error path: 单块盘补挂失败时返回明确原因，但不阻断后续失败盘处理。
- Integration: `backfill` 不会对 `mounted_elsewhere` 的盘执行卸载或重挂。

**Verification:**
- 未挂上的盘可以在不影响已挂盘的前提下被单独补挂。

- [x] **Unit 4: 增加组合入口 `reconcile`，统一执行别名同步与失败盘补挂**

**Goal:**  
提供一个适合重启后使用的高层命令，在一次运行中完成“先别名同步，再补挂失败盘”，并输出清晰总结。

**Requirements:**  
R6, R7, R11, R12, R13, R14

**Dependencies:**  
Unit 2, Unit 3

**Files:**
- Create: `linux/fnos/fnos-mount-manager/commands/reconcile.sh`
- Modify: `linux/fnos/fnos-mount-manager/main.sh`
- Modify: `linux/fnos/fnos-mount-manager/build.sh`
- Modify: `linux/fnos/fnos-mount-manager/README.md`
- Test: `linux/fnos/fnos-mount-manager/tests/reconcile.test.ts`
- Test: `linux/fnos/fnos-mount-manager/tests/manager-cli.test.ts`

**Approach:**
- `reconcile` 明确按顺序执行：别名同步阶段 -> 补挂阶段 -> 汇总结果。
- 汇总输出至少包括：`unchanged`、`alias_synced`、`backfilled`、`failed` 四类。
- 默认不对 `mounted_elsewhere` 的盘做底层卸载重挂；若将来需要更激进模式，放到后续增强，不在本轮默认行为中加入。

**Technical design:** *(directional guidance, not implementation specification.)*

```text
for each disk:
  classify state

alias phase:
  if mounted_elsewhere -> alias

backfill phase:
  if not_mounted -> backfill

summary:
  print per-disk final action and failures
```

**Patterns to follow:**
- `linux/fnos/fnos-mount-manager/commands/generate.sh`
- `linux/fnos/fnos-mount-manager/tests/source-vs-build.test.ts`

**Test scenarios:**
- Happy path: 同一次运行里，已挂错路径的盘被同步别名，未挂上的盘被补挂。
- Edge case: 所有盘都已健康时，`reconcile` 返回成功并说明无需动作。
- Error path: 别名同步成功但某块盘补挂失败时，结果摘要能同时反映成功项和失败项。
- Integration: 构建产物与源码入口对 `reconcile --help` 和默认输出保持一致。

**Verification:**
- 用户有一个明确的“重启后统一纠偏”命令，而不需要手动按盘决定运行哪个子命令。

- [x] **Unit 5: 为共享层切换预留稳定业务名入口，并更新文档/运维说明**

**Goal:**  
把业务名路径作为推荐入口固化进文档，并为后续 Samba 切换留下明确边界和验证方式。

**Requirements:**  
R8, R9, R10

**Dependencies:**  
Unit 4

**Files:**
- Modify: `linux/fnos/fnos-mount-manager/README.md`
- Modify: `linux/INSTALL.md`
- Modify: `docs/plans/2026-04-05-001-refactor-fnos-mount-manager-plan.md`
- Test: `Test expectation: none -- documentation-only unit`

**Approach:**
- README 里明确区分三类命令：底层配置命令、保守修复命令、启动后协调命令。
- 文档中把业务名路径定义为推荐访问入口，把型号路径定义为底层实现细节。
- 记录共享层切换建议：当业务名路径稳定后，Samba path 应优先指向业务名路径，而不是型号路径。
- 旧计划文档补充交叉引用，说明“开机后命名稳定化”已拆成新的后续工作，而不是继续堆进原计划。

**Patterns to follow:**
- `linux/fnos/fnos-mount-manager/README.md`
- `linux/INSTALL.md`

**Test scenarios:**
- `Test expectation: none -- documentation-only unit`

**Verification:**
- 实现完成后，后来者能够从文档直接理解“为什么保留型号路径、为什么业务名路径仍然稳定、重启后应该跑哪个命令”。

## System-Wide Impact

- **Interaction graph:** `disks.local.conf` → 状态分类 helper → `alias` / `backfill` / `reconcile` → 业务名路径稳定层 → 本地 CLI / 后续 Samba path 切换。
- **Error propagation:** 原始挂载不存在、bind mount 失败、补挂失败都要沿命令摘要清晰上抛；不能只留一条“失败了”的模糊日志。
- **State lifecycle risks:** 同一磁盘同时存在原始路径和业务名路径，必须确保别名同步幂等；失败盘补挂后不能反过来污染已挂盘状态。
- **API surface parity:** 新增命令必须同步进入源码入口、构建产物、README、测试入口。
- **Integration coverage:** 只 mock 单条命令不足以证明状态分类和组合流程正确；需要 fixture 驱动的 “mounted elsewhere + not mounted” 混合场景测试。
- **Unchanged invariants:** `trim_main.service` 继续存在；型号路径继续存在； `fstab` / `tmpfiles` 仍然负责你已有的基础挂载配置，但不再承担“赢过 FNOS 全部原始挂载”的单一职责。

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| bind mount 别名与 FNOS 原生共享/监控逻辑发生意外交互 | 首版保留原始路径不动，只新增业务名路径；文档里明确业务名路径为上层推荐入口 |
| 状态分类不稳定，导致同一块盘在不同命令里被不同逻辑处理 | 先抽统一状态分类 helper，再让 alias/backfill/reconcile 全部复用 |
| `reconcile` 既做别名又做补挂，日志和失败语义变得混乱 | 用分阶段执行和结构化摘要输出，保留 per-disk 结果 |
| Samba 最终仍未切换到业务名路径，导致用户感知收益有限 | 在文档里把 Samba 切换作为明确后续动作暴露出来，不再隐含假设 |
| `bookDisk` 失败原因不只是不挂载，后续可能需要更深排障 | backfill 分支必须保留明确失败原因，不把所有问题都压扁成“挂载失败” |

## Documentation / Operational Notes

- 这份计划默认不自动改 Samba 配置，但会把“何时可以切换共享路径”作为文档化结果交付。
- 运行层建议会从“`repair` / `remount`”转向“`reconcile`”，并明确它适合重启后调用。
- 现有 README、安装说明和后续运维说明需要显式写清楚哪些旧命令被降级：`repair` 是保守修复，`remount` 是手工接管，`reconcile` 才是默认的启动后协调入口。
- 如果未来确认 FNOS 有原生可注入命名点，这份计划仍然可作为过渡方案；别名层不阻断更深度整合。

## Alternative Approaches Considered

- **继续强化 `remount` 让所有盘都统一重挂到业务名路径**  
  这对失败盘有效，但对已经被 FNOS 正常挂上的盘代价偏高，也更容易和原生自动挂载反复抢占。

- **只做共享层改名，不做本地业务名路径**  
  这样 Windows/Samba 侧可能够用，但本地 CLI 和脚本仍然面对型号路径，不满足当前要求。

- **继续赌 `fstab` + `tmpfiles` 足够赢过 FNOS 原生自动挂载**  
  实机状态已经证明这条路不足以稳定解决问题。

## Sources & References

- **Origin document:** [docs/brainstorms/2026-04-05-fnos-disk-alias-and-backfill-requirements.md](docs/brainstorms/2026-04-05-fnos-disk-alias-and-backfill-requirements.md)
- Related code: [linux/fnos/fnos-mount-manager/common.sh](linux/fnos/fnos-mount-manager/common.sh)
- Related code: [linux/fnos/fnos-mount-manager/commands/status.sh](linux/fnos/fnos-mount-manager/commands/status.sh)
- Related code: [linux/fnos/fnos-mount-manager/commands/repair.sh](linux/fnos/fnos-mount-manager/commands/repair.sh)
- Related code: [linux/fnos/fnos-mount-manager/commands/remount.sh](linux/fnos/fnos-mount-manager/commands/remount.sh)
- Related code: [linux/fnos/fnos-mount-manager/tests/](linux/fnos/fnos-mount-manager/tests)
- Related config: [linux/fnos/fnos-mount-manager/disks.local.conf](linux/fnos/fnos-mount-manager/disks.local.conf)
- Local state reference: `/etc/samba/users/1000.share.conf`
