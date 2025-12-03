## Impact Analysis (影响面分析)
- 修改文件: `c:\home\env\powershellScripts\profile\profile.ps1`
- 可能修改: `c:\home\env\powershellScripts\profile\wrapper.ps1`
- 潜在风险: 初始化逻辑与代理环境变量变更会影响现有会话；缓存策略调整可能影响 starship/zoxide 初始化行为

## Step 1: Context Gathering（上下文确认）
- 阅读并确认 `loadModule.ps1` 引入的 `psutils` 模块提供的函数（`Test-ExeProgram`, `Set-CustomAlias`, `Get-CustomAlias`, `Invoke-WithCache`）可用
- 检查 `env.ps1` 是否存在且内容为空，按模板加载（仅在文件存在时）

## Step 2: Implementation（实现优化）
- 修正别名函数日志属性错误：`$alias.name` → `$alias.aliasName`
- 修正描述错误：`df` 的说明改为准确的 duf 描述
- 路径语义与可读性：`Split-Path -Parent $PSScriptRoot` 明确父路径赋值给 `POWERSHELL_SCRIPTS_ROOT`
- 代理变量一致性：当未启用代理时，清空 `http_proxy` 与 `https_proxy`
- 初始化健壮性：在 `Initialize-Environment` 顶部设置 `$ErrorActionPreference = 'Stop'` 并保持 idempotent
- 缓存策略改进：将 starship/zoxide 的 `Invoke-WithCache` 缓存键加入版本号；或缩短缓存时长（如 7 天）以避免陈旧脚本
- 可读性与一致性：将 `$AliasDespPrefix` 统一为更清晰的 `$AliasDescPrefix`（同步所有引用）
- 帮助输出改进：`Show-MyProfileHelp` 环境变量读取统一使用 `Env:` 提示；补充代理开关用法示例
- 兼容性与规范：顶部增加 `#requires -Version 7.0`，路径拼接尽量使用 `Join-Path`

## Step 3: Verification（验证）
- 启动新会话执行 `Initialize-Environment -Verbose`，确认无错误
- 运行 `Show-MyProfileHelp` 检查别名/函数包装输出是否正确
- 验证代理开关：切换 enableProxy 文件存在与否，确认环境变量正确设置/清空
- 如果本机已安装 starship/zoxide，确认初始化无异常且提示正常
- 观察 Profile 加载耗时，确认无明显回归
