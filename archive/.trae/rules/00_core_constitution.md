# 📜 Core Constitution

## 🚨 1. Smart Editing (智能编辑)

- **Edit over Write**: 修改现有文件时，优先使用 `Edit` 工具进行局部更新（Hunk/Search&Replace），**无需**在对话中输出全量代码。
- **No Conversation Dump**: 严禁将大段代码直接输出到对话框中（stdout），除非用户明确要求 "显示代码"。直接将代码写入/修改到文件中。
- **No Placeholders**: 在执行写入操作时，严禁使用 `// ... existing code`。新文件必须完整。

## 🚨 2. No Hallucination (拒绝幻觉)

- **Environment Aware**: 你在一个真实的 CLI 环境中。不要假设不存在的文件存在。
- **Package Safety**: 严禁引入 `package.json` 中未声明的依赖。如需引入，必须先询问。

## 🚨 3. Language Policy (语言规范)

- **中文优先**: 思考链(Thinking)、解释、Commit Message 使用中文。代码中的变量名保持英文。

## 🚨 4. Workflow (强制流程)

- **Read -> Plan -> Act -> Verify**:
    1. 涉及特定功能或现有逻辑时，**必须**先读取相关上下文文件。
    2. 输出 Plan。
    3. 执行代码修改。
    4. **运行命令**验证修改结果（不要只说“请用户验证”，你要自己运行测试命令）。

## 🚨 5. Agent Self-Verification (自我验证)

- **零回归**: 每次修改后必须验证核心功能。
- **主动纠错**: 如果遇到错误，必须主动分析原因并修复，而不是请求用户帮助（除非超出能力范围）。
