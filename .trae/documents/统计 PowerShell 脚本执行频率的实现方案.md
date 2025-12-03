## 原因与目标

* 当前 `profile/profile.ps1#L8-14` 通过 `loadModule.ps1` 执行 `Import-Module psutils`，而 `psutils.psd1` 的 `NestedModules` 会一次性加载 19 个子模块，导致启动阶段不必要的 IO 与解析开销。

* 启动阶段实际只用到少量函数：`Test-EXEProgram`（test.psm1）、`Invoke-WithFileCache`（cache.psm1）、`Set-CustomAlias`/`Get-CustomAlias`（wrapper.psm1）。

* 目标：在不影响功能与测试的前提下，将启动时的模块加载降到“最小必要集合”，其余按需（首次调用时）再加载。

## Plan

* [ ] Impact Analysis（影响面分析）

  * 修改文件：`profile/loadModule.ps1`

  * 可选修改：`profile/profile.ps1`（追加 `PSModulePath` 以便后续自动加载完整模块）

  * 风险：极低；仅改变启动阶段的加载策略，不改动函数语义

* [ ] Step 1: Context Gathering（上下文获取）

  * 已确认 `psutils.psd1` 使用 `NestedModules` 全量导入；`index.psm1` 无顶层执行逻辑

  * `profile` 启动实际使用的函数来源于 `test.psm1`、`cache.psm1`、`wrapper.psm1`

* [ ] Step 2: Implementation（实现）

  * 将 `profile/loadModule.ps1` 从“导入 `psutils` 整体”改为“按路径仅导入最小必要模块”：

    * `Import-Module "$repo\psutils\modules\test.psm1"`

    * `Import-Module "$repo\psutils\modules\cache.psm1"`

    * `Import-Module "$repo\psutils\modules\wrapper.psm1"`

  * 在加载结束后，如果 `PSModulePath` 未包含 `psutils` 根目录，则追加一次（确保后续首次使用其它函数时可自动加载完整模块）：

    * 将 `c:\home\env\powershellScripts\psutils` 追加到 `PSModulePath`（使用 `Join-Path` + 去重）

* [ ] Step 3: Verification（验证）

  * 运行现有 Pester 测试：`pnpm test`（Windows/Minimal 两项性能基准保持通过）

  * 进行一次交互试用：调用非最小集合中的函数（如 `Get-OperatingSystem`），确认能按需自动加载 `psutils` 完整模块并正常工作。

## 变更细节（示例草案）

* `profile/loadModule.ps1`

  * 旧：`Import-Module (Join-Path $moduleParent 'psutils')`

  * 新：

    * 计算 `psutils\modules` 路径后，分别 `Import-Module` 指定的 `test.psm1`、`cache.psm1`、`wrapper.psm1`

    * 检查 `PSModulePath`，若缺失 `psutils` 根路径则追加（用于后续自动加载完整模块）

## 预期效果

* 默认模式启动时间下降（避免一次性加载 19 个子模块）

* Minimal 模式保持更快（不变）

* 业务函数首次使用时再导入完整模块，平衡“冷启动性能”与“功能完整性”

## 备注

* 不修改 `psutils.psd1`；保持清单导出与函数索引不变，以支持自动加载。

* 若后续需要进一步压缩默认启动时间，可引入“全量导入开关”（如 `POWERSHELL_PROFILE_FULLMODULE=1`）实现可配置策略。

