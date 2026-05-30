# 整理根目录结构

## Goal

让项目根目录更简洁、更容易扫读。优先处理已经不再作为入口使用的工具配置与运行产物，例如根目录 `.mcp.json`，并形成可重复的归档/迁移规则，避免后续 AI 工具、测试报告、缓存目录继续堆在根目录。

用户价值：

- 打开仓库根目录时，优先看到项目入口、构建配置和源码目录。
- AI/MCP 相关配置有稳定归属，不需要靠记忆区分根目录文件是否仍有效。
- 运行产物和本地数据目录不会与可维护源码混在一起。

## Confirmed Facts

- 根目录当前存在大量平台/工具配置目录，包括 `.agents`、`.claude`、`.codex`、`.promptx`、`.serena`、`.trae`、`.vscode`、`.vercel`、`.trellis`。
- `.mcp.json` 是已跟踪文件，包含多个 MCP server 配置；除 `context7` 外，其余大多处于 `disabled: true` 状态。
- 仓库已经存在更专门的 MCP 配置归档位置：`ai/mcp/mcps/*.json`、`ai/mcp/trae/mcp.json`、`ai/mcp/mcp-superassistan/config.json`。
- Codex 当前 MCP 配置已经存在于 `ai/coding/codex/config.toml`，其中包含 `context7` 与 `serena` 配置。
- `config/gemini-cli/settings.json` 也包含 MCP 配置。
- `.mcp.json` 在仓库内仅被自身和 Claude Code 文档示例引用；没有发现源码、测试或脚本依赖它作为运行输入。
- `.gitignore` 已忽略 `coverage.xml`、`testResults.xml`、`vitest-report.xml`、`node_modules` 等运行产物。
- 当前工作区存在未跟踪 `.shrimp-data/`，根目录 `.mcp.json` 中的 `shrimp-task-manager` 配置使用 `DATA_DIR=.shrimp-data`，但该 MCP server 已禁用。
- `.betterleaksignore` 是已跟踪文件；仓库文档 `docs/cheatsheet/security/Betterleaks.md` 明确说明 Betterleaks 忽略文件放在仓库根目录。
- `projects/**` 是 pnpm workspace 的正式入口，`package.json`、`pnpm-workspace.yaml`、Dependabot 配置和 README 均引用该目录。
- 根目录 `self-hosted/forgejo` 已有 Trellis infra 规范和任务文档作为正式自托管服务入口；`ai/self-hosted/lobehub` 仍是 AI 相关自托管服务入口。
- `blockDanmuku` 是已跟踪的 UTF-8 文本规则文件，当前文件名缺少扩展名，语义不像根目录项目入口。
- 根目录 `ipynb/` 当前只包含 `renameLegal.ipynb`，仓库文档更常用的命名是 `notebooks/`。
- 当前工作区还有其他未提交改动，本任务不得回滚或混入无关变更。

## Recommended Classification

建议第一轮整理对象：

- `.mcp.json`：直接迁到 `ai/mcp/` 下，不保留根目录副本。
- `.shrimp-data/`：作为本地运行数据处理，加入 `.gitignore` 并从根目录噪音中移除；不归档。
- `.playwright/`、`.ruff_cache/`、`.rumdl_cache/`、`coverage.xml`、`testResults.xml`、`vitest-report.xml`：作为工具缓存或报告处理；已有忽略项的保持，缺失的补 `.gitignore`。
- `gitconfig_company.ps1`：未跟踪本地配置，建议纳入 `.gitignore` 或迁到 `config/git/` 后改名为示例文件；不应继续以未跟踪文件留在根目录。
- `blockDanmuku`：从根目录搬到 `config/danmaku/block-danmuku.txt`，并补扩展名。
- `.serena/` 与禁用的 serena MCP 配置：不再使用，从仓库移除，并加入 `.gitignore` 防止本地状态目录重新进入跟踪。
- `.gitignore`：按类别分块整理，并补充简洁中文注释。

建议暂不整理或只记录原因：

- `.betterleaksignore`：保留根目录，外部工具有根目录约定。
- `.editorconfig`、`.gitattributes`、`.gitignore`、`.husky`、`.github`、`package.json`、`pnpm-lock.yaml`、`pnpm-workspace.yaml`、`turbo.json`、`biome.json`、`ruff.toml`、`.rumdl.toml`：保留根目录，属于工具入口或仓库级配置。
- `.agents`、`.claude`、`.codex`、`.trellis`、`.vscode`：保留根目录，工具可能直接读取。
- `.promptx`、`.trae`、`.vercel`：先保留根目录，后续单独确认工具是否支持迁移或是否仍使用。
- `projects/`：保留根目录，属于 workspace 正式目录。
- `self-hosted/`：保留根目录，已有 infra 规范；但后续可单独讨论是否把 AI 相关自托管服务统一迁到 `ai/self-hosted` 或反向合并。
- `deprecated/`、`todos/`、`templates/`：短期保留；如要收敛，可作为第二阶段目录命名治理处理。
- `ipynb/`：本轮不改名。
- `todos/`：用户已迁移到 `docs/todos/`，本轮纳入根目录收敛提交，并同步旧路径引用。

## Naming Recommendations

- 根目录目录名优先使用稳定领域名：`scripts`、`profile`、`psutils`、`config`、`docs`、`tests`、`projects`、`self-hosted`。
- 工具专用隐藏目录只在工具强约定读取根目录时保留，例如 `.codex`、`.claude`、`.trellis`。
- 可迁移的 AI 配置统一放入 `ai/<domain>/<tool>/` 或 `ai/mcp/<client>/`，避免根目录出现新的 `.xxx.json` 聚合配置。
- 本地运行数据和缓存使用 `.gitignore` 管理，不放入 `ai/` 或 `config/` 归档。
- Notebook 目录本轮保持 `ipynb/`。
- 无扩展名的数据/规则文件建议补扩展名，例如 `*.txt`、`*.json`、`*.yaml`，提高编辑器和搜索体验。
- 自托管服务如果是通用基础设施，放 `self-hosted/<service>/`；如果强绑定 AI 产品栈，可放 `ai/self-hosted/<service>/`，但不要同一类服务长期两套规则并存而无说明。

## Requirements

- 根目录整理必须先定义归属规则，再做文件迁移或清理。
- 不再作为真实入口使用的 AI/MCP 聚合配置应迁出根目录，归档到 `ai/mcp/`。
- 仍被外部工具约定必须放在根目录的文件或目录，需要保留并记录原因。
- 运行产物、缓存和本地数据目录不应作为归档对象；应通过 `.gitignore`、清理命令或工具配置避免污染根目录。
- 所有迁移都必须检查引用并同步更新文档或配置，避免保留断链说明。
- 不处理已有无关未提交改动。
- `.gitignore` 必须按类别分块整理，并为每组规则补充简洁中文注释。

## Acceptance Criteria

- [x] 形成根目录文件/目录分类清单：保留根目录、迁入 `ai/`、迁入 `config/`、仅忽略/清理、待确认。
- [x] 明确 `.mcp.json` 的目标归档位置，并说明是否保留根目录兼容副本。
- [x] 若移动 `.mcp.json`，仓库内对旧路径的说明或引用被同步更新。
- [x] `.shrimp-data/`、测试报告、缓存目录等运行产物有明确处理策略，不作为源码类归档。
- [x] `.serena/` 不再作为跟踪文件出现，禁用的 serena MCP 配置已移除，并通过 `.gitignore` 防止重新进入工作区。
- [x] `blockDanmuku` 不再位于根目录，目标文件名带清晰扩展名。
- [x] `ipynb/` 保持现状，不纳入本轮迁移。
- [x] `todos/` 已迁移到 `docs/todos/`，旧路径引用已同步。
- [x] `.gitignore` 已按类别分块，并包含中文注释。
- [x] 变更后 `git status` 中不混入本任务之外的文件修改。
- [x] 若只移动配置/文档，不强制新增单元测试；若修改脚本逻辑，则执行根目录 `pnpm qa`。

## Out of Scope

- 重构 PowerShell 脚本目录、`psutils`、测试架构或构建流程。
- 合并或删除 `.claude`、`.codex`、`.agents`、`.trellis` 等当前工具仍可能直接读取的根目录配置。
- 清理用户已有未提交改动。
- 删除本地个人配置或数据，除非用户明确要求。

## Open Questions

- 无。

## Notes

- 本任务当前处于规划阶段。用户批准实施前，不移动根目录文件。
