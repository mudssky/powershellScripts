# VS Code Tasks 速查

### **VS Code Tasks 快速参考 (Cheatsheet)**

VS Code Tasks 是一个内置功能，用于自动化和集成外部工具命令（如编译、运行脚本、打包）。无需离开编辑器，即可一键执行终端命令。

---

### **🚀 核心流程：创建与运行**

#### **1. 创建 `tasks.json` 文件**

1. 按 `F1` 或 `Ctrl+Shift+P` (macOS: `Cmd+Shift+P`) 打开命令面板。
2. 输入 `Tasks: Configure Task` (任务: 配置任务)。
3. 选择 `Create tasks.json file from template` (从模板创建 tasks.json 文件)。
4. 选择 `Others` (其他) 来创建一个通用的、可自定义的模板。

这会在你的项目根目录创建 `.vscode/tasks.json` 文件。

#### **2. 运行任务**

| 操作 (Action) | 快捷键 / 命令 | 说明 (Description) |
| :--- | :--- | :--- |
| **运行指定任务** | `F1` > `Tasks: Run Task` | 显示所有可用任务列表，供你选择。 |
| **运行默认构建任务** | `Ctrl+Shift+B` (macOS: `Cmd+Shift+B`) | 直接运行被标记为默认的构建任务，最高效！ |
| **重新运行上次任务** | `F1` > `Tasks: Rerun Last Task` | 无需选择，快速重复执行上一个任务。 |

---

### **🔧 `tasks.json` 结构与核心属性**

这是一个包含常用配置的 `tasks.json` 示例：

```json
{
  "version": "2.0.0", // 文件格式版本，必须是 "2.0.0"
  "tasks": [
    {
      "label": "Build C++ Project", // 任务名称，在列表中显示
      "type": "shell", // 任务类型，'shell' 或 'process'
      "command": "g++", // 要执行的命令
      "args": [ // 传递给命令的参数列表
        "-g",
        "${file}",
        "-o",
        "${fileDirname}/${fileBasenameNoExtension}"
      ],
      "group": { // 将任务分组，用于快捷键
        "kind": "build", // 分组类型，可以是 'build' 或 'test'
        "isDefault": true // 设置为默认构建任务 (Ctrl+Shift+B)
      },
      "presentation": { // 控制任务终端的行为
        "echo": true, // 在终端显示执行的命令
        "reveal": "always", // 总是显示终端面板
        "focus": false, // 不把焦点自动切换到终端
        "panel": "shared", // 所有任务共享一个终端
        "clear": true // 每次运行时清空终端
      },
      "problemMatcher": [ // 问题匹配器，用于捕捉错误和警告
        "$gcc" // 使用内置的 GCC 编译器错误匹配器
      ]
    },
    {
      "label": "Run Python Script",
      "type": "shell",
      "command": "python3 ${file}",
      "problemMatcher": [] // 如果不需要捕捉问题，留空即可
    }
  ]
}
```

#### **关键属性详解**

| 属性 (Property) | 类型 (Type) | 说明 (Description) |
| :--- | :--- | :--- |
| `label` | `string` | **必需**。任务的唯一名称，用于在UI中识别。 |
| `type` | `string` | **必需**。任务类型。最常用的是 `shell`（在shell中执行）和 `process`（作为独立进程执行）。还有 `npm`、`gulp` 等专用类型。 |
| `command` | `string` | **必需**。要执行的命令或可执行文件的路径。 |
| `args` | `string[]` | 传递给 `command` 的参数数组。 |
| `group` | `object` | 将任务归类为 `build` 或 `test` 任务，并可设为 `isDefault: true` 以便通过快捷键运行。 |
| `problemMatcher`| `string \| string[]` | **核心功能**。用于解析任务输出，并在“问题”面板中显示错误/警告。VS Code 内置了 `$gcc`, `$tsc`, `$eslint-compact` 等。 |
| `dependsOn` | `string[]` | 定义前置任务。运行此任务前，会先按顺序执行依赖的任务。 |
| `presentation` | `object` | 控制任务终端的外观和行为，如是否清屏、是否自动显示等。 |
| `options` | `object` | 配置任务执行环境，如 `cwd` (当前工作目录)。 |

---

### **✨ 常用变量 (让任务更灵活)**

在 `command`, `args`, `options` 中使用这些变量，让你的任务变得通用。

| 变量 (Variable) | 说明 (Description) | 示例 |
| :--- | :--- | :--- |
| `${workspaceFolder}` | 工作区的根目录路径 | `/home/user/my-project` |
| `${file}` | 当前活动编辑器的完整文件路径 | `/home/user/my-project/src/main.js` |
| `${fileDirname}` | 当前文件的目录路径 | `/home/user/my-project/src` |
| `${fileBasename}` | 当前文件的文件名（含扩展名） | `main.js` |
| `${fileBasenameNoExtension}` | 当前文件的文件名（不含扩展名） | `main` |
| `${fileExtname}` | 当前文件的扩展名 | `.js` |
| `${lineNumber}` | 当前光标所在的行号 | `42` |
| `${selectedText}` | 当前编辑器中选中的文本 | `console.log('Hello')` |

---

### **💡 实用示例 (即插即用)**

#### **1. 编译并运行 C/C++ 文件**

```json
{
  "label": "Compile and Run C++",
  "type": "shell",
  "command": "g++ -g '${file}' -o '${fileDirname}/${fileBasenameNoExtension}' && '${fileDirname}/${fileBasenameNoExtension}'",
  "group": "build",
  "problemMatcher": ["$gcc"]
}
```

#### **2. 运行 NPM 脚本**

```json
{
  "label": "NPM: Start Dev Server",
  "type": "npm", // 使用 npm 专用类型
  "script": "dev", // package.json 中的脚本名
  "problemMatcher": []
}
```

#### **3. 运行 Python 文件**

```json
{
  "label": "Run Active Python File",
  "type": "shell",
  "command": "python", // 或 python3
  "args": ["${file}"]
}
```

#### **4. 组合任务：先构建，再启动服务**

```json
{
    "tasks": [
        {
            "label": "Build",
            "type": "npm",
            "script": "build"
        },
        {
            "label": "Serve",
            "type": "shell",
            "command": "node ./dist/server.js"
        },
        {
            "label": "Build and Serve",
            "dependsOn": [ // 依赖 "Build" 和 "Serve" 任务
                "Build",
                "Serve"
            ],
            "dependsOrder": "sequence", // "sequence" 表示串行执行
            "problemMatcher": []
        }
    ]
}
```

---

### **⭐ 最佳实践**

* **默认构建任务**：将最常用的编译/打包命令设为 `group` 中的默认构建任务，使用 `Ctrl+Shift+B` 一键触发。
* **善用问题匹配器**：为编译、Linter 等任务配置 `problemMatcher`，可以极大提升修复错误的效率。
* **变量是核心**：多使用 `${file}` 和 `${workspaceFolder}` 等变量，避免硬编码路径，让任务可重用。
* **保持简洁**：为每个项目只配置最核心、最常用的任务。
