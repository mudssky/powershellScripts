## 原因分析
- 当前脚本未显式设置 Compose 项目名，`Invoke-DockerCompose` 使用 `-Project $ProjectName`，但默认值为空。
- Docker Compose 默认项目名取自 `docker-compose.yml` 所在目录名；本仓库路径为 `config/dockerfiles/compose/docker-compose.yml`，因此 Docker 客户端显示为 `compose`。

## 目标效果
- 在 Docker Desktop/CLI 中显示更语义化的分组名，例如：`dev-redis`、`dev-nacos`、`mongo-repl-dev`。
- 项目名在未传入 `-ProjectName` 时自动按服务名生成，保证统一、可读、可预测。
- 保持现有命令（`Up/Down/Pull/Build/Wait-ServiceHealthy`）的一致性与兼容性。

## 具体改动
- 新增 `Get-DefaultProjectName`：按以下优先级解析最终项目名，并做合规化处理（小写、非法字符替换为 `-`、长度限制 40）。
  1) 用户显式传入的 `-ProjectName`
  2) 环境变量 `${env:COMPOSE_PROJECT_NAME}`（若存在）
  3) 若指定了 `-ServiceName`，使用 `dev-<ServiceName>`（例如 `dev-redis`）
  4) 兜底：`compose`
- 在主执行流程中：
  - 计算最终 `projectName = Get-DefaultProjectName -ServiceName $ServiceName -ProjectName $ProjectName`
  - 设置环境变量：`${env:COMPOSE_PROJECT_NAME} = $projectName`
  - 所有 `Invoke-DockerCompose` 与 `Wait-ServiceHealthy` 调用统一使用该 `projectName`
- `-List` 模式优化：在打印可用服务名时，附加当前默认项目名提示（便于用户预期容器前缀与分组）。
- 帮助注释增强：在 `.PARAMETER ProjectName` 与 `.EXAMPLE` 中加入项目名示例与说明。

## 兼容性与注意事项
- 项目名改变会影响容器、网络、卷的前缀；若之前用 `compose` 前缀启动过，需要使用旧项目名执行一次 `-Down` 清理旧资源后再切换新项目名。
- 不建议在 Compose 文件中设置固定 `container_name`，以免影响扩缩容与命名规则；通过项目名分组即可满足可读性。

## 验证步骤
- 干运行验证：`-DryRun` 观察生成的命令包含 `-p dev-redis` 等预期项目名。
- 启动验证：`.\start-container.ps1 -ServiceName redis` 后在 Docker Desktop 查看分组名为 `dev-redis`（或用户指定）。
- 健康检查验证：`Wait-ServiceHealthy` 能正确通过 `com.docker.compose.project=<projectName>` 过滤容器并完成健康检查。
- 停止/清理验证：`-Down` 对指定项目名执行停止与删除，确保无残留。

## 使用示例
- 显式指定项目名：
  - `.\start-container.ps1 -ServiceName redis -ProjectName dev-redis`
- 自动项目名（按服务名生成）：
  - `.\start-container.ps1 -ServiceName nacos`
- 干运行预览：
  - `.\start-container.ps1 -ServiceName redis -DryRun`

## 可选扩展（后续）
- 新增 `-EnvTag` 参数（如 `dev/test/prod`），默认项目名规则调整为 `<EnvTag>-<ServiceName>`；若用户传入 `-ProjectName` 则优先使用显式值。