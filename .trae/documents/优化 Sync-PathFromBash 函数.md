## 目标
- 提升 `Sync-PathFromBash` 的健壮性、可控性与可测试性，减少意外覆盖/污染 `PATH`。

## 影响面分析
- 修改文件：`psutils/modules/env.psm1`
- 风险：环境变量影响面大，错误追加可能导致命令解析异常；需提供 Dry-Run 与更严格的防护。

## 现状问题与优化方向
- 信息流与可观察性：当前使用 `Write-Information`，示例建议 `-Verbose`，但未使用 `Write-Verbose`；建议统一信息/详细日志策略。
- 输出未结构化：只打印，不返回结构化结果，调用方无法编程处理新增项、跳过项、统计信息。
- 目录有效性：未校验路径是否存在（`Test-Path`），可能追加无效目录。
- 去重与归一化：未去重；未做修剪（`Trim()`）、末尾斜杠/空白处理；大小写敏感性（Linux）与符号链接差异未考虑。
- 排序与策略：一律追加到末尾，无法控制优先级（例如优先使用 Bash 的路径）；缺少 `-Prepend`/`-Append` 选项。
- 安全开关：缺少 `-WhatIf`/`-Confirm` 或 Dry-Run；无法在 CI/脚本中安全预览更改。
- 回退路径：`bash -l` 失败仅告警退出；可提供回退（如 `bash -c 'source /etc/profile; echo $PATH'`），并在信息流中标注来源。
- 错误处理：建议在关键步骤使用 `ErrorActionPreference='Stop'` 并提供更具体的上下文消息。
- 性能与正确性：`Compare-Object` 能用但不直观；可用 `HashSet`/`Select-Object -Unique` 实现更明确的缺失集计算，并保留 Bash 顺序。

## 具体改动建议（按代码位置）
- env.psm1:454 — 为 Bash 输出添加修剪：将 `$bashPathOutput = bash -l -c 'echo $PATH'` 改为捕获并 `.Trim()`，避免尾随换行影响分割。
- env.psm1:461-466 — 在拆分后对两侧路径进行 `Trim()`，并用 `Select-Object -Unique` 去重；可考虑规范化末尾斜杠。
- env.psm1:472 — 用显式集合差运算替换 `Compare-Object`，同时保留 Bash 顺序（遍历 `bashPaths`，仅选不在 `psPathsSet` 的项）。
- env.psm1:481-486 — 在写入前过滤不存在目录：`Where-Object { Test-Path -LiteralPath $_ -PathType Container }`；并提供 `-IncludeNonexistent` 开关（默认 false）。
- 新增参数：
  - `-Prepend`（默认 `false`）：将缺失项前置到 `PATH`，用于优先使用 Bash 环境。
  - `-WhatIf`/`-Confirm`：沿用 PowerShell 语义，提供安全预览与确认。
  - `-ReturnObject`（默认 `true`）：返回 `PSCustomObject`（如 `AddedPaths`, `SkippedPaths`, `Source`, `ElapsedMs`）。
  - `-IncludeNonexistent`（默认 `false`）：是否允许追加不存在目录。
- 日志改造：
  - 进度与细节使用 `Write-Verbose`。
  - 重要提示保留 `Write-Information`，并允许通过 `-InformationAction` 控制显示。
- 回退策略：当 `bash -l` 返回非零，尝试 `bash -c 'source /etc/profile >/dev/null 2>&1; echo $PATH'`，并记录来源 `Source='bash-login'|'bash-profile-fallback'`。
- 返回值：返回结构化对象，便于外部脚本做断言或记录；同时保留当前打印行为。

## 接口示例（不立即修改，仅描述）
- `Sync-PathFromBash [-Prepend] [-WhatIf] [-Confirm] [-IncludeNonexistent] [-ReturnObject] [-Verbose]`
- 返回：`[PSCustomObject]`，字段：`SourcePathsCount`, `CurrentPathsCount`, `AddedPaths`, `SkippedPaths`, `NewPath`, `Source`, `ElapsedMs`

## 验证方案
- 冒烟：在 Linux/macOS 会话中运行 `-WhatIf` 与真实执行，确认无重复、仅追加存在目录、顺序符合策略。
- 极端用例：
  - Bash 输出包含尾随换行/空白（验证 `.Trim()`）。
  - PATH 含重复项与不存在目录（验证去重与过滤）。
  - `bash` 不存在或退出码非零（验证回退与错误信息）。
  - `-Prepend` 与 `-Append` 不同策略对顺序的影响。
- Pester：针对集合差、过滤逻辑、返回对象的字段完整性写基本单测。

## 实施步骤
1. 调整 Bash 调用与输出修剪，添加回退逻辑与来源标注。
2. 拆分后归一化、去重，构建 `HashSet`。
3. 计算缺失项并按策略过滤不存在目录；实现 `-IncludeNonexistent`。
4. 支持 `-Prepend`/`-Append` 并实现 `-WhatIf`/`-Confirm`；只在非 WhatIf 情况下更新 `$env:PATH`。
5. 输出结构化对象并改造日志为 `Write-Verbose` + 可控信息流。
6. 增补 Pester 测试与使用示例文档。

## 交付物
- 更新后的 `Sync-PathFromBash` 函数实现。
- 基本 Pester 测试（集合差与过滤、参数行为）。
- README/模块注释更新（`.SYNOPSIS`, `.PARAMETER`, `.EXAMPLE`）。

请确认上述计划，确认后我将据此实现并提交具体改动。