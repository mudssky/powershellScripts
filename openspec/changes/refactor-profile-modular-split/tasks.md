## 1. 入口与模块结构

- [ ] 1.1 新建 `profile/core` 与 `profile/features` 目录脚本骨架
- [ ] 1.2 迁移模式决策与 UTF8 设置到 `core` 模块
- [ ] 1.3 在 `profile/profile.ps1` 固化新的 dot-source 编排顺序
- [ ] 1.4 保留入口参数、PS 5.1 回退与耗时统计逻辑

## 2. 功能迁移与兼容

- [ ] 2.1 迁移扩展脚本条件加载逻辑（Full/Minimal/UltraMinimal）
- [ ] 2.2 迁移 `Initialize-Environment` 到功能模块并保持行为一致
- [ ] 2.3 迁移 `Show-MyProfileHelp` 与降级输出逻辑并保持兼容
- [ ] 2.4 迁移 `Set-PowerShellProfile` 并保持 `-LoadProfile` 入口兼容

## 3. 回归验证

- [ ] 3.1 验证 Full/Minimal/UltraMinimal 三种模式行为一致
- [ ] 3.2 验证关键函数可见性与调用结果（Help/Init/Install）
- [ ] 3.3 验证 `profile_unix.ps1` shim 透传行为未受影响
- [ ] 3.4 使用 `pwsh -NoProfile` 完成语法与基础加载验证
