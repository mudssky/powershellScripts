# pgBackRest 配置示例与维护脚本

## Goal

在 `config/database/backup/pgBackRest/` 下补充 pgBackRest 配置示例、中文文档与维护脚本，服务于 `postgresql://postgres:12345678@macmini:5432/lobechat` 对应 PostgreSQL 实例的整实例备份，并明确“某数据库某表”应采用 `pg_dump` 逻辑备份的最佳实践。

## What I Already Know

- 用户要求目标目录为 `config/database/backup/pgBackRest`。
- 用户要求配置文件使用 `.local` 结尾。
- 用户提供的数据库连接串为 `postgresql://postgres:12345678@macmini:5432/lobechat`。
- 用户希望维护脚本能在任意机器执行；macmini 当前可通过 Tailscale IP/地址访问。
- 需求包含 pgBackRest 配置示例、文档、整库备份、某数据库某表备份最佳实践、维护脚本。
- 仓库中已有 `config/database/backup/pgBackRest/` 目录，目前为空。
- 仓库已有 PostgreSQL 逻辑备份工具与文档：`scripts/pwsh/devops/Postgres-Toolkit.ps1`、`docs/cheatsheet/database/postgresql/backup-restore.md`。
- pgBackRest 是实例/集群级物理备份工具；表级备份最佳实践应使用 `pg_dump -t`。
- `pg_dump` 不提供真正的增量备份；如果要增量，应使用 pgBackRest 的整实例 full/diff/incr 备份链。
- 仓库已有 `scripts/pwsh/devops/postgresql` 备份脚本，应在现有 toolkit 上扩展，而不是另起一套 Bash 维护入口。

## Assumptions (temporary)

- `.local` 配置用于本机真实环境，不应提交可泄露密码的真实文件；仓库可提交 `.example` 或无敏感值模板。
- 维护脚本优先复用 `scripts/pwsh/devops/postgresql`，保持 `Postgres-Toolkit.ps1` 为统一入口。
- 目标 PostgreSQL 主机名 `macmini` 或其 Tailscale IP 可被执行脚本的机器访问。
- `lobechat` 是需要逻辑表级备份的默认数据库名；pgBackRest 整实例备份仍以 PostgreSQL data directory 为范围。
- pgBackRest 整实例远程备份默认采用 Tailscale + SSH 模式；若用户明确要避免 SSH，再考虑 pgBackRest TLS server。

## Open Questions

- 备份仓库应默认存放在执行脚本的当前机器，还是固定存放到某个共享/NAS/服务器路径？
- 定时任务 MVP 是否只实现 PM2 模板，还是同时生成 systemd / Windows Task Scheduler / launchd 模板？

## Requirements (evolving)

- 在 `config/database/backup/pgBackRest/` 下提供 pgBackRest 配置示例和中文 README。
- 提供 `.local` 结尾的本机配置入口或模板，满足用户命名偏好。
- 支持在任意能通过 Tailscale 访问 macmini 的机器上运行维护脚本。
- 文档说明 pgBackRest 整实例备份、WAL 归档、保留策略、初始化与日常维护命令。
- 文档说明 pgBackRest 远程备份不是仅依赖 PostgreSQL 连接串：需要 macmini 上安装 pgBackRest，并通过 SSH 或 TLS 让执行机访问数据库主机的 data directory/WAL 配置。
- 文档说明“备份某数据库某表”使用 `pg_dump -t` / `pg_restore -t`，并给出 `lobechat` 示例。
- 文档说明 `pg_dump` 是逻辑快照而非增量备份；需要增量时使用 pgBackRest full/diff/incr 整实例链路。
- 扩展现有 `Postgres-Toolkit.ps1`，至少覆盖 pgBackRest 检查、创建 stanza、全量备份、差异/增量备份、查看状态、过期清理；表级逻辑备份继续由现有 `backup --table` 承担。
- 避免将真实密码提交到仓库；需要提供本地 secret 文件或环境变量方案。
- 若引入 PM2 定时执行，必须明确它是调度层，不重写备份逻辑；最终执行仍调用 `Postgres-Toolkit.ps1 pgbackrest ...`。
- `bin/` 入口应由 `Manage-BinScripts.ps1` 生成，不手写提交 shim；PostgreSQL toolkit 使用 `scripts/pwsh/**/tool.psd1` 暴露稳定公开入口。
- 跨平台定时任务采用“备份 CLI 跨平台、调度器按平台适配”的模型，不实现长期运行的 PowerShell 自制 scheduler loop。
- 可选实现一个 Node.js 定时任务服务，由 PM2 管理常驻进程；Node 服务仅负责任务调度、互斥、日志和调用 toolkit，不实现 pgBackRest 参数拼装之外的备份逻辑。
- 可选实现一个 Go 定时任务服务，由 PM2 管理常驻二进制；Go 服务与 Node 服务职责相同，但会引入新的 Go build/test/release 轨道。
- Windows 桌面通知是显式需求：备份开始/成功/失败时应支持发送通知；但本地 toast 仅在运行于当前登录用户会话时可靠，若服务跑在 SYSTEM/非交互会话，应使用 webhook/ntfy/email 等替代通知渠道。

## Acceptance Criteria (evolving)

- [ ] `config/database/backup/pgBackRest/` 包含可读的中文 README，能解释 pgBackRest 与 pg_dump 的职责边界。
- [ ] 示例配置包含 `macmini`、`lobechat` 场景所需字段，并避免提交真实密码。
- [ ] 示例配置体现 Tailscale 网络访问场景，允许将 `macmini` 替换为 Tailscale IP。
- [ ] `Postgres-Toolkit.ps1` 支持 pgBackRest dry-run 或等价的命令预览能力，降低误操作风险。
- [ ] 表级备份示例能指定 schema/table，并默认指向 `lobechat`。
- [ ] README 明确说明 pg_dump 无通用增量备份，避免用户误以为单表可通过 pg_dump 做增量。
- [ ] 文档包含首次初始化、执行备份、查看备份、恢复注意事项的步骤。
- [ ] 若选择 PM2 路线，文档或脚本必须解释 `cron_restart` 对一次性备份任务的语义，并避免成功退出后被 PM2 自动循环重启。
- [ ] 若选择 Node scheduler 服务，必须限制 PM2 为 fork/单实例运行，任务执行需要 no-overlap 或等价互斥，失败退出码需进入日志并影响健康判断。
- [ ] 若选择 Go scheduler 服务，必须提供 go module、构建命令、测试命令、PM2 `interpreter: none` 配置，以及 Windows 通知后端抽象。
- [ ] Windows 通知后端至少能区分 `backup_started`、`backup_succeeded`、`backup_failed` 三类事件，并允许在非 Windows 或无交互桌面环境下禁用或降级为日志/webhook。
- [ ] 若调整 `bin/` 打包，`Manage-BinScripts.ps1` 测试覆盖 toolkit 入口只暴露公开脚本、不暴露内部模块。

## Definition of Done

- 新增/更新的脚本具备中文注释，函数包含参数和返回值说明。
- 配置文件不需要单元测试。
- 代码改动完成后执行根目录 `pnpm qa`；若维护脚本属于 pwsh 范围则额外执行 `pnpm test:pwsh:all`。
- 文档明确说明敏感信息处理、恢复前验证和 pgBackRest 与 pg_dump 的适用边界。

## Out of Scope

- 不改造现有 `Postgres-Toolkit.ps1` 的核心实现，除非后续确认必须复用。
- 不自动修改远程 PostgreSQL `postgresql.conf` / `pg_hba.conf`。
- 不提交真实生产密码或真实 `.local` secret 文件。
- 不实现完整 PITR 自动恢复流程；先提供恢复说明和必要命令入口。

## Research References

- [`research/pgbackrest-backup-practices.md`](research/pgbackrest-backup-practices.md) — pgBackRest 适合整实例物理备份，表级备份应使用 `pg_dump -t`。
- [`research/pm2-scheduled-backups-and-bin-packaging.md`](research/pm2-scheduled-backups-and-bin-packaging.md) — PM2 可做 cron restart，但应作为调度层；`bin/` 应由 `Manage-BinScripts.ps1` 生成 shim，toolkit bundle 仍走现有构建脚本。
- [`research/cross-platform-scheduler-options.md`](research/cross-platform-scheduler-options.md) — 推荐保留跨平台备份 CLI，通过 PM2/systemd/Windows Task Scheduler/launchd 做薄调度适配。

## Research Notes

### Feasible approaches here

**Approach A: 扩展现有 Postgres Toolkit（推荐）**

- How it works: 在 `scripts/pwsh/devops/postgresql` 增加 `pgbackrest` 子命令；`backup` 继续封装 `pg_dump` 做逻辑库/表快照；`config/database/backup/pgBackRest` 只放配置模板和中文文档。
- Pros: 复用已有连接串、env-file、dry-run、测试和构建体系，避免两套维护脚本分叉。
- Cons: 远端 Linux/macOS 环境需要安装 PowerShell，或使用已构建的 `Postgres-Toolkit.ps1`。

**Approach B: 任意 Tailscale 可达机器远程执行 pgBackRest**

- How it works: 在执行机放 repo，使用 `pg1-host=macmini` 或 Tailscale IP 远程调用数据库主机上的 pgBackRest；表级逻辑备份直接通过 PostgreSQL TCP 连接 `lobechat`。
- Pros: 符合用户“任意机器执行”的目标，备份仓库可与数据库主机隔离，Tailscale 已提供网络可达性。
- Cons: macmini 上仍需要安装 pgBackRest 并配置 SSH 或 pgBackRest TLS server；执行机之间若各自保存 repo，需要额外注意备份分散问题。

**Approach C: 仅文档化 pgBackRest，表级备份完全交给现有 Postgres-Toolkit**

- How it works: pgBackRest 目录只放配置和 README；表级备份引导用户运行现有 PowerShell toolkit。
- Pros: 复用已有工具，新增脚本少。
- Cons: 不能完全满足“提供维护脚本”的直觉预期，Linux/macmini 上使用 PowerShell 可能不如 Bash 直接。

### PM2 / bin packaging follow-up

**Approach D: PM2 仅作为配置模板**

- How it works: 在 `config/database/backup/pgBackRest/` 增加 PM2 ecosystem 示例，定时触发现有 `Postgres-Toolkit.ps1 pgbackrest --action backup --type ...`。
- Pros: 改动轻，符合“配置目录只放模板和 README”的约束。
- Cons: 用户需要自己执行 `pm2 start`、`pm2 save`、`pm2 startup`，脚本级可测试性弱。

**Approach E: PM2 wrapper + ecosystem 模板**

- How it works: 参考 `config/network/rathole/start.ps1` 写一个 PM2 管理包装，只管理 start/stop/logs/status/save/config/dry-run，不实现备份。
- Pros: 操作体验最好，和仓库已有 rathole PM2 风格一致。
- Cons: 在 `config/database/backup/pgBackRest/` 增加脚本会触碰当前 PostgreSQL spec 的边界，需要把它定义为“调度胶水”而非备份维护脚本。

**Approach F: Toolkit scheduler 子命令 + bin manifest（推荐进一步评估）**

- How it works: 在 `scripts/pwsh/devops/postgresql` 增加 scheduler/pm2 命令生成能力；`config/database/backup/pgBackRest/` 只保留模板；通过 `Build-PostgresToolkit.ps1` 生成单文件 bundle，并用 `tool.psd1` 让 `Manage-BinScripts.ps1` 在 `bin/` 暴露公开入口。
- Pros: 最符合现有 toolkit、测试、bundle 与 bin shim 机制。
- Cons: 实现量最大，需要更新 `Manage-BinScripts` 或测试确认 Postgres toolkit 目录工具不会暴露内部脚本。

**Approach G: Node.js scheduler 服务 + PM2 管理**

- How it works: 在 Node 脚本体系里实现一个 `pgbackrest-scheduler` 常驻服务，读取 `pgBackRest` 目录里的 scheduler 配置，按 cron/interval 调用 `Postgres-Toolkit.ps1 pgbackrest ...`；PM2 只负责守护这个 Node 进程。
- Pros: 跨平台体验比 systemd/Task Scheduler/launchd 统一；比 PM2 `cron_restart` 更适合表达一次性备份任务、互斥、重试和日志。
- Cons: 新增一个长期维护的 Node 组件；需要明确停机期间 missed run 是否补跑、多机器是否允许同时调度、PM2 cluster 禁用等边界。

**Approach H: Go scheduler 服务 + PM2 管理**

- How it works: 新增 Go 模块，编译为 `pgbackrest-scheduler` 单二进制；PM2 用 `interpreter: none` 管理该二进制；Go 服务读取配置、按计划调用 `Postgres-Toolkit.ps1 pgbackrest ...`，并在开始/成功/失败时触发通知。
- Pros: 分发体验最好，运行时依赖少，内存占用低；Go 的 `gocron`、`os/exec`、信号处理适合常驻调度服务。
- Cons: 仓库目前没有 Go 服务先例，会增加 Go toolchain、构建产物、测试和发布规范；Windows toast 仍受当前登录用户会话/AppID 限制。

### Notification follow-up

**Option 1: Windows toast local notification**

- Use when: scheduler runs on the Windows desktop session where the user wants to see backup notifications.
- Risk: if PM2 is running as SYSTEM/background service, toast may not appear.

**Option 2: PowerShell BurntToast bridge**

- Use when: we want minimal implementation and can rely on the existing Windows PowerShell module setup.
- Risk: PowerShell module availability and user-session constraints.

**Option 3: Webhook/ntfy/email notification**

- Use when: backup runs on macmini/Linux/NAS but notification should arrive on Windows or phone.
- Risk: requires external endpoint/token but is more reliable than desktop toast for unattended machines.

## Decision (ADR-lite)

**Context**: PostgreSQL toolkit 已经是模块化源码加单文件 bundle 的结构；`Manage-BinScripts.ps1` 已支持 `tool.psd1` 暴露目录型工具入口并隐藏内部脚本。

**Decision**: 使用 `tool.psd1` 作为 PostgreSQL toolkit 进入 `bin/` 的公开入口机制。定时任务不做 PowerShell 自制 scheduler loop；可选方向是在 PM2 下运行 Node/Go scheduler 服务，或让 toolkit 生成/记录 PM2/systemd/Windows Task Scheduler/launchd 等调度器适配。

**Consequences**: `bin/` 不手写 shim；PM2 可作为 MVP 的跨平台-ish 路线。若采用 Node scheduler 服务，需要按 `node-script` 包规范补 TypeScript/Vitest 质量检查；若采用 Go scheduler 服务，需要新增 Go 模块和构建测试规范。两者都必须保持备份执行入口仍为 Postgres Toolkit，并把通知设计成可替换后端。

## Technical Notes

- Context7 查询库：`/websites/pgbackrest_configuration`。
- Context7 文档确认：`pg1-host` 用于远程 PostgreSQL 主机；`pg1-host-type` 支持 `ssh` 和 `tls`，默认 `ssh`。
- 已读本地文件：
  - `.gitignore`
  - `docs/cheatsheet/database/postgresql/backup-restore.md`
  - `scripts/pwsh/devops/postgresql/README.md`
  - `scripts/pwsh/devops/postgresql/docs/help.md`
  - `ai/self-hosted/lobehub/docs/postgres-docker-usage.md`
  - `ai/self-hosted/lobehub/.env.example`
- 当前 git 工作区已有用户/任务改动：`.gitignore` 修改、`.trellis/tasks/05-14-pgbackrest-config-docs/` 未跟踪。
