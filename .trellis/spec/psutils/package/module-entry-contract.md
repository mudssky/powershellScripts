# PsUtils Module Entry Contract

> 本规范记录 `psutils` 聚合模块的入口、运行时版本、导出一致性与兼容 shim 契约。

## Scenario: Canonical Module Import and Export Surface

### 1. Scope / Trigger

- Trigger：修改 `psutils/psutils.psd1`、`psutils/index.psm1`、NestedModules、子模块公共导出或仓库内聚合模块导入路径。
- Scope：`psutils.psd1` 是规范模块入口；`index.psm1` 只服务旧脚本迁移，不是第二份模块实现。
- Design intent：让 manifest 声明、实际命令、子模块依赖和仓库消费者保持同一契约，防止单独子模块测试通过但聚合入口失效。

### 2. Signatures

- Recommended manifest import：
  - `Import-Module ./psutils/psutils.psd1 -Force`
- Recommended directory import：
  - `Import-Module ./psutils -Force`
- Deprecated compatibility import：
  - `Import-Module ./psutils/index.psm1 -Force`
- Runtime metadata：
  - `PowerShellVersion = '7.4'`
  - `CompatiblePSEditions = @('Core')`

### 3. Contracts

- 目录导入必须解析到 `psutils/psutils.psd1`。
- `index.psm1` 必须输出弃用 warning，并把 manifest 导入调用方可见作用域；shim 返回后公共命令仍可调用。
- `FunctionsToExport` 中的名称必须唯一，且排序后与 `Get-Command -Module psutils -CommandType Function` 完全一致。
- manifest 不得声明不存在的函数，也不得用同名 nested module 导出来静默覆盖不同参数契约。
- 同一公共命令只有一个权威实现；旧参数名通过 parameter alias 或兼容 wrapper 保留。
- 直接导入存在跨模块调用的 nested module 时，该模块必须自行导入直接依赖，不能依赖聚合 manifest 偶然提供兄弟命令。
- 新的生产脚本、测试和示例不得导入 `index.psm1`。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| PowerShell 版本低于 7.4 | manifest 或 `#requires` 拒绝导入 |
| PSEdition 为 Desktop | manifest 不声明兼容，不提供 5.1 fallback |
| `FunctionsToExport` 含重复名称 | `moduleContract.Tests.ps1` 失败 |
| manifest 声明的函数未实际导出 | 聚合命令集合对比失败 |
| nested modules 导出同名但参数不同的函数 | 契约测试失败；合并为单一权威实现 |
| 导入 `index.psm1` | 输出弃用 warning，随后公共命令在调用方会话可见 |
| 生产脚本或示例继续导入 `index.psm1` | 可发现性检查失败，迁移到 manifest 或目录入口 |
| 直接导入 nested module 后调用其跨模块能力 | 直接依赖必须可见，不能要求调用方先导入聚合模块 |

### 5. Good/Base/Bad Cases

- Good：生产脚本直接导入 `psutils.psd1`，契约测试同时校验 metadata、导出集合和关键参数 alias。
- Good：`win.psm1` 独占 `New-Shortcut` 实现，并用 `Path`、`Destination` alias 兼容旧调用。
- Base：旧个人脚本暂时导入 `index.psm1`，收到弃用 warning 后仍能使用公共命令。
- Bad：在 `index.psm1` 复制一份 NestedModules 或导出列表，形成第二个会漂移的模块入口。
- Bad：manifest 写入不存在的导出名，因为 `Test-ModuleManifest` 不一定能发现 nested module 的缺失函数。
- Bad：两个 nested modules 导出同名函数，依赖加载顺序决定最终参数契约。

### 6. Tests Required

- `psutils/tests/moduleContract.Tests.ps1` 必须校验 PowerShell 版本和 PSEdition。
- 测试必须比较 manifest 唯一导出名与实际聚合命令集合。
- 使用独立 `pwsh -NoProfile` 子进程导入 `index.psm1`，断言 warning 和 shim 返回后的命令可见性。
- 测试目录导入实际解析到 `psutils.psd1`。
- 对合并过的同名命令断言权威参数和兼容 alias。
- 修改 nested module 依赖时，增加直接导入消费模块后调用公共函数的测试。

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
