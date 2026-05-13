# OpenSSH 客户端选项语义确认

## 来源

* Context7：`/openssh/openssh-portable`
* 查询主题：`ssh_config RemoteForward ExitOnForwardFailure ServerAliveInterval ServerAliveCountMax TCPKeepAlive RequestTTY RemoteCommand VS Code Remote SSH 多连接 端口转发配置建议`

## 结论

* `RemoteForward`/`ssh -R` 用于把远端监听端口转发到客户端侧可访问的目标地址与端口。
* `ServerAliveInterval` 与 `ServerAliveCountMax` 是客户端侧保活配置；例如 `60` 与 `3` 表示每 60 秒发送一次服务端保活探测，连续 3 次无响应后客户端认为连接不可用。
* `ConnectTimeout` 只影响建立连接阶段，适合避免网络异常时长时间卡住，不用于保持已建立连接。
* `ExitOnForwardFailure yes` 可让端口转发绑定失败时直接失败，避免进入“SSH 已连接但代理未建立”的半成功状态；本轮先关闭 `RemoteForward`，所以不作为活跃配置重点。

## 对本仓库任务的约束

* 当前目标是定位问题，不宜同时修改 zellij Host 的生命周期参数。
* VS Code Remote SSH 常会建立多条连接，文档应避免把同一个 `RemoteForward 7890` 放进 VS Code Host 作为默认方案。
* 如果后续需要恢复代理，优先使用专用隧道 Host 或临时 `ssh -N -R`，并配合 `ExitOnForwardFailure yes` 做显性失败。
