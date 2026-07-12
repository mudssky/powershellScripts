# 实施计划

- [x] 新增 PS5.1 兼容模块，复用 `WindowsBootstrap.psm1` 的结果与退出码合同。
- [x] 实现 Tailscale IPv4 发现/校验、托管证书选择、listener/firewall 状态读取和计划生成。
- [x] 实现 configure、verify、rollback，所有写操作支持 WhatIf 零副作用。
- [x] 新增固定入口脚本与 Text/Json 单文档输出。
- [x] 新增 Pester 测试和 Windows 安装文档。
- [x] 运行窄测、`pnpm qa`、`pnpm test:pwsh:all`、`git diff --check`。
- [x] 更新 Windows install code-spec。
- [x] 提交并推送 GitHub，确认 Windows CI。
