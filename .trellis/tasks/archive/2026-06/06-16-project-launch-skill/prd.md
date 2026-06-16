# 通用项目启动 skill

## Goal

开发一个可跨 agent 复用的通用项目启动 skill，优先服务 Java/JVM 项目的本地开发启动。

该 skill 应让 agent 能在进入陌生项目后，先识别启动方式和依赖条件，再用一条命令启动一个或多个服务。首版核心体验是：多个服务可在 tmux 中统一编排启动，命令执行后返回 tmux session 名称和可复制的 attach 命令，用户可以用一条命令打开同时查看多个服务日志与交互终端的 tmux 界面。

tmux 是首版默认且主要的启动承载层，因为 agent 需要能进入服务所在终端继续交互、观察输出、执行重启或补充命令。非 tmux 能力仅作为 plan、doctor、dry-run 等诊断/预览能力，不作为主要启动路径。

## User Value

- 减少 Java 多服务项目启动前的人工排查：JDK、Maven/Gradle、配置 profile、端口占用、依赖服务和构建目录冲突。
- 对 agent 提供标准化操作入口，避免每次根据 README 手写临时启动命令。
- 多服务启动后不阻塞 agent 会话，用户仍能随时进入 tmux 查看、停止或重启单个服务。

## Requirements

- Skill 形态
  - 新 skill 名称为 `project-launcher`，放在 `ai/skills/dev/project-launcher/` 下，文档主要内容使用中文。
  - CLI 脚本名为 `project-launcher.js`，安装态入口为 `node scripts/project-launcher.js ...`。
  - 首版采用 TypeScript CLI 实现，提交源码、测试和构建后的 `scripts/*.js` 分发入口。
  - `SKILL.md` 中的命令必须指向安装态可直接运行的 `node scripts/*.js`，不要求用户先构建源码。
- CLI 命令形态
  - `plan`：发现项目、解析配置、输出启动计划，不执行长期启动。
  - `doctor`：检查 tmux、Java、Maven/Gradle wrapper 或 CLI、端口和外部依赖就绪情况。
  - `start --service <name>`：启动指定服务或服务子集。
  - `start --all`：显式启动发现到或配置声明的全部服务。
  - `start --name <name> --command <command>`：支持一次性命令覆盖，用于启动发现不到或非标准的简单服务。
  - 一次性命令默认不写配置；传 `--save` 时可记录到本机私有 `project-launch.local.json`，下次可通过 `--service <name>` 启动。
  - `--save` 遇到同名 service 已存在时默认报错，不覆盖；只有显式传 `--overwrite` 才替换已有本机配置。
  - `start` 默认不直接 attach，执行完成后返回 session 名称、attach 命令和服务映射；需要进入 tmux 时显式传 `--attach`。
  - `attach`：输出或执行进入当前项目 tmux session 的命令。
  - `stop`：停止由本 skill 管理的当前项目 tmux session。
  - `init --write-gitignore`：可选写入项目初始化辅助内容，例如把 `.project-launcher/` 加入 `.gitignore`；默认命令不自动修改项目文件。
- 目标项目范围
  - 首版重点支持 Java/JVM 项目，优先识别 Maven、Gradle、Spring Boot 常见启动方式。
  - 前端、Go、Rust/Cargo 等语言暂不作为首版深度目标；可以通过显式自定义命令接入，但不做复杂自动推断。
- 配置与命令计划
  - 支持零配置启动：简单单服务 Java/JVM 项目不需要配置文件即可生成启动计划并启动。
  - 支持零配置发现一个项目内的多个服务，并允许通过 `--service <name>` 指定启动单个服务或服务子集。
  - 零配置发现到多个服务时，未传 `--service` 或 `--all` 默认只输出计划和候选服务，不直接启动全部候选。
  - 零配置发现默认保守：只把明显可运行的服务模块作为启动候选，不确定模块仅列为 ignored/unknown，不自动启动。
  - 配置文件是复杂项目的增强入口，不是首版启动的强制前提。
  - 支持显式指定配置文件或 profile；显式 `--config` 优先级最高。
  - 首版配置优先使用项目级 `project-launch.config.json` / `project-launch.local.json`；真实本机差异放入被忽略的 `*.local.json`。
  - 写回本机私有配置前必须在同目录创建时间戳 `.bak` 备份；不自动写回可提交的 `project-launch.config.json`。
  - 支持以可预览的启动计划展示服务名、工作目录、启动命令、环境变量摘要、端口、tmux session/window/pane 布局。
  - 支持多服务配置，一次启动多个服务。
- 输出格式
  - CLI 支持 `--format text|json`，默认 `text`。
  - `plan`、`doctor`、`start` 至少支持 JSON 输出，便于 agent 解析 session 名、attach 命令、服务映射、端口和诊断失败原因。
- 依赖与环境检测
  - 启动前检测必要 CLI，例如 `java`、`mvn`、`gradle` 或项目 wrapper、`tmux`。
  - 启动前检测端口占用，并给出占用进程或至少给出冲突端口。
  - 对缺失依赖只给出诊断和安装建议，不自动安装全局依赖。
  - 对数据库、Redis、MQ、Docker Compose 等外部依赖服务，MVP 默认只检测和提示，不自动拉起服务。
  - 支持显式配置 `preflight` / `prepare` / `dependencies[].checkCommand` 这类受控检查命令；依赖启动命令若进入 MVP，必须显式配置并由用户传 `--start-deps` 才执行。
- tmux 编排
  - tmux 是主要启动方式；执行真实多服务启动时默认进入 tmux 编排路径。
  - 支持在 tmux 中创建或复用命名 session。
  - tmux session 默认命名为 `pl-<project-slug>`；同一项目多配置可追加 profile 或短 hash。
  - 使用 `.project-launcher/session.json` 保存运行态元数据，用于识别本 skill 创建的 session、项目根路径、配置指纹、服务列表和创建时间。
  - 如果项目 `.gitignore` 未忽略 `.project-launcher/`，默认只提示建议，不自动修改；只有用户显式执行初始化写入命令时才修改 `.gitignore`。
  - MVP 默认布局为一个 tmux session 内一个 `dev` window，多服务使用多个 pane 平铺展示。
  - 支持为多个服务创建可查看的 tmux 界面；例如同时启动三个服务时，提供一条 `tmux attach ...` 命令进入能同屏看到三个服务的界面。
  - 启动命令返回 session 名称、attach 命令、服务到 pane/window 的映射。
  - 同名 session 已存在时，默认只复用由本 skill 创建、且工作目录/配置匹配的 session；其他同名 session 直接报错，并提示使用 `--attach`、`--replace` 或换 session 名。
- 多服务编译冲突
  - 默认串行执行每个服务的预编译、依赖准备或短生命周期构建步骤，再将长期 dev/run 命令放入各自 tmux pane。
  - 并发构建默认关闭；只有用户显式传 `--allow-parallel-build` 或配置声明服务可并行构建时才开启。
  - Maven 多模块优先使用 root reactor 与 `-pl` 选择模块；Gradle 多项目优先使用 `:service:taskName` 选择子项目任务。
  - 若检测到多个服务会同时执行 `compile`、`build`、`package` 等短生命周期构建命令，plan 阶段应给出并发风险提示。
- 热重载
  - 支持 Java 常见开发热重载方式，例如 Spring Boot devtools、Maven/Gradle continuous build 或项目自定义 watch 命令。
  - 热重载能力应以项目已有能力和显式配置为主，不应为了热重载强行改写业务项目。
  - CLI 提供 `--reload auto|off|command`，默认 `auto`。
  - `auto` 优先复用项目已有 dev/run/watch 能力；检测不到可靠热重载能力时正常启动并提示未启用热重载。
- 安全边界
  - 不把真实 secret、token、生产连接串写入可提交配置。
  - 默认面向本地开发环境，不自动连接生产服务或执行破坏性命令。

## Acceptance Criteria

- [ ] 新 skill 有中文 `SKILL.md`，frontmatter `name` 与目录名一致，并清楚说明使用时机、工作流程和边界。
- [ ] 新 skill 目录名、frontmatter、脚本名和文档命令统一使用 `project-launcher` / `project-launcher.js`。
- [ ] CLI 能输出 `--help`，并有至少一个 dry-run/plan 命令展示多服务启动计划。
- [ ] CLI 在没有配置文件时，能对简单单服务 Java/JVM 项目生成启动计划并通过 tmux 启动。
- [ ] CLI 在没有配置文件时，能发现多服务 Java/JVM 项目的服务候选，并支持 `--service <name>` 只启动指定服务。
- [ ] CLI 在零配置发现多个服务但用户未传 `--service` 或 `--all` 时，不启动服务，只输出可执行的候选计划和下一步命令。
- [ ] CLI 不会把普通 library、parent/aggregator、model/common/sdk 等不明确可运行的模块自动纳入启动候选。
- [ ] CLI 支持 `start --name <name> --command <command>` 一次性启动；传 `--save` 时写入 `project-launch.local.json` 并先创建 `.bak` 备份。
- [ ] `--save` 写入同名 service 时默认报错；传 `--overwrite` 才替换已有本机配置。
- [ ] CLI 能在缺少 `tmux`、`java`、`mvn`/`gradle` 时给出清晰诊断，不直接崩溃为堆栈。
- [ ] CLI 能检测配置中声明的端口占用，并阻止或明确提示冲突。
- [ ] CLI 对外部依赖服务默认只检测和提示；不会默认执行 `docker compose up`、启动数据库、Redis 或 MQ。
- [ ] CLI 能生成或执行一个三服务 tmux 启动方案，默认使用一个 `dev` window 内三 pane 平铺布局，并返回 session 名称、attach 命令和服务映射。
- [ ] tmux session 默认使用 `pl-<project-slug>` 命名，并通过 `.project-launcher/session.json` 保存运行态元数据。
- [ ] CLI 检测到 `.project-launcher/` 未被 `.gitignore` 忽略时默认只提示；显式 `init --write-gitignore` 才写入忽略规则。
- [ ] CLI 对已有同名 tmux session 有可测试的冲突处理行为：安全匹配时可复用，非本 skill 或目录/配置不匹配时默认报错。
- [ ] CLI 对多服务启动默认生成“串行准备 + tmux 长期运行”的执行计划；并发构建需要显式允许。
- [ ] CLI 在检测到潜在 Maven/Gradle 并发构建风险时，能在 plan 输出中说明风险和开启方式。
- [ ] CLI 支持 `--reload auto|off|command`；默认不改写项目源码或配置，检测不到热重载能力时正常启动并提示原因。
- [ ] `start` 默认不进入长期 tmux TUI，会返回 session 名称、attach 命令和服务映射；传 `--attach` 时才直接进入 tmux。
- [ ] `plan`、`doctor`、`start` 支持 `--format json`，输出包含 session、attachCommand、services、diagnostics 等 agent 可解析字段。
- [ ] 单元测试覆盖配置解析、命令计划生成、端口检测结果处理、tmux 命令生成和 session 冲突策略。
- [ ] 构建产物 `scripts/*.js` 已生成并提交，安装态命令不依赖 TypeScript 运行器。
- [ ] 完成代码改动后执行根目录 `pnpm qa`；若改动涉及 pwsh 相关文件，再执行 `pnpm test:pwsh:all`。

## Confirmed Facts

- 仓库规范要求脚本型 skill 的安装态入口指向 `scripts/*.js` 或轻量 Python 脚本；复杂 TypeScript skill 应提交 `src/`、`tests/`、`package.json`、`tsconfig.json` 和构建后的 JavaScript。
- 现有 `database-query` skill 已采用 TypeScript CLI、`cac`、Vitest、构建后 `scripts/*.js` 的模式，可作为本任务的主要工程样板。
- tmux 官方资料确认支持 detached session、attach/create、attach 并 detach 其他 client、水平/垂直 split pane 等能力，可支撑多服务会话编排。
- 用户已确认 MVP tmux 默认布局采用一个 session、一个 `dev` window、多 pane 平铺，目标是用一条 attach 命令同屏查看多个服务。
- 用户已确认同名 tmux session 默认只安全复用本 skill 创建且工作目录/配置匹配的 session；其他冲突必须显式处理。
- 用户已确认配置文件不能成为简单场景的前提；简单单服务项目、项目内多服务发现、指定服务启动都应支持零配置路径。
- 用户已确认零配置多服务场景下，未传 `--service` 或 `--all` 时默认不启动全部候选，而是输出计划并要求显式选择。
- Maven 官方资料确认多模块项目可通过 reactor 处理模块构建并用 `-pl` 选择子项目；Gradle 官方资料确认多项目任务可用 `:subproject:taskName` 指定，且支持 `--continuous`/`-t` 持续构建。
- 用户已确认多服务编译冲突的首版策略：默认串行预编译/依赖准备，长期服务命令进入 tmux pane；并发构建必须显式开启。
- 用户已确认热重载首版策略：默认 `auto`，只复用项目已有能力或显式配置，不自动改写业务项目。
- 用户已确认依赖服务处理范围：MVP 默认只检测和提示外部依赖，不自动拉起 Docker、数据库、Redis 或 MQ；显式依赖启动需要受控入口。
- 用户已确认 skill 名称为 `project-launcher`，CLI 脚本名为 `project-launcher.js`，主命令包含 `plan`、`doctor`、`start`、`attach`、`stop`。
- 用户已确认零配置服务发现应保守：只把明显可运行的服务模块当候选，不确定模块只列为 ignored/unknown。
- 用户已确认 `start` 默认不直接 attach；需要交互时显式传 `--attach` 或运行返回的 attach 命令。
- 用户已确认 tmux session 稳定前缀使用 `pl-`，不用 `proj-`；`proj-` 更像人工 session 名，反而更容易撞名。
- 用户已确认 `.project-launcher/` 的 `.gitignore` 策略：默认只提示，不自动修改项目；显式初始化写入命令才修改。
- 用户已确认一次性 `--command` 覆盖需要支持，并且可通过显式 `--save` 记录入本机配置，方便下次直接运行。
- 用户已确认 `--save` 遇到同名 service 时默认不覆盖，必须显式 `--overwrite`。
- 用户已确认输出格式需要同时支持人读文本与 agent 可解析 JSON；`plan`、`doctor`、`start` 都应支持 `--format json`。

## Out of Scope

- 首版不做通用 IDE 或完整进程管理平台。
- 首版不自动安装 JDK、Maven、Gradle、tmux、数据库、消息队列或 Docker。
- 首版不承诺深度支持前端、Go、Rust、.NET、Python 等非 JVM 项目的自动推断。
- 首版不改写目标业务项目源码以植入热重载。
- 首版不提供 Web UI。
- 首版不把普通 `spawn` 后台进程管理作为主启动方式；无 tmux 时应诊断失败或只允许 plan/dry-run。

## Open Questions

- MVP 规划基本收束，需要补充 `design.md` 与 `implement.md` 后进入评审。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
