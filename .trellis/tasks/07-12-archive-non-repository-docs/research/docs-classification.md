# docs 文件分类

## 结论

- Git 跟踪文件总数：162。
- 保留：29 个与仓库代码、配置、测试、安装、运维或当前工程约束直接相关的文档。
- 归档：133 个文件，其中历史规划/待办 54 个，通用 cheatsheet 79 个。

## 整体归档目录

以下目录已被 Trellis 替代，作为历史过程资料整体归档：

- `docs/brainstorms`
- `docs/ideation`
- `docs/plans`
- `docs/superpowers`
- `docs/todos`

## 保留的 cheatsheet

以下 16 个文件承担仓库专用职责，整篇保留：

- `docs/cheatsheet/database/postgresql/backup-restore.md`
- `docs/cheatsheet/github/dependabot.md`
- `docs/cheatsheet/linux/docker/docker-bind-localhost.md`
- `docs/cheatsheet/network/tailscale/index.md`
- `docs/cheatsheet/pwsh/script-template.ps1`
- `docs/cheatsheet/pwsh/高性能pwsh最佳实践.md`
- `docs/cheatsheet/security/betterleaks-guide.md`
- `docs/cheatsheet/vscode/remote/devcontainers.md`
- `docs/cheatsheet/vscode/remote/setup-ssh.md`
- `docs/cheatsheet/vscode/remote/ssh-proxy.md`
- `docs/cheatsheet/typescript/cross-platform-script-deno.md`
- `docs/cheatsheet/typescript/cross-platform-script-node.md`
- `docs/cheatsheet/python/cross-platform-script-python.md`
- `docs/cheatsheet/rust/cross-platform-script-rust.md`
- `docs/cheatsheet/golang/cross-platform-script-golang.md`
- `docs/cheatsheet/pwsh/Pwsh跨平台脚本最佳实践.md`

前 10 个文件被活动代码、测试、任务、skill 或仓库配置直接引用，或明确描述仓库实际入口。后 6 个文件由保留的 `docs/跨平台单文件脚本最佳实践.md` 作为仓库脚本选型入口引用。

## 归档的 cheatsheet 路径

以下 46 个最大路径子树覆盖 79 个通用 cheatsheet，且不包含上述保留例外：

- `docs/cheatsheet/README.md`
- `docs/cheatsheet/api`
- `docs/cheatsheet/backend`
- `docs/cheatsheet/database/sql.md`
- `docs/cheatsheet/deno`
- `docs/cheatsheet/frontend`
- `docs/cheatsheet/git`
- `docs/cheatsheet/github/actions`
- `docs/cheatsheet/infra`
- `docs/cheatsheet/laptop`
- `docs/cheatsheet/linux/apt.md`
- `docs/cheatsheet/linux/env.md`
- `docs/cheatsheet/linux/network`
- `docs/cheatsheet/linux/nix`
- `docs/cheatsheet/linux/permission`
- `docs/cheatsheet/linux/services`
- `docs/cheatsheet/linux/ubuntu_package.md`
- `docs/cheatsheet/linux/user`
- `docs/cheatsheet/lua`
- `docs/cheatsheet/macos`
- `docs/cheatsheet/neovim`
- `docs/cheatsheet/network/network-troubleshooting.md`
- `docs/cheatsheet/node`
- `docs/cheatsheet/pwsh/PSReadLine.md`
- `docs/cheatsheet/pwsh/Pester.md`
- `docs/cheatsheet/pwsh/交互性.md`
- `docs/cheatsheet/pwsh/模块使用指南.md`
- `docs/cheatsheet/python/jupyterlab最佳实践.md`
- `docs/cheatsheet/python/jupyter搭配git使用.md`
- `docs/cheatsheet/python/test`
- `docs/cheatsheet/python/请求封装最佳实践.md`
- `docs/cheatsheet/rust/Rust 语法速查手册.md`
- `docs/cheatsheet/rust/ecosystem`
- `docs/cheatsheet/rust/rust测试指南.md`
- `docs/cheatsheet/rust/编译速度优化.md`
- `docs/cheatsheet/rust/错误处理.md`
- `docs/cheatsheet/sheet`
- `docs/cheatsheet/stable-diffusion`
- `docs/cheatsheet/terminal`
- `docs/cheatsheet/vscode/extensions`
- `docs/cheatsheet/vscode/remote/remote-guide.md`
- `docs/cheatsheet/vscode/remote/ssh-nopasswd.md`
- `docs/cheatsheet/vscode/vscode-cheatsheet.md`
- `docs/cheatsheet/vscode/vscode-tasks.md`
- `docs/cheatsheet/vscode/workspace.md`
- `docs/cheatsheet/win`

## 其他保留文档

除上述 16 个 cheatsheet 外，保留以下 13 个仓库文档：

- `docs/INSTALL.md`
- `docs/install/README.md`
- `docs/local-cross-platform-testing.md`
- `docs/scripts-index.md`
- `docs/solutions/**` 共 7 个文件
- `docs/换源脚本使用说明.md`
- `docs/跨平台单文件脚本最佳实践.md`

## 风险

- 旧规划文档可能被 Trellis 历史任务引用。历史引用不作为活动入口，但明确的活动引用需要迁到 `archive/docs/**`。
- 保留文档可能链接到待归档 cheatsheet。执行前后都要扫描 Markdown 相对链接，修复活动文档中的断链。
- `docs/superpowers/plans/` 原有 7 个被忽略、未跟踪的本地文件，不属于 Git 冷归档范围；执行前已原样备份到 `/Users/mudssky/.local/share/powershellScripts/ignored-docs-superpowers-plans-2026-07-12_12-47-38/`，并删除失效的 `.gitignore` 规则。
- 三对中文文件路径会生成重复稳定 ID，因此 48 个路径使用 batch 7，另外 3 个冲突文件使用 batch 8；文件分类和镜像路径不变。
