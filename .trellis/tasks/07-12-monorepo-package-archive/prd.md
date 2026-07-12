# 设计 monorepo 包归档流程

## Goal

为 monorepo 中已停用、被替代或只具历史价值的包建立可重复、可审计、可恢复的归档流程，并以 `projects/clis/json-diff-tool` 作为首个候选审计对象。

## Background

- `projects/clis/json-diff-tool` 当前仍是活动的 pnpm workspace 包：`pnpm-workspace.yaml` 的 `projects/**` 会自动包含它。
- 该包有源码、测试、README、TypeScript/Vitest/Biome 配置，以及 `build`、`qa`、`test`、`typecheck`、`prepublishOnly` 脚本和 `json-diff` CLI 入口。
- `pnpm-lock.yaml` 仍有对应 importer，`.trellis/spec/json-diff-tool/package/index.md` 仍有包级规范。
- `CLAUDE.md:88` 和 `CLAUDE.md:244` 仍把该包列入目录与 QA 说明。
- `powershellScripts.code-workspace:36` 仍将该包添加为 workspace folder。
- `scripts/pwsh/misc/Compare-JsonFiles.ps1:245` 是该 CLI 的包装器，但它以 `$PSScriptRoot` 为基础查找 `clis/json-diff-tool`，实际会指向不存在的 `scripts/pwsh/misc/clis/json-diff-tool`；其 `--file`、`--ignore-array-order` 等参数也与当前 CLI 契约不一致，因此它不是当前可用的活动入口。
- 仓库代码中未找到对 `json-diff-tool` package 或其源码的其他运行时依赖；`scripts/node` 使用的 `json-diff` 是独立的 npm 依赖，不是本地 `json-diff-tool`。
- `projects/clis/json-diff-tool/README.md` 的安装方式、目录结构、脚本名称和部分 CLI 参数已与当前实现不一致，不能单独作为包仍在使用的证据。
- 该包近期仍有依赖升级和 CI 修复提交，不能仅根据目录位置或使用频率判定为废弃。

## Requirements

- 本次先产出可复用的 monorepo 包归档方案，并将 `json-diff-tool` 作为候选对象完成审计；在证据与迁移前置条件明确前，不预先批准实际归档。
- `json-diff-tool` 的 JSON 对比能力已确认不再需要；不为它实现替代工具、兼容入口或后续维护路径。
- 已失效的 `scripts/pwsh/misc/Compare-JsonFiles.ps1` 与 package 一并按原路径镜像归档，不直接删除。
- 本次不扩展 `archive_project.py` 的 monorepo 解析能力；先以明确清单和首个实例验证 package 归档门禁，再根据重复需求决定是否自动化。
- 归档流程必须先区分“已废弃包”、“被替代包”、“暂停维护但仍可用的包”与“仅历史保留的包”。
- 归档前必须审计 workspace/lockfile、构建与测试、CLI 或发布入口、跨包依赖、脚本调用、CI、IDE 配置、工程文档和 Trellis 规范引用。
- 存在活动用户入口、未替代功能或发布路径时，不得直接归档。
- 冷归档目标路径应保留原目录结构，即 `archive/projects/clis/json-diff-tool`。
- 归档后的包不应再被正常 workspace 构建、测试、发布、依赖更新或 IDE 工作区发现，除非最终决策明确要求保留某项能力。
- 归档操作必须可通过结构化索引追溯原路径、归档原因、替代方案、日期与恢复方式。
- 归档移动与必要的活动引用清理需有清晰的提交边界，不在同一步改写被归档源码的业务行为。
- 将 package 归档门禁补充到现有仓库归档规范，不新建并行的归档规范或索引。

## Acceptance Criteria

- [x] 定义可执行的包归档资格判定与阻断条件。
- [x] 定义归档前的引用与运行入口审计清单。
- [x] 定义包退出 workspace、lockfile、CI、IDE、工程文档和包级规范的处理方式。
- [x] 定义 `archive/<原路径>` 布局、索引元数据和恢复流程。
- [x] 对 `json-diff-tool` 给出有证据的结论：功能已停用且无活动依赖，可进入归档规划。
- [x] `json-diff-tool` 的所有活动引用已清理，并通过归档、workspace 与质量门禁验证。
- [x] 现有归档规范包含 monorepo package 的资格审计、退出清单和恢复要求。

## Out Of Scope

- 在规划获得批准前移动 `json-diff-tool` 或修改其源码。
- 归档与本任务无关的其他 package、文档或工具。
- 处理当前工作区中与 `psutils` 相关的并行改动。
