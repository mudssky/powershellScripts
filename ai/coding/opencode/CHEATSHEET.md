**OpenCode** 是一个开源的终端 AI 编程助手，类似于 Claude Code，但它不绑定特定供应商，支持 OpenAI、Anthropic (Claude)、Gemini、Ollama (本地模型) 等多种后端。

以下是一份 **OpenCode CheatSheet (速查表)**，涵盖安装、配置、常用命令和快捷键。

---

# 🚀 OpenCode Cheat Sheet

## 1. 安装 (Installation)

根据你的操作系统选择安装方式：

* **一键安装脚本 (Linux/macOS/WSL)**:

    ```bash
    curl -fsSL https://opencode.ai/install | bash
    ```

* **npm (全平台，需 Node.js)**:

    ```bash
    npm install -g opencode-ai
    ```

* **Homebrew (macOS/Linux)**:

    ```bash
    brew install opencode-ai/tap/opencode
    ```

* **Arch Linux (AUR)**:

    ```bash
    paru -S opencode-bin
    ```

---

## 2. 快速开始 (Getting Started)

### 初始化与连接

首次使用需要配置模型提供商（API Key）。

1. **启动 TUI 界面**:

    ```bash
    opencode
    ```

2. **连接模型提供商**:
    在 TUI 界面输入命令：

    ```text
    /connect
    ```

    * 选择提供商（如 `anthropic`, `openai`, `google` 等）。
    * 按提示输入 API Key（这是最安全的配置方式，Key 会被加密存储）。

3. **项目初始化**:
    进入你的代码仓库目录，运行：

    ```text
    /init
    ```

    * 这会扫描项目并生成 `AGENTS.md`（类似于 `.cursorrules`），帮助 AI 理解项目结构和规范。建议将此文件提交到 Git。

---

## 3. CLI 命令行参数 (Command Line Interface)

除了交互式 TUI，你也可以直接在命令行使用它：

| 命令 | 描述 | 示例 |
| :--- | :--- | :--- |
| `opencode` | 启动交互式终端界面 (TUI) | `opencode` |
| `opencode run "<prompt>"` | **非交互模式**执行任务 (适合脚本) | `opencode run "修复 main.go 中的编译错误"` |
| `opencode -c` / `--continue` | 继续上一次的会话 | `opencode -c` |
| `opencode -s <id>` | 恢复指定 ID 的会话 | `opencode -s 12345` |
| `opencode models` | 列出所有可用模型 | `opencode models` |
| `opencode auth login` | 登录/配置认证信息 | `opencode auth login` |
| `opencode agent list` | 列出可用的 AI 代理类型 | `opencode agent list` |

---

## 4. TUI 交互命令 (In-App Commands)

在 OpenCode 界面中输入 `/` 可触发命令：

| 命令 | 描述 |
| :--- | :--- |
| `/help` | 显示帮助菜单 |
| `/models` | **切换模型** (如从 GPT-4 切换到 Claude 3.5 Sonnet) |
| `/connect` | 添加/修改模型提供商 API Key |
| `/init` | 分析当前项目并创建 `AGENTS.md` |
| `/agent` | 切换代理模式 (Build/Plan) |
| `/clear` | 清空当前会话上下文 |
| `/copy` | 复制最后一条回复 |
| `/exit` 或 `/quit` | 退出程序 |
| `/reset` | 重置当前会话（清除上下文但保留设置） |

---

## 5. 快捷键 (Keyboard Shortcuts)

OpenCode 的 TUI 类似于 Vim 或 Tmux，使用 **Leader Key** (默认通常是 `Ctrl+x`) 组合操作。

| 快捷键 | 作用 |
| :--- | :--- |
| `Tab` | **切换 Agent 模式** (在 `Build` 和 `Plan` 之间切换) |
| `Ctrl + x` 然后 `n` | **新建会话** (New Session) |
| `Ctrl + x` 然后 `?` | 打开帮助/快捷键列表 |
| `Ctrl + c` | 中断当前生成 / 取消 |
| `Up / Down` | 浏览历史命令 |
| `PageUp / PageDn` | 滚动查看对话历史 |

> **提示**: `Plan` 模式下 AI 是**只读**的，只会给出建议不会修改代码；`Build` 模式是默认模式，可以执行写文件操作。

---

## 6. 高级配置 (Configuration)

### 配置文件位置

* **全局配置**: `~/.config/opencode/config.json` (或 `~/.opencode.json`)
* **项目配置**: 项目根目录下的 `opencode.json` (优先级更高)

### 配置示例 (`opencode.json`)

你可以在项目中定义固定的模型或自定义命令：

```json
{
  "model": "anthropic/claude-3-5-sonnet-20241022",
  "agent": {
    "build": {
      "temperature": 0.0
    }
  },
  "command": {
    "test": {
      "description": "运行测试",
      "prompt": "运行项目中的所有单元测试并修复失败的用例"
    }
  }
}
```

### 使用本地模型 (Ollama)

OpenCode 支持通过 OpenAI 兼容协议连接本地模型：

1. 启动 Ollama: `ollama serve`
2. 在 OpenCode 中运行 `/connect`。
3. 选择 `OpenAI Compatible` 或手动配置 URL 为 `http://localhost:11434/v1`。

---

## 7. 最佳实践 (Best Practices)

1. **使用 `/init`**: 任何新项目第一步都先运行 `/init`，让 AI 建立索引，能大幅提升回答准确率。
2. **善用 `Plan` 模式**: 在进行复杂重构前，按 `Tab` 切换到 `Plan` 模式，让 AI 先写出方案，确认无误后再切换回 `Build` 模式执行。
3. **特定文件提问**: 虽然它有 LSP 支持，但明确指出文件名通常效果更好，例如：`"修复 utils.ts 中的类型错误"`。
4. **非交互式管道**: 你可以将 opencode 集成到 shell 脚本中，例如：

    ```bash
    cat error.log | opencode run "分析这个日志并解释错误原因"
    ```

---

**对比 Claude Code 的核心优势：**

* **开源免费**: 工具本身免费，Token 费用直付给 API 提供商。
* **多模型**: 没钱可以用 Gemini Flash 或 本地模型；追求质量可以用 Claude 3.5 Sonnet。
* **隐私**: 代码不经过中间商服务器。
