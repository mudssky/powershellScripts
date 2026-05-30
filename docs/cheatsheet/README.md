# Cheatsheet 分类索引

本目录收纳可复用的速查表、排障手册和工具使用笔记。新增文档时优先按“主要使用场景”分类，避免只按一篇文档里偶然出现的命令归类。

## 分类规则

- `infra/`：基础设施、服务器、反向代理、容器暴露、运维安全等跨平台或偏服务端的主题。
- `network/`：Tailscale、DNS、端口连通性、跨平台网络排障等通用网络工具。
- `linux/`、`win/`、`macos/`：平台专属命令、系统配置和平台专属排障。
- `pwsh/`、`python/`、`rust/`、`golang/`、`lua/`、`typescript/`：语言或脚本运行时相关实践。
- `node/`、`deno/`：运行时生态、包管理、框架配套工具。
- `frontend/`：前端框架、CSS、字体、组件工程实践。
- `devtools/` 当前拆分为 `git/`、`github/`、`terminal/`、`vscode/`、`neovim/` 等具体工具目录。
- `database/`：SQL、PostgreSQL、备份恢复等数据库主题。
- `security/`：安全扫描、泄漏检查和安全工具。
- `laptop/`、`sheet/`、`stable-diffusion/`：暂时保留的独立主题，等同类内容增多后再合并或拆分。

## 常用入口

- 服务器与反向代理：[`infra/server/`](./infra/server/)
- 通用网络工具：[`network/`](./network/)
- 平台网络排障：[`linux/network/`](./linux/network/)、[`win/network/`](./win/network/)
- VS Code 远程开发：[`vscode/remote/`](./vscode/remote/)
- PowerShell：[`pwsh/`](./pwsh/)
- 跨平台单文件脚本：[`../跨平台单文件脚本最佳实践.md`](../跨平台单文件脚本最佳实践.md)

## 放置建议

- 如果文档主要讲“某台服务器怎么对外提供服务”，放到 `infra/server/`。
- 如果文档主要讲“网络工具或协议如何使用”，放到 `network/`。
- 如果文档只适用于某个操作系统，放到对应平台目录，例如 `linux/network/` 或 `win/network/`。
- 如果文档是某个编辑器或终端工具的配置，放到对应工具目录。
- 如果一个主题横跨多个目录，优先选择读者最可能查找的入口，并在相关文档末尾补交叉链接。
