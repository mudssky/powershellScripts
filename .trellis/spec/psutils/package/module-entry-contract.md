# PsUtils Module Entry Contract

> 本规范记录 `psutils` 聚合模块的入口、运行时版本、导出一致性与兼容 shim 契约。

## Scenario: Canonical Module Import and Export Surface

### 1. Scope / Trigger

- Trigger：修改 `psutils/psutils.psd1`、`psutils/index.psm1`、NestedModules、子模块公共导出、README、docs、examples 或仓库内聚合模块导入路径。
- Scope：`psutils.psd1` 是规范模块入口；`index.psm1` 只服务旧脚本迁移，不是第二份模块实现。用户文档和活动示例必须描述同一入口与运行时契约。
- Design intent：让 manifest 声明、实际命令、子模块依赖和仓库消费者保持同一契约，防止单独子模块测试通过但聚合入口失效。

### 2. Signatures

- Recommended manifest import：
  - `Import-Module ./psutils/psutils.psd1 -Force`
- Recommended directory import：
  - `Import-Module ./psutils -Force`
- Deprecated compatibility import：
  - `Import-Module ./psutils/index.psm1 -Force`
- Documentation validation：
  - `pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode qa -Path ./psutils/tests/documentation.Tests.ps1`
- API boundary validation：
  - `pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode qa -Path ./psutils/tests/apiBoundary.Tests.ps1`
- Diagnostic direct import：
  - `Import-Module ./psutils/modules/<diagnostic-module>.psm1 -Force`
- Runtime metadata：
  - `PowerShellVersion = '7.4'`
  - `CompatiblePSEditions = @('Core')`

### 3. Contracts

- 目录导入必须解析到 `psutils/psutils.psd1`。
- `index.psm1` 必须输出弃用 warning，并把 manifest 导入调用方可见作用域；shim 返回后公共命令仍可调用。
- `FunctionsToExport` 中的名称必须唯一，且排序后与 `Get-Command -Module psutils -CommandType Function` 完全一致。
- manifest 不得声明不存在的函数，也不得用同名 nested module 导出来静默覆盖不同参数契约。
- 子模块必须使用显式 `Export-ModuleMember -Function <name...>`；禁止 wildcard 导出，避免新增 helper 时意外扩大公共面。
- 聚合 manifest 只导出 Stable User、Shared Repository 和 Compatibility 命令。Diagnostic 仅保留对应子模块直导入口，Private 不得从聚合或子模块导出。
- 模块导入不得创建无必要的 global 变量；只服务模块实现的默认值使用 script scope。
- 聚合公共函数必须提供可由 `Get-Help -Full` 读取的 comment-based help：每个显式参数都有 `.PARAMETER` 说明，并声明 `.OUTPUTS`；无结构化返回时写 `None`。
- 同一公共命令只有一个权威实现；旧参数名通过 parameter alias 或兼容 wrapper 保留。
- 直接导入存在跨模块调用的 nested module 时，该模块必须自行导入直接依赖，不能依赖聚合 manifest 偶然提供兄弟命令。
- 新的生产脚本、测试和示例不得导入 `index.psm1`。
- README 的模块版本、PowerShell 要求和入口必须与 manifest 一致；不得手工维护未受测试约束的模块数量或不存在的能力列表。
- 已弃用的帮助搜索 API 只能出现在迁移说明中，不得作为 README 或活动示例的推荐调用。
- 活动示例必须通过 PowerShell AST 解析；`Import-Module` 的字面量路径必须存在。可安全执行的示例还必须在独立 `pwsh -NoProfile` 子进程中完成 smoke 检查。
- 会下载网络资源、修改系统配置、清理用户级数据或依赖失效路径的 demo 不得作为活动示例；仅具历史价值时迁移到根 `archive/<原路径>` 并登记 `archive/index.json`。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| PowerShell 版本低于 7.4 | manifest 或 `#requires` 拒绝导入 |
| PSEdition 为 Desktop | manifest 不声明兼容，不提供 5.1 fallback |
| `FunctionsToExport` 含重复名称 | `moduleContract.Tests.ps1` 失败 |
| manifest 声明的函数未实际导出 | 聚合命令集合对比失败 |
| 子模块使用 wildcard 导出 | `apiBoundary.Tests.ps1` 失败；改为精确导出列表 |
| Private helper 仍可从子模块获取 | API 边界测试失败；测试通过 `InModuleScope` 访问内部实现 |
| Diagnostic 命令进入聚合 manifest | API 边界测试失败；仅允许直导对应子模块 |
| 公共函数缺少参数或返回值说明 | API 边界测试失败；补齐可被 `Get-Help -Full` 解析的帮助块 |
| 导入模块创建实现专用 global 变量 | API 边界测试失败；改为 script scope |
| nested modules 导出同名但参数不同的函数 | 契约测试失败；合并为单一权威实现 |
| 导入 `index.psm1` | 输出弃用 warning，随后公共命令在调用方会话可见 |
| 生产脚本或示例继续导入 `index.psm1` | 可发现性检查失败，迁移到 manifest 或目录入口 |
| 直接导入 nested module 后调用其跨模块能力 | 直接依赖必须可见，不能要求调用方先导入聚合模块 |
| README 版本或 PowerShell 要求与 manifest 不一致 | `documentation.Tests.ps1` 失败，先以 manifest 为真源修正文档 |
| README 把弃用帮助 API 作为代码示例 | 文档契约测试失败，改用 `Get-Help` / `Get-Command` |
| example 存在语法错误或失效字面量导入路径 | AST 或路径断言失败，不进入活动示例集 |
| demo 会清理用户缓存或修改系统状态 | 不纳入自动执行；修成受控 `-WhatIf` 流程或冷归档 |

### 5. Good/Base/Bad Cases

- Good：生产脚本直接导入 `psutils.psd1`，契约测试同时校验 metadata、导出集合和关键参数 alias。
- Good：聚合 manifest 导出稳定 API，benchmark 通过直导子模块使用 Diagnostic 命令，内部 helper 测试使用 `InModuleScope`。
- Good：模块默认值保存在 `$script:` 作用域，公共函数的 `.PARAMETER` 和 `.OUTPUTS` 可由 `Get-Help -Full` 读取。
- Good：`win.psm1` 独占 `New-Shortcut` 实现，并用 `Path`、`Destination` alias 兼容旧调用。
- Good：README 从 manifest 同步 `ModuleVersion`、`PowerShellVersion` 和规范入口，示例由 `documentation.Tests.ps1` 做 AST 与子进程 smoke 检查。
- Base：旧个人脚本暂时导入 `index.psm1`，收到弃用 warning 后仍能使用公共命令。
- Base：诊断命令继续存在，但调用方必须明确直导所属子模块，不获得聚合兼容承诺。
- Bad：子模块 wildcard 导出，或为了测试内部 helper 而把它重新加入公共导出。
- Bad：导入模块时写入 `$Global:` 默认值，或公共帮助只存在于无法被 `Get-Help` 识别的位置。
- Bad：在 `index.psm1` 复制一份 NestedModules 或导出列表，形成第二个会漂移的模块入口。
- Bad：manifest 写入不存在的导出名，因为 `Test-ModuleManifest` 不一定能发现 nested module 的缺失函数。
- Bad：两个 nested modules 导出同名函数，依赖加载顺序决定最终参数契约。
- Bad：README 手写“模块数量”和旧版本号，example 使用不存在的相对路径，demo 默认清理整个用户缓存目录。

### 6. Tests Required

- `psutils/tests/moduleContract.Tests.ps1` 必须校验 PowerShell 版本和 PSEdition。
- `psutils/tests/apiBoundary.Tests.ps1` 必须校验聚合分类数量、Private/Diagnostic 边界、精确导出和无 global 导入副作用。
- API 边界测试必须遍历聚合公共函数，通过 `Get-Help -Full` 断言全部显式参数具有说明且 `.OUTPUTS` 非空。
- 私有 helper 的既有单元测试必须改用 `InModuleScope <module>`，不得以恢复导出换取测试可见性。
- 测试必须比较 manifest 唯一导出名与实际聚合命令集合。
- 使用独立 `pwsh -NoProfile` 子进程导入 `index.psm1`，断言 warning 和 shim 返回后的命令可见性。
- 测试目录导入实际解析到 `psutils.psd1`。
- 对合并过的同名命令断言权威参数和兼容 alias。
- 修改 nested module 依赖时，增加直接导入消费模块后调用公共函数的测试。
- `psutils/tests/documentation.Tests.ps1` 必须从 manifest 读取版本和运行时事实，并拒绝已知过时声明。
- 文档测试必须用 PowerShell AST 解析所有活动 example，验证字面量模块路径存在，并在独立子进程执行标记为安全的 smoke 场景。
- 归档活动 demo 后运行 `project-archive` 的 `check`，确认 `archive/index.json` 与镜像路径一致。

### 7. Wrong vs Correct

#### Wrong

```powershell
# index.psm1 再维护一套加载与导出清单
Import-Module ./modules/os.psm1 -Force
Import-Module ./modules/hardware.psm1 -Force
Export-ModuleMember -Function Get-OperatingSystem, Get-GpuInfo
```

问题：manifest 和脚本入口会分别演进，测试其中一个入口不能证明另一个可用。

#### Correct

```powershell
# 生产脚本使用唯一规范入口
Import-Module ./psutils/psutils.psd1 -Force

# 旧入口只做带提示的调用方作用域转发
Write-Warning 'psutils/index.psm1 已弃用，请改为导入 psutils.psd1 或 psutils 目录。'
Import-Module (Join-Path $PSScriptRoot 'psutils.psd1') -Force -Global
```

理由：manifest 是模块结构和公共面的单一事实来源，shim 只承担迁移兼容，不复制实现。

#### Wrong

```powershell
$Global:DefaultPrefix = '[custom] '
Export-ModuleMember -Function *
```

问题：导入模块污染调用方全局状态，并让后续新增 helper 自动成为公共 API。

#### Correct

```powershell
$script:DefaultPrefix = '[custom] '
Export-ModuleMember -Function Get-CustomAlias, Set-CustomAlias
```

理由：模块实现状态留在 script scope，公共面由可审阅的精确列表控制；内部函数通过 `InModuleScope` 测试。

#### Wrong

```markdown
- 版本：0.0.1
- PowerShell：5.1+

Search-ModuleHelp -SearchTerm config
```

问题：文档复制了会漂移的 manifest 事实，并继续推荐已弃用 API。

#### Correct

```markdown
运行时版本和公共导出以 `psutils.psd1` 为唯一事实来源。

Get-Command -Module psutils -Name '*Config*'
Get-Help Resolve-ConfigSources -Full
```

理由：用户路径使用 PowerShell 标准发现机制，版本与入口由契约测试持续对齐 manifest。
