---
date: 2026-04-05
topic: fnos-postboot-disk-naming
focus: 重启后仍然无法稳定按业务名挂载 FNOS 外接盘，还有什么办法
---

# Ideation: FNOS 重启后磁盘业务名稳定化

## Codebase Context

当前仓库已经有一套 `linux/fnos/fnos-mount-manager`，支持 `generate`、`apply`、`check`、`status`、`repair`、`remount`，并能生成 `fstab` 与 `tmpfiles` 规则。实现假设是：只要 systemd 在开机阶段成功挂载到 `/vol00/bookDisk`、`/vol00/debutDisk` 这类路径，就能稳定保持业务名。

但本机实际行为显示，这个假设只成立一部分。开机后真正把多块 NTFS 盘挂载到 `/vol00/ST4000VX007-2DT166`、`/vol00/ST8000NM017B-2TJ103`、`/vol00/WDC WD40EZRZ-00GXCB0` 的，是 FNOS 的 `trim_main.service`，而不是我们的挂载管理器。当前状态里：

- `RemovableDisk` 能按我们的名字挂上。
- `animeDisk`、`debutDisk`、`galDisk` 常被 FNOS 原生自动挂载抢到型号路径。
- `bookDisk` 还存在“重启后未挂上”的单独失败路径。
- `status`、`check`、`repair`、`remount` 已能把这些冲突暴露出来，但还没有从产品层决定“到底是要和 FNOS 抢挂载，还是接受 FNOS 原始挂载再做命名抽象”。

代码与系统信号都说明：继续单纯增强 `fstab` 规则，无法保证重启后稳定取胜。FNOS 原生自动挂载是系统内建对手，而不是偶发干扰。

## Ranked Ideas

### 1. 在 FNOS 原始挂载之上建立稳定业务名别名层
**Description:** 不再尝试让 FNOS 原生自动挂载直接使用 `bookDisk`、`debutDisk` 这些名字，而是接受它先挂到型号路径，再由我们的管理器在开机后建立稳定的业务名别名层。别名层优先考虑 bind mount，其次才是 symlink，因为 bind mount 对 Samba、本地 CLI 和依赖真实目录树的工具兼容性更强。这里的“同步”不是给已有挂载直接改名，也不是默认先卸载再重挂，而是保持 FNOS 原始挂载不动，再把 `/vol00/ST...` 绑定到 `/vol00/bookDisk` 这类业务路径。  
**Rationale:** 这条路线不和 `trim_main.service` 正面争抢首挂时机，而是把它当成底层事实来源，再把用户真正关心的“稳定业务名路径”叠加在其上。它最符合当前代码库和本机观测：FNOS 会挂、但名字不对；我们要的是名字稳定，而不是一定亲自执行底层第一次 mount。  
**Downsides:** 需要额外处理“原始路径发现”和“业务名别名同步”两层状态；如果 FNOS 某次连原始挂载都失败，别名层也无能为力。另外这条路线会同时保留“型号路径”和“业务名路径”两套入口。  
**Confidence:** 88%  
**Complexity:** Medium  
**Status:** Unexplored

### 2. 增加开机后重协调服务，显式执行 `remount`
**Description:** 把当前已有的 `remount` 命令做成开机后的 oneshot service，顺序放在 `trim_main.service` 和相关挂载完成之后。它的职责不是取代 `fstab`，而是当系统重启后发现设备被挂到型号路径或某块盘未按期望挂载时，主动卸掉错误挂载并按业务名重挂。  
**Rationale:** 这条路线最大程度复用你已经写好的 `remount` 逻辑，改动集中，能最快验证“重启后自动纠偏”是否足够。对于现在这种“重启后只挂 4 块、而且名字不对”的症状，它能直接对症。  
**Downsides:** 仍然属于“和 FNOS 原生自动挂载打第二回合”，而不是从模型上绕开冲突。若 FNOS 服务在后续阶段继续刷新挂载，仍可能出现来回抢占。  
**Confidence:** 81%  
**Complexity:** Medium  
**Status:** Unexplored

### 3. 采用混合策略：FNOS 原始挂载做底座，仅对失败盘和关键盘执行定向重挂
**Description:** 把盘分成两类：默认所有盘都接受 FNOS 原始挂载结果，并通过业务名别名层统一访问；只有像 `bookDisk` 这种重启后经常挂载失败、或你明确要求必须真实占用业务名路径的少数盘，再执行定向 `remount`。也就是说，“已经被 FNOS 正常挂上但名字不对”的盘走 bind mount 别名；“FNOS 没挂上”的盘才补挂。  
**Rationale:** 这是在稳定性和控制力之间的折中方案。你不必为所有盘都承担“抢占底层挂载”的风险，只把复杂度投到真正出问题的少数盘。  
**Downsides:** 认知模型变成双轨：有些业务名来自别名，有些来自真实重挂。后续运维文档必须写清楚，否则容易混乱；实现上还要有“判定某块盘属于哪一类”的稳定规则。  
**Confidence:** 77%  
**Complexity:** Medium  
**Status:** Unexplored

### 4. 把“名字稳定”下沉到共享层，而不是块设备挂载层
**Description:** 接受本地实际挂载仍然是 `/vol00/ST...` 或 `/vol00/WDC...`，但通过 Samba/WebDAV/文件管理器配置层，把对外暴露的名称稳定成 `bookDisk`、`debutDisk` 这类业务名。同时，本地 CLI 若也需要业务名，可再提供轻量别名目录或脚本辅助跳转。  
**Rationale:** 如果你的核心诉求其实是“网络访问和日常管理看起来名字稳定”，那就没必要非在底层挂载点层面赢 FNOS。共享层通常比块设备层更适合承接“人类可读命名”。  
**Downsides:** 这并不能让 `/vol00/bookDisk` 本身天然存在，更多是“用户界面命名正确”，不是真正的底层挂载命名统一。对需要本地脚本固定路径的场景帮助有限。  
**Confidence:** 72%  
**Complexity:** Low  
**Status:** Unexplored

### 5. 逆向 FNOS 原生自动挂载链路，寻找可注入的命名映射点
**Description:** 把研究重点从 `fstab` 和 systemd 转到 FNOS 自带服务链路，尤其是 `trim_main.service`、`share_service`、`RemovableMonitor`、以及它们使用的配置和模板。目标不是立刻 hack 二进制，而是先验证是否存在“把型号路径映射成业务名”的可注入配置点或 hook。  
**Rationale:** 如果 FNOS 确实有内建命名映射能力，而我们现在只是没找到，那么这是唯一能让“系统原生自动挂载直接按业务名表现”的正统路线。长远看，这也是最干净的整合方式。  
**Downsides:** 当前扫描没有发现明显现成入口，说明这条路要么不存在，要么埋得很深。探索成本最高，成功率不如前几项确定。  
**Confidence:** 44%  
**Complexity:** High  
**Status:** Unexplored

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | 继续只靠 `fstab` / `tmpfiles` 打赢 FNOS 原生自动挂载 | 当前系统状态已经证明这条路不稳定，`trim_main.service` 会在重启后抢设备挂载 |
| 2 | 单纯把 NTFS 卷标改成业务名，让 FNOS 自动用卷标命名 | 现网证据显示 FNOS 当前挂载名更多来自磁盘型号而不是文件系统卷标 |
| 3 | 完全禁用 `trim_main.service` | 风险过高，它是 FNOS 核心服务，禁掉会影响的不只是外接盘挂载 |
| 4 | 只用 symlink 做业务名 | 成本低但兼容性弱，许多工具和共享场景对 bind mount 更稳 |
| 5 | 继续人工重启后执行 `remount` | 不解决“重启后自动恢复”的根问题，只是把操作成本留给人 |

## Session Log
- 2026-04-05: Initial ideation — 10+ candidate directions considered, 5 survivors kept
- 2026-04-05: Refined ideas #1 and #3 — clarified that alias sync prefers bind mounts over rename/unmount, and that failed disks can fall back to targeted remount
