# implement: skills installer private module split

## Checklist

1. 准备任务状态
   * 补齐 `design.md` 与 `implement.md`。
   * 执行 `task.py start` 将任务状态切到 `in_progress`。
2. 新建私有脚本目录
   * 创建 `ai/skills/private/bootstrap.ps1`。
   * 创建 `ai/skills/private/plan.ps1`。
   * 创建 `ai/skills/private/presentation.ps1`。
   * 创建 `ai/skills/private/execution.ps1`。
3. 迁移函数
   * 将无 CLI 参数依赖的 helper 按边界移动到私有脚本。
   * 入口脚本保留参数、共享模块导入、私有脚本加载、`Invoke-SkillsInstallMain` 与最终执行块。
   * 保留原有 comment-based help，不改变函数名和参数。
4. 验证兼容性
   * `pnpm exec pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Path ./tests/SkillsInstaller.Tests.ps1`
   * `pnpm qa`
   * `pnpm test:pwsh:all`
5. Review gate
   * 确认 `Install-Skills.ps1` 行数明显下降。
   * 确认没有新增 `psutils` 领域外逻辑。
   * 确认工作区只包含本任务相关文件。

## Rollback Points

* 私有脚本加载失败：先检查 dot-source 路径和加载顺序。
* 函数不可见：确认测试仍 dot-source 入口脚本，而不是直接调用私有脚本。
* 行为回归：通过 `git diff` 比对迁移块，优先恢复对应函数原文再缩小拆分范围。
