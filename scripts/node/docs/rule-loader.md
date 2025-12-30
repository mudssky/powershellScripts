# AI 编码规则加载器 (Rule Loader)

`rule-loader` 是一个专门为 AI 编码工具（如 Trae、Claude Code）设计的规则加载器 CLI 工具。它负责读取项目中的规则文件（`.trae/rules/*.md`），解析其元数据，并以 AI 友好的格式输出。

## 功能特性

* **智能解析**: 自动识别 Trae 风格的 Markdown 规则文件，支持解析 Frontmatter 元数据。
* **多格式输出**: 支持 Markdown（默认，适合 LLM 阅读）和 JSON（适合程序处理）格式。
* **灵活过滤**: 支持按 `alwaysApply` 属性过滤规则。
* **Glob 支持**: 正确处理 `globs` 字段，支持数组和逗号分隔字符串。

## 安装与构建

本工具是 `scripts/node` 工程的一部分。

```bash
# 进入 Node 脚本目录
cd scripts/node

# 构建工具 (生成 bin/rule-loader)
pnpm build
```

构建完成后，可执行文件位于项目根目录 `bin/rule-loader`。

## 使用方法

### 基础用法

```bash
# 加载所有规则并以 Markdown 格式输出
rule-loader
```

### 命令行选项

| 选项 | 缩写 | 描述 | 默认值 |
| :--- | :--- | :--- | :--- |
| `--format <type>` | `-f` | 输出格式 (`markdown`, `json`) | `markdown` |
| `--filter-apply` | | 只显示 `alwaysApply: true` 的规则 | `false` |
| `--verbose` | `-v` | 显示详细日志 | `false` |
| `--help` | `-h` | 显示帮助信息 | |

### 常见场景

**1. 为 AI 会话加载所有规则**

这是最常用的模式，输出包含所有强制规则的完整内容和条件规则的索引。

```bash
rule-loader
```

**2. 仅查看全局强制规则**

如果你只想看必须遵守的 Core Rules：

```bash
rule-loader --filter-apply
```

**3. 程序化集成**

如果你需要通过脚本处理规则数据：

```bash
rule-loader --format json
```

## 在 Claude Code 中使用

为了让 Claude Code CLI 在启动时自动加载这些规则，你可以在 `.claude/settings.json` 中配置 `hooks`。

### 配置示例

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "echo '以下是本项目的重要规范，请严格遵守:' && rule-loader"
          }
        ]
      }
    ]
  }
}
```

### 注意事项 (Windows)

如果 `rule-loader` 没有在你的系统路径中，建议使用 `pwsh -c rule-loader` 或提供完整路径。

## 规则文件格式

工具期望规则文件位于 `.trae/rules/` 目录下，并遵循以下 Frontmatter 格式：

```markdown
---
alwaysApply: false        # 是否总是加载完整内容 (默认为 true)
globs: "*.js, *.ts"       # 匹配的文件模式 (逗号分隔或数组)
description: "规则描述"    # 可选描述
---

# 规则标题

规则正文...
```

* **alwaysApply**:
  * `true` (默认): 规则内容会被完整输出到 Context 中。
  * `false`: 仅输出规则的索引信息（文件名、匹配模式、触发条件），AI 需要使用 `Read` 工具按需读取。
* **globs**: 定义规则适用的文件类型。

## 规则转换 (Rule Conversion)

`rule-loader` 支持将 Trae 格式的规则转换为其他 AI 代理（如 Antigravity）支持的格式。

### 使用方法

```bash
rule-loader convert [options]
```

### 选项

| 选项 | 缩写 | 描述 | 默认值 |
| :--- | :--- | :--- | :--- |
| `--target <type>` | `-t` | 目标格式 (`antigravity`) | `antigravity` |
| `--output <dir>` | `-o` | 输出目录 (默认根据目标格式自动决定) | |
| `--source <dir>` | `-s` | 源规则目录 | `.trae/rules` |

### Antigravity 转换说明

默认输出目录: `.agent/rules`

**映射规则**:

| Trae (`.trae/rules`) | Antigravity (`.agent/rules`) | 说明 |
| :--- | :--- | :--- |
| `alwaysApply: true` (且无 `globs`) | `trigger: always_on` | 全局强制规则 |
| `alwaysApply: true` (且有 `globs`) | `trigger: glob` | 文件匹配时自动加载 |
| `alwaysApply: false` | `trigger: manual` | 需手动读取 |
| `globs` | `globs` | 保持不变 |
| `description` | `description` | 保持不变 |

**示例**:

```bash
# 转换当前项目的 Trae 规则到 Antigravity 格式
rule-loader convert

# 指定输出目录
rule-loader convert --output ./custom-rules
```

## 开发说明

源码位于 `scripts/node/src/rule-loader/`。

* `index.ts`: 入口文件
* `cli.ts`: Commander 配置
* `loader.ts`: 规则加载逻辑
* `formatters.ts`: 输出格式化
