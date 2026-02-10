## Why

当前 `profile/` 已完成一轮拆分，但仍保留了 PowerShell 5.1 兼容分支与若干历史路径，导致维护复杂度偏高、目录职责不够清晰、后续演进成本增加。既然后续明确不再兼容 5.1，就应当同步收敛行为边界与结构约束，统一到 `pwsh`（PowerShell 7+）语义。

## What Changes

- **BREAKING**: 移除 PowerShell 5.1 兼容逻辑与相关兜底分支（例如 `$IsWindows/$IsLinux/$IsMacOS` 的手动回填路径），明确最低运行环境为 PowerShell 7+。
- 收敛与清理历史入口/历史兼容说明，使统一入口行为与文档声明一致。
- 优化 `profile/` 内部目录职责，将“配置数据（如用户别名）”与“功能实现脚本”分层，减少根目录漂移文件。
- 调整脚本导入组织方式（dot-source/路径约定），让加载链路更可读、可扩展、可验证。
- 同步更新相关 OpenSpec 规格与任务拆解，为后续实施提供可执行清单。

## Capabilities

### New Capabilities
- _None_

### Modified Capabilities
- `unified-profile`: 更新运行时兼容边界（移除 5.1 兼容要求）、目录组织与加载约定的规范要求。

## Impact

- Affected specs: `openspec/specs/unified-profile/spec.md`（新增 delta spec）。
- Affected code areas: `profile/profile.ps1`、`profile/core/loaders.ps1`、`profile/features/*`、`profile/user_aliases.ps1`（或其迁移后的新路径）、相关安装/文档脚本。
- Affected docs: `docs/install/README.md` 与其它 profile 使用说明。
- Runtime impact: 仅支持 PowerShell 7+；不提供 5.x 兼容层与过渡策略。
