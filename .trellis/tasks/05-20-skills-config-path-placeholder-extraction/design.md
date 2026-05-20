# design: config path placeholder extraction

## Scope

本任务抽取通用“配置路径解析”能力到 `psutils/modules/config.psm1`。公共 API 只处理字符串路径与环境变量 placeholder，不包含 skills、GitHub release、agent、ctx7 或安装计划语义。

首个接入调用方是 `ai/skills/Install-Skills.ps1`。GitHub CLI 安装器和 rclone 等脚本只作为设计参考，后续单独迁移。

## Public API

新增 `Resolve-ConfigEnvPlaceholder`：

* 入参：`Value`、`Context`
* 支持 `${VAR}`，缺失时抛出 `环境变量未设置: <name>（<context>）`
* 支持平台原生 `%VAR%`，通过 `[Environment]::ExpandEnvironmentVariables`
* 返回展开后的字符串

新增 `Resolve-ConfigPath`：

* 入参：`Path`、`BasePath`、`Context`
* 空白路径抛出 `路径配置不能为空: <context>`
* 先调用 `Resolve-ConfigEnvPlaceholder`
* 支持 `~`、`~/...`、`~\...`
* 相对路径基于 `BasePath`
* 返回 `[System.IO.Path]::GetFullPath(...)`

## Compatibility

保持 `Install-Skills.ps1` 当前行为：

* `${VAR}` 缺失时抛错。
* `%VAR%` 保持 .NET 环境变量展开语义。
* `~` 缺失用户主目录时抛错。
* 所有相对路径仍基于配置文件目录或调用方传入的 base path。

## Tradeoffs

不在本轮支持默认值、可选路径、存在性检查或目录创建。这些属于调用方业务规则，公共 helper 只返回解析后的路径字符串。

## Rollback

如迁移后发现差异，可恢复 `Install-Skills.ps1` 私有 `Resolve-SkillsEnvPlaceholder` / `Resolve-SkillsPath`，公共 API 作为向后兼容新增保留。
