# psutils API 与模块边界执行计划

## Checklist

- [x] 等待核心契约任务完成，加载 `trellis-before-dev` 与相关规范。
- [x] 生成当前导出、仓库调用、README/Profile 使用和帮助状态的 `api-inventory.md`。
- [x] 用户审阅 Stable User、Compatibility 与待私有化命令清单。
- [x] 先添加显式导出和全局状态测试。
- [x] 替换 `wrapper.psm1`、`string.psm1` wildcard 导出。
- [x] 将默认别名描述前缀移出 global scope。
- [x] 处理 help 诊断命令、内部 parser 和 deprecated 路径。
- [x] 为最终保留的公共函数补齐参数和 `.OUTPUTS` 帮助。
- [x] 按收益决定是否拆分 `functions.psm1`、`help.psm1`、`test.psm1`。
- [x] 迁移仓库消费者并加入兼容 wrapper/alias。
- [x] 复测聚合导入和 Profile 性能。
- [x] 运行 QA 与完整 PowerShell 回归。

## Validation

```powershell
pnpm --filter psutils test:qa
pnpm qa
pnpm test:pwsh:all
pwsh -NoProfile -File ./profile/Debug-ProfilePerformance.ps1
```

性能脚本的最终参数以届时 README/帮助为准，至少交替采样 5 次并报告中位数。

验证结果：

- `pnpm --filter psutils test:qa`：432 通过，0 失败。
- `pnpm qa`：通过。
- `pnpm test:pwsh:all`：主机 800 通过、Linux 容器 797 通过，均 0 失败。
- 修改后导入中位数：Aggregate `329.700ms`、ProfileCore `152.174ms`、Direct `138.036ms`。
- 修改后 Profile 中位数：内部 `381ms`、完整进程 `651.944ms`、`initialize-environment` `183ms`。
- 相对修改前最大稳定变化为 `initialize-environment` 约 `+7.0%`，未超过 `10%` 回退阈值。

## Risky Files

- `psutils/psutils.psd1`
- `psutils/modules/wrapper.psm1`
- `psutils/modules/string.psm1`
- `psutils/modules/functions.psm1`
- `psutils/modules/help.psm1`
- `psutils/modules/test.psm1`
- `profile/**`
