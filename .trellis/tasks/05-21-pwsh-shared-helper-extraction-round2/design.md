# design: pwsh shared helper extraction round 2

## Scope

本轮处理上一轮建议顺序的第 2-5 项：

1. rclone 配置 helper 迁移。
2. Docker Compose helper 抽取。
3. JSON/manifest/原子写入工具。
4. 文件同步/备份 helper。

`Install-GitHubCli.ps1` 明确不改。

## Config Helpers

`psutils/modules/config.psm1` 已提供 `ConvertTo-ConfigHashtable`、`Get-ConfigValue`、`Resolve-ConfigEnvPlaceholder` 与 `Resolve-ConfigSources`。`rclone-ops.ps1` 保留旧领域函数名作为兼容 wrapper，但内部委托共享 helper。

## Docker Compose Helpers

新增 `psutils/modules/docker.psm1`，只提供 Docker Compose 基础设施：

* `Test-DockerComposeAvailable`
* `Assert-DockerComposeReady`
* `Get-DockerComposeBaseArgs`
* `Invoke-DockerComposeCommand`

调用脚本可保留本地 `Invoke-DockerCompose` 等旧函数名作为 wrapper，避免破坏测试和用户脚本习惯。

## JSON Helpers

新增 `psutils/modules/json.psm1`，提供：

* `Read-JsonHashtableFile`
* `Write-JsonFileAtomic`
* `Get-StableJsonKey`

这些 helper 只负责 JSON 读写与稳定键，不处理 Claude settings 合并、安全校验或 HuJSON 兼容。

## File Helpers

在 `psutils/modules/filesystem.psm1` 中补充：

* `Copy-FileSystemItemSafe`
* `New-BackupSnapshot`

它们只处理文件系统复制/备份基础设施。Claude managed manifest 的 stale cleanup 仍保留在 `Sync-ClaudeConfig.ps1`。

## Compatibility

* 保留 rclone 与 Claude 同步脚本的对外函数名和命令行入口。
* 保留测试依赖的关键错误文本。
* Docker Compose 先迁移测试覆盖较好的调用点，避免一轮改完所有 start 脚本。

## Validation

* `psutils/tests/config.Tests.ps1`
* `psutils/tests/filesystem.Tests.ps1`
* `psutils/tests/json.Tests.ps1`
* `psutils/tests/docker.Tests.ps1`
* `tests/RcloneOps.Tests.ps1`
* `tests/Sync-ClaudeConfig.Tests.ps1`
* 迁移的 Docker Compose start 脚本对应测试
* `pnpm qa`
* `pnpm test:pwsh:all`
