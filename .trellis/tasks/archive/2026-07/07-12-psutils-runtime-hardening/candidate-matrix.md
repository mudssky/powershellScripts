# psutils 运行时加固候选矩阵

| 候选 | 触发条件与证据 | 实际影响 | 结论 | 计划处理 |
|---|---|---|---|---|
| `Set-SSHKeyAuth` 非空 `Passphrase` | `ssh-keygen -N $Passphrase` 把口令作为原生进程参数 | 同机进程检查工具可能读取口令；默认值 `'""'` 还会产生错误语义 | Fix | 拒绝非空字符串口令；新增显式交互提示模式；默认只传空口令 |
| `Set-SSHKeyAuth` 使用 `USERPROFILE` | macOS/Linux 下变量可能为空，当前路径退化为根目录下 `.ssh` | 密钥写入错误目录或直接失败 | Fix | 使用 PowerShell 跨平台 `$HOME`，并在缺失时明确失败 |
| SSH 目标参数 | 用户名或主机名以选项前缀、空白或 `@` 进入 native 参数 | 可能形成错误的 ssh 参数边界 | Fix | 在执行 native command 前验证目标组成部分 |
| `Invoke-FzfHistorySmart` 动态执行 | 用户在 fzf 中按 `Ctrl+E`，输入来自本地 PSReadLine 历史 | 行为本身就是执行历史命令；改成其他动态调用不会降低权限 | Documented Exception | 保留 `Invoke-Expression`，增加局部分析器说明、帮助边界和“仅 Ctrl+E 执行”测试 |
| `Get-HistoryCommandRank` 历史路径 | 路径硬编码为 Windows `USERPROFILE/AppData` | macOS/Linux 产生文件不存在错误 | Fix | 默认读取 `Get-PSReadLineOption().HistorySavePath`，允许显式路径用于测试和脚本 |
| `env.psm1` 缓存空 catch | 缓存 JSON 损坏或写入失败 | 功能可降级，但无法定位缓存失效原因 | Fix | `Verbose` 记录读取/写入失败，不改变降级结果 |
| `hardware.psm1` 注册表回退空 catch | Windows GPU 注册表读取异常 | 后续探测仍可继续，但回退失败不可诊断 | Fix | `Verbose` 记录失败并继续其他 GPU 探测 |
| `proxy.psm1` auto 空 catch | TCP 探测创建或连接异常 | 自动代理静默失效，并可能遗漏关闭客户端 | Fix | `Verbose` 记录异常，`finally` 关闭客户端 |
| `Wait-ForURL` 重试 catch | URL 在等待期间不可达 | 失败属于预期重试，但 `-Verbose` 无法解释最后一次失败 | Fix | 每次失败写 `Verbose`，保持超时返回 false |
| `Test-PortOccupation` | 非 Windows 没有 `Get-NetTCPConnection` | macOS/Linux 调用产生命令不存在错误 | Fix | 使用跨平台 .NET TCP 连接和监听器快照 |
| `Get-PortProcess` | PID 映射依赖 Windows `Get-NetTCPConnection` | 非 Windows 无可靠内置 PID 映射 | Documented Exception | 明确 Windows-only，缺命令时返回可诊断错误，不引入 `lsof`/`ss` 依赖 |
| `$Matches` 自动变量 | 正则匹配后立即读取捕获组 | PowerShell 标准语义，没有变量遮蔽 | No Issue | 保持现状 |
| 交互命令 `Write-Host` | 代理、SSH、历史选择器显示即时状态 | 属于明确的终端 UI，不是数据 API | Documented Exception | 不批量改写，不全局禁用分析规则 |

## Verification Evidence

- 修改前在 macOS 调用 `Get-HistoryCommandRank -ErrorAction Stop` 会访问 `/AppData/.../ConsoleHost_history.txt` 并产生文件不存在错误。
- SSH 红灯测试确认原实现会接受非空口令、使用 `USERPROFILE` 路径、缺少交互口令模式且不拒绝选项型用户名。
- `PSScriptAnalyzer` 定向审阅后，SSH 口令规则通过局部 `SuppressMessageAttribute` 说明；`Invoke-Expression` 只在历史 `ctrl-e` 分支局部说明，没有全局禁用规则。
- `runtimeHardening.Tests.ps1` 检查 `env`、`hardware`、`network`、`proxy` 不存在完全空的 catch。
- `Wait-ForURL` Slow 标签测试单独执行 5 项全部通过。
- Linux 镜像缺少 fzf 时，测试临时注册并清理占位函数，再由 Pester mock；Linux `psutils` 集合 453 项通过。
- `pnpm --filter psutils test:qa`、`pnpm qa`、`pnpm test:pwsh:all` 均通过。
