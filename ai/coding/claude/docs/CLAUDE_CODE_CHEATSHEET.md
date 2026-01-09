# Claude Code Cheatsheet & Best Practices

这份清单总结了 Claude Code 的核心概念、配置最佳实践以及常用命令，帮助你高效使用 Claude Code 进行开发。

## 🚀 快速开始 (Quick Start)

### 启动

在项目根目录下运行：

```bash
claude
```

### 单次命令模式

不进入交互模式，直接执行任务：

```bash
claude -p "检查当前目录下的未提交更改并总结"
```

## ⚙️ 配置最佳实践 (Configuration)

Claude Code 支持三级配置，优先级从高到低：**Enterprise > User > Project > Env Vars**。

### 1. 项目级配置 (`.claude/settings.json`)

*提交到 Git，用于统一团队规范*

```json
{
  "permissions": {
    "allow": [
      "Read(**/*.{ts,tsx,js,jsx,json,md})",
      "Bash(npm run test)",
      "Bash(npm run lint)"
    ],
    "deny": [
      "Read(.env)",
      "Bash(rm -rf *)"
    ]
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true
  }
}
```

### 2. 用户级配置 (`~/.claude/settings.json`)

*个人偏好，不提交 Git*

```json
{
  "permissions": {
    "permissionMode": "acceptEdits" // 自动接受编辑，减少确认次数
  },
  "statusLine": {
    "enabled": true
  }
}
```

### 3. 环境变量 (Environment Variables)

*用于 CI/CD 或临时覆盖*

- `ANTHROPIC_API_KEY`: API 密钥
- `ANTHROPIC_DEFAULT_SONNET_MODEL`: 指定模型版本 (e.g., `claude-sonnet-4-5`)
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`: 禁用非必要流量 (隐私模式)
- `NO_PROXY`: 绕过代理设置

---

## 🧠 核心记忆文件 (`CLAUDE.md`)

在项目根目录创建 `CLAUDE.md`，这是 Claude 的"长期记忆"。**这是最重要的最佳实践之一。**

**推荐结构：**

```markdown
# 项目名称指南

## 🛠 技术栈
- **Framework**: Next.js 14 (App Router)
- **State**: Zustand
- **Style**: Tailwind CSS

## 📏 代码规范
- 组件命名使用 PascalCase (e.g., `UserProfile.tsx`)
- 所有的异步操作必须使用 try/catch 处理错误
- 禁止使用 `any`，必须定义完整 TypeScript 接口

## 🏗 构建与部署
- Build: `npm run build`
- Test: `npm run test`
- Lint: `npm run lint`

## 📂 目录结构
- src/components: 通用 UI 组件
- src/features: 业务功能模块
```

---

## ⌨️ 常用命令 (CLI & Slash Commands)

在 Claude Code 交互会话中使用的指令：

| 命令 | 说明 |
|------|------|
| `/help` | 查看帮助信息 |
| `/clear` | 清除当前会话上下文 (Reset context) |
| `/compact` | 压缩会话历史以节省 Token |
| `/config` | 查看当前生效的配置 |
| `/doctor` | 检查环境健康状态 (Installation health check) |
| `/bug` | 报告 Claude Code 的 Bug |
| `/init` | 初始化当前目录 (创建配置文件等) |
| `/cost` | 查看当前会话的 Token 消耗与成本 |

---

## 🔌 MCP (Model Context Protocol) 集成

通过 MCP 扩展 Claude 的能力（如访问数据库、GitHub、文件系统等）。

**配置示例 (`.claude/settings.json`):**

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-github"]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "C:\\projects"]
    }
  }
}
```

## 🪝 Hooks (自动化钩子)

> 💡 **速查表**: [Workflow & Hooks Cheatsheet](./CLAUDE_CODE_WORKFLOW_CHEATSHEET.md)

在工具执行前后自动运行命令，用于增强安全性或自动化流程。

**示例：修改代码后自动 Lint**

```json
"hooks": {
  "PostToolUse": [
    {
      "matcher": "Edit(**/*.ts)",
      "hooks": [
        {
          "type": "command",
          "command": "npm run lint -- --fix"
        }
      ]
    }
  ]
}
```

## 🛡️ 安全建议

1. **`.env` 保护**: 始终在 `settings.json` 的 `deny` 列表中包含 `.env` 文件。
2. **沙箱模式**: 尽量启用 `sandbox: { "enabled": true }` 以隔离执行环境。
3. **最小权限**: 仅授予必要的目录读写权限，避免使用通配符 `*` 授权根目录写权限。

---

## 🚀 高级功能 (Advanced Features)

Claude Code 支持通过 **Subagents** 和 **Skills** 扩展能力。

- **Subagents (子智能体)**: 自主的子进程，用于处理复杂任务。
- **Agent Skills (技能)**: 模块化的领域知识包。
- **Agent SDK**: 使用 Python/TS 编程构建自定义 Agent。
- **Git Integration**: 内置的智能提交和 PR 工作流。

👉 **详细文档请参考**: [Advanced Features](./CLAUDE_CODE_ADVANCED_FEATURES.md) | [Agent Skill](./CLAUDE_CODE_AGENT_SKILL_CHEATSHEET.md) | [Subagent](./CLAUDE_CODE_SUB_AGENT_CHEATSHEET.md) | [Workflow](./CLAUDE_CODE_WORKFLOW_CHEATSHEET.md)
