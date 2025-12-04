## 目标
- 使 `profile_unix.ps1` 中的 `Sync-PathFromBash | Out-Null` 在错误发生时可预期地“终止或报告”，避免悄然失败。
- 优化 `Sync-PathFromBash` 方法的性能与稳健性，降低启动时的开销。

## 影响面分析
- 修改文件：`profile/profile_unix.ps1`、`psutils/modules/env.psm1`、`tests/Sync-PathFromBash.Tests.ps1`
- 风险：环境变量修改具有全局影响；错误语义调整可能改变现有调用方的行为（从非终止改为终止）。

## 问题分析与方案
### 错误语义（profile_unix.ps1）
- 现状：`Sync-PathFromBash` 内部使用 `Write-Warning`/`Write-Error`，多数为非终止错误；`| Out-Null` 只丢弃输出流，不影响错误流，但不会抛出异常。
- 方案：
  1. 在 `profile_unix.ps1` 使用 `-ErrorAction Stop` 强制将错误升格为终止错误，并包裹 `try/catch` 明确处理：
     - `try { Sync-PathFromBash -ErrorAction Stop | Out-Null } catch { Write-Error ... }`
  2. 同步在函数中提供可选开关 `-ThrowOnFailure`（默认 `false`），在无法获取 PATH 等关键失败场景调用 `throw`；调用方可选择更严格模式。

### 性能优化（env.psm1）
- 外部进程开销：每次调用都会 `bash` 启动新进程，代价高；默认已切换为非登录（`.bashrc`），但仍需优化。
- 方案：
  1. 引入轻量缓存：新增参数 `-CacheSeconds`（默认如 300 秒），将上次获取的 Bash PATH 缓存到 `~/.cache/powershellScripts/bash_path.json`（含来源标记与时间戳），在有效期内直接使用缓存，避免重复启动 `bash`。
  2. 去管道微优化：用原生循环/集合替换 `ForEach-Object`/`Where-Object`/`Select-Object -Unique`，减少解释器与管道开销。
  3. 预分配集合容量：对缺失集 `List[string]` 预估容量为 `bashPaths.Count`，降低扩容成本；合并日志输出，避免在循环中重复 `Write-Verbose`。
  4. 验证开关复用：保留现有 `-IncludeNonexistent` 作为“跳过 `Test-Path`”的性能开关；在文档中明确其性能影响。
  5. 其他细化：慎用 `Resolve-Path`（昂贵），保持 `join` 与字符串拼接以降低开销。

## 实施步骤
1. `profile_unix.ps1`：在行 160 将调用改为 `try/catch` + `-ErrorAction Stop`，确保异常可被捕获并报告。
2. `env.psm1`：
   - 添加 `-ThrowOnFailure` 与 `-CacheSeconds` 参数；实现缓存读取/写入逻辑（文件存在、时间戳校验、来源一致）。
   - 用循环替换管道式 `Trim`/去重/过滤；整合日志输出。
   - 保持默认非登录与 `-Login` 分支逻辑不变，兼容现有用法。
3. `tests`：完善 Pester 测试，覆盖 `-Login`/默认分支、`-IncludeNonexistent`、`-CacheSeconds`（模拟缓存命中/过期）、错误语义（`-ThrowOnFailure`）。

## 验证方案
- 冒烟：执行 `Sync-PathFromBash -WhatIf -ReturnObject:$true` 与 `-Login` 变体；测量 `Measure-Command` 对比缓存命中与未命中耗时。
- 错误路径：模拟 `bash` 不可用或返回空，验证 `-ThrowOnFailure` 与 `-ErrorAction Stop` 行为。
- Pester：对象结构完整性、参数行为、缓存分支、目录过滤的正确性。

请确认以上方案，确认后我将进行实现与测试。