# 冷归档索引

本目录保存已经退出活动维护范围、但仍有历史追溯或恢复参考价值的内容。归档路径镜像原始仓库相对路径，文件继续由 Git 跟踪，也可以通过普通搜索或 `git log --follow` 查找历史。

归档内容不承诺继续可执行，默认不参与 workspace、构建、测试、格式化、lint 和发布流程。提交前的 secret 安全扫描仍覆盖本目录。

## 已批准批次

| 批次 | 原路径 | 归档路径 | 归档原因 | 替代入口或恢复说明 |
|---|---|---|---|---|
| 1 | `deprecated/**` | [`archive/deprecated/**`](./deprecated/) | 旧脚本已失效、被替代或不再维护 | `concatflv.ps1` 使用 [`scripts/pwsh/media/concatflv.ps1`](../scripts/pwsh/media/concatflv.ps1)；其余文件仅供历史参考 |
| 1 | `profile/deprecated/**` | [`archive/profile/deprecated/**`](./profile/deprecated/) | 旧 Linux Profile 已被模块化 Profile 替代 | 使用 [`profile/profile.ps1`](../profile/profile.ps1) |
| 1 | `macos/archive/**` | [`archive/macos/archive/**`](./macos/archive/) | LaunchAgent 合盖轮询方案无法可靠阻止残留进程 | 使用 [`macos/hammerspoon/`](../macos/hammerspoon/) 和 [`macos/09deployHammerspoon.zsh`](../macos/09deployHammerspoon.zsh) |
| 1 | `config/frontend/deprecated/**` | [`archive/config/frontend/deprecated/**`](./config/frontend/deprecated/) | 旧 Biome v1 与 Prettier 配置已退出当前工具链 | 使用根 [`biome.json`](../biome.json) |
| 1 | `config/vscode/back/**` | [`archive/config/vscode/back/**`](./config/vscode/back/) | 历史 VS Code Vim 配置备份无活动引用 | 当前配置位于 [`config/vscode/settings/`](../config/vscode/settings/) 与 [`config/vscode/neovim/`](../config/vscode/neovim/) |
| 1 | `config/software/pixpin/deprecated/**` | [`archive/config/software/pixpin/deprecated/**`](./config/software/pixpin/deprecated/) | 日期化旧配置快照不再作为当前真源 | 使用 [`config/software/pixpin/PixPin.pixconf`](../config/software/pixpin/PixPin.pixconf) |
| 2 | `.vercel/project.json` | [`archive/.vercel/project.json`](./.vercel/project.json) | 本仓已停止使用 Vercel 部署 | 仅保留旧项目标识，无活动替代入口 |
| 2 | `ipynb/renameLegal.ipynb` | [`archive/ipynb/renameLegal.ipynb`](./ipynb/renameLegal.ipynb) | Notebook 已有受维护的 PowerShell 脚本替代 | 使用 [`scripts/pwsh/filesystem/renameLegal.ps1`](../scripts/pwsh/filesystem/renameLegal.ps1) |

## 恢复规则

恢复某一项前，应先确认它仍有明确使用场景、当前维护负责人和质量门禁。恢复使用反向 `git mv`，并同步更新本索引和相关活动文档；不要直接从归档路径建立新的安装或运行入口。
