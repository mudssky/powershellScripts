# WSL SSH 宿主与客体入口设计

## Files

```text
linux/wsl/
  prepare-ssh-access.sh
windows/wsl/
  Initialize-WslSshAccess.ps1
  Invoke-WslSshAccessRefresh.ps1
tests/
  WslSshAccess.Tests.ps1
```

`prepare-ssh-access.sh` 是唯一 guest package/sshd/authorized_keys owner。Windows orchestrator 负责验证参数、调用 guest helper、安装稳定 runtime helper/config、注册 task、配置 portproxy/firewall 和汇总 JSON。

## Guest Contract

- 参数：operation、Linux user、guest port、authorized key file/base64。
- Preview 不要求 root；Apply/Rollback 必须 root。
- apt 只安装 `openssh-server`；写固定 `/etc/ssh/sshd_config.d/90-powershellscripts-wsl-ssh.conf`。
- authorized key 使用固定 comment/marker 精确管理，其他行保留。
- enable/start/restart `ssh.service`，Verify 输出 package/config/service/listener/key fingerprint。

## Host Contract

- 参数：distribution、Windows user、Linux user、listen address/port、guest port、remote addresses、authorized key path、Apply/Rollback/OutputFormat。
- runtime config 位于 `%ProgramData%\powershellScripts\wsl-ssh\<safe-id>.json`，不含 key 正文。
- scheduled task `powershellScripts-WSL-SSH-<safe-id>` 使用 AtStartup、S4U、Highest；action 只调用稳定 refresh helper。
- refresh helper 启动 distro、等待 guest ssh、解析首个有效 WSL NAT IPv4，并只替换 exact listen address/port 的 portproxy。
- firewall rule 使用固定 name，允许配置的 remote addresses；所有 profile 已关闭时保持关闭并报告 Skipped。

## Result

单文档 schema v1 至少包含 Operation、Status、ExitCode、Changed、Distribution、WindowsUser、LinuxUser、ListenAddress、ListenPort、GuestPort、WslIPv4、Guest、ScheduledTask、PortProxy、Firewall、Errors。JSON 不含 key 正文。

## Rollback

先删除 exact host managed resources，再调用 guest rollback 删除 managed drop-in/key marker。任何一步不得通过 wildcard 删除非本功能资源。openssh-server 与 host keys 保留。
