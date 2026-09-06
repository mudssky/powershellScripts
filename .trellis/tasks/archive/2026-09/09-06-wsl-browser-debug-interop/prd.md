# WSL 内调用 browser-debug 创建 Windows 快捷方式与启动

## Goal

在 WSL 会话（含 AI agent 会话）内直接创建 Windows 端 debug 浏览器快捷方式并启动/管理 browser-debug Profile，无需手动切回 Windows 终端；并把该已验证的调用契约沉淀到 `.agents/skills/repo-ops` skill 的 reference，方便后续 agent 与用户复用。

## Background / Confirmed Facts（仓库与实测证据）

- browser-debug CLI 入口：`bin/browser-debug.ps1` → `scripts/pwsh/devops/browser-debug/main.ps1`；`Invoke-BrowserDebugCli` 在非 help/completion 分支调用 `Assert-BrowserDebugWindowsPlatform`（`runtime.ps1:10-16`），非 Windows 平台抛错。
- 快捷方式由 `New-BrowserDebugShortcut`（`runtime.ps1:587-609`）通过 WScript.Shell COM 创建，参数为 `-NoProfile -File "<entry>" profile start <name> --mode <mode> --open-guide --yes`，**未包含 `-ExecutionPolicy Bypass`**。
- 仓库只存在于 WSL 文件系统；Windows 侧访问路径为 `\\wsl.localhost\Ubuntu-22.04\home\mudssky\projects\env\powershellScripts`（`wslpath -w` 实测）。未发现 Windows 侧 checkout。
- 实测：WSL 内执行 `"/mnt/c/Program Files/PowerShell/7/pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File '<UNC>\bin\browser-debug.ps1' profile list` 成功（空 registry，退出码 0）。**不加 `-ExecutionPolicy Bypass` 时 UNC 路径脚本被执行策略拦截（RemoteSigned 视 UNC 为不可信）**。
- WSL interop 已启用（`/etc/wsl.conf` `interop.enabled=true`，`appendWindowsPath=true`）；Windows 侧存在 pwsh 7（`C:\Program Files\PowerShell\7\pwsh.exe`）与 Windows PowerShell 5.1。当前 WSL 会话 PATH 中无 `pwsh.exe`（需按绝对路径或标准相对路径探测）。
- registry 默认位于 Windows 侧 `D:\browser-debug-profiles\registry.json`（`registry.ps1:37`）；shortcut 默认目录为 Windows 桌面（模块内逻辑）。
- Windows 宿主 `.wslconfig` 为 `networkingMode=mirrored` + `hostAddressLoopback=true`：WSL 内可用 `localhost:<cdpPort>` 直连 Windows 端 CDP，启动后 WSL 侧 dev 工具（如 Playwright）可直接消费。
- Linux shell 集成规范落点：`shell/shared.d/*.sh`（由 `shell/deploy.sh` 部署到 `~/.bashrc.d/`），降级/幂等规则见 `.agents/skills/repo-ops/references/shell-profile-integration.md`。当前 `shell/` 下没有任何 WSL interop 先例。
- repo-ops skill 规则：有真实流程才建 reference；路径与行为以仓库代码为事实来源，不在 Skill 复制第二份实现。
- 文档索引：`docs/scripts-index.md` 已记录 browser-debug 命令树。

## Requirements

1. **WSL 侧调用入口**：在 `shell/shared.d/` 新增片段，提供 `browser-debug` 函数，将参数原样转发给 Windows pwsh 执行 UNC 路径下的 `bin/browser-debug.ps1`，内部处理 `-ExecutionPolicy Bypass` 与 Windows pwsh 路径探测。
   - interop 或 Windows pwsh 缺失时安静降级（不注册函数、无硬错误），符合 shell-profile-integration.md 降级合同。
   - 重复 source 不重复注册；非交互式会话行为需定义。
   - 参数含绝对 POSIX 路径（`/` 开头且存在）时用 `wslpath -w` 自动转 Windows 路径，方便在 WSL 内直接传 `/mnt/c/...` 形态的 `--source-user-data-path`、`--profile-path` 等值。
2. **UNC 快捷方式可用性修复**：`New-BrowserDebugShortcut` 在入口路径为 UNC（`\\` 开头）时给快捷方式参数追加 `-ExecutionPolicy Bypass`，使从 WSL 创建的快捷方式双击可直接运行；本地路径行为不变。
3. **repo-ops reference**：新增 reference 文档（如 `references/wsl-windows-interop.md`），记录已验证的调用契约：UNC 路径转换（`wslpath -w`）、`-ExecutionPolicy Bypass` 必要性、mirrored 网络下 WSL 直连 CDP、可用命令树与验证命令；明确"复制 Chrome profile 创建调试浏览器"的标准流程（`profile create` 默认源即 Chrome User Data；Chrome 运行中会被 `Test-BrowserDebugSourceInUse` 拒绝复制）。
4. **文档索引**：`docs/scripts-index.md` 补充 WSL 调用方式说明。
5. **真实验证流程（作为最终验收执行一次）**：从 WSL 执行 `browser-debug profile create <name> --browser chrome`（复制 Chrome User Data）、确认桌面快捷方式生成、`profile start` 启动并从 WSL 内 `curl http://localhost:<cdpPort>/json/version` 验证 CDP 可达（mirrored 网络）。

## Acceptance Criteria

- [x] WSL 交互式 shell 内 `browser-debug profile list` 返回与 Windows 侧一致的结果（空 registry 时无输出、退出码 0）；`browser-debug help` 正常输出。
- [x] 从 WSL 执行 `browser-debug profile create <name> --browser chrome` 流程验证：因 Chrome 正在运行，按安全合同改用 `--source-user-data-path` 合成空源完成同代码路径验证（克隆→桌面 `.lnk`→registry 登记→参数路径自动转换均通过）；真实 Chrome User Data 克隆待用户关闭 Chrome 后执行同一条命令即可。
- [x] 双击该快捷方式能启动对应 Profile（UNC 入口 + Bypass 修复生效；已核验 `.lnk` 参数为 `-NoProfile -ExecutionPolicy Bypass -File "<UNC>\bin\browser-debug.ps1" profile start <name> --mode local --open-guide --yes`，且该命令行语义经 `profile start` 实测成功）。
- [x] Windows 本地路径（非 UNC）场景下生成的快捷方式参数与现有行为一致（回归：现有测试断言不被破坏，按需更新测试）。
- [x] interop 不可用（模拟缺失 Windows pwsh）时，source 片段无报错、不注册入口；重复 source 只注册一次。
- [x] repo-ops reference 存在且与实际代码行为一致；AGENTS.md 门禁执行（`pnpm qa` 通过；pwsh 改动跑 `pnpm test:pwsh:all`：host 全量绿、Docker lane 仅剩 1 个 stash 证明的 master 既有失败；BrowserDebug windowsOnly 套件经 Windows pwsh interop 61/61 全绿）。

## 验证结果补充（2026-09-06）

- `wslverify` 验证 Profile 与桌面快捷方式保留为可用实例（browser-debug 无删除命令，不手工动 registry）。
- 实施中发现并修复两处 UNC 路径兼容问题：`Get-BrowserDebugRepoRoot` 与 `Format-PowerShellCode.ps1` `Get-RepositoryRoot` 的 `Resolve-Path` 在 WSL UNC 上返回 `FileSystem::` 前缀且不折叠 `..`，均做归一化；`Test-BrowserDebugShortcutCurrent` 把"引用 UNC 入口但缺 Bypass"判为过期触发原地重建。
- 环境准备：WSL 侧安装 rustup minimal stable（qa 门禁 `format:pwsh` 的 pwshfmt-rs 硬依赖 cargo，Rust ≥1.85 支持 edition 2024；Windows 侧 cargo 1.79 过旧不可用）。

## Out of Scope

- 不改动 registry 默认路径、profile 存储布局与 SSH 转发功能。
- 不在 Windows 侧创建仓库 checkout。
- 不做 NAT 模式（非 mirrored）下的端口转发方案；沿用现有 LAN/tailscale/SSH 转发能力。
- 不为 cmd/PowerShell 增加新入口；Windows 侧沿用现有 alias 与 completion。
- 不为 Linux shell 注册 browser-debug 补全（Windows completion 无法透传，收益低）。

## Key Decisions

- 推荐交付全量组合（R1-R4）：wrapper 解决"启动方便"，UNC Bypass 修复让"从 WSL 创建的快捷方式可双击"，reference 沉淀给后续 agent 会话。若用户砍掉 R2，则从 WSL 创建的快捷方式双击会因执行策略失败，仅 wrapper 直调启动可用。
