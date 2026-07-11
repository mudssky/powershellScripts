---
alwaysApply: false
globs: psutils/**/*
---

# 📂 Project Specific Rules (PSUtils)

## 1. Architecture

- **Module Root**: `psutils.psd1` (Manifest), `index.psm1` (Entry).
- **Sub-modules**: `modules/*.psm1` (功能模块).
- **Tests**: `tests/*.Tests.ps1` (Pester 测试).

## 2. Development Workflow

- **Adding Functions**:
  1. 在 `modules/` 下对应模块文件中添加函数。
  2. 确保函数导出 (`Export-ModuleMember`).
  3. 在 `tests/` 下添加对应测试用例。
- **Naming**: 模块文件全小写 (`network.psm1`), 函数 `Verb-Noun`.

## 3. Testing

- **Mandatory**: 修改核心逻辑后必须运行测试。
- **Command**: `Invoke-Pester ./tests/` 或针对特定文件测试。

## 4. Documentation

- 每个导出函数必须包含完整的 `.SYNOPSIS` 和 `.EXAMPLE`。
- 更新 `README.md` 如果添加了新模块或重大功能。
