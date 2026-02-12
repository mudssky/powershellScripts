## Context

Phase 1 优化（`psutils-deferred-loading`）通过分层延迟加载将 `core-loaders` 从 680ms 降至 ~290ms。当前 profile 总加载时间 ~1150ms（Windows），`initialize-environment` 占 ~594ms。

精确分步诊断（`pf-diag.ps1`）揭示了两个此前隐藏的瓶颈：

| 步骤 | 耗时 | 根因 |
|------|------|------|
| starship dot-source | 274ms | 缓存脚本中 `Set-PSReadLineOption -ContinuationPrompt (Invoke-Native ...)` 每次 spawn starship 子进程 |
| Set-ProfileUtf8Encoding | 278ms | `Set-PSReadLineKeyHandler -Key Tab` 触发 PSReadLine 模块首次完整初始化 |

两者合计 552ms，占 `initialize-environment` 的 93%。

现有 OnIdle 基础设施（`loadModule.ps1`）已成熟可复用：`Register-EngineEvent -SourceIdentifier PowerShell.OnIdle` + `.GetNewClosure()` 模式。

## Goals / Non-Goals

**Goals:**
- 将 `initialize-environment` 从 ~594ms 降至 ~300ms 以下
- 将总 profile 加载时间从 ~1150ms 降至 ~800ms 以下
- 消除 starship continuation prompt 每次启动的子进程调用
- 消除 PSReadLine 冷启动对 profile 加载的影响

**Non-Goals:**
- 不优化 starship `New-Module` 的编译开销（~100-120ms，属于 PowerShell 引擎固有成本）
- 不优化 `core-loaders` 阶段（Phase 1 已优化到位）
- 不修改 starship 本身的 init 脚本结构
- 不做 profile 模式（Minimal/UltraMinimal）相关变更

## Decisions

### Decision 1: PSReadLine 键绑定移至 OnIdle

**选择**: 将 `encoding.ps1` 中的 `Set-PSReadLineKeyHandler -Key Tab -Function Complete` 移到现有 `loadModule.ps1` 的 OnIdle Action 中。

**理由**:
- PSReadLine 的 `Set-PSReadLineKeyHandler` 在冷启动时触发模块完整初始化（~260ms）
- Tab 补全在 profile 加载后的前几秒内几乎不可能使用（用户还没开始输入命令）
- OnIdle 在用户首次空闲时触发，此时 PSReadLine 已自然初始化，键绑定注册接近零成本
- 复用现有 OnIdle 事件处理器，不需要注册新的引擎事件

**替代方案**:
- 注册独立的 OnIdle 事件：增加复杂度，且 `-MaxTriggerCount 1` 限制了灵活性
- 保持现状：放弃 ~260ms 的优化

### Decision 2: 缓存 starship continuation prompt

**选择**: 使用 `Invoke-WithFileCache` 缓存 `starship prompt --continuation` 的输出，按平台区分缓存 key。

**缓存策略**:
- 缓存 key: `starship-continuation-prompt`（与 starship-init 缓存同目录）
- 有效期: 7 天（与 starship init 缓存一致）
- 缓存内容: continuation prompt 的纯文本输出
- 失效条件: starship 配置变更需手动删除缓存（与现有 init 缓存行为一致）

**实现方式**: 在 starship init 缓存脚本生成后，对其内容进行 post-processing——将 `Set-PSReadLineOption -ContinuationPrompt (Invoke-Native ...)` 替换为缓存的字面量值。

**理由**:
- `starship prompt --continuation` 输出是确定性的（仅依赖 starship 配置）
- 当前每次 profile 启动都 spawn 一个 starship 子进程，耗时 ~100-150ms
- 缓存后降为 0ms（字面量字符串赋值）

**替代方案**:
- 修改 starship init 脚本模板：需要在 starship 版本更新时维护 patch，成本太高
- 使用环境变量传递 continuation prompt：starship 不支持此机制

### Decision 3: starship 缓存按平台隔离

**选择**: starship init 缓存 key 增加平台标识符，防止跨平台共享项目时缓存交叉污染。

**缓存 key**: `starship-init-powershell-<platform>`，其中 `<platform>` 为 `win`/`linux`/`macos`。

**理由**:
- 诊断中发现 Linux 生成的缓存文件包含 `/home/linuxbrew/.linuxbrew/bin/starship` 硬编码路径
- 在 Windows 上 dot-source 此缓存时，`Invoke-Native` 使用错误路径导致进程启动失败/超时
- 删除并重新生成 Windows 缓存后立刻节省 ~178ms

## Risks / Trade-offs

- **[OnIdle 前 Tab 行为变化]** → 在 OnIdle 触发前按 Tab 使用 PowerShell 默认 `TabCompleteNext`（循环补全）而非 `Complete`（菜单补全）。影响窗口极短（启动后 1-2 秒），用户几乎不会察觉。
- **[Continuation prompt 缓存过期]** → 用户更改 starship 配置后需删除缓存文件或等待 7 天自动过期。与现有 init 缓存行为一致，可通过文档说明。
- **[Post-processing 脆弱性]** → 对 starship init 输出进行正则替换依赖其输出格式的稳定性。如果 starship 版本更新改变了 init 脚本结构，替换可能失败。应实现 fallback：替换失败时保持原始行为（spawn 子进程）。
