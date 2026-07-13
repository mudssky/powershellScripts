# WSL SSH Access

## Scenario: Windows 宿主上的独立 WSL Linux SSH 入口

### 1. Scope / Trigger

- Trigger：修改 `windows/wsl/*WslSshAccess*`、`linux/wsl/prepare-ssh-access.sh` 或对应 Pester/安装文档。
- Scope：现有 Ubuntu/Debian WSL2 的 sshd、Windows portproxy、scoped firewall rule、S4U AtStartup task 和精确 rollback。
- Design intent：Windows SSH/PSRP 与 WSL Linux SSH 使用独立端口和身份；宿主负责稳定入口，客体负责 Linux SSH 策略。

### 2. Signatures

```powershell
powershell.exe -File windows/wsl/Initialize-WslSshAccess.ps1 `
  -Distribution <name> -WindowsUser <user> -LinuxUser <user> `
  [-ListenAddress 0.0.0.0] [-ListenPort 2222] [-GuestPort 22] `
  [-RemoteAddress LocalSubnet,100.64.0.0/10] `
  [-AuthorizedKeyPath <public-key>] [-Apply|-Verify|-Rollback] `
  [-OutputFormat Text|Json]
```

```bash
bash linux/wsl/prepare-ssh-access.sh \
  --operation plan|apply|verify|rollback --user <linux-user> --port <port> \
  [--authorized-key-base64 <base64>] [--output-format json|text]
```

### 3. Contracts

- 默认操作为 Preview；Apply/Rollback 必须显式选择，且 Windows host 写操作要求管理员、guest 写操作要求 root。
- Windows PowerShell 5.1 入口、模块和 runtime helper 含中文时必须为 UTF-8 BOM，并通过 parser 测试。
- guest 仅支持 Ubuntu/Debian WSL，配置 `PasswordAuthentication no`、`KbdInteractiveAuthentication no`、`PermitRootLogin no`、`PubkeyAuthentication yes` 和精确 `AllowUsers`。
- authorized key 只管理固定 marker 行；不接受私钥，不删除其他 key。状态只输出 fingerprint，不输出公钥正文。
- 每个 distribution 使用独立 config、runtime helper、task 和 firewall rule 名称，避免 rollback 影响其他 distribution。
- AtStartup task 固定 S4U、Highest、单个 boot trigger 和固定 PowerShell action。不得保存 Windows 密码/PIN，也不得降级为依赖自动登录的 AtLogOn。
- runtime helper 启动指定 distribution/`ssh.service`，读取当前 WSL IPv4，并只刷新精确 listen address/port 的 v4tov4 portproxy。
- firewall rule 只允许显式 remote allowlist；不改变 profile 启停状态。全部 profile 已关闭时不创建 rule，host verify 将该项视为 skipped/satisfied。
- rollback 只删除本功能命名资源和精确 portproxy；保留 Windows OpenSSH、PSRP、Tailscale、`openssh-server`、host keys 和其他 firewall/task/portproxy。
- JSON stdout 只有一个 schema v1 document；退出码为成功/Preview 0、执行失败 1、参数无效 2、Blocked 10。

### 4. Validation Matrix

| Condition | Expected Behavior |
|---|---|
| Windows 路径传给 `wsl.exe` | native argv 必须保留反斜杠，`wslpath` 返回有效 guest 路径 |
| Preview | 不创建 task、portproxy、firewall rule 或 guest 配置 |
| 第二次 Apply | host 与 guest 均 `Changed=false` |
| WSL IPv4 变化 | runtime 只替换相同 listen address/port 的 portproxy |
| firewall profiles 全关闭 | 不启用 profile、不创建 rule，verify 不因此失败 |
| 非 WSL / 非 Ubuntu-Debian | Blocked/10 |
| Apply 无管理员/root | Blocked/10 |
| Rollback | 仅删除固定命名资源，之后可重新 Apply |

### 5. Tests Required

- Pester：资源名、公钥/端口、CIDR 规范化、Preview/幂等/rollback plan、非 Windows JSON、UTF-8 BOM、parser 和 wildcard 删除拒绝。
- Bash：`bash -n linux/wsl/prepare-ssh-access.sh`；fixture plan 输出单文档 JSON。
- Gates：`pnpm qa`、`pnpm test:pwsh:all`、`git diff --check`。
- 实机：Windows Preview/Apply/二次 Apply/Verify；WSL terminate 恢复；外部 SSH；无登录 reboot；rollback 后 reapply。
