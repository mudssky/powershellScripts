## 1. 运行时边界收敛

- [x] 1.1 移除 `profile/profile.ps1` 中 PowerShell 5.1 兼容变量回填逻辑
- [x] 1.2 删除所有 5.x 兼容分支与相关提示分支，保持 PowerShell 7+ 单路径执行
- [x] 1.3 清理注释与文案中的 5.x 兼容描述

## 2. profile 目录职责优化

- [x] 2.1 新建配置目录并迁移 `user_aliases.ps1` 到约定位置
- [x] 2.2 更新 `profile/core/loaders.ps1` 的别名脚本加载路径
- [x] 2.3 验证 `Set-AliasProfile` 与 `Show-MyProfileHelp` 对迁移后别名数据的兼容

## 3. 文档与规范同步

- [x] 3.1 更新 `docs/install/README.md`，移除 5.1 相关路径并明确 `pwsh` 前置条件
- [x] 3.2 更新 profile 相关注释/帮助文本，保持与新运行时边界一致
- [x] 3.3 校验 `openspec/changes/drop-ps51-compat-and-optimize-profile/specs/unified-profile/spec.md` 与实现计划一致

## 4. 回归验证

- [x] 4.1 在 Full/Minimal/UltraMinimal 三种模式下验证入口加载成功
- [x] 4.2 验证别名加载、帮助输出、关键函数可用性未回归
- [x] 4.3 记录基线耗时并确认结构优化后无明显性能退化

### 验证记录（2026-02-10）

- Full: 2313 ms
- Minimal: 1723 ms
- UltraMinimal: 1502 ms
