# 仓库冷归档批次实施计划

## 1. 启动前检查

- [x] 确认任务状态已由用户审阅后切换为 `in_progress`。
- [x] 使用 `trellis-before-dev` 加载根规范、PowerShell 脚本规范和 `pwshfmt-rs` 规范。
- [x] 记录 `git status --short`，只处理本子任务文件，不修改或提交 Nix 子任务目录。
- [x] 再次确认 PRD R1 的 8 个源对象存在，未批准目录仍在原位。

## 2. 建立归档合同

- [x] 新增 `archive/README.md`，写入设计文档定义的 5 列索引和归档生命周期说明。
- [x] 更新根 `README.md` 目录树：展示 `archive/`，移除根 `deprecated/` 的活动目录描述。
- [x] 在 `biome.json`、`.rumdl.toml`、`ruff.toml`、`package.json` 和 `lint-staged.config.js` 中落实 `archive/**` 排除。
- [x] 保持 betterleaks 暂存区安全扫描覆盖归档文件。

## 3. PowerShell 格式器排除

- [x] 为 `pwshfmt-rs` 配置和 CLI 增加排除路径字段，默认仓库配置排除 `archive`。
- [x] 在目录递归和 Git changed discovery 中应用同一排除规则，目录遍历时直接剪枝。
- [x] 同步 `Format-PowerShellCode.ps1` 的预览、快速退出和实际调用语义。
- [x] 补充 Rust 测试：普通文件仍被发现，递归扫描跳过 `archive/**`，Git changed 跳过 `archive/**`，配置与 CLI 覆盖顺序保持稳定。
- [x] 如包装脚本新增公共参数或函数，按项目要求补充参数与返回值说明。

## 4. 执行镜像移动

- [x] 使用 `git mv deprecated archive/deprecated`。
- [x] 使用 `git mv profile/deprecated archive/profile/deprecated`。
- [x] 使用 `git mv macos/archive archive/macos/archive`。
- [x] 使用 `git mv config/frontend/deprecated archive/config/frontend/deprecated`。
- [x] 使用 `git mv config/vscode/back archive/config/vscode/back`。
- [x] 使用 `git mv config/software/pixpin/deprecated archive/config/software/pixpin/deprecated`。
- [x] 使用 `git mv .vercel/project.json archive/.vercel/project.json`。
- [x] 使用 `git mv ipynb/renameLegal.ipynb archive/ipynb/renameLegal.ipynb`。
- [x] 不改写被移动文件内容；检查 Git 是否识别为 rename。

## 5. 引用和边界复核

- [x] 搜索 8 个原路径、目录名和具体文件名，修复现行引用，保留历史任务中的旧路径。
- [x] 确认 `docs/cheatsheet/**`、`ai/docs/**`、`linux/wsl2/deprecated/**`、`config/vscode/neovim/dreprecated/**` 等未批准对象未移动。
- [x] 确认 `pnpm-workspace.yaml` 和 Turbo 任务图不匹配 `archive/**`。
- [x] 确认归档内容仍被 `git ls-files archive` 跟踪，并可被 `rg --hidden` 定向搜索。

## 6. 验证

- [x] 运行 `cargo test --manifest-path projects/clis/pwshfmt-rs/Cargo.toml`。
- [x] 运行 PowerShell 格式器的归档排除窄测或 `-ShowOnly` 检查。
- [x] 运行 Biome、rumdl、Ruff 和 notebook 清理的定向 dry-run/检查，确认不处理 `archive/**`。
- [x] 运行 `pnpm qa`。
- [x] 运行 `pnpm test:pwsh:all`；若 Docker 不可用，按仓库规则记录替代验证和 Linux 覆盖缺口。
- [x] 移动提交完成后运行 `git log --follow -- archive/deprecated/concatflv.ps1`，确认能看到移动前提交。

## 7. 提交与回滚点

- [x] 提交 `9e83a4d feat(repo): 建立冷归档结构与工具排除合同`，包含镜像移动、索引、formatter 和工具排除。
- [x] 提交 `0368941 fix(qa): 保留编排器注入的测试路径`，修复 changed 测试集到 Pester 的传递。
- [x] 提交 `chore(task): archive 07-10-repository-archive-batch`，由 Trellis 归档流程创建。
- [x] 如单项发现活动依赖，反向移动该项并从 `archive/README.md` 删除对应索引行；本批次未触发回滚。

## 8. 验证结果

- `pnpm qa`：194 通过，0 失败，2 跳过。
- macOS 主机全量：759 通过，0 失败，6 跳过。
- Linux Docker 全量：756 通过，0 失败，9 跳过；其中 Git-only formatter 用例因镜像未安装 Git 明确跳过，递归排除用例已通过。
- `pnpm --filter pwshfmt-rs qa`：16 个单元/集成测试全部通过，Clippy 与 typecheck 通过。
- `git log --follow -- archive/deprecated/concatflv.ps1`：可追溯到迁移前提交 `02f615f`、`a541407`、`da50054`。
