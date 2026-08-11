# 浏览器远程 CDP 调试配置

## Goal

提供一个 Windows PowerShell CLI，为 Chrome 或 Microsoft Edge 创建和管理独立调试 Profile，使本机、局域网或远端主机上的官方 `playwright-cli` 能连接，并可查询 Profile 路径、端口、快捷方式与 SSH 交接信息。

## Background

- 首版位于 `scripts/pwsh`，仅支持 Windows；macOS、Linux 与 WSL 因当前无法验证而不纳入首版。
- 调试 Profile 与日常浏览器 Profile 隔离，默认存放在 D 盘。
- `playwright-cli` 使用 `playwright-cli attach --cdp=http://<host>:<port>` 连接 Chromium CDP。
- 仓库已有 `browserctl.ps1`，但它只代理 installed `browser-host`，不创建或登记本地调试 Profile。

## Requirements

### CLI interface

- 公开入口为 `browser-debug.ps1`；正常 PowerShell Profile 中提供 `browser-debug` 别名。
- 使用传统 CLI 语法：小写资源/动作、位置名称参数和 `--kebab-case` 长选项。
- Profile actions：`create|set|get|list|start|status|stop|shortcut`。
- SSH actions：`create|set|get|list|info|start|status|stop`。
- 提供 `help`、分层 `--help`、`--json` 和 `completion powershell`。
- PowerShell Native Completer 可补全资源、动作、选项、枚举值、已登记 Profile 名称和 SSH 配置名称。

### Profile 与端口

- 支持 Chrome 与 Edge，并发现常见 Windows 安装位置；缺失时给出明确错误。
- `profile create <name>` 支持配置浏览器、CDP 端口、Profile 路径、User Data 来源和快捷方式目录，只克隆、创建和登记，不启动浏览器。
- 默认从所选浏览器当前用户的默认 User Data 目录克隆全部登录状态与扩展；`--source-user-data-path` 可覆盖来源，`--without-extensions` 可排除扩展本体和扩展状态目录以节省空间。
- 克隆目标必须与来源完全隔离；来源浏览器仍在运行、存在 Chromium 锁文件、路径互相包含或复制失败时拒绝登记，并提示关闭浏览器后重试。
- 默认根目录为 `D:\browser-debug-profiles`，每个 Profile 使用独立目录，禁止复用浏览器默认用户数据目录。
- `profile set <name> --cdp-port <port>` 在停止状态下持久修改端口；运行中拒绝修改并提示先停止。
- 快捷方式和 SSH 配置只引用 Profile，使用时解析当前端口，因此端口修改后无需同步更新其他配置。
- 同名 Profile、端口冲突、无效路径、浏览器缺失或启动失败时返回可诊断错误，不写入误导性的成功记录。

### 浏览器启动模式

- `profile start <name>` 支持 `--mode local|lan`，默认 `local`。
- `local` 让 CDP 仅监听 `127.0.0.1`，适用于本机或独立 SSH 隧道。
- `lan` 默认监听全部接口，也允许 `--listen-address` 指定接口；每次显式使用时警告 CDP 无认证且可完全控制浏览器。
- 启动后验证 `/json/version`，报告成功前确认 CDP 可用。
- `profile stop` 只停止命令行明确引用目标 Profile 路径的浏览器进程，不停止日常浏览器或未知 Chrome/Edge。

### 独立 SSH 配置

- SSH 与浏览器生命周期独立；任何浏览器 create/start/stop 都不隐式建立或关闭 SSH 隧道。
- 保存命名 SSH 配置，引用一个 Profile，并记录转发方向、SSH target、Agent 端口、SSH config 路径和详细日志选项。
- `local-forward` 生成供远端 Agent 执行的 `ssh -4 -N -o ExitOnForwardFailure=yes -L <agentPort>:127.0.0.1:<cdpPort> <windowsTarget>`；Windows CLI 不控制对面的 SSH 进程。
- `reverse-forward` 由 Windows 执行 `ssh -4 -N -o ExitOnForwardFailure=yes -R <agentPort>:127.0.0.1:<cdpPort> <agentTarget>`，可独立 start/status/stop。
- `ssh info <name>` 无副作用地输出 SSH 命令、CDP endpoint、`playwright-cli attach` 命令、JSON 配置和中文 Agent Prompt。
- Agent Prompt 明确要求连接现有浏览器，不创建新的浏览器实例。

### 注册表、发现与快捷方式

- 默认注册表为 `D:\browser-debug-profiles\registry.json`，分别保存 Profiles 和 SSH 配置。
- 修改已有注册表前创建同目录可读时间戳 `.bak`，再原子写入。
- `profile list/get/status` 和 `ssh list/get/status` 提供人类可读输出；`--json` 输出稳定 `schemaVersion = 1` 对象。
- 创建 Profile 时生成 Windows Local `.lnk`，默认位于当前用户桌面，可覆盖目录。
- 快捷方式执行 `browser-debug.ps1 profile start <name>`，默认只开放本机 CDP；可随后通过 `profile shortcut <name> --mode lan` 单独增加 LAN 快捷方式，不替换已有 Local 快捷方式。

### 启动帮助页面

- 用户通过 Local 或 LAN 快捷方式成功启动浏览器后，自动打开与该 Profile 和启动模式对应的 HTML 帮助页面。
- 帮助页面是启动完成后生成的静态快照；不启动 Caddy、本地 Web 服务或其他常驻帮助进程。
- 页面参数必须来自本次启动的实际结果，包括实际 CDP 端口、监听模式、监听地址、CDP 版本、当时可用的 LAN 地址和关联 SSH 配置；通配监听列出每个候选 LAN IPv4，不静默选择唯一首地址；页面打开后不再从 registry 动态刷新这些参数。
- 页面集中展示 CDP endpoint、`/json/version` 探测地址、`playwright-cli attach` 命令、Profile 路径、端口、监听模式、局域网安全提示、相关 SSH 配置和可复制的中文 Agent Prompt。
- 页面不得展示 Cookie、密码、Token 或其他浏览器敏感数据。
- 页面生成与打开失败不能把已成功启动的浏览器误报为启动失败。
- 同模式 Profile 已运行时再次点击快捷方式，复用当前实例并根据当前实际运行参数重新生成快照；请求模式与实际模式不同时拒绝，提示先停止 Profile 再切换模式。

## Acceptance Criteria

- [ ] 可分别创建 Chrome 和 Edge Profile，默认路径为 `D:\browser-debug-profiles\<name>`，创建动作不启动浏览器。
- [ ] 创建 Profile 默认克隆所选浏览器 User Data 的登录状态和扩展；可显式指定来源，并可用 `--without-extensions` 排除扩展相关目录。
- [ ] 来源浏览器运行中或存在锁文件时拒绝克隆；复制失败不写 registry，也不留下最终 Profile 路径。
- [ ] 可在 Profile 停止后持久修改 CDP 端口；快捷方式和 SSH 信息随后使用新端口。
- [ ] `profile start` 默认 `local`，可显式使用 `lan`；endpoint 与实际监听一致。
- [ ] Edge launcher 退出 0 但目标 Profile 子进程接管时，start 等待 owned 进程和 CDP 就绪后成功，不返回误导性的立即退出错误。
- [ ] `lan` 每次启动都显示无认证风险，不因历史状态被静默复用。
- [ ] 桌面快捷方式可再次启动同一 Profile，并始终使用 `local`。
- [ ] 可为同一 Profile 单独增加 LAN 快捷方式；Local 与 LAN 快捷方式名称和启动模式明确，互不覆盖。
- [ ] 通过快捷方式启动后会打开帮助页面，页面配置与实际 Profile、启动模式、SSH 信息一致，并提供可复制的远端 Agent 连接内容。
- [ ] 同模式快捷方式可复用已运行实例并重新生成帮助快照；不同模式快捷方式不会静默复用或改变现有监听方式。
- [ ] `profile status/stop` 不会把未知端口占用或日常浏览器误判为本工具进程。
- [ ] SSH 配置生成的 `-L`/`-R` 命令、endpoint、Playwright 命令和 Agent Prompt 相互一致。
- [ ] SSH start/stop 不隐式操作浏览器；浏览器 start/stop 不隐式操作 SSH。
- [ ] `browser-debug completion powershell` 可注册补全；资源、动作、选项、枚举和动态名称均可通过 Tab 补全。
- [ ] 补全器只读本地注册表，不访问网络、不探测端口、不启动进程；重复注册保持幂等。
- [ ] Pester 覆盖 CLI 解析、帮助、补全、注册表、端口修改、Local/Lan、浏览器所有权、SSH 两种方向、快捷方式和 JSON 输出，不启动真实用户浏览器或 SSH。

## Out of Scope

- macOS、Linux、WSL、Firefox、WebKit 或其他非 Chromium 浏览器。
- 管理或复用用户日常 Chrome/Edge Profile。
- 自动安装或升级远端 `playwright-cli`。
- 自动配置 Windows OpenSSH Server、Tailscale、防火墙或路由器端口映射。
- 删除 Profile 数据目录；首版不提供 remove/delete。

## Technical Notes

- Chrome 136+ 远程调试要求非默认 `user-data-dir`，独立 Profile 满足该约束。
- CDP 没有内建认证，因此 `lan` 不能成为默认值。
- 快捷方式复用 `psutils/modules/win.psm1` 的 `New-Shortcut`。
