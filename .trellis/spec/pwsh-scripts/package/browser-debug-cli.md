# Browser Debug CLI Spec

> 适用于 `scripts/pwsh/devops/browser-debug/**` 的 Chromium User Data 克隆、CDP 进程管理、快捷方式、SSH 交接和启动帮助页合同。

## Scenario: Windows Chromium Remote CDP Profile

### 1. Scope / Trigger

- Trigger: 修改 `browser-debug profile|ssh|completion` 命令、registry schema、Chromium 启停、CDP 探测、快捷方式或静态帮助页。
- Scope: `profile` 的 local 模式支持 Windows/macOS/Linux；LAN 模式与 `ssh` 交接仅支持 Windows（Windows Chrome/Edge 原生 LAN 直连不可用的结论仅约束 Windows）。Profile 数据与用户日常 User Data 隔离，SSH 生命周期与浏览器生命周期独立。
- Design intent: 为本机、LAN 或 SSH 隧道后的 Agent 提供可发现、可验证且不会误伤日常浏览器的 CDP 入口。
- 平台分派合同:浏览器发现、User Data 定位、克隆、进程枚举、快捷方式生成必须经 `Get-BrowserDebugPlatform` 分派；平台差异不得散落在命令编排层。LAN/SSH 仅由 `Assert-BrowserDebugCommandSupport` 在 CLI 边界拒绝，命令内部函数保持平台无关。
- 默认 CDP 端口三平台统一为 21229（`--cdp-port` 可覆盖）；9222 常与本机常驻 Chromium 冲突，不作为默认值。
- Unix 快捷方式与补全入口的 pwsh 必须经过可运行性探测（试运行 `-NoProfile -Command exit 0` 退出码为 0）后选定；补全在注册时不固定 Source，调用时按当前会话 PATH 解析 `pwsh`。禁止把需要 `DOTNET_ROOT` 等环境变量的裸 apphost 直接固化为快捷方式目标。

### 2. Signatures

```text
browser-debug profile create <name> --browser chrome|edge [--cdp-port N] [--source-user-data-path PATH] [--without-extensions]
browser-debug profile start <name> [--mode local|lan] [--listen-address IPv4] [--open-guide] [--yes]
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
- 快捷方式入口路径为 UNC（仓库位于 WSL 文件系统，经 `Resolve-Path` 会带 `FileSystem::` 前缀且不折叠 `..`，必须归一化）时，Arguments 必须携带 `-ExecutionPolicy Bypass`；幂等检查把"引用 UNC 入口但缺 Bypass"视为参数过期并原地重建。本地路径 Arguments 合同保持不变。
- `--open-guide` 对同模式已运行实例可复用；请求模式或显式监听地址不同则进入切换流程。交互式命令默认展示当前 endpoint、当前/目标模式并确认，非交互调用必须显式传 `--yes`；Local/LAN 快捷方式携带 `--yes`，双击即确认。
- 静态 HTML 的完整页面骨架、CSS、SVG 与 JavaScript 固定存放在 `scripts/pwsh/devops/browser-debug/browser-debug-guide.template.html`；运行时必须通过 `$PSScriptRoot` 定位，以唯一占位符注入已编码片段。模板缺失、占位符重复/缺失或渲染后残留占位符必须返回可诊断错误，guide 失败仍只追加 warning。
- 指南只把实际可探测的 `127.0.0.1:<actualPort>` 标为原生 CDP Ready endpoint；`mode` 与 `listenAddress` 只是启动请求元数据，不得作为 LAN listener 或远程可达性的证明。动态文本全部 HTML 编码，不包含 Cookie、密码、Token、标签页或历史记录。
- LAN 页面必须明确标记 Windows Chrome/Edge 原生 LAN 直连当前不可用，并按实际 CDP 端口提供两种不自动执行的远程方案：Tailnet 内的 Tailscale Serve TCP forwarder，以及由远端设备执行的通用 `ssh -N -o ExitOnForwardFailure=yes -L`。Local 页面不得显示该警告或通用远程方案。
- LAN 快照生成时以只读 `tailscale status --json` 探测本机地址（仅允许 100.64.0.0/10 的 Tailnet IPv4、去尾点的 MagicDNS 域名与合法主机名字符集的 `Self.HostName`，缺失时回退域名首段）；可执行文件缺失、未登录、非零退出、3 秒超时或解析失败一律静默回退为未检测，绝不 throw。Tailnet endpoint 一律使用 Tailnet IPv4，检测到时快照携带 `hostnameEndpoint`/`aliasEndpoint`/`detected`，渲染依次追加"主机名别名 endpoint""MagicDNS 别名 endpoint"可复制字段；未检测到时 endpoint 保持占位符并在 Tailscale 区块显示未检测提示。
- Tailscale 区域必须包含精确端口的 `serve --bg --yes --tcp`、`serve status` 与 `serve --tcp=<actualPort> off`，不得建议 `serve reset`；SSH 区域必须包含远端回环 endpoint、探测 URL、Playwright attach 与 Agent Prompt。
- registry 中显式登记的 SSH configurations 在 Local/LAN 页面均继续独立展示；生成 SSH、Playwright 和 Agent Prompt 时使用当前实际 CDP 端口。浏览器命令不得隐式启动或停止 SSH。
- registry 默认路径按平台取值：Windows 保持 `D:\browser-debug-profiles\registry.json`，macOS/Linux 取用户本地数据目录下 `browser-debug-profiles/registry.json`；Profile root 始终是 registry 所在目录，env 覆盖（`BROWSER_DEBUG_REGISTRY_PATH`/`BROWSER_DEBUG_ROOT_PATH`）在三平台等价生效。
- 路径比较语义按平台分派：Linux 使用 `Ordinal`（大小写敏感），Windows/macOS 使用 `OrdinalIgnoreCase`；统一经 `Test-BrowserDebugSamePath`/`Test-BrowserDebugPathWithin` 完成，禁止在编排层内联大小写敏感比较或 `TrimEnd('\')`。
- Unix 克隆分派 macOS `ditto`、Linux `cp -a`；工具无复制期排除能力时必须整体克隆后修剪排除目录/文件，语义对齐 robocopy `/XF` `/XD` 的任意深度匹配；退出码合同 Unix 为 `0` 即成功，Windows robocopy 保持 `0..7`。
- Unix 进程枚举解析 `ps` 输出（macOS `-axo`、Linux `-e -o`），仅保留 Chromium 家族行；进程对象没有 `ExecutablePath` 时，所有权判定使用命令行前缀匹配（应用包路径可含空格，禁止拆分 argv[0]），`--user-data-dir` 正则与端口提取合同复用。
- Unix 快捷方式：macOS 生成 `<name>.command`（shebang 脚本、`chmod +x`、sh 单引号转义），Linux 生成 `<name>.desktop`（freedesktop Exec 转义、`Terminal=false`、按浏览器给主题图标名）；两者都携带 `profile start <name> --mode local --open-guide --yes` 参数合同；LAN 变体文件名仅在 Windows 存在。幂等、事务回滚和未知同名文件拒绝覆盖合同跨平台一致。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| 默认 User Data 正在被 Chrome/Edge 使用 | 拒绝克隆并提示完全关闭浏览器 |
| 目标 Profile 或 registry 已登记路径冲突 | 拒绝创建，不覆盖现有目录或快捷方式 |
| Edge launcher 退出 `0`，owned 子进程随后接管 | 继续等待，owned 进程与 CDP 同时就绪后成功 |
| launcher 非零退出且没有 owned/CDP 证据 | 立即返回可诊断错误 |
| Local 实例运行时请求 LAN，未传 `--yes` 且不可交互 | 停止前拒绝并提示显式添加 `--yes` |
| Local 实例运行时请求 LAN，交互确认或传入 `--yes` | 只停止该 Profile owned PID，以 LAN 重启并返回 `switched` 与 `stoppedProcessIds` |
| 同模式实例运行时请求 `--open-guide` | 复用实例并按当前实际参数重新生成快照，不停止进程 |
| LAN 模式且实际 CDP 只监听回环 | 页面只把 `127.0.0.1:<actualPort>` 标为 Ready，显示原生直连不可用提示以及 Tailscale Serve、通用 `ssh -L` 方案 |
| LAN 快照探测 Tailscale 失败（未安装/未登录/超时/解析失败） | endpoint 回退占位符并显示未检测提示，指南仍生成成功 |
| Local 模式生成指南 | 只显示本机 CDP、已登记 SSH configurations 与对应 Agent Prompt，不显示 LAN 警告或通用 Tailscale/SSH 指南 |
| 快捷方式目标已由该 Profile 同模式登记 | 幂等返回，不写无意义 registry 备份 |
| 快捷方式目标是未知文件 | 拒绝覆盖 |
| 帮助页文件写入或打开失败 | 浏览器启动结果成功，附带 warning |
| owned 子进程在 stop 循环中自行退出 | 忽略 `NoProcessFoundForGivenId`，其他错误不吞 |
| 非 Windows 平台执行 `ssh *` 或 `profile * --mode lan` | CLI 边界抛出"仅支持 Windows"错误，退出码 1 |
| 非 Windows 平台执行 `profile list/get` 或 local 模式命令 | 正常放行 |
| Unix 克隆后修剪失败或 `ditto`/`cp -a` 非零退出 | 按克隆失败清理临时目录，不落 registry |
| Unix 快捷方式目标文件未携带完整启动参数合同 | 幂等校验失败，原地重建 |

### 5. Good/Base/Bad Cases

- Good: `profile start edge-debug --mode local --open-guide` 返回 owned PID、实际 `21229` 端口并从模块外部模板生成 Local 快照。
- Good: LAN 页面将 `http://127.0.0.1:21229` 标为本机 Ready，检测到 Tailscale 时用 Tailnet IPv4（如 `http://100.101.7.31:21229`）派生 Tailnet endpoint/探测/attach/Prompt 并附主机名与 MagicDNS 别名，同时生成 `tailscale serve --bg --yes --tcp=21229 tcp://127.0.0.1:21229` 与 `ssh -N -o ExitOnForwardFailure=yes -L 21229:127.0.0.1:21229 <windows-user>@<windows-host>`。
- Good: `profile shortcut edge-debug --mode lan` 保留 `edge-debug.lnk`，另建携带 `--yes` 的 `edge-debug-LAN.lnk`，其 Target、Arguments、WorkingDirectory、IconLocation 与 registry 路径合同不因指南改造而变化。
- Good: Local 实例运行时执行 `profile start edge-debug --mode lan --yes`，只停止 `edge-debug` owned PID并返回 `switched=true`。
- Base: 同模式普通 `profile start` 遇到已运行实例继续报错；`--open-guide` 提供同模式复用，模式变化则进入确认切换。
- Bad: 把 `--remote-debugging-address=0.0.0.0`、显式网卡 IPv4 或网卡枚举结果渲染成 Ready endpoint 或 LAN Agent Prompt。
- Bad: 使用 `tailscale serve reset`、自动执行网络暴露命令，或让快捷方式联动 SSH 生命周期。
- Bad: launcher 对象 `HasExited` 后立即报失败，即使 Edge 子进程和 CDP 已经正常运行。
- Bad: 用 registry 的旧端口生成远程 Agent Prompt。
- Bad: 为方便停止浏览器而终止所有 `msedge.exe`，这会误伤日常浏览器。

### 6. Tests Required

- CLI parser/help/completion 必须覆盖新增 action、必需参数、未知/重复选项和动态 Profile 名称。
- 平台能力测试必须在所有平台运行：`Get-BrowserDebugPlatform` 与操作系统一致、`Assert-BrowserDebugCommandSupport` 显式传入平台时的放行/拒绝矩阵、路径比较语义、ps 解析、Unix 进程形状的前缀所有权判定。平台专属测试用 `-Skip` 守卫而非仅靠 tag。
- 克隆测试必须覆盖运行来源、锁文件、扩展排除、克隆退出码（robocopy 0..7 / Unix 0）、事务清理和 registry 不落脏记录；Unix 环境另需覆盖整体克隆后的排除修剪。
- 启动测试必须覆盖 Edge launcher `0` 接管、非零退出、实际端口/地址提取、同模式复用、交互确认接受/拒绝、非交互缺少 `--yes` 拒绝和确认后的模式切换。
- stop 测试必须覆盖 owned 过滤、并发 PID 消失与 PermissionDenied 不吞。
- 快捷方式测试必须覆盖 legacy `shortcutPath`、`shortcutPaths.local/lan`、参数合同升级重建、幂等、未知冲突、回滚和精确 `--mode --open-guide --yes` 参数；Unix 环境另需覆盖 `.command` 可执行位、`.desktop` Exec 行和内容级合同校验。
- guide 测试必须覆盖外部模板存在、`$PSScriptRoot` 定位、固定占位符唯一性、模板缺失/残留诊断、HTML 编码、敏感字段排除、复制控件、回环实际端口、LAN 不可用提示、Tailscale 三条命令、通用 `ssh -L`、Local 页面降噪、已登记 SSH、原子写入和打开失败 warning；并覆盖 Tailscale 探测：CGNAT IPv4 判定、`status --json` 解析（域名去尾点、HostName 回退与字符集过滤）、探测失败/invoker 异常/缺少可执行文件回退、检测成功时 endpoint 用 IPv4 与别名行渲染、未检测提示、负向断言放行 Tailnet CGNAT 段但仍禁止其余私网 endpoint。
- 快捷方式回归必须确认 Windows Local/LAN 文件名、Target、Arguments、WorkingDirectory、IconLocation 与 registry 登记路径保持现有合同。
- 至少运行 Browser Debug 专项 Pester、Profile Loading/Mode 窄测、严格格式、AST、Markdown、CLI smoke 和 `git diff --check`。

### 7. Wrong vs Correct

#### Wrong

```powershell
if ($launcher.HasExited) {
    throw "浏览器启动失败: $($launcher.ExitCode)"
}

$endpoint = "http://$($lanAddresses[0]):$($profile.cdpPort)"
```

问题：Windows Edge launcher 可以正常退出后由子进程接管；网卡地址和启动请求值也不证明 Chrome/Edge 已建立 LAN listener，registry 端口可能与真实进程不一致。

#### Correct

```powershell
$owned = Get-OwnedChromiumProcess -Profile $profile
$cdp = Get-CdpVersion -Port $owned.CdpPort -Address $owned.ProbeAddress

if ($owned -and $cdp) {
    $endpoint = "http://127.0.0.1:$($owned.CdpPort)"
    $templatePath = Join-Path $PSScriptRoot 'browser-debug-guide.template.html'
}
```

理由：启动与交接信息都基于实际 owned 进程和 CDP 证据；原生 Ready endpoint 固定使用可探测的回环地址，LAN 页面另行提供 Tailscale Serve 与远端 `ssh -L`，不制造虚假的网卡直连能力。

#### Wrong (Unix)

```powershell
# 按 argv[0] 空格拆分 ps 输出解析可执行文件
$parts = $process.CommandLine -split ' '
$actual = $parts[0]
if ($actual -ne $expected) { return $false }
```

问题：macOS 应用包路径自带空格（`/Applications/Google Chrome.app/...`），按空格拆分会把 argv[0] 截断，owned 进程永远匹配不上。

#### Correct (Unix)

```powershell
# 不拆分 argv[0]，用完整命令行对期望路径做前缀匹配
if (-not $commandLine.StartsWith($expected, $comparison)) { return $false }
$remainder = $commandLine.Substring($expected.Length)
return $remainder.Length -eq 0 -or $remainder[0] -eq ' '
```
