# implement: pwsh shared helper extraction round 2

## Checklist

1. 启动任务
   * 完成 `prd.md`、`design.md`、`implement.md`。
   * 执行 `task.py start`。
2. GitHub CLI 下载器 helper 迁移
   * 配置表、路径、平台映射 wrapper 委托 `psutils`。
   * 归档解压、候选文件查找、可执行文件安装、PATH 检查与提示委托共享 helper。
   * 保留脚本入口与原函数名。
3. rclone config helper 迁移
   * `ConvertTo-RcloneOpsHashtable` 委托 `ConvertTo-ConfigHashtable`。
   * `Get-RcloneOpsConfigValue` 委托 `Get-ConfigValue`。
   * `Resolve-RcloneOpsEnvPlaceholder` 委托 `Resolve-ConfigEnvPlaceholder`，非字符串保持原样。
4. Docker Compose helper
   * 新增 `psutils/modules/docker.psm1` 和测试。
   * 选择一个已有 start 脚本迁移到共享 helper。
5. JSON helper
   * 新增 `psutils/modules/json.psm1` 和测试。
   * 更新 `psutils/psutils.psd1`。
6. File helper
   * 更新 `psutils/modules/filesystem.psm1` 和测试。
   * `Sync-ClaudeConfig.ps1` 复用 JSON/文件 helper。
7. 验证
   * targeted Pester。
   * `pnpm qa`。
   * `pnpm test:pwsh:all`。
8. 提交
   * Conventional Commits，中文 subject。

## Review Gate

* `Install-GitHubCli.ps1` 只保留领域逻辑与兼容 wrapper，不再维护通用 helper 实现。
* 新增 `psutils` helper 不包含 rclone/Claude/具体服务领域语义。
* Docker Compose 只迁移有测试或行为足够简单的调用点。
