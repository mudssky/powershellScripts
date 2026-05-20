# implement: config helper extraction

## Checklist

1. 更新 `psutils/src/config/convert.ps1`
   * 补强 `ConvertTo-ConfigHashtable` 对 `System.Collections.IDictionary` 的处理。
   * 新增 `Get-ConfigValue`。
   * 为新增/更新公共函数保留中文 comment-based help。
2. 更新 `psutils/modules/config.psm1`
   * 导出 `Get-ConfigValue`。
3. 更新 `psutils/psutils.psd1`
   * 在 `FunctionsToExport` 中加入 `Get-ConfigValue`。
4. 更新 `psutils/tests/config.Tests.ps1`
   * 添加/补充 helper 用例。
5. 更新 `ai/skills/Install-Skills.ps1`
   * 删除 `ConvertTo-SkillsHashtable` 和 `Get-SkillsConfigValue`。
   * 确保在使用 helper 前导入 config 模块。
   * 将调用点替换为公共函数。
6. 更新 `tests/SkillsInstaller.Tests.ps1`
   * 若导入时机改变导致测试需要调整，只做最小更新。
7. 验证
   * `pnpm exec pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Path ./psutils/tests/config.Tests.ps1`
   * `pnpm exec pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Path ./tests/SkillsInstaller.Tests.ps1`
   * `pnpm qa`
   * `pnpm test:pwsh:all`

## Review Gate

确认本轮 diff 没有包含 path/env placeholder 实现，也没有把 skills 安装计划逻辑移入 `psutils`。
