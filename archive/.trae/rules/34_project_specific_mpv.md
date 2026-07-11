---
alwaysApply: false
globs: config/software/mpv/**/*
---

# 📂 Project Specific Rules (MPV)

globs: config/software/mpv/**/*

## 1. Architecture

- **Config**: `mpv.conf` (主配置), `input.conf` (快捷键)。
- **Scripts**:
  - Lua Scripts: `scripts/*.lua`
  - JS/TS Scripts: `mpv_scripts/` (TypeScript Project)

## 2. TypeScript Scripts (`mpv_scripts`)

- **Build System**: Rollup (`npm run build`).
- **Workflow**:
  - 源码位于 `mpv_scripts/src/`。
  - 修改后运行 `cd mpv_scripts; pnpm build`。
  - 构建产物会自动输出到 `../scripts/` (或其他配置的输出目录)。
- **Dependencies**: 严禁在运行时依赖 `node_modules`，所有依赖必须打包。

## 3. Configuration Rules

- **Comments**: 配置文件必须保留关键注释。
- **Backup**: 修改关键配置前建议备份。
