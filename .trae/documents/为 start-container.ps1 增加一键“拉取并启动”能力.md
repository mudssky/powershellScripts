## 背景
- 当前脚本支持 `-Pull` 拉取镜像与 `up -d` 启动，但没有一个参数同时完成二者。
- 用户需要“一条命令拉取并启动”的便捷入口。

## 方案选项
- 方案 A（兼容最广）：新增 `-Update`，顺序执行 `pull` → `up -d`（按 `-ServiceName` 的 profile）。
- 方案 B（Compose v2 优化）：新增 `-PullAlways`，执行 `up -d --pull always`，让 `up` 阶段自动拉取最新镜像。
- 无 `-ServiceName` 时，默认作用于所有服务；提供 `-DryRun` 预览命令。

## 实现步骤
1. 参数扩展：在 `param()` 增加 `[switch]$Update`、`[switch]$PullAlways`，并更新 Doc 注释示例与 `.PARAMETER`。
2. 逻辑分支：
   - `$Update` 为真：
     - 调用 `Invoke-DockerCompose -Action 'pull' -Profiles @($ServiceName)`
     - 继续调用 `Invoke-DockerCompose -Action 'up -d' -Profiles @($ServiceName)`
   - `$PullAlways` 为真（Compose v2）：
     - 调用 `Invoke-DockerCompose -Action 'up -d' -Profiles @($ServiceName) -ExtraArgs @('--pull','always')`
     - 若检测为 legacy compose（`docker-compose`），自动降级为方案 A 的两步执行。
3. 细节约束：保持现有 `ProjectName`、环境变量注入与 `Wait-ServiceHealthy` 行为一致。
4. 文档更新：完善 `.SYNOPSIS`、`.PARAMETER`、`.EXAMPLE`，新增：
   - `.\start-container.ps1 -ServiceName new-api -Update`
   - `.\start-container.ps1 -ServiceName new-api -PullAlways`

## 验证
- 使用 `-DryRun` 验证生成命令，在 v2 环境确认出现 `--pull always`。
- 针对 `redis`、`new-api` 做冒烟：`-Update` 和 `-PullAlways` 分别测试，有/无 `-ServiceName` 两种路径。
- 保证 legacy 环境自动回退，两步执行仍可用。

## 风险与回滚
- `--pull always` 仅 v2 支持，已设置自动回退避免失败。
- 若镜像更新导致不兼容，可用 `-Down` 再 `-Update` 进行干净重启。

## 代码位置参考
- 拉取逻辑：`start-container.ps1:294-301`
- 启动逻辑：`start-container.ps1:302-306`
- Compose 封装：`start-container.ps1:165-189`
- `new-api` 服务定义（profile 映射）：`config/dockerfiles/compose/docker-compose.yml:214-229`