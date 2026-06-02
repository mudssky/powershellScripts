# Python Skill 脚本规范

## Goal

扩展 `.trellis/spec/infra/agent-skill-dev.md`，在既有 TypeScript 脚本型 skill 规范旁补充 Python 脚本型 skill 的开发、测试、依赖与安装态运行契约。

该规范的用户价值是：后续在 `ai/skills/dev/<skill-name>/` 中新增 Python 脚本时，agent 能清楚判断什么时候使用纯标准库脚本、什么时候允许独立 Python 项目，以及 `SKILL.md` 应该暴露什么命令，避免把本地开发环境、未锁定依赖或隐式构建步骤带到安装态。

## Confirmed Facts

- 当前 `.trellis/spec/infra/agent-skill-dev.md` 已记录 TypeScript 脚本型 skill 的结构、`dist/*.js` 分发产物、Vitest 测试与安装态边界。
- 本次讨论目标文件是 `.trellis/spec/infra/agent-skill-dev.md`，主题是 Python 作为 skill 常用脚本语言时的规范。
- `ai/skills/dev` 现有 skill 示例主要是文档型 skill 和 JavaScript 辅助脚本，尚未出现 Python 脚本型 skill 的稳定模板。
- 仓库根目录 `package.json` 已有 `uvx ruff format .` 与 `uvx ruff check --fix .`，说明 Python 代码格式化和 lint 倾向复用 Ruff。
- 仓库已有独立 Python/uv 项目示例 `ai/coding/window-warmer/`，包含 `pyproject.toml`、`uv.lock`、包目录和 pytest 测试。
- 仓库也有零散 Python 脚本与 Trellis Python 脚本，这些脚本通常通过 `python <script>.py` 直接运行。
- 当前 TypeScript skill 规范强调安装态脚本入口应直接可运行，不能要求用户先安装依赖或构建源码。
- Python skill 的核心未决点是：安装态是否允许 `uv run` 同步依赖，还是优先要求 `python scripts/*.py` 直接运行且依赖标准库。
- 已确定 Python skill 的默认规范为轻量标准库脚本；只有复杂需求、确实需要第三方依赖时，才使用 `uv run` 与独立依赖声明。
- 已确定目录分层策略：轻量 Python 脚本放在 `scripts/*.py`；依赖型或复杂脚本采用独立 uv 项目结构，包含 `pyproject.toml`、`uv.lock`、`src/<package>/` 与 `tests/`。
- 已确定 `SKILL.md` 中 Python 脚本命令默认以 skill 根目录为工作目录，使用相对路径或模块名运行。
- 已确定轻量 Python 脚本不因“轻量”自动豁免测试；按风险分级决定验证强度。
- 已确定最终落地时同步更新 `.trellis/spec/infra/agent-skill-dev.md` 与 `ai/skills/SKILL_SPEC.md`；前者记录完整契约，后者记录面向 skill 作者的精简版。
- 仓库现有配置格式中，JSON、YAML、TOML 都有实际使用；Python 代码里常见 JSON 读取，独立 uv 项目 `ai/coding/window-warmer` 使用 `tomllib` 读取 TOML 配置。
- Python 标准库直接支持 JSON；Python 3.11+ 通过 `tomllib` 支持读取 TOML；YAML 读取通常需要第三方依赖，除非只实现非常受限的简单解析。
- `database-query` skill 当前使用 YAML 作为多实例数据库连接清单示例，适合人工编辑和表达嵌套结构。
- 私有配置已有 `*.local.*` 约定，真实本机配置需要被 `.gitignore` 或局部 `.gitignore` 忽略。
- 已确定 TOML 不作为 Python skill 配置的默认推荐格式；它可用于复用既有工具生态或项目已有 TOML 配置，但轻量脚本默认不为了配置语义额外引入 TOML 约定。
- 已确定 Python skill 配置推荐顺序：少量配置用 CLI 参数；轻量标准库脚本用 JSON；复杂人工维护嵌套配置用 YAML，但读取 YAML 时应升级为依赖型 uv 项目；`.env` 只用于 secret 或环境差异值。

## Requirements

- 在 `.trellis/spec/infra/agent-skill-dev.md` 补充 Python 脚本型 skill 的 Scenario。
- 明确 Python 脚本型 skill 的适用范围、目录结构、运行签名、依赖策略、测试策略和安装态边界。
- 规范应覆盖至少两类 Python 脚本：
  - 轻量脚本：仅依赖 Python 标准库，安装态直接通过 `python scripts/<script>.py` 或等价命令运行。
  - 依赖型脚本：只有复杂需求才使用，必须有明确依赖声明、锁定与 `uv run` 运行方式。
- 轻量 Python 脚本推荐目录为 `scripts/<script>.py`，避免为简单任务创建包结构。
- 依赖型 Python 脚本推荐目录为 `pyproject.toml`、`uv.lock`、`src/<package>/`、`tests/`，避免把复杂业务堆在单文件脚本中。
- `SKILL.md` 的 Python 示例命令应假设当前目录是 skill 根目录，例如 `python scripts/<script>.py [args]` 或 `uv run python -m <package>.cli [args]`。
- agent 调用安装态 skill 时，应先解析 `<installed-skill>` 到实际目录并进入该目录，再执行 `SKILL.md` 中的相对命令。
- 规范应说明 `SKILL.md` 示例命令不得依赖未声明依赖、全局 pip 包或开发者本机虚拟环境。
- 规范应说明轻量脚本不得为了便利随意引入第三方包；优先用标准库完成参数解析、JSON/YAML 以外的简单文本处理、文件 IO 与进程退出。
- Python 代码应使用类型标注、清晰函数文档字符串或注释，公共入口说明参数、返回值与退出码语义。
- 轻量 Python 脚本若只做低风险文件转换、参数拼接、格式整理或无状态检查，至少需要 `--help` 或最小成功命令 smoke test。
- 轻量 Python 脚本只要包含业务规则、校验逻辑、危险操作保护、复杂输入解析、文件修改或外部命令调用，就必须有单元测试；优先使用标准库 `unittest`，避免为轻量脚本引入 pytest。
- 依赖型 uv 项目必须有测试，优先使用锁定在项目中的 pytest，并通过 `uv run pytest` 或等价命令运行。
- 测试要求应覆盖参数解析、核心业务规则、错误退出和最小命令 smoke test。
- 规范应与现有 `uvx ruff` / Ruff 格式化约定兼容。
- `ai/skills/SKILL_SPEC.md` 应同步补充 Python 脚本型 skill 的精简规范，避免 skill 作者只看总规范时遗漏 Python 约定。
- 规范应补充 Python 脚本读取配置文件时的格式推荐、依赖边界、私有配置命名和 CLI/env/config 的优先级。
- Python skill 配置格式推荐应偏向：少量配置用 CLI 参数；轻量标准库脚本用 JSON；复杂人工维护的嵌套配置用 YAML，并把读取 YAML 视为依赖型 uv 项目场景；TOML 仅作为复用既有项目配置时的可选项。

## Acceptance Criteria

- [x] PRD 收敛 Python skill 脚本的运行时依赖策略。
- [x] 明确轻量 Python 脚本和依赖型 Python 脚本的推荐目录结构。
- [x] 明确 `SKILL.md` 中 Python 脚本调用签名。
- [x] 明确 Python 脚本测试、lint、format 与 smoke 验证命令。
- [x] 明确安装态不能依赖未提交、未锁定或本机私有虚拟环境。
- [x] 明确与 TypeScript 脚本型 skill 的边界：何时选 TS，何时选 Python。
- [x] 最终更新 `.trellis/spec/infra/agent-skill-dev.md`，并同步 `ai/skills/SKILL_SPEC.md`。
- [x] 明确 Python skill 脚本读取配置文件时推荐使用的格式和选择条件。
- [x] 明确轻量脚本读取配置时不应为了 YAML 引入隐式第三方依赖。

## Out of Scope

- 不在本次实现具体 Python skill。
- 不重构已有 `ai/coding/window-warmer` 或 Trellis Python 脚本。
- 不新增全仓库 Python 包管理体系，除非讨论结论认为 skill 规范必须依赖它。
- 不修改 skill 安装器的复制、裁剪或构建流程，除非后续明确纳入范围。

## Open Questions

- 无。
