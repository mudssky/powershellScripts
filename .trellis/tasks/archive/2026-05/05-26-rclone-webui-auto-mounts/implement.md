# rclone WebUI 自动挂载多个 OSS 实施计划

## Checklist

- [x] 阅读并遵守 `pwsh-scripts` / `psutils` 配置解析规范。
- [x] 在 `rclone-ops.ps1` 新增 mounts 配置读取与校验函数。
- [x] 新增 mount 参数构造函数，支持字符串值、布尔 flag、路径解析与环境变量占位符。
- [x] 新增配置化 `mount-all`、`unmount-all`、`up`、`down` 命令。
- [x] 修正现有 `mount --background` 的 PID 文件命名，避免多挂载覆盖。
- [x] 更新 `Show-RcloneOpsHelp`。
- [x] 更新 `rclone.config.example.json`，加入 `mounts` 示例。
- [x] 按用户本地 4 个 remote 更新 `rclone.config.local.json` 的 `mounts` 配置，避免写入真实密钥。
- [x] 更新 `README.md`，说明一键启动/停止、mount schema、配置参数含义与推荐参数。
- [x] 扩展 `tests/RcloneOps.Tests.ps1`，覆盖 mounts 配置解析与参数构造。

## Validation

- [x] `pnpm format:pwsh`
- [x] `pnpm test:pwsh:qa`
- [x] 根目录 `pnpm qa`
- [ ] 如 QA 环境因 Docker 或外部依赖受限，记录失败原因并至少完成 PowerShell 相关验证。

## Risky Files

- `config/service/oss/rclone/rclone-ops.ps1`：命令调度与进程管理。
- `config/service/oss/rclone/rclone.config.local.json`：本地忽略配置，可能包含真实 remote 名称；编辑时不得泄露密钥。
- `tests/RcloneOps.Tests.ps1`：dot-source 脚本后需要清理新增函数，避免测试间污染。

## Rollback Points

- 若配置化 mount 逻辑复杂度过高，保留 `mount-all/unmount-all`，推迟 `up/down`。
- 若本地挂载验证受系统 FUSE 依赖影响，只验证命令构造和 Pester 逻辑，不强行实际 mount。
