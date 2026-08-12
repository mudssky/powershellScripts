# 浏览器调试模式快捷切换实施计划

## Implementation

1. 更新 `schema.ps1`：为 `profile start` 增加 `--yes` flag、帮助文本和 completion 可发现性。
2. 在 `commands.ps1` 增加可 Mock 的切换判断与交互确认逻辑，覆盖交互默认 No、非交互拒绝及 `--yes` 跳过确认。
3. 重构 `Invoke-BrowserDebugProfileStart`：同配置复用；不同模式或显式不同监听地址时确认、停止 owned PID、重新启动，并补齐 `switched` / `stoppedProcessIds` 结果字段。
4. 更新 `runtime.ps1` 快捷方式参数为 `--mode <mode> --open-guide --yes`，保持 Local/LAN 文件名和登记事务不变。
5. 更新 `BrowserDebugProfile.Tests.ps1`：替换“不同模式拒绝”断言，增加确认拒绝、确认执行、`--yes`、非交互/JSON 拒绝、停止失败、启动失败、owned PID 和快捷方式参数测试。
6. 更新 `.trellis/spec/pwsh-scripts/package/browser-debug-cli.md` 的接口、合同、错误矩阵、Good/Base/Bad cases 和测试要求。
7. 重新生成或幂等更新桌面 `edge-debug.lnk` 与 `edge-debug-LAN.lnk`，确认两者携带 `--yes`。

## Validation

1. 运行 Browser Debug 专项 Pester。
2. 运行受影响的 Profile Loading/Mode 窄测。
3. 运行 PowerShell 格式、AST、Markdown 和 CLI help/completion smoke。
4. 运行根目录 `pnpm qa`。
5. 按仓库规则运行 `pnpm test:pwsh:all`；若 Docker 不可用，运行 `pnpm test:pwsh:full` 并注明 Linux 覆盖依赖 CI/WSL。
6. 在用户明确确认关闭当前 `edge-debug` owned 浏览器后，执行真实 Local → LAN → Local smoke；每一步用 `profile status edge-debug --json` 验证实际模式、监听地址和 CDP 可用，并确认其他 Edge 窗口未被停止。

## Risk and Rollback Points

- `commands.ps1` 的停止与重启之间是不可原子化窗口；新实例失败时保留明确错误，不伪造回滚。
- 真实 smoke 会关闭当前 `edge-debug` 浏览器进程，执行前必须单独取得高风险确认。
- 快捷方式与 CLI schema 必须同批切换；若回滚代码，需同步重建旧参数快捷方式。
- 不修改 registry schema，不迁移 Profile 数据，不触碰 SSH 进程。