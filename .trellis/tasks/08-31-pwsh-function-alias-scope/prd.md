# 修复 PowerShell 函数别名作用域

## Goal

让 `profile/env.ps1` 中声明的本机命令包装在 Profile 加载完成后可从交互式 `pwsh` 调用，同时选择与仓库现有 Profile 分层一致、不会泄露本机敏感配置的实现方式。

## Background

- `profile/features/environment.ps1:632-642` 在 `Initialize-Environment` 函数内部 dot-source `profile/env.ps1`。
- PowerShell 的 dot-source 只把定义导入“当前作用域”；此处当前作用域是 `Initialize-Environment` 的函数作用域，因此普通 `function name {}` 会在函数返回后消失。
- 实测同一路径中函数在加载函数内部可见、返回后不可见；改为 `function global:name {}` 后，返回交互式作用域仍可调用。
- `profile/env.ps1` 被 `.gitignore:5` 忽略，仓库说明将其定位为本机环境变量和敏感配置文件，不应把其中内容写入版本库、日志或测试夹具。
- 仓库已有两类共享实现：`profile/config/aliases/user_aliases.ps1:3-64` 配置简单别名及带固定参数的函数别名；`profile/wrapper.ps1` 保存较复杂的共享包装函数并由 OnIdle 加载。

## Requirements

- R1：说明普通函数声明失效的准确作用域原因，并区分函数、别名和命令包装三种概念。
- R2：列出可行方案及适用边界，覆盖显式 Global 函数、Function Provider、调整 dot-source 边界、脚本模块，以及仓库现有别名配置/包装函数机制。
- R3：将 `profile/env.ps1` 中现有本机命令包装改为显式 Global 函数，保留固定参数与 `@args` 透传行为。
- R4：保留现有环境变量加载行为，不输出、不提交本机敏感值，不改变仓库级 Profile 加载合同。

## Key Decisions

- D1：采用 `function global:<name> { ... }` 修复当前机器的私有函数包装。
- D2：不调整 `Initialize-Environment` 的 dot-source 边界；避免让 `env.ps1` 的变量和其他副作用进入更宽作用域。
- D3：不把包含本机私有地址或参数的包装迁入版本化的 `user_aliases.ps1` 或 `wrapper.ps1`。
- D4：任务按轻量本机配置修复处理，仅维护 `prd.md`；实施前为 `profile/env.ps1` 创建同目录可读时间戳 `.bak` 备份。
- D5：2026-08-31 独立检查曾在工具记录中意外展开本机敏感配置上下文；该记录无法通过仓库修改撤销，用户已明确选择接受残余风险并继续收尾，不执行凭据轮换。

## Acceptance Criteria

- AC1：能用作用域链解释为何 `profile/env.ps1` 中普通函数仅在 `Initialize-Environment` 执行期间存在。
- AC2：每种备选方案明确维护位置、可见范围、固定参数/参数透传能力及主要取舍。
- AC3：独立 `pwsh -NoProfile` 进程加载真实 Profile 后，四个目标包装命令均可由 `Get-Command -CommandType Function` 找到。
- AC4：通过进程内 `npx` 测试替身调用目标包装，确认固定参数与调用方参数顺序不变，且不产生网络请求。
- AC5：验证过程不打印或复制 `profile/env.ps1` 的敏感值；该文件及其时间戳备份保持 Git 忽略。

## Accepted Risk

- AC5 的当前状态已满足：后续验证未再展开敏感内容，`profile/env.ps1` 与时间戳备份均保持 Git 忽略。
- AC5 的历史“全程无回显”部分存在已知例外；用户于 2026-08-31 明确接受该风险。最终验收必须保留此说明，不得将其表述为无例外通过。

## Out of Scope

- 修改 `profile/features/environment.ps1`、Profile 作用域合同或加载顺序。
- 重构无关的 Profile 启动、工具初始化、代理或 OnIdle 流程。
- 把本机私有 URL、令牌或账号配置迁入版本控制。
- 为本机私有配置增加仓库级 Pester 测试或执行与该配置无关的全仓门禁。
