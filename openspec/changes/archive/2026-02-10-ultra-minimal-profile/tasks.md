## 1. 模式与开关

- [x] 1.1 在 `profile/profile.ps1` 引入 `UltraMinimal` 模式判定（含环境变量优先级）
- [x] 1.2 保留并兼容现有 `Minimal` 语义，明确与 `UltraMinimal` 的边界
- [x] 1.3 在代码注释中写明三种模式差异（Full/Minimal/UltraMinimal）
- [x] 1.4 固化默认策略：默认 `Full`，`Minimal` 仅手动触发
- [x] 1.5 固化自动降级策略：仅 Codex/沙盒命中时自动降级到 `UltraMinimal`
- [x] 1.6 明确当前不实现 CI 自动判定（YAGNI）
- [x] 1.7 固化自动判定最小变量集合（V1）：`CODEX_THREAD_ID` 或 `CODEX_SANDBOX_NETWORK_DISABLED`
- [x] 1.8 明确 `CODEX_MANAGED_BY_NPM/BUN` 不参与自动判定

## 2. 极简执行路径

- [x] 2.1 将 UTF8 配置抽出为独立函数，供 Full/Minimal/UltraMinimal 复用
- [x] 2.2 在 UltraMinimal 下跳过 `loadModule.ps1`、`wrapper.ps1`、`user_aliases.ps1` 加载
- [x] 2.3 在 UltraMinimal 下跳过代理、PATH 同步、工具初始化、别名注册
- [x] 2.4 在 UltraMinimal 下保留 `POWERSHELL_SCRIPTS_ROOT` 设置

## 3. 兼容与提示

- [x] 3.1 `Show-MyProfileHelp` 在未加载模块时降级输出（不报错）
- [x] 3.2 增加简短模式提示（可通过 `Verbose` 控制）
- [x] 3.3 增加模式决策摘要日志（mode/source/markers）
- [x] 3.4 增加手动兜底文案（`FULL`/`MODE`/`ULTRA_MINIMAL` 的用法）
- [x] 3.5 固化 V1 字段集合：`mode/source/reason/markers`（含 `elapsed_ms`）
- [x] 3.6 固化 `reason` 枚举并在文档中示例
- [x] 3.7 固化 `markers` 输出策略：输出全部命中变量
- [x] 3.8 预留 V2 扩展字段：`phase_ms/ps_version/host/pid`

## 4. 验证

- [x] 4.1 语法检查：`pwsh -NoProfile` 解析 `profile/profile.ps1`
- [x] 4.2 行为验证：UltraMinimal 下无 starship/zoxide/proxy 初始化日志
- [x] 4.3 性能验证：记录 Full/Minimal/UltraMinimal/baseline 四组耗时（至少 10 次）
- [x] 4.4 优先级验证：`FULL > MODE > ULTRA_MINIMAL > auto > default`
- [x] 4.5 误判/漏判演练：通过手动开关可即时回退到期望模式
- [x] 4.6 日志验证：V1 字段完整、`reason` 在枚举内、`markers` 为全命中集合
