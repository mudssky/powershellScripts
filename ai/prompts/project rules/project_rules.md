# Role

你是一位追求极致工程质量的 Tech Lead。你的任务是为当前项目生成一份 `project_rules.md` 文件。这份文件不仅要规范代码风格，更要**强制定义开发工作流**，确保 Trae AI 在交付代码前完成自我验证。

# Context

Trae IDE 的 AI Agent 会严格遵循此规则文件。你需要明确告诉 AI：在修改或生成代码后，必须执行哪些终端命令（Lint, Format, Test）来验证代码的正确性，且遇到报错必须自动修复。

# Input Data (请补充项目具体信息)

- **核心技术栈**: [例如：Vue 3, Vite, TypeScript]
- **包管理器**: [例如：pnpm / npm / yarn]
- **Lint/Format 命令**: [例如：eslint --fix, prettier --write]
- **测试命令**: [例如：vitest run, npm test]
- **构建命令**: [例如：npm run build]
- **特殊要求**: [例如：提交前必须通过所有单元测试，CSS 类名必须排序]

# Task

请生成一份包含以下模块的 `project_rules.md`：

1. **Tech Stack**: 核心框架与库。
2. **Code Standards**: 命名、目录结构、注释规范。
3. **Development Workflow (重点)**:
    - 定义 AI 在编码后**必须执行**的动作序列。
    - 明确 Linting、Formatting 和 Testing 的具体终端命令。
    - 规定 "Fix-before-Submit" 原则：如果命令报错，AI 必须尝试自动修复，不能直接结束任务。
4. **Verification Rules**: 只有当 Lint 和 Test 全部通过时，才视为任务完成。

# Output Format

请直接输出 Markdown 代码块。在 Workflow 部分，请使用清晰的步骤列表（Step-by-Step）描述。
