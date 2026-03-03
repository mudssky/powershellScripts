## ADDED Requirements

### Requirement: Safe default image cleanup
系统 SHALL 在默认模式下仅清理低风险冗余镜像（包括 dangling 镜像与满足时间阈值且未被运行中容器使用的镜像），并 MUST 避免直接执行激进全量删除。

#### Scenario: 默认执行时使用保守策略
- **WHEN** 用户不传入激进模式参数运行清理脚本
- **THEN** 脚本仅选择低风险候选镜像并跳过受保护镜像

### Requirement: Fzf multi-select interaction
系统 SHALL 提供基于 `fzf` 的多选交互流程，让用户从候选镜像中选择实际删除项。

#### Scenario: 用户通过 fzf 选择删除目标
- **WHEN** 用户启用交互式多选模式运行清理脚本
- **THEN** 脚本通过 `fzf` 展示候选镜像并仅对用户选中的条目执行删除

### Requirement: Fzf dependency enforcement
系统 SHALL 在进入交互式多选流程前检测 `fzf` 可用性；若未安装，MUST 立即失败并输出明确安装提示。

#### Scenario: 缺失 fzf 时快速失败并提示安装
- **WHEN** 用户启用交互式多选模式且运行环境不存在 `fzf`
- **THEN** 脚本以非零退出并输出可执行的 `fzf` 安装提示

### Requirement: Dry-run preview before deletion
系统 SHALL 支持 `DryRun` 预览模式，并在该模式下仅展示候选镜像、预计释放空间与将执行命令，MUST NOT 实际删除任何镜像。

#### Scenario: DryRun 不产生实际删除
- **WHEN** 用户以 `-DryRun` 运行清理脚本
- **THEN** 脚本输出候选与统计信息且 Docker 镜像集合保持不变

### Requirement: Configurable keep rules
系统 SHALL 支持通过仓库名列表与 tag 正则配置保留规则，并 MUST 在执行删除前对候选镜像应用保留过滤。

#### Scenario: 保留规则命中时镜像被跳过
- **WHEN** 候选镜像的仓库名或 tag 命中保留规则
- **THEN** 脚本将该镜像标记为保留并不执行删除

### Requirement: Explicit aggressive cleanup mode
系统 SHALL 提供显式激进模式开关用于清理更多未使用镜像，并 MUST 在执行前输出风险提示以确认该模式非默认行为。

#### Scenario: 激进模式仅在显式开启时触发
- **WHEN** 用户未提供激进模式参数
- **THEN** 脚本不执行激进级别的镜像清理命令

#### Scenario: 激进模式执行前提示风险
- **WHEN** 用户提供激进模式参数运行脚本
- **THEN** 脚本在执行删除前输出明确风险说明与本次模式标识

### Requirement: Cleanup result reporting
系统 SHALL 在清理前后输出磁盘占用统计，并 SHALL 至少包含镜像占用变化信息以验证清理收益。

#### Scenario: 清理结果可对比
- **WHEN** 脚本完成一次清理流程（含 DryRun 或实际执行）
- **THEN** 输出中包含清理前后统计及差异信息

### Requirement: Docker dependency check
系统 SHALL 在执行前检查 Docker CLI 可用性；若环境不满足，MUST 以非零退出并提供可理解错误信息。

#### Scenario: Docker 不可用时快速失败
- **WHEN** 运行环境不存在可用的 `docker` 命令
- **THEN** 脚本立即失败并提示 Docker 不可用原因
