---
alwaysApply: false
globs: scripts/node/**/*
---

# 📂 Project Specific Rules (Node.js)

## 1. Architecture (`scripts/node`)

- **Build System**: Rspack 单文件构建。
- **Location**: 源码位于 `scripts/node/src/`。
- **Output**: 构建后会自动在项目根目录 `bin/` 生成对应的 Shim 脚本。

## 2. Workflow

- **新增脚本**: 在 `scripts/node/src/` 下新建 `.ts` 文件，构建系统会自动识别。
- **Commands**:
  - `pnpm build`: 生产构建 (压缩)。
  - `pnpm build:dev`: 开发构建 (不压缩)。
  - `pnpm build:standalone`: 独立构建 (复制 JS 到 bin)。
  - `pnpm test`: 运行 Vitest。
  - `pnpm qa`: format && lint && test (完成需求后必须执行，修复出现的问题)。
