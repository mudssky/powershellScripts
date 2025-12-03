## 目标
- 将 Windows/Unix Profile 中的 `Invoke-WithFileCache` 提取为通用模块函数，避免重复实现、统一维护。
- 在 `psutils/tests` 增加两个基准测试，分别测量 Windows 与 Unix Profile 的加载耗时（含 Minimal 模式）。

## 影响面分析
- 修改文件：`psutils/modules/cache.psm1`、`psutils/psutils.psd1`、`profile/profile.ps1`、`profile/profile_unix.ps1`。
- 新增文件：`psutils/tests/profile_windows.Tests.ps1`、`psutils/tests/profile_unix.Tests.ps1`。
- 风险：模块导出函数名变更需与 Profile 引用一致；缓存目录参数默认值需清晰避免误写到模块目录。

## 方案细节
- 在 `psutils/modules/cache.psm1` 中新增函数 `Invoke-WithFileCache`：
  - 参数：`Key`、`MaxAge`、`Generator`、`BaseDir`（可选，默认使用集中缓存目录 `Get-CacheBaseDirectory()` 的子目录 `profile_scripts/`）。
  - 行为：根据 Key 在 `BaseDir` 下生成/更新 `*.ps1` 缓存文件并返回其绝对路径；命中有效期则直接返回路径。
  - 导出：在 `Export-ModuleMember` 与 `psutils.psd1` 的 `FunctionsToExport` 中加入。
- 修改两个 Profile：移除内联的同名函数定义，改为调用模块版本，并显式传入 `BaseDir = (Join-Path $PSScriptRoot '.cache')` 保持现有 `.cache` 位置不变。
- 增加基准测试：
  - `profile_windows.Tests.ps1`：仅在 `$IsWindows` 运行，分别测量默认与 Minimal 模式的加载耗时，输出到测试日志；断言耗时为非负并小于一个宽松阈值（如 10000ms），避免环境波动导致失败。
  - `profile_unix.Tests.ps1`：仅在 `$IsLinux` 或 `$IsMacOS` 运行，测量 Unix Profile 的默认与 Minimal 模式的加载耗时，断言同上。

## 验证
- 运行现有测试套件，确保新增测试通过，Profile 正常加载、starship/zoxide 缓存脚本生成与 dot-source 行为正确。
- 手动测量并对比默认与 Minimal 模式耗时，确保日志可读。

## 回滚
- 若出现问题，可在两个 Profile 中临时恢复内联函数定义或将 `BaseDir` 切换为集中缓存目录；模块函数不影响现有 `Invoke-WithCache`。