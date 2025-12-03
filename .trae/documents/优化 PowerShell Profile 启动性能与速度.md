## 目标
- 将 `c:\home\env\powershellScripts\profile\profile.ps1` 的启动耗时尽量降低到 300–500ms 区间（取决于是否启用 starship/zoxide）。
- 通过“惰性初始化 + 文件级缓存 + 可配置跳过”三策略减少每次会话的重复开销。

## 影响面分析
- 修改文件: `c:\home\env\powershellScripts\profile\profile.ps1`
- 新增目录: `c:\home\env\powershellScripts\profile\.cache/`（用于存放生成的初始化脚本）
- 风险: starship/zoxide 首次使用时触发一次性加载，行为与即时加载略有不同；但保持功能等价。

## 现状洞察（热点定位）
- 核心初始化函数：`Initialize-Environment` 在 `profile\profile.ps1:186`。
- 外部工具初始化：
  - starship 初始化在 `profile\profile.ps1:262-266`（使用 `Invoke-WithCache` 后 `Invoke-Expression`）。
  - zoxide 初始化在 `profile\profile.ps1:271-275`（同样用字符串缓存 + `Invoke-Expression`）。
- 别名与函数设置：`Set-AliasProfile` 在 `profile\profile.ps1:149`，循环 5 项开销很小。
- 帮助函数 `Show-MyProfileHelp` 不参与启动开销（仅调用时执行）。
- 结论：主要开销集中在 starship/zoxide 的初始化执行与字符串解析。

## 优化方案
### 1) 文件级缓存替换字符串解析
- 将 `Invoke-Expression` 解析长字符串的方式，改为“生成一次 .ps1 文件 → 每次会话直接 dot-source”。
- 具体：
  - 新增轻量助手：`Invoke-WithFileCache -Key <name> -MaxAge <TimeSpan> -Generator { <生成脚本文本> }`，生成到 `profile/.cache/<key>.ps1` 并返回路径。
  - starship：第一次运行 `starship init powershell` 的输出写入 `profile/.cache/starship-init.ps1`，后续使用 `. "<缓存文件>"`。
  - zoxide：同理，输出写入 `profile/.cache/zoxide-init.ps1` 并 dot-source。
- 预期收益：避免每次会话的长字符串 `Invoke-Expression` 解析与管道成本，文件加载速度更稳定。

### 2) 惰性初始化（Lazy Init）
- zoxide：设为“首次使用才加载”的模式。
  - 定义轻量占位函数 `z`：第一次调用时 dot-source `zoxide-init.ps1` 并重载自身为真正的 `z`，随后执行用户输入参数；后续调用不再有额外成本。
  - 对 `zoxide query/add/remove` 的函数别名不变；若首次调用这些命令，也触发一次性初始化。
- starship：保持会话启动即加载（提示符依赖），但允许通过参数跳过（见下一节）。
- 预期收益：不使用 `z` 则不付初始化成本，交互式体验更快。

### 3) 可配置跳过（Minimal 模式）
- 扩展 `Initialize-Environment` 的参数：
  - `-SkipTools`：跳过所有外部工具初始化（starship/zoxide/sccache）。
  - `-SkipStarship`：仅跳过 starship。
  - `-SkipZoxide`：仅跳过 zoxide（配合懒加载占位也可选择启用）。
  - `-SkipAliases`：跳过别名/函数创建（用于极致最小化）。
  - `-Minimal`：等价于 `-SkipTools -SkipAliases`，用于 CI/远程会话等。
- 默认策略：
  - 若存在 `"$PSScriptRoot\minimal"` 文件，则自动启用 `-Minimal`。
  - 也可通过环境变量（如 `POWERSHELL_PROFILE_MINIMAL=1`）启用。
- 预期收益：在需要极致冷启动的场景显著降低等待时间。

### 4) 微优化项
- 编码设置：用 `[System.Text.UTF8Encoding]::new($false)` 代替 `New-Object System.Text.UTF8Encoding`，减少反射开销（位置：`profile\profile.ps1:244-246`）。
- 工具检测：保留 `Test-EXEProgram` 数量（当前仅 3 项），但将工具初始化写入 try/catch 前先做参数级跳过检查，避免无意义分支与字符串构建。
- 输出控制：维持 `Write-Verbose`，默认不影响性能；但对较长字符串拼接仅在启用 Verbose 时执行（条件封装）。

## 验证与基线对比
- 基线：使用文件末尾已存在的计时逻辑 `profile\profile.ps1:326-330`，记录首次加载耗时。
- 方案后：
  - 分别在默认模式、`-Minimal` 模式、`-SkipZoxide` 模式下进行 3 次测量，观察平均值与抖动。
  - 验证 starship 提示符正常显示、`z` 首次调用能触发加载且后续零额外开销。
- 额外：若需要，可在新会话用 `Measure-Command { pwsh -NoLogo -NoProfile -Command "& '$PROFILE'" }` 做外部测量。

## 回滚策略
- 所有优化通过参数门控，随时可用 `-SkipTools/-Minimal` 回退为更轻量行为。
- 文件缓存均为生成产物，删除 `profile/.cache/*.ps1` 即可恢复到重新生成状态。

## 交付内容
- 更新后的 `profile\profile.ps1`（含参数与懒加载逻辑、文件缓存辅助函数）。
- 新增 `profile/.cache/` 目录及自动生成的缓存文件。
- 使用说明与可选模式示例（README 或脚本内注释段）。

## 预计收益（经验值）
- 默认模式：减少 `Invoke-Expression` 字符串解析与管道开销，冷启动稳态下降。
- Minimal 模式：在 CI/远程环境显著降低启动时间（工具与别名完全跳过）。
- 用户体验：功能等价，`z` 用时再加载更贴合实际使用习惯。
