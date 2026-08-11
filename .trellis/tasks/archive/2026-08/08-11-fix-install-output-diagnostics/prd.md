# 修复安装编排乱码与错误诊断

## Goal

修复 Windows `pnpm provision:core` 经根安装编排器捕获叶子进程输出后出现的中文乱码，并让 Scoop 单项安装失败时保留足够、可操作的原始诊断，使用户能够区分 bucket 更新、下载和包安装失败，同时保持步骤启动提示、JSON 单文档和中断清理合同。

## Background

- `windows/03configureSources.ps1` 直接运行时输出合法 UTF-8 中文；通过 `Invoke-InstallLeafProcess` 执行后，同一内容稳定出现 `���`。原始 stdout 字节仍是合法 UTF-8，损坏发生在父进程读取字符串的路径中。
- 当前 `Invoke-InstallLeafProcess` 在 `scripts/pwsh/install/InstallOrchestrator.psm1:666-709` 使用重定向 stdout/stderr、`ReadToEndAsync()` 和 `WaitForExit(250)` 轮询；同步读取相同进程时中文正常，异步读取较长中文输出并轮询时可复现损坏。
- 当前 Text 模式会即时输出安全命令，并每 15 秒输出一次 elapsed heartbeat。用户确认周期耗时提示会污染输出且价值不足；本任务删除 heartbeat，但保留一次步骤启动提示和中断时终止叶子进程树的能力。
- 本次真实失败至少包含 Scoop `delta` 安装失败。失败发生在 `Updating files: 89% (642/721)` 的 bucket Git 更新阶段；紧接着下一项 `carapace-bin` 更新 Scoop 成功。当前 Scoop main bucket 已干净并与 `origin/master` 一致，但 `delta` 未安装，因此原始事件更像瞬时 bucket 更新故障，而不是已证实的 delta 资产下载错误。
- `Install-PackageManagerApps` 在 `psutils/modules/install.psm1:728-747` 捕获单项异常后继续安装其余应用；根编排器最终只保存经 `Protect-InstallDiagnostic` 截断到 1024 字符的步骤级 stdout/stderr 摘要，长批次中后续失败原因可能不可见。

## Requirements

1. 修复 `Invoke-InstallLeafProcess` 的输出捕获，使 UTF-8 stdout/stderr 在 Windows PowerShell 7 子进程、长文本、多字节字符和有限轮询同时存在时保持完整，不产生替换字符或乱码。
2. Text 模式只在叶子启动时输出一次安全 `[Running]` 行，不再输出周期性 elapsed heartbeat；JSON 模式保持零进度污染，参数数组执行、退出码映射和中断清理进程树合同不变。
3. 为每个包管理器应用失败保留结构化且可操作的诊断，至少包含应用名、安装命令、退出码和原始错误尾部；单项失败后继续其他应用的现有行为不变。
4. 根 `core-cli` 失败摘要应优先展示失败项，而不是被大量成功更新/下载进度挤占；仍需执行脱敏并设置有界长度，不能把任意未限制日志写入最终 JSON/Text document。
5. 测试不得执行真实 Scoop、网络下载或修改本机 package manager 状态；使用 fixture 子进程与伪安装命令复现长 UTF-8 输出、多流输出和多个单项结果。
6. 代码变更后按仓库规则执行 `pnpm qa` 与 `pnpm test:pwsh:all`。
7. Scoop 安装失败不自动重试；继续使用根编排器生成的 `-Step core-cli` 人工重跑命令，避免重复副作用和不可控执行时长。

## Acceptance Criteria

- [ ] 运行根编排器的 Windows source UTF-8 fixture 时，中文内容与叶子直接输出逐字符一致，不包含 `U+FFFD`，且 JSON 可解析。
- [ ] 长 UTF-8 stdout/stderr 与有限轮询并存时输出不损坏，Text 模式在叶子退出前只出现一次步骤启动行，不出现 `elapsed=` heartbeat。
- [ ] `-OutputFormat Json` stdout 仍只有最终单个 document，stderr 不出现 Text 进度行。
- [ ] 中断等待中的 fixture 后，直接子进程及其后代不遗留。
- [ ] 模拟 Scoop 第一项失败、后续项成功时，`core-cli` 为 Failed，摘要明确指出失败应用、命令、退出码及错误尾部，并保留失败后的继续安装行为。
- [ ] 长成功日志不会挤掉失败项诊断；token/password/secret/api key 脱敏继续生效，摘要长度有明确上限。
- [ ] 既有 Core/Full、source cleanup、重跑命令、Windows Core 精确 13 项和 package installer 测试继续通过。

## Out of Scope

- 修改 Scoop bucket、delta manifest、aria2 配置或用户网络代理。
- 为 Scoop 或其他应用安装命令增加自动重试。
- 把叶子原始 stdout/stderr 实时直通父终端。
- 增加其他周期性进度、百分比或耗时输出。
- 为所有安装步骤增加统一超时。
- 改变 Windows Core 工具清单或移除 delta。

## Key Decisions

- 保留一次步骤启动提示和有限轮询，通过修复进程输出边界解决乱码，不恢复无限阻塞等待。
- 删除周期性 elapsed heartbeat，有限轮询只服务于中断响应和进程树清理。
- 失败摘要优先保留结构化失败项，同时继续执行脱敏与有界截断。
- Scoop 失败不自动重试，继续提供现有人工 `-Step core-cli` 重跑命令。
