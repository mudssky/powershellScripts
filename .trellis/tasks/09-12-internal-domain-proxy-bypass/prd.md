# Shell 与 PowerShell 内网域名代理绕过

## Goal

统一 Bash/Zsh `proxy` 与 PowerShell `Set-Proxy` 的私网绕过合同，使 `.internal` 域名在启用公网代理时仍保持直连；本任务不部署或配置代理服务本体。

## Background

- `shell/shared.d/proxy.sh` 的 `_PM_NO_PROXY` 与 `psutils/modules/proxy.psm1` 的 `$NoProxyList` 当前都包含 loopback、RFC1918、`macmini`、`.ts.net` 和 `100.64.0.0/10`，但缺少 `.internal`。
- 默认代理环境访问 `ai-gateway.internal` 会进入 loopback proxy 并返回 502；强制 direct 返回 200。
- Shell 与 PowerShell 维护两份相同语义常量，若只修一处会造成终端行为漂移。

## Requirements

- Bash/Zsh 与 PowerShell 默认绕过列表同时加入 `.internal`，继续设置大小写 `NO_PROXY`/`no_proxy`。
- 不枚举单个服务域名；整个受管 `.internal` zone 遵循直连合同。
- 保留现有 loopback、RFC1918、`macmini`、`.ts.net` 和 `100.64.0.0/10` 条目，不改变代理 host、port、自动启用或 Docker 子命令行为。
- PowerShell Pester 测试验证公开 `Set-Proxy on` 的可观察环境变量；Shell 使用 syntax/focused smoke 验证公开 `proxy on` 行为。
- 明确 `.internal` 是 curl/多数运行时使用的后缀写法；macOS System Configuration 使用 `*.internal`，属于其它仓库/任务，不在这里写系统配置。
- 新值只影响重新执行 `proxy on` 或新启动的进程；不重启 Orca/OMP，不修改当前系统代理。

## Acceptance Criteria

- [ ] `proxy on` 后 `NO_PROXY` 与 `no_proxy` 相等，并包含 `.internal`、`macmini`、`.ts.net` 和 `100.64.0.0/10`。
- [ ] `Set-Proxy -Command on` 后大小写变量满足相同合同。
- [ ] 在临时 shell 环境中启用代理后，`.internal` 请求被 curl 判定为 direct；公网请求仍按代理变量处理。
- [ ] Shell syntax/focused smoke、`proxy.Tests.ps1`、仓库规定的 QA/Pester 门禁与 `git diff --check` 通过。
- [ ] 修改仅落在 canonical shell/PowerShell实现及必要测试，不触碰本机生成配置、代理服务或系统 network settings。

## Out of Scope

- 安装、部署、升级或切换 Clash/mihomo/其它代理。
- macOS/Windows GUI 系统代理 bypass、浏览器扩展、PAC、TUN、fake-IP 与 split DNS。
- self-hosted-compose、Technitium、Traefik、Bifrost 或 Agent 模型配置修改。
