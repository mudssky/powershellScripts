随着 Deno 对 NPM 生态系统的支持日益完善，Deno 正在成为一个更灵活的 JavaScript/TypeScript 运行时和工具包。

Deno 作为包管理器时，其哲学与传统的 NPM 有很大的不同。它主要有三种依赖管理模式：**URL 导入**、**Import Maps** 和 **`npm:` Specifier**。

这里是一份 Deno 包管理器功能的速查表 (Cheatsheet)。

---

## Deno 包管理器 (Package Manager) Cheatsheet

### 1. 核心依赖管理哲学

| 机制 | Node.js 对标 | 描述 | 优势 |
| :--- | :--- | :--- | :--- |
| **URL 导入** | `require()` / `import` (文件名) | 直接在代码中使用 URL 导入模块，版本号嵌入 URL 中。 | 无需安装、去中心化、无 `node_modules`。 |
| **Import Maps** | 路径别名 (例如 `tsconfig.json` 或 Webpack 配置) | 在 `deno.jsonc` 中定义短路径到完整 URL 的映射。 | 简化导入路径，集中管理版本。 |
| **`npm:` Specifier** | `require('package-name')` | 允许直接在 Deno 代码中导入 NPM 包。 | 兼容现有 NPM 生态，无需 `npm install`。 |

### 2. Deno 配置文件 (`deno.jsonc`)

这个文件是 Deno 依赖和配置的中心，取代了 `package.json` 的大部分功能。

| 区域 | 作用 | 示例 |
| :--- | :--- | :--- |
| **`imports`** | 核心的导入映射。将短路径映射到完整 URL 或 `npm:` 包。 | `"imports": { "std/": "https://deno.land/std@0.211.0/", "lodash": "npm:lodash@4.17.21" }` |
| **`tasks`** | 类似 `package.json` 的 `scripts`，定义可运行的任务。 | `"tasks": { "start": "deno run --allow-net mod.ts" }` |
| **`lock`** | 指定依赖锁文件路径 (类似 `package-lock.json`)，用于保证依赖版本一致。 | `"lock": "deno.lock"` |

### 3. D常用命令 (Package Management Commands)

| Deno 命令 | 作用 | Node.js 对标功能 | 备注 |
| :--- | :--- | :--- | :--- |
| `deno run <file>` | 运行脚本，自动下载/缓存依赖。 | `node <file>` | 第一次运行会自动缓存依赖。 |
| `deno cache <file/url>` | 强制下载并缓存依赖项。 | `npm install` (下载依赖) | 用于预下载，确保离线可用。 |
| `deno check <file>` | 检查代码类型和依赖项。 | `tsc --noEmit` | 内置的类型检查。 |
| `deno doc <file/url>` | 生成代码文档。 | `jsdoc` / `typedoc` | 内置文档生成器。 |
| `deno vendor` | 将远程依赖下载到本地目录。 | `npm install` (在项目中创建 `node_modules`) | 用于完全隔离或离线环境。不常用。 |
| `deno lint` | 代码 Linter。 | `eslint` | 内置，无需配置。 |
| `deno fmt` | 代码 Formatter。 | `prettier` | 内置，无需配置。 |
| `deno task <name>` | 运行 `deno.jsonc` 中定义的任务。 | `npm run <script-name>` | |

### 4. 依赖导入 (Importing Dependencies)

#### A. 标准 URL 导入 (最常见)

| 场景 | 代码示例 | 解释 |
| :--- | :--- | :--- |
| **Deno 标准库** | `import { serve } from "https://deno.land/std@0.211.0/http/server.ts";` | 标准库 URL，通常包含版本号。 |
| **第三方模块** | `import { Application } from "https://deno.land/x/oak@v12.6.1/mod.ts";` | `deno.land/x/` 是社区托管模块的首选。 |

#### B. 使用 Import Maps 简化路径

1. **在 `deno.jsonc` 中配置映射：**

    ```json
    // deno.jsonc
    {
      "imports": {
        "oak/": "https://deno.land/x/oak@v12.6.1/",
        "utils/": "./src/utils/"
      }
    }
    ```

2. **在代码中导入：**

    ```typescript
    // 代码中
    import { Application } from "oak/mod.ts";
    import { helper } from "utils/helper.ts";
    ```

#### C. 导入 NPM 包

1. **在代码中直接导入：**

    ```typescript
    import React from "npm:react@18.2.0";
    import _ from "npm:lodash@4.17.21";
    ```

2. **在 `deno.jsonc` 中通过 Import Maps 映射：**

    ```json
    // deno.jsonc
    {
      "imports": {
        "react": "npm:react@18.2.0"
      }
    }
    ```

### 5. 依赖锁定和版本管理

| 机制 | 作用 | 命令/配置 |
| :--- | :--- | :--- |
| **依赖锁定** | 锁定所有依赖（URL 和 NPM 包）的确切版本和哈希值，确保构建的可复现性。 | 1. 在 `deno.jsonc` 中设置 `"lock": "deno.lock"`。 <br>2. 运行 `deno run --lock=deno.lock <file>` 或 `deno check --lock=deno.lock <file>` 来生成或验证锁文件。 |
| **更新依赖** | 更新指定脚本的所有 URL 依赖到最新版本。 | `deno cache --reload <file>` |
| **强制重新加载** | 强制重新下载所有依赖项，忽略本地缓存。 | `deno run --reload <file>` |

### 6. 权限管理 (Security)

Deno 的包管理也包括权限管理，这是与 Node.js 最大的不同。

| 标志 | 作用 | 对应权限 |
| :--- | :--- | :--- |
| `--allow-net` | 允许网络请求 (例如 `fetch`) 或开启 HTTP 服务器。 | **网络** |
| `--allow-read` | 允许文件系统读取 (例如 `Deno.readTextFile`)。 | **文件读取** |
| `--allow-write` | 允许文件系统写入 (例如 `Deno.writeTextFile`)。 | **文件写入** |
| `--allow-env` | 允许访问环境变量 (例如 `Deno.env.get`)。 | **环境变量** |
| `--allow-ffi` | 允许调用外部函数接口 (用于原生插件，如前面提到的 `faiss-node`)。 | **原生调用** |
| `--allow-all` | 授予所有权限。 | **不推荐** |
