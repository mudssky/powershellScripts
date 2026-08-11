# 技术设计

## CLI Module

- 新增目录型工具 `scripts/pwsh/devops/browser-debug/`，入口 `main.ps1`，manifest `tool.psd1` 生成 `bin/browser-debug.ps1`。
- CLI Module 对调用者只暴露一个命令树；注册表、浏览器发现、进程、CDP、SSH、快捷方式和补全均隐藏在 implementation 中。
- `main.ps1` 使用原始 `$args`，由共享 command schema 驱动解析、帮助、分发和补全，避免手写多套 action 列表。
- 命令返回统一结果对象，入口根据 `--json` 或人类模式渲染并映射稳定退出码。

## 命令树

```text
browser-debug.ps1
├── profile
│   ├── create <name> --browser chrome|edge [--cdp-port N] [--profile-path PATH] [--source-user-data-path PATH] [--without-extensions] [--shortcut-directory PATH]
│   ├── set <name> [--cdp-port N] [--browser chrome|edge] [--shortcut-directory PATH]
│   ├── get [name] [--json]
│   ├── list [--json]
│   ├── start <name> [--mode local|lan] [--listen-address ADDRESS] [--open-guide]
│   ├── status <name> [--json]
│   ├── stop <name>
│   └── shortcut <name> --mode local|lan [--shortcut-directory PATH]
├── ssh
│   ├── create <name> --profile PROFILE --direction local-forward|reverse-forward --target TARGET --agent-port N
│   ├── set <name> [配置选项]
│   ├── get [name] [--json]
│   ├── list [--json]
│   ├── info <name> [--json]
│   ├── start <name>
│   ├── status <name> [--json]
│   └── stop <name>
├── completion powershell
├── help
└── __complete --line TEXT --position N
```

- `__complete` 为内部命令，不显示在普通帮助中。
- 名称使用位置参数；选项统一为小写 kebab-case；不同时支持 PowerShell `-Name` 风格，避免 interface 混杂。
- `--help` 可出现在根、资源或 action 层级。

## PowerShell 补全

- 提供轻量 `completion.ps1`，执行 `Register-ArgumentCompleter -Native -CommandName browser-debug,browser-debug.ps1`。
- Profile 集成只注册 `browser-debug` 别名和 Native Completer，不在启动时读取注册表或调用 CLI。
- 按 Tab 时 completer 将完整命令行和 cursor position 传给 `browser-debug.ps1 __complete`。
- `__complete` 复用 command schema 补全资源、action、合法选项和枚举值；仅在名称位置只读 registry 补全 Profile/SSH 名称。
- 补全失败安静返回空集合，不影响 PowerShell 其他补全；重复加载通过会话标记保持幂等。
- 测试使用 `CommandCompletion::CompleteInput()` 验证真实用户入口。

## 数据与端口

- 默认根目录：`D:\browser-debug-profiles`；默认 registry：`D:\browser-debug-profiles\registry.json`。
- registry 使用 `schemaVersion = 1`、`profiles` 和 `sshConfigurations`。
- Profile 端口是持久字段；`profile set --cdp-port` 只允许停止状态执行。
- SSH 配置只保存 Profile 名称，生成命令时读取当前 CDP 端口，避免复制和同步。
- 修改 registry 前创建 `registry.json.<timestamp>.bak`，写入采用同目录临时文件和原子替换。
- D 盘不存在时默认创建失败，并提示显式路径/registry 覆盖方式。

## 浏览器启动

- Chrome/Edge 参数至少包含独立 `--user-data-dir`、`--remote-debugging-port`、`--remote-debugging-address`、`--no-first-run` 和 `--no-default-browser-check`。
- `local` 使用 `127.0.0.1`；`lan` 默认 `0.0.0.0`，也允许显式接口地址。
- 使用 `ProcessStartInfo.ArgumentList` detached 启动；启动后轮询 `/json/version`。
- Windows Edge launcher 可能正常退出 0 并由子进程承接；启动成功以 CDP 可用且存在明确拥有目标 Profile 的浏览器进程为准，不能把 launcher 生命周期直接等同于浏览器生命周期。
- launcher 非零退出且尚无 owned 进程/CDP 时快速报错；launcher 退出 0 时继续等待到子进程接管或超时。
- status 从端口、CDP 和匹配 Profile 路径的进程命令行推导实际状态与模式。
- 浏览器所有权以可执行文件和规范化 `--user-data-dir=<ProfilePath>` 为准；stop 不终止未知 Chrome/Edge。
- stop 先快照所有 owned PID；停止根进程导致后续 owned 子进程自行退出时，将 `NoProcessFoundForGivenId` 视为幂等成功并返回原快照 PID，访问拒绝等其他停止错误仍向上抛出。
- `--open-guide` 用于快捷方式启动：Profile 未运行时正常启动；已运行且实际模式与请求模式一致时复用 owned 实例；模式不一致时拒绝并提示先停止后切换。普通 `profile start` 不带该选项时保持“已运行即报错”的现有合同。

## User Data 克隆

- `profile create` 默认解析 Chrome/Edge 当前用户的标准 User Data 目录，也允许 `--source-user-data-path` 显式覆盖；来源与目标不得相同或互相包含。
- 默认克隆登录状态、Profile 数据和扩展；`--without-extensions` 排除 `Extensions`、Extension State、Local/Sync/Managed Extension Settings、Extension Rules/Scripts 与扩展缓存。
- 始终排除 Singleton 锁、DevToolsActivePort、LevelDB `LOCK`、临时文件和明显运行时缓存，不复制 junction。
- 进程命令行表明来源 User Data 正在使用，或来源根目录存在 Chromium 锁文件时拒绝复制，提示完全关闭浏览器后重试。
- 使用 `robocopy` 复制到目标同目录的临时克隆目录；退出码 0..7 视为成功，随后重命名为最终 Profile。失败时清理临时目录，不写 registry。

## SSH 与 Agent 交接

- `local-forward` 只生成供远端执行的 `ssh -4 -N -o ExitOnForwardFailure=yes -L ...`。
- `reverse-forward` 由 Windows 使用 `ssh.exe -4 -N -o ExitOnForwardFailure=yes -R ...` detached 启动。
- OpenSSH target 原样传递，让 Host alias 负责用户、端口、密钥和代理跳转；同时支持 `user@host`。
- 反向隧道所有权由 PID、完整转发参数和 target 共同确认，不停止其他 SSH 会话。
- 交接对象包含 endpoint、SSH 命令、`playwright-cli attach` 命令、探测步骤和中文 Prompt；文本与 JSON 从同一对象渲染。

## 快捷方式

- 复用 `New-Shortcut`，默认输出到当前用户桌面。
- `profile create` 默认生成 `<name>.lnk`，调用 `profile start <name> --mode local --open-guide`，保持 Local 安全默认。
- `profile shortcut <name> --mode lan` 可随后生成 `<name>-LAN.lnk`，调用 `profile start <name> --mode lan --open-guide`，不替换已有 Local 快捷方式。
- 同一 Profile、模式和目录重复创建快捷方式时幂等返回已登记路径；未知同名文件冲突时拒绝覆盖。
- registry 使用结构化 `shortcutPaths.local/lan` 保存多个路径，同时保留旧 `shortcutPath` 作为 Local 兼容字段。
- 快捷方式不固化 CDP 端口或 SSH 参数，启动时仍从 registry 读取当前配置。

## 启动帮助页面

- `--open-guide` 在 CDP 和 owned Profile 进程确认就绪后构造不可变启动快照；快照包含实际模式、监听地址、CDP 端口与版本、生成时间、Profile 路径、当前 LAN IPv4 地址和引用该 Profile 的 SSH 交接对象。
- HTML 写入 registry 同级 `guides/` 目录，Local/LAN 使用独立文件名，避免混入 Chromium User Data；使用同目录临时文件后原子替换。
- 所有动态文本先 HTML 编码；页面不读取或嵌入 Cookie、密码、Token、页面标题和浏览历史。
- 页面提供本机、LAN 和 SSH 场景的 endpoint、探测 URL、`playwright-cli attach` 命令、中文 Agent Prompt 和复制按钮；`0.0.0.0` 通配监听为全部候选 LAN IPv4 分别生成直连项，显式监听地址只生成对应直连项；LAN 页面突出显示 CDP 无认证风险和防火墙未自动配置。
- 写入完成后使用目标浏览器与相同 `--user-data-dir` 打开 `file://` 页面，使 Chromium 将新标签交给已确认 owned 的运行实例。
- HTML 生成或打开异常作为结构化 warning 返回，不能把已成功启动或复用的浏览器改判为失败。

## 风险与回滚

- `lan` 无认证，只能显式启用且不自动修改防火墙。
- 静态帮助页只反映生成时的启动参数；配置或网络地址变化后需重新点击同模式快捷方式生成新快照。
- 运行中修改端口被拒绝，避免 registry、进程和 SSH 信息不一致。
- 浏览器与 SSH 生命周期严格独立，任何一侧失败不清理另一侧。
- registry 失败保留备份和临时文件；Profile 创建失败不自动删除浏览器已写数据。
- Profile 集成必须保持 Full/Minimal/UltraMinimal、OnIdle 和重复加载合同，不在启动路径调用 CLI。
