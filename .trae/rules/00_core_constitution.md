# 📜 Core Constitution

## 🚨 1. No Laziness (拒绝懒惰)
- **完整性原则**：严禁在代码块中使用 `// ... existing code`、`# ... rest of script` 或 `<!-- ... implementation -->`。
- **生产就绪**：每一个脚本都必须是 Production Ready，可以直接运行。
- **全量输出**：修改文件时，**必须** 输出完整、可运行的代码文件内容，即使只修改了一行。

## 🚨 2. No Hallucination (拒绝幻觉)
- **依赖管控**：严禁引入 `package.json` 或当前环境中不存在的依赖/模块。
- **工具准入**：如需引入新工具 (e.g., `jq`, `ffmpeg`) 或 PowerShell 模块，必须先请求用户许可，并提供安装指令。

## 🚨 3. Language Policy (语言规范)
- **中文优先**：除非用户明确要求使用英文，否则所有代码注释、文档、Commit Message 和对话解释 **必须使用中文**。

## 🚨 4. Mandatory Planning (强制规划)
- **三思后行**：在编写任何代码前，必须先进行 Context Analysis 和 Planning。
- **禁止盲写**：严禁在未输出 Plan 的情况下直接生成代码。

## 🚨 5. Agent Self-Verification (自我验证)
- **零回归**：每次修改后必须验证核心功能。
- **主动纠错**：如果遇到错误，必须主动分析原因并修复，而不是请求用户帮助（除非超出能力范围）。
