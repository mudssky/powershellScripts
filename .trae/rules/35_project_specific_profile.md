---
alwaysApply: false
globs: profile/**/*
---
# 📂 Project Specific Rules (Profile)

## 1. Criticality

- **High Impact**: 此目录下的脚本直接影响 Shell 启动速度与稳定性。
- **Performance**: 严禁引入耗时的同步操作 (如网络请求) 到 `profile.ps1`。

## 2. Structure

- `profile.ps1`: 主入口。
- `profile_unix.ps1`: linux,macos主入口。
- `user_aliases.ps1`: 用户别名定义。
- `installer/`: 环境安装脚本。

## 3. Best Practices

- **Lazy Loading**: 尽可能延迟加载模块 (`Import-Module` 耗时较长)。
- **Error Handling**: `profile.ps1` 中的错误不应导致 Shell 启动失败 (使用 `try/catch` 并静默处理非致命错误)。
- **Cross-Platform**: 考虑 Windows/Linux/macOS 兼容性 (使用 `IsWindows`/`IsLinux`/`IsMacOS` 变量或
