# Claude Skill Manager (CSM) - Technical Specification

## 1. 项目背景与目标 (Background & Goals)

目前 Claude Code 的配置目录 `.claude` 通过软链接指向全局配置 (`~/.claude`)。为了支持 Agent Skills 的高效开发、调试与共享，我们需要一个管理工具来打通本地开发目录 `skills-dev/` 与全局生效目录 `.claude/skills/`。

**核心目标**:

- **开发与运行分离**: 在 `skills-dev` 中开发，按需发布到全局。
- **高效迭代**: 提供 Watch 模式，实现开发时的实时同步。
- **便捷管理**: 提供交互式界面进行安装、卸载、搜索和打包分享。

## 2. 核心流程 (Core Workflow)

```mermaid
graph TD
    A[skills-dev/MySkill] -->|Install/Update (Copy)| B[.claude/skills/MySkill]
    A -->|Watch (Real-time Copy)| B
    B -->|Uninstall (Delete)| C[Remove from Global]
    A -->|Export (Zip)| D[MySkill.zip]
    E[User Query] -->|Search| F[Filter List]
```

## 3. 功能性需求 (Functional Requirements)

### 3.1 技能列表与状态管理 (Skill List & Status)

- **扫描范围**:
  - Source: `skills-dev/*` (本地开发库)
  - Target: `.claude/skills/*` (全局已安装库)
- **状态定义**:
  - `Not Installed`: 仅在 Source 存在。
  - `Installed`: Source 和 Target 均存在，且内容一致（可选：通过 Hash 或时间戳判断，简化版可只判断存在性）。
  - `Orphaned`: 仅在 Target 存在（可能是非本项目管理的 Skill，脚本应标记但不主动删除，除非用户明确操作）。
- **展示信息**: Skill Name, Version (from SKILL.md), Status.

### 3.2 安装与更新 (Install & Update)

- **操作**: 将 `skills-dev/<skill-name>` 目录完整**复制**到 `.claude/skills/<skill-name>`。
- **覆盖策略**: 强制覆盖 (Force Copy)。
- **前置检查**: 检查 `SKILL.md` 是否存在，确保是合法的 Skill 目录。

### 3.3 实时开发模式 (Watch Mode)

- **功能**: 监听 `skills-dev/<skill-name>` 的文件变动。
- **行为**: 一旦检测到变动，自动执行 Copy 操作。
- **实现**: 优先使用 `watchexec` (如果可用)，否则回退到 PowerShell `FileSystemWatcher`。

### 3.4 搜索功能 (Search)

- **输入**: 关键词。
- **范围**: 匹配 Skill Name 或 Description (解析 SKILL.md)。
- **结果**: 实时过滤列表视图。

### 3.5 分享与打包 (Export)

- **功能**: 选择一个或多个 Skill，打包为 `.zip` 文件。
- **输出**: 默认输出到项目根目录或指定 `dist/` 目录。

## 4. 非功能性需求 (Non-functional Requirements)

- **兼容性**: PowerShell 7+ (跨平台)。
- **安全性**: 操作前确认 `.claude` 软链接有效性。
- **交互性**: 使用 Terminal GUI (TUI) 风格，如 `Out-GridView` (仅 Windows) 或 交互式文本菜单。考虑到兼容性，优先使用交互式文本菜单 + 颜色高亮。

## 5. 技术方案建议 (Technical Proposal)

### 5.1 脚本架构

- **语言**: PowerShell
- **路径**: `scripts/pwsh/Manage-ClaudeSkills.ps1`
- **核心函数**:
  - `Get-ClaudeSkill`: 获取所有 Skill 对象列表。
  - `Install-ClaudeSkill`: Copy-Item -Recurse -Force。
  - `Watch-ClaudeSkill`: 封装 FileSystemWatcher 或 watchexec。
  - `Compress-ClaudeSkill`: Compress-Archive。
  - `Show-Menu`: 主循环 UI。

### 5.2 目录结构假设

```text
ProjectRoot/
├── .claude/ -> ~/.claude (Symlink)
│   └── skills/
├── skills-dev/ (Source)
│   ├── my-skill-a/
│   └── my-skill-b/
└── scripts/
    └── pwsh/
        └── Manage-ClaudeSkills.ps1
```

## 6. 边缘情况与风险 (Edge Cases)

- **软链接断裂**: 如果 `.claude` 指向的路径不存在，脚本应报错并停止。
- **文件锁定**: Windows 下如果 Claude 正在读取文件，可能导致 Copy 失败。需添加 `try-catch` 重试机制。
- **命名冲突**: 确保 Source 和 Target 的文件夹名称一一对应。
