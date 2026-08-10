# 技术设计

## 边界

- `install.ps1` 继续作为根 Stage 1 唯一实现，负责平台识别、Preset、步骤过滤、网络模式、交互模式和退出码。
- `package.json` 只提供无状态的一行命令别名，不读取系统类型、不复制参数校验、不调用平台叶子。
- 各平台 `00` 入口继续独占 Stage 0；pnpm 快捷入口不承担 bootstrap。

## 命令合同

| pnpm script | 转发目标 |
| --- | --- |
| `provision:list` | `pwsh -NoProfile -File ./install.ps1 -ListSteps` |
| `provision:core:preview` | `pwsh -NoProfile -File ./install.ps1 -Preset Core -WhatIf` |
| `provision:full:preview` | `pwsh -NoProfile -File ./install.ps1 -Preset Full -WhatIf` |
| `provision:core` | `pwsh -NoProfile -File ./install.ps1 -Preset Core` |
| `provision:full` | `pwsh -NoProfile -File ./install.ps1 -Preset Full` |

pnpm 11 会将脚本名后的参数直接传给底层命令，例如 `pnpm provision:core -NetworkMode China`；不得增加 `--`，否则字面量会传给 PowerShell。`provision` 与仓库已有 Ansible 系统配置语义一致，也不与 pnpm 内置命令冲突。快捷入口不显式固定默认 `Direct`，避免与用户追加的 `-NetworkMode` 重复绑定。
## Text 输出修复

`Write-InstallRunText` 中包含多个格式参数的 `Console.WriteLine` 调用必须把完整 `-f` 表达式包在括号内，再作为单个字符串参数传入。只修复调用边界，不改变结果 document、步骤状态或退出码。Pester 以结构化 fixture document 调用导出函数，验证标题、步骤、source restore 和最终状态均可输出。


## 兼容性

- 不改动现有 `pwsh:install` 与 `scripts:install`，两者仍执行无参数开发环境准备。
- 不新增平台名脚本；相同命令在 Windows、macOS 和 Linux/WSL 上由 `Resolve-InstallPlatform` 选择当前平台。
- package scripts 仅在 Node.js、pnpm 与 PowerShell 7 已可用时成立。
- Text 汇总修复保持既有输出文本和字段顺序，只消除 PowerShell 方法参数绑定歧义。

## 风险与回退

- 风险：用户把 pnpm 快捷入口误当新机 bootstrap。通过 `docs/INSTALL.md` 的 Stage 0/Stage 1 前置说明消除。
- 风险：修复触及 PowerShell 安装编排模块。通过新增窄测、preview smoke、`pnpm test:pwsh:all` 与 `pnpm qa` 验证。
- 风险：执行命令会真实修改系统。文档先展示 preview，再展示 apply。
- 回退：删除新增的五个 package scripts 和对应文档段落即可；安装编排器与平台叶子不受影响。
