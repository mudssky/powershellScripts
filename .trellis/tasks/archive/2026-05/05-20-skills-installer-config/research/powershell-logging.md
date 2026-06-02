# PowerShell 日志调研

## 结论摘要

skills 安装器适合实现一层轻量日志封装，而不是引入完整日志框架。内部状态消息使用 PowerShell streams；外部 `npx skills add` 的 stdout/stderr 通过 helper 同步输出到控制台和日志文件，并保留退出码。

## 资料来源

* Context7 `/microsoftdocs/powershell-docs`
* 本仓库现有 PowerShell 脚本：
  * `scripts/pwsh/devops/postgresql/core/logging.ps1`
  * `ai/downloadModels.ps1`

## PowerShell 官方能力

* `Start-Transcript` 记录整个 PowerShell session 到文本文件；适合交互排障或全局会话记录，但不适合作为单个安装命令的结构化日志主路径。
* `Tee-Object` 可以把 pipeline 输出同时写到控制台和文件；适合简单输出复制。
* PowerShell redirection 支持 success、error、warning、verbose、debug、information streams；外部命令 stdout/stderr 对应 success/error stream，但需要小心保留退出码。

## 本仓库现状

* `Postgres-Toolkit` 使用小型 `Write-PostgresToolkitMessage` 统一输出前缀。
* `ai/downloadModels.ps1` 使用 `Write-Host` / `Write-Warning` / `Write-Verbose` 的简单封装。
* 没有可直接复用的通用日志模块。

## 推荐实现

* 新增脚本内 helper，例如 `Invoke-SkillNativeCommand`：
  * 入参：命令、参数数组、日志文件路径、可选工作目录。
  * 行为：执行 `npx skills ...`，把 stdout/stderr 同步输出到控制台并追加到日志。
  * 返回：exit code、stdout/stderr 摘要、日志路径。
* 新增脚本内 helper，例如 `Write-SkillInstallerLog`：
  * 内部消息写入控制台对应 stream，并追加到日志文件。
  * 日志行包含时间戳、level、message。
* 默认日志目录：`ai/skills/logs/`。
* 日志文件名：`install-skills.<yyyyMMdd-HHmmss>.log`。
* 日志目录应通过 `.gitignore` 忽略真实日志文件，可用 `.gitkeep` 保留目录。

## 不推荐作为 MVP 主路径

* 仅依赖 `Start-Transcript`：简单但粒度太粗，测试和失败摘要都不够清晰。
* 只用 `Tee-Object` 管道：容易混淆 stdout/stderr，且退出码处理容易被管道行为掩盖。
* 做成通用 psutils 日志模块：未来可以抽象，但首版会扩大范围。
