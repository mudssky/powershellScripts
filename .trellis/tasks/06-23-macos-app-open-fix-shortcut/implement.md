# macOS 应用打不开右键修复快捷指令执行计划

## Implementation Checklist

- [x] 新增 `macos/quick-actions/` 目录。
- [x] 新增通用分派器 `macos/quick-actions/run.zsh`，通过动作 ID 触发具体快捷操作。
- [x] 新增处理脚本 `macos/quick-actions/fix-app-open-issue.zsh`，实现批量 `.app` 诊断、清除 quarantine 和打开。
- [x] 新增 Finder Quick Action/Automator workflow 资产，调用处理脚本并接收 Finder 选中项。
- [x] 新增批量安装脚本 `macos/08installQuickActions.zsh`，把 workflow 安装到 `~/Library/Services`。
- [x] 更新 `macos/INSTALL.md`，加入安装步骤、验证方式、使用方式和安全边界。
- [x] 按需更新 `macos/06verifyInstall.zsh`，增加 quick actions 的可发现性检查。
- [x] 本地验证安装脚本 dry-run、真实安装路径和处理脚本的非 `.app` 跳过逻辑。

## Validation Commands

```zsh
zsh macos/08installQuickActions.zsh --dry-run
zsh macos/08installQuickActions.zsh
test -d "$HOME/Library/Services/Fix App Open Issue.workflow"
zsh macos/quick-actions/fix-app-open-issue.zsh /tmp/not-an-app
pnpm qa
```

若实现改动涉及 PowerShell 或 `profile/**`，追加：

```zsh
pnpm test:pwsh:all
```

## Risky Files

- `macos/06verifyInstall.zsh`：已有多步骤验证逻辑，若修改需保持其他步骤行为不变。
- `macos/INSTALL.md`：新增步骤编号可能影响现有文档引用，需要保持流程清楚。
- `~/Library/Services`：安装脚本写入用户本机服务目录，应支持 dry-run，并避免删除用户已有服务。

## Review Gate

实现前需要用户确认本规划进入 Phase 2。启动后执行：

```zsh
python3 ./.trellis/scripts/task.py start 06-23-macos-app-open-fix-shortcut
```
