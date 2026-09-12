# Implement — Shell 与 PowerShell 内网域名代理绕过

## 实施清单

- [x] 将任务状态置为 `in_progress`，补齐 design、implement 与 context manifests。
- [x] 在 Shell `_PM_NO_PROXY` 中加入 `.internal`，保留既有 loopback、RFC1918、`macmini`、`.ts.net` 与 `100.64.0.0/10`。
- [x] 在 PowerShell `$NoProxyList` 中同步加入 `.internal`，不改变代理 endpoint、自动启用或 Docker 子命令。
- [x] 更新两处相邻注释，说明 `.internal`/`.ts.net` 是域名后缀绕过，CIDR 覆盖直接 IP。
- [x] 扩展现有 Pester 行为测试，通过公开 `Set-Proxy -Command on` 断言完整 loopback、RFC1918、`macmini`、`.internal`、`.ts.net` 与 `100.64.0.0/10` 绕过合同，并保留 `NO_PROXY`/`no_proxy` 相等断言。
- [x] 实现完成，待主会话统一验证。

## 主会话验证

- [x] Shell syntax：`bash -n shell/shared.d/proxy.sh` 与 `zsh -n shell/shared.d/proxy.sh` 通过。
- [x] 隔离 Bash/Zsh smoke：`proxy on` 后大小写变量相等，完整 loopback、RFC1918、`macmini`、`.internal`、`.ts.net` 与 `100.64.0.0/10` 合同存在；curl trace 证明 `.internal` 直连而公网域名进入临时代理。
- [x] Focused Pester：Pester `6.1.0` 下 22 passed、0 failed；直接 PowerShell smoke 同样确认大小写变量与完整合同。
- [x] 仓库门禁：`pnpm qa`（Pester `6.1.0`）143 passed、0 failed，`git diff --check` 与 task validation 通过。`pnpm test:pwsh:all` 的 Linux 983 tests 全通过；macOS host 996 passed、2 个任务外 BrowserDebug shortcut 测试因找不到独立 `pwsh` launcher 失败，与 proxy 变更无关。

## 非目标

不修改当前 shell 环境、macOS System Configuration、Clash/mihomo、代理 host/port、Docker daemon/container 配置、DNS 或任何运行态，也不重启 Orca/OMP。
