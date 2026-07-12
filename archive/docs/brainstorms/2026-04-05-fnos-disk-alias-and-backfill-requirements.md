---
date: 2026-04-05
topic: fnos-disk-alias-and-backfill
---

# FNOS 磁盘业务名别名与失败盘补挂方案

## Problem Frame

当前 `linux/fnos/fnos-mount-manager` 已经能生成 `fstab`、`tmpfiles`、并提供 `check`、`repair`、`remount` 等命令，但实机重启后的结果说明：仅靠 systemd `fstab` 挂载，并不能稳定赢过 FNOS 原生自动挂载。

本机当前状态已经清楚分成两类：

- `animeDisk`、`debutDisk`、`galDisk` 已经被 FNOS 原生服务挂上，但路径是 `/vol00/ST4000VX007-2DT166`、`/vol00/ST8000NM017B-2TJ103`、`/vol00/WDC WD40EZRZ-00GXCB0` 这类型号路径，而不是业务名路径。
- `bookDisk` 没有被成功挂上，属于真正的失败盘。

因此下一步不应该继续把所有盘都视为“必须由我们抢到底层首次挂载”，而是要把方案改成两段式：

1. 对已经被 FNOS 原生挂上的盘，建立稳定业务名别名层。
2. 对 FNOS 没挂上的盘，单独补挂。

这个方案的目标不是改掉 FNOS 原始挂载路径，而是在保留原始路径的前提下，额外提供稳定、可预期、适合 Samba/脚本/人工使用的业务名路径。

## Requirements

**Alias Layer**
- R1. 方案必须保留 FNOS 原始挂载路径，不主动重命名或删除 `/vol00/ST...`、`/vol00/WDC...` 这类原生路径。
- R2. 对已经被 FNOS 成功挂上的磁盘，管理器必须能够建立稳定的业务名别名路径，例如把原始路径映射到 `/vol00/debutDisk`。
- R3. 业务名别名层默认必须使用 bind mount，而不是 symlink，除非目标环境明确不支持 bind mount。
- R4. 别名同步时必须以“原始路径是否已存在且已挂载”为前提；如果原始路径不存在，不应创建空壳别名误导使用者。

**Backfill for Failed Disks**
- R5. 对 FNOS 原生自动挂载失败的磁盘，管理器必须能够单独执行补挂，而不是要求所有磁盘都统一重挂。
- R6. “失败盘补挂”与“已挂盘别名同步”必须是可组合但逻辑独立的两个分支；不能因为某块盘失败就中断其余已挂盘的别名同步。
- R7. 对补挂仍失败的磁盘，管理器必须给出明确失败原因，并保留其他磁盘的成功结果。

**Naming and Access**
- R8. 业务名路径必须继续以结构化配置中的固定业务名为准，例如 `/vol00/bookDisk`、`/vol00/debutDisk`，不能退回卷标或磁盘型号派生。
- R9. Samba 等上层共享配置必须可以稳定切换到业务名路径，而不要求依赖 FNOS 原始型号路径。
- R10. 对终端用户和脚本调用方而言，业务名路径应成为推荐访问入口；原始路径保留但降级为底层实现细节。

**Workflow**
- R11. 管理器必须新增明确的“别名同步”能力，并支持只同步别名、不执行补挂。
- R12. 管理器必须支持只对失败盘执行补挂，而不扰动已经被 FNOS 挂上的磁盘。
- R13. 管理器必须支持一个组合入口，在一次运行中完成“先同步已挂盘别名，再补挂失败盘”。
- R14. 组合入口默认不应对已经健康挂上的磁盘执行 `umount` + `mount`，除非用户显式选择强制重挂。

## Success Criteria
- `animeDisk`、`debutDisk`、`galDisk` 这类已被 FNOS 挂到型号路径的盘，在不破坏原始路径的前提下，能稳定通过业务名路径访问。
- `bookDisk` 这类 FNOS 未挂上的盘，可以被单独补挂到业务名路径。
- 业务名路径能够作为 Samba 或其他上层入口的稳定配置目标。
- 管理器在一次执行中可以同时报告：哪些盘做了别名同步、哪些盘做了补挂、哪些盘仍失败。
- 失败盘不会拖垮已挂盘的别名同步结果。

## Scope Boundaries
- 本次不尝试让 FNOS 原生自动挂载直接改名为业务名路径。
- 本次不禁用或替换 `trim_main.service` 这类 FNOS 核心服务。
- 本次不要求删除型号路径或让它们从系统中消失。
- 本次不把 Samba 共享层的最终改动策略在此文档中细化到具体配置文件级别；这里只要求业务名路径可作为稳定目标。

## Key Decisions
- 采用“保留 FNOS 原始路径 + 叠加 bind mount 业务名别名”的方式，而不是强行改写 FNOS 原始挂载结果。
- 采用“只对失败盘补挂”的方式，而不是每次对所有盘统一重挂。
- 采用“别名同步”和“失败盘补挂”分支解耦的方式，而不是把两者硬塞进一个只会全成全败的流程。
- 采用“业务名路径为推荐入口”的方式，而不是继续让型号路径暴露给上层使用者。

## Dependencies / Assumptions
- FNOS 原生自动挂载在多数情况下仍会先把部分盘挂到型号路径，这些路径在方案运行时可被发现。
- 目标环境支持 bind mount，并允许在 `/vol00` 下建立附加挂载点。
- 当前仓库内的结构化磁盘配置已经足以表达“业务名 -> 设备标识”的关系。

## Outstanding Questions

### Resolve Before Planning
- 暂无。

### Deferred to Planning
- [Affects R2,R3,R11,R13][Technical] 别名同步是通过 bind mount 单次命令完成，还是需要额外生成/安装持久化规则或 service 来保障重启后自动恢复。
- [Affects R5,R6,R12,R13][Technical] 失败盘补挂的判定规则如何定义，才能稳定区分“未挂上”与“已挂到错误路径”。
- [Affects R9,R10][Technical] 是否要在同一轮里同步更新 Samba 配置指向业务名路径，还是先只保证本地业务名路径稳定可用。
- [Affects R13][Technical] 组合入口的命令面应如何设计，例如 `sync`、`alias`、`backfill`、`reconcile` 哪个最清晰。

## Next Steps

→ /prompts:ce-plan for structured implementation planning
