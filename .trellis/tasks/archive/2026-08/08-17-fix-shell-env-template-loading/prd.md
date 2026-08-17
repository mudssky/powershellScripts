# 修复 Shell 环境模板误加载

## Goal

防止可提交的本机环境变量模板被 `shell/deploy.sh` 当作活动 `*.sh` 配置部署并 source，避免 `sk-REPLACE_ME` 等占位值污染交互 shell，同时保留真实 `env.local.sh` 的既有加载行为。

## Confirmed Facts

- `shell/deploy.sh:254` 通过 `"$source_dir"/*."$ext"` 枚举共享脚本，`shared.d` 使用扩展名 `sh`。
- `shell/shared.d/env.local.example.sh` 以 `.sh` 结尾，因此会被部署到 `~/.bashrc.d/`。
- `cleanup_stale_symlinks` 会删除重命名后指向不存在源文件的旧软链接。

## Requirements

- 将模板重命名为 `shell/shared.d/env.local.sh.example`，使其不匹配活动脚本 glob。
- 更新模板文件头、复制命令及仓库内有效引用；历史归档任务保持不变。
- `shell/deploy.sh` 显式跳过误命名为 `*.example.sh` 或 `*.sample.sh` 的模板，形成防御性边界。
- 真实私有文件继续使用 `shell/shared.d/env.local.sh`，保持 gitignore 和部署行为不变。
- 日志与测试不得输出任何真实密钥；模板仅保留占位值。

## Acceptance Criteria

- [x] 仓库中活动模板路径为 `shell/shared.d/env.local.sh.example`，旧路径不存在。
- [x] dry-run/隔离 HOME 验证模板不会创建 `~/.bashrc.d/env.local.sh.example` 或 `env.local.example.sh` 链接。
- [x] `env.local.sh` 仍会被部署为 `~/.bashrc.d/env.local.sh`。
- [x] 即使存在 `*.example.sh` 或 `*.sample.sh` 文件，部署逻辑也会跳过。
- [x] `bash -n shell/deploy.sh` 和相关 Bash 测试通过；最终执行仓库要求的 `pnpm qa`。

## Out of Scope

- 不修改本机真实 `env.local.sh` 内容或任何密钥。
- 不修改 PowerShell profile 的环境变量解析规则。
- 不处理当前工作树中无关的 Trellis 任务目录。
