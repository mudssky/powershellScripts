# PowerShell Profile Package Guidelines

> 适用于 `profile/**` 的统一入口、模式判定、平台策略、核心模块加载、OnIdle 生命周期和性能诊断。

## Scope

- 包路径：`profile`
- 统一入口：`profile/profile.ps1`
- 兼容入口：`profile/profile_unix.ps1`
- 核心实现：`profile/core/*.ps1`

## Pre-Development Checklist

- 修改加载顺序、平台判断、模式语义或 OnIdle 前，先阅读 [Profile Runtime Contract](./profile-runtime.md)。
- 保留统一入口，不重新复制 Windows 与 Unix 执行链。
- 性能结论必须来自真实 `profile.ps1`，不得手工重放另一套初始化逻辑。
- 修改 PowerShell 逻辑后运行 Profile 窄测、`pnpm qa` 和项目要求的 `pnpm test:pwsh:all`。

## Quality Check

- Windows/macOS/Linux 平台上下文矩阵通过。
- Full/Minimal/UltraMinimal 的模块、工具、别名和公共函数契约通过。
- 同一进程重复加载后 Profile 自己管理的 OnIdle 订阅最多一个。
- 诊断报告包含内部耗时、完整进程耗时、样本统计和平台限制说明。
- README 的模块数量、模式语义和诊断命令与代码一致。

## Guidelines

| Guide | Description | Status |
|---|---|---|
| [Profile Runtime Contract](./profile-runtime.md) | 统一入口、平台上下文、模式加载、降级、OnIdle 与真实入口性能诊断 | Active |
