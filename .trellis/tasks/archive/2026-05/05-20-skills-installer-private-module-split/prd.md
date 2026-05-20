# skills installer private module split

## Goal

把 `ai/skills/Install-Skills.ps1` 中仍然偏大的 skills 领域逻辑拆到 `ai/skills` 私有模块中，让入口脚本保留 CLI 参数、模块加载和高层流程。

## Requirements

* 私有模块只服务 skills 安装器，不进入 `psutils`。
* 优先拆清晰边界：agent 目录检查、配置计划生成、执行步骤、展示/确认。
* 拆分后入口脚本应更短，但行为、参数和测试保持兼容。
* 需要决定是否采用 source-first 结构，以及是否保留单文件入口。

## Acceptance Criteria

* [ ] 有独立 `design.md` 和 `implement.md` 描述模块边界、文件布局和迁移顺序。
* [ ] 拆分后 `Install-Skills.ps1` 入口明显变薄。
* [ ] 现有 `tests/SkillsInstaller.Tests.ps1` 继续覆盖核心行为，必要时补充模块级测试。
* [ ] 不把 skills 领域逻辑搬进 `psutils`。

## Out of Scope

* 新增配置字段或变更安装语义。
* 抽通用路径/env helper。
