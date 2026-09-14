# Implement — browser-debug macOS/Linux 支持

## 有序执行清单

1. **平台基座**：`runtime.ps1` 新增 `Get-BrowserDebugPlatform` 与 `Assert-BrowserDebugCapability`（替换 `Assert-BrowserDebugWindowsPlatform` 的调用点），`main.ps1:78` 门禁改写；`completion/help/list/get` 全平台放行，`--mode lan`、`ssh *` 非 Windows 报明确错误。
2. **浏览器发现与 User Data**：`Resolve-BrowserDebugExecutable`、`Resolve-BrowserDebugDefaultUserDataPath` 增加按平台路径表分派（macOS `.app` 路径、Unix PATH 探测用 `Get-Command`）；探测失败文案列出该平台已支持位置。
3. **路径语义**：新增 `Compare-BrowserDebugPath`，替换 `commands.ps1:129,138` 等处 `TrimEnd('\') + OrdinalIgnoreCase` 比较；`registry.ps1`、`commands.ps1` 移除 `D:\` 特判，默认根改为平台 LocalApplicationData。
4. **克隆分派**：`Copy-BrowserDebugUserData` 底层按平台分派 `robocopy`（Windows 现状）/`ditto`（macOS）/`cp -a`（Linux），锁文件排除表按平台（`Singleton*`），保留事务临时目录+原子重命名与失败清理。
5. **进程枚举**：Unix 用 `ps -e -o pid=,args=`（macOS `-axo`）解析为 Windows 对象同形状；复用 owned 判定、CDP 端口提取正则；`Stop-BrowserDebugProfileProcess` Unix 分支 `kill`。
6. **快捷方式分派**：`New-BrowserDebugShortcut` 按平台生成 `.lnk`（现状）/`.command`/`.desktop`；`Test-BrowserDebugShortcutCurrent` 平台化读取；`Add-BrowserDebugProfileShortcut` 事务保留；`Invoke-BrowserDebugProfileCreate` 的 `$expectedShortcutPath` 扩展名平台化（`commands.ps1:148`）。
7. **测试**：`tests/BrowserDebugProfile.Tests.ps1` 新增 Unix 分支契约（stub 可执行文件 + env 覆盖；`ps` 解析、快捷方式内容/幂等/未知冲突、克隆排除、lan/ssh 拒绝）；保留全部 Windows 契约不动。
8. **spec 更新**：`.trellis/spec/pwsh-scripts/package/browser-debug-cli.md` 改写"仅 Windows"范围声明为三平台 local + Windows LAN/SSH，补充 Unix 快捷方式与进程合同、错误矩阵行。
9. **文档**：`docs/scripts-index.md` 与 `profile/README.md` 中 browser-debug 条目更新平台说明。

## 验证命令

- `pnpm test:pwsh:all`（Linux Docker harness 原生覆盖 Unix 分支；本机 mac 如 Docker 可用直接跑，不可用则说明依赖 CI/WSL）
- `pnpm test:pwsh:coverage`（涉及 coverage 合同时）
- `pnpm qa`
- macOS 本机手动验收：`browser-debug profile create demo --browser chrome` → 双击桌面 `demo.command` → CDP `/json/version` 探测 → `profile stop demo`

## 风险文件与回滚点

- 高风险：`runtime.ps1`（Windows 现有行为零回归靠既有契约测试守护）、`commands.ps1` 路径比较语义。
- 回滚：单任务单分支，revert 即可；registry schema 无迁移，回滚后旧版本可读。

## task.py start 前检查

- [ ] 用户已明确批准最终规划总结（尤其 D2/D3 两个推荐决策）
- [ ] PRD 收敛通过、阻塞问题为空
