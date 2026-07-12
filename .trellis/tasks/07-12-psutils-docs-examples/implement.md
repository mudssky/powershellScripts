# psutils 文档与示例执行计划

## Checklist

- [ ] 等待 `07-12-psutils-core-contract` 完成并加载最终入口/API 契约。
- [ ] 对照 manifest、`Get-Command` 和 tests 重写 README 的版本、安装、能力与测试章节。
- [ ] 移除不存在的 ffmpeg 模块和错误的按需加载/完整帮助声明。
- [ ] 修复或归档错误路径、重复或版本过时的 cache demo。
- [ ] 修复 examples 的入口并停止推荐弃用帮助搜索路径。
- [ ] 增加无副作用的 example/demo 可发现性或 smoke 测试。
- [ ] 运行相关 Pester、QA 与完整 PowerShell 回归。

## Validation

```powershell
pnpm --filter psutils test:qa
pnpm qa
pnpm test:pwsh:all
```

纯文案提交可按仓库规则跳过 QA；一旦修改 `.ps1`、`.psm1` 或测试，则执行完整命令。

## Risky Files

- `psutils/README.md`
- `psutils/modules/help.psm1`
- `psutils/examples/**`
- `psutils/demo/**`
- `psutils/tests/**`
