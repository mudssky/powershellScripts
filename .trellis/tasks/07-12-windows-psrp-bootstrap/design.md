# Windows PSRP Bootstrap 设计

## 模块边界

- `windows/bootstrap/WindowsRemotePsRemoting.psm1`：纯验证/计划函数与受控系统操作。
- `windows/bootstrap/Enable-WindowsRemotePsRemoting.ps1`：参数解析、管理员边界、Text/Json 输出和退出码。
- `tests/WindowsRemotePsRemoting.Tests.ps1`：优先测试纯计划合同，系统 cmdlet 使用 fixture/mocks。
- `windows/INSTALL.md`：记录 SSH → PSRP 执行与 rollback 命令。

## 数据流

```text
显式 IP 或 Tailscale adapter/tailscale.exe
  -> CGNAT 地址校验
  -> 读取托管证书/listener/防火墙状态
  -> 生成固定 action plan
  -> WhatIf 直接输出 Preview
  -> 管理员 apply/rollback
  -> 读取监听地址并输出结构化验证结果
```

## 资源所有权

- 证书 subject 前缀固定为 `CN=powershellScripts-PSRP-`。
- 防火墙 DisplayName 固定为 `powershellScripts PSRP HTTPS`。
- listener 仅在证书属于上述前缀或地址等于本次目标 Tailscale IP 时视为托管资源。
- rollback 不删除其他 HTTPS/HTTP listener、其他证书、防火墙规则或 OpenSSH 资源。

## 失败语义

- 参数/IP/端口错误：参数错误，exit 2。
- 非管理员实际执行、多个 Tailscale IP、外部前置缺失：Blocked，exit 10。
- 系统 cmdlet 或验证异常：Failed，exit 1。
- WhatIf、已满足、成功：exit 0。

## 安全决策

- 不调用 `Enable-PSRemoting`，避免其创建 wildcard HTTP listener 或修改防火墙全局行为。
- 只启动/设为自动启动 WinRM 服务，显式保持 `AllowUnencrypted=false`。
- listener 使用精确 `Address=<tailscale-ip>`；验证拒绝 `*`、`0.0.0.0`、`::`。
- 防火墙 rule 同时限制 `LocalAddress=<tailscale-ip>`、`RemoteAddress=100.64.0.0/10`、`LocalPort=5986`。
