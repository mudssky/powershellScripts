# Shared Config Resolver Spec

> 本规范记录 `psutils/src/config` 的配置读取契约。任何 PowerShell 脚本需要读取 env、JSON、`.psd1`、Markdown frontmatter 或 CLI 覆盖参数时，应优先复用这里的 source-first 配置解析器。

## Scenario: Unified PowerShell Config Sources

### 1. Scope / Trigger

- Trigger: 修改 `psutils/src/config/**`、`psutils/modules/config.psm1`、`psutils/tests/config.Tests.ps1`，或为脚本新增通用配置文件读取能力。
- Scope: `psutils/src/config` 是配置来源解析的源码真相；`psutils/modules/config.psm1` 只负责 dot-source 这些文件并导出公共函数。
- Design intent: 让独立脚本、模块和可打包 CLI 共享同一套配置来源语义，避免每个脚本各自实现 dotenv、JSON、frontmatter 或 CLI 参数合并。

### 2. Signatures

- Module import:
  - `Import-Module ./psutils/modules/config.psm1 -Force`
- Config merge:
  - `Resolve-ConfigSources -Sources <hashtable[]> [-BasePath <string>] [-IncludeTrace] [-ErrorOnMissing]`
  - `Resolve-ConfigSources -ConfigFile <string[]> [-BasePath <string>] [-IncludeTrace] [-ErrorOnMissing]`
- Source readers:
  - `Read-ConfigEnvFile -Path <string>`
  - `Read-ConfigPowerShellDataFile -Path <string>`
  - `Read-ConfigMarkdownFrontMatter -Path <string>`
- Conversion helpers:
  - `ConvertTo-ConfigHashtable -InputObject <object>`
  - `Get-ConfigValue -Values <hashtable> -Name <string> [-DefaultValue <object>]`
  - `ConvertTo-ConfigKeyName -Name <string>`
  - `ConvertFrom-ConfigCliParameters -Parameters <hashtable> [-ExcludeKeys <string[]>]`
- Scoped env:
  - `Invoke-WithScopedEnvironment -Variables <hashtable> -ScriptBlock <scriptblock>`

### 3. Contracts

- Supported source types are `Hashtable`、`ProcessEnv`、`EnvFile`、`JsonFile`、`PowerShellDataFile`、`MarkdownFrontMatter` and `CliParameters`.
- `Resolve-ConfigSources` merges sources in declaration order; later sources overwrite earlier values.
- `-ConfigFile` treats `.json` paths as `JsonFile` and all other paths as `EnvFile`.
- Without `-Sources` or `-ConfigFile`, `Resolve-ConfigSources -BasePath <dir>` auto-discovers `.env` then `.env.local` under the base path.
- `Resolve-DefaultEnvFiles -PrimaryBasePath <dir> -FallbackBasePath <dir>` only falls back when the primary directory has no default env file at all.
- `CliParameters` converts explicit PowerShell parameters to snake_case keys and skips `$null`、empty strings and `ExcludeKeys`.
- `MarkdownFrontMatter` returns parsed metadata plus `__content` for the Markdown body.
- `Get-ConfigValue` performs shallow case-insensitive lookup only; it must not expand paths, environment variables, nested paths, or normalize key names.
- Missing file sources return an empty table by default; `-ErrorOnMissing` changes that to `配置文件不存在: <path>`.
- `Invoke-WithScopedEnvironment` must restore overwritten variables and remove newly created variables even when the script block throws.
- `psutils/modules/config.psm1` must export public resolver functions and must not contain a second implementation of the parser.

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| Env file contains a non-empty, non-comment line without `=` | Throw `无效 env 行` |
| `MarkdownFrontMatter` line is not `key: value` | Throw with file path and line number |
| Markdown frontmatter starts with `---` but has no closing marker | Throw `Markdown frontmatter 缺少结束标记` |
| Missing file source without `-ErrorOnMissing` | Return empty values for that source |
| Missing file source with `-ErrorOnMissing` | Throw `配置文件不存在: <path>` |
| Unknown source `Type` | Throw `不支持的配置来源类型` |
| CLI parameter value is `$null` or whitespace | Omit it from merged config |

### 5. Good/Base/Bad Cases

- Good: `scripts/pwsh/ai/agent-runner/core/config.ps1` merges defaults, prompt preset metadata and CLI parameters through `Resolve-ConfigSources`.
- Good: `scripts/pwsh/ai/agent-runner/core/prompt.ps1` reads preset frontmatter through `Read-ConfigMarkdownFrontMatter`.
- Good: `scripts/pwsh/devops/postgresql/core/context.ps1` uses `Resolve-DefaultEnvFiles` and `Resolve-ConfigSources` for PostgreSQL env defaults.
- Base: `scripts/pwsh/download/Install-GitHubCli.ps1` imports `psutils/modules/config.psm1` and uses `JsonFile` plus `CliParameters` sources.
- Bad: Add a new `Read-EnvFile` helper inside a script when `Read-ConfigEnvFile` already covers strict dotenv parsing.
- Bad: Parse `.md` preset frontmatter with ad hoc regex in a feature script instead of using `Read-ConfigMarkdownFrontMatter`.

### 6. Tests Required

- `psutils/tests/config.Tests.ps1` must cover source order override and `Sources` winner tracking.
- Env file tests must assert `.env.local` overrides `.env` and invalid dotenv lines throw.
- JSON and `.psd1` tests must assert values are converted to plain hashtables.
- Markdown tests must assert metadata types, `__content`, and file/line-number parse errors.
- CLI parameter tests must assert snake_case conversion, empty-value skipping and `ExcludeKeys`.
- Scoped environment tests must assert restoration on success and on exception.
- When a downstream script adopts the resolver, add focused Pester tests around the script's source order and validation behavior, not around `psutils` internals.

### 7. Wrong vs Correct

#### Wrong

```powershell
function Read-LocalEnvFile {
    param([string]$Path)
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $parts = $line -split '=', 2
        $values[$parts[0]] = $parts[1]
    }
    return $values
}
```

问题：重复实现会和共享解析器在非法行、缺失文件、覆盖顺序和测试覆盖上漂移。

#### Correct

```powershell
Import-Module (Join-Path $repoRoot 'psutils/modules/config.psm1') -Force

$config = Resolve-ConfigSources -Sources @(
    @{ Type = 'Hashtable'; Name = 'Defaults'; Data = @{ retry_count = 3 } }
    @{ Type = 'EnvFile'; Name = '.env'; Path = '.env' }
    @{ Type = 'CliParameters'; Name = 'Cli'; Data = $PSBoundParameters; ExcludeKeys = @('Verbose') }
) -BasePath $workingDirectory -ErrorOnMissing
```

理由：调用方只声明配置来源和优先级，解析、错误语义、键名规范化和测试契约都由 `psutils/src/config` 维护。
