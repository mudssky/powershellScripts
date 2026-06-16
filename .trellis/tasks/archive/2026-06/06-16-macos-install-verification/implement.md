# macOS 安装验证实施计划

## Checklist

- [x] A1. 更新 `macos/INSTALL.md`，为每个阶段补充前置检查、执行命令、验证命令和失败提示。
- [x] A2. 新增独立的 `macos/06verifyInstall.zsh`，实现统一验证入口和 `--step` 参数。
- [x] A3. 为 repo、brew、pwsh、shell、apps、hammerspoon 分别实现只读检查。
- [x] A4. 确保输出包含 PASS/WARN/FAIL 和汇总，退出码符合设计。
- [x] A5. 在文档中说明 Hammerspoon 辅助功能权限需要用户授权，验证脚本不会自动处理。
- [x] A6. 核对本任务改动不覆盖已有 Hammerspoon 优化任务中的未提交改动。
- [x] A7. 归档旧 `macos/config/.zshrc`，安装流程改为只部署根目录 `shell/` 配置片段，不再替换整个 `~/.zshrc`。

## Validation Commands

```zsh
zsh -n macos/06verifyInstall.zsh
zsh macos/06verifyInstall.zsh --help
zsh macos/06verifyInstall.zsh --step repo
zsh macos/06verifyInstall.zsh --step brew
git diff --check -- macos/INSTALL.md macos/06verifyInstall.zsh .trellis/tasks/06-16-macos-install-verification
pnpm qa
```

## Validation Results

- `zsh -n macos/06verifyInstall.zsh`：通过。
- `zsh macos/06verifyInstall.zsh --help`：通过，显示脚本用法和 `--step` 选项。
- `zsh macos/06verifyInstall.zsh --step repo`：通过，3 passed。
- `zsh macos/06verifyInstall.zsh --step brew`：通过，2 passed。
- `zsh macos/06verifyInstall.zsh --step pwsh`：通过，2 passed。
- `zsh macos/06verifyInstall.zsh --step shell`：通过，3 passed。
- `zsh macos/06verifyInstall.zsh --step apps`：脚本正确返回 1；当前机器缺少 Hammerspoon，其他代表应用通过。
- `zsh macos/06verifyInstall.zsh --step hammerspoon`：脚本正确返回 1；当前机器未安装 Hammerspoon，且 `~/.hammerspoon` 托管文件尚未部署。
- `zsh macos/06verifyInstall.zsh`：脚本正确返回 1；14 passed，7 failed，失败项均指向 Hammerspoon 未安装/未部署。
- `git diff --check -- macos/INSTALL.md macos/06verifyInstall.zsh .trellis/tasks/06-16-macos-install-verification`：通过。
- `pnpm qa`：通过；PowerShell QA 90 passed，0 failed，6 not run，Linux-only QA 在 Darwin 上按脚本规则跳过。
- `zsh -n macos/03deployShellConfig.sh && zsh -n macos/06verifyInstall.zsh && zsh macos/06verifyInstall.zsh --step shell`：通过，确认 shell 验证只依赖 modular loader 和 `~/.bashrc.d` 托管片段。
- `bash shell/deploy.sh --shell zsh --dry-run`：通过，确认会同步 `shell/shared.d` 和 `shell/zsh.d` 的 13 个片段。
- `rg -n "macos/config|config/\\.zshrc|Symlink \\.zshrc|symlink 到" macos .trellis/tasks/06-16-macos-install-verification`：只剩归档说明和设计记录，无安装路径引用。
- 归档后的 `pnpm qa`：通过；PowerShell QA 90 passed，0 failed，6 not run。

## Risky Files

- `macos/INSTALL.md`：需要和实际脚本入口保持同步，避免文档漂移。
- `macos/06verifyInstall.zsh`：必须默认只读，不能在验证路径里写用户目录。
- `macos/03deployShellConfig.sh` 与 `shell/deploy.sh`：安装入口只负责同步 `shell/` 片段，不再替换整个 `~/.zshrc`。
- `macos/archive/config/.zshrc`：旧 macOS `.zshrc` 归档，只作历史参考，不作为安装目标。
- `macos/hammerspoon/*`：已有另一组未提交改动，本任务除非必要不触碰。

## Rollback

- 删除 `macos/06verifyInstall.zsh`。
- 回退 `macos/INSTALL.md` 中新增的验证命令段落。
- 保留 Trellis 规划文件作为任务记录，或在任务取消时删除本任务目录。
