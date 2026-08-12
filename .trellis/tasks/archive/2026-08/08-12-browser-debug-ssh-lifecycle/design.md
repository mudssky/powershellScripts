# Technical Design

## Architecture and Boundaries

新增 `scripts/pwsh/devops/browser-debug/browser-debug-guide.template.html`：

- 保存完整 HTML 文档、CSS、SVG sprite 和复制按钮 JavaScript。
- 使用数量有限且唯一的文本占位符，例如 `{{PAGE_TITLE}}`、`{{STATUS_GRID}}`、`{{LOCAL_SECTION}}`、`{{REMOTE_GUIDANCE}}`、`{{REGISTERED_SSH_SECTION}}`、`{{AGENT_SECTION}}`。
- 模板自身不读取 registry、不执行命令、不拼接未编码数据。

`runtime.ps1` 保留：

- `New-BrowserDebugGuideSnapshot`：生成结构化连接模型。
- `ConvertTo-BrowserDebugGuideHtml`：编码动态值、构造重复卡片片段、读取模板并替换占位符。
- `Write-BrowserDebugGuide`：沿用临时文件加原子替换。

模板路径通过 `Join-Path $PSScriptRoot 'browser-debug-guide.template.html'` 解析，不依赖 CLI 当前目录。渲染前检查模板存在；渲染后检查不存在未解析的 browser-debug 占位符。

## Data Model

`New-BrowserDebugGuideSnapshot` 调整为：

- `endpoint`、`probeUrl`、`playwrightCommand`：始终使用实际可探测的 `127.0.0.1:<actualPort>`。
- `mode`、`listenAddress`：保留启动请求元数据，但页面不把它们当作监听证明。
- `nativeLanReachable = false`：当前 Windows Chrome/Edge 已验证事实。
- `tailscale`：仅 LAN 模式构造，包含按实际端口生成的 enable/status/disable 命令和 endpoint 模板。
- `sshLocalForward`：仅 LAN 模式构造，包含远端执行命令、远端本地 endpoint、探测 URL、Playwright attach 和 Agent Prompt。
- `sshConfigurations`：继续包含 registry 中显式登记的 SSH 配置。
- `directConnections`：停止由网卡地址推导 Ready endpoint，删除相应 LAN Agent Prompt。

## Rendered UX

Local 页面：

1. **本机 CDP — Ready**：`127.0.0.1:<port>`。
2. **已登记 SSH configurations**：若存在则继续展示。
3. **Agent Prompts**：只包含真实可用连接。

LAN 页面：

1. **本机 CDP — Ready**：`127.0.0.1:<port>`。
2. **原生 LAN 直连 — Unavailable**：说明 Chrome/Edge 当前没有实际 LAN listener，LAN 快捷方式只是启动请求，不能作为可达性证明。
3. **Tailscale Serve — 推荐，多设备共享**：
   - 启用：`tailscale serve --bg --yes --tcp=<port> tcp://127.0.0.1:<port>`
   - 查看：`tailscale serve status`
   - 关闭当前端口：`tailscale serve --tcp=<port> off`
   - 访问：`http://<本机 MagicDNS 或 Tailscale IP>:<port>`
4. **SSH local forward — 单设备临时连接**：
   - `ssh -N -o ExitOnForwardFailure=yes -L <port>:127.0.0.1:<port> <windows-user>@<windows-host>`
   - 远端访问 `http://127.0.0.1:<port>`。
5. **已登记 SSH configurations**：保持现有高级配置输出。
6. **Agent Prompts**：只生成本机、Tailscale、SSH 的真实方案，不生成 LAN IPv4 直连 Prompt。

## Shortcut Contract

不修改快捷方式实现：

- 保留 `<profile>.lnk` 与 `<profile>-LAN.lnk`。
- 保留现有 Target、Arguments、WorkingDirectory、IconLocation 与 registry 路径。
- LAN 能力边界只在其打开的 LAN 模式 HTML 中表达。

## Compatibility

- 不改变 CLI 参数和 JSON schema。
- 不改变快捷方式 current 检查和迁移合同。
- 外部模板属于运行时必要资源；当前 `bin/browser-debug.ps1` 是回源 shim，因此无需复制模板到 `bin/`。
- 指南生成失败仍只追加 warning，不推翻已成功的浏览器启动。

## Security

- Tailscale Serve 仅建议 Tailnet 内使用，并明确受 ACL/Grants 控制；不建议 Funnel。
- SSH 命令使用 `ExitOnForwardFailure=yes`，不包含密码、密钥路径或真实账号。
- 不自动执行任何网络暴露命令。
- 所有 Snapshot 动态值进入 HTML 前继续使用 `HtmlEncode`。

## Rollback

- 删除外部模板并恢复原渲染函数即可回滚页面拆分。
- 本次不写入 Tailscale、SSH、快捷方式或 registry 状态，没有网络与桌面状态回滚。
