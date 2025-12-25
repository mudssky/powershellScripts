# Node.js TypeScript Scripts

这是一个用于管理和打包 TypeScript 脚本的工具箱。基于 Rspack 构建，支持生成单文件脚本，并自动创建 Windows (.cmd) 和 Linux (Shell) 的可执行封装。

## 包含的工具

* **[rule-loader](docs/rule-loader.md)**: AI 编码规则加载器 CLI。用于加载 `.trae/rules` 目录下的规则文件，支持 Markdown/JSON 输出。

## 目录结构

```text
scripts/node/
├── src/               # 脚本源码目录 (在此处添加 .ts 文件)
├── dist/              # 打包产物目录
├── bin/               # (本地调试用) 生成的执行脚本
├── generate-bin.js    # 自动生成 bin 封装的脚本
├── rspack.config.ts   # Rspack 构建配置
└── package.json
```

## 快速开始

### 1. 添加新脚本

在 `src` 目录下创建一个新的 TypeScript 文件，例如 `src/my-tool.ts`：

```typescript
// src/my-tool.ts
import { program } from 'commander';

console.log('Hello from my tool!');
```

### 2. 构建

在当前目录下运行构建命令：

```bash
# 标准构建 (压缩，生成 Shim 指向 dist)
npm run build

# 开发构建 (不压缩，便于调试)
npm run build:dev

# 独立构建 (打包并复制 JS 到 bin 目录，适合分发)
npm run build:standalone
```

### 3. 使用

构建完成后，可执行文件会自动生成到项目根目录的 `bin` 文件夹中 (`c:\home\env\powershellScripts\bin`)。

确保该目录在你的系统 `PATH` 环境变量中，即可直接在终端运行：

```bash
my-tool
```

## 构建模式说明

| 命令 | 描述 | 产物位置 (Shim) | JS 文件位置 | 压缩 | 适用场景 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `build` | 标准构建 | `../../bin/` | `dist/` (引用) | ✅ | 日常使用 |
| `build:dev` | 开发构建 | `../../bin/` | `dist/` (引用) | ❌ | 开发调试 |
| `build:standalone` | 独立构建 | `../../bin/` | `../../bin/` (复制) | ✅ | 分发/独立部署 |

## 技术栈

* **构建工具**: [Rspack](https://www.rspack.dev/) - 高性能构建引擎
* **语言**: TypeScript
* **运行时**: Node.js

## 注意事项

* 打包后的文件默认为 CommonJS 格式 (`.cjs`)，以兼容不同环境。
* Shim 脚本会自动处理跨平台兼容性 (Windows/Linux)。
