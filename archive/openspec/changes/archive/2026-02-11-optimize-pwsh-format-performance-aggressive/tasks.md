## 1. 快速路径与模块加载

- [x] 1.1 调整 `-GitChanged` 流程：先收集改动文件，再决定是否导入 `PSScriptAnalyzer`
- [x] 1.2 移除 `Get-Module -ListAvailable` 预扫描，改为直接 `Import-Module` 失败后处理
- [x] 1.3 为 `Get-GitChangedPowerShellFiles` 增加扩展名 pathspec 过滤，减少无关文件处理

## 2. 激进规则集与严格模式

- [x] 2.1 在 `Format-PowerShellCode.ps1` 中定义默认激进 settings（不含 `PSUseCorrectCasing`）
- [x] 2.2 增加严格模式参数（如 `-Strict`）并切换到完整规则行为
- [x] 2.3 保持默认命令行为稳定：不改入口名，仅改变默认策略为快速模式

## 3. 启动与 IO 性能优化

- [x] 3.1 将目录扫描从三次 `Get-ChildItem -Filter` 优化为单次遍历 + 扩展名筛选
- [x] 3.2 在写回前比较原文与格式化结果，一致则跳过 `Set-Content`
- [x] 3.3 更新 `package.json`：`format:pwsh` / `format:pwsh:all` 使用 `pwsh -NoProfile`

## 4. 验证与文档

- [x] 4.1 运行 `pnpm qa:pwsh` 并修复 PowerShell 相关问题（按仓库约定）
- [x] 4.2 补充 README 或脚本帮助：说明默认激进模式与严格模式的适用场景
- [x] 4.3 补充性能前后对比数据（空改动、少量改动、重文件场景）
