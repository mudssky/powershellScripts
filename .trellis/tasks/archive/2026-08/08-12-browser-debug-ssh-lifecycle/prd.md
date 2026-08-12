# 改进 browser-debug LAN 连接指南

## Goal

将 browser-debug 的大段 HTML 从 PowerShell 逻辑中抽成独立模板；LAN 快捷方式打开的连接指南明确说明 Windows Chrome/Edge 当前实际只监听回环地址，并提供 Tailscale Serve 与远端 `ssh -L` 两种可复制的远程 CDP 方案。

## User Value

用户双击 LAN 快捷方式后，可以直接看到真实能力边界并复制适合自己的远程连接命令；不会再把 `--remote-debugging-address` 的请求值误认为实际可用的 LAN endpoint，也无需为每台 Tailnet 设备分别创建 SSH 隧道。

## Confirmed Facts

- `scripts/pwsh/devops/browser-debug/runtime.ps1:852-947` 的 `ConvertTo-BrowserDebugGuideHtml` 当前内联整份 HTML、CSS 和 JavaScript，运行时由 `Write-BrowserDebugGuide` 写到 registry 同级 `guides/<profile>-<mode>.html`。
- 该模板已足够大，且页面结构/样式与 PowerShell 快照和转义逻辑混在一起；拆成同模块目录下的独立模板文件可以降低维护成本，同时保留 PowerShell 负责动态数据、HTML 编码和原子写入。
- 当前 Chrome 与 Edge 在本机 Windows 上，即使传入 `--remote-debugging-address=0.0.0.0` 或物理 IPv4，实际也只监听 `127.0.0.1:<cdpPort>`。
- `New-BrowserDebugGuideSnapshot` 当前根据请求模式生成 `directConnections`，会把 LAN IPv4 渲染成可直连 endpoint；这与真实监听结果不一致。
- 当前 Local/LAN 快捷方式都执行 `profile start <name> --mode <mode> --open-guide --yes`，LAN 文件名为 `<profile>-LAN.lnk`。
- 用户决定保留两个快捷方式现有名称、路径和参数；只在 LAN 模式打开的 HTML 中显示远程 CDP 直连失效提示。
- Tailscale 1.102.2 支持持久 TCP forwarder：`tailscale serve --bg --tcp=<port> tcp://127.0.0.1:<port>`。Serve 只在 Tailnet 内提供服务，访问权限仍受 Tailscale ACL/Grants 控制。
- 本机 Tailscale Serve 已有其他端口配置；新增 CDP TCP 端口不应使用 `serve reset` 或影响现有服务。
- 本机 Windows OpenSSH Server 正在监听 TCP 22；远端设备可执行 `ssh -L <localPort>:127.0.0.1:<cdpPort> <user>@<windows-host>`。
- 现有 registry SSH 配置继续作为高级、显式配置展示；本次不联动浏览器与 SSH 生命周期。

## Requirements

- R1：新增独立 HTML 模板文件，承载页面骨架、CSS、SVG 和 JavaScript；PowerShell 仅构造已编码的动态片段并替换固定占位符。
- R2：模板路径必须相对 browser-debug 模块解析，不依赖调用者当前工作目录；模板缺失或占位符异常时返回可诊断错误，并沿用现有 guide warning 降级合同。
- R3：指南始终以实际可探测的 `127.0.0.1:<cdpPort>` 作为浏览器原生 CDP endpoint，不再把网卡 IPv4 列为已就绪的直连 endpoint。
- R4：仅 LAN 模式页面显著标明：当前 Windows Chrome/Edge 的远程调试地址参数未产生真实 LAN listener，LAN 直连不可用；`mode`/`listenAddress` 只表示启动请求，不表示远程可达。
- R5：LAN 模式页面新增 Tailscale Serve 方案，提供按实际 CDP 端口生成的启用、查看和关闭命令，并说明 Tailnet 访问仍受 ACL/Grants 控制。
- R6：LAN 模式页面新增远端 `ssh -L` 方案，提供按实际 CDP 端口生成的命令、远端本地 endpoint、探测 URL和 Playwright attach 命令；主机/用户以明确占位符表示。
- R7：保留 registry 中已有 SSH 配置的展示，避免破坏现有 `browser-debug ssh` 合同；通用 `ssh -L` 方案与已登记配置分区展示。
- R8：Local 模式页面维持本机连接用途，不增加 LAN 失效警告或通用远程方案噪声。
- R9：两个快捷方式的文件名、Target、Arguments、WorkingDirectory、IconLocation 和 registry 登记均保持不变。
- R10：Tailscale 命令不得清空或覆盖本机其他 Serve 端口；关闭示例只关闭当前 CDP TCP 端口。
- R11：所有动态 HTML 内容继续编码，不得把 Cookie、密码、Token、标签页或历史记录写入指南。

## Acceptance Criteria

- AC1：仓库存在独立 browser-debug HTML 模板；`runtime.ps1` 不再内联完整 `<html>…</html>` 页面。
- AC2：从任意工作目录执行 `profile start <name> --open-guide` 均能解析模板并生成 `guides/<profile>-<mode>.html`。
- AC3：生成页面只把 `127.0.0.1:<actualPort>` 标为浏览器原生 Ready endpoint；不生成虚假的 `http://<LAN IPv4>:<port>` Ready 卡片或 Agent Prompt。
- AC4：LAN 页面显著显示“远程 CDP 直连当前不生效”，并引导选择 Tailscale Serve 或 `ssh -L`；Local 页面不显示该警告区。
- AC5：LAN 页 Tailscale 区域包含 `serve --bg --tcp`、`serve status` 和精确端口 `off` 命令，端口来自实际启动结果。
- AC6：LAN 页 SSH 区域包含远端执行的 `ssh -N -o ExitOnForwardFailure=yes -L` 命令，以及对应 `127.0.0.1:<port>` 的探测与 Playwright 命令。
- AC7：已有 registry SSH 配置仍正常渲染；动态内容编码、复制控件、无外部页面依赖和敏感字段排除测试继续通过。
- AC8：两个现有快捷方式无需迁移，属性和 registry 路径保持不变。
- AC9：Browser Debug 专项 Pester、Profile 窄测、`pnpm test:pwsh:all` 与 `pnpm qa` 通过。

## Out of Scope

- 不自动执行或持久化 Tailscale Serve 配置。
- 不让快捷方式自动启动/停止 SSH。
- 不修改、重命名或删除现有 Local/LAN 快捷方式。
- 不实现 Windows Device Portal、TCP proxy 或 `netsh portproxy`。
- 不移除现有 `lan` CLI 模式，也不改变 Profile 端口、浏览器类型或 User Data 路径。
- 不修改 Tailnet ACL/Grants 或 OpenSSH 认证配置。
