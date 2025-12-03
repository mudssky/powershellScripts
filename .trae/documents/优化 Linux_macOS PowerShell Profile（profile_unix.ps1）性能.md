## 目标
- 将 `c:\home\env\powershellScripts\profile\profile_unix.ps1` 在 Linux/macOS 的冷启动时间降至 300–500ms 区间（工具安装与否会影响最终值）。
- 应用与 Windows 版一致的三大策略：文件级缓存、惰性初始化、可配置跳过。

## 影响面分析（Impact Analysis）
- 修改文件：`c:\home\env\powershellScripts\profile\profile_unix.ps1`
- 新增目录：`c:\home\env\powershellScripts\profile/.cache/`（缓存 `starship/zoxide` 初始化脚本）
- 风险：首次使用 zoxide 时由“按需加载”改为延迟加载（行为等价）；starship 由字符串解析改为 dot-source 缓存脚本（等价但更快）。

## 现状洞察（热点定位）
- 工具初始化集中在 `profile_unix.ps1:156-171`：
  - starship：`Invoke-Expression (&starship init powershell)`（字符串解析）。
  - zoxide：`Invoke-Expression (zoxide init powershell | Out-String)`（字符串解析）。
  - fnm：字符串管道执行。
- PATH 同步与 env.ps1 加载：`profile_unix.ps1:139-155`（必要但轻量）。
- 别名设置在两个函数：`Set-AliasProfile` 与 `Set-CustomAliasesProfile`（可合并或保持现状）。

## 优化方案
### 1) 文件级缓存替换字符串解析
- 新增轻量助手：`Invoke-WithFileCache`（同 Windows 版本），将 `starship init powershell` 与 `zoxide init powershell` 的输出写入 `.cache/*.ps1`，每次会话用 dot-source 加载。
- starship：生成 `starship-init-powershell.ps1` → `. <缓存文件>`。
- zoxide：生成 `zoxide-init-powershell.ps1` → `. <缓存文件>`。
- 预期收益：避免每次会话字符串解析与管道开销，提升稳定性与速度。

### 2) 惰性初始化（Lazy Init）
- 定义 `z` 占位函数：首次调用时 dot-source `zoxide-init` 缓存脚本并重载自身，再将参数透传；后续调用零额外开销。
- starship：保持会话启动即加载（提示符依赖），但允许通过参数跳过（下一条）。

### 3) 可配置跳过（Minimal 模式与细粒度）
- 扩展 `Initialize-Environment` 参数：`-SkipTools`、`-SkipStarship`、`-SkipZoxide`、`-SkipAliases`、`-Minimal`。
- 默认策略：
  - 若存在 `"$PSScriptRoot/minimal"` 或环境变量 `POWERSHELL_PROFILE_MINIMAL=1`，启用 Minimal（跳过工具与别名）。
- 预期收益：在 CI/远程/非交互场景显著降低冷启动时间。

### 4) 微优化与一致性
- 编码设置：在 Unix 脚本中同样使用 `[System.Text.UTF8Encoding]::new($false)`（若需要设置编码，统一方式）。
- fnm：保留，但可通过 `-SkipTools` 跳过；同时将其改为文件缓存或维持当前（建议维持当前，因输出较短）。
- 安装提示：保持 Homebrew/Linuxbrew 提示，但避免冗长字符串拼接开销（仅 Verbose/必要时输出）。
- 别名设置：保留现状；可考虑统一到一个函数，但为避免风险，先只做性能相关改造。

### 5) 计时与验证
- 在脚本末尾加入耗时输出（与 Windows 版一致的模式），或提供简单基准示例：
  - `Measure-Command { pwsh -NoLogo -NoProfile -File ./profile_unix.ps1 }`。
- 验证模式：默认、`-Minimal`、`-SkipZoxide`、首次调用 `z` 的懒加载链路。

## 交付内容
- 更新后的 `profile_unix.ps1`：包含 `Invoke-WithFileCache`、惰性 `z`、跳过参数、Minimal 模式、微优化与使用说明。
- 新增 `.cache/` 目录与自动生成的 `*.ps1` 缓存脚本（由脚本运行自动生成）。

## 回滚策略
- 参数门控：可随时通过 `-SkipTools/-Minimal` 回退为更轻量行为。
- 删除 `.cache/*.ps1` 即可刷新缓存，恢复即时生成。

## 验证与预期收益
- 预计默认模式冷启动下降；`Minimal` 模式显著提升启动速度。
- zoxide 使用体验不变，但仅在真正需要时加载。

请确认上述方案，我将据此实现、验证并提交优化版本。