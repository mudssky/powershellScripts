## 一、VS Code Deno 开发配置指南

在 VS Code 中配置 Deno 非常简单，因为它有一个官方的语言服务扩展。

### 1. 安装 Deno 扩展

这是核心步骤。

1. 打开 VS Code 的扩展面板 (Extensions)。
2. 搜索 `deno`。
3. 安装 **Deno** 扩展（扩展 ID 为 `denoland.vscode-deno`）。

### 2. 启用 Deno 支持（工作区设置）

安装扩展后，Deno 扩展默认是关闭的，你需要为你的项目工作区单独启用它，以避免干扰非 Deno 项目。

#### **方法一：使用命令面板 (推荐)**

1. 打开你的 Deno 项目文件夹。
2. 按下 `Ctrl+Shift+P` (或 `Cmd+Shift+P`) 打开命令面板。
3. 输入并运行 `Deno: Initialize Workspace Configuration` (初始化工作区配置)。
4. 这个命令会为你创建或修改 `.vscode/settings.json` 文件，并自动添加必要的配置。

#### **方法二：手动配置**

在你的项目根目录下创建 `.vscode/settings.json` 文件，并添加以下内容：

```json
{
  // 启用 Deno
  "deno.enable": true,
  // 将 Deno 内置的 formatter 设置为默认格式化工具 (等同于 deno fmt)
  "editor.defaultFormatter": "denoland.vscode-deno",
  // 启用 Deno 内置的 linter (等同于 deno lint)
  "deno.lint": true,
  // (可选) 如果你的项目使用了不稳定的 Deno API，启用此项
  "deno.unstable": false
}
```

### 3. 配置 `deno.json`（或 `deno.jsonc`）

类似于 Node.js 中的 `package.json`，Deno 使用 `deno.json` 或 `deno.jsonc` 来管理项目配置、任务、导入映射 (Import Maps) 等。VS Code 扩展会自动识别并应用此文件中的设置。

一个基础的 `deno.json` 文件可能包含：

```json
{
  "compilerOptions": {
    "strict": true // TypeScript 严格模式
  },
  // 类似 npm scripts 的任务
  "tasks": {
    "start": "deno run --allow-net src/main.ts",
    "dev": "deno run --watch --allow-net src/main.ts",
    "test": "deno test --allow-read"
  },
  // 导入映射，类似于在 package.json 中配置路径别名
  "imports": {
    "~/": "./src/"
  }
}
```

### 4. 调试配置 (Debugging)

Deno 支持 V8 Inspector Protocol，与 Node.js 使用相同的调试协议，因此配置类似：

在 `.vscode/launch.json` 中添加一个 `Deno` 启动配置（如果没有 `launch.json`，点击运行和调试侧栏的齿轮图标创建）。

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "request": "launch",
      "name": "Run Deno Script",
      // 类型设置为 deno
      "type": "deno",
      // 要运行的脚本文件
      "program": "${file}",
      // Deno 运行时参数
      "runtimeArgs": [
        "run",
        "--allow-net",
        "--allow-env" // 根据你的项目需求添加所需的权限
      ],
      // (可选) 传递给脚本本身的参数
      "args": []
    }
  ]
}
```

---

## 二、Deno 快速上手备忘录（Node.js 开发者视角）

| Node.js 概念 / 命令 | Deno 对应概念 / 命令 | 差异和说明（重点关注） |
| :--- | :--- | :--- |
| **项目依赖** | **URL 导入 / `deno cache`** | 告别 `npm install`。依赖项直接在代码中通过 **URL** 导入，例如：<br> `import { serve } from "https://deno.land/std/http/server.ts";`<br>首次运行时，Deno 会自动**缓存**依赖项到本地，后续无需重复下载。`node_modules` 文件夹被消除。 |
| **依赖管理文件** | **无 (或 `deno.jsonc` / `import_map.json`)** | 无需 `package.json` 或 `package-lock.json`。Deno CLI 有内置工具处理。<br>可以使用 **Import Maps**（在 `deno.json` 中配置）来管理长 URL 的别名。 |
| **TypeScript** | **内置支持 (开箱即用)** | Deno 原生支持 TypeScript，无需配置 `tsconfig.json` 或安装 `ts-node`/编译器。<br>（虽然你可以选择使用 `tsconfig.json` 或在 `deno.json` 中配置 `compilerOptions`。） |
| **核心模块** | **Deno.std (标准库) 和 Web 标准 API** | Node.js 的 `require('fs')` 变为 Web 标准的 **`fetch`** 或 Deno 标准库 **`Deno.readFile()`** 等。`Deno` 是全局命名空间，提供所有运行时 API。 |
| **安全性** | **无权限 (沙盒模式)** | 默认情况下，Deno 脚本无法访问文件系统、网络或环境变量。这是**最大的区别**。|
| `npm run build/start` | **`deno run [文件]` 或 `deno task [任务名]`** | 使用 `deno run` 启动脚本。如果配置了 `deno.json`，可以使用 `deno task start`。 |
| `node index.js` | **`deno run --allow-net --allow-read index.ts`** | 必须通过 **`--allow-*`** 标志显式授予权限。例如：`--allow-net` 允许网络访问，`--allow-read` 允许读取文件。 |
| `eslint`, `prettier` | **`deno lint`, `deno fmt`** | Deno 内置了 Linter 和 Formatter，无需额外安装和配置这些工具。 |
| `jest`, `mocha` | **`deno test`** | Deno 内置了测试运行器，直接在 TypeScript/JavaScript 文件中编写测试即可运行。 |
| `fs.readFileSync(...)` | **`Deno.readFileSync(...)`** | Deno 的 API 鼓励使用 **Promises** 和 **`async/await`**。同步 API 具有 `Sync` 后缀。 |
| `require('module')` | **`import { ... } from 'URL/path'`** | Deno 使用 ES Modules 规范，不支持 CommonJS 的 `require()`。 |

### 核心 Deno CLI 命令

| 命令 | 作用（对标 Node.js 功能） |
| :--- | :--- |
| `deno run <file>` | 运行脚本，类似 `node <file>`。**注意权限**。|
| `deno fmt <file>` | 格式化代码（内置 Prettier）。 |
| `deno lint <file>` | 检查代码规范（内置 Linter）。|
| `deno test` | 运行项目中的所有测试文件。 |
| `deno cache <url/file>` | 预先下载并缓存依赖项。 |
| `deno doc <file>` | 为模块生成文档。 |
| `deno install ...` | 将 Deno 脚本安装为系统可执行命令。 |
| `deno upgrade` | 升级 Deno 运行时本身。 |

### 运行时权限标志 (Permission Flags)

在运行任何需要系统资源的脚本时，你必须使用以下标志之一：

| 权限标志 | 作用 |
| :--- | :--- |
| `--allow-net` | 允许网络访问（例如，启动 HTTP 服务器或发起 `fetch` 请求）。 |
| `--allow-read` | 允许文件系统读取访问（可指定路径）。 |
| `--allow-write` | 允许文件系统写入访问（可指定路径）。 |
| `--allow-env` | 允许访问环境变量。|
| `--allow-run` | 允许运行子进程（执行其他程序）。 |
| `--allow-all` | 授予所有权限（**不推荐在生产环境使用**）。|
