## Why

当前开发环境长期拉取和构建镜像后，存在大量无用 Docker 镜像占用磁盘空间，导致磁盘告警、构建失败风险上升，并增加日常维护成本。需要提供统一脚本，在可预览、可控和可回滚认知（通过 DryRun 与明确输出）的前提下清理冗余镜像。

## What Changes

- 新增一个 `scripts/pwsh/devops/` 下的 Docker 镜像清理脚本，用于识别并删除可清理镜像。
- 提供默认安全清理策略（优先清理 dangling 与长期未使用镜像），并支持显式激进模式。
- 提供保留规则参数（按仓库名、tag 等）避免误删关键基础镜像。
- 增加 `fzf` 交互式多选流程，用于从候选镜像中选择实际删除项。
- 当本机未安装 `fzf` 时，脚本快速失败并输出明确安装提示，不回退到其他交互方案。
- 提供 `DryRun` 预览与清理前后空间统计输出，确保操作可验证。
- 与现有 `scripts/pwsh/devops/run.ps1` 入口兼容，可通过统一入口调用。

## Capabilities

### New Capabilities
- `docker-image-cleanup`: 提供可配置、可预览的 Docker 冗余镜像清理能力，包含安全默认策略、保留规则、`fzf` 多选交互与空间统计。

### Modified Capabilities
- 无

## Impact

- 受影响代码：`scripts/pwsh/devops/` 新增清理脚本；可能补充脚本文档注释与调用示例。
- 依赖系统：本地 Docker CLI（`docker`）与 `fzf` 可用。
- 行为影响：执行清理会删除满足条件的本地镜像，需要通过默认安全策略与参数保护降低误删风险。
