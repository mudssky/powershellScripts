# implement: pwsh shared helper extraction round 2

## Checklist

1. 启动任务
   * 完成 `prd.md`、`design.md`、`implement.md`。
   * 执行 `task.py start`。
2. rclone config helper 迁移
   * `ConvertTo-RcloneOpsHashtable` 委托 `ConvertTo-ConfigHashtable`。
   * `Get-RcloneOpsConfigValue` 委托 `Get-ConfigValue`。
   * `Resolve-RcloneOpsEnvPlaceholder` 委托 `Resolve-ConfigEnvPlaceholder`，非字符串保持原样。
3. Docker Compose helper
   * 新增 `psutils/modules/docker.psm1` 和测试。
   * 选择一个已有 start 脚本迁移到共享 helper。
4. JSON helper
   * 新增 `psutils/modules/json.psm1` 和测试。
   * 更新 `psutils/psutils.psd1`。
5. File helper
   * 更新 `psutils/modules/filesystem.psm1` 和测试。
   * `Sync-ClaudeConfig.ps1` 复用 JSON/文件 helper。
6. 验证
   * targeted Pester。
   * `pnpm qa`。
   * `pnpm test:pwsh:all`。
7. 提交
   * Conventional Commits，中文 subject。

## Review Gate

* `Install-GitHubCli.ps1` 没有出现在本轮 diff。
* 新增 `psutils` helper 不包含 rclone/Claude/具体服务领域语义。
* Docker Compose 只迁移有测试或行为足够简单的调用点。
