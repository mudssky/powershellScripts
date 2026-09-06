# browser-debug 支持 macOS/Linux 与平台快捷方式

## Goal

让 macOS 与 Linux 用户获得与 Windows 一致的 CDP 调试浏览器体验：一条命令创建隔离 debug profile、一条命令启动 debug 浏览器，并生成"类似 Windows 桌面快捷方式"的本地启动入口（macOS `.command` / Linux `.desktop`），双击/点按即可打开带 `--user-data-dir` 隔离和 CDP 端口的 Chromium 调试浏览器，同时保证 Windows 现有行为零变化。

## Background

现有 `browser-debug` CLI（`scripts/pwsh/devops/browser-debug/`，约 2300 行）首版仅支持 Windows。平台耦合点集中在 5 个函数边界（浏览器发现、User Data 定位、克隆、进程枚举、快捷方式生成），而 CDP `/json/version` 探测、guide HTML 模板、registry schema、CLI parser/completion 均平台无关可复用。测试套件 `tests/BrowserDebugProfile.Tests.ps1` 已在这些缝隙上做函数级 mock，且 Pester 本身运行在 Linux Docker harness 中，Unix 分支可被原生测试覆盖。

Windows 快捷方式语义（`runtime.ps1:587-609`）：桌面 `<name>.lnk` → `pwsh -NoProfile -File bin/browser-debug.ps1 profile start <name> --mode local --open-guide --yes`，图标为浏览器 exe；`profile create` 默认生成 local，`--mode lan` 幂等追加。

## Requirements

- R1 `profile create <name> --browser chrome|edge` 在 macOS/Linux 可用：按平台探测浏览器可执行文件与默认 User Data，克隆（排除锁文件 `Singleton*`）并登记 registry；事务语义（失败清理、不覆盖已登记路径）与 Windows 一致。
- R2 `profile start/status/stop` 在 macOS/Linux 可用：以隔离 user-data-dir + CDP 端口启动浏览器，沿用"owned 进程 + 实际 `/json/version`"的成功判定与 owned PID 停止语义。
- R3 `profile create/shortcut` 在 macOS 生成桌面 `<name>.command`、在 Linux 生成 `.desktop` 入口，语义对齐 Windows `.lnk`：local 文件名 `<name>`、幂等重建、不覆盖未知同名文件、快捷方式携带 `--open-guide --yes` 参数合同。
- R4 平台差异收敛为按 OS 分派的抽象层；registry/Profile 默认根路径按平台取值（env 覆盖 `BROWSER_DEBUG_REGISTRY_PATH`/`BROWSER_DEBUG_ROOT_PATH` 继续有效）；路径比较语义按平台区分大小写敏感性。
- R5 LAN 模式与 `ssh` 子命令在 macOS/Linux 明确返回"仅 Windows 支持"错误，不静默降级。
- R6 spec（`.trellis/spec/pwsh-scripts/package/browser-debug-cli.md`）与 Pester 契约测试同步更新；Windows 分支的现有合同（文件名/Target/Arguments/registry 结构）有测试守护。

## Key Decisions（按推荐方案收敛，最终批准时可推翻）

- D1 载体：扩展现有 `browser-debug` pwsh CLI，不另写 zsh/bash 工具。依据：仓库 `macos/`、`linux/` 安装链均已部署 pwsh；复用 CDP 探测、guide 模板、registry、CLI parser、测试骨架约 70% 逻辑；独立脚本会导致双份维护漂移。
- D2 首版范围：local 模式全链路（create/start/guide/shortcut/status/stop）；LAN 与 SSH 保持仅 Windows（Windows guide 中"原生 LAN 直连不可用"文案继续成立；Linux Chrome 对非回环 `--remote-debugging-address` 的真实绑定行为留待后续任务调研）。
- D3 快捷方式形态：macOS 用 `.command` 文件（双击经 Terminal 执行 pwsh，实现成本最低；`.app` 无窗口形态列为后续增强）；Linux 写 XDG 桌面目录（存在时）与 `~/.local/share/applications`（应用网格可见）。
- D4 Unix 默认数据根：`[Environment]::GetFolderPath(LocalApplicationData)/browser-debug-profiles`（Linux `~/.local/share/...`，macOS 同为 XDG 语义），不再出现 `D:\` 特判路径。
- D5 浏览器集合：macOS/Linux 与 Windows 相同仅 `chrome|edge`；flatpak/snap/Chromium 变体不在本任务范围（探测不到时给出明确错误与已支持位置说明）。

## Out of Scope

- LAN 模式、`ssh` 子命令的 macOS/Linux 实现（含 Linux 非回环 CDP 绑定能力调研）。
- macOS `.app` 快捷方式包形态。
- flatpak/snap/Chromium 等浏览器变体支持。
- `browserctl`（WSL→Windows browser-runtime，独立工具，与本任务无关）。

## Acceptance Criteria

- [ ] macOS 本机：`browser-debug profile create demo --browser chrome` 成功克隆 `~/Library/Application Support/Google/Chrome`（含 `Singleton*` 排除），桌面出现 `demo.command`，双击后隔离 Chrome 启动、实际 CDP `/json/version` 可探测、guide 页打开。
- [ ] macOS/Linux：`profile status`、`profile stop` 基于 `ps` 解析的 owned 进程证据工作；stop 只终止参数中携带该 Profile user-data-dir 的进程。
- [ ] Linux（Docker/WSL）：同链路生成 `.desktop` 并可从应用网格启动；`profile start` 成功判定与 Windows 合同一致。
- [ ] 非 Windows 平台执行 `profile shortcut <name> --mode lan`、`ssh <name> info` 返回明确"仅 Windows 支持"错误（退出码非 0）。
- [ ] Windows 行为零变化：现有 Browser Debug 专项 Pester 全绿，快捷方式文件名/Target/Arguments/IconLocation/registry 登记合同不变。
- [ ] 新增 Unix 分支 Pester 契约测试在 Linux Docker harness 原生运行（stub 浏览器可执行文件 + env 覆盖路径），覆盖克隆排除、幂等快捷方式、未知冲突拒绝、owned 进程匹配。
- [ ] `pnpm qa` 与 `pnpm test:pwsh:all` 通过。
