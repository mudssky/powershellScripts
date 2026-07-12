# psutils 运行时加固执行计划

## Checklist

- [ ] 等待核心契约和 API 边界任务完成。
- [ ] 加载 `trellis-before-dev` 与 psutils 规范。
- [ ] 建立候选矩阵并逐项复现或证明风险。
- [ ] 先为入选 Fix 添加失败测试。
- [ ] 加固 SSH passphrase 与 native command 参数边界。
- [ ] 明确或替换历史命令动态执行路径。
- [ ] 为可降级空 catch 添加 `Verbose` 诊断，为不可恢复错误建立明确失败语义。
- [ ] 处理确认有影响的自动变量和跨平台问题。
- [ ] 记录 Documented Exception，不追求告警清零。
- [ ] 运行窄测试、QA 和完整 PowerShell 回归。

## Validation

```powershell
pnpm --filter psutils test:qa
pnpm --filter psutils test:full
pnpm qa
pnpm test:pwsh:all
```

不得在验证中连接真实 SSH 主机、修改系统代理、安装字体或写入真实用户配置。

## Risky Files

- `psutils/modules/linux.psm1`
- `psutils/modules/functions.psm1`
- `psutils/modules/env.psm1`
- `psutils/modules/hardware.psm1`
- `psutils/modules/network.psm1`
- `psutils/modules/proxy.psm1`
