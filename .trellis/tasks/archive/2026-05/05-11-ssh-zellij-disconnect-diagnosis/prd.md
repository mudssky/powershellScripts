# brainstorm: 排查 SSH zellij 频繁断开

## Goal

定位 Windows 客户端 `192.168.21.108` 通过 SSH 连接服务器 `192.168.27.77` 时频繁断开或需要重连的根因，并形成一个可重复执行的排查路线。当前连接同时使用 `RemoteCommand` 自动进入项目目录并 attach zellij session，以及 `RemoteForward 7890 192.168.21.108:7890` 建立远端代理入口；需要区分客户端主动断开、网络抖动、端口转发异常、zellij attach 退出、VS Code Remote SSH 重连、以及服务端 sshd 策略导致的断开。

## What I Already Know

* SSH 客户端 Host 为 `proj-xhgj-ai-platform`，目标服务器 `192.168.27.77`，用户 `administrator`。
* 当前客户端配置包含 `RemoteForward 7890 192.168.21.108:7890`、`RequestTTY yes`、`RemoteCommand cd ~/projects/ai/java/xhgj-ai-platform && /home/linuxbrew/.linuxbrew/bin/zellij attach -c proj-xhgj-ai-platform`。
* 服务端近期存在大量来自 `192.168.21.108` 的 publickey 登录记录。
* 已观察到多条 `Received disconnect ... disconnected by user`、`Disconnected from user administrator 192.168.21.108`、`pam_unix(sshd:session): session closed`，初步更像客户端主动断开或上层远程工具重连。
* VS Code Remote SSH 也会断联，只是使用 sshd + zellij RemoteCommand 的连接断联更频繁；因此 sshd/zellij 可能不是唯一决定因素，而是某个共同网络或客户端问题的放大场景。
* 断联通常发生在连接建立十几分钟之后，不是秒级复现；因此优先检查历史日志与断开时间点附近的日志切片，而不是只依赖实时观察。
* 也存在只有 `session closed` 的日志，需要结合前后文、sshd LogLevel、客户端 verbose 日志进一步判断。
* 一条 `192.168.21.54` 的 `kex_exchange_identification: Connection closed by remote host` 不是主要客户端 IP，暂不作为主线证据。
* 仓库已有 `docs/cheatsheet/vscode/remote/ssh-proxy.md`，记录了 RemoteForward、服务端 `127.0.0.1:7890` 监听验证、代理 curl 验证，以及隧道自动断开可加 `ServerAliveInterval`。
* 仓库已有 `docs/cheatsheet/terminal/Zellij.md`，记录了 zellij attach/list-sessions/detach 等常用行为。
* Context7 OpenSSH 文档确认：SSH 客户端可使用 `ServerAliveInterval`、`ServerAliveCountMax`，服务端可使用 `ClientAliveInterval`、`ClientAliveCountMax`；反向转发使用 `ssh -R` / `RemoteForward`；`RequestTTY` 适合交互命令；`ExitOnForwardFailure` 可让端口转发失败显式暴露；sshd 配置中也存在 `MaxSessions`、`MaxStartups` 这类连接/会话限制项。

## Assumptions (Temporary)

* 服务器运行的是 OpenSSH sshd，并可读取 `journalctl`、`ss`、`ps`、`zellij list-sessions` 等命令输出。
* 客户端可能是 Windows OpenSSH、VS Code Remote SSH，或两者叠加；VS Code 可能会建立额外连接、主动重连或关闭旧连接。
* 远端 `127.0.0.1:7890` 默认由 sshd 为当前 SSH 会话监听；旧会话残留或其他进程占用会影响新连接。
* `RemoteCommand` 中的 `zellij attach` 一旦正常退出、异常退出或被远端伪终端关闭，SSH 会话也会随之结束。
* SSH 连接数量可能不是导致已建立连接被服务端主动踢掉的直接原因，但可能通过端口转发冲突、认证中连接限流、VS Code 多连接清理、客户端资源/网络压力等方式提高断联概率。

## Open Questions

* None.

## Requirements (Evolving)

* 收集服务端 sshd 配置中的 keepalive、forwarding、TTY、MaxSessions/MaxStartups 等关键项。
* 统计当前同一客户端、同一用户的 sshd 连接/会话数量，区分已认证会话、认证中连接、VS Code Remote SSH 连接和 zellij attach 连接。
* 收集历史 sshd/journal 日志，先做长窗口统计，再对具体断开时间点做前后 2-5 分钟切片，并按 `received disconnect`、`timeout`、`reset`、`broken pipe`、`kex`、`session closed` 分类。
* 检查服务器与客户端之间是否存在网络抖动，至少覆盖连通性、延迟、丢包、TCP 连接状态。
* 检查 `RemoteForward 7890` 是否成功建立，远端 `127.0.0.1:7890` 是否被旧 sshd 或其他进程占用。
* 检查 zellij session 与相关进程是否稳定，确认断开后 session 是否仍存在，以及 attach 命令是否有异常退出迹象。
* 检查 VS Code Remote SSH 或 Windows 客户端是否主动关闭连接、重连或复用/清理连接。
* 评估客户端临时配置：加入 `ServerAliveInterval 30`、`ServerAliveCountMax 3`、`TCPKeepAlive yes`、`ExitOnForwardFailure yes`，并将 `RemoteCommand` 改为 `bash -lc 'cd ... && exec zellij attach -c ...'`。
* 在完成诊断后，将 RemoteCommand + zellij attach + RemoteForward 7890 的断连排查流程沉淀到 `docs/cheatsheet/vscode/remote/ssh-proxy.md`。

## Acceptance Criteria (Evolving)

* [ ] 能根据历史服务端日志明确区分“客户端主动断开”“网络/TCP 异常”“服务端超时/策略断开”“远程命令退出”中的至少一类主要原因。
* [ ] 能确认 sshd keepalive 与 forwarding 相关配置当前值。
* [ ] 能确认断联时 SSH 连接数量是否异常，以及是否接近 `MaxSessions` / `MaxStartups` 或出现连接风暴。
* [ ] 能确认断开时远端 7890 监听状态和所有者。
* [ ] 能确认 zellij session/proc 在断开前后是否稳定。
* [ ] 能给出下一步最小改动建议，并说明如何验证该建议是否有效。
* [x] 仓库文档包含可复用的排查清单、推荐 SSH 配置、命令输出解读规则和 VS Code/命令行 SSH 对照实验。

## Definition of Done (Team Quality Bar)

* Tests added/updated where code behavior changes are introduced.
* Lint / typecheck / CI green if repository code is changed.
* Docs/notes updated if reusable diagnostic knowledge is added.
* Rollout/rollback considered if changing SSH client/server configuration.

## Research References

* [`research/openssh-remote-command-forwarding.md`](research/openssh-remote-command-forwarding.md) — OpenSSH keepalive、RemoteForward、RequestTTY、RemoteCommand 排查要点。

## Research Notes

### What Similar Tools Do

* SSH 交互命令通常通过 `RequestTTY` / `ssh -t` 获取伪终端；远程命令生命周期就是 SSH 会话生命周期的重要组成部分。
* 反向端口转发常用 `RemoteForward` 或 `ssh -R`；诊断重点是远端监听是否创建、绑定地址是否符合预期、失败是否被显式暴露。
* keepalive 常分为客户端侧 `ServerAlive*` 和服务端侧 `ClientAlive*`；客户端侧更适合临时验证“连接空闲或网络中间设备导致断开”的假设。
* `MaxStartups` 更偏向限制未完成认证的新连接，通常表现为新连接被拒绝或 kex 阶段关闭；`MaxSessions` 更偏向单条 SSH 连接内可打开的 session/channel 数，未必直接解释已有连接频繁断开，但必须纳入事实核查。

### Constraints From This Repo/Project

* 现有 SSH 代理文档已经覆盖 `RemoteForward 7890` 与 `ServerAliveInterval`，本次选择直接补充到该文档。
* 现有 zellij 文档是使用速查表，尚未覆盖 SSH `RemoteCommand` 场景下的 attach 退出排查。
* 历史日志策略已确定：近 7 天做模式统计，近 24 小时做细看；若用户提供具体断开时间，则优先做断开前后 2-5 分钟切片。
* 本次如果只做排查与 PRD，不需要执行 `pnpm qa`；如果后续新增脚本或修改文档，应按项目规则做相应验证。

### Feasible Approaches Here

**Approach A: 一次性人工诊断**

* How it works: 先执行服务端和客户端诊断命令，基于日志和连接状态给出根因判断，再只修改 SSH 客户端配置做 A/B 验证。
* Pros: 最快定位问题，避免过早写脚本。
* Cons: 诊断经验主要留在本任务 PRD，复用性有限。

**Approach B: 诊断清单 + 文档沉淀** (Chosen)

* How it works: 在人工诊断后，把 RemoteCommand + zellij + RemoteForward 的排查流程补充到现有 cheatsheet。
* Pros: 低成本复用，适合类似服务器连接问题再次发生。
* Cons: 仍依赖人工执行命令和解读日志。

**Approach C: 新增 PowerShell/SSH 诊断脚本**

* How it works: 写脚本自动拉取 sshd 配置、journal 日志、端口监听、zellij session、网络探测结果，并生成摘要。
* Pros: 可重复、输出稳定，适合长期维护多个 SSH 主机。
* Cons: 范围更大，会涉及 pwsh 脚本规范和 `pnpm test:pwsh:all` 验证。

## Expansion Sweep

### Future Evolution

* 后续可扩展为通用“SSH RemoteCommand + terminal multiplexer + port forwarding”诊断文档或脚本。
* 如果该连接用于长期开发，可进一步规划 ControlMaster、VS Code Remote SSH 独立 Host、或代理隧道与交互 session 分离。

### Related Scenarios

* 同类问题可能出现在 tmux、screen、zellij 的自动 attach 场景。
* VS Code Remote SSH 与人工终端 SSH 共用同一个 Host 配置时，RemoteCommand、TTY、RemoteForward 和连接数量可能互相干扰。

### Failure And Edge Cases

* `RemoteForward` 端口已被旧 sshd 占用时，如果没有 `ExitOnForwardFailure yes`，用户可能误以为隧道正常。
* 多个 SSH 连接同时使用同一个 `RemoteForward 7890` 时，只有一个连接能成功监听同一远端地址端口；其他连接可能绑定失败或退化为无代理状态。
* zellij attach 退出、远端 shell 初始化脚本错误、客户端窗口关闭、VS Code 清理旧连接都可能在服务端表现为普通 `session closed`。
* 网络中间设备、Wi-Fi 漫游、Windows 睡眠/锁屏、省电策略可能导致客户端侧连接被关闭。

## Technical Approach

先用历史日志和状态命令建立事实时间线：登录时间、断开时间、sshd 断开原因、7890 监听归属、zellij session 状态、SSH 连接/会话数量、网络连通性。因为断联通常在十几分钟之后出现，第一轮以近 24 小时到近 7 天的日志统计为主，再围绕用户提供的断开时间点做精确切片。随后用最小客户端配置变更做对照：加入 keepalive、`ExitOnForwardFailure`，并用 `exec zellij attach` 确保远程命令生命周期更直观。如果仍断开，再拆分实验：去掉 `RemoteForward`、去掉 `RemoteCommand`、不用 VS Code 仅命令行 SSH，以及拆分 VS Code Host 与人工 zellij Host，以二分方式确定触发条件。诊断完成后，把可复用清单和判断框架写入仓库文档。

## Decision (ADR-lite)

**Context**: 这类断连问题横跨 SSH 客户端、sshd、RemoteForward、zellij、VS Code Remote SSH 和网络链路；只给一次性结论会让后续相同问题重复排查。

**Decision**: 采用 Approach B，先完成一次人工诊断，再把排查流程沉淀为仓库文档。

**Consequences**: 成本低于新增自动化脚本，同时能复用现有 SSH 代理和 zellij cheatsheet；缺点是仍需要人工执行命令和解释输出。若后续类似问题频繁发生，再升级为 PowerShell/SSH 诊断脚本。

## Final Requirements Summary

* 文档落点：补充到 `docs/cheatsheet/vscode/remote/ssh-proxy.md`。
* 默认日志策略：近 7 天统计、近 24 小时细看、已知断点时间做 2-5 分钟切片。
* 文档必须覆盖：历史日志排查、连接数量/`MaxSessions`/`MaxStartups` 核查、`RemoteForward 7890` 端口冲突、zellij attach 退出语义、VS Code Host 与人工 zellij Host 拆分对照、推荐临时 SSH 配置。
* 不新增自动化脚本，不修改生产 sshd 配置。

## Implementation Plan

* [x] PR1: 补充 SSH 反向代理文档中的断连排查章节。
* [x] PR2: 更新任务验收状态，确认文档内容覆盖 PRD 要点。

## Out of Scope

* 暂不修改生产服务器 sshd 配置，除非诊断证据明确指向服务端 keepalive/forwarding 策略。
* 暂不删除 zellij session 或 kill sshd 进程，除非先确认对应进程属于本次问题且用户同意。
* 暂不把 VS Code Remote SSH 的完整行为自动化分析纳入 MVP；先收集客户端日志或用命令行 SSH 对照。
* 暂不新增自动化诊断脚本；本轮以人工诊断和文档沉淀为边界。

## Technical Notes

* Created task: `.trellis/tasks/05-11-ssh-zellij-disconnect-diagnosis`。
* Inspected `.trellis/workflow.md` and current Trellis task conventions.
* Inspected `docs/cheatsheet/vscode/remote/ssh-proxy.md` for existing RemoteForward guidance.
* Inspected `docs/cheatsheet/terminal/Zellij.md` for existing zellij usage notes.
* Used Context7 CLI:
  * `npx ctx7@latest library "OpenSSH" "..."`
  * `npx ctx7@latest library "Zellij" "..."`
  * `npx ctx7@latest docs /openssh/openssh-portable "..."`

## Investigation Findings (2026-05-11)

* 本机 `ssh -G proj-xhgj-ai-platform` 显示当前 Host 仍为 `ServerAliveInterval 0`、`ExitOnForwardFailure no`、`RequestTTY true`、`RemoteCommand zellij attach`、`RemoteForward 7890 [192.168.21.108]:7890`。
* 本机 `~/.ssh/config` 中存在多组指向 `192.168.27.77` 的 Host，很多都配置相同的 `RemoteForward 7890 192.168.21.108:7890` 和 zellij `RemoteCommand`；这会放大多连接抢同一远端端口的问题。
* 服务器当前 `127.0.0.1:7890` 已由 `mihomo.service` 监听，`[::1]:7890` 由用户会话监听；因此 SSH `RemoteForward 7890` 在 IPv4 loopback 上存在明确端口冲突。
* 服务端日志在 2026-05-11 多个时段反复出现 `error: bind [127.0.0.1]:7890: Address already in use` 和 `channel_setup_fwd_listener_tcpip: cannot listen to port: 7890`。今天按小时统计与登录次数高度同步，例如 08 点 7 次、09 点 9 次、10 点 3 次、11 点 2 次、12 点至少 1 次。
* 最小复现：`ssh -o ExitOnForwardFailure=yes -R 127.0.0.1:7890:192.168.21.108:7890 administrator@192.168.27.77 true` 会报 `remote port forwarding failed for listen port 7890`，证明显式绑定 `127.0.0.1:7890` 时转发失败是可复现的。
* `last -Fai` 显示近期来自 `192.168.21.108` 的会话既有 1-2 分钟短连接，也有 40 分钟、1 小时、数小时甚至多天连接；这不像单一 sshd keepalive 配置稳定踢人。
* 当前从 `192.168.21.108` 到服务器存在多条 SSH 连接，并且服务端存在一个远端进程连接客户端 `192.168.21.108:7890` 的 `CLOSE-WAIT` 状态；说明代理链路或客户端代理连接存在残留连接。
* 本机 `ping -n 20 192.168.27.77` 结果为 0% 丢包，平均约 6ms；当前短时网络连通性正常，但不能排除更长周期 Wi-Fi/睡眠/客户端进程重启。
* 非 root 用户执行 `/usr/sbin/sshd -T` 因 `/etc/ssh/sshd_config.d/50-cloud-init.conf` 权限不足未能确认完整有效配置；如需确认 `ClientAlive*` / `MaxSessions` / `MaxStartups` 的实际值，需要在服务端用 sudo 执行。
* 用户确认服务端确实启动了 mihomo，并已先关闭；下一步观察关闭 mihomo 后是否仍会出现十几分钟后断联。

## Current Diagnosis

最明确的已证实问题是 `RemoteForward 7890` 与服务器本机已有 `mihomo.service` 的 `127.0.0.1:7890` 监听冲突。由于客户端配置 `ExitOnForwardFailure no`，SSH 登录仍会继续，导致连接处于“会话成功但转发部分失败/半成功”的状态。结合本机存在多个同目标 Host 都声明相同 `RemoteForward 7890`，VS Code Remote SSH 与人工 zellij 连接共用配置时会进一步放大多连接与端口争用。

这不一定是所有断联的唯一原因，但它是当前可复现、可解释大量日志、且最值得优先修复的主因。下一步建议先拆分 Host、移除 VS Code Host 上的 `RemoteCommand` 与重复 `RemoteForward`，并把 zellij Host 的 `RemoteForward` 改为不冲突端口或先禁用。

2026-05-11 当前处理：先关闭服务端 mihomo，保留现有 SSH 配置，明天观察是否仍断联。如果关闭后稳定，基本可确认远端 `127.0.0.1:7890` 端口冲突是主因；如果仍断联，再继续拆分 VS Code Host 与 zellij Host，并补充客户端 keepalive。
