---
alwaysApply: false
globs: scripts/ahk/**/*
---
# 📂 Project Specific Rules (AutoHotkey)

globs: scripts/ahk/**/*

## 1. Core Stack

- **Language**: AutoHotkey v2.0 (`#Requires AutoHotkey v2.0`)
- **Structure**:
  - `base.ahk`: 基础配置与公共函数。
  - `scripts/*.ahk`: 功能脚本模块。
  - `makeScripts.ps1`: 构建脚本，用于合并模块。

## 2. Coding Standards

- **Version**: 严禁使用 AHK v1 语法，必须兼容 v2。
- **Formatting**: 使用 Tab 缩进 (或保持当前文件一致性)。
- **Hotkeys**: 避免覆盖系统关键快捷键 (如 Win+L)。

## 3. Workflow

- **Modification**: 修改 `scripts/` 下的模块文件，而不是直接修改构建产物。
- **Build**: 修改后必须运行 `.\makeScripts.ps1` 重新生成最终脚本。
- **Reload**: 构建后需重载 AHK 脚本生效。
