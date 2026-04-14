# PostgreSQL Toolkit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个跨平台的 PostgreSQL PowerShell CLI，源码可拆分维护，最终产出单文件脚本与独立帮助文档，并覆盖 `backup`、`restore`、`import-csv`、`install-tools` 四个核心命令。

**Architecture:** 采用“多文件源码 + 构建脚本拼装单文件产物”的结构。源码目录负责参数解析、命令翻译、平台安装策略和帮助文档源文件；测试直接针对源码入口和构建产物做断言，最终由构建脚本生成仓库内可分发的 `Postgres-Toolkit.ps1` 与 `Postgres-Toolkit.Help.md`。

**Tech Stack:** PowerShell 7、PostgreSQL CLI（`psql` / `pg_dump` / `pg_restore` / `pg_dumpall`）、Pester、pnpm QA 脚本

---

## Planned File Map

### Create

- `scripts/pwsh/devops/postgresql/main.ps1`
- `scripts/pwsh/devops/postgresql/README.md`
- `scripts/pwsh/devops/postgresql/.env.example`
- `scripts/pwsh/devops/postgresql/docs/help.md`
- `scripts/pwsh/devops/postgresql/core/logging.ps1`
- `scripts/pwsh/devops/postgresql/core/process.ps1`
- `scripts/pwsh/devops/postgresql/core/arguments.ps1`
- `scripts/pwsh/devops/postgresql/core/connection.ps1`
- `scripts/pwsh/devops/postgresql/core/context.ps1`
- `scripts/pwsh/devops/postgresql/core/formats.ps1`
- `scripts/pwsh/devops/postgresql/core/validation.ps1`
- `scripts/pwsh/devops/postgresql/commands/help.ps1`
- `scripts/pwsh/devops/postgresql/commands/backup.ps1`
- `scripts/pwsh/devops/postgresql/commands/restore.ps1`
- `scripts/pwsh/devops/postgresql/commands/import-csv.ps1`
- `scripts/pwsh/devops/postgresql/commands/install-tools.ps1`
- `scripts/pwsh/devops/postgresql/platforms/windows.ps1`
- `scripts/pwsh/devops/postgresql/platforms/macos.ps1`
- `scripts/pwsh/devops/postgresql/platforms/linux.ps1`
- `scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1`
- `tests/PostgresToolkit.Core.Tests.ps1`
- `tests/PostgresToolkit.Commands.Tests.ps1`
- `tests/PostgresToolkit.Build.Tests.ps1`

### Modify

- `package.json`

### Generated and committed

- `scripts/pwsh/devops/Postgres-Toolkit.ps1`
- `scripts/pwsh/devops/Postgres-Toolkit.Help.md`

### Responsibilities

- `core/arguments.ps1`：把 `--flag value`、`--flag=value`、布尔开关解析为统一 hashtable，避免子命令各自手写参数拆解。
- `core/connection.ps1`：解析连接串、读取 `.env`、屏蔽密码展示。
- `core/context.ps1`：合并显式参数、连接串、`.env`、`PG*` 环境变量，产出统一连接上下文。
- `core/formats.ps1`：识别备份格式与恢复输入类型。
- `core/validation.ps1`：互斥参数、路径存在性、并行参数限制等校验。
- `core/process.ps1`：统一封装 native command 执行与 dry-run 展示。
- `commands/*.ps1`：把用户参数翻译为 PostgreSQL 官方 CLI 参数数组。
- `platforms/*.ps1`：生成并可选执行各平台安装命令。
- `build/Build-PostgresToolkit.ps1`：按顺序拼装源码并输出单文件产物。
- `tests/*.Tests.ps1`：分别覆盖基础 helper、命令翻译、构建产物。

## Task 1: Build the Core Helper Layer

**Files:**
- Create: `tests/PostgresToolkit.Core.Tests.ps1`
- Create: `scripts/pwsh/devops/postgresql/core/logging.ps1`
- Create: `scripts/pwsh/devops/postgresql/core/process.ps1`
- Create: `scripts/pwsh/devops/postgresql/core/arguments.ps1`
- Create: `scripts/pwsh/devops/postgresql/core/connection.ps1`
- Create: `scripts/pwsh/devops/postgresql/core/context.ps1`
- Create: `scripts/pwsh/devops/postgresql/core/formats.ps1`
- Create: `scripts/pwsh/devops/postgresql/core/validation.ps1`

- [ ] **Step 1: Write the failing core tests**

```powershell
Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    foreach ($relativePath in @(
            'scripts/pwsh/devops/postgresql/core/logging.ps1'
            'scripts/pwsh/devops/postgresql/core/process.ps1'
            'scripts/pwsh/devops/postgresql/core/arguments.ps1'
            'scripts/pwsh/devops/postgresql/core/connection.ps1'
            'scripts/pwsh/devops/postgresql/core/context.ps1'
            'scripts/pwsh/devops/postgresql/core/formats.ps1'
            'scripts/pwsh/devops/postgresql/core/validation.ps1'
        )) {
        . (Join-Path $script:RepoRoot $relativePath)
    }
}

Describe 'Resolve-PgContext' {
    It '显式参数优先于 env-file 与进程环境变量' {
        $envFile = Join-Path $TestDrive 'postgres.env'
        Set-Content -Path $envFile -Value @(
            'PGHOST=env-file-host'
            'PGPORT=5544'
            'PGUSER=env-file-user'
            'PGPASSWORD=env-file-password'
            'PGDATABASE=env-file-db'
        )

        $env:PGHOST = 'process-host'
        $env:PGPORT = '6432'
        $env:PGUSER = 'process-user'
        $env:PGPASSWORD = 'process-password'
        $env:PGDATABASE = 'process-db'

        $context = Resolve-PgContext -CliOptions @{
            host     = 'cli-host'
            database = 'cli-db'
            env_file = $envFile
        }

        $context.Host | Should -Be 'cli-host'
        $context.Port | Should -Be 5544
        $context.User | Should -Be 'env-file-user'
        $context.Password | Should -Be 'env-file-password'
        $context.Database | Should -Be 'cli-db'
    }
}

Describe 'Resolve-PgRestoreInputKind' {
    It '识别 sql dump tar 和目录' {
        $sqlPath = Join-Path $TestDrive 'sample.sql'
        $dumpPath = Join-Path $TestDrive 'sample.dump'
        $tarPath = Join-Path $TestDrive 'sample.tar'
        $dirPath = Join-Path $TestDrive 'sample-dir'

        Set-Content -Path $sqlPath -Value '-- sql'
        Set-Content -Path $dumpPath -Value 'custom'
        Set-Content -Path $tarPath -Value 'tar'
        New-Item -Path $dirPath -ItemType Directory | Out-Null

        (Resolve-PgRestoreInputKind -InputPath $sqlPath) | Should -Be 'sql'
        (Resolve-PgRestoreInputKind -InputPath $dumpPath) | Should -Be 'archive'
        (Resolve-PgRestoreInputKind -InputPath $tarPath) | Should -Be 'archive'
        (Resolve-PgRestoreInputKind -InputPath $dirPath) | Should -Be 'directory'
    }
}

Describe 'ConvertFrom-LongOptionList' {
    It '解析 --flag value 与 --flag=value 形式' {
        $parsed = ConvertFrom-LongOptionList -Arguments @(
            '--host', 'db.local',
            '--database=app',
            '--header',
            '--jobs', '4'
        )

        $parsed.host | Should -Be 'db.local'
        $parsed.database | Should -Be 'app'
        $parsed.header | Should -BeTrue
        $parsed.jobs | Should -Be '4'
    }
}

Describe 'Invoke-PgNativeCommand' {
    It 'dry-run 只返回命令预览' {
        $spec = New-PgNativeCommandSpec -FilePath 'pg_dump' -ArgumentList @('-Fc', '-f', 'app.dump') -Environment @{ PGPASSWORD = 'secret' }
        $result = Invoke-PgNativeCommand -Spec $spec -DryRun

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'pg_dump'
        $result.Output | Should -Match 'app.dump'
    }
}
```

- [ ] **Step 2: Run the core test file and verify it fails**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path ./tests/PostgresToolkit.Core.Tests.ps1
```

Expected: FAIL，提示类似 `Resolve-PgContext is not recognized`、`Resolve-PgRestoreInputKind is not recognized`。

- [ ] **Step 3: Write the minimal helper implementation**

```powershell
# scripts/pwsh/devops/postgresql/core/arguments.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-LongOptionList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $result = [ordered]@{}
    $index = 0
    while ($index -lt $Arguments.Count) {
        $token = $Arguments[$index]
        if (-not $token.StartsWith('--')) {
            throw "仅支持 GNU 风格长参数，收到: $token"
        }

        $trimmed = $token.Substring(2)
        if ($trimmed.Contains('=')) {
            $parts = $trimmed.Split('=', 2)
            $result[$parts[0].Replace('-', '_')] = $parts[1]
            $index++
            continue
        }

        if (($index + 1) -lt $Arguments.Count -and -not $Arguments[$index + 1].StartsWith('--')) {
            $result[$trimmed.Replace('-', '_')] = $Arguments[$index + 1]
            $index += 2
            continue
        }

        $result[$trimmed.Replace('-', '_')] = $true
        $index++
    }

    return $result
}
```

```powershell
# scripts/pwsh/devops/postgresql/core/connection.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-PgEnvFile {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @{}
    }

    $values = [ordered]@{}
    foreach ($line in Get-Content -Path $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }

        $parts = $line.Split('=', 2)
        if ($parts.Count -ne 2) {
            throw "无效 env 行: $line"
        }

        $values[$parts[0].Trim()] = $parts[1].Trim()
    }

    return $values
}

function ConvertFrom-PgConnectionString {
    [CmdletBinding()]
    param(
        [string]$ConnectionString
    )

    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        return @{}
    }

    $builder = [System.Uri]$ConnectionString
    return @{
        Host     = $builder.Host
        Port     = if ($builder.Port -gt 0) { $builder.Port } else { $null }
        User     = $builder.UserInfo.Split(':', 2)[0]
        Password = if ($builder.UserInfo.Contains(':')) { $builder.UserInfo.Split(':', 2)[1] } else { $null }
        Database = $builder.AbsolutePath.TrimStart('/')
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/core/context.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-PgContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions
    )

    $envFileValues = Import-PgEnvFile -Path $CliOptions.env_file
    $connectionValues = ConvertFrom-PgConnectionString -ConnectionString $CliOptions.connection_string

    $host = if ($CliOptions.host) { $CliOptions.host } elseif ($connectionValues.Host) { $connectionValues.Host } elseif ($envFileValues.PGHOST) { $envFileValues.PGHOST } else { $env:PGHOST }
    $port = if ($CliOptions.port) { [int]$CliOptions.port } elseif ($connectionValues.Port) { [int]$connectionValues.Port } elseif ($envFileValues.PGPORT) { [int]$envFileValues.PGPORT } elseif ($env:PGPORT) { [int]$env:PGPORT } else { 5432 }
    $user = if ($CliOptions.user) { $CliOptions.user } elseif ($connectionValues.User) { $connectionValues.User } elseif ($envFileValues.PGUSER) { $envFileValues.PGUSER } else { $env:PGUSER }
    $password = if ($CliOptions.password) { $CliOptions.password } elseif ($connectionValues.Password) { $connectionValues.Password } elseif ($envFileValues.PGPASSWORD) { $envFileValues.PGPASSWORD } else { $env:PGPASSWORD }
    $database = if ($CliOptions.database) { $CliOptions.database } elseif ($connectionValues.Database) { $connectionValues.Database } elseif ($envFileValues.PGDATABASE) { $envFileValues.PGDATABASE } else { $env:PGDATABASE }

    return [PSCustomObject]@{
        Host     = $host
        Port     = $port
        User     = $user
        Password = $password
        Database = $database
        EnvFile  = $CliOptions.env_file
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/core/formats.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-PgRestoreInputKind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputPath
    )

    if (Test-Path -Path $InputPath -PathType Container) {
        return 'directory'
    }

    $extension = [System.IO.Path]::GetExtension($InputPath).ToLowerInvariant()
    return switch ($extension) {
        '.sql' { 'sql' }
        '.dump' { 'archive' }
        '.backup' { 'archive' }
        '.tar' { 'archive' }
        default { throw "不支持的恢复输入类型: $InputPath" }
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/core/validation.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-PgMutuallyExclusiveOptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Left,
        [Parameter(Mandatory)]
        [bool]$Right,
        [Parameter(Mandatory)]
        [string]$LeftName,
        [Parameter(Mandatory)]
        [string]$RightName
    )

    if ($Left -and $Right) {
        throw "参数冲突: $LeftName 与 $RightName 不能同时使用。"
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/core/logging.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-PostgresToolkitMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('info', 'warn', 'error')]
        [string]$Level,
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host ("[postgres-toolkit][{0}] {1}" -f $Level, $Message)
}
```

```powershell
# scripts/pwsh/devops/postgresql/core/process.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Format-PgNativeCommandPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec
    )

    $arguments = $Spec.ArgumentList -join ' '
    return ("{0} {1}" -f $Spec.FilePath, $arguments).Trim()
}

function New-PgNativeCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string[]]$ArgumentList,
        [AllowNull()]
        [hashtable]$Environment
    )

    return [PSCustomObject]@{
        FilePath     = $FilePath
        ArgumentList = $ArgumentList
        Environment  = if ($null -eq $Environment) { @{} } else { $Environment }
    }
}

function Invoke-PgNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Spec,
        [switch]$DryRun
    )

    if ($DryRun) {
        return [PSCustomObject]@{
            ExitCode = 0
            Output   = Format-PgNativeCommandPreview -Spec $Spec
        }
    }

    $previous = @{}
    foreach ($entry in $Spec.Environment.GetEnumerator()) {
        $previous[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }

    try {
        $output = @(& $Spec.FilePath @Spec.ArgumentList)
        return [PSCustomObject]@{
            ExitCode = $LASTEXITCODE
            Output   = ($output -join [Environment]::NewLine)
        }
    }
    finally {
        foreach ($entry in $previous.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
        }
    }
}
```

- [ ] **Step 4: Run the core test file and verify it passes**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path ./tests/PostgresToolkit.Core.Tests.ps1
```

Expected: PASS，`Resolve-PgContext`、`Resolve-PgRestoreInputKind`、`ConvertFrom-LongOptionList` 断言全部通过。

- [ ] **Step 5: Commit the helper layer**

```powershell
git add tests/PostgresToolkit.Core.Tests.ps1 scripts/pwsh/devops/postgresql/core
git commit -m "test: add postgresql toolkit core helpers"
```

## Task 2: Add the CLI Entry, Help Text, and Source Docs

**Files:**
- Create: `tests/PostgresToolkit.Commands.Tests.ps1`
- Create: `scripts/pwsh/devops/postgresql/main.ps1`
- Create: `scripts/pwsh/devops/postgresql/commands/help.ps1`
- Create: `scripts/pwsh/devops/postgresql/README.md`
- Create: `scripts/pwsh/devops/postgresql/.env.example`
- Create: `scripts/pwsh/devops/postgresql/docs/help.md`

- [ ] **Step 1: Write the failing CLI help tests**

```powershell
Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $env:PWSH_TEST_SKIP_POSTGRES_TOOLKIT_MAIN = '1'

    foreach ($relativePath in @(
            'scripts/pwsh/devops/postgresql/core/logging.ps1'
            'scripts/pwsh/devops/postgresql/core/process.ps1'
            'scripts/pwsh/devops/postgresql/core/arguments.ps1'
            'scripts/pwsh/devops/postgresql/core/connection.ps1'
            'scripts/pwsh/devops/postgresql/core/context.ps1'
            'scripts/pwsh/devops/postgresql/core/formats.ps1'
            'scripts/pwsh/devops/postgresql/core/validation.ps1'
            'scripts/pwsh/devops/postgresql/commands/help.ps1'
            'scripts/pwsh/devops/postgresql/main.ps1'
        )) {
        . (Join-Path $script:RepoRoot $relativePath)
    }
}

Describe 'Get-PostgresToolkitHelpText' {
    It '输出四个核心命令和示例' {
        $helpText = Get-PostgresToolkitHelpText

        $helpText | Should -Match 'backup'
        $helpText | Should -Match 'restore'
        $helpText | Should -Match 'import-csv'
        $helpText | Should -Match 'install-tools'
        $helpText | Should -Match 'Postgres-Toolkit.ps1 backup'
    }
}

Describe 'Invoke-PostgresToolkitCommand' {
    It '未传命令时返回帮助文本而不是抛错' {
        $result = Invoke-PostgresToolkitCommand -CommandName '' -RawArguments @()
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Usage'
    }
}
```

- [ ] **Step 2: Run the command test file and verify it fails**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path ./tests/PostgresToolkit.Commands.Tests.ps1
```

Expected: FAIL，提示 `Get-PostgresToolkitHelpText is not recognized` 或 `Invoke-PostgresToolkitCommand is not recognized`。

- [ ] **Step 3: Write the CLI skeleton and source docs**

```powershell
# scripts/pwsh/devops/postgresql/commands/help.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PostgresToolkitHelpText {
    [CmdletBinding()]
    param(
        [string]$CommandName
    )

    $sections = @{
        default = @'
Usage:
  ./Postgres-Toolkit.ps1 <command> [options]

Commands:
  backup
  restore
  import-csv
  install-tools
  help

Examples:
  ./Postgres-Toolkit.ps1 backup --database app --output ./app.dump --format custom
  ./Postgres-Toolkit.ps1 restore --input ./app.dump --target-database app_restore --clean
  ./Postgres-Toolkit.ps1 import-csv --input ./users.csv --table users --header
  ./Postgres-Toolkit.ps1 install-tools --apply
'@
    }

    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        return $sections.default.Trim()
    }

    return $sections.default.Trim()
}
```

```powershell
# scripts/pwsh/devops/postgresql/main.ps1
#!/usr/bin/env pwsh
<#
.SYNOPSIS
    PostgreSQL 常用备份、恢复、CSV 导入与工具安装命令行工具。
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$CommandName,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RawArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-PostgresToolkitCommand {
    [CmdletBinding()]
    param(
        [string]$CommandName,
        [string[]]$RawArguments
    )

    if ([string]::IsNullOrWhiteSpace($CommandName) -or $CommandName -eq 'help') {
        return [PSCustomObject]@{
            ExitCode = 0
            Output   = Get-PostgresToolkitHelpText
        }
    }

    throw "未知命令: $CommandName"
}

if ($env:PWSH_TEST_SKIP_POSTGRES_TOOLKIT_MAIN -ne '1') {
    $result = Invoke-PostgresToolkitCommand -CommandName $CommandName -RawArguments $RawArguments
    if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
        Write-Output $result.Output
    }
    exit $result.ExitCode
}
```

````markdown
<!-- scripts/pwsh/devops/postgresql/README.md -->
# PostgreSQL Toolkit Source

这个目录存放 PostgreSQL PowerShell CLI 的源码、帮助文档源文件和构建脚本。

## Build

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1
```

## Commands

- `backup`
- `restore`
- `import-csv`
- `install-tools`
````

```dotenv
# scripts/pwsh/devops/postgresql/.env.example
PGHOST=127.0.0.1
PGPORT=5432
PGUSER=postgres
PGPASSWORD=change-me
PGDATABASE=app
```

````markdown
<!-- scripts/pwsh/devops/postgresql/docs/help.md -->
# Postgres Toolkit Help

## Commands

- `backup`
- `restore`
- `import-csv`
- `install-tools`

## Examples

```powershell
./Postgres-Toolkit.ps1 backup --database app --output ./app.dump --format custom
```
````

- [ ] **Step 4: Re-run the command test file and verify it passes**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path ./tests/PostgresToolkit.Commands.Tests.ps1
```

Expected: PASS，帮助文本和空命令行为断言通过。

- [ ] **Step 5: Commit the CLI skeleton**

```powershell
git add tests/PostgresToolkit.Commands.Tests.ps1 scripts/pwsh/devops/postgresql/main.ps1 scripts/pwsh/devops/postgresql/commands/help.ps1 scripts/pwsh/devops/postgresql/README.md scripts/pwsh/devops/postgresql/.env.example scripts/pwsh/devops/postgresql/docs/help.md
git commit -m "feat: scaffold postgresql toolkit cli"
```

## Task 3: Implement backup and restore Command Translation

**Files:**
- Modify: `tests/PostgresToolkit.Commands.Tests.ps1`
- Create: `scripts/pwsh/devops/postgresql/commands/backup.ps1`
- Create: `scripts/pwsh/devops/postgresql/commands/restore.ps1`
- Modify: `scripts/pwsh/devops/postgresql/main.ps1`

- [ ] **Step 1: Extend the command tests with backup and restore coverage**

```powershell
Describe 'New-PgBackupCommandSpec' {
    It '默认生成 custom 格式 pg_dump 命令' {
        $spec = New-PgBackupCommandSpec -CliOptions @{
            database = 'app'
            output   = './app.dump'
        } -Context ([PSCustomObject]@{
            Host     = '127.0.0.1'
            Port     = 5432
            User     = 'postgres'
            Password = 'secret'
            Database = 'app'
        })

        $spec.FilePath | Should -Be 'pg_dump'
        $spec.ArgumentList -join ' ' | Should -Match '-Fc'
        $spec.ArgumentList -join ' ' | Should -Match 'app.dump'
    }
}

Describe 'New-PgRestoreCommandSpec' {
    It 'sql 文件切换到 psql 恢复路径' {
        $inputPath = Join-Path $TestDrive 'sample.sql'
        Set-Content -Path $inputPath -Value '-- sql'

        $spec = New-PgRestoreCommandSpec -CliOptions @{
            input           = $inputPath
            target_database = 'restore_db'
        } -Context ([PSCustomObject]@{
            Host     = '127.0.0.1'
            Port     = 5432
            User     = 'postgres'
            Password = 'secret'
            Database = 'postgres'
        })

        $spec.FilePath | Should -Be 'psql'
        $spec.ArgumentList -join ' ' | Should -Match 'restore_db'
        $spec.ArgumentList -join ' ' | Should -Match '-f'
    }

    It 'archive 文件走 pg_restore 并支持 --clean' {
        $inputPath = Join-Path $TestDrive 'sample.dump'
        Set-Content -Path $inputPath -Value 'archive'

        $spec = New-PgRestoreCommandSpec -CliOptions @{
            input           = $inputPath
            target_database = 'restore_db'
            clean           = $true
        } -Context ([PSCustomObject]@{
            Host     = '127.0.0.1'
            Port     = 5432
            User     = 'postgres'
            Password = 'secret'
            Database = 'postgres'
        })

        $spec.FilePath | Should -Be 'pg_restore'
        $spec.ArgumentList | Should -Contain '--clean'
    }
}
```

- [ ] **Step 2: Run the command tests and verify the new cases fail**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path ./tests/PostgresToolkit.Commands.Tests.ps1
```

Expected: FAIL，提示 `New-PgBackupCommandSpec is not recognized` 或 `New-PgRestoreCommandSpec is not recognized`。

- [ ] **Step 3: Implement backup and restore translation**

```powershell
# scripts/pwsh/devops/postgresql/commands/backup.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-PgBackupCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions,
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $format = if ($CliOptions.format) { $CliOptions.format } else { 'custom' }
    if ($format -ne 'directory' -and $CliOptions.jobs) {
        throw '只有 directory 格式支持 --jobs。'
    }

    Assert-PgMutuallyExclusiveOptions `
        -Left ([bool]$CliOptions.schema_only) `
        -Right ([bool]$CliOptions.data_only) `
        -LeftName '--schema-only' `
        -RightName '--data-only'

    $arguments = @(
        '-h', $Context.Host,
        '-p', [string]$Context.Port,
        '-U', $Context.User,
        '-d', $Context.Database
    )

    $arguments += switch ($format) {
        'plain' { '-Fp' }
        'directory' { '-Fd' }
        'tar' { '-Ft' }
        default { '-Fc' }
    }

    if ($CliOptions.output) { $arguments += @('-f', $CliOptions.output) }
    if ($CliOptions.table) { $arguments += @('-t', $CliOptions.table) }
    if ($CliOptions.schema) { $arguments += @('-n', $CliOptions.schema) }
    if ($CliOptions.exclude_table) { $arguments += "--exclude-table=$($CliOptions.exclude_table)" }
    if ($CliOptions.schema_only) { $arguments += '-s' }
    if ($CliOptions.data_only) { $arguments += '-a' }
    if ($CliOptions.jobs) { $arguments += @('-j', [string]$CliOptions.jobs) }

    return New-PgNativeCommandSpec -FilePath 'pg_dump' -ArgumentList $arguments -Environment @{
        PGPASSWORD = $Context.Password
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/commands/restore.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-PgRestoreCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions,
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $inputKind = Resolve-PgRestoreInputKind -InputPath $CliOptions.input
    $targetDatabase = if ($CliOptions.target_database) { $CliOptions.target_database } else { $Context.Database }

    if ($inputKind -eq 'sql') {
        $arguments = @(
            '-h', $Context.Host,
            '-p', [string]$Context.Port,
            '-U', $Context.User,
            '-d', $targetDatabase,
            '-v', 'ON_ERROR_STOP=1',
            '-f', $CliOptions.input
        )

        return New-PgNativeCommandSpec -FilePath 'psql' -ArgumentList $arguments -Environment @{
            PGPASSWORD = $Context.Password
        }
    }

    $arguments = @(
        '-h', $Context.Host,
        '-p', [string]$Context.Port,
        '-U', $Context.User,
        '-d', $targetDatabase
    )

    if ($CliOptions.clean) { $arguments += '--clean' }
    if ($CliOptions.if_exists) { $arguments += '--if-exists' }
    if ($CliOptions.no_owner) { $arguments += '--no-owner' }
    if ($CliOptions.no_privileges) { $arguments += '--no-privileges' }
    if ($CliOptions.schema_only) { $arguments += '-s' }
    if ($CliOptions.data_only) { $arguments += '-a' }
    if ($CliOptions.table) { $arguments += @('-t', $CliOptions.table) }
    if ($CliOptions.schema) { $arguments += @('-n', $CliOptions.schema) }
    if ($CliOptions.jobs) { $arguments += @('-j', [string]$CliOptions.jobs) }
    $arguments += $CliOptions.input

    return New-PgNativeCommandSpec -FilePath 'pg_restore' -ArgumentList $arguments -Environment @{
        PGPASSWORD = $Context.Password
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/main.ps1
function Invoke-PostgresToolkitCommand {
    [CmdletBinding()]
    param(
        [string]$CommandName,
        [string[]]$RawArguments
    )

    $options = ConvertFrom-LongOptionList -Arguments $RawArguments
    $context = Resolve-PgContext -CliOptions $options
    $dryRun = [bool]$options.dry_run

    switch ($CommandName) {
        'backup' {
            $spec = New-PgBackupCommandSpec -CliOptions $options -Context $context
            return Invoke-PgNativeCommand -Spec $spec -DryRun:$dryRun
        }
        'restore' {
            $spec = New-PgRestoreCommandSpec -CliOptions $options -Context $context
            return Invoke-PgNativeCommand -Spec $spec -DryRun:$dryRun
        }
        'help' { return [PSCustomObject]@{ ExitCode = 0; Output = Get-PostgresToolkitHelpText } }
        default { return [PSCustomObject]@{ ExitCode = 0; Output = Get-PostgresToolkitHelpText } }
    }
}
```

- [ ] **Step 4: Re-run the command tests and verify backup/restore pass**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path ./tests/PostgresToolkit.Commands.Tests.ps1
```

Expected: PASS，新增的 `backup` / `restore` 参数翻译断言通过。

- [ ] **Step 5: Commit backup and restore**

```powershell
git add tests/PostgresToolkit.Commands.Tests.ps1 scripts/pwsh/devops/postgresql/commands/backup.ps1 scripts/pwsh/devops/postgresql/commands/restore.ps1 scripts/pwsh/devops/postgresql/main.ps1
git commit -m "feat: add postgresql backup and restore commands"
```

## Task 4: Implement import-csv and install-tools

**Files:**
- Modify: `tests/PostgresToolkit.Commands.Tests.ps1`
- Create: `scripts/pwsh/devops/postgresql/commands/import-csv.ps1`
- Create: `scripts/pwsh/devops/postgresql/commands/install-tools.ps1`
- Create: `scripts/pwsh/devops/postgresql/platforms/windows.ps1`
- Create: `scripts/pwsh/devops/postgresql/platforms/macos.ps1`
- Create: `scripts/pwsh/devops/postgresql/platforms/linux.ps1`
- Modify: `scripts/pwsh/devops/postgresql/main.ps1`

- [ ] **Step 1: Add failing tests for CSV import and install plan generation**

```powershell
Describe 'New-PgImportCsvCommandSpec' {
    It '生成带 header 的 \\copy 语句' {
        $csvPath = Join-Path $TestDrive 'users.csv'
        Set-Content -Path $csvPath -Value "id,name`n1,Alice"

        $spec = New-PgImportCsvCommandSpec -CliOptions @{
            input  = $csvPath
            table  = 'users'
            header = $true
        } -Context ([PSCustomObject]@{
            Host     = '127.0.0.1'
            Port     = 5432
            User     = 'postgres'
            Password = 'secret'
            Database = 'app'
        })

        $spec.FilePath | Should -Be 'psql'
        $spec.ArgumentList -join ' ' | Should -Match '\\copy public.users'
        $spec.ArgumentList -join ' ' | Should -Match 'HEADER true'
    }
}

Describe 'Get-PgInstallPlan' {
    It 'Windows auto 策略优先返回 winget 命令' {
        $plan = Get-PgInstallPlan -Platform 'windows' -PackageManager 'auto' -Tools @('psql', 'pg_dump')

        $plan.PackageManager | Should -Be 'winget'
        $plan.Commands[0] | Should -Match 'winget'
    }

    It 'Linux apt 策略返回 apt install 命令' {
        $plan = Get-PgInstallPlan -Platform 'linux' -PackageManager 'apt' -Tools @('psql')

        $plan.Commands[0] | Should -Match 'apt-get install'
    }
}
```

- [ ] **Step 2: Run the command tests and verify the new cases fail**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path ./tests/PostgresToolkit.Commands.Tests.ps1
```

Expected: FAIL，提示 `New-PgImportCsvCommandSpec` 或 `Get-PgInstallPlan` 尚未定义。

- [ ] **Step 3: Implement CSV import and install strategy**

```powershell
# scripts/pwsh/devops/postgresql/commands/import-csv.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-PgImportCsvCommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$CliOptions,
        [Parameter(Mandatory)]
        [pscustomobject]$Context
    )

    $schema = if ($CliOptions.schema) { $CliOptions.schema } else { 'public' }
    $delimiter = if ($CliOptions.delimiter) { $CliOptions.delimiter } else { ',' }
    $header = if ($CliOptions.header) { 'true' } else { 'false' }
    $nullString = if ($CliOptions.null_string) { ", NULL '$($CliOptions.null_string)'" } else { '' }
    $columns = if ($CliOptions.columns) { "($($CliOptions.columns))" } else { '' }
    $truncateSql = if ($CliOptions.truncate_first) { "TRUNCATE TABLE $schema.$($CliOptions.table); " } else { '' }
    $copySql = "$truncateSql\copy $schema.$($CliOptions.table)$columns FROM '$($CliOptions.input)' WITH (FORMAT csv, HEADER $header, DELIMITER '$delimiter'$nullString);"

    $arguments = @(
        '-h', $Context.Host,
        '-p', [string]$Context.Port,
        '-U', $Context.User,
        '-d', $Context.Database,
        '-v', 'ON_ERROR_STOP=1',
        '-c', $copySql
    )

    return New-PgNativeCommandSpec -FilePath 'psql' -ArgumentList $arguments -Environment @{
        PGPASSWORD = $Context.Password
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/platforms/windows.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PgWindowsInstallPlan {
    [CmdletBinding()]
    param(
        [string]$PackageManager = 'auto'
    )

    $manager = if ($PackageManager -eq 'auto') { 'winget' } else { $PackageManager }
    $command = switch ($manager) {
        'winget' { 'winget install --id PostgreSQL.PostgreSQL --source winget' }
        'choco' { 'choco install postgresql --yes' }
        default { throw "Windows 不支持的包管理器: $manager" }
    }

    return [PSCustomObject]@{
        PackageManager = $manager
        Commands       = @($command)
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/platforms/macos.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PgMacOSInstallPlan {
    [CmdletBinding()]
    param(
        [string]$PackageManager = 'auto'
    )

    $manager = if ($PackageManager -eq 'auto') { 'brew' } else { $PackageManager }
    if ($manager -ne 'brew') {
        throw "macOS 不支持的包管理器: $manager"
    }

    return [PSCustomObject]@{
        PackageManager = $manager
        Commands       = @('brew install libpq', 'brew link --force libpq')
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/platforms/linux.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PgLinuxInstallPlan {
    [CmdletBinding()]
    param(
        [string]$PackageManager = 'auto'
    )

    $manager = if ($PackageManager -eq 'auto') { 'apt' } else { $PackageManager }
    $command = switch ($manager) {
        'apt' { 'sudo apt-get update && sudo apt-get install -y postgresql-client' }
        'dnf' { 'sudo dnf install -y postgresql' }
        'yum' { 'sudo yum install -y postgresql' }
        'apk' { 'sudo apk add postgresql-client' }
        default { throw "Linux 不支持的包管理器: $manager" }
    }

    return [PSCustomObject]@{
        PackageManager = $manager
        Commands       = @($command)
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/commands/install-tools.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MissingPgTools {
    [CmdletBinding()]
    param(
        [string[]]$Tools = @('psql', 'pg_dump', 'pg_restore', 'pg_dumpall')
    )

    return @(
        foreach ($tool in $Tools) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                $tool
            }
        }
    )
}

function Get-PgInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('windows', 'macos', 'linux')]
        [string]$Platform,
        [string]$PackageManager = 'auto',
        [string[]]$Tools = @('psql', 'pg_dump', 'pg_restore', 'pg_dumpall')
    )

    return switch ($Platform) {
        'windows' { Get-PgWindowsInstallPlan -PackageManager $PackageManager }
        'macos' { Get-PgMacOSInstallPlan -PackageManager $PackageManager }
        'linux' { Get-PgLinuxInstallPlan -PackageManager $PackageManager }
    }
}

function Invoke-PgInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Plan,
        [switch]$Apply
    )

    if (-not $Apply) {
        return [PSCustomObject]@{
            ExitCode = 0
            Output   = ($Plan.Commands -join [Environment]::NewLine)
        }
    }

    $runner = if ($IsWindows) {
        @{
            FilePath     = 'pwsh'
            ArgumentList = @('-NoProfile', '-Command')
        }
    }
    else {
        @{
            FilePath     = '/bin/sh'
            ArgumentList = @('-lc')
        }
    }

    foreach ($commandText in $Plan.Commands) {
        Write-PostgresToolkitMessage -Level info -Message ("执行安装命令: {0}" -f $commandText)
        $null = & $runner.FilePath @($runner.ArgumentList + $commandText)
        if ($LASTEXITCODE -ne 0) {
            throw "安装命令执行失败: $commandText"
        }
    }

    return [PSCustomObject]@{
        ExitCode = 0
        Output   = ($Plan.Commands -join [Environment]::NewLine)
    }
}
```

```powershell
# scripts/pwsh/devops/postgresql/main.ps1
switch ($CommandName) {
    'import-csv' {
        $spec = New-PgImportCsvCommandSpec -CliOptions $options -Context $context
        return Invoke-PgNativeCommand -Spec $spec -DryRun:$dryRun
    }
    'install-tools' {
        $platform = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
        $missingTools = Get-MissingPgTools -Tools $(if ($options.tool) { @($options.tool -split ',') } else { @('psql', 'pg_dump', 'pg_restore', 'pg_dumpall') })
        if ($missingTools.Count -eq 0) {
            return [PSCustomObject]@{ ExitCode = 0; Output = '所有 PostgreSQL CLI 工具已可用。' }
        }

        $plan = Get-PgInstallPlan -Platform $platform -PackageManager $(if ($options.package_manager) { $options.package_manager } else { 'auto' })
        return Invoke-PgInstallPlan -Plan $plan -Apply:([bool]$options.apply)
    }
}
```

- [ ] **Step 4: Re-run the command tests and verify CSV/install cases pass**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path ./tests/PostgresToolkit.Commands.Tests.ps1
```

Expected: PASS，CSV 导入与安装策略断言全部通过。

- [ ] **Step 5: Commit CSV import and install-tools**

```powershell
git add tests/PostgresToolkit.Commands.Tests.ps1 scripts/pwsh/devops/postgresql/commands/import-csv.ps1 scripts/pwsh/devops/postgresql/commands/install-tools.ps1 scripts/pwsh/devops/postgresql/platforms scripts/pwsh/devops/postgresql/main.ps1
git commit -m "feat: add postgresql csv import and install commands"
```

## Task 5: Add the Builder and Build Verification Tests

**Files:**
- Create: `tests/PostgresToolkit.Build.Tests.ps1`
- Create: `scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1`
- Modify: `package.json`

- [ ] **Step 1: Write the failing build tests**

```powershell
Set-StrictMode -Version Latest

Describe 'Build-PostgresToolkit.ps1' {
    It '生成单文件脚本和帮助文档' {
        $outputScript = Join-Path $TestDrive 'Postgres-Toolkit.ps1'
        $outputHelp = Join-Path $TestDrive 'Postgres-Toolkit.Help.md'
        $builderPath = Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'devops' 'postgresql' 'build' 'Build-PostgresToolkit.ps1'

        & $builderPath -SourceRoot (Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'devops' 'postgresql') -OutputScriptPath $outputScript -OutputHelpPath $outputHelp

        Test-Path $outputScript | Should -BeTrue
        Test-Path $outputHelp | Should -BeTrue
        (Get-Content -Path $outputScript -Raw) | Should -Match 'Invoke-PostgresToolkitCommand'
        (Get-Content -Path $outputHelp -Raw) | Should -Match 'import-csv'
    }
}
```

- [ ] **Step 2: Run the build test file and verify it fails**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path ./tests/PostgresToolkit.Build.Tests.ps1
```

Expected: FAIL，提示构建脚本不存在或未生成产物。

- [ ] **Step 3: Implement the builder and add a package script**

```powershell
# scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1
#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot '..'),
    [string]$OutputScriptPath = (Join-Path $PSScriptRoot '..' '..' 'Postgres-Toolkit.ps1'),
    [string]$OutputHelpPath = (Join-Path $PSScriptRoot '..' '..' 'Postgres-Toolkit.Help.md')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptParts = @(
    'core/logging.ps1'
    'core/process.ps1'
    'core/arguments.ps1'
    'core/connection.ps1'
    'core/context.ps1'
    'core/formats.ps1'
    'core/validation.ps1'
    'platforms/windows.ps1'
    'platforms/macos.ps1'
    'platforms/linux.ps1'
    'commands/help.ps1'
    'commands/backup.ps1'
    'commands/restore.ps1'
    'commands/import-csv.ps1'
    'commands/install-tools.ps1'
    'main.ps1'
)

$bundle = foreach ($relativePath in $scriptParts) {
    $fullPath = Join-Path $SourceRoot $relativePath
    if (-not (Test-Path $fullPath)) {
        throw "缺少源码片段: $fullPath"
    }

    "# region $relativePath"
    Get-Content -Path $fullPath -Raw
    "# endregion $relativePath"
}

Set-Content -Path $OutputScriptPath -Value ($bundle -join [Environment]::NewLine) -Encoding utf8NoBOM
Copy-Item -Path (Join-Path $SourceRoot 'docs/help.md') -Destination $OutputHelpPath -Force
```

```json
// package.json
{
  "scripts": {
    "build:pwsh:postgresql": "pwsh -NoProfile -File ./scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1"
  }
}
```

- [ ] **Step 4: Re-run the build tests and verify they pass**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path ./tests/PostgresToolkit.Build.Tests.ps1
```

Expected: PASS，构建测试能在 `TestDrive` 看到脚本和帮助文档。

- [ ] **Step 5: Commit the builder**

```powershell
git add tests/PostgresToolkit.Build.Tests.ps1 scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1 package.json
git commit -m "build: add postgresql toolkit bundler"
```

## Task 6: Generate the Final Artifacts and Run Full Verification

**Files:**
- Generate: `scripts/pwsh/devops/Postgres-Toolkit.ps1`
- Generate: `scripts/pwsh/devops/Postgres-Toolkit.Help.md`
- Modify if needed after verification: `scripts/pwsh/devops/postgresql/docs/help.md`

- [ ] **Step 1: Build the distributable artifacts into the repo**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1
```

Expected: `scripts/pwsh/devops/Postgres-Toolkit.ps1` 与 `scripts/pwsh/devops/Postgres-Toolkit.Help.md` 被更新。

- [ ] **Step 2: Smoke-test the built script help and dry-run output**

Run:

```powershell
$sampleSql = Join-Path $env:TEMP 'postgres-toolkit-sample.sql'
Set-Content -Path $sampleSql -Value 'select 1;'
pwsh -NoProfile -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 help
pwsh -NoProfile -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 backup --host 127.0.0.1 --database app --output ./app.dump --format custom --dry-run
pwsh -NoProfile -File ./scripts/pwsh/devops/Postgres-Toolkit.ps1 restore --host 127.0.0.1 --database postgres --input $sampleSql --target-database app_restore --dry-run
Remove-Item -Path $sampleSql -Force
```

Expected:

- 第一条命令打印四个核心子命令。
- 第二条命令打印 `pg_dump` 风格参数而不实际执行。
- 第三条命令针对 `.sql` 输入走 `psql` 风格参数而不实际执行。

- [ ] **Step 3: Run the focused PowerShell tests for the new toolkit**

Run:

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial -Coverage Off -Path "./tests/PostgresToolkit.Core.Tests.ps1;./tests/PostgresToolkit.Commands.Tests.ps1;./tests/PostgresToolkit.Build.Tests.ps1"
```

Expected: PASS，三个新增测试文件全部通过。

- [ ] **Step 4: Run repository QA and the full PowerShell suite required by project policy**

Run:

```powershell
pnpm qa
pnpm test:pwsh:all
```

Expected:

- `pnpm qa` 通过，PowerShell 格式化与仓库门禁通过。
- `pnpm test:pwsh:all` 通过；若本机 Docker 不可用，则至少记录原因并改跑 `pnpm test:pwsh:full`，在交付说明中明确 Linux 覆盖仍依赖 CI 或 WSL。

- [ ] **Step 5: Commit the finished toolkit**

```powershell
git add scripts/pwsh/devops/postgresql tests/PostgresToolkit.Core.Tests.ps1 tests/PostgresToolkit.Commands.Tests.ps1 tests/PostgresToolkit.Build.Tests.ps1 scripts/pwsh/devops/Postgres-Toolkit.ps1 scripts/pwsh/devops/Postgres-Toolkit.Help.md package.json
git commit -m "feat: add postgresql toolkit"
```

## Self-Review

### Spec Coverage

- `backup`、`restore`、`import-csv`、`install-tools`：由 Task 3 和 Task 4 实现。
- 连接优先级、`.env.example`、标准 `PG*` 变量：由 Task 1 和 Task 2 实现。
- 单文件脚本与帮助文档：由 Task 5 和 Task 6 实现。
- README、源码目录、帮助文档源文件：由 Task 2 实现。
- Pester 测试与构建验证：由 Task 1、Task 3、Task 4、Task 5、Task 6 实现。

### Placeholder Scan

- 本计划未保留任何“后续再补”“稍后实现”“占位待填”之类的未完成语句。
- 每个任务都给出了具体文件路径、测试命令、代码片段和提交命令。

### Type Consistency

- CLI 解析统一使用 `ConvertFrom-LongOptionList`。
- 连接上下文统一使用 `Resolve-PgContext`。
- 命令构建统一返回 `New-PgNativeCommandSpec` 生成的对象。
- 构建统一使用 `Build-PostgresToolkit.ps1` 产出最终脚本和帮助文档。
