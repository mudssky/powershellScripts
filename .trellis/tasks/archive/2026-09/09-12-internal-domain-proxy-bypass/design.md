# Design — Shell 与 PowerShell 内网域名代理绕过

## 变更边界

- 行为缺口：公开 `proxy on` 与 `Set-Proxy -Command on` 生成的默认绕过列表缺少 `.internal`，导致受管内网域名可能误走公网代理。
- 行为归属：分别位于 `shell/shared.d/proxy.sh` 的 `_PM_NO_PROXY` 与 `psutils/modules/proxy.psm1` 的 `$NoProxyList`；两处是不同终端运行时的 canonical 常量，需要同步修改。
- 必要文件：更新两处实现常量及相邻说明；扩展现有 `psutils/tests/proxy.Tests.ps1` 行为断言；补齐本任务规划和上下文清单。
- 明确不做：不部署或切换代理服务，不修改代理 host/port、自动启用、Docker 子命令、系统代理、DNS、Orca/OMP 或任何运行态。

## 行为合同

- 默认列表保留 loopback、RFC1918、`macmini`、`.ts.net` 与 `100.64.0.0/10`，仅新增 `.internal`。
- `.internal` 与 `.ts.net` 使用 curl/多数运行时认可的点前缀后缀匹配写法；CIDR 条目覆盖直接访问的私网 IP。
- Shell 与 PowerShell 开启代理时继续同时设置大小写 `NO_PROXY`/`no_proxy`，且两者值相等。
- 新值只在重新执行开启命令或加载更新后的脚本后生效。

## 验证边界

- Pester focused 测试从公开 `Set-Proxy -Command on` 观察完整 loopback、RFC1918、`macmini`、`.internal`、`.ts.net` 与 `100.64.0.0/10` 绕过合同，并验证大小写变量一致。
- Shell 不增加源码文本断言；由主会话在隔离子 shell 中执行 syntax 与公开 `proxy on` smoke。
- 不发起真实网络、Docker、系统代理或服务重启操作。
