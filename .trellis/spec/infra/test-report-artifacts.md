# Test Report Artifacts Contract

## 1. Scope / Trigger

- Trigger：修改 Pester/Vitest 机器可读报告、coverage 输出、CI test reporter 或报告忽略规则。
- Scope：`PesterConfiguration.ps1`、根测试脚本、`.github/workflows/test.yml`、`tests/reports/` 和 `.gitignore`。
- Design intent：报告集中到稳定目录，不随当前工作目录漂移，也不污染仓库根目录。

## 2. Signatures

- Pester host test result：`tests/reports/testResults.xml`。
- Pester host coverage：`tests/reports/coverage.xml`。
- Vitest JUnit：`tests/reports/vitest-report.xml`。
- Pester override：`PESTER_RESULT_PATH=<custom xml path>`。
- Linux Docker Pester：named volume `/workspace-output/testResults-linux.xml`。

## 3. Contracts

- Pester 默认路径必须基于 `PesterConfiguration.ps1` 的 `$PSScriptRoot`，不能使用依赖当前目录的裸相对路径。
- 配置加载时必须确保 `tests/reports/` 存在。
- `PESTER_RESULT_PATH` 非空时覆盖默认 NUnit 路径；coverage 仍使用统一默认路径。
- `tests/reports/.gitkeep` 保证目录可见，`/tests/reports/*.xml` 必须被 Git 忽略。
- GitHub Actions 的生成命令和 reporter 必须读取同一路径。
- `test:pwsh:full` 必须复用 `Invoke-PesterMode.ps1 -Mode full -Coverage On`，不能在 package script 中使用会被 Unix shell 展开的 `$env:` 命令字符串。

## 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| 从仓库根加载 Pester 配置 | 输出到 `<repo>/tests/reports/` |
| 从 `psutils/` 等子目录加载配置 | 与根目录加载结果完全相同 |
| 设置 `PESTER_RESULT_PATH` | NUnit 报告写入显式路径 |
| `tests/reports/` 不存在 | 配置加载时自动创建 |
| CI 运行 Pester/Vitest | reporter 能在统一目录找到 XML |
| package script 包含双引号 `$env:` | Unix shell 可能提前展开并导致命令失败 |

## 5. Good / Base / Bad Cases

- Good：Pester 和 Vitest 都写入 `tests/reports/`，CI reporter 使用精确路径。
- Base：调用方通过 `PESTER_RESULT_PATH` 将单次 Pester 报告隔离到临时目录。
- Bad：默认 `OutputPath = 'testResults.xml'`，导致从不同目录运行时产生多个报告。
- Bad：继续在 package script 中内联 `pwsh -Command "$env:..."`。

## 6. Tests Required

- Pester configuration test：从根目录和子目录加载配置，断言测试结果与 coverage 路径一致且为绝对统一路径。
- Override test：设置 `PESTER_RESULT_PATH` 后断言配置保留显式路径。
- Gate：`pnpm qa`、`pnpm test:pwsh:all` 和涉及 coverage 时的 `pnpm test:pwsh:coverage`。
- Vitest reporter smoke：确认命令能创建 `tests/reports/vitest-report.xml`；测试套件自身的无关平台失败需单独记录。
- Filesystem：确认根目录和 `psutils/` 不再生成目标 XML，报告 XML 命中 `.gitignore`。

## 7. Wrong vs Correct

### Wrong

```powershell
OutputPath = 'testResults.xml'
```

```json
"test:pwsh:full": "pwsh -Command \"$env:PWSH_TEST_MODE='full'; ...\""
```

问题：报告路径依赖当前目录，`$env:` 还可能被外层 Unix shell 提前展开。

### Correct

```powershell
$reportDirectory = Join-Path $PSScriptRoot 'tests/reports'
$testResultPath = Join-Path $reportDirectory 'testResults.xml'
```

```json
"test:pwsh:full": "pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode full -Coverage On"
```

理由：路径锚定仓库根，命令参数通过 `-File` 传递，不依赖外层 shell 的变量语义。
