## 目标
- 在 `pwsh` 中“直接执行”脚本，同时提升项目的可维护性、跨平台性与可分发性。

## 方案总览
- 模块化 + 自动加载：将通用函数沉淀为模块，依赖 PowerShell 的模块自动加载，调用即用。
- `scripts/` 可执行包装：为模块函数提供薄包装脚本，保持 CLI 体验统一，集中管理 PATH。
- Profile 注入：在用户或仓库 Profile 中按需注入函数/别名，实现“无路径直接调用”。
- PowerShellGet 安装脚本：用 `New/Save/Install-Script` 管理脚本，统一安装位置与 PATH。
- Unix Shebang：在跨平台脚本顶部使用 `#!/usr/bin/env pwsh` 并 `chmod +x`，原生可执行。
- 可选：包管理器/符号链接（Scoop/Chocolatey/symlink），用于分发与本地 shim（需确认后再做）。
- 执行策略与签名：在受限环境下采用签名或受信路径，保证可执行性与安全性。

## 推荐目录结构
- `psutils/`：模块根目录，包含 `psutils.psd1` 与 `index.psm1`，按 `Public/`、`Private/` 分层。
- `scripts/`：仅放可直接执行的 CLI 脚本，名称即命令名；内部调用模块函数。
- `profile/`：仓库级 Profile（Windows/Unix），负责加载模块与设置 PATH/PSModulePath。
- `bin/`（可选）：给 PATH 使用的统一入口，脚本或符号链接集中于此，避免污染仓库根。

## 实施路径 A：模块化 + 自动加载（推荐）
- 将复用逻辑集中到模块：按照已有 `psutils` 结构导出公共函数（`Export-ModuleMember`）。
- 配置模块搜索路径：将仓库根或模块目录追加到 `PSModulePath`（区别于 PATH）。
  - 示例：`$env:PSModulePath = "$env:PSModulePath;c:\home\env\powershellScripts"`
- 使用自动加载：直接调用导出的函数名即可，无需手动 `Import-Module`。
- 优势：命令名即函数名、强类型参数、帮助系统集成、易测试与复用。

## 实施路径 B：`scripts/` 薄包装 CLI
- 在 `scripts/` 中为核心功能提供同名 `*.ps1` 包装，内部仅做参数解析与调用模块函数。
- 将 `scripts/` 而非仓库根加入 PATH，保持根目录整洁。
- 跨平台：Windows 走 PATH，Unix 走 Shebang + 可执行位；脚本内部统一调用模块。
- 优势：CLI 用户体验稳定，模块与可执行层清晰分离。

## 实施路径 C：Profile 注入（仓库或用户级）
- 在 `profile/profile.ps1` 与 `profile/profile_unix.ps1` 内：
  - 设置 `PSModulePath` 并 `Import-Module psutils`（或依赖自动加载）。
  - 定义常用命令的 `function` 或 `Set-Alias`，实现“直接调用”。
- 优势：个人环境集成度高；风险：耦合到用户环境，团队可控性较弱。

## 实施路径 D：PowerShellGet 安装脚本
- 为可执行脚本添加清单：`New-ScriptFileInfo -Path scripts/YourCmd.ps1 -Version 1.0.0 ...`
- 保存与安装到标准位置：`Save-Script` → `Install-Script`（通常安装到用户脚本目录）。
- 管理与更新：`Get-InstalledScript`、`Update-Script`，PATH 使用标准脚本目录。
- 优势：安装/更新一致；适合在多机器复用；团队分发便捷。

## 实施路径 E：Unix Shebang（跨平台）
- 在需要跨平台直接执行的脚本顶部添加：``#!/usr/bin/env pwsh``。
- 赋予可执行位：`chmod +x scripts/yourcmd.ps1`，即可 `./yourcmd.ps1` 直接运行。
- 与 PATH 配合：将 `scripts/` 添加到 `PATH`，或在 `bin/` 建立链接。

## 可选路径 F：包管理器/符号链接（需许可）
- 使用 Scoop/Chocolatey 发布脚本，生成 shim 自动出现在 PATH。
- 或在 `bin/` 下用符号链接指向仓库脚本：`New-Item -ItemType SymbolicLink -Path ~/bin/yourcmd.ps1 -Target <repo>/scripts/yourcmd.ps1`。

## 执行策略与安全
- 在受限环境可采用：签名脚本（代码签名证书）、受信目录（将 `scripts/` 设为可信路径）、或使用 `RemoteSigned` 并确保本地生成。
- 避免在脚本中泄露敏感信息；参数默认值避免敏感数据；输出使用 `Write-Output`。

## 验证方案
- 模块化：`Get-Module -ListAvailable psutils`、`Get-Command -Module psutils`、直接调用导出函数。
- `scripts/`：`Get-Command yourcmd` 返回 `Application` 或 `ExternalScript`，`yourcmd -?` 展示帮助。
- Profile：启动新会话验证函数/别名是否生效，`$env:PSModulePath` 是否包含仓库路径。
- PowerShellGet：`Install-Script yourcmd` 后，检查标准脚本目录是否在 PATH 并能直接调用。
- Unix：`./yourcmd.ps1` 在 WSL/Linux/macOS 可直接运行（需 `pwsh` 已安装）。

## 推荐与取舍
- 推荐组合：模块化（自动加载） + `scripts/` 薄包装 + Profile 加载器。
  - 开发友好：模块便于测试复用；CLI 与用户体验稳定；环境集成可控。
  - 分发友好：后续可平滑升级为 PowerShellGet/包管理器方案。

## 下一步
- 如确认上述方向：
  - 整理 `psutils` 导出面与帮助文档（保持 Verb-Noun）。
  - 规范化 `scripts/` 包装模板，统一参数/日志/错误处理。
  - 在 `profile/` 中补充加载器与路径设置（Windows/Unix 双栈）。
- 如需分发能力，再追加 PowerShellGet 清单与安装脚本的自动化。