## 目标与依据
- 依据 `docs/cheatsheet/pwsh/Pwsh跨平台脚本最佳实践.md` 与示例 `docs/cheatsheet/pwsh/script-template.ps1`，为项目根目录的所有 `.ps1` 脚本统一落地跨平台与工程化规范。

## Plan
- [ ] Impact Analysis (影响面分析)
  - 修改文件（根目录脚本，共 41 个）：
    - `Compare-JsonFiles.ps1`, `ConventAllbyExt.ps1`, `DownloadVSCodeExtension.ps1`, `ExtractAss.ps1`, `PesterConfiguration.ps1`, `Setup-SshNoPasswd.ps1`, `Setup-VSCodeSSH.ps1`, `Start-Bee.ps1`, `VideoToAudio.ps1`, `abematv.ps1`, `cbz.ps1`, `cleanEnvPath.ps1`, `cleanTorrent.ps1`, `concatXML.ps1`, `concatflv.ps1`, `denmodown.ps1`, `dlsiteUpdate.ps1`, `downGithub.ps1`, `downWith.ps1`, `dvdcompress.ps1`, `ffmpegPreset.ps1`, `findLostNum.ps1`, `folderSize.ps1`, `get-SnippetsBody.ps1`, `gitconfig_personal.ps1`, `install.ps1`, `jupyconvert.ps1`, `losslessToQaac.ps1`, `lrc-maker.ps1`, `pngCompress.ps1`, `proxyHelper.ps1`, `pslint.ps1`, `renameLegal.ps1`, `restoreEnvPath.ps1`, `runScripts.ps1`, `smallFileCleaner.ps1`, `start-container.ps1`, `startaria2c.ps1`, `syncConfig.ps1`, `tesseract.ps1`, `test-lint-staged.ps1`, `webpCompress.ps1`
  - 潜在风险：
    - 新增 `Set-StrictMode` 和 `$ErrorActionPreference='Stop'` 可能暴露隐藏错误；
    - 统一 `Join-Path` 替换硬编码反斜杠可能影响与外部 Windows 原生命令的交互；
    - 引入 `SupportsShouldProcess` 后流程需适配 `-WhatIf`；
    - Shebang 与 LF 换行对 Windows 无影响，但需确保 UTF-8 无 BOM，以避免 Unix 下 `exec format error`。
- [ ] Step 1: Context Gathering（上下文收集）
  - 已盘点根目录脚本清单（见上）。
  - 抽样现状：
    - `install.ps1`：无 Shebang、未启用 StrictMode/Stop，路径使用 `"$PSScriptRoot\psutils"`（建议换 `Join-Path`），交互式 `Read-Host`（需保持）；`install.ps1:21-39`。
    - `start-container.ps1`：已启用 `[CmdletBinding]` 与 `Set-StrictMode`，缺少 `$ErrorActionPreference='Stop'` 与 Shebang；部分 `Join-Path` 已使用，但仍有字符串拼接风险；参考 `start-container.ps1:263-266`。
    - `Compare-JsonFiles.ps1`：有 `[CmdletBinding]` 与 `ShouldProcess`，缺少 Shebang/StrictMode/Stop；路径使用反斜杠字符串；参考 `Compare-JsonFiles.ps1:239-246`。
- [ ] Step 2: Implementation（落地改造）
  - 统一头部与运行时规范（所有文件）：
    - 第一行添加 Shebang：`#!/usr/bin/env pwsh`（参考 `script-template.ps1:1`）。
    - 增加 `[CmdletBinding(SupportsShouldProcess = $true)]`（参考 `script-template.ps1:27`）。
    - 增加 `param`（为空也可），至少便于 `-Verbose/-WhatIf`。
    - 启用严格模式与错误停止：`Set-StrictMode -Version Latest`（`script-template.ps1:38`），`$ErrorActionPreference = 'Stop'`（`script-template.ps1:40`）。
    - 将主体包裹到 `Main` 函数并使用 `try/catch/finally`（参考 `script-template.ps1:43-100`）。
    - 对有副作用的操作使用 `if ($PSCmdlet.ShouldProcess(...)) { ... }`（`script-template.ps1:75`）。
  - 路径与平台规范：
    - 全量替换 `"$PSScriptRoot\sub\path"` 为 `Join-Path $PSScriptRoot "sub" "path"`（`Pwsh跨平台脚本最佳实践.md:46-48`）。
    - 仅在必要时使用 `$IsWindows/$IsLinux/$IsMacOS` 做分支（`Pwsh跨平台脚本最佳实践.md:65-73`）。
  - 命令与输出：
    - 替换别名为完整 Cmdlet（`ls`→`Get-ChildItem`、`curl`→`Invoke-RestMethod` 等；`Pwsh跨平台脚本最佳实践.md:50-59`）。
    - 约定：数据输出使用 `Write-Output`，UI 提示可用 `Write-Host`（项目规则）。
  - 编码与换行：
    - 保存为 UTF-8 无 BOM、换行使用 LF（`Pwsh跨平台脚本最佳实践.md:19-30`）；必要时以工具批量转换（后续执行阶段完成）。
  - 重点脚本的定制化改造要点：
    - `install.ps1`：
      - 头部标准化、`Join-Path` 导入模块、非交互路径兼容；为配置步骤加 `ShouldProcess` 与 `try/catch`；必要时在 `Windows/Unix` 分支加清晰日志。
    - `start-container.ps1`：
      - 添加 `$ErrorActionPreference='Stop'` 与 Shebang；将主要执行路径用 `try/catch` 包裹；确保 `Set-Content -Encoding utf8`（无 BOM）；复核所有路径 `Join-Path`（如 `composeDir`）；对 `docker` 调用保留现有健壮探测。
    - `Compare-JsonFiles.ps1`：
      - 头部标准化；`Set-StrictMode` 与 Stop；将 `"clis\json-diff-tool"` 改为 `Join-Path`；确保不因 `npx tsx` 引入跨平台问题；完善错误上下文。
  - 文档注释：
    - 按 `.SYNOPSIS/.DESCRIPTION/.PARAMETER/.EXAMPLE` 规范补齐缺失项（项目规则）。

- [ ] Step 3: Verification（验证与自查）
  - 静态分析：尝试运行 `Invoke-ScriptAnalyzer`（如环境可用）对所有改造文件进行检查。
  - 冒烟验证：
    - 对具副作用脚本使用 `-WhatIf` 进行干运行。
    - 需要管理员或外部依赖的脚本（如 Docker、Node）仅做参数解析与路径构造的冒烟测试。
  - 运行环境差异：
    - Windows/WSL/Linux/macOS 下最小化验证：
      - Windows：直接 `pwsh -File`；
      - Linux/macOS：确保 `chmod +x` 后 `./script.ps1` 可执行（Shebang 起效）。

- [ ] Step 4: Documentation（文档更新）
  - 若脚本参数或行为变化，更新脚本头部注释与 `README.md`（如存在）。
  - 在 `docs/cheatsheet/pwsh/Pwsh跨平台脚本最佳实践.md` 增补“迁移清单”示例。

## 代码引用（确认改造点）
- `docs/cheatsheet/pwsh/script-template.ps1:26-41`（高级函数与严格模式示例）
- `docs/cheatsheet/pwsh/script-template.ps1:43-100`（`Main`/`try/catch/finally`/`ShouldProcess` 模式）
- `docs/cheatsheet/pwsh/Pwsh跨平台脚本最佳实践.md:46-48`（跨平台 `Join-Path`）
- `install.ps1:21-39`（模块导入与权限交互现状）
- `start-container.ps1:263-266`（路径拼接示例，需统一）
- `Compare-JsonFiles.ps1:239-246`（工具路径字符串，建议改 `Join-Path`）

## 风险缓解
- 分批次改造与验证，优先处理无外部依赖的脚本；
- 对可能影响生产使用的脚本保留原行为，新增 `-WhatIf` 干运行；
- 一旦发现兼容性问题，快速回滚具体文件并记录差异。

## 交付物
- 全量更新后的根目录 `.ps1` 文件；
- 验证报告（静态分析与冒烟结果摘要）；
- 变更说明（包含规范对照与关键差异）。

请确认以上计划，我将按此执行并提交具体文件改造。