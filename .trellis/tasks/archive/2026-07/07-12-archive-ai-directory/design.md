# 技术设计

## 边界

本任务将 `ai/` 作为一个整体冷归档对象。归档内容仅限 Git 跟踪文件，目标固定为 `archive/ai/`。归档目录只承担历史参考和恢复来源，不作为脚本、测试、workspace 或包管理器的新运行入口。

## 迁移结构

1. 使用 `archive_project.py plan ai` 获取镜像目标、跟踪状态和引用报告。
2. 使用相同参数执行 `archive ... --execute`，由工具完成 `git mv ai archive/ai` 并更新 `archive/index.json`。
3. 在独立变更中清理仓库活动层面的引用：
   - 从 `pnpm-workspace.yaml` 移除 `ai/skills/dev/*`，并用 pnpm 更新 lockfile。
   - 从 `Manage-BinScripts.ps1` 的文档和默认模式移除 `ai/` 扫描入口。
   - 从 `powershellScripts.code-workspace` 移除 AI 专属排除项。
   - 从根 `README.md`、`CLAUDE.md` 的活动目录说明中移除 `ai/`。
   - 删除只针对已归档入口的 `Sync-ClaudeConfig.Tests.ps1`、`SkillsInstaller.Tests.ps1` 和 `LiteLLMStart.Tests.ps1`。
   - 将 `.trellis/spec/infra/` 下 4 份 AI 专属规范按原路径镜像归档，并更新 infra 规范索引。
4. 使用精确路径检索确认活动树中没有残留运行引用，不把第三方文档中的 `claude.ai`、模型名或普通英文单词 `ai` 当作路径引用。

## 本机内容处理

忽略文件、secret、依赖和生成物不进入归档索引，也不由归档工具迁移。由于这些内容可能含用户状态，执行时只报告并保留，不自动删除。Git 跟踪目录迁移后，原 `ai/` 可能因这些本机内容继续存在；验收以“无 Git 跟踪内容和无仓库活动入口”为准。

## 提交边界

- 提交 1：仅执行 `ai/` 到 `archive/ai/` 的 Git 移动并更新 `archive/index.json`。
- 提交 2：清理 workspace、脚本、测试、文档、lockfile 和活动规范入口；AI 专属规范分别使用归档工具建立索引项。
- 不在提交 1 中改写迁入归档的正文，保证 Git rename 识别和历史可追踪性。

## 兼容与回滚

该变更有意停止本仓库中的 AI 工具兼容入口。需要恢复时，反向 `git mv archive/ai ai`、删除对应索引条目，并恢复第二个提交移除的 workspace、脚本、测试和文档引用；随后重新运行质量门禁。

## 风险

- 归档工具的宽泛文本引用扫描可能产生大量 `ai` 子串误报，执行前需人工区分真实路径引用。
- pnpm workspace 成员移除会改动根 lockfile，必须通过 `pnpm install --lockfile-only` 或仓库既有命令机械更新。
- 删除 AI 专属测试后，必须确保剩余测试清单和 QA 脚本不再硬编码这些测试文件。
- 本机忽略内容可能使原 `ai/` 目录继续可见，但不得因此删除用户 secret 或运行状态。
