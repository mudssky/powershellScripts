# Implement — browser-debug 指南自动探测 Tailscale 地址

## 执行清单（按序）

1. `scripts/pwsh/devops/browser-debug/runtime.ps1`
   - 新增 `Resolve-BrowserDebugTailscaleAddress`（可执行文件定位 + `status --json` 3s 超时执行 + CGNAT IPv4/DNSName/HostName 解析 + 全失败回退 `$null`，支持 `-StatusInvoker` 注入）。
   - `New-BrowserDebugGuideSnapshot` LAN 分支接入探测：endpoint/hostnameEndpoint/aliasEndpoint/detected 字段，派生 probeUrl、playwrightCommand、agentPrompt。
   - `ConvertTo-BrowserDebugGuideHtml` LAN 区块：条件渲染 `主机名别名 endpoint`、`MagicDNS 别名 endpoint` 行与未检测提示。
2. `tests/BrowserDebugProfile.Tests.ps1`
   - 探测函数单测：可执行文件缺失、invoker 抛错/超时/垃圾 JSON → `$null`；样例 JSON → CGNAT IPv4 选取、IPv6 忽略、DNSName 去尾点、HostName 缺失回退与字符集校验。
   - 快照测试：检测成功（mock 返回 ipv4+域名）断言 endpoint/probe/attach/prompt 使用 IPv4 且 aliasEndpoint 正确；检测失败断言占位符与 `$null` 别名；改造 `tests/BrowserDebugProfile.Tests.ps1:805` 负向断言（放行 100.64/10，仍禁 172.*/192.168.*/非 CGNAT 100.x）。
   - 渲染测试：别名行出现/消失、未检测提示出现/消失、别名值 HTML 编码。
   - 原有 `enableCommand/statusCommand/disableCommand` 精确断言与敏感字段排除断言保持。
3. `.trellis/spec/pwsh-scripts/package/browser-debug-cli.md`
   - §3 合同补探测（只读、超时、回退、endpoint 形式）；§4 矩阵补"未安装/超时 → 占位符+提示且指南仍生成"；§5 Good/Bad 同步；§6 测试要求补探测覆盖。
4. `docs/scripts-index.md:187` 修正 tailscale 相关表述（现状段落还带旧的按候选 LAN IPv4 枚举说法，一并按实际行为修正该句）。
5. 收尾检查 `shell/shared.d/browser-debug.sh` 确认无 endpoint 逻辑需联动。

## 验证命令

- `pnpm test:pwsh:all`（涉及 `scripts/pwsh/**`、`tests/**/*.ps1`，必须执行）
- `pnpm qa`（提交前）
- 若本机 Docker 不可用：`pnpm test:pwsh:full` 并在提交说明中注明 Linux 覆盖依赖 CI/WSL
- 针对性窄测：Pester `BrowserDebugProfile.Tests.ps1` 的"启动帮助页" Describe 块

## 风险文件与回滚点

- 风险集中在 `runtime.ps1`（快照/渲染核心）；每步可独立 revert。
- registry schema、快捷方式、SSH 命令合同不动。

## start 前检查

- [ ] 用户已明确批准最终规划摘要
- [ ] `prd.md`/`design.md`/`implement.md` 就绪
