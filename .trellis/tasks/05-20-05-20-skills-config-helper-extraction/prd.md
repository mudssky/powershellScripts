# skills config helper extraction

## Goal

把多个 PowerShell 脚本重复实现的“配置对象转 hashtable”和“大小写不敏感读取配置值”收敛到 `psutils/modules/config.psm1`，先供 `ai/skills/Install-Skills.ps1` 使用。

## Requirements

* `psutils` 暴露稳定公共 helper，用于浅层配置对象转换与大小写不敏感键读取。
* helper 必须保持通用配置语义，不包含 skills、ctx7、agent、GitHub release 等领域概念。
* `ConvertTo-ConfigHashtable` 需要兼容 `hashtable`、`System.Collections.IDictionary`、`PSCustomObject`、`$null`。
* 新增读取函数应支持默认值，并在 key 命中时保留原始 value 类型。
* `Install-Skills.ps1` 应移除本地 `ConvertTo-SkillsHashtable` / `Get-SkillsConfigValue`，改用 `psutils` 公共 helper。
* 本轮不抽 `Resolve-SkillsPath` / `Resolve-SkillsEnvPlaceholder`；路径/env placeholder 留给 `skills-config-path-placeholder-extraction` 子任务。
* 本轮不拆 `Install-Skills.ps1` 私有业务模块；模块拆分留给 `skills-installer-private-module-split` 子任务。

## Acceptance Criteria

* [ ] `psutils/modules/config.psm1` 导出通用 config helper，函数有中文 comment-based help、参数说明和返回值说明。
* [ ] `psutils/tests/config.Tests.ps1` 覆盖 dictionary 转换、大小写不敏感读取、默认值、原始类型保留。
* [ ] `Install-Skills.ps1` 改用公共 helper 后行为不变。
* [ ] 不把 skills 安装器领域语义加入 `psutils`。
* [ ] 定向 config 测试、skills 安装器测试、`pnpm qa`、`pnpm test:pwsh:all` 通过。

## Out of Scope

* 配置路径解析、`~` 展开、`${VAR}` / `%VAR%` placeholder 展开。
* GitHub CLI 安装器、rclone、start-container 的批量替换。
* `Install-Skills.ps1` 业务模块拆分。
