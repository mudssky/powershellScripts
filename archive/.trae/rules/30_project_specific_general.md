# 📂 Project Specific Rules (General)

## 1. Core Stack

- **PowerShell**: PowerShell 7 (`pwsh`), Cross-Platform (Windows/Linux).
- **Node.js**: `pnpm` workspace, ESM support.

## 2. Project Structure

```text
root/
├── bin/                # 自动生成的跨平台可执行脚本 (Shim)
├── scripts/            # 自动化脚本集合
│   ├── node/           # Node.js 脚本工程 (Rspack + TS)
│   │   └── src/        # 源码目录
│   └── pwsh/           # PowerShell 脚本源码
├── install.ps1         # 项目入口安装脚本
└── README.md           # 项目总览
```

## 3. Strictness Level

- **High**: 对 `bin/` 目录的生成逻辑保持高度敏感，严禁手动修改 `bin/` 下的 Shim 文件。
