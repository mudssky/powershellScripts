---
module: System
date: 2026-03-14
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "root PowerShell 测试命令同时混用了 test/full/linux/qa 语义，开发者无法从命令名直接判断用途"
  - "仓库没有一条标准命令在提交前同时覆盖 host full 与 Linux full 的 PowerShell 测试"
  - "`pnpm qa` 很容易被误解为完整 pwsh 回归，但它实际只是快速质量门"
  - "AGENTS、README、CLAUDE 与本地跨平台测试文档对 pwsh 相关改动的提交前验证没有统一说法"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [powershell, pester, workflow, pre-commit, cross-platform, qa, developer-experience]
---

# Troubleshooting: 收敛 pwsh 测试命令并补齐提交前跨环境验证流程

## Problem

root PowerShell / Pester 测试入口长期混用了“测试域、运行环境、质量门”三种语义。开发者能看到 `test`、`test:full`、`test:fast`、`test:linux`、`test:linux:full`、`test:qa`、`qa:pwsh`，但很难仅凭命令名判断哪些是 host 测试、哪些是 Linux 容器测试、哪些是快速质量门、哪些才适合提交前完整验证。

更具体地说，仓库缺少一条标准命令在提交前同时覆盖 host `full` 与 Linux `full`。结果是 `pnpm qa` 很容易被误解成“完整回归”，而实际上它只是为了本地快速反馈设计的质量门，无法替代跨环境 pwsh 验证。

## Environment

- Module: System-wide PowerShell tooling
- Affected Component: root `package.json` 测试脚本、贡献者工作流与本地测试文档
- Platform: Windows host + Linux Docker container
- PowerShell: 7.x
- Key files:
  - `package.json`
  - `AGENTS.md`
  - `README.md`
  - `CLAUDE.md`
  - `docs/local-cross-platform-testing.md`
  - `docker-compose.pester.yml`
  - `PesterConfiguration.ps1`
- Date: 2026-03-14

## Symptoms

- root PowerShell 测试命令同时存在 `test`、`test:full`、`test:fast`、`test:linux`、`test:linux:full`、`test:qa`、`qa:pwsh`，命名维度不一致。
- `test` 与 `test:full` 语义重复，而 `test:linux` 默认又是 fast，导致 host / linux 命名不对称。
- `pnpm qa` 在文档和协作约定中被频繁提到，但它并不等于跨环境完整 pwsh 回归。
- 文档没有统一说明“改动 pwsh 相关内容时，提交前到底该跑哪条命令”。

## What Didn't Work

**Attempted Solution 1:** 继续把 `pnpm qa` 或 `pnpm qa:all` 当作提交前标准动作。  
- **Why it failed:** `qa` 系列是为了快速反馈设计的质量门，`qa:pwsh` 当前也只跑 `qa` 子集，不应该承载 host + Linux full 的重验证语义。

**Attempted Solution 2:** 新增一个泛化的 `ci:check`。  
- **Why it failed:** 这个名字和现有 `qa` / `qa:all` 语义重叠，而且没有明确表达“这是 PowerShell 测试工作流”，容易再次制造命名歧义。

**Attempted Solution 3:** 引入 `test:linux:qa` 这类命名。  
- **Why it failed:** 它把平台、测试域和质量门语义混在一起，仍然无法解决“看到名字就能判断用途”的问题。

**Attempted Solution 4:** 保留旧的 root `test:*` 命名，只在 README 里补说明。  
- **Why it failed:** 这会把理解成本继续留给使用者。只补文档不能消除命令表面的歧义，协作约定也难以收敛。

## Solution

最终方案分成四部分：

1. 将 root PowerShell / Pester 测试入口统一收敛到 `test:pwsh:*`
2. 新增 `test:pwsh:all`，并发执行 host `full` 与 Linux `full`
3. 让 root `test:pwsh:*` 命令强制在失败时返回非零退出码
4. 同步更新 AGENTS / README / CLAUDE / 本地跨平台测试文档，明确提交前动作和 Docker fallback

### Code changes

```json
// Before (ambiguous):
{
  "scripts": {
    "test": "pwsh -NoProfile -Command \"Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )\"",
    "test:full": "pwsh -NoProfile -Command \"$env:PWSH_TEST_MODE='full'; Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )\"",
    "test:fast": "pwsh -NoProfile -Command \"$env:PWSH_TEST_MODE='fast'; Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )\"",
    "test:qa": "pwsh -NoProfile -Command \"$env:PWSH_TEST_MODE='qa'; Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )\"",
    "test:linux": "docker compose -f docker-compose.pester.yml run --rm pester-fast",
    "test:linux:full": "docker compose -f docker-compose.pester.yml run --rm pester-full",
    "qa:pwsh": "pnpm format:pwsh && pnpm test:qa"
  }
}
```

```json
// After (explicit):
{
  "scripts": {
    "test:pwsh:fast": "pwsh -NoProfile -Command \"$env:PWSH_TEST_MODE='fast'; $c = ./PesterConfiguration.ps1; $c.Run.Exit = $true; Invoke-Pester -Configuration $c\"",
    "test:pwsh:qa": "pwsh -NoProfile -Command \"$env:PWSH_TEST_MODE='qa'; $c = ./PesterConfiguration.ps1; $c.Run.Exit = $true; Invoke-Pester -Configuration $c\"",
    "test:pwsh:full": "pwsh -NoProfile -Command \"$env:PWSH_TEST_MODE='full'; $c = ./PesterConfiguration.ps1; $c.Run.Exit = $true; Invoke-Pester -Configuration $c\"",
    "test:pwsh:linux:fast": "docker compose -f docker-compose.pester.yml run --rm pester-fast",
    "test:pwsh:linux:full": "docker compose -f docker-compose.pester.yml run --rm pester-full",
    "test:pwsh:all": "pnpm exec concurrently --names host,linux --prefix-colors blue,magenta --kill-others-on-fail \"pnpm test:pwsh:full\" \"pnpm test:pwsh:linux:full\"",
    "qa:pwsh": "pnpm format:pwsh && pnpm test:pwsh:qa"
  }
}
```

```markdown
# Workflow rule added to AGENTS.md:
- 若改动涉及 pwsh 相关内容（如 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`、`PesterConfiguration.ps1`、`docker-compose.pester.yml`），提交代码前执行 `pnpm test:pwsh:all`。
- 若本机 Docker 不可用，至少执行 `pnpm test:pwsh:full`，并在说明中明确 Linux 覆盖依赖 CI 或 WSL。
```

### Commands run

```bash
# 增加并发执行依赖
pnpm add -Dw concurrently

# 验证新的 host 命令族
pnpm test:pwsh:fast
pnpm test:pwsh:full

# 验证新的跨环境聚合入口
pnpm test:pwsh:all

# 根目录快速质量门
pnpm qa
```

### Verified result

- `pnpm test:pwsh:fast` 通过，说明新的 host 快速命令族工作正常。
- `pnpm test:pwsh:full` 通过，说明新的 host 完整命令与失败退出码语义工作正常。
- `pnpm test:pwsh:all` 能正确并发启动 `host` / `linux` 两路，输出带标签，并在 Linux full 失败时返回非零退出码。
- `pnpm qa` 继续通过，说明 `qa` 的快速质量门边界没有被这次工作流收敛破坏。
- 已知边界：`pnpm test:pwsh:all` 当前会暴露现有 `pnpm test:pwsh:linux:full` 基线问题，包括 Linux full 用例失败和 code coverage 收尾阶段的 `Normalize-Path` 空字符串异常。这是被新工作流提前暴露的问题，不是这次命名收敛本身引入的新回归。

## Why This Works

这次问题的根因不是“少一个命令”，而是缺少一个清晰、可执行、可传播的 pwsh 测试工作流。

1. **命名先表达测试域，再表达环境和强度。**  
   `test:pwsh:*` 先告诉使用者“这是 root PowerShell / Pester 测试”，再继续区分 `fast`、`full`、`linux:*`。这比原来的 `test`、`test:full`、`test:linux` 更容易建立稳定心智模型。

2. **`qa` 和“完整回归”被重新分层。**  
   `qa` 继续做快速质量门，`test:pwsh:all` 单独承担“pwsh 相关改动的提交前跨环境完整验证”。这避免了把已有快速流程重新拖重。

3. **跨环境验证收敛成单一入口。**  
   过去需要靠记忆去组合 host 与 Linux 命令；现在只需要执行 `pnpm test:pwsh:all`。开发者不再需要自己决定“是不是还要顺手补一轮 Linux 容器测试”。

4. **失败退出码被显式拉直。**  
   root `test:pwsh:*` 命令里统一把 `Run.Exit` 设为 `$true`，确保本地 CLI 在失败时真正返回非零。否则即使命令名清晰，自动化链路也可能误把失败当成功。

5. **新工作流会更早暴露 Linux 分支问题。**  
   这不是副作用，而是目标的一部分。`test:pwsh:all` 让 Linux full 失败在提交前而不是 CI 后置暴露，直接缩短反馈回路。

## Prevention

- **测试命名按“测试域 -> 运行环境 -> 强度”组织。**  
  Root PowerShell / Pester 命令统一使用 `test:pwsh:*`，例如 `test:pwsh:fast`、`test:pwsh:linux:full`。不要再使用只表达平台或只表达强度的名字，避免把测试域、平台和质量门语义重新混在一起。

- **把 `qa` 保持为快速质量门，不把它抬成完整回归入口。**  
  `qa` / `qa:all` / `qa:pwsh` 的职责是快速反馈和改动检查；提交前需要跨环境完整验证时，使用专门入口 `pnpm test:pwsh:all`。不要再把“`qa` 看起来像全量”当成“已经覆盖完整 PowerShell 回归”。

- **为 pwsh 相关改动定义固定的提交前动作。**  
  只要改动命中 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`、`PesterConfiguration.ps1` 或 `docker-compose.pester.yml`，提交前统一执行 `pnpm test:pwsh:all`。这条规则要同时写进 `AGENTS.md`、README 和本地测试文档，避免团队成员各自理解。

- **跨环境验证必须包含真实 Linux 容器路径，而不是只在 Windows 本机补一层包装。**  
  `test:pwsh:all` 应继续并发执行 host `full` 和 Linux `full`，让 PATH、shebang、覆盖率、容器文件路径等平台差异尽早暴露；不要把它退化成只串联两个“看起来对称”的名字。

- **Docker 不可用时，明确降级策略而不是静默跳过。**  
  本机没有 Docker 时，至少执行 `pnpm test:pwsh:full`，并在说明里明确 Linux 覆盖依赖 CI 或 WSL。不要让“没跑 Linux”变成隐式事实，否则团队会误以为已经完成跨环境验证。

- **命名迁移时，脚本、文档、协作约定必须同批更新。**  
  任何测试命令重命名都要同时更新 `package.json`、README、`docs/local-cross-platform-testing.md`、`CLAUDE.md`、`AGENTS.md`。如果只改脚本不改文档，很快就会重新出现“新人照着旧命令跑，结果和当前约定不一致”的漂移。

## Related Issues

- See also: [linux-macos-powershell-tooling-tests-system-20260314.md](../test-failures/linux-macos-powershell-tooling-tests-system-20260314.md) — 这篇文档记录了 Linux/macOS 下真实暴露的 PowerShell 测试问题，也是引入 `test:pwsh:all` 的直接动机之一。
