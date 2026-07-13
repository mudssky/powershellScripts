# WSL SSH 宿主与客体入口实施计划

- [ ] 读取 Windows install、Linux/WSL pipeline、OpenSSH、managed-host 和测试规范。
- [ ] 先为 guest plan/validate/render/key merge 编写纯逻辑测试，再实现 `linux/wsl/prepare-ssh-access.sh`。
- [ ] 为 host 参数、resource name、portproxy/firewall/task plan 与 JSON 脱敏编写 Pester 测试。
- [ ] 实现稳定 runtime refresh helper，再实现 host orchestrator plan/apply/verify/rollback。
- [ ] 在非 Windows 测试中使用 mocks/fixture，不真实调用 WSL、ScheduledTasks、netsh 或 firewall cmdlets。
- [ ] 运行相关窄测、`pnpm qa`、`pnpm test:pwsh:all`、Bash syntax 和 `git diff --check`。
- [ ] 更新 infra specs 与 Windows/Linux INSTALL 文档。
- [ ] 按 Conventional Commits 提交并 push GitHub，向 self-hosted-compose 返回完整 commit SHA。
