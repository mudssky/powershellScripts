# Claude Code Workflow & Hooks Cheatsheet

Workflow 功能允许你通过 Hooks（钩子）和自定义命令自动化开发流程，确保代码质量并增强智能体的自主性。

## 🪝 Hooks (自动化钩子)

Hooks 是在 Claude 执行特定动作（如使用工具、停止会话）前后自动运行的处理器。

### 1. 配置位置
通常在插件或项目的 `hooks/hooks.json` 中定义。

### 2. 核心事件类型
- **`PreToolUse`**: 在 Claude 调用工具（如 `Write`, `Edit`, `Bash`）**之前**触发。常用于安全检查或规范提示。
- **`PostToolUse`**: 在工具执行**之后**触发。常用于自动运行 Lint、格式化或测试。
- **`Stop`**: 当智能体认为任务完成并准备停止时触发。常用于最终质量验证。
- **`SubagentStop`**: 当子智能体任务结束时触发。

### 3. 钩子类型
- **`command`**: 执行 Bash 脚本或命令。适用于确定性的检查（如编译、测试）。
- **`prompt`**: 向 Claude 发送额外的系统指令。适用于基于逻辑的审查（如代码风格、架构一致性）。

### 4. 配置示例 (`hooks.json`)

```json
{
  "PreToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "prompt",
          "prompt": "在修改代码前，请确保符合项目命名规范：组件使用 PascalCase。",
          "timeout": 30
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "npm run lint -- --fix",
          "timeout": 60
        }
      ]
    }
  ],
  "Stop": [
    {
      "matcher": ".*",
      "hooks": [
        {
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/final-check.sh",
          "timeout": 45
        }
      ]
    }
  ]
}
```

## ⌨️ 自定义命令 (Slash Commands)

自定义命令允许你通过 `/` 触发预定义的一系列操作。

### 1. 定义方式
在 `commands/` 目录下创建 `.md` 文件。

### 2. 示例模板 (`commands/review.md`)

```markdown
---
description: 对当前更改进行代码审查
argument-hint: [file-path]
---

请审查 @$1 中的代码更改。
1. 检查潜在的逻辑漏洞。
2. 确保没有硬编码的敏感信息。
3. 运行项目测试套件以验证功能。
```

## 🔄 标准开发工作流 (Standard Workflow)

1. **Context Gathering**: Claude 阅读 `CLAUDE.md` 和项目结构。
2. **Plan**: Claude 提出修改计划。
3. **Execute**: 
   - `PreToolUse` 钩子运行（如提示规范）。
   - Claude 执行 `Edit`/`Write`。
   - `PostToolUse` 钩子运行（如自动 `prettier`）。
4. **Verify**: Claude 运行 `Bash` 命令执行测试。
5. **Final Check**: Claude 准备停止，`Stop` 钩子运行最终验证脚本。

## 💡 最佳实践

- **静默失败 vs 强制中断**: `command` 钩子如果返回非零退出码，会中断 Claude 的当前操作。
- **使用变量**: 在命令中使用 `${CLAUDE_PLUGIN_ROOT}` 引用插件根目录。
- **超时设置**: 始终设置 `timeout` 以防止挂起的脚本阻塞会话。
- **匹配器优化**: 使用精确的正则表达式作为 `matcher`（如 `Write|Edit` 而不是 `.*`），以减少不必要的资源消耗。
