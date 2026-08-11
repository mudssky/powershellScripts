# Browser Debug CLI Spec

> 适用于 `scripts/pwsh/devops/browser-debug/**` 的 Chromium User Data 克隆、CDP 进程管理、快捷方式、SSH 交接和启动帮助页合同。

## Scenario: Windows Chromium Remote CDP Profile

### 1. Scope / Trigger

- Trigger: 修改 `browser-debug profile|ssh|completion` 命令、registry schema、Chromium 启停、CDP 探测、快捷方式或静态帮助页。
- Scope: 首版仅支持 Windows Chrome/Edge；Profile 数据与用户日常 User Data 隔离，SSH 生命周期与浏览器生命周期独立。
- Design intent: 为本机、LAN 或 SSH 隧道后的 Agent 提供可发现、可验证且不会误伤日常浏览器的 CDP 入口。

### 2. Signatures

```text
browser-debug profile create <name> --browser chrome|edge [--cdp-port N] [--source-user-data-path PATH] [--without-extensions]
browser-debug profile start <name> [--mode local|lan] [--listen-address IPv4] [--open-guide]
browser-debug profile shortcut <name> --mode local|lan [--shortcut-directory PATH]
browser-debug profile status|stop <name>
browser-debug ssh info <name> [--json]
playwright-cli attach --cdp=http://<host>:<port>
```

### 3. Contracts

- `profile create` 默认克隆所选浏览器的完整 User Data；来源浏览器运行、锁文件存在、路径包含冲突或复制失败时不得登记 Profile。
- 克隆使用同目录临时路径和 `robocopy`；退出码 `0..7` 成功，随后原子重命名；失败清理临时目录。
- `profile start` 默认 `local/127.0.0.1`；`lan` 必须显式请求并显示 CDP 无认证警告。
- 启动成功必须同时满足：存在命令行明确拥有目标 `--user-data-dir` 的 Chromium 进程，且实际 CDP `/json/version` 可用。
- Windows Edge launcher 退出 `0` 不代表失败；返回 PID、端口、模式和监听地址必须来自 owned 进程与实际 CDP，不得回退到陈旧 registry 请求值。
- `stop` 只处理 owned PID；根进程退出导致子进程并发消失时，只忽略 `NoProcessFoundForGivenId`，访问拒绝等错误继续抛出。
- `profile create` 默认生成 Local 快捷方式；`profile shortcut --mode lan` 可幂等追加 LAN 快捷方式，未知同名文件不得覆盖。
- `--open-guide` 对同模式已运行实例可复用；请求模式不同则拒绝。静态 HTML 使用实际启动快照，动态文本全部编码，不包含 Cookie、密码、Token、标签页或历史记录。
- `0.0.0.0` LAN 快照必须列出全部候选 IPv4 endpoint，不得静默选择第一块网卡；显式监听地址只展示该地址。
- HTML 生成或打开失败只返回 warning，不得把已经成功的浏览器启动改判为失败。
- SSH 配置只引用 Profile；生成 SSH、Playwright 和 Agent Prompt 时使用当前实际 CDP 端口。浏览器命令不得隐式启动或停止 SSH。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| 默认 User Data 正在被 Chrome/Edge 使用 | 拒绝克隆并提示完全关闭浏览器 |
| 目标 Profile 或 registry 已登记路径冲突 | 拒绝创建，不覆盖现有目录或快捷方式 |
| Edge launcher 退出 `0`，owned 子进程随后接管 | 继续等待，owned 进程与 CDP 同时就绪后成功 |
| launcher 非零退出且没有 owned/CDP 证据 | 立即返回可诊断错误 |
| Local 实例运行时请求 LAN `--open-guide` | 拒绝并提示先 `profile stop` |
| 同模式实例运行时请求 `--open-guide` | 复用实例并按当前实际参数重新生成快照 |
| `0.0.0.0` 监听且存在多个 IPv4 | 页面生成多个 endpoint/attach/prompt，不选唯一首地址 |
| 快捷方式目标已由该 Profile 同模式登记 | 幂等返回，不写无意义 registry 备份 |
| 快捷方式目标是未知文件 | 拒绝覆盖 |
| 帮助页文件写入或打开失败 | 浏览器启动结果成功，附带 warning |
| owned 子进程在 stop 循环中自行退出 | 忽略 `NoProcessFoundForGivenId`，其他错误不吞 |

### 5. Good/Base/Bad Cases

- Good: `profile start edge-debug --mode local --open-guide` 返回 owned PID、实际 `21229` 端口并生成 Local 快照。
- Good: `profile shortcut edge-debug --mode lan` 保留 `edge-debug.lnk`，另建 `edge-debug-LAN.lnk`。
- Good: LAN 通配监听页面分别列出物理网卡、VPN 或其他有效 IPv4 候选，由用户选择可达地址。
- Base: 普通 `profile start` 遇到已运行实例继续报错；只有 `--open-guide` 提供同模式复用语义。
- Bad: launcher 对象 `HasExited` 后立即报失败，即使 Edge 子进程和 CDP 已经正常运行。
- Bad: 用 registry 的旧端口或 `lanAddresses[0]` 生成远端 Agent Prompt。
- Bad: 为方便停止浏览器而终止所有 `msedge.exe`，这会误伤日常浏览器。

### 6. Tests Required

- CLI parser/help/completion 必须覆盖新增 action、必需参数、未知/重复选项和动态 Profile 名称。
- 克隆测试必须覆盖运行来源、锁文件、扩展排除、`robocopy` 退出码、事务清理和 registry 不落脏记录。
- 启动测试必须覆盖 Edge launcher `0` 接管、非零退出、实际端口/地址提取、同模式复用和不同模式拒绝。
- stop 测试必须覆盖 owned 过滤、并发 PID 消失与 PermissionDenied 不吞。
- 快捷方式测试必须覆盖 legacy `shortcutPath`、`shortcutPaths.local/lan`、幂等、未知冲突、回滚和精确 `--mode --open-guide` 参数。
- guide 测试必须覆盖 HTML 编码、敏感字段排除、LAN 多候选、显式 IPv4、实际端口同步、SSH 信息、原子写入和打开失败 warning。
- 至少运行 Browser Debug 专项 Pester、Profile Loading/Mode 窄测、严格格式、AST、Markdown、CLI smoke 和 `git diff --check`。

### 7. Wrong vs Correct

#### Wrong

```powershell
if ($launcher.HasExited) {
    throw "浏览器启动失败: $($launcher.ExitCode)"
}

$endpoint = "http://$($lanAddresses[0]):$($profile.cdpPort)"
```

问题：Windows Edge launcher 可以正常退出后由子进程接管；网卡顺序也不能代表远端可达性，registry 端口可能与真实进程不一致。

#### Correct

```powershell
$owned = Get-OwnedChromiumProcess -Profile $profile
$cdp = Get-CdpVersion -Port $owned.CdpPort -Address $owned.ProbeAddress

if ($owned -and $cdp) {
    return New-ActualStartResult -Process $owned -CdpVersion $cdp
}

$directEndpoints = Get-LanIPv4Address | ForEach-Object {
    "http://${_}:$($owned.CdpPort)"
}
```

理由：启动与交接信息都基于实际 owned 进程和 CDP 证据；通配 LAN 显式保留多候选地址，不制造错误的唯一答案。
