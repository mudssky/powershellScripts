# psutils API Inventory

## Scope

本清单以 `psutils/psutils.psd1` 的 130 个唯一 `FunctionsToExport` 为基线，结合实际
`Import-Module` 结果、Git 跟踪 PowerShell 文件的 AST 调用、README/Profile 文本和
`Get-Help -Full` 元数据进行分类。

仓库零调用只表示“没有静态证据”，不能单独证明外部交互调用不存在。只有同时满足内部
实现属性、无稳定文档契约且没有生产/Profile 消费者的命令，才进入 Private 候选。

## Classification

| 类别 | 数量 | 聚合模块策略 |
|---|---:|---|
| Stable User | 50 | 保留聚合导出；保持交互兼容 |
| Shared Repository | 56 | 保留聚合导出；仓库消费者属于契约 |
| Compatibility | 3 | 保留聚合导出和弃用提示，不继续扩张 |
| Diagnostic | 4 | 建议移出聚合导出，保留子模块直导 |
| Private | 17 | 经本次审阅确认后停止子模块与聚合导出 |
| 合计 | 130 | 与当前 manifest 唯一导出数一致 |

### Evidence Legend

- `doc`：在根 README、psutils README 或 Profile README 中存在文本引用；不等于一定是推荐 API。
- `prod:N`：N 个非测试、非 Profile、非 example 的 Git 跟踪 PowerShell 文件存在 AST 调用。
- `profile:N`：N 个 Profile 文件存在 AST 调用。
- `example:N`：N 个活动 example 存在 AST 调用。
- `internal:N`：N 个 psutils 模块或 `src` 文件存在 AST 调用。
- `test:N`：N 个测试/benchmark 文件存在 AST 调用。
- `no in-repo call`：没有静态调用；仍可能存在交互或仓库外消费者。

## Review Decisions

### Private Candidates

高置信候选，均由公开 wrapper/聚合函数消费，或仅用于平台探测和解析实现：

- Docker：`Get-WslDockerCandidateDistro`、`Get-WslDockerEnvironmentArgument`、
  `Resolve-WslDockerDistro`、`Test-DockerDesktopDaemonAvailable`、
  `Test-WindowsDockerDaemonAvailable`、`Test-WslDockerEngineAvailable`。
- Filesystem：`Build-TreeObject`、`Show-TreeItem`、`Get-ItemColor`、
  `Get-GitignoreRules`、`Test-GitignoreMatch`。
- Help/install/test：`Convert-HelpBlock`、`Get-PackageInstallCommand`、
  `Test-ArrayNotNull`、`Test-MacOSCaskApp`、`Test-HomebrewFormula`、
  `Test-MacOSApplicationInstalled`。

以下低置信候选经审阅决定继续保留，零调用不作为删除依据：

- Stable User：`Get-ScriptFolder`、`Get-NeedBinaryDigit`、`Get-ReversedMap`、
  `New-7ZipExcludeArgs`。
- Shared Repository：`Get-GitIgnorePatterns`，作为 `New-7ZipExcludeArgs` 的可复用 reader。

### Diagnostic Boundary

以下命令不作为聚合模块长期稳定 API，但保留对应子模块直导入口：

- `Test-HelpSearchPerformance`：仅由 benchmark 使用。
- `Clear-EXEProgramCache`：测试/探测缓存维护命令。
- `Debug-CommandExecution`：无生产消费者的诊断命令。
- `Out-ModuleToFile`：无仓库消费者的模块分析工具。

### Compatibility Boundary

`Search-ModuleHelp`、`Find-PSUtilsFunction`、`Get-FunctionHelp` 继续保留聚合导出和弃用
提示。本任务不删除这三个命令，只阻止新文档和新调用继续依赖它们。

### Export And State Changes

- `string.psm1` 改为显式导出 `Get-LineBreak`、`Convert-JsoncToJson`。
- `wrapper.psm1` 改为显式导出 `Set-CustomAlias`、`Get-CustomAlias`。
- `$Global:DefaultAliasDespPrefix` 改为 script scope 常量；参数默认值和 verbose 文案不再
  依赖导入副作用。
- 暂不拆分 `functions.psm1`、`help.psm1`、`test.psm1`。本轮先收紧导出，拆分尚无
  独立的加载成本或冲突收益证据。

### Help Contract Resolution

聚合 manifest 最终保留 109 个 Stable User、Shared Repository 和 Compatibility 命令；
另有 4 个 Diagnostic 命令仅允许子模块直导。实现前发现的 `.OUTPUTS` 和显式参数说明
缺口已全部补齐，`apiBoundary.Tests.ps1` 会逐个检查聚合公共函数。`WhatIf`、`Confirm`
等 PowerShell 公共参数不计入说明缺口。

## Full Inventory

| Command | Definition | Classification | Evidence | Initial help gap | Proposed action |
|---|---|---|---|---|---|
| `Add-EnvPath` | env | Stable User | doc | outputs;params:Path,EnvTarget | 保留聚合导出 |
| `Add-Startup` | win | Stable User | test:1 | ok | 保留聚合导出 |
| `Assert-DockerComposeReady` | docker | Shared Repository | prod:4, test:1 | ok | 保留聚合导出 |
| `Build-TreeObject` | filesystem | Private | internal:1, test:1 | ok | 停止子模块与聚合导出 |
| `Clear-EXEProgramCache` | test | Diagnostic | test:1 | outputs | 移出聚合；保留子模块直导 |
| `Clear-ExpiredCache` | cache | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `Close-Proxy` | proxy | Stable User | doc | outputs | 保留聚合导出 |
| `Convert-HelpBlock` | help | Private | internal:1, test:1 | ok | 停止子模块与聚合导出 |
| `Convert-JsoncToJson` | string | Stable User | test:1 | ok | 保留聚合导出 |
| `ConvertFrom-ConfigCliParameters` | convert | Shared Repository | prod:1, internal:1 | ok | 保留聚合导出 |
| `ConvertTo-ConfigHashtable` | convert | Shared Repository | prod:11, internal:4, test:2 | ok | 保留聚合导出 |
| `ConvertTo-ConfigKeyName` | convert | Shared Repository | prod:1, internal:2 | ok | 保留聚合导出 |
| `ConvertTo-TreeJson` | filesystem | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `ConvertTo-WslDockerArgument` | docker | Shared Repository | internal:1, test:1 | ok | 保留聚合导出 |
| `ConvertTo-WslDockerMountSpec` | docker | Shared Repository | internal:1 | ok | 保留聚合导出 |
| `ConvertTo-WslDockerPath` | docker | Shared Repository | internal:1, test:1 | ok | 保留聚合导出 |
| `ConvertTo-WslDockerVolumeSpec` | docker | Shared Repository | internal:1 | ok | 保留聚合导出 |
| `Copy-FileSystemItemSafe` | filesystem | Shared Repository | doc, prod:1, internal:1, test:1 | ok | 保留聚合导出 |
| `Debug-CommandExecution` | error | Diagnostic | test:1 | ok | 移出聚合；保留子模块直导 |
| `Enable-WslDockerWrapper` | docker | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `Expand-ArchiveFile` | filesystem | Shared Repository | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `Find-ExecutableCommand` | commandDiscovery | Shared Repository | doc, profile:1, internal:1, test:2 | ok | 保留聚合导出 |
| `Find-FileCandidate` | filesystem | Shared Repository | prod:1, test:1 | ok | 保留聚合导出 |
| `Find-PSUtilsFunction` | help | Compatibility | doc, test:1 | outputs | 保留兼容并维持弃用提示 |
| `Format-NativeCommandLine` | process | Shared Repository | doc, prod:3, internal:1, test:1 | ok | 保留聚合导出 |
| `Get-ArchiveKind` | filesystem | Shared Repository | doc, prod:1, internal:1, test:1 | ok | 保留聚合导出 |
| `Get-CacheStats` | cache | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `Get-ConfigValue` | convert | Shared Repository | prod:6, internal:2, test:1 | ok | 保留聚合导出 |
| `Get-CustomAlias` | wrapper | Stable User | doc, profile:1, test:1 | outputs | 保留聚合导出 |
| `Get-DockerComposeBaseArgs` | docker | Shared Repository | prod:1, test:1 | ok | 保留聚合导出 |
| `Get-Dotenv` | env | Stable User | doc, internal:1, test:1 | params:Path | 保留聚合导出 |
| `Get-EnvParam` | env | Shared Repository | prod:2, test:1 | outputs;params:ParamName,EnvTarget | 保留聚合导出 |
| `Get-FormatLength` | functions | Shared Repository | prod:1, test:1 | ok | 保留聚合导出 |
| `Get-FunctionHelp` | help | Compatibility | doc, test:1 | outputs | 保留兼容并维持弃用提示 |
| `Get-GitIgnorePatterns` | git | Shared Repository | internal:1, test:1 | params:GitIgnorePath | 保留聚合导出 |
| `Get-GitignoreRules` | filesystem | Private | internal:1, test:1 | ok | 停止子模块与聚合导出 |
| `Get-GpuInfo` | hardware | Stable User | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `Get-HistoryCommandRank` | functions | Stable User | test:1 | ok | 保留聚合导出 |
| `Get-ItemColor` | filesystem | Private | internal:1 | ok | 停止子模块与聚合导出 |
| `Get-LineBreak` | string | Shared Repository | prod:1, test:1 | ok | 保留聚合导出 |
| `Get-NeedBinaryDigit` | functions | Stable User | test:1 | ok | 保留聚合导出 |
| `Get-OperatingSystem` | os | Shared Repository | doc, prod:1, internal:5, test:1 | ok | 保留聚合导出 |
| `Get-OssObjectInfo` | oss | Stable User | test:1 | ok | 保留聚合导出 |
| `Get-OssObjectList` | oss | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `Get-PackageInstallCommand` | install | Private | internal:1, test:1 | ok | 停止子模块与聚合导出 |
| `Get-PathAddHint` | env | Shared Repository | prod:1, test:1 | ok | 保留聚合导出 |
| `Get-PortProcess` | network | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `Get-ReversedMap` | functions | Stable User | test:1 | ok | 保留聚合导出 |
| `Get-ScriptFolder` | functions | Stable User | test:1 | ok | 保留聚合导出 |
| `Get-StableJsonKey` | json | Shared Repository | prod:1, test:1 | ok | 保留聚合导出 |
| `Get-SystemMemoryInfo` | hardware | Stable User | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `Get-Tree` | filesystem | Stable User | doc, example:1, internal:1, test:1 | ok | 保留聚合导出 |
| `Get-TreeObject` | filesystem | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `Get-WslDockerCandidateDistro` | docker | Private | internal:1 | ok | 停止子模块与聚合导出 |
| `Get-WslDockerEnvironmentArgument` | docker | Private | internal:1, test:1 | ok | 停止子模块与聚合导出 |
| `Import-EnvPath` | env | Stable User | internal:1, test:1 | outputs | 保留聚合导出 |
| `Install-Dotenv` | env | Stable User | doc, test:1 | params:EnvTarget,Path | 保留聚合导出 |
| `Install-ExecutableFile` | install | Shared Repository | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `Install-Font` | font | Stable User | doc | ok | 保留聚合导出 |
| `Install-PackageManagerApps` | install | Shared Repository | prod:5, profile:1, test:1 | ok | 保留聚合导出 |
| `Install-RequiredModule` | install | Shared Repository | doc, profile:1, test:1 | ok | 保留聚合导出 |
| `Invoke-DockerComposeCommand` | docker | Shared Repository | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `Invoke-FzfHistorySmart` | functions | Stable User | internal:1, test:1 | ok | 保留聚合导出 |
| `Invoke-NativeCommand` | process | Shared Repository | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `Invoke-WithCache` | cache | Stable User | doc, profile:2, test:1 | ok | 保留聚合导出 |
| `Invoke-WithFileCache` | cache | Shared Repository | doc, profile:1, test:1 | ok | 保留聚合导出 |
| `Invoke-WithScopedEnvironment` | scoped-environment | Shared Repository | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `Invoke-WslDocker` | docker | Stable User | doc, internal:1 | ok | 保留聚合导出 |
| `New-7ZipExcludeArgs` | git | Stable User | test:1 | params:AdditionalExcludes,GitIgnorePath | 保留聚合导出 |
| `New-BackupSnapshot` | filesystem | Shared Repository | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `New-CommandLogFile` | process | Shared Repository | prod:1, test:1 | ok | 保留聚合导出 |
| `New-OssContext` | oss | Stable User | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `New-PlatformDescriptor` | os | Shared Repository | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `New-Shortcut` | win | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `New-WebShortcut` | web | Stable User | test:1 | outputs | 保留聚合导出 |
| `Out-ModuleToFile` | pwsh | Diagnostic | no in-repo call | ok | 移出聚合；保留子模块直导 |
| `Publish-OssDirectory` | oss | Stable User | doc, prod:1, test:1 | ok | 保留聚合导出 |
| `Publish-OssObject` | oss | Stable User | doc, prod:1, internal:1, test:1 | ok | 保留聚合导出 |
| `Read-ConfigEnvFile` | reader | Shared Repository | doc, prod:2, internal:1 | ok | 保留聚合导出 |
| `Read-ConfigMarkdownFrontMatter` | reader | Shared Repository | prod:2, internal:1 | ok | 保留聚合导出 |
| `Read-ConfigPowerShellDataFile` | reader | Shared Repository | prod:1, internal:1 | ok | 保留聚合导出 |
| `Read-ConfigSshClientConfig` | reader | Shared Repository | prod:1, test:1 | ok | 保留聚合导出 |
| `Read-JsonHashtableFile` | json | Shared Repository | prod:2, test:1 | ok | 保留聚合导出 |
| `Register-FzfHistorySmartKeyBinding` | functions | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `Remove-FromEnvPath` | env | Stable User | no in-repo call | outputs;params:Path,EnvTarget | 保留聚合导出 |
| `Resolve-ConfigEnvPlaceholder` | convert | Shared Repository | prod:2, internal:1, test:1 | ok | 保留聚合导出 |
| `Resolve-ConfigPath` | convert | Shared Repository | prod:4, internal:1, test:1 | ok | 保留聚合导出 |
| `Resolve-ConfigPlatformValue` | convert | Shared Repository | prod:1, test:1 | ok | 保留聚合导出 |
| `Resolve-ConfigSources` | resolver | Shared Repository | doc, prod:19, internal:1, test:2 | ok | 保留聚合导出 |
| `Resolve-DefaultEnvFiles` | discovery | Shared Repository | doc, prod:2, internal:1, test:1 | ok | 保留聚合导出 |
| `Resolve-NativeExecutablePath` | process | Shared Repository | doc, prod:1, internal:1 | ok | 保留聚合导出 |
| `Resolve-WslDockerDistro` | docker | Private | internal:1 | ok | 停止子模块与聚合导出 |
| `Search-ModuleHelp` | help | Compatibility | doc, internal:1, test:1 | ok | 保留兼容并维持弃用提示 |
| `Select-InteractiveItem` | selection | Shared Repository | prod:2, test:1 | ok | 保留聚合导出 |
| `Select-PackageManagerApps` | install | Shared Repository | prod:4, internal:1, test:2 | ok | 保留聚合导出 |
| `Set-CustomAlias` | wrapper | Stable User | doc, profile:1, test:1 | outputs;params:PassThru,Scope | 保留聚合导出 |
| `Set-EnvPath` | env | Stable User | prod:2, internal:1 | outputs;params:PathStr,EnvTarget | 保留聚合导出 |
| `Set-Proxy` | proxy | Stable User | doc, profile:1, internal:1, test:1 | outputs | 保留聚合导出 |
| `Set-Script` | functions | Stable User | test:1 | params:key,path,value | 保留聚合导出 |
| `Set-SSHKeyAuth` | linux | Stable User | no in-repo call | outputs;params:Passphrase | 保留聚合导出 |
| `Show-TreeItem` | filesystem | Private | internal:1 | outputs;params:GitignoreRules | 停止子模块与聚合导出 |
| `Start-Ipython` | functions | Stable User | no in-repo call | ok | 保留聚合导出 |
| `Start-Proxy` | proxy | Stable User | doc | outputs | 保留聚合导出 |
| `Start-PSReadline` | functions | Stable User | no in-repo call | ok | 保留聚合导出 |
| `Sync-PathFromBash` | env | Stable User | doc, profile:1, test:2 | outputs;params:CacheSeconds,ThrowOnFailure | 保留聚合导出 |
| `Test-Administrator` | os | Shared Repository | doc, prod:2, test:1 | ok | 保留聚合导出 |
| `Test-ApplicationInstalled` | test | Shared Repository | prod:3, internal:1, test:1 | ok | 保留聚合导出 |
| `Test-ArrayNotNull` | test | Private | test:1 | ok | 停止子模块与聚合导出 |
| `Test-DirectoryInPath` | env | Shared Repository | prod:2, test:1 | ok | 保留聚合导出 |
| `Test-DockerComposeAvailable` | docker | Shared Repository | doc | ok | 保留聚合导出 |
| `Test-DockerDesktopDaemonAvailable` | docker | Private | doc, internal:1 | ok | 停止子模块与聚合导出 |
| `Test-EXEProgram` | test | Shared Repository | doc, prod:2, profile:2, internal:1, test:1 | ok | 保留聚合导出 |
| `Test-Font` | font | Stable User | test:1 | params:Name | 保留聚合导出 |
| `Test-GitignoreMatch` | filesystem | Private | internal:1, test:1 | ok | 停止子模块与聚合导出 |
| `Test-HelpSearchPerformance` | help | Diagnostic | test:1 | ok | 移出聚合；保留子模块直导 |
| `Test-HomebrewFormula` | test | Private | internal:1, test:1 | ok | 停止子模块与聚合导出 |
| `Test-MacOSApplicationInstalled` | test | Private | internal:1, test:1 | ok | 停止子模块与聚合导出 |
| `Test-MacOSCaskApp` | test | Private | internal:1, test:1 | ok | 停止子模块与聚合导出 |
| `Test-ModuleInstalled` | install | Shared Repository | prod:1, internal:1, test:1 | ok | 保留聚合导出 |
| `Test-OssObject` | oss | Stable User | internal:1, test:1 | ok | 保留聚合导出 |
| `Test-PackageManagerAppCatalog` | install | Shared Repository | prod:7, test:1 | ok | 保留聚合导出 |
| `Test-PathHasExe` | test | Shared Repository | prod:1, test:1 | ok | 保留聚合导出 |
| `Test-PortOccupation` | network | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `Test-WindowsDockerDaemonAvailable` | docker | Private | no in-repo call | ok | 停止子模块与聚合导出 |
| `Test-WslDockerEngineAvailable` | docker | Private | doc, internal:1 | ok | 停止子模块与聚合导出 |
| `Uninstall-Font` | font | Stable User | doc | ok | 保留聚合导出 |
| `Update-Semver` | functions | Stable User | test:1 | params:UpdateType,Version | 保留聚合导出 |
| `Wait-ForURL` | network | Stable User | doc, test:1 | ok | 保留聚合导出 |
| `Write-CommandLogLine` | process | Shared Repository | prod:2, internal:1, test:1 | ok | 保留聚合导出 |
| `Write-JsonFileAtomic` | json | Shared Repository | prod:2, test:1 | ok | 保留聚合导出 |
