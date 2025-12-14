## 目标
- 在真实 Linux 环境下稳定通过跨平台测试；对 Windows-only 方法进行明确标记与排除；统一项目执行环境为 PowerShell 7（pwsh）。

## 影响面分析
- 修改文件: `psutils/tests/*.Tests.ps1`, `psutils/modules/*.psm1`, `PesterConfiguration.ps1`, `.trae/rules/project_rules.md`
- 风险: 跨平台行为差异、覆盖率统计变化、并行执行下跳过用例计数差异

## 调研结论（失败根因）
- 缓存测试使用 Windows 环境变量: `psutils/tests/cache.Tests.ps1:24` 使用 `$env:LOCALAPPDATA` 导致 Linux 为 null。
- 字体模块与测试 Windows-only: `psutils/modules/font.psm1:41-47` 依赖 `Env:SystemRoot` 与 `\Fonts`。
- 快捷方式 Windows-only 且 PowerShell 7 Linux 无 COM: `psutils/modules/functions.psm1:152` 使用 `New-Object -ComObject`。
- Git 测试临时目录可能为 null: `psutils/tests/git.Tests.ps1:6` 依赖 `$env:TEMP`。
- 配置未排除 Windows-only 测试: `PesterConfiguration.ps1:45` 仅排除了 `Slow` 标签。
- 平台门控参考: `psutils/tests/profile_unix.Tests.ps1:12-19` 展示了 `$IsLinux`/`$IsMacOS` 条件跳过的模式。

## 修改项（跨平台与门控）
- 路径与环境变量
  - 缓存测试改为复用模块目录: `psutils/tests/cache.Tests.ps1:24` 改为 `Get-CacheBaseDirectory()` 或 `$script:CacheBaseDir`（模块已提供，见 `psutils/modules/cache.psm1:39-42`）。
  - 统一路径构造用 `Join-Path`，避免反斜杠；将 `Import-Module "$PSScriptRoot\..\modules\*.psm1"` 改为 `Join-Path $PSScriptRoot '..' 'modules' '*.psm1'`（示例: `psutils/tests/font.Tests.ps1:2`）。
  - Git 测试 `BeforeAll` 对临时目录兜底：当 `$env:TEMP` 为空时使用 `[System.IO.Path]::GetTempPath()` 或 `Join-Path $env:HOME 'tmp'`。
- Windows-only 方法标记与跳过
  - 字体与快捷方式测试添加标签 `-Tag 'windows'`，并在非 Windows 环境下统一跳过；或使用条件 `if (-not $IsWindows) { Set-ItResult -Skipped; return }`（示例: `psutils/tests/font.Tests.ps1` 与 `psutils/tests/functions.Tests.ps1`）。
  - 保持函数逻辑不变，仅在 `.NOTES` 明确为 Windows-only（参考: `psutils/modules/font.psm1:23`, `psutils/modules/functions.psm1:135-136`）。
- 跨平台测试用例修正
  - `Test-EXEProgram` 测试不改逻辑，统一使用 `pwsh` 作为存在的可执行程序名（项目约定）。更新: `psutils/tests/test.Tests.ps1:7`。
  - `Test-PathHasExe` 为 Windows-only（检测 `.exe`），添加 `-Tag 'windows'` 或条件跳过；如需跨平台版本，另行实现基于可执行权限的检测。
- Pester 配置调整（在 Linux 上排除 Windows-only）
  - 为 Windows-only 测试添加统一标签 `windows`，并在配置中排除：`PesterConfiguration.ps1:45` 增加 `ExcludeTag = @('Slow', 'windows')`。
  - 可选: 根据平台动态设置 `Run.ExcludePath`，排除 `profile_windows.Tests.ps1`、`font.Tests.ps1`、`functions.Tests.ps1`。
- 项目规则更新
  - 在 `.trae/rules/project_rules.md` 增加“执行环境为 PowerShell 7（pwsh）”的高优先级规则：
    - 统一使用 `pwsh`，测试与脚本不得依赖 Windows PowerShell 或 `powershell.exe` 名称。
    - 可执行程序检测统一以 `pwsh` 为基准示例。

## 测试执行要求（自动记录与覆盖）
- 真实 Linux 环境运行：在 `BeforeAll` 读取 `/etc/os-release` 输出发行版与版本；输出 `pwsh --version` 与 `$PSVersionTable`。
- 权限场景：普通用户默认执行；root 用户以文档示例单独运行；只读路径相关用例使用 `WhatIf` 验证。
- 并发访问：为缓存模块增加并发读取的集成测试（`Start-Job` 并行调用 `Invoke-WithCache`），确认无死锁与结果一致性。

## 测试结果验证
- 兼容性：Linux 兼容的方法通过；Windows-only 测试被排除且不会执行。
- 日志与错误：异常路径输出符合预期，失败信息包含上下文。
- 性能：`profile_unix.ps1` 保持现有基准（`< 10s`），缓存操作百毫秒级；覆盖率不低于当前基线（≥25.25%）。

## 验证步骤
- 在 Linux 下执行：`pnpm test`；观察 Windows-only 用例标记为 Skipped；`cache.Tests.ps1`、`git.Tests.ps1`、`test.Tests.ps1` 通过；失败数显著减少，覆盖率稳定。

## 风险与回滚
- 如标签化遗漏导致 Windows-only 用例仍执行，临时使用 `Run.ExcludePath` 兜底。
- 如平台防护影响 Windows 行为，保留仅测试层门控，后续再做函数断言。

## 交付物
- 测试文件平台化修订（标签/条件/路径）
- 更新后的 `PesterConfiguration.ps1`（按平台排除）
- 项目规则文件新增“统一使用 pwsh”
- 新增环境记录与并发场景测试示例