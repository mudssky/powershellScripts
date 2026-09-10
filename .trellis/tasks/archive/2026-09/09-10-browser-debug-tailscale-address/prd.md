# browser-debug 指南增加 Tailscale 地址

## Goal

LAN 模式启动帮助页不再让用户手抄 `http://<本机 MagicDNS 或 Tailscale IP>:<port>` 占位符：生成指南时自动探测本机 Tailscale 地址并生成可直接复制的 Tailnet endpoint 及配套探测地址、Playwright attach、Agent Prompt，未检测到时保持现有占位符并给出提示。

## Background

- 现状：`scripts/pwsh/devops/browser-debug/runtime.ps1:1204` 中 `New-BrowserDebugGuideSnapshot` 在 LAN 模式将 endpoint 写死为占位符，`probeUrl`/`playwrightCommand`/`agentPrompt` 全部基于该占位符（runtime.ps1:1204-1213）。
- LAN/ssh 交接仅 Windows 支持；LAN 指南由快照（`New-BrowserDebugGuideSnapshot`）→ 渲染（`ConvertTo-BrowserDebugGuideHtml`）→ 原子写入（`Write-BrowserDebugGuide`）构成（spec：`.trellis/spec/pwsh-scripts/package/browser-debug-cli.md`）。
- spec Bad case 禁止自动执行网络暴露命令（`tailscale serve` 只能作为可复制文本）；只读 `tailscale status --json` 不受限。
- guide 生成失败只追加 warning、不影响启动结果（现有合同，必须保持）。
- 本机 Windows 主机已加入 Tailnet 且 MagicDNS 已启用（`archive/ai/skills/dev/powershellscripts-ops/references/deprecated/windows-openssh.md:74`）。
- `tests/BrowserDebugProfile.Tests.ps1:805` 现有负向断言禁止页面出现 `http://100.*:21229`，与本需求冲突，需按 CGNAT 范围（100.64.0.0/10）重新划界。
- `docs/scripts-index.md:187` 关于指南内容的描述已过时（仍在描述按候选 LAN IPv4 枚举 endpoint），需一并修正 tailscale 相关表述。

## Requirements

### R1 自动探测 Tailscale 地址（默认决策：IPv4 为主 + 域名别名）

- 新增只读探测：定位 `tailscale` 可执行文件并运行 `tailscale status --json`（进程 3 秒超时），解析 `Self.TailscaleIPs` 中 100.64.0.0/10 的 IPv4、`Self.DNSName`（去尾点）与 `Self.HostName`（为空时取 DNSName 首段）。
- 探测全程不 throw：可执行文件缺失、daemon 不可用、非零退出、超时、JSON 异常均回退为"未检测到"。

### R2 快照与指南使用真实地址

- 检测成功：`tailscale.endpoint`/`probeUrl`/`playwrightCommand`/`agentPrompt` 使用 `http://<Tailnet IPv4>:<实际端口>`；检测到主机名（如 `macmini`，用户确认可读性最高）时快照携带 `hostnameEndpoint`，检测到 MagicDNS 域名时携带 `aliasEndpoint`，指南在 Tailnet endpoint 下依次追加"主机名别名 endpoint""MagicDNS 别名 endpoint"可复制字段。
- 检测失败：endpoint 等保持现有占位符，指南 Tailscale 区块追加"未检测到 Tailscale（未安装或未登录）请自行替换"提示，且指南仍成功生成。
- `enableCommand`/`statusCommand`/`disableCommand`（`serve --bg --yes --tcp=<port>` 三条命令）合同保持不变。

### R3 合同与文档同步

- 更新 `.trellis/spec/pwsh-scripts/package/browser-debug-cli.md`：探测合同、错误矩阵、Good/Bad 案例、测试要求。
- 修正 `docs/scripts-index.md:187` 中与 tailscale 地址相关的过时描述。
- Ready endpoint 仍只标 `127.0.0.1:<actualPort>`；页面不自动执行任何命令（维持 spec）。

## Acceptance Criteria

- [ ] LAN 指南在装有并登录 Tailscale 的机器上生成的 endpoint/探测/attach/Prompt 均为 `http://<100.64/10 IPv4>:<实际端口>`，可直接复制使用，无需手工替换。
- [ ] 检测到主机名时页面出现"主机名别名 endpoint"（如 `http://macmini:<port>`）可复制字段；检测到 MagicDNS 域名时出现"MagicDNS 别名 endpoint"字段；值含 `<`/`>` 等字符时正确 HTML 编码。
- [ ] 未安装/未登录/超时/解析失败时：endpoint 为原占位符、页面出现未检测提示、指南照常生成且仅追加 warning。
- [ ] `tailscale serve` 三条命令文本与现状逐字一致。
- [ ] 页面负向断言更新后仍禁止 172.*/192.168.*/非 CGNAT 100.x 作为 endpoint；100.64.0.0/10 仅出现在 Tailscale Serve 区块。
- [ ] `pnpm test:pwsh:all`（Browser Debug 专项 Pester 至少全绿）与 `pnpm qa` 通过。

## Out of Scope

- 不自动执行 `tailscale serve` 等网络暴露命令。
- 不改动 SSH local forward 区块 `<windows-user>@<windows-host>` 占位符。
- 不改变 Local 模式指南降噪合同、原生 LAN 直连结论与 `--remote-debugging-address` 行为。
- 不改动 registry schema、快捷方式与 SSH 生命周期合同。
