# psutils 文档与示例执行计划

## Checklist

- [x] 等待 `07-12-psutils-core-contract` 完成并加载最终入口/API 契约。
- [x] 对照 manifest、`Get-Command` 和 tests 重写 README 的版本、安装、能力与测试章节。
- [x] 移除不存在的 ffmpeg 模块和错误的按需加载/完整帮助声明。
- [x] 修复或归档错误路径、重复或版本过时的 cache demo。
- [x] 修复 examples 的入口并停止推荐弃用帮助搜索路径。
- [x] 增加无副作用的 example/demo 可发现性或 smoke 测试。
- [x] 运行相关 Pester、QA 与完整 PowerShell 回归。

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

## Validation Results

- `documentation.Tests.ps1`：16 通过，0 失败。
- `pnpm --filter psutils test:qa`：418 通过，3 跳过，22 平台未运行。
- `pnpm qa`：138 通过，0 失败，6 未运行。
- `pnpm test:pwsh:all`：主机 786 通过、Linux Docker 783 通过，均 0 失败。
- `project-archive check`：79 条归档记录一致。
