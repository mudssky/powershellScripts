# AI Index & 助手指南 (AI-INDEX)

## 1. 脚本管理 (PowerShell)

- **新增脚本**: 在 `scripts/pwsh/<分类>/` 下创建 `.ps1` 文件。
- **同步 Shim**: 运行 `.\Manage-BinScripts.ps1 -Action sync`。
- **清理 Shim**: 运行 `.\Manage-BinScripts.ps1 -Action clean`。

### 2. Node.js 开发流程

- **构建所有**: `pnpm build` (生产) 或 `pnpm build:dev` (开发)。
- **运行测试**: `pnpm test`。
- **新增工具**: 在 `scripts/node/src/` 下创建 `<tool-name>.ts`。

### 3. 环境初始化

- **安装**: 运行 `.\install.ps1` (配置 PATH, 安装依赖, 同步脚本)。

## 📚 文档索引 (Documentation)

- **项目总览**: `README.md` (包含使用说明和特性)。
- **脚本列表**: `docs/scripts-index.md` (详细的脚本清单)。
- **最佳实践**: `docs/跨平台单文件脚本最佳实践.md`。
- **pwsh脚本参考模板**: `docs/cheatsheet/pwsh/script-template.md`。
