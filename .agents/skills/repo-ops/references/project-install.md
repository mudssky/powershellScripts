# 项目安装与依赖运维

## 关键路径

- 总入口文档：`docs/INSTALL.md`
- 根目录安装脚本：`install.ps1`
- PowerShell 模块安装：`profile/installer/installModules.ps1`
- npm 脚本入口：`package.json`
- 质量脚本：`scripts/qa.mjs`

## 初始化命令

跨平台 PowerShell 层初始化：

```powershell
pwsh ./install.ps1
```

等价 npm scripts：

```bash
pnpm pwsh:install
pnpm scripts:install
```

安装额外应用：

```powershell
pwsh ./install.ps1 -installApp
```

安装 PowerShell 模块：

```powershell
pwsh ./profile/installer/installModules.ps1
```

## install.ps1 做什么

- Windows 下检查并配置仓库根目录和 `bin/` 到 PATH。
- 执行 `Manage-BinScripts.ps1 -Action sync -Force` 同步 bin shim。
- 非 Windows 下构建 `scripts/bash` 工具集。
- 进入 `scripts/node` 执行 `pnpm install --ignore-scripts` 和 `pnpm run build`。
- 安装或配置 `nbstripout`。
- Windows 下处理 AutoHotkey 配置。
- Linux/macOS 下执行 `shell/deploy.sh`。

## QA 与测试

常用命令：

```bash
pnpm qa
pnpm qa:all
pnpm qa:verbose
pnpm test:pwsh:all
pnpm test:pwsh:coverage
```

项目规则：

- 每个代码改动任务完成时，执行根目录 `pnpm qa` 并修复出现的问题；只改文案时可不执行。
- 涉及 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`、`PesterConfiguration.ps1`、`docker-compose.pester.yml` 等 pwsh 相关内容时，提交前执行 `pnpm test:pwsh:all`。
- 需要显式验证 coverage 门槛或改动涉及 coverage 规范时，额外执行 `pnpm test:pwsh:coverage`。
- 本机 Docker 不可用时，至少执行 `pnpm test:pwsh:full`，并说明 Linux 覆盖依赖 CI 或 WSL。

## 排查提示

- `pnpm` 不存在：先安装 pnpm 或启用 Corepack。
- `pnpm install` 在 `scripts/node` 失败：进入 `scripts/node` 目录单独复现，保留失败命令和首个错误。
- PowerShell 模块安装失败：确认 PowerShellGet/PSGallery 可用，必要时记录代理、网络或权限问题。
- Docker 相关测试失败：先确认 Docker Desktop / Docker Engine 与 compose v2 可用。
