# Project Rules: PowerShell Scripts Automation

## 🚨 Critical Instructions (最高指令)

1. **No Laziness (拒绝懒惰)**
    - 严禁在代码块中使用 `// ... existing code`、`# ... rest of script` 或 `<!-- ... implementation -->`。
    - **必须** 输出完整、可运行的代码文件内容，即使只修改了一行。
    - 每一个脚本都必须是生产就绪的 (Production Ready)。

2. **No Hallucination (拒绝幻觉)**
    - 严禁引入 `package.json` 或当前环境中不存在的依赖/模块。
    - 如需引入新工具 (e.g., `jq`, `ffmpeg`) 或 PowerShell 模块，必须先请求用户许可，并提供安装指令。

3. **Language (语言规范)**
    - 除非用户明确要求使用英文，否则所有代码注释、文档、Commit Message 和对话解释 **必须使用中文**。

## 🧠 Chain of Thought & Planning (思考与规划)

- 在编写任何代码前，必须在对话中输出以下计划块:

```markdown
## plan
- [ ] **Impact Analysis (影响面分析)**:
    - 修改文件: `script.ps1`, `README.md`
    - 潜在风险: 可能会影响依赖该模块的 CI 流程
- [ ] **Step 1: Context Gathering**: 确认现有参数定义
- [ ] **Step 2: Implementation**: 重构参数解析逻辑
- [ ] **Step 3: Verification**: 运行 Pester 测试确保无回归
```

## 🛠 Tech Stack & Coding Standards (技术与规范)

### 1. Core Stack

- **PowerShell**: PowerShell 7+ (Core), 遵循 Windows/Linux 跨平台兼容性。
- **TypeScript (CLI Tools)**: Node.js (LTS), pnpm, Vitest.
- **Shell**: Bash (for Linux specific tasks).

### 2. Naming Convention (命名规范)

- **PowerShell Functions**: 严格遵循 `Verb-Noun` 格式 (e.g., `Get-SystemInfo`, `Install-App`).
  - Verbs 必须来自 `Get-Verb` 许可列表。
- **Variables**:
  - PowerShell: `PascalCase` (e.g., `$LogFilePath`).
  - TypeScript: `camelCase` (e.g., `const configPath`).
- **Files**:
  - Scripts: `camelCase.ps1` or `PascalCase.ps1` (保持与目录内现有风格一致).
  - Configs: `kebab-case` or standard tool naming (e.g., `docker-compose.yml`).

### 3. Preferred Patterns (推荐模式)

- **PowerShell**:
  - 使用 `[CmdletBinding()]` 和 `param()` 块。
  - 优先使用 `ErrorActionPreference = 'Stop'` 处理错误。
  - 使用 `PSCustomObject` 而不是哈希表返回结构化数据。
- **TypeScript**:
  - Early Returns (卫语句) 减少嵌套。
  - 使用 `zod` 或类似库进行运行时校验 (如果项目中已引入)。

### 4. Anti-patterns (禁止模式)

- **PowerShell**:
  - 禁止使用 `Write-Host` 输出数据 (仅用于 UI 提示)，数据流应使用 `Write-Output`。
  - 禁止硬编码绝对路径 (使用 `$PSScriptRoot` 或配置文件)。
- **TypeScript**:
  - 禁止使用 `any` 类型。
  - 禁止在生产代码中保留 `console.log`。

## ⚡ Development Workflow (严格执行流)

### Step 1: Context Gathering (上下文获取)

- **严禁盲写**。必须先运行 `ls` 确认目录结构，使用 `Read` 读取相关文件 (如 `package.json`, 现有脚本)。

### Step 2: Coding (原子化修改)

- 每次只专注于解决一个问题。
- 保持函数短小精悍 (单一职责原则)。

### Step 3: Self-Correction & Verification (自查与验证)

- **必须** 在代码修改后进行验证：
  - **PowerShell**: 运行 `PSScriptAnalyzer` (如果可用) 或简单的冒烟测试 (Dry Run).
    - `Invoke-ScriptAnalyzer -Path .\script.ps1`
  - **TypeScript**:
    - `pnpm run typecheck`
    - `pnpm run biome:check` (自动修复: `pnpm run biome:fixAll`)
    - `pnpm run test`
- 如果验证失败，必须自动尝试修复 (最多 3 次)，并在最终回复中报告修复过程。

### Step 4: Documentation (文档更新)

- 修改脚本参数后，必须更新脚本头部的 `.SYNOPSIS` 和 `.PARAMETER` 注释。
- 如果引入新功能，必须更新 `README.md`。

## 📝 Documentation & Maintenance

- **Commit Messages**: 遵循 Conventional Commits。
  - `feat: 新增视频压缩脚本`
  - `fix: 修复路径空格处理 bug`
  - `docs: 更新安装文档`
- **Dependencies**: 任何 `npm` 依赖变更必须同步更新 `package.json`。

## 📂 Project Structure Guide

```text
root/
├── clis/               # TypeScript/Node.js CLI 工具
│   └── json-diff-tool/ # JSON 差异对比工具
├── config/             # 各种软件的配置文件 (Docker, Git, VSCode...)
├── docs/               # 项目文档 & Cheatsheets
├── linux/              # Linux 专用脚本 (Ubuntu, Arch, WSL)
├── ai/                 # AI 相关配置 & Prompts
├── .vscode/            # VS Code 工作区设置
├── install.ps1         # 项目入口安装脚本
└── README.md           # 项目总览
```
