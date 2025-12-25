# Claude Code Advanced Features: Subagents & Skills

本文档介绍了 Claude Code 的高级功能：**Subagents (子智能体)** 和 **Agent Skills (智能体技能)**。这些功能允许你创建更强大、更自主的 AI 工作流。

## 🤖 Subagents (子智能体)

子智能体是处理复杂、多步骤任务的自主子进程。它们拥有独立的系统提示词（System Prompt）和工具集，可以由主智能体根据任务需求自动唤起。

### 1. 核心概念

- **自主性**：独立处理任务，直到完成或需要帮助。
- **触发机制**：通过 YAML Frontmatter 中的 `description` 和示例触发。
- **隔离性**：拥有独立的上下文和工具权限。

### 2. 目录结构

通常位于项目或插件的 `agents/` 目录下：

```text
my-plugin/
└── agents/
    ├── bug-fixer.md
    └── code-reviewer.md
```

### 3. 定义格式 (`agents/*.md`)

每个 Agent 定义文件是一个 Markdown 文件，包含 YAML Frontmatter 和 System Prompt。

**示例：`agents/bug-fixer.md`**

```markdown
---
name: bug-fixer
description: 专注于修复代码中的 bug 和逻辑错误。
model: claude-3-5-sonnet-20241022
color: "#ff0000"
examples:
  - "修复 auth.ts 中的空指针异常"
  - "解决登录页面的状态同步问题"
---

# Bug Fixer Agent System Prompt

你是一个专业的 Bug 修复专家。你的目标是分析错误、定位根因并修复代码。

## 工作流程
1. **重现**：首先尝试编写测试用例重现 bug。
2. **分析**：阅读相关代码，理解逻辑。
3. **修复**：修改代码。
4. **验证**：运行测试确保修复有效且无回归。

## 规则
- 必须在修改前运行测试。
- 修改后必须再次运行测试。
```

### 4. 生命周期控制

- **SubagentStop Hook**: 可以定义 Hook 来拦截子智能体的停止行为，确保任务真正完成（例如强制要求所有测试通过）。

---

## 🧠 Agent Skills (智能体技能)

技能是模块化的知识包，用于扩展 Claude 的能力。它们就像是特定领域的"入职指南"，包含专业知识、工作流和工具。

### 1. 核心概念

- **模块化**：自包含的知识单元。
- **渐进式披露**：通过 `SKILL.md` 提供核心概念，详细内容放在 `references/` 中按需加载。
- **结构化**：包含文档、示例和脚本。

### 2. 目录结构

通常位于 `skills/` 目录下，每个技能一个子目录：

```text
my-plugin/
└── skills/
    └── database-migration/
        ├── SKILL.md          # 核心定义 (必须)
        ├── references/       # 详细参考文档
        │   └── schema-rules.md
        ├── examples/         # 示例用法
        │   └── migration-example.sql
        └── scripts/          # 辅助脚本
            └── verify-db.py
```

### 3. 定义格式 (`skills/*/SKILL.md`)

**示例：`skills/database-migration/SKILL.md`**

```markdown
---
name: database-migration
description: 当用户需要编写或执行数据库迁移脚本时使用此技能。
version: 1.0.0
---

# Database Migration Skill

本技能指导如何安全地进行数据库迁移。

## 核心原则
1. **向后兼容**：所有迁移必须保持向后兼容。
2. **事务性**：迁移脚本必须在事务中运行。
3. **可回滚**：必须提供 Down 脚本。

## 常用命令
- 创建迁移: `npm run migration:create`
- 执行迁移: `npm run migration:up`

## 参考资料
- [Schema 规范](references/schema-rules.md)
```

### 4. 如何使用 Skill (How to Use)

封装好 Skill 后，你可以在 Command (`.md`) 或 Agent 定义中通过自然语言引用它：

**Command 引用示例 (`commands/generate-docs.md`)**

```markdown
---
description: 生成 API 文档
argument-hint: [file-path]
---

请为 @$1 生成文档。
**使用 api-docs-standards skill 来确保文档格式正确且包含所有必要部分。**
```

### 5. 最佳实践

- **明确触发条件**：在 `description` 中使用第三人称清晰描述何时使用此技能（例如 "This skill should be used when..."）。
- **引用分离**：将长篇大论的文档放入 `references/`，保持 `SKILL.md` 精简（约 1500 词以内）。
- **提供示例**：在 `examples/` 目录提供具体的代码或命令示例。

---

## 🔌 插件架构与 MCP 集成 (Plugin & MCP Architecture)

在 Claude Code 中，封装 **Plugins**（插件）和 **Skills**（技能）是扩展其能力的核心方式。

### 1. Plugin (插件) 的标准封装结构

Claude Code 的插件是一个包含特定文件和目录结构的文件夹。最核心的是位于 `.claude-plugin/` 目录下的 `plugin.json` 描述文件。

一个完整的插件目录结构如下：

```text
my-plugin/
├── .claude-plugin/
│   └── plugin.json          # [必须] 插件的核心清单文件
├── commands/                # [可选] 存放 Slash 命令 (.md 文件)
├── agents/                  # [可选] 存放自定义 Agent 定义 (.md 文件)
├── skills/                  # [可选] 存放 Skills (每个 Skill 一个子目录)
│   └── my-skill/
│       ├── SKILL.md         # [必须] Skill 的核心定义
│       ├── references/      # [可选] 参考文档
│       ├── examples/        # [可选] 示例文件
│       └── scripts/         # [可选] 辅助脚本
├── hooks/                   # [可选] 事件钩子配置 (hooks.json)
├── .mcp.json                # [可选] MCP 服务器配置 (也可以写在 plugin.json 中)
└── scripts/                 # [可选] 插件通用的工具脚本
```

#### `plugin.json` 配置示例

这是插件的入口，定义了插件的元数据和组件路径：

```json
{
  "name": "my-awesome-plugin",
  "version": "1.0.0",
  "description": "一个用于演示封装结构的插件",
  "commands": "./commands",   // 指定命令目录
  "agents": "./agents",       // 指定 Agent 目录
  "skills": "./skills",       // 指定 Skill 目录（会自动扫描子目录）
  "mcpServers": "./.mcp.json" // 指定 MCP 配置文件
}
```

### 2. MCP (Model Context Protocol) 工具封装

如果你需要封装代码逻辑（如调用 API、数据库操作），则需要集成 MCP Server。

#### 方式 A：独立配置文件 (`.mcp.json`)

推荐用于复杂的配置。

```json
{
  "my-tools": {
    "command": "node",
    "args": ["${CLAUDE_PLUGIN_ROOT}/servers/index.js"],
    "env": {
      "API_KEY": "${MY_API_KEY}"
    }
  }
}
```

*注意：使用 `${CLAUDE_PLUGIN_ROOT}` 变量可以确保路径在不同机器上都能正确解析。*

#### 方式 B：内联配置 (`plugin.json`)

适合简单的插件。

```json
{
  "name": "my-plugin",
  "mcpServers": {
    "simple-tool": {
      "command": "python",
      "args": ["script.py"]
    }
  }
}
```

### 3. 开发工具与最佳实践

1. **快速创建**：
    使用 Claude Code 内置的脚手架命令可以快速生成标准结构：

    ```bash
    /plugin-dev:create-plugin
    ```

2. **本地测试**：
    在开发过程中，可以使用 `--plugin-dir` 参数加载本地插件进行测试：

    ```bash
    claude --plugin-dir /path/to/my-plugin
    ```

3. **权限控制**：
    在定义 Command 时，通过 `allowed-tools` 明确限制该命令能使用的工具，提高安全性：

    ```markdown
    ---
    allowed-tools: ["mcp__my-plugin__read_data", "Bash"]
    ---
    ```

---

## 🛠️ Agent SDK (程序化开发)

除了通过配置和 Markdown 定义 Agent，Claude Code 还提供了 **Agent SDK** (支持 Python 和 TypeScript)，允许你以编程方式构建复杂的 Agent 应用。

### 1. 快速开始

使用内置命令脚手架创建新项目：

```bash
/new-sdk-app my-agent-app
```

### 2. SDK 核心组件

- **Agent**: 定义智能体的核心逻辑和 System Prompt。
- **Tools**: 注册自定义工具函数。
- **Workflows**: 定义多步执行流程。

### 3. 自动验证

Claude Code 提供了验证 Agent 来确保你的 SDK 应用遵循最佳实践：

- **TypeScript**: `agent-sdk-verifier-ts`
- **Python**: `agent-sdk-verifier-py`

验证器会自动检查 SDK 版本兼容性、配置正确性以及错误处理模式。

---

## 🐙 Git 工作流集成 (Git Integration)

Claude Code 内置了强大的 Git 自动化插件 (`commit-commands`)，通过 Slash Commands 简化日常版本控制操作。

### 常用 Git 命令

| 命令 | 说明 |
|------|------|
| `/commit` | 自动分析暂存区更改，生成 Commit Message 并提交 |
| `/commit-push-pr` | 提交更改，推送到远程，并使用 `gh` CLI 创建 Pull Request |
| `/clean_gone` | 清理本地已合并或删除的废弃分支 |
| `/review` | (需插件) 读取 PR diff 并进行代码审查 |

**注意**：`/commit-push-pr` 和 PR 相关功能需要预先安装并登录 GitHub CLI (`gh`)。

---

## 🎨 输出风格 (Output Styles)

你可以通过插件或 Hook 改变 Claude 的输出风格，使其适应不同的使用场景。

### 常见风格插件

- **Explanatory Style (解释型)**: 适合教学或学习。Claude 会在编写代码前后提供详细的解释，分析实现选择和权衡。
- **Learning Style (学习型)**: 交互式学习模式。Claude 会在关键决策点暂停，引导用户思考或补全代码，而非直接给出答案。

### 实现原理

这些风格通常通过 **SessionStart Hook** 实现，在会话开始时向 System Prompt 注入特定的指令集。

```json
"hooks": {
  "SessionStart": [
    {
      "type": "prompt",
      "content": "你现在是教学模式。每写一段代码前，请先解释其背后的设计模式..."
    }
  ]
}
```
