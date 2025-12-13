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

4. **Execution Environment (执行环境)**
    - **PowerShell**: 默认使用 PowerShell 7 (`pwsh`)。所有脚本必须兼容跨平台 (Windows/Linux)。
    - **Node.js**: 使用 `pnpm` 管理依赖。Node.js 版本需支持 ESM。

## 🧠 Chain of Thought & Planning (思考与规划)

- 在编写任何代码前，必须在对话中输出以下计划块:

```markdown
## Plan
- [ ] **Impact Analysis (影响面分析)**:
    - 修改文件: `script.ps1`, `README.md`
    - 潜在风险: 可能会影响依赖该模块的 CI 流程
- [ ] **Step 1: Context Gathering**: 确认现有参数定义
- [ ] **Step 2: Implementation**: 重构参数解析逻辑
- [ ] **Step 3: Verification**: 运行 Pester 测试或 Vitest 测试确保无回归
```

## 🛠 Tech Stack & Coding Standards (技术与规范)

### 1. PowerShell Best Practices (核心规范)

- **Header & Shebang**:
  - 所有 `.ps1` 文件第一行必须是: `#!/usr/bin/env pwsh`
  - 必须包含 `[CmdletBinding(SupportsShouldProcess = $true)]`。
  - 必须配置环境: `Set-StrictMode -Version Latest` 和 `$ErrorActionPreference = 'Stop'`。

- **Structure**:
  - 主逻辑必须封装在 `Main` 函数中。
  - 使用 `try/catch/finally` 包裹主执行逻辑。
  - 示例结构:

    ```powershell
    #!/usr/bin/env pwsh
    <#
    .SYNOPSIS
        简短描述
    .DESCRIPTION
        详细描述
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Main {
        try {
            # 业务逻辑
        }
        catch {
            throw $_
        }
    }

    Main
    ```

- **Cross-Platform**:
  - **路径处理**: 严禁使用字符串拼接路径 (如 `"$root\bin"`), **必须** 使用 `Join-Path`。
  - **换行符**: 文件必须保存为 UTF-8 (No BOM)，换行符使用 LF。

### 2. Node.js/TypeScript Standards (scripts/node)

- **Architecture**:
  - 基于 **Rspack** 构建单文件应用。
  - 源码位于 `scripts/node/src/`。
  - 构建后会自动在项目根目录 `bin/` 生成对应的 Shim 脚本 (Windows `.cmd` 和 Linux Shell)。

- **Workflow**:
  - **新增脚本**: 仅需在 `scripts/node/src/` 下新建 `.ts` 文件，构建系统会自动识别并打包。
  - **构建命令**:
    - `pnpm build`: 生产构建 (压缩)。
    - `pnpm build:dev`: 开发构建 (不压缩)。
    - `pnpm build:standalone`: 独立构建 (复制 JS 到 bin)。

- **Testing**:
  - 使用 **Vitest** 进行单元测试和集成测试。
  - 运行测试: `pnpm test`。

### 3. PowerShell Script Management (scripts/pwsh)

- **Architecture**:
  - 脚本源码位于 `scripts/pwsh/` 下的各分类目录中。
  - 使用 `Manage-BinScripts.ps1` 工具管理脚本映射。
  - **Shim 生成**: `Manage-BinScripts.ps1 -Action sync` 会在 `bin/` 目录生成对应的 Shim 脚本，指向源码位置。
  - **Clean**: 使用 `Manage-BinScripts.ps1 -Action clean` 清理 `bin/` 目录中的 PowerShell 脚本映射。

- **Workflow**:
  - **新增脚本**: 在 `scripts/pwsh/` 相应分类下创建 `.ps1` 文件。
  - **同步**: 运行 `.\Manage-BinScripts.ps1 -Action sync` 更新 `bin/` 目录。
  - **安装**: `install.ps1` 会自动调用同步逻辑。

### 4. Naming Convention (命名规范)

- **PowerShell**:
  - Functions: `Verb-Noun` (e.g., `Get-SystemInfo`).
  - Files: `PascalCase.ps1` 或 `camelCase.ps1` (保持一致性)。
- **TypeScript**:
  - Files: `kebab-case.ts` (推荐) 或 `camelCase.ts`。
  - Variables: `camelCase`.

## 📖 Documentation & Commenting Standards (文档与注释规范)

### 1. DocStrings (文档注释)

- **PowerShell**: 必须包含 `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`。
- **TypeScript**: 导出函数必须包含 JSDoc (`@param`, `@returns`)。

### 2. "Why" over "What" (意图优先)

- ❌ 禁止: `// 循环遍历列表` (描述语法)
- ✅ 必须: `// 过滤掉未激活用户以防止计费错误` (描述业务意图)

### 3. TODOs (技术债务)

- 格式: `// TODO(User): [描述]` 或 `# TODO(User): [描述]`。

## 🛡️ Maintainability & Coding Principles (可维护性与架构)

### 1. Error Handling (错误处理)

- **PowerShell**: 使用 `ErrorAction = 'Stop'` 配合 `try/catch`。
- **TypeScript**: 所有 Promise 必须 handle rejection。

### 2. Boy Scout Rule (童子军法则)

- 修改现有代码时，如果你发现了显而易见的 Code Smell (如硬编码路径)，必须顺手修复它。

## ⚡ Development Workflow (严格执行流)

### Step 1: Context Gathering (上下文获取)

- 运行 `ls` 确认目录结构。
- 读取 `package.json` 或现有脚本确认逻辑。

### Step 2: Coding (原子化修改)

- 每次只专注于解决一个问题。

### Step 3: Self-Correction & Verification (自查与验证)

- **PowerShell**:
  - 确保无 PScriptAnalyzer 严重警告。
  - 运行脚本使用 `-WhatIf` (如果实现了 ShouldProcess) 进行验证。
- **TypeScript (Node)**:
  - 运行 `pnpm run qa` (包含类型检查、Lint 和测试)。
  - 如果修改了构建逻辑，必须运行 `pnpm build` 验证产物生成。

### Step 4: Documentation (文档更新)

- 更新脚本头部注释。
- 如果引入新功能，更新 `README.md`。

## 📂 Project Structure Guide

```text
root/
├── ai/                 # AI 相关配置 (Coding, Docs, MCP, Prompts)
├── bin/                # 自动生成的跨平台可执行脚本 (Shim)
├── config/             # 软件配置 (Docker, Git, Nginx, VSCode, Rust, etc.)
├── docs/               # 文档 & Cheatsheets (按技术栈分类: frontend, git, linux...)
├── linux/              # Linux 发行版特定配置 (Arch, Ubuntu, WSL2)
├── macos/              # macOS 特定配置 (Hammerspoon)
├── projects/           # 子项目目录
│   └── clis/           # TypeScript/Node.js CLI 工具 (e.g., json-diff-tool)
├── psutils/            # PowerShell 通用模块 (demo, docs, examples, modules)
├── scripts/            # 自动化脚本集合
│   ├── node/           # 新版统一 Node.js 脚本工程 (Rspack + TS)
│   └── pwsh/           # PowerShell 脚本 (devops, filesystem, media, network...)
├── templates/          # 模板文件
├── tests/              # 全局测试文件
├── install.ps1         # 项目入口安装脚本
└── README.md           # 项目总览
```
