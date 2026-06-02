# design: skills 安装器第一轮瘦身

## Scope

第一轮只抽取外部命令执行与轻量命令日志基础设施。`psutils` 不接收 skills 安装器的领域概念，以下逻辑继续留在 `ai/skills/Install-Skills.ps1`：

* Claude/Codex skill 目录解析与已安装检测
* ctx7 默认 check 配置
* 安装计划、agent 名称映射、scope 与 projectPath 处理
* 安装计划展示、确认文案与 `ShouldProcess` 目标描述

## Public API

新增 `psutils/modules/process.psm1`，导出以下函数：

* `Format-NativeCommandLine`
  * 入参：`Command`、`ArgumentList`
  * 返回：可读的一行命令文本，用于预览、日志和 `ShouldProcess` action。
* `Resolve-NativeExecutablePath`
  * 入参：`Command`
  * 返回：可传给 `System.Diagnostics.ProcessStartInfo.FileName` 的命令路径或原始命令名。
  * Windows/npm wrapper 场景优先选择 `Application`，避免误选 `.ps1` wrapper。
* `New-CommandLogFile`
  * 入参：`LogDirectory`、可选 `Prefix`、可选 `Header`
  * 返回：日志文件绝对路径。
* `Write-CommandLogLine`
  * 入参：`LogPath`、`Message`
  * 返回：无。`LogPath` 为空时 no-op。
* `Invoke-NativeCommand`
  * 入参：`Command`、`ArgumentList`、`WorkingDirectory`、`LogPath`、`AllowFailure`、`SuppressOutput`
  * 返回：`PSCustomObject`，包含 `ExitCode`、`StdOut`、`StdErr`。

## Data Flow

`Install-Skills.ps1` 在启动时导入 `psutils/modules/process.psm1`。安装器生成计划后，所有命令预览继续由安装器决定调用位置，但实际格式化、日志文件创建、日志写入和外部命令执行都委托给 `psutils`。

测试仍可通过 `CommandRunner` 注入替身；默认 runner 调用 `Invoke-NativeCommand`。tool check 的安静检查从脚本级 `$script:SkillsInstallerSuppressCommandOutput` 改为 runner 参数传递，避免公共模块依赖调用方全局状态。

## Compatibility

保持当前行为：

* stdout/stderr 默认继续转发到控制台，同时写入日志。
* check 场景可静默控制台输出，但仍保留日志。
* 非零退出码在 `AllowFailure` 为 false 时抛出 `外部命令执行失败(<code>): <command line>`。
* 日志行格式仍为 `[yyyy-MM-dd HH:mm:ss] MESSAGE`。
* skills 默认日志文件仍位于 `ai/skills/logs`，文件名仍以 `skills-install-` 开头。

## Tradeoffs

第一轮不抽 config helper 和 placeholder 解析，避免 `psutils` API 一次扩大过多。`Invoke-NativeCommand` 不处理 stdin、环境变量覆盖、后台进程或实时流式输出，这些属于第二轮或具体调用方扩展点。

## Rollback

如公共模块行为引发兼容问题，可恢复 `Install-Skills.ps1` 内部 helper 并移除 `process.psm1` 导出；由于 API 新增且调用面窄，回滚不会影响既有 `psutils` 模块。
