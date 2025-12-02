# 🚀 VS Code Multi-root Workspaces Cheatsheet

### 1. 基础操作 (Basics)

| 目标 | 操作/快捷键 | 说明 |
| :--- | :--- | :--- |
| **创建工作区** | `File` > `Add Folder to Workspace...` | 添加第一个文件夹后，再添加第二个即可进入多根模式。 |
| **保存工作区** | `File` > `Save Workspace As...` | 生成一个 `.code-workspace` JSON 文件。 |
| **切换工作区** | `Ctrl + R` (Recent) | 像切换项目一样快速切换不同的工作区配置。 |
| **快速打开文件** | `Ctrl + P` | 搜索范围会自动包含**所有**根文件夹中的文件。 |
| **全局搜索** | `Ctrl + Shift + F` | 默认搜索所有项目，可指定 `./projectA` 仅搜索特定项目。 |

---

### 2. 配置文件结构 (.code-workspace)

这是工作区的核心，所有的魔法都在这个 JSON 文件里。建议**手动编辑**它来实现高级功能。

```json
{
  "folders": [
    {
      "path": "server", // 支持相对路径（推荐）或绝对路径
      "name": "Backend API" // 【技巧】给文件夹起别名，不影响文件系统
    },
    {
      "path": "client",
      "name": "Frontend App"
    }
  ],
  "settings": {
    // 这里的设置只对当前工作区生效，覆盖 User Settings
    "editor.fontSize": 14,
    "files.exclude": {
      "**/.git": true
    }
  },
  "extensions": {
    // 推荐该工作区必装的插件
    "recommendations": ["dbaeumer.vscode-eslint"]
  }
}
```

---

### 3. 设置优先级 (Settings Precedence)

这是最容易混淆的地方，务必记住优先级顺序（由高到低）：

1. 🥇 **文件夹设置** (`project/.vscode/settings.json`)
    * *最高优先级*。针对单个项目的特定设置（如 Python 解析器路径）。
2. 🥈 **工作区设置** (`.code-workspace` 文件中的 `"settings"`)
    * *中等优先级*。针对这组项目的通用设置（如隐藏共同的 `node_modules`）。
3. 🥉 **用户设置** (全局 User Settings)
    * *最低优先级*。你的个人通用习惯。

> **技巧**：如果你想统一所有项目的格式化规则，写在 `.code-workspace` 里；如果你想单独定义后端用 Python 环境，写在后端的 `.vscode/settings.json` 里。

---

### 4. 调试黑科技 (Compound Debugging)

这是多根工作区最强大的功能：**一键同时启动前后端**。

你需要创建一个**工作区级别**的 `launch.json`（或者直接写在 `.code-workspace` 文件的 `"launch"` 字段中）。

**示例：一键启动 Node 后端和 React 前端**

```json
{
  "launch": {
    "configurations": [], // 这里留空，配置引用各项目的 launch.json
    "compounds": [
      {
        "name": "🚀 Full Stack Debug",
        "configurations": [
          "Launch Server", // 对应 server/.vscode/launch.json 中的 name
          "Launch Client"  // 对应 client/.vscode/launch.json 中的 name
        ]
      }
    ]
  }
}
```

* **使用方法**：在 Debug 面板下拉菜单选择 "🚀 Full Stack Debug"，点击开始，两个项目会同时启动调试。

---

### 5. 变量引用 (Variable Substitution)

在 `tasks.json` 或 `launch.json` 中，由于有多个根目录，需要明确指定路径：

| 变量 | 含义 |
| :--- | :--- |
| `${workspaceFolder}` | **慎用**。它通常指向第一个添加的文件夹或当前聚焦文件所在的文件夹，容易指错。 |
| `${workspaceFolder:FolderName}` | **推荐**。明确指定引用哪个项目。例如 `${workspaceFolder:Backend API}` (对应你在配置中起的别名或文件夹名)。 |

---

### 6. Git 管理 (Source Control)

VS Code 的源代码管理（SCM）面板会自动检测工作区内所有的 `.git` 仓库。

* **UI 变化**：SCM 面板会变成“分栏”显示，每个项目（Repository）一个列表。
* **技巧**：你可以分别提交，也可以按住 `Ctrl` 选中多个 Repos 中的文件进行批量操作（视插件支持情况）。

---

### 7. 必装插件推荐 (Extensions)

某些插件对 Multi-root 支持特别好，能极大提升体验：

1. **Project Manager**
    * *作用*：将 `.code-workspace` 文件保存为收藏，一键在侧边栏切换不同的多项目工作区。
2. **Peep**
    * *作用*：如果你的 `.code-workspace` 文件放在项目根目录下，不想在左侧资源管理器看到它（因为它通常只在逻辑上存在），可以用 Peep 隐藏它，保持目录整洁。
3. **GitLens**
    * *作用*：完美支持多仓库视图，能清晰区分不同子项目的 Git 历史。

---

### 8. 性能优化 (Performance Tips)

如之前的问答所述，为了防止电脑卡顿：

* **排除不必要的文件**：
    在 `.code-workspace` 中配置：

    ```json
    "settings": {
        "search.exclude": { "**/node_modules": true, "**/dist": true },
        "files.watcherExclude": { "**/node_modules/**": true }
    }
    ```

* **按工作区禁用插件**：
    在插件面板，右键某插件 -> `Disable (Workspace)`。
  * *场景*：在写全栈项目时，把 C++ 插件禁用了，只保留 JS/Python 插件。

---

### 总结：什么时候该用它？

* ✅ **全栈开发**：前端 + 后端。
* ✅ **微服务**：Service A + Service B + Shared Library。
* ✅ **文档与代码**：Code Repo + Documentation Repo。
* ❌ **毫无关联的巨型项目**：建议分窗口打开，避免内存爆炸。
