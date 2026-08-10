# Shell Profile 集成流程

## 事实来源与路径

| 范围 | 实现入口 | 测试与规范 |
| --- | --- | --- |
| PowerShell 模式、工具初始化 | `profile/profile.ps1`、`profile/features/environment.ps1` | `.trellis/spec/profile/package/profile-runtime.md`、`tests/ProfileInstallHints.Tests.ps1`、`tests/ProfileLoading.Tests.ps1` |
| PowerShell OnIdle 与键位 | `profile/core/loadModule.ps1` | `tests/ProfileLoading.Tests.ps1`、`tests/DeferredLoading.Tests.ps1` |
| Bash/Zsh 共享初始化 | `shell/shared.d/*.sh`、`shell/deploy.sh` | `.trellis/spec/shell-shared/package/index.md`、`scripts/bash/**/*.test.ts` |
| Windows 软件清单 | `profile/installer/apps-config.json`、`windows/pwsh/WindowsInstall.psm1` | `.trellis/spec/infra/windows-install-pipeline.md`、`tests/WindowsInstallPipeline.Tests.ps1` |
| macOS/Linux 软件清单 | `profile/installer/apps-config.json`、平台 `05`/`08` 入口 | `.trellis/spec/infra/macos-install-pipeline.md`、`.trellis/spec/infra/linux-install-pipeline.md`、对应平台测试 |

## 执行顺序

1. 全局搜索目标工具的初始化、补全、hook、环境变量、键位和安装条目，确认不存在第二入口。
2. 判定归属：双 Shell 兼容初始化放 `shell/shared.d`；专属 widget 放 `shell/{bash,zsh}.d`；PowerShell 外部工具只在 Full 的 `profile/features/environment.ps1` 初始化，延迟键位放 `profile/core/loadModule.ps1`。
3. 先定义非交互式、命令缺失、初始化失败和重复加载的行为，再写成功路径。
4. 安装只修改 `profile/installer/apps-config.json`；平台 bucket 等前置扩展通用安装模块，不创建工具专属叶子脚本。
5. 更新行为测试、必要 README 和受影响的 Trellis spec。
6. 依次执行 Shell 语法与 fixture source smoke、PowerShell 窄测、安装选择预览、真实 Profile 入口、PowerShell 全量测试和根质量门禁。

## 归属与加载顺序

- 双 Shell 均可执行且不含专属 widget/数组语法的初始化放 `shell/shared.d/*.sh`；文件由 `shell/deploy.sh` 部署到 `~/.bashrc.d/`，不得直接写用户完整 rc。
- Zsh completion system 只由 `shell/zsh.d/00-compinit.zsh` 初始化。通用补全排在它之后；命令专属补全排在通用补全之后，以保留最终覆盖权。
- Atuin 先注册历史 widget，`95-zsh-autosuggestions.zsh` 再包装现有 widget；`zzz-zsh-syntax-highlighting.zsh` 必须在 prompt 与其它 widget 后最后加载。两个插件只在交互式 Zsh source，缺失、失败或已由用户配置加载时安静降级且不重复注册。
- 历史 hook 靠近 prompt 之前加载；重复 source 必须由当前会话变量阻止重复注册。
- PowerShell 外部工具探测与同步初始化只属于 Full。Minimal 不执行工具探测，UltraMinimal 不加载完整 Environment。
- PowerShell OnIdle 保持 `$Global:__PowerShellProfileOnIdleState` 单订阅；psutils、wrapper、fzf、PSReadLine 各步骤继续独立捕获错误。

## 降级、缓存与幂等

- Shell 共享片段先判断交互式会话，再用 `command -v` 判断工具；不满足时安静返回。
- Carapace 必须根据当前进程的 `BASH_VERSION` / `ZSH_VERSION` 选择 Shell，并显式调用 `carapace _carapace bash` 或 `carapace _carapace zsh`；不得依赖可能继承自登录 Shell 的 `$SHELL`。
- 只有生成命令成功且生成脚本 `eval` 成功后才能设置会话完成标记；两阶段任一失败都必须吞掉该工具的诊断并安静降级，不得阻断后续片段。尤其不能把生成命令退出码当成 Bash 3.2 等旧 Shell 已成功加载生成脚本的证明。
- PowerShell 使用批量 `Find-ExecutableCommand` 结果，不为单个工具重复发现命令。
- 生成型 PowerShell 初始化复用 `Invoke-WithFileCache`，缓存名包含平台 `CacheId`；缓存脚本 dot-source 成功后才设置全局会话标记。
- 可选工具缺失只写 Verbose 或安静跳过，不进入 Profile 安装提示定义。
- Windows Scoop 应用声明额外 bucket 时，统一安装模块必须先幂等确保 bucket；失败时不得继续伪装应用安装成功。

## 键位合同

| 键位 | 合同 |
| --- | --- |
| PowerShell Tab | Carapace 成功初始化后为 `MenuComplete`；缺失或失败时为 `Complete` |
| Up | Atuin 一律使用 `--disable-up-arrow`，保留各 Shell 原生历史导航 |
| `Ctrl+r` | 由 Atuin 初始化提供历史搜索入口 |
| `Alt+h` | 保留仓库已有 fzf 历史入口，不得覆盖 |

## 行为测试矩阵

| 场景 | Bash | Zsh | PowerShell |
| --- | --- | --- | --- |
| 非交互式 | 不调用工具 | 不调用工具 | 由模式合同覆盖 |
| 工具缺失 | source 成功、无硬错误 | source 成功、无硬错误 | Full 跳过且无安装提示 |
| 工具存在 | 按 `BASH_VERSION` 显式传 `carapace _carapace bash` | 按 `ZSH_VERSION` 显式传 `carapace _carapace zsh` | Full 生成、缓存并加载脚本 |
| 重复加载 | 每项初始化一次 | 每项初始化一次，`compinit` 不重复 | 工具初始化一次、OnIdle 一个 |
| 模式 | 不适用 | 不适用 | Minimal/UltraMinimal 外部进程为零 |
| 键位 | Atuin 禁用 Up 覆盖 | Atuin 禁用 Up 覆盖 | Tab 条件切换；Up 与 `Alt+h` 保留 |
| 单项失败 | 其他片段继续 | 其他片段继续 | 其他工具和基础 profile 继续 |

测试必须观察 fake executable 的调用参数、计数、生成脚本副作用、PSReadLine handler 或事件订阅结果。禁止仅搜索源码字符串证明行为。
