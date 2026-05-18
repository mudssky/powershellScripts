# Dev Container 标准配置模板

## Goal

在 `config/vscode` 下沉淀一套可复制到其他项目的 Dev Container 标准配置模板和最佳实践文档，让后续项目可以快速获得一致的 VS Code 容器开发环境。其中至少包含一个 Java 8 项目模板，并说明如何在容器内复用本机 Codex 或 Claude Code 的配置与登录态。

## What I already know

* 目标目录应位于 `config/vscode` 下，作为 VS Code 相关配置资产的一部分。
* 本次目标是标准模板、配置示例和最佳实践文档，不是只给某一个项目写专用 `.devcontainer`。
* 需要包含一个 Java 8 项目模板；文档中只描述为 Java 8 项目，不出现具体项目名称或本机项目路径。
* 用户希望 Dev Container 能配合本机已有 Codex 或 Claude Code 开发。
* 当前 `config/vscode` 已有 settings、snippets、neovim 配置，没有现成 Dev Container 模板目录。
* 仓库已有 `docs/cheatsheet/vscode/remote/remote-guide.md` 简要提到 Dev Containers，可作为文档体系参考。

## Assumptions (temporary)

* 模板落点采用 `config/vscode/devcontainers/`，目录名直观且与现有 VS Code 配置分组一致。
* Java 8 模板优先使用 Dev Container Feature 安装 Java 8 和 Maven，避免手写 JDK 安装脚本。
* AI Agent 复用优先采用“容器内安装 CLI + 挂载宿主配置目录”的方式，而不是直接挂载宿主可执行文件。
* 首版模板只覆盖 Linux 容器；Windows/macOS 作为宿主时通过 Docker Desktop/VS Code Dev Containers 自行接入。

## Open Questions

* 无。

## Requirements (evolving)

* 在 `config/vscode` 下新增 Dev Container 模板目录。
* 首版采用分层模板库结构，优先提供 base / Java 8 / AI Agent 配置复用的可组合模板。
* 提供至少一个 Java 8 项目可复制模板。
* Java 8 模板需要能复用宿主 Maven 配置，至少覆盖 `~/.m2/settings.xml` 与 Maven 本地仓库缓存的常见需求。
* Java 8 模板需要能复用宿主 Claude Code 配置。
* Java 8 模板需要能复用宿主 Codex 配置。
* 宿主 Maven、Claude Code、Codex 配置默认采用“配置只读 + 缓存读写”的挂载策略。
* 提供模板使用文档，说明复制到项目 `.devcontainer/` 的方式、可调整项和安全注意事项。
* 文档不得出现用户提供的具体项目名称或本机项目路径。
* 模板和文档需要说明 Codex / Claude Code 在容器内复用本机配置的推荐方式。
* 模板不得写入真实 token、API key、私有路径或项目专属配置。

## Acceptance Criteria (evolving)

* [x] `config/vscode` 下存在清晰命名的 Dev Container 模板目录。
* [x] 至少一个 Java 8 模板包含可用的 `devcontainer.json`。
* [x] Java 8 模板包含宿主 Maven 配置/缓存挂载方案。
* [x] Java 8 模板包含宿主 Claude Code 配置挂载方案。
* [x] Java 8 模板包含宿主 Codex 配置挂载方案。
* [x] 默认挂载策略体现配置只读、缓存读写，并在文档中解释原因与调整方式。
* [x] 文档能说明如何复制模板到任意项目的 `.devcontainer/`。
* [x] 文档包含 Codex / Claude Code 配置复用说明，并明确安全边界。
* [x] 文档和模板中不出现具体项目名称或本机项目路径。
* [x] 根目录 `pnpm qa` 通过，或如有环境限制则记录原因。

## Definition of Done (team quality bar)

* Tests added/updated only where business logic or reusable script behavior changes.
* Lint / typecheck / CI green where applicable.
* Docs/notes updated because this task主要产物是配置模板与文档。
* Rollout/rollback considered: 模板是新增资产，可通过删除新增目录回滚。

## Out of Scope (explicit)

* 不为任何具体业务项目直接写入 `.devcontainer`。
* 不在模板中固化真实 API key、登录态、私有代理、私服地址或本机项目路径。
* 不实现自动复制/安装脚本，除非后续收敛时明确纳入。
* 不处理 Java 8 项目的私有 Maven 仓库、证书、数据库、中间件等项目专属依赖。

## Technical Notes

* 已检查 `config/vscode`，当前包含 settings、snippets、neovim 等配置资产。
* 已检查 `docs/cheatsheet/vscode/remote/remote-guide.md`，已有远程开发概览，可补充链接或保持模板目录内自带 README。
* 已通过 Context7 查询 Dev Container 官方资料，确认 `features`、`mounts`、`remoteEnv`、`customizations.vscode`、`remoteUser` 等字段适合本任务。
* 用户提供的 `.sdkmanrc` 示例指向 Java 8；该信息只用于确定 Java 版本，不写入用户可读文档的项目身份信息。

## Research References

* [`research/devcontainer-template-notes.md`](research/devcontainer-template-notes.md) — Dev Container 模板字段、Java Feature 与 AI Agent 配置复用建议。

## Research Notes

### Feasible approaches here

**Approach A: 一个完整 Java 8 + AI Agent 模板**

* How it works: 只提供 `java8-ai-agents/` 一个可复制目录，内含 Java 8、Maven、Node、Codex/Claude 配置挂载建议。
* Pros: 首版最简单，用户拿来即用。
* Cons: 复用到非 Java 项目时需要删改，标准模板库的扩展性弱。

**Approach B: 分层模板库（已选择）**

* How it works: 提供 `base/`、`java8/`、`ai-agents/` 或一个 Java 8 组合模板加共享文档，明确哪些片段可合并。
* Pros: 更像标准配置模板库，后续可扩展 Node、Python、Go 等项目模板。
* Cons: 首版文件数略多，文档需要解释组合方式。

**Approach C: 只写文档和片段，不提供完整模板**

* How it works: 用 README 展示 JSONC 片段，用户按需拼装。
* Pros: 最灵活，维护成本低。
* Cons: 落地成本高，不能直接复制使用。

## Expansion Sweep

* Future evolution: 后续可能扩展 Node、Python、Go、数据库客户端、Docker-in-Docker 等模板；首版目录结构应允许新增语言模板。
* Related scenarios: VS Code Remote 文档已有概览，新文档应能被发现，但不必改动所有远程开发文档。
* Failure/edge cases: 需要提醒挂载宿主 Codex/Claude 配置只适合可信容器；宿主 CLI 二进制不一定能直接在容器内执行。

## Decision (ADR-lite)

**Context**: 本任务需要产出可复用的 Dev Container 标准配置，而不是某个项目的单点配置。后续可能继续增加更多语言和工具链模板。

**Decision**: 采用分层模板库结构，首版围绕 base、Java 8 与 AI Agent 配置复用组织模板；Java 8 示例模板必须覆盖宿主 Maven、Claude Code 与 Codex 配置复用。宿主配置默认采用“配置只读 + 缓存读写”的挂载策略。

**Consequences**: 首版文档需要说明不同模板片段的组合方式；换来的是后续扩展其他语言或工具链时不需要重写 Java 8 示例。配置只读能降低容器误改宿主登录态和敏感配置的风险，但用户若要在容器内重新登录或修改 agent 配置，需要按文档临时改成读写挂载。
