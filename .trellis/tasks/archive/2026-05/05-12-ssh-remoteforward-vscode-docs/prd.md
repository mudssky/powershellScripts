# SSH RemoteForward 断联与 VS Code 文档优化

## Goal

排查 Windows 侧 SSH 连接 Linux 服务器时的间歇断联问题，先通过关闭常规连接里的 `RemoteForward` 来观察是否由多个客户端抢占同一个远端端口触发，同时更新 VS Code Remote SSH 文档，避免后续配置继续把代理隧道混入 VS Code 或 zellij 会话。

## What I already know

* 本机 `C:\Users\mudssky\.ssh\config` 中多个普通 Host 曾直接配置 `RemoteForward 7890 127.0.0.1:7890` 或 `RemoteForward 7890 localhost:7890`。
* zellij 项目 Host 使用 `RequestTTY yes` 与 `RemoteCommand ... zellij attach -c ...`。
* 用户确认当前不确定断联是否由 `RemoteForward` 引发，策略是先关掉观察。
* 用户希望 VS Code 侧加 `ServerAliveInterval 60`、`ServerAliveCountMax 3`、`ConnectTimeout 30`，zellij 侧暂不加，避免混淆观察结果。
* `docs/cheatsheet/vscode/remote/ssh-proxy.md` 已有 RemoteForward、VS Code、zellij 混用断联排查说明，但当前“VS Code 自动化配置”部分仍容易鼓励把 `RemoteForward` 放入 VS Code Host。

## Requirements

* 注释掉普通 Host 中现有 `RemoteForward 7890`，保留原配置作为可恢复记录。
* 只给普通/VS Code 连接 Host 增加 `ServerAliveInterval 60`、`ServerAliveCountMax 3`、`ConnectTimeout 30`。
* 暂不修改 zellij Host 的保活参数，保留其原有 `RequestTTY` 与 `RemoteCommand` 行为。
* 更新 VS Code Remote SSH 文档：默认建议不要让 VS Code Host 直接声明 `RemoteForward`；如需代理，优先使用独立隧道 Host 或临时 `ssh -N -R`。
* 文档补充本次观察法：先关闭 `RemoteForward`，仅给 VS Code Host 加保活，观察断联是否缓解。
* 文档补充可直接套用的 SSH config 实例，覆盖 VS Code、zellij、独立代理隧道三种入口。

## Acceptance Criteria

* [x] 本机 SSH config 中普通 Host 不再启用 `RemoteForward 7890`。
* [x] 本机 SSH config 中普通/VS Code Host 具备 `ServerAliveInterval 60`、`ServerAliveCountMax 3`、`ConnectTimeout 30`。
* [x] zellij Host 未新增保活参数。
* [x] VS Code SSH 反向代理文档不再把 `RemoteForward` 放入 VS Code Host 作为默认推荐。
* [x] VS Code SSH 反向代理文档包含 VS Code、zellij、独立 tunnel 三种配置实例。
* [x] 可通过 `ssh -G` 验证关键 Host 配置解析结果。

## Definition of Done

* 文档与本机配置改动完成。
* 配置解析验证通过。
* 仅修改文档/配置，不执行根目录 `pnpm qa`。

## Out of Scope

* 不修改远端 `sshd_config`。
* 不调整 zellij Host 的 `RemoteCommand` 写法。
* 不新增单元测试。
* 不直接判定断联根因，保留观察结论。

## Research References

* [`research/openssh-client-options.md`](research/openssh-client-options.md) — OpenSSH 客户端选项语义确认。

## Technical Approach

采用最小变量实验：关闭 `RemoteForward`，只在普通/VS Code Host 上增加客户端保活与连接超时参数；zellij Host 保持原状。文档同步改为“独立隧道优先、VS Code Host 保持干净”的建议。

## Decision (ADR-lite)

**Context**: 当前断联根因未确认，`RemoteForward` 多连接冲突只是候选原因之一。

**Decision**: 不一次性重构全部 Host；先注释普通 Host 的 `RemoteForward` 并给 VS Code 侧增加连接参数，zellij 侧不动。

**Consequences**: 观察期内远端 `127.0.0.1:7890` 代理不会自动随普通连接建立；如果断联仍出现，后续再排查网络空闲超时、VS Code 重连、远端 sshd 限制或 zellij attach 生命周期。

## Technical Notes

* 涉及文件：`C:\Users\mudssky\.ssh\config`、`docs/cheatsheet/vscode/remote/ssh-proxy.md`。
* Context7 查询 OpenSSH 文档，确认 `RemoteForward`、`-R`、`ServerAliveInterval`、`ServerAliveCountMax`、`TCPKeepAlive` 等选项语义。
