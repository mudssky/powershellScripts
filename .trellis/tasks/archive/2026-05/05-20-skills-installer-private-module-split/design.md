# design: skills installer private module split

## Scope

本任务只拆分 `ai/skills/Install-Skills.ps1` 内部的 skills 安装器领域逻辑。拆出的文件放在 `ai/skills/private/`，通过入口脚本 dot-source 加载，不进入 `psutils`，也不改变配置字段、安装语义或外部命令参数。

入口脚本继续作为唯一 CLI 入口，负责：

* 声明参数与脚本级帮助。
* 初始化 `Set-StrictMode`、`$ErrorActionPreference`、`$script:SkillsInstallerRoot`、`$script:SkillsRepoRoot`。
* 导入 `psutils/modules/process.psm1` 与 `psutils/modules/config.psm1`。
* 按顺序加载私有脚本。
* 保留 `Invoke-SkillsInstallMain` 与最终 `exit` 调用。

## File Layout

新增 `ai/skills/private/`：

* `bootstrap.ps1`
  * 字符串数组转换、默认路径、用户目录、agent skill 目录、已安装目录检查。
* `plan.ps1`
  * 配置读取、agent/scope/source 解析、命令计划、完整安装计划生成。
* `presentation.ps1`
  * 安装计划展示与脚本级确认。
* `execution.ps1`
  * tool check、pending plan 过滤、单步执行和计划执行。

## Load Order

`Install-Skills.ps1` 先导入共享 `psutils` 模块，再按以下顺序 dot-source 私有脚本：

1. `bootstrap.ps1`
2. `plan.ps1`
3. `presentation.ps1`
4. `execution.ps1`

这个顺序保证私有脚本可以直接复用共享配置/进程 helper，以及前置私有 helper。

## Compatibility

* 保留现有函数名，测试继续通过 dot-source `Install-Skills.ps1` 访问这些函数。
* 保留 `SKILLS_INSTALLER_SKIP_MAIN=1` 测试入口语义。
* 保留 `WhatIf`、`DryRun`、`Yes`、`Force` 行为。
* 保留日志文件创建与命令执行器注入方式。

## Tradeoffs

本轮不引入 `.psm1` 模块导出或构建型单文件 bundle。当前优先目标是降低入口脚本体积和提高领域边界可读性；如果后续需要发布单文件脚本，可再增加构建脚本把 `private/*.ps1` inline 到 bundle。

## Rollback

如拆分后出现加载或作用域问题，可把 `private/*.ps1` 的函数按原顺序合并回 `Install-Skills.ps1`，删除 dot-source 加载块即可恢复单文件结构。
