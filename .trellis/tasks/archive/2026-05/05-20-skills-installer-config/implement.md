# implement: skills 安装器第一轮瘦身

## Checklist

1. 新增 `psutils/modules/process.psm1`
   * 实现命令格式化、可执行路径解析、日志文件、日志行、外部命令执行。
   * 每个公共函数补充中文 comment-based help，包含参数和返回值说明。
   * 通过 `Export-ModuleMember` 精确导出。
2. 新增 `psutils/tests/process.Tests.ps1`
   * 覆盖命令格式化和含空格/引号参数。
   * 覆盖日志文件创建与空日志路径 no-op。
   * 覆盖外部命令成功、日志退出码、静默输出。
   * 覆盖非零退出时抛错与 `AllowFailure` 返回结果。
3. 更新 `psutils/psutils.psd1`
   * 将 `modules\process.psm1` 加入 `NestedModules`。
   * 将新增公共函数加入 `FunctionsToExport`。
4. 更新 `ai/skills/Install-Skills.ps1`
   * 导入 `psutils/modules/process.psm1`。
   * 删除或替换脚本内 `Format-SkillsCommandLine`、`Resolve-SkillsExecutablePath`、`New-SkillsLogFile`、`Write-SkillsLogLine`、`Invoke-SkillsExternalCommand`。
   * 把默认 `CommandRunner` 改为调用 `Invoke-NativeCommand`，支持 `SuppressOutput`。
   * 保留 skills 领域逻辑在脚本内。
5. 更新 `tests/SkillsInstaller.Tests.ps1`
   * 将外部命令执行回归改为验证公共 `Invoke-NativeCommand` 或默认 runner 行为。
   * 调整 runner 替身签名，覆盖 `SuppressOutput` 参数。
6. 验证
   * 定向：`pnpm exec pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Path ./psutils/tests/process.Tests.ps1`
   * 定向：`pnpm exec pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Path ./tests/SkillsInstaller.Tests.ps1`
   * 根目录：`pnpm qa`
   * 提交前：`pnpm test:pwsh:all`

## Review Gate

确认第一轮 diff 中没有把 agent/ctx7/skills 配置语义移动到 `psutils`，且 `Install-Skills.ps1` 行数下降、公共模块有独立测试。
