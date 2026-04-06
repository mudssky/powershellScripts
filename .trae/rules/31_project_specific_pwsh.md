---
alwaysApply: false
globs: **/*.ps1, **/*.psm1
---

# 📂 Project Specific Rules (PowerShell)

## 1. Architecture (`scripts/pwsh`)

- **Location**: 脚本源码位于 `scripts/pwsh/` 下的各分类目录中。
- **Shim Generation**:
  - 运行 `Manage-BinScripts.ps1 -Action sync` 更新 `bin/` 目录。
  - `install.ps1` 会自动调用同步逻辑。

## 2. Best Practices

- **Header**:
  - Line 1: `#!/usr/bin/env pwsh`
  - Line 2+: `[CmdletBinding(SupportsShouldProcess = $true)]`
  - Setup: `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`
- **Path Handling**:
  - 严禁使用字符串拼接路径 (如 `"$root\bin"`)。
  - **必须** 使用 `Join-Path`。
- **Encoding**: UTF-8 (No BOM), LF line endings.
