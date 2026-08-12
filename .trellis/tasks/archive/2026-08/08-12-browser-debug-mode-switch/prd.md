# 支持浏览器调试模式快捷切换

## Goal

让用户通过 Local/LAN 桌面快捷方式直接把同一 browser-debug Profile 切换到目标运行模式，不再要求先手工执行 `profile stop`，同时保持只管理 owned Chromium 进程的安全边界。

## Background

- `edge-debug-LAN.lnk` 参数正确，实际调用 `profile start edge-debug --mode lan --open-guide`。
- 当前 `edge-debug` 已以 `local/127.0.0.1` 运行时，`scripts/pwsh/devops/browser-debug/commands.ps1:325-332` 会拒绝模式或监听地址不同的复用请求。
- `scripts/pwsh/devops/browser-debug/runtime.ps1:554-567` 已提供只停止目标 Profile owned Chromium 进程的实现，不会终止其他日常 Edge/Chrome 实例。
- 现有规范 `.trellis/spec/pwsh-scripts/package/browser-debug-cli.md:33,46-47,59` 和测试 `tests/BrowserDebugProfile.Tests.ps1:265-280` 明确规定不同模式拒绝；本任务将更新该合同。
- 2026-08-11 的快捷方式任务已确定 Local 与 LAN 快捷方式并存、同模式幂等；当时未提供运行模式自动切换。

## Requirements

- R1：目标 Profile 未运行时，保持现有 Local/LAN 启动行为。
- R2：目标 Profile 已按相同模式和监听地址运行时，继续复用现有实例；带 `--open-guide` 时打开基于当前实际状态生成的最新帮助页。
- R3：所有 `profile start` 入口都支持从当前模式切换到目标模式；模式或监听地址改变时，停止该 Profile 的 owned Chromium 进程，再以目标配置重新启动。
- R4：交互式命令在关闭当前 CDP endpoint 和浏览器会话前，必须展示当前模式、endpoint 与目标模式并取得确认；用户拒绝时不得停止任何进程。
- R5：新增显式免确认选项 `--yes`。生成的 Local/LAN 快捷方式必须携带该选项，双击即视为用户确认切换。
- R6：非交互调用（包括 `--json`、重定向输入、CI 或 Agent）需要切换但未传 `--yes` 时，必须返回非零结果并提示添加 `--yes`，不得等待输入或默认执行。
- R7：切换不得停止不属于目标 Profile 的 Edge/Chrome 进程；进程所有权判断继续复用现有实现。
- R8：切换结果必须明确返回是否发生重启、停止的 PID、目标实际模式、监听地址、CDP endpoint 和启动 warning。
- R9：旧实例停止后新实例启动失败时必须返回非零和明确错误，不得伪装成功；不承诺自动恢复旧模式。
- R10：LAN 无认证警告继续在实际请求 LAN 启动或切换时输出；SSH 配置和进程生命周期保持独立。

## Acceptance Criteria

- [ ] AC1：Local 实例运行时触发 LAN 快捷入口，可无需二次确认自动切换为 LAN，最终状态 `running=true`、`mode=lan` 且 CDP 可用。
- [ ] AC2：LAN 实例运行时触发 Local 快捷入口，可无需二次确认自动切换为 Local，最终监听 `127.0.0.1` 且 CDP 可用。
- [ ] AC3：重复触发当前模式快捷入口不重启浏览器，只复用实例并按需打开帮助页。
- [ ] AC4：交互式 CLI 切换前显示当前 endpoint/模式与目标模式；确认后切换，拒绝确认时旧实例保持运行。
- [ ] AC5：`--json` 或其他非交互调用未带 `--yes` 时稳定失败并提示 `--yes`；带 `--yes` 时可完成切换。
- [ ] AC6：切换只停止目标 Profile 的 owned PID，不影响其他 Chromium Profile。
- [ ] AC7：切换启动失败时返回非零结果和明确错误，不报告成功状态。
- [ ] AC8：CLI help/completion、快捷方式参数、专项 Pester、真实 Local→LAN→Local smoke 与仓库 PowerShell 门禁覆盖新合同。

## Out of Scope

- 不切换或联动 SSH 配置与 SSH 进程。
- 不修改 Profile 的持久端口、浏览器类型或 User Data 路径。
- 不停止用户日常浏览器或其他 browser-debug Profile。
- 不实现切换失败后的自动回滚到旧模式。
