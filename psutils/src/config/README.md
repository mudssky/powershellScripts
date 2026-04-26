# psutils 配置解析器

这个目录存放 source-first 的配置解析实现。`psutils/modules/config.psm1` 会 dot-source 这些文件并导出公共函数。

## Source 类型

- `Hashtable`：直接传入键值表。
- `ProcessEnv`：读取当前进程环境变量。
- `EnvFile`：读取严格 `KEY=VALUE` 格式文件。
- `JsonFile`：读取 JSON 文件。
- `PowerShellDataFile`：读取 `.psd1` data file。
- `MarkdownFrontMatter`：读取 Markdown 文件开头的简单 frontmatter，并把正文保存到 `__content`。
- `CliParameters`：把 `$PSBoundParameters` 转成下划线风格配置键。

## 优先级

`Resolve-ConfigSources` 按传入顺序合并 source，后出现的值覆盖先出现的值。推荐顺序是：

```powershell
Resolve-ConfigSources -Sources @(
    @{ Type = 'Hashtable'; Name = 'Defaults'; Data = @{ agent = 'codex' } }
    @{ Type = 'MarkdownFrontMatter'; Name = 'Preset'; Path = './prompts/commit.md' }
    @{ Type = 'CliParameters'; Name = 'Cli'; Data = $PSBoundParameters }
)
```

## Markdown frontmatter

第一版支持简单键值：

```markdown
---
agent: codex
reasoning_effort: medium
json: false
---

正文内容
```

不支持嵌套对象、数组和多行 YAML 值。解析失败时会报告文件路径与行号。

## 新增 Source 类型

新增 source 时需要：

1. 在 `reader.ps1` 或合适文件中实现读取函数。
2. 在 `Read-ConfigSourceValues` 的 switch 中添加分支。
3. 为正常路径、缺失文件和非法格式补充 Pester 测试。
4. 如需公共复用，在 `psutils/modules/config.psm1` 和 `psutils/psutils.psd1` 中导出函数。
