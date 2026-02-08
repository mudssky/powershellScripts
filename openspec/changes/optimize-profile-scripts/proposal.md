## Why

当前 `profile.ps1` 相关脚本在功能上稳定，但存在一些“脆弱点”和维护性成本：
- `Import-Module` 失败时错误定位不够明确，容易让人以为是别的逻辑出错
- `Test-EXEProgram` / `Test-ExeProgram` 命名不一致，可能导致工具探测误判
- 别名函数通过字符串拼接生成脚本块，遇到复杂参数/引号时易出错
- 个别小问题（如 `PSModulePath` 长期增长、`Get-Help` 性能）会随使用时间放大

这些问题不是“功能缺失”，但会影响可维护性与稳定性，适合做一次集中优化。

## What Changes

- 为关键入口增加**最小化错误上下文**：
  - `loadModule.ps1` 的 `Import-Module` 增加 `try/catch`，保留失败但输出清晰来源
  - `profile.ps1` 中 dot-source 脚本增加轻量错误提示（不做路径检查）
- 统一工具探测函数命名（`Test-EXEProgram`），避免误判
- 别名生成改为结构化调用：将 `command` 拆分为 `command` + `args`，通过 `& $cmd @args @($args)` 执行，减少参数解析问题
- 低风险维护性提升（可选）：
  - `PSModulePath` 去重，避免长期重复
  - `Get-Help` 结果缓存，降低 profile 加载耗时
  - `Add-CondaEnv` 支持更多路径或可配置路径

## Capabilities

### New Capabilities
- 无

### Modified Capabilities
- 无（现有需求不变，仅改进实现与健壮性）

## Impact

- **修改文件**: `profile/profile.ps1`、`profile/loadModule.ps1`、`profile/wrapper.ps1`、`profile/user_aliases.ps1`
- **行为影响**: 功能保持不变，但错误提示更明确、别名执行更稳健、长期维护成本降低
- **依赖**: 无新增依赖
