## 1. 现状确认与设计落地

- [x] 1.1 确认 `psutils` 中工具探测函数的实际导出名称（`Test-EXEProgram` 或其他）
- [x] 1.2 盘点 `user_aliases.ps1` 中需要改为 `command + commandArgs` 的条目
- [x] 1.3 明确错误提示的最小格式（包含脚本/模块路径与异常消息）

## 2. 关键实现调整（保持行为一致）

- [x] 2.1 `profile/loadModule.ps1`：为 `Import-Module` 加最小 `try/catch` 并输出清晰来源
- [x] 2.2 `profile/profile.ps1`：为 dot-source 三个脚本增加轻量错误提示（不做 `Test-Path`）
- [x] 2.3 `profile/wrapper.ps1`：统一工具探测函数命名与调用
- [x] 2.4 `profile/user_aliases.ps1`：调整别名对象结构（`command` + `commandArgs`）
- [x] 2.5 `profile/profile.ps1`：别名执行逻辑改为结构化调用（`& $cmd @commandArgs @($args)`）

## 3. 可选维护性提升（低风险）

- [x] 3.1 `profile/loadModule.ps1`：`PSModulePath` 去重
- [x] 3.2 `profile/wrapper.ps1`：`Get-Help` 结果缓存（或轻量降级策略）
- [x] 3.3 `profile/wrapper.ps1`：`Add-CondaEnv` 支持额外路径或可配置路径

## 4. 手动验证

- [x] 4.1 在 Windows / Linux 各启动一次 profile，确认无报错
- [x] 4.2 验证别名行为（含带参数的别名）与 `yaz` 函数正常
- [x] 4.3 验证错误提示是否“可定位且不噪音”
