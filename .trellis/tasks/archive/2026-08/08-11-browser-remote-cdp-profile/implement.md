# 实施计划

## 实现步骤

1. 创建 `scripts/pwsh/devops/browser-debug/`、`main.ps1`、`tool.psd1` 和共享 command schema，实现帮助、解析、分发、结果与退出码。
2. 实现 Profile/SSH registry、时间戳备份、原子写入、默认路径和 Chrome/Edge 发现。
3. 实现 `profile create/set/get/list/shortcut`，包括默认/自定义 User Data 安全克隆、可选排除扩展、端口持久修改、默认 Local 快捷方式和可追加 LAN 快捷方式，确保 create 不启动浏览器。
4. 实现 `profile start/status/stop`、local/lan、端口冲突、detached 浏览器、Edge launcher 子进程接管和 `/json/version` + Profile 所有权验证；`--open-guide` 支持同模式运行实例复用，不同模式明确拒绝。
5. 实现 SSH 配置、local-forward 命令生成、reverse-forward 进程管理和结构化 Agent 交接信息。
6. 实现根/资源/action 帮助、`--json`、`completion powershell` 和复用 command schema 的内部 `__complete`。
7. 在 PowerShell Profile 中幂等注册 `browser-debug` 别名和 Native Completer，保持所有模式与启动性能合同。
8. 实现启动参数静态 HTML 快照、HTML 编码、复制控件、LAN 风险提示、SSH 交接信息和使用目标 Profile 打开页面的降级 warning。
9. 增加 Pester 测试，mock 浏览器、SSH、COM 快捷方式、端口、HTTP、HTML 文件和 completion 边界。
10. 更新 `docs/scripts-index.md`，记录 CLI 命令树、端口修改、Local/Lan、多个快捷方式、静态帮助页、SSH 两方向及 Agent Prompt 示例。
11. 同步 bin shim，验证只公开 `browser-debug.ps1`，内部脚本不生成 bin 入口。

## 验证命令

- `pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode qa -Path ./tests/BrowserDebugProfile.Tests.ps1`
- 运行 Profile loading/completion 相关窄测。
- `pnpm qa`
- `pnpm test:pwsh:all`
- 验证 `browser-debug.ps1 --help`、每层 `--help`、`--json`、错误退出码和 Native Completion。
- 使用临时 Profile 和端口验证 Chrome/Edge local；lan 只在受控网络验证，不自动开放防火墙。
- 验证默认 Local 快捷方式、追加 LAN 快捷方式、同模式复用、不同模式拒绝，以及帮助页快照参数来自实际启动结果。
- 验证 HTML 动态值编码、敏感数据不进入页面、复制按钮降级，以及帮助页写入/打开失败只产生 warning。
- 验证 local-forward/reverse-forward、SSH alias/`user@host`、SSH 立即退出和未知 SSH 进程保护。

## 风险文件与回滚点

- `scripts/pwsh/devops/browser-debug/**`：新 CLI，可整体移除回滚。
- `profile/**`：只增加轻量别名/补全注册，必须通过 Profile 模式和重复加载测试。
- `tests/BrowserDebugProfile.Tests.ps1` 及 Profile 相关测试：独立行为覆盖。
- `docs/scripts-index.md`：只追加新入口，不修改现有 `browserctl` 合同。
- `bin/browser-debug.ps1`：由 `Manage-BinScripts.ps1` 生成，不手工维护。
- 实机验证禁止指向浏览器默认用户数据目录。

## 启动实现前检查

- 纯 CLI interface 的最终规划获得用户明确批准。
- `implement.jsonl` 与 `check.jsonl` 包含 PowerShell、Profile、配置、进程启动和 SSH config 相关规范。
- 工作区现有未提交文件不属于本任务，不回退或覆盖。
