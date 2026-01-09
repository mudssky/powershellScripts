# Claude Code Subagent Cheatsheet

Subagent 是处理复杂、多步骤任务的自主子进程。它们拥有独立的系统提示词（System Prompt）和工具集，可以由主智能体根据任务需求自动唤起。

## 📂 目录结构 (Standard Structure)

Subagent 定义文件通常位于插件或项目的 `agents/` 目录下。

```text
agents/
├── <agent-name>.md       # Subagent 定义文件
└── ...
```

## 📝 Subagent 定义模板 (Markdown + YAML)

每个 Subagent 是一个包含 YAML Frontmatter 和 Markdown Body 的文件。

```markdown
---
name: <unique-agent-name>
description: |
  当 [触发条件] 时使用此智能体。
  例如：
  <example>
  Context: [场景描述]
  user: "[用户请求]"
  assistant: "我会使用 <agent-name> 来处理此任务。"
  <commentary>
  [为什么触发此智能体的说明]
  </commentary>
  </example>
model: inherit  # 使用主智能体的模型配置，或指定具体模型
color: "#7B61FF" # 在终端显示的颜色标识
tools: ["Read", "Write", "Grep"] # [可选] 限制此智能体可用的工具
---

# <Agent Name> System Prompt

你是一个专攻 [特定领域] 的专家。你的目标是 [任务目标]。

## 核心职责 (Core Responsibilities)
1. 职责一
2. 职责二

## 工作流程 (Workflow)
1. 第一步：分析上下文
2. 第二步：执行操作
3. 第三步：验证结果

## 规则 (Rules)
- 始终保持 X 规范
- 禁止执行 Y 操作
```

## 🧠 核心字段说明 (Key Fields)

| 字段 | 必填 | 说明 |
| :--- | :--- | :--- |
| `name` | 是 | 智能体的唯一标识符。 |
| `description` | 是 | **最关键字段**。Claude 通过此字段决定何时唤起该智能体。必须包含 `<example>` 块。 |
| `model` | 是 | 建议设为 `inherit`。也可以指定如 `claude-3-5-sonnet-latest`。 |
| `color` | 是 | 用于区分不同智能体在终端的输出。 |
| `tools` | 否 | 定义子智能体可以访问的工具列表。若不指定，默认继承权限。 |

## 🚀 触发机制 (Triggering)

Subagent 的触发是**自动化**的：
1. **意图匹配**：主智能体根据用户请求，对比所有可用 Agent 的 `description`。
2. **上下文隔离**：一旦触发，子智能体会在独立的上下文窗口中运行，直到任务完成。
3. **结果回传**：任务结束后，子智能体会将摘要或结果返回给主智能体。

## 💡 编写最佳实践 (Best Practices)

- **精确的示例**：在 `description` 中提供 2-3 个高质量的 `<example>` 块，涵盖正向和负向触发场景。
- **角色定位清晰**：在 System Prompt 中给智能体一个明确的身份（如 "Security Auditor" 或 "Performance Optimizer"）。
- **限制工具范围**：通过 `tools` 字段实施最小权限原则，防止子智能体执行不相关的操作。
- **强制验证**：在 Workflow 中明确要求子智能体在完成任务前运行测试或验证脚本。

## ✅ 快速创建清单 (Checklist)

1. [ ] 在 `agents/` 目录下创建 `.md` 文件
2. [ ] 填写 `name` 和 `color`
3. [ ] 编写包含 `<example>` 的 `description`
4. [ ] 定义清晰的 System Prompt 和 Workflow
5. [ ] (可选) 限制 `tools` 权限
