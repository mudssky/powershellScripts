# 浏览器调试模式快捷切换设计

## Architecture

保持 `profile start` 作为唯一外部接口，将“复用、确认、停止 owned 进程、重新启动、生成帮助页”集中在 `Invoke-BrowserDebugProfileStart` 这一深模块中。快捷方式不实现第二套切换逻辑，只通过同一接口传入 `--yes`。

## CLI Contract

```text
browser-debug profile start <name> [--mode local|lan] [--listen-address IPv4] [--open-guide] [--yes]
```

- `--yes` 仅表示用户预先确认了必要的模式/监听地址切换；目标未运行或可直接复用时没有额外副作用。
- Local/LAN 快捷方式固定携带 `--open-guide --yes`。
- JSON 或非交互环境需要切换且没有 `--yes` 时直接失败，错误提示给出重试命令所需的 `--yes`。

## Data Flow

1. 读取 Profile 和实际 runtime status。
2. 比较当前实际模式、显式监听地址与目标请求，计算是否需要切换。
3. 未运行：直接启动，`switched=false`。
4. 同配置运行：沿用既有复用规则；没有 `--open-guide` 时仍保持“Profile 已在运行”错误，避免扩大无关语义。
5. 需要切换：
   - `--yes` 存在时直接继续。
   - 否则，JSON/输入重定向/无交互 Host 直接拒绝；交互 Host 展示当前模式、endpoint、目标模式和关闭影响，默认选择 No。
   - 确认后调用现有 `Stop-BrowserDebugProfileProcess`，只停止 owned PID。
   - 调用 `Start-BrowserDebugProfileProcess` 以目标配置重新启动。
6. 基于实际启动结果生成帮助页，保留帮助页失败仅 warning 的既有合同。

## Result Contract

`profile start` 结果在既有字段上补充：

- `reused: bool`：是否复用原实例。
- `switched: bool`：是否停止旧实例后重新启动。
- `stoppedProcessIds: int[]`：切换过程中请求停止的 owned PID；未切换为空数组。

`mode`、`listenAddress`、`endpoint`、`cdpPort` 和 `cdpVersion` 继续来自实际 owned 进程与 CDP 探测。

## Confirmation Seam

新增一个内部确认函数，输入当前 status、目标模式和目标监听地址，输出布尔值或抛出非交互错误。`Invoke-BrowserDebugProfileStart` 只依赖该小接口，Pester 可直接 Mock，避免测试真实终端输入。

交互确认使用 PowerShell Host 的选择提示，默认 No。无法可靠交互时不尝试 `Read-Host` 或 stdin，统一提示添加 `--yes`。

## Compatibility

- 默认启动、LAN 安全警告、同模式 `--open-guide` 复用、owned PID 识别、SSH 独立生命周期均保持不变。
- 有意变更：不同模式或显式不同监听地址不再永久拒绝；在确认或 `--yes` 后切换。
- 现有快捷方式需通过 `profile shortcut` 的幂等更新逻辑重建，确保参数包含 `--yes`；真实 `edge-debug` Local/LAN 快捷方式在实现后同步更新。

## Failure and Rollback

- 用户拒绝或非交互缺少 `--yes`：停止前失败，旧实例不受影响。
- 停止 owned 进程失败：立即失败，不启动新实例。
- 停止成功但新启动失败：明确返回失败；不自动回滚旧模式，避免掩盖第二次启动失败或重复改变状态。
- 代码回滚可恢复旧的不同模式拒绝合同；快捷方式中的多余 `--yes` 在旧 schema 下会报未知选项，因此回滚代码时需同步重建快捷方式。