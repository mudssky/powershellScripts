# pwsh shared helper extraction round 2

## Goal

继续从 `psutils` 之外的大型 PowerShell 脚本里抽取通用基础设施，降低重复实现和后续维护成本。

## Requirements

- 跳过前一轮建议中的第 1 项：不修改 `scripts/pwsh/download/Install-GitHubCli.ps1`。
- 迁移 rclone 运维脚本中的配置 helper，优先复用 `psutils/modules/config.psm1`。
- 抽取 Docker Compose 相关通用 helper，并至少迁移一个已有 start 脚本调用点。
- 抽取 JSON/manifest/原子写入 helper，不包含 Claude、Tailscale、rclone 等领域规则。
- 抽取文件同步/备份中稳定通用的基础 helper；领域耦合过强的 managed manifest 清理保留在调用脚本中。
- 保留现有脚本入口、参数、测试可见函数名和行为语义。

## Acceptance Criteria

- [ ] `Install-GitHubCli.ps1` 未被修改。
- [ ] `rclone-ops.ps1` 不再维护重复的 env placeholder / hashtable / case-insensitive lookup 实现。
- [ ] 至少一个 Docker Compose start 脚本复用共享 helper，原测试行为保持兼容。
- [ ] `psutils` 提供 JSON 原子读写或稳定键 helper，并有 Pester 覆盖。
- [ ] Claude config sync 复用通用 JSON/文件 helper，业务合并和安全校验仍留在脚本内。
- [ ] 目标脚本现有 Pester 测试通过，根目录 `pnpm qa` 与 `pnpm test:pwsh:all` 通过。

## Notes

- 用户明确指定“2 3 4 5 改一下，1 先不改了”，此处的 1 指上一轮建议顺序中的 GitHub CLI 下载器迁移。
