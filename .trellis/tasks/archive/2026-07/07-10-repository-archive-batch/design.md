# 仓库冷归档批次技术设计

## 1. 边界

本任务只处理 PRD R1 中已批准的 8 个对象。`archive/` 是冷内容的唯一根目录，内部镜像原始相对路径，不按语言、平台或文件类型重新分类。

| 原路径 | 目标路径 | 替代入口或恢复说明 |
|---|---|---|
| `deprecated/**` | `archive/deprecated/**` | `concatflv.ps1` 由 `scripts/pwsh/media/concatflv.ps1` 替代；其余文件仅保留历史参考 |
| `profile/deprecated/**` | `archive/profile/deprecated/**` | 当前模块化入口为 `profile/profile.ps1` |
| `macos/archive/**` | `archive/macos/archive/**` | 当前入口为 `macos/hammerspoon/` 与 `macos/09deployHammerspoon.zsh` |
| `config/frontend/deprecated/**` | `archive/config/frontend/deprecated/**` | 当前根 `biome.json` 使用 Biome 2 |
| `config/vscode/back/**` | `archive/config/vscode/back/**` | 当前配置位于 `config/vscode/settings/` 与 `config/vscode/neovim/` |
| `config/software/pixpin/deprecated/**` | `archive/config/software/pixpin/deprecated/**` | 当前配置源为 `config/software/pixpin/PixPin.pixconf` |
| `.vercel/project.json` | `archive/.vercel/project.json` | 本仓不再使用 Vercel 部署，仅保留旧项目标识 |
| `ipynb/renameLegal.ipynb` | `archive/ipynb/renameLegal.ipynb` | 当前入口为 `scripts/pwsh/filesystem/renameLegal.ps1` |

## 2. 归档索引合同

`archive/README.md` 使用一张稳定索引表，每行对应一个批准对象，字段固定为：

1. 批次：沿用候选清单中的“批次 1”或“批次 2”。
2. 原路径：移动前的仓库相对路径。
3. 归档路径：当前仓库相对路径。
4. 原因：说明失效、被替代或仅具历史价值的原因。
5. 替代入口或恢复说明：有现行入口时提供可点击相对链接；没有替代入口时明确“仅供历史参考”。

索引正文同时声明：归档内容仍由 Git 跟踪和普通搜索覆盖，但不承诺可执行性，也不参与默认质量门禁。

## 3. 引用迁移

- 更新根 `README.md` 的目录树，增加 `archive/` 并移除根 `deprecated/` 的活动目录描述。
- 不修改 `.trellis/tasks/archive/**`、父任务研究材料或其他历史设计中的旧路径，因为这些文件记录的是当时状态。
- 移动后重新搜索目录名和具体文件名；只有仍代表当前入口的引用才改写。

## 4. Git 历史

- 所有对象使用 `git mv`，不复制后删除，也不在同一提交中重写归档文件内容。
- Git 的重命名识别依赖内容相似度；保持内容不变可提高单文件 `git log --follow` 的可追溯性。
- 空的 `.vercel/`、`ipynb/` 等源目录由 Git 自然消失，不创建占位文件。

## 5. 默认流程排除

### 5.1 Workspace、构建、测试和发布

`pnpm-workspace.yaml` 只包含 `projects/**`、若干明确脚本包和配置包，`archive/**` 不匹配这些路径。Turbo 只调度 workspace 包，因此无需扩大 workspace 配置；验证阶段以命令和路径断言确认该边界。

Pester、Vitest、Bash QA 和发布入口均使用明确的活动路径。归档路径不加入测试发现、coverage 或发布清单。

### 5.2 格式化和 lint

- Biome：在根 `biome.json` 的 `files.includes` 中加入对 `archive/**` 的 force-ignore，避免扫描和格式化归档 JSON/JSONC。
- rumdl：在 `.rumdl.toml` 的全局排除列表中加入 `archive`。
- Ruff：在根 `ruff.toml` 中加入 `archive` 排除，形成跨文件类型的一致归档合同。
- Notebook：根 `nb:clean` 命令显式排除 `archive`。
- lint-staged：在任务分派前过滤 `archive/**`，避免 Biome、rumdl、PowerShell 格式器、Ruff、Stylua 和 nbstripout处理归档文件。
- betterleaks：保持对所有暂存内容的安全扫描。归档仍会进入 Git 历史，不能因为生命周期变冷而绕过 secret 检查。

### 5.3 PowerShell 格式器

`pwshfmt-rs` 增加通用的排除路径配置与 CLI 参数，仓库默认配置排除 `archive`。发现逻辑在遍历目录前剪枝，并在 Git changed 结果进入集合前过滤，覆盖两种默认入口。

PowerShell 包装脚本继续复用 Rust CLI；其预览和快速退出逻辑使用同一排除合同，避免包装层显示将处理归档文件而底层实际跳过。

## 6. 兼容性与回滚

- 这是路径迁移，不提供旧路径 shim；用户此前已批准这些入口退出活动结构。
- 若验证发现真实活动引用，优先回滚对应单项移动并将其恢复为待确认，而不是放宽整个归档目录的默认排除。
- 整批回滚可反向 `git mv` 并撤销工具排除配置；归档文件内容未改写，因此回滚不需要数据转换。

## 7. 验证策略

- 静态检查：逐项确认源路径消失、目标路径存在、未批准目录保持原位。
- 引用检查：搜索原目录和文件名，区分现行引用与历史记录。
- 工具检查：Biome、rumdl、Ruff、lint-staged 和 pwshfmt 对归档 fixture 或真实移动文件均不产生处理动作。
- 回归检查：`pnpm qa`、`pnpm test:pwsh:all`。
- 历史检查：对 `archive/deprecated/concatflv.ps1` 等单文件执行 `git log --follow`。
