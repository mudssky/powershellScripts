# Claude Code Agent Skill Cheatsheet

Agent Skill 是 Claude Code 的模块化知识包，用于为 Claude 提供特定领域的专业知识、工作流指导和工具参考。

## 📂 目录结构 (Standard Structure)

Skill 必须位于插件或项目的 `skills/` 目录下，每个 Skill 拥有独立的子目录。

```text
skills/
└── <skill-name>/
    ├── SKILL.md          # [必须] 核心定义文件
    ├── references/       # [可选] 详细参考文档 (.md)
    ├── examples/         # [可选] 代码或用法示例
    └── scripts/          # [可选] 辅助脚本
```

## 📝 SKILL.md 模板 (Core Definition)

`SKILL.md` 是 Skill 的灵魂，包含元数据和核心指令。

```markdown
---
name: <unique-skill-name>
description: <何时使用此技能的清晰描述，建议使用第三人称，例如 "This skill should be used when...">
version: 1.0.0
---

# <Skill Name> 指南

## 🎯 核心原则 (Core Principles)
- 简明扼要地列出该领域的核心规则。
- 强调安全性、性能或规范要求。

## 🛠 常用工作流 (Common Workflows)
1. 第一步：执行某项检查。
2. 第二步：调用相关工具。
3. 第三步：验证结果。

## ⌨️ 推荐命令 (Recommended Commands)
- `npm run lint`: 检查代码规范
- `pytest`: 运行测试用例

## 📚 参考资料 (References)
- [规范详情](references/spec.md)
```

## 🚀 触发与调用 (How to Invoke)

Skill 不需要手动加载，Claude 会根据 `description` 自动发现或通过自然语言显式引导。

### 1. 自动触发 (Auto-discovery)
Claude 会扫描所有 `SKILL.md` 的 `description` 字段。当用户的请求与描述匹配时，Claude 会自动加载该 Skill 的上下文。

### 2. 显式引用 (Explicit Reference)
在 Command 或 Prompt 中使用 `@` 或直接指名引用：

```markdown
请使用 **database-migration** skill 来生成这次的迁移脚本。
```

## 💡 编写最佳实践 (Best Practices)

- **原子化**: 一个 Skill 只负责一个特定的领域或任务。
- **渐进式披露 (Progressive Disclosure)**:
    - 保持 `SKILL.md` 精简（建议 1500 词以内）。
    - 将详细的 API 文档、长篇规范放入 `references/`。
- **清晰的 Description**: 描述应聚焦于"任务场景"，而不是"功能列表"。
- **提供示例**: 在 `examples/` 目录下提供具体的 `before/after` 代码，帮助 Claude 理解预期输出。

## ✅ 快速创建清单 (Checklist)

1. [ ] 创建目录 `skills/my-new-skill/`
2. [ ] 编写 `SKILL.md` 并包含 YAML Frontmatter
3. [ ] 检查 `description` 是否清晰、具有辨识度
4. [ ] (可选) 在 `references/` 放入详细文档
5. [ ] (可选) 在 `examples/` 放入代码示例
