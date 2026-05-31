# 创建通用整理分类技能

## Goal

在 `ai/skills/dev` 下创建一个通用的“整理分类”agent skill，帮助 agent 面对文件目录结构、文章目录结构、知识资料、配置清单等对象时，先建立分类原则，再给出可执行的整理方案。

用户价值：

- 面对杂乱文件、目录、文档结构时，agent 不只机械移动文件，而是先识别对象类型、使用场景和归属规则。
- 把“万物皆文件”的整理思路沉淀成可复用 skill，使目录结构、文章结构和其他可文本化对象都能按同一套分类流程处理。
- 让后续 AI 整理任务更可控：能说明保留、合并、迁移、归档、删除或暂缓的理由，并避免破坏现有入口或引用。

## Confirmed Facts

- 用户明确指定目标位置为 `ai/skills/dev`。
- 用户希望创建一个“通用的整理分类”技能，适用于文件目录结构、文章目录结构等更广义的整理分类场景。
- 用户确认首版应偏“泛化强的整理分类技能”，并把文件目录整理作为最常用的一等场景。
- 用户要求 skill 内置多种整理方法论，让 agent 能按场景选择方法，而不是只套用单一分类规则。
- 用户确认 skill 默认先产出整理方案；用户批准后可以继续执行，但必须按风险分级处理。
- 用户确认 skill 名称使用 `organize-classify`。
- 用户确认整理方案默认输出为 Markdown 表格加简短决策摘要。
- 用户确认采用渐进加载组织：`SKILL.md` 放核心流程、方法路由和安全边界，详细方法论与示例拆入 `references/`。
- 用户强调 skill 不能绑定本仓库结构；本仓库只能提供开发规范和风险检查经验，不能成为通用整理建议的默认答案。
- 用户要求编程目录结构方法论具备通用性，并提供常见编程语言/生态的目录结构推荐，拆成多个 reference 文件维护。
- 用户确认首版编程目录结构 reference 覆盖七组：Python、JavaScript/TypeScript、Go、Rust、JVM、.NET、脚本型项目。
- 用户确认框架有自己的目录结构，skill 不写死具体框架目录；遇到框架项目时应明确要求查框架官方文档和当前项目约定。
- 仓库已有本地开发 skill 目录：`ai/skills/dev/`。
- 当前 `ai/skills/dev` 下已有三类样板：
  - `api-example-test-writer`：纯文档/引用型 skill，包含 `SKILL.md`、`references/`、`examples/`、`agents/openai.yaml`。
  - `dingtalk-doc-playwright`：轻脚本型 skill，包含 `SKILL.md`、`scripts/`。
  - `database-query`：TypeScript 脚本型 skill，包含源码、测试、构建产物和分发脚本。
- `.trellis/spec/infra/agent-skill-dev.md` 规定：
  - `SKILL.md` 是必需文件，frontmatter `name` 必须与目录名一致。
  - 纯文档 skill 可以只有 `SKILL.md`、`references/`、`examples/`。
  - 若包含脚本，应按 TypeScript 或 Python 脚本型 skill 的运行、测试、分发契约处理。
- 系统 `skill-creator` 指南要求：
  - skill 名称使用小写字母、数字和连字符。
  - `description` 要清楚说明能力和触发场景。
  - `SKILL.md` 保持精炼，较长内容按需拆入 `references/`。
  - 不创建无关 `README.md`、`CHANGELOG.md`、`QUICK_REFERENCE.md` 等辅助文件。
- 相近历史任务 `05-30-root-directory-cleanup` 已沉淀过根目录整理经验：先定义归属规则，再做迁移或清理；外部工具强约定的根目录入口应保留；运行产物、缓存和本地数据应通过 ignore 或清理策略处理，而不是作为源码归档对象。
- `docs/cheatsheet/README.md` 已有分类原则：新增文档优先按“主要使用场景”分类，避免只按文档里偶然出现的命令归类；跨多个目录时，优先选择读者最可能查找的入口，并补交叉链接。
- 本仓库中的 `.trellis/spec/guides/cross-layer-thinking-guide.md`、`.trellis/spec/guides/code-reuse-thinking-guide.md`、`psutils` 包规范和 CLI 项目结构只能作为“整理时要先识别入口、边界、引用、共享能力和验证入口”的证据来源；新 skill 不得把这些路径或目录名写成通用默认结构。

## Methodology Candidates

首版候选方法论：

- 使用场景优先：按用户查找、使用或维护时最自然的入口分类。
- 生命周期分类：按 inbox、active、reference、archive、deprecated、generated 等状态分类。
- 领域/职责分类：按业务域、技术域、工具域、文档主题或模块职责分类。
- 对象类型分类：按文件类型、内容类型、媒介类型或格式分类；适合初筛，不应单独支配长期结构。
- 频率/重要性分类：按高频入口、低频参考、长期归档、临时缓存分类。
- 代码项目结构整理：按入口、领域/功能、架构层、共享能力、测试、配置、生成产物和运行态数据判断归属；优先沿用项目已有结构，不凭个人偏好重排。细分方法见下方“编程目录结构方法论候选”。
- LATCH：按 Location、Alphabet、Time、Category、Hierarchy 选择信息组织轴。
- MECE：检查分类是否尽量互斥且整体覆盖，避免大量“其他”和重复归属。
- 渐进整理：先盘点和标记，再小批迁移，最后更新引用和验证；适合高风险文件目录整理。

### 编程目录结构方法论候选

- 入口优先：先识别 CLI、API、应用启动、包导出、配置加载、测试和构建入口；入口文件保持薄，复杂逻辑下沉到模块。
- 包/工作区边界优先：先识别 monorepo workspace、包级 manifest、语言模块文件、构建文件等边界；不要把某个包内规则扩散到根目录或其他包。
- 功能/领域垂直切片：把同一业务能力的路由、服务、模型、测试、文档靠近组织；适合产品功能快速演进的应用代码。
- 架构层分层：按 `cli`、`api`、`service`、`domain`、`adapter`、`infra`、`ui` 等层分离；适合边界清晰、跨功能复用多的系统。
- Ports/Adapters：核心领域逻辑放中间，外部数据库、HTTP、文件系统、模型供应商、CLI 等作为 adapter；适合需要替换外部依赖的工具或服务。
- 共享能力抽取：相似逻辑出现多处时，抽到 `shared`、`core`、`utils`、公共模块或包内源码真相；但避免为了单次使用过早抽象。
- 测试邻近或镜像：小模块优先 colocated test，大型或跨包测试使用镜像目录或根级集成测试；测试位置跟随验证对象和运行入口。
- 配置分层：把默认配置、环境变量、本机私有覆盖、示例配置和生成配置分开；遵循“CLI > ENV > local > config > defaults”一类优先级。
- 源码/构建产物分离：`src`、`scripts`、`dist`、`bin`、生成 bundle、缓存和报告要有明确边界；生成物不反向成为源码真相。
- 文档随代码或集中索引：API/模块说明靠近代码，长期知识和跨模块说明放集中 docs；索引按读者最可能查找的入口组织。
- 语言/生态约定优先：当项目使用某种语言、框架或包管理器时，优先读取该生态的官方目录约定和项目现有约定，再给出整理建议。
- 框架官方约定优先：遇到 Next.js、Django、FastAPI、Spring Boot、ASP.NET、Flutter、Android 等框架时，不套用语言通用结构替代框架结构；先查框架文档和项目已有约定。

### 编程目录结构 Reference 规划

除通用方法论外，首版增加多个编程结构 reference 文件，避免把语言细节塞进 `SKILL.md`：

- `references/programming-structure.md`：跨语言通用原则、架构维度、风险检查和输出模板。
- `references/programming-python.md`：Python 包、脚本、CLI、测试、配置和数据目录建议。
- `references/programming-javascript-typescript.md`：Node.js、TypeScript、前后端应用、包入口、测试和构建产物建议。
- `references/programming-go.md`：Go module、`cmd/`、`internal/`、`pkg/`、测试和配置建议。
- `references/programming-rust.md`：Cargo 项目、workspace、`src/`、`bin/`、examples、tests、benches 建议。
- `references/programming-jvm.md`：Java/Kotlin/Gradle/Maven 常见源码、测试、资源和多模块结构建议。
- `references/programming-dotnet.md`：.NET solution、projects、tests、src/test 分组和配置建议。
- `references/programming-scripts.md`：Shell、PowerShell、单文件脚本、工具型脚本、bin shim、生成 bundle 和跨平台脚本建议。

## Requirements

- 新 skill 必须放在 `ai/skills/dev/organize-classify/` 下，至少包含 `SKILL.md`。
- `SKILL.md` 主要内容使用中文。
- skill 应覆盖至少两类核心场景：
  - 文件/目录结构整理：项目根目录、下载目录、资料库、配置目录等。
  - 文章/文档目录结构整理：标题层级、大纲、章节归属、信息架构等。
- skill 的工作流必须要求 agent 先读取可用证据，再提出分类方案；仓库、文件系统或文档内容能回答的问题，不应直接问用户。
- skill 应输出可执行的分类结果，而不只是抽象原则。分类结果应包含对象、建议归属、操作类型和理由。
- skill 默认整理方案格式为 Markdown 表格，列包含：`对象`、`当前位置/结构`、`建议归属`、`操作`、`方法论依据`、`风险`、`验证方式`。
- 输出前应先给简短决策摘要，说明本次采用的主分类维度、辅助标签和关键风险。
- 表格格式应适配不同对象：文件目录中“当前位置/结构”表示路径；文章目录中表示章节层级；代码项目中表示文件路径、模块位置或架构层。
- skill 默认先给整理方案，不直接改动目标内容；用户明确批准后才进入执行。
- skill 应区分低风险和高风险执行：
  - 低风险：文章大纲、文档目录、非破坏性重排建议等，可在确认后直接修改。
  - 高风险：文件目录、代码项目结构、批量重命名、删除、移动入口文件、修改外部引用等，必须先检查引用和验证路径，再等待明确批准。
- skill 必须包含安全边界：
  - 整理前识别入口文件、外部工具约定路径、被引用路径、生成产物、本机私有配置和敏感信息。
  - 涉及移动、删除、重命名或批量改写前，需要先给出计划并等待用户批准。
  - 默认不删除内容；删除应作为单独高风险动作。
- skill 应保持足够通用，不绑定某个仓库或某种文件格式。
- skill 应内置多种整理方法论，并提供选择指引。方法论既要覆盖通用分类，也要覆盖文件目录和文档结构等高频场景。
- skill 应包含代码项目结构整理方法论，用于源码仓库、脚本目录、配置目录、测试目录、构建产物和文档入口等开发场景。
- 编程目录结构建议必须保持通用性：先识别语言/生态/框架/包管理器，再参考对应 reference，不得默认套用本仓库目录。
- 常见编程语言/生态的目录结构建议应拆入多个 `references/programming-*.md` 文件，`SKILL.md` 只保留选择入口和读取指引。
- 编程语言/生态目录建议应优先基于官方文档或事实上的生态标准；实现时需要记录引用来源或至少说明“以官方/生态约定为准”。
- 框架级目录结构不在首版 reference 中展开；skill 应写明框架项目必须先读取框架官方文档、框架配置和当前项目结构，再提出整理方案。
- 文件目录整理是一等场景：skill 应额外包含路径引用、安全迁移、入口文件、生成产物、本地私有文件和外部工具约定的检查要求。
- 对一个对象可组合多种方法论，但最终输出必须收敛到一个主分类维度和必要的辅助标签，避免同时并列多套目录树。
- 初版优先实现为纯文档 skill；除非规划中明确发现稳定、重复、可确定的机器化操作，否则不新增脚本。
- 如需要详细分类模板或示例，应使用 `references/` 或 `examples/`，保持 `SKILL.md` 精炼。
- `SKILL.md` 应包含何时读取引用文件的导航：
  - `references/methodologies.md`：详细方法论、选择信号、不适用情况和组合规则。
  - `references/examples.md`：文件目录、文章目录、代码项目结构的整理方案示例。
  - `references/programming-structure.md` 与 `references/programming-*.md`：编程目录结构通用方法和语言/生态推荐。

## Acceptance Criteria

- [x] `ai/skills/dev/organize-classify/SKILL.md` 存在，frontmatter `name` 为 `organize-classify`。
- [x] `description` 明确包含“整理/分类/目录结构/文章结构/文件归属”等触发语义，并符合 skill 触发描述要求。
- [x] `SKILL.md` 使用中文描述主要流程和边界。
- [x] skill 工作流包含证据盘点、分类维度选择、方案输出、风险检查、执行前确认、执行后验证。
- [x] skill 明确支持文件目录结构和文章目录结构两个场景。
- [x] skill 内置多种整理方法论，并说明每种方法适合的场景、输入信号和不适用情况。
- [x] skill 包含代码项目结构整理方法论，并要求先读取项目规范、现有目录、构建入口、测试入口和引用关系。
- [x] skill 明确说明编程目录结构建议不绑定本仓库，必须先识别语言/生态/框架/包管理器和现有项目约定。
- [x] skill 拆分多个编程目录结构 reference 文件，至少覆盖 Python、JavaScript/TypeScript、Go、Rust、JVM、.NET 和脚本型项目。
- [x] skill 明确说明框架级目录结构以框架官方文档和当前项目约定为准，不在首版写死具体框架结构。
- [x] skill 明确禁止在未获批准前执行删除、批量移动、批量重命名或会破坏引用的改动。
- [x] skill 区分方案阶段与执行阶段，并写清低风险/高风险动作的确认门槛。
- [x] skill 提供 Markdown 表格整理方案格式，列包含对象、位置、建议归属、操作、方法论依据、风险和验证方式。
- [x] 若创建 `references/` 或 `examples/`，`SKILL.md` 能说明何时读取它们。
- [x] 方法论细节从 `SKILL.md` 拆到 `references/methodologies.md`，示例拆到 `references/examples.md`。
- [x] 通过 skill 结构校验，或记录无法校验的原因。
- [x] 若只新增/修改文档型 skill，不强制执行根目录 `pnpm qa`；若新增脚本或测试，则按项目规则执行对应验证。

## Out of Scope

- 初版不做自动移动、删除、重命名或批量改写脚本。
- 初版不实现全盘文件索引、重复文件检测、OCR、内容向量检索或长期知识库系统。
- 初版不绑定单一目录哲学，不强制所有整理任务采用同一种分类维度。
- 初版不把某个个人知识管理系统当作唯一标准；PARA、Zettelkasten、LATCH、MECE 等都只能作为可选方法，而不是默认强制框架。

## Notes

- 当前判断为复杂文档型 skill：虽然不新增脚本，但会创建多份 reference 文件并覆盖多个编程生态，因此需要 `design.md` 与 `implement.md`。
- skill 名称已确定为 `organize-classify`。

## Open Questions

- 是否按当前 PRD 进入实现阶段？
