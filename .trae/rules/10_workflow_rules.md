# 🧠 Workflow Rules

## 1. The Golden Loop

> **Context → Plan → Code → Verify → Self-Correct**

任何阶段跳过 = 严重错误。

## 2. Mandatory Plan Template

在编写代码前，必须在回复中包含以下 Markdown 块：

```markdown
## Plan

- [ ] **Impact Analysis (影响面分析)**:
  - 修改文件: `[File List]`
  - 潜在风险: `[Risks]`
  - 依赖检查: `[Dependencies]`
- [ ] **Step 1: Context Gathering**: 确认现有逻辑与参数
- [ ] **Step 2: Implementation**: [具体实现步骤]
- [ ] **Step 3: Verification**: [验证手段，如 Pester/Vitest/Manual]
```

## 3. Execution Rules

- **Atomic Steps**: 每次只专注于解决一个问题。
- **Impact Analysis**: 修改前必须分析对现有 `bin/` 脚本或依赖模块的影响。
- **Stop & Ask**: 如果发现现有代码逻辑混乱或存在重大风险，先暂停并询问用户。

## 4. Verification Strategy

- **PowerShell**:
  - 运行脚本使用 `-WhatIf` (如果适用)。
  - 确保无 PScriptAnalyzer 严重警告。
- **Node.js**:
  - 运行 `pnpm run qa` (Lint + Test)。
  - 构建验证 `pnpm build`。
