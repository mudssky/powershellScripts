## Context

`profile/` 在上一轮已完成入口与功能拆分，但仍存在两个结构性问题：

1. 运行时边界未收敛：当前规范和实现仍包含 Windows PowerShell 5.1 兼容路径，增加维护分支和测试心智负担。
2. 目录职责不够清晰：配置数据（例如 `user_aliases.ps1`）与入口/功能脚本并列放在 `profile/` 根目录，加载链路可读性与后续扩展性受限。

此外，`Full` 模式启动耗时明显高于 `Minimal/UltraMinimal`，后续优化需要在不破坏现有模式语义的前提下推进。

## Goals / Non-Goals

**Goals:**
- 明确并收敛 `profile` 的最低运行环境为 PowerShell 7+（`pwsh`），移除 5.1 兼容语义与相关分支。
- 规范 `profile/` 目录职责，将“配置数据”与“功能实现”分离，降低根目录耦合。
- 固化可维护的加载组织方式，为后续性能优化和功能扩展提供稳定骨架。
- 保持统一入口与模式系统（`Full/Minimal/UltraMinimal`）的核心行为不变。

**Non-Goals:**
- 本次不引入新的 profile 功能（仅做边界收敛与结构优化）。
- 本次不重写 `psutils` 模块对外接口。
- 本次不改变用户命令习惯（入口仍为 `profile/profile.ps1`）。

## Decisions

### 1) 运行时基线收敛到 PowerShell 7+

**Decision**: 将 `pwsh`（PowerShell 7+）定义为唯一受支持运行时；移除 5.1 兼容要求及实现分支。

**Rationale**:
- 减少跨版本分支判断和隐式回填逻辑，降低维护成本。
- 避免编码/解析行为在 5.1 与 7+ 的差异带来的隐性故障。

**Alternatives considered**:
- 保持双栈兼容（5.1 + 7+）：实现与测试复杂度过高，且团队已明确不再需要 5.1。

### 2) 别名配置归档到专用配置目录

**Decision**: 将 `user_aliases.ps1` 从 `profile/` 根目录迁移到配置目录（例如 `profile/config/aliases/user_aliases.ps1`），并由统一加载器引用新路径。

**Rationale**:
- 配置数据与功能脚本解耦，职责边界更清晰。
- 后续可并行引入更多配置文件（环境、工具、别名分组）而不污染根目录。

**Alternatives considered**:
- 维持根目录现状：短期改动最小，但长期继续扩大根目录“平铺”问题。
- 直接改为 `.psd1`：结构化程度更高，但需同步调整现有别名脚本表达方式，适合后续迭代。

### 3) 加载链路保持单入口、集中声明

**Decision**: 保留 `profile/profile.ps1` 作为唯一入口，所有内部脚本路径在核心加载层集中声明并按确定顺序加载。

**Rationale**:
- 统一观测点，便于定位启动失败与性能瓶颈。
- 降低“隐式 dot-source”带来的顺序依赖风险。

**Alternatives considered**:
- 分散在各 feature 内部互相加载：灵活但可读性差，跨模块依赖更难管理。

### 4) 性能优化采取“先结构后行为”的两阶段策略

**Decision**: 本 change 先完成运行时边界与结构治理；具体工具懒加载/并行化优化作为后续增量任务实施。

**Rationale**:
- 降低一次性改动风险，确保每轮变更可验证、可回滚。

## Risks / Trade-offs

- [Risk] 仍在使用 Windows PowerShell 5.1 的用户会直接受影响（BREAKING）  
  → Mitigation: 本项目不提供兼容与迁移策略，直接按 PowerShell 7+ 基线执行。

- [Risk] 别名配置迁移可能导致旧路径被第三方脚本直接引用而失效  
  → Mitigation: 统一在本次变更中完成路径切换，不保留旧路径兼容跳转。

- [Risk] 加载链路调整可能引入顺序回归  
  → Mitigation: 在任务中加入加载顺序与函数可用性回归验证。

## Migration Plan

1. 先更新规格（移除 5.1 兼容要求，新增目录职责要求），确保目标行为明确。
2. 实现阶段移除 `profile.ps1` 中 5.1 回填逻辑，不增加任何 5.x 兼容分支或提示分支。
3. 迁移 `user_aliases.ps1` 到新配置目录并更新加载路径。
4. 更新安装与使用文档，统一标注 `pwsh` 作为唯一支持运行时。
5. 执行加载链路与模式行为回归验证。

**Rollback strategy**:
- 若迁移后出现严重回归，可回退到变更前版本并恢复旧路径加载；由于本次不涉及数据持久层变更，回滚成本较低。

## Open Questions

- 无（本次直接一次性切换，不保留临时兼容层）。
- `user_aliases` 后续是否演进为结构化数据文件（如 `.psd1`/`.json`）以便校验与工具化？
