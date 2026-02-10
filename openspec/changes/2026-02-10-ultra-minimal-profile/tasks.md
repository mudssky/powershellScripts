## 1. 模式与开关

- [ ] 1.1 在 `profile/profile.ps1` 引入 `UltraMinimal` 模式判定（含环境变量优先级）
- [ ] 1.2 保留并兼容现有 `Minimal` 语义，明确与 `UltraMinimal` 的边界
- [ ] 1.3 在代码注释中写明三种模式差异（Full/Minimal/UltraMinimal）

## 2. 极简执行路径

- [ ] 2.1 将 UTF8 配置抽出为独立函数，供 Full/Minimal/UltraMinimal 复用
- [ ] 2.2 在 UltraMinimal 下跳过 `loadModule.ps1`、`wrapper.ps1`、`user_aliases.ps1` 加载
- [ ] 2.3 在 UltraMinimal 下跳过代理、PATH 同步、工具初始化、别名注册
- [ ] 2.4 在 UltraMinimal 下保留 `POWERSHELL_SCRIPTS_ROOT` 设置

## 3. 兼容与提示

- [ ] 3.1 `Show-MyProfileHelp` 在未加载模块时降级输出（不报错）
- [ ] 3.2 增加简短模式提示（可通过 `Verbose` 控制）

## 4. 验证

- [ ] 4.1 语法检查：`pwsh -NoProfile` 解析 `profile/profile.ps1`
- [ ] 4.2 行为验证：UltraMinimal 下无 starship/zoxide/proxy 初始化日志
- [ ] 4.3 性能验证：记录 Full/Minimal/UltraMinimal/baseline 四组耗时（至少 10 次）
