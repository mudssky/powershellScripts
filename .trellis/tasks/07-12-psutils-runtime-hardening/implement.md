# psutils 运行时加固执行计划

## Checklist

- [x] 等待核心契约和 API 边界任务完成。
- [x] 加载 `trellis-before-dev` 与 psutils 规范。
- [x] 建立候选矩阵并逐项复现或证明风险。
- [x] 先为入选 Fix 添加失败测试。
- [x] 加固 SSH passphrase 与 native command 参数边界。
- [x] 明确或替换历史命令动态执行路径。
- [x] 为可降级空 catch 添加 `Verbose` 诊断，为不可恢复错误建立明确失败语义。
- [x] 处理确认有影响的自动变量和跨平台问题。
- [x] 记录 Documented Exception，不追求告警清零。
- [x] 运行窄测试、QA 和完整 PowerShell 回归。

## Validation

```powershell
pnpm --filter psutils test:qa
pnpm --filter psutils test:full
pnpm qa
pnpm test:pwsh:all
```

不得在验证中连接真实 SSH 主机、修改系统代理、安装字体或写入真实用户配置。

验证结果：

- `pnpm --filter psutils test:qa`：451 通过，0 失败。
- `pnpm qa`：238 个 changed QA 测试通过，0 失败。
- `pnpm test:pwsh:all`：主机 817 通过、Linux 容器 814 通过，均 0 失败。
- Linux `psutils` 最终补充回归：453 通过，0 失败。
- `Wait-ForURL` Slow 标签定向回归：5 通过，0 失败。
- 验证过程未连接真实 SSH 主机，也未修改真实代理、字体或用户配置。

## Risky Files

- `psutils/modules/linux.psm1`
- `psutils/modules/functions.psm1`
- `psutils/modules/env.psm1`
- `psutils/modules/hardware.psm1`
- `psutils/modules/network.psm1`
- `psutils/modules/proxy.psm1`
