# 实施计划

## 修改步骤

1. 在根 `package.json` 增加 `install:list`、Core/Full preview、Core/Full apply 五个快捷入口；保留现有安装脚本不变。
2. 修复 `Write-InstallRunText` 的多参数格式表达式方法绑定，并在 `tests/InstallOrchestrator.Tests.ps1` 增加 Text 输出回归测试。
3. 更新 `docs/INSTALL.md`：说明 pnpm 入口的前置条件、统一平台自动识别行为、`pnpm run` 用法和脚本名后直接追加参数的规则。
4. 检查文档未把 package scripts 描述为 Stage 0，也未引入平台专属重复命令。
## 验证

1. 安装编排 Text 输出窄测。
2. `pnpm provision:list`
3. `pnpm provision:core:preview`
4. `pnpm provision:full:preview`
5. `pnpm provision:core:preview -NetworkMode Direct`
6. `pnpm qa`
7. `pnpm test:pwsh:all`

preview 命令是本次真实入口 smoke；不执行 `pnpm provision:core` 或 `pnpm provision:full`，避免为验证而修改当前工作站的软件和用户配置。

## 评审门槛
- 五个脚本只转发根 `install.ps1`，不包含平台判断。
- 旧 `pwsh:install` 与 `scripts:install` 字符串保持不变。
- Text 汇总修复不改变 document、状态或退出码，只修正格式表达式作为单个方法参数传入。
- 文档先写 Stage 0 边界，再给 Stage 1 `pnpm run` 入口。
- smoke 输出来自当前平台步骤，preview 无真实安装副作用。

## 回滚点

- `InstallOrchestrator.psm1` 修复为四个独立表达式，可逐行回退；对应 Pester 用例同步删除。
- `package.json` 新增脚本为独立行，可整体删除。
- `docs/INSTALL.md` 新增说明为独立段落，可同步删除。
