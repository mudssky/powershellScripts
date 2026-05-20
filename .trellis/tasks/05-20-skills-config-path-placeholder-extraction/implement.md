# implement: config path placeholder extraction

## Checklist

1. 更新 `psutils/src/config/convert.ps1`
   * 新增 `Resolve-ConfigEnvPlaceholder`。
   * 新增 `Resolve-ConfigPath`。
   * 公共函数补充中文 comment-based help。
2. 更新 `psutils/modules/config.psm1`
   * 导出新增函数。
3. 更新 `psutils/psutils.psd1`
   * 将新增函数加入 `FunctionsToExport`。
4. 更新 `psutils/tests/config.Tests.ps1`
   * 覆盖 `${VAR}` 展开。
   * 覆盖缺失 `${VAR}` 抛错。
   * 覆盖 `~` 展开。
   * 覆盖相对路径基于 `BasePath`。
   * 覆盖空路径抛错。
5. 更新 `ai/skills/Install-Skills.ps1`
   * 删除 `Resolve-SkillsEnvPlaceholder`。
   * 删除 `Resolve-SkillsPath`。
   * 改用 `Resolve-ConfigPath`。
6. 验证
   * `pnpm exec pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Path ./psutils/tests/config.Tests.ps1`
   * `pnpm exec pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Path ./tests/SkillsInstaller.Tests.ps1`
   * `pnpm qa`
   * `pnpm test:pwsh:all`

## Review Gate

确认本轮没有修改 GitHub CLI 安装器、rclone 或 skills 私有模块拆分逻辑；它们留到后续独立任务。
