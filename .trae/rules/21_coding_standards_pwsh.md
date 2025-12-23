---
alwaysApply: false
globs: *.ps1,*.psm1
---
# 🛡️ Coding Standards (PowerShell)

## 1. Naming Conventions

- **Functions**: 必须遵循 `Verb-Noun` (e.g., `Get-SystemInfo`)。
- **Files**: `PascalCase.ps1` 或 `camelCase.ps1` (保持一致性)。
- **Variables**: `PascalCase` 或 `camelCase` (保持一致性)。

## 2. Documentation (DocStrings)

- **必须包含**:
  - `.SYNOPSIS`: 简短描述。
  - `.DESCRIPTION`: 详细描述。
  - `.PARAMETER`: 参数说明。
  - `.EXAMPLE`: 使用示例。

## 3. Error Handling

- **配置**: `$ErrorActionPreference = 'Stop'`。
- **结构**: 使用 `try/catch` 包裹主逻辑。
- **禁止**: 严禁吞掉错误 (Empty Catch Block)。
