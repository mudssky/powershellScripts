# PowerShell Script Config Loading Spec

> 本规范记录 `scripts/pwsh/**` 独立脚本如何加载配置。默认路径是通过 `psutils/modules/config.psm1` 复用 `psutils/src/config`，不要为每个脚本新增自己的 env/JSON/frontmatter parser。

## Scenario: Script Config Loading via psutils

### 1. Scope / Trigger

- Trigger: 修改 `scripts/pwsh/**` 中读取 `.env`、`.env.local`、JSON、`.psd1`、Markdown preset、`$PSBoundParameters` 或临时环境变量的逻辑。
- Scope: 独立脚本负责声明配置来源、优先级和业务字段校验；底层文件读取、键名转换、来源合并和临时 env 作用域由 `psutils/src/config` 提供。
- Design intent: 让 `start-container`、GitHub CLI 下载器、AI agent runner 和 PostgreSQL toolkit 使用一致的配置加载语义。

### 2. Signatures

- Load shared parser:
  - `Import-Module (Join-Path $repoRoot 'psutils/modules/config.psm1') -Force`
- Merge sources:
  - `Resolve-ConfigSources -Sources <hashtable[]> -BasePath <dir> [-IncludeTrace] [-ErrorOnMissing]`
- Read prompt preset:
  - `Read-ConfigMarkdownFrontMatter -Path <preset.md>`
- Apply temporary compose/env variables:
  - `Invoke-WithScopedEnvironment -Variables <hashtable> -ScriptBlock <scriptblock>`
- Common source order:
  - defaults -> process env or config files -> local override file -> CLI/env hashtable

### 3. Contracts

- New script config readers must prefer `Resolve-ConfigSources` over direct `Get-Content | ConvertFrom-Json` or custom dotenv parsing.
- Scripts may keep business-specific normalization helpers, such as platform path expansion or case-insensitive nested JSON lookup, but the top-level source loading should still come from `Resolve-ConfigSources`.
- CLI overrides should use `CliParameters` and `ExcludeKeys` for control parameters that are not configuration values.
- Secrets or process-wide env values passed to child commands should use `Invoke-WithScopedEnvironment` so the caller's session is restored after success or failure.
- If a script must be distributed as one file, the build step may inline the required `psutils/src/config` function closure. The editable source must still import or reference the shared implementation instead of maintaining a hand-written copy.
- Existing generated bundle example: `scripts/pwsh/devops/Postgres-Toolkit.ps1` contains shared config functions generated from `scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1`; modify the source/build pipeline, not only the bundle.
- Narrow format-specific parsers are allowed only when the target file is not a general config source, such as constrained Docker Compose YAML block extraction in `start-container.ps1`.

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| New script adds `.env` support | Use `EnvFile` or `Resolve-DefaultEnvFiles`; invalid lines throw `无效 env 行` |
| New script adds JSON config | Use `JsonFile`; missing required business fields are validated after merge |
| New script adds Markdown preset metadata | Use `Read-ConfigMarkdownFrontMatter` or `MarkdownFrontMatter` source |
| CLI parameter should override config file | Put `CliParameters` after file sources |
| CLI parameter is a control flag, not config | Add it to `ExcludeKeys` |
| Child command needs temporary env | Wrap invocation in `Invoke-WithScopedEnvironment` |
| Single-file bundle needs config helpers | Inline through a build/dependency step from `psutils/src/config`, then test the bundle |

### 5. Good/Base/Bad Cases

- Good: `scripts/pwsh/download/Install-GitHubCli.ps1` imports `psutils/modules/config.psm1` and merges `Defaults`、`JsonFile`、`CliParameters`.
- Good: `scripts/pwsh/ai/agent-runner/core/config.ps1` merges default agent settings, preset metadata and CLI overrides with `Resolve-ConfigSources`.
- Good: `scripts/pwsh/devops/start-container.ps1` imports the config module, resolves compose environment through `Resolve-ServiceComposeConfiguration`, and uses `Invoke-WithScopedEnvironment` around Docker Compose calls.
- Good: `scripts/pwsh/devops/postgresql/core/context.ps1` delegates default env discovery and env file loading to shared config helpers.
- Base: `scripts/pwsh/ai/agent-runner/core/prompt.ps1` uses `Read-ConfigMarkdownFrontMatter` for preset metadata, but direct `-PromptFile` content reading remains plain file IO because it is not config metadata.
- Bad: Add another `Import-EnvFile` implementation for new scripts. `start-container.ps1` still has a historical helper, but new work should not copy it.
- Bad: Parse top-level JSON config with `Get-Content -Raw | ConvertFrom-Json` in a new script when `JsonFile` can participate in source ordering and source tracking.

### 6. Tests Required

- Source order tests must assert the business-specific precedence, for example default < `.env` < `.env.local` < CLI/env overrides.
- Error tests must assert malformed env or frontmatter errors surface with useful messages instead of silently ignoring bad config.
- For CLI overrides, assert omitted/empty parameters do not erase config-file values.
- For temporary env injection, assert existing env values are restored after the command and newly added values are removed.
- For bundle scripts, add a build test that confirms generated output includes the required shared config functions and a command test that exercises config loading in the generated script.

### 7. Wrong vs Correct

#### Wrong

```powershell
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if ($PSBoundParameters.ContainsKey('DownloadDir')) {
    $config.download_dir = $DownloadDir
}
```

问题：文件读取、CLI 覆盖、缺失文件处理和来源追踪都散落在业务脚本里，后续脚本会复制出不同语义。

#### Correct

```powershell
$sources = @(
    @{ Type = 'Hashtable'; Name = 'Defaults'; Data = @{ download_dir = '.downloads' } }
    @{ Type = 'JsonFile'; Name = 'ConfigFile'; Path = $ConfigPath }
    @{
        Type        = 'CliParameters'
        Name        = 'Cli'
        Data        = $PSBoundParameters
        ExcludeKeys = @('ConfigPath', 'DryRun')
    }
)

$config = (Resolve-ConfigSources -Sources $sources -BasePath $basePath -ErrorOnMissing).Values
```

理由：脚本只描述“有哪些来源”和“谁覆盖谁”，共享解析器负责一致的读取、合并和错误语义。
