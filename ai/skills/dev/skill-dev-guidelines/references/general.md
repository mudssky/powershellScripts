# 通用 Skill 结构

## 规范源

开始开发或维护本仓库 skill 前，先读取：

- `ai/skills/SKILL_SPEC.md`
- `.trellis/spec/infra/agent-skill-dev.md`

本文件只做执行摘要。发现冲突时，以规范源为准。

## 命名和 frontmatter

- 目录名使用小写短横线，路径为 `ai/skills/dev/<skill-name>/`。
- `SKILL.md` frontmatter 只写 `name` 和 `description`。
- `name` 必须与目录名一致。
- `description` 是触发依据，要写清能力和使用场景，不只写功能名。

示例：

```markdown
---
name: my-skill
description: 管理某类本地开发任务。Use when 用户要求创建、检查或维护该类任务的配置、脚本和验证流程。
---
```

## 目录结构

纯文档型 skill：

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  references/
  examples/
```

`SKILL.md` 是唯一必需文件。`references/` 放长规范、工作流、领域知识和少用分支；`examples/` 放可复制示例。没有实际需要时不要创建空目录。

脚本型 skill 再按语言加入 `scripts/`、`src/`、`tests/`、`package.json`、`pyproject.toml` 等文件。语言细节见 `python.md` 和 `typescript.md`。

## 内容组织

`SKILL.md` 推荐顺序：

1. 使用时机。
2. 工作流程。
3. 约束边界。
4. 资源引用。

保持 `SKILL.md` 精简。一个 skill 支持多语言、多数据库、多平台等分支时，把分支细节拆进一层 `references/`，并在主文件说明何时读取。

不要创建额外 `README.md`、`INSTALLATION_GUIDE.md`、`QUICK_REFERENCE.md`、`CHANGELOG.md` 等辅助文档；这些会增加维护入口。

## 代码和注释

- 公共函数、CLI 入口、对外配置读取函数要说明核心功能、入参、返回值或退出码语义。
- 中文注释只解释复杂业务逻辑、风险边界和设计意图，不复述基础语法。
- 复杂逻辑应拆成可测试函数，CLI 层只负责参数解析、IO 和退出码。

## 安装态边界

- `SKILL.md` 中的命令必须能在安装后的 skill 目录运行。
- 不要求安装态用户先构建源码、安装开发依赖、激活本机 venv 或运行未记录准备步骤。
- 需要额外 CLI、浏览器或工具安装副作用时，不要塞进 `SKILL.md`；应通过 `ai/skills/skills.config.json` 的 `commands` 接入安装器。
- `agents/openai.yaml` 是 UI 元数据，不是主要执行说明。只有需要 UI 展示语同步时才创建或更新，并保持与 `SKILL.md` 一致。

## 本地配置和 secret

- 私有配置用 `*.local.*`、`.env.local` 等命名，并确认被 `.gitignore` 或目录局部忽略。
- `.env` 只放 secret、token、连接串或机器差异值，不表达复杂嵌套结构。
- 结构化配置通过 `passwordEnv`、`tokenEnv`、`connectionStringEnv` 等字段引用环境变量名。
- 跨 agent、跨项目复用的用户级配置使用 `$XDG_CONFIG_HOME/<skill-name>/`，未设置时回退 `~/.config/<skill-name>/`；不要写到 Codex/Claude 专属目录，也不要写入 skill 安装目录。

## 验证清单

- frontmatter 合法，`name` 与目录一致。
- `SKILL.md` description 有明确触发条件。
- reference 只一层深，并且主文件说明何时读取。
- 安装态命令不依赖开发态源码或隐式环境。
- 没有真实 secret、本机私有凭据或用户数据。
- 文档改动可只跑 skill 校验；代码改动按语言运行对应测试并执行根目录 `pnpm qa`。
