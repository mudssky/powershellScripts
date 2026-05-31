# organize-classify 设计

## Architecture and Boundaries

本任务交付一个纯文档型 agent skill，放在 `ai/skills/dev/organize-classify/`。它不实现脚本、不自动扫描、不自动迁移文件，只提供 agent 使用的整理分类工作流、方法路由、风险边界和可按需读取的 reference。

目录结构：

```text
ai/skills/dev/organize-classify/
  SKILL.md
  references/
    methodologies.md
    examples.md
    programming-structure.md
    programming-python.md
    programming-javascript-typescript.md
    programming-go.md
    programming-rust.md
    programming-jvm.md
    programming-dotnet.md
    programming-scripts.md
```

`SKILL.md` 是触发后的主入口，保持精炼，负责：

- 说明使用时机和不使用时机。
- 要求先读取证据，再分类和给方案。
- 路由到通用方法论、文件目录、文章目录、代码项目结构等场景。
- 给出默认 Markdown 表格输出格式。
- 写清方案阶段与执行阶段的确认门槛。
- 指明何时读取各个 `references/*.md`。

`references/methodologies.md` 负责通用整理方法论：

- 使用场景优先、生命周期分类、领域/职责分类、对象类型分类、频率/重要性分类、LATCH、MECE、渐进整理。
- 每种方法写明适用场景、输入信号、不适用情况、可组合方式。
- 强调最终必须收敛到一个主分类维度和少量辅助标签。

`references/programming-structure.md` 负责跨语言编程目录结构原则：

- 入口优先、包/工作区边界、垂直切片、架构分层、Ports/Adapters、共享能力抽取、测试位置、配置分层、源码/产物分离、文档位置。
- 要求先识别语言、框架、包管理器、构建工具、测试入口和现有项目约定。
- 明确框架级目录结构以框架官方文档和当前项目约定为准，本 skill 不写死具体框架结构。

语言/生态 reference 只提供稳定、通用的结构建议，不替代框架官方结构：

- Python：包、脚本、CLI、测试、配置、数据目录。
- JavaScript/TypeScript：Node 包、库、CLI、前后端应用、测试和构建产物。
- Go：module、`cmd/`、`internal/`、可选 `pkg/`、测试、配置。
- Rust：Cargo package/workspace、`src/`、`src/bin/`、`examples/`、`tests/`、`benches/`。
- JVM：Maven/Gradle、`src/main`、`src/test`、resources、多模块。
- .NET：solution、projects、`src`/`tests`、配置和多项目边界。
- Scripts：Shell、PowerShell、单文件脚本、工具型脚本、bin shim、生成 bundle、跨平台脚本。

`references/examples.md` 提供三个示例：

- 文件目录整理方案。
- 文章目录整理方案。
- 代码项目结构整理方案。

## Data Flow and Contracts

使用 skill 时的数据流：

1. 用户提出整理目标。
2. Agent 读取可用证据：目录树、文件内容、现有文档、项目配置、引用关系、框架/语言约定。
3. Agent 判断对象类型：文件目录、文章目录、代码项目结构、知识资料、配置清单等。
4. Agent 选择主方法论和辅助标签。
5. Agent 输出决策摘要和 Markdown 表格方案。
6. 用户批准后，Agent 才能进入执行阶段。
7. 执行后按方案中的验证方式检查引用、路径、文档、构建/测试入口或内容一致性。

默认方案表格列：

```text
对象 | 当前位置/结构 | 建议归属 | 操作 | 方法论依据 | 风险 | 验证方式
```

风险分级：

- 低风险：文章标题重排、非破坏性文档目录调整、纯建议输出。
- 高风险：移动文件、删除文件、批量重命名、移动入口文件、修改代码项目结构、改写外部引用。

## Compatibility and Migration Notes

- 不创建脚本或依赖文件，因此不引入安装态运行依赖。
- 不绑定本仓库目录结构；本仓库经验只用于指导“先查证据、识别边界、保护入口和引用”。
- 不创建 `README.md`、`CHANGELOG.md`、`QUICK_REFERENCE.md` 等额外文档。
- 框架目录结构可能随版本变化；skill 只写“查框架官方文档和当前项目约定”的原则，不固化具体框架结构。

## Trade-offs

- 拆分多个 reference 文件会增加文件数，但保持 `SKILL.md` 精炼，符合渐进加载。
- 语言级结构建议比框架级建议更稳定，但当用户整理具体框架项目时，Agent 需要额外查框架文档。
- 初版不写自动扫描脚本，牺牲一部分自动化，换取通用性和低维护成本。

## Rollback

本任务只新增 `ai/skills/dev/organize-classify/` 和 Trellis 规划文件。若实现方向不合适，可删除该 skill 目录并回滚对应任务文档，不影响现有代码运行。
