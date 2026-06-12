# Implement: SSH/WSL 项目启动脚本

## Checklist

- [x] 在 `psutils/src/config` 增加 SSH config 读取函数，解析并过滤适合启动器展示的 `Host` block。
- [x] 更新 `psutils/modules/config.psm1` 与 `psutils/psutils.psd1`，导出新的 SSH config 读取函数。
- [x] 确认启动器通过共享 SSH config 读取函数获取 Host block，不在脚本内部维护第二份 SSH config parser。
- [x] 为 SSH config 读取器补充 focused Pester 测试，覆盖普通 Host、RemoteCommand、多 pattern、通配符和注释。
- [x] 新增 `scripts/pwsh/devops/project-launcher/` 工具目录，包含 `tool.psd1` 与 `main.ps1`。
- [x] 在启动器中复用 `Resolve-ConfigSources` 读取默认值、JSON 配置与 CLI 覆盖参数。
- [x] 检查启动器中不存在手写通用 JSON 配置读取流程；只保留业务字段规范化与校验。
- [x] 在启动器中复用 `Select-InteractiveItem`，实现未指定名称时的交互选择与取消路径。
- [x] 检查启动器中不存在直接 `fzf` 调用或复制文本编号选择逻辑。
- [x] 实现启动项 catalog 合并：SSH config 为连接真相源，JSON 只新增 WSL 项或补充显示元数据。
- [x] 实现平台过滤：非 Windows 环境过滤 WSL 项。
- [x] 实现执行计划：SSH 默认使用 `ssh -tt <Name>`，WSL 使用 `wsl.exe -d <Distro> -- bash -lc <Command>`。
- [x] 修复交互启动卡住问题：Windows 下默认在新终端承载 SSH/WSL 会话，`-Inline` 才在当前终端内直接执行。
- [x] 实现 dry-run，输出执行计划但不启动外部进程。
- [x] 为启动器补充 Pester 测试，覆盖 JSON 增量、默认 distro、entry 级 distro 覆盖、command 优先、zellij fallback、非 Windows 过滤、显式名称、交互取消与 dry-run。
- [x] 更新必要 README 或示例配置，说明 JSON schema 与典型用法。

## Candidate Files

- `psutils/src/config/reader.ps1`
- `psutils/modules/config.psm1`
- `psutils/psutils.psd1`
- `psutils/tests/config.Tests.ps1`
- `scripts/pwsh/devops/project-launcher/tool.psd1`
- `scripts/pwsh/devops/project-launcher/main.ps1`
- `tests/ProjectLauncher.Tests.ps1`

`xx.md` 是临时草稿，不纳入候选实现文件、fixture 或文档文件。

## Validation Commands

- `pnpm qa`
- `pnpm test:pwsh:all`
- 如果 Docker 不可用：`pnpm test:pwsh:full`

## Risk And Rollback

- SSH config 解析器不应试图完整替代 OpenSSH 解析。若解析复杂配置风险变大，回滚到只读取单文件简单 `Host` block，并在文档中声明限制。
- JSON 同名 entry 只补 metadata。若实现中出现覆盖核心 SSH 字段的路径，应优先删除该覆盖能力。
- WSL 启动真实调用依赖 Windows 和 `wsl.exe`。测试默认验证执行计划，不直接调用真实 WSL。
- `psutils/psutils.psd1` 导出变更会影响模块导入；如果导出失败，回滚新增导出项并保留脚本本地导入作为临时方案。
