---
date: 2026-03-14
topic: pwsh-test-command-alignment
---

# PowerShell 测试命令收敛与提交流程约定

## What We're Building

整理根目录 `package.json` 中与 PowerShell 测试相关的命令命名，让命令语义按“测试域 + 运行环境 + 强度”表达，避免 `test:linux`、`test:full` 这类维度混杂的名字继续扩散。目标是让开发者看到命令名就能判断：这是 PowerShell 测试、在哪个环境执行、以及执行的是快速集还是完整集。

在此基础上新增一个跨环境聚合入口 `test:pwsh:all`，用于在提交前一键覆盖本机 Windows 和 Linux 容器两套完整 PowerShell 测试。与此同时，在 `AGENTS.md` 中补充协作约定：若改动了 pwsh 相关内容，提交代码前执行 `pnpm test:pwsh:all`。现有 `qa` 入口继续保留为通用快速质量门，不承担完整跨环境 pwsh 回归的语义。

## Why This Approach

讨论过三条主要路径：新增一个更重的 `ci:check` 入口、继续沿用现有 `test:linux` 等命名并局部打补丁、以及把 PowerShell 测试统一收敛到 `test:pwsh:*` 命名下。最终选择第三条，因为它先表达“这是 PowerShell/Pester 测试”，再表达环境与强度，心智模型最稳定，也更容易继续扩展到聚合命令。

相比之下，`ci:check` 很容易与现有 `qa`/`qa:all` 语义重叠；`test:linux:qa` 一类名字又把平台、测试域和质量门语义混在一起，长期看会继续制造歧义。把 `qa` 留给聚合质量门，把 `test:pwsh:*` 留给 PowerShell 测试域，职责边界更清楚。

## Key Decisions

- 将本机 PowerShell 测试命名统一到 `test:pwsh:fast` 与 `test:pwsh:full`。
- 将 Linux 容器内 PowerShell 测试命名统一到 `test:pwsh:linux:fast` 与 `test:pwsh:linux:full`。
- 不保留旧脚本名兼容层，直接切换到新命名。
- 新增 `test:pwsh:all`，并发执行本机与 Linux 两套 `full` 级别 PowerShell 测试。
- `test:pwsh:all` 只承担 PowerShell 测试聚合，不与 `qa`/`qa:all` 混合。
- 在 `AGENTS.md` 中增加提交前约定：若改动了 pwsh 相关内容，提交代码前执行 `pnpm test:pwsh:all`。

## Resolved Questions

- 不新增 `ci:check`。
- 不使用 `test:linux:qa` 这类混合平台与质量门语义的命名。
- 不保留旧命名别名。
- `test:pwsh:all` 需要覆盖 Windows 本机与 Linux 容器两个环境。
- `test:pwsh:all` 中两个环境都执行 `full` 级别测试，而不是 `fast`。

## Open Questions

- 暂无。当前边界已经足够进入 planning 或 implementation。

## Next Steps

-> `/ce:plan` 用于整理 `package.json`、测试文档与 `AGENTS.md` 的具体改动步骤
