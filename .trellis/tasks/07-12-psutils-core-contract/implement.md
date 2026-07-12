# psutils 核心契约执行计划

## Checklist

- [x] 加载 `trellis-before-dev` 与 psutils/pwsh 相关规范。
- [x] 先写聚合 manifest、shim 和关键参数契约的失败测试。
- [x] 更新 manifest 的 PowerShell 版本与 edition 声明。
- [x] 实现 `index.psm1` 弃用 shim，并迁移 `ai/downloadModels.ps1` 与树示例。
- [x] 对齐 config 公共 reader 导出及规范测试。
- [x] 删除不存在的 `Test-ModuleFunction` manifest 项。
- [x] 合并 `New-Shortcut` 公共契约，以参数 alias 保留旧调用方式。
- [x] 复核直接子模块依赖由现有 config/install/test/hardware 测试覆盖。
- [x] 运行窄测试、包级测试、QA 和完整 PowerShell 回归。
- [x] 用 `ai/downloadModels.ps1 -ListOnly` 做只读 smoke test。

## Validation

```powershell
pnpm --filter psutils test:qa
pnpm --filter psutils test:full
pnpm qa
pnpm test:pwsh:all
pwsh -NoProfile -File ./ai/downloadModels.ps1 -ListOnly
```

## Risky Files

- `psutils/psutils.psd1`
- `psutils/index.psm1`
- `psutils/modules/config.psm1`
- `psutils/modules/functions.psm1`
- `psutils/modules/win.psm1`
- `ai/downloadModels.ps1`

提交前确认没有吸收工作区中其他归档任务的改动。

## Validation Results

- `moduleContract.Tests.ps1`：6 通过。
- `pnpm --filter psutils test:qa`：402 通过，3 跳过，22 平台未运行。
- `pnpm --filter psutils test:full`：402 通过，3 跳过，22 平台未运行。
- `pnpm qa`：186 通过，1 跳过，6 平台未运行。
- `pnpm test:pwsh:all`：主机 768 通过、Linux Docker 765 通过，均 0 失败。
- `ai/downloadModels.ps1 -ListOnly`：成功生成下载/删除计划，未执行模型变更。
