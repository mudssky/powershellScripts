## 1. Script Skeleton

- [x] 1.1 新增 `scripts/pwsh/devops/Clean-DockerImages.ps1` 并建立标准头部注释、`CmdletBinding(SupportsShouldProcess)`、`Set-StrictMode` 与统一错误处理。
- [x] 1.2 定义并校验核心参数（如 `DryRun`、激进模式开关、时间阈值、保留规则参数），补充默认值与参数说明。

## 2. Cleanup Logic

- [x] 2.1 实现 Docker CLI 可用性检查与失败快返逻辑，确保环境不满足时返回非零退出码与清晰提示。
- [x] 2.2 实现默认保守清理候选筛选（含 dangling 与时间阈值过滤），并在删除前应用保留规则过滤。
- [x] 2.3 实现显式激进模式分支，确保仅在用户开启参数时执行更高强度清理，并输出风险提示。

## 3. Safety And Reporting

- [x] 3.1 实现 `DryRun` 预览输出，展示候选镜像、预计操作和命令，不执行实际删除。
- [x] 3.2 实现清理前后 `docker system df` 统计采集与差异输出，展示镜像占用变化。
- [x] 3.3 删除操作统一接入 `ShouldProcess` 语义，确保交互式与自动化调用行为一致。

## 4. Validation

- [x] 4.1 在有 Docker 环境下分别验证默认模式、`DryRun`、激进模式、保留规则命中场景。
- [x] 4.2 通过 `scripts/pwsh/devops/run.ps1` 入口验证脚本可被发现并正常传参调用。
- [x] 4.3 执行根目录 `pnpm qa` 并修复出现的问题，确保本次改动满足仓库质量门槛。

## 5. Fzf Interactive Mode

- [x] 5.1 增加交互式多选参数与 `fzf` 调用流程，仅删除用户在 `fzf` 中选中的候选镜像。
- [x] 5.2 增加 `fzf` 依赖检测，缺失时快速失败并输出明确安装提示。
- [x] 5.3 更新 `scripts/pwsh/devops/Clean-DockerImages.ps1` 顶部帮助文档，补充 `fzf` 交互模式说明与示例。
- [x] 5.4 在 Docker 环境验证 `fzf` 多选路径、缺失 `fzf` 报错路径，并执行根目录 `pnpm qa`。
