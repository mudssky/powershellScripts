# 通用 Skill 开发规范

本目录用于维护可跨多个 agent 复用的个人 skill。稳定后可以通过 `Install-Skills.ps1`
安装到 Claude、Codex 等 agent；仍在实验中的内容先放在 `dev/` 下。

## 目录结构

推荐每个纯文档型 skill 使用独立目录：

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  references/
  examples/
```

`SKILL.md` 是唯一必需文件。`references/` 放长文档或外部资料摘要，`examples/`
放可复制的使用示例。

带 TypeScript 脚本的 skill 使用源码与分发产物分层结构：

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  package.json
  tsconfig.json
  src/
    <script>.ts
  tests/
    <script>.test.ts
  scripts/
    <script>.js
  references/
  examples/
```

`src/`、`tests/`、`package.json`、`tsconfig.json` 是开发态资产；`scripts/*.js`
是安装后的运行入口，必须提交到仓库，且不要手工修改。`SKILL.md` 中的命令必须
指向 `scripts/*.js`，不能要求用户先安装依赖、构建源码或运行 `tsx src/*.ts`。
构建后的脚本优先保持单文件、未压缩和现代 Node.js 可读输出，避免安装后还要理解
多个运行时依赖文件。TypeScript CLI 默认推荐使用 `cac` 处理选项、校验和内置
`--help` 输出；极简脚本可以直接使用 Node 内置 `node:util` 的 `parseArgs`，避免引入
不必要依赖。
TypeScript 脚本测试复用根目录已有的 `vitest`、`typescript` 等依赖，不在每个
skill 内重复声明同一套 dev dependency。lint 和 format 复用 monorepo 根目录的
Biome 配置与依赖，不在每个 skill 内重复声明 formatter/linter 依赖。

带 Python 脚本的 skill 默认使用轻量标准库脚本：

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  scripts/
    <script>.py
  references/
  examples/
```

`SKILL.md` 中的命令默认从 skill 根目录执行：

```bash
python scripts/<script>.py [args]
```

轻量 Python 脚本不得依赖全局 pip 包、开发者本机虚拟环境或未声明的第三方库。
只有复杂需求确实需要第三方依赖时，才升级为独立 uv 项目：

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  pyproject.toml
  uv.lock
  src/
    <package>/
      __init__.py
      cli.py
  tests/
    test_cli.py
  references/
  examples/
```

依赖型 Python 脚本的 `SKILL.md` 命令使用 `uv run`，并同样要求从 skill 根目录执行：

```bash
uv run python -m <package>.cli [args]
```

Python 代码应使用类型标注；公共函数和 CLI 入口用 docstring 或相邻注释说明核心
功能、入参、返回值和退出码语义。低风险轻量脚本至少提供 `--help` 或最小成功命令
smoke 验证；包含业务规则、校验逻辑、危险操作保护、复杂输入解析、文件修改或外部
命令调用时必须补充单元测试。轻量脚本优先用标准库 `unittest`，依赖型 uv 项目优先
通过 `uv run pytest` 运行测试。Python lint 和 format 复用根目录 `uvx ruff`
约定，不在轻量脚本 skill 内重复声明 formatter/linter 依赖。

Python 脚本读取配置时，少量一次性配置优先用 CLI 参数；轻量标准库脚本需要配置文件时
优先用 JSON，并通过标准库 `json` 读取。复杂人工维护的嵌套配置可以使用 YAML，
例如多实例、多 profile、带注释的连接清单；但 Python 脚本一旦直接读取 YAML，就应
升级为依赖型 uv 项目，并在 `pyproject.toml` 与 `uv.lock` 中锁定 `PyYAML` 或同类
依赖。TOML 不作为新 Python skill 配置的默认推荐格式，只在复用既有工具生态或已有
项目配置时使用。`.env` 只放 secret、token、连接串或机器差异值，不承载复杂结构；
结构化配置通过 `passwordEnv`、`tokenEnv`、`connectionStringEnv` 等字段引用环境变量。
配置优先级推荐为 CLI 参数 > 环境变量 > `*.local.*` 私有本机配置 > 可提交默认配置或
示例配置，脚本不得把真实 secret 写回可提交文件。

更多可执行约定见 `.trellis/spec/infra/agent-skill-dev.md`。

## SKILL.md Frontmatter

每个 `SKILL.md` 必须包含 frontmatter：

```markdown
---
name: my-skill
description: 一句话说明触发场景和能力边界。
---
```

要求：

- `name` 使用小写短横线命名，并与目录名保持一致。
- `description` 用中文描述“什么时候使用”，避免只写功能名。
- 不写入单一 agent 私有字段；需要 agent 差异时放在正文的兼容性说明中。

## 内容组织

正文建议按这个顺序：

1. 使用时机：明确哪些请求会触发该 skill。
2. 工作流程：列出 agent 执行任务时应遵循的步骤。
3. 约束边界：说明不要做什么、何时应改用其他工具。
4. 资源引用：只链接必要的 `references/`、`examples/` 或 `scripts/` 文件。

## 脚本与依赖

如果 skill 依赖额外 CLI 或运行环境，不要把安装副作用写进 `SKILL.md`。
应在 `skills.config.json` 中为该 skill 配置 `commands`，例如：

```json
{
  "my-playwright-skill": {
    "description": "使用 Playwright 做浏览器自动化。",
    "source": "./dev/my-playwright-skill",
    "sourceType": "local",
    "commands": [
      {
        "name": "install-playwright-browsers",
        "phase": "postInstall",
        "command": "npx",
        "args": ["playwright", "install", "--with-deps"]
      }
    ]
  }
}
```

安装脚本会把这些命令纳入 dry-run、确认、日志和 `ShouldProcess` 链路。

## 本地开发到安装

默认只安装 `skills.config.json` 显式列出的本地 skill。需要临时同步全部本地开发
skill 时，可执行：

```powershell
pwsh -NoProfile -File ./ai/skills/Install-Skills.ps1 -IncludeDevAll -DryRun
```

确认计划正确后移除 `-DryRun`。远程和本地 skill 都通过 `npx skills add` 安装，
安装状态与 lock 文件由 `skills` CLI 维护。

当前默认只通过安装器同步 Claude Code 目标，不再把 `codex` 写入
`skills.config.json` 的默认 agents。Codex 会加载通用个人 skill 目录
`~/.agents/skills`；如果再通过安装器向 `~/.codex/skills` 安装同名 skill，
会在 Codex 中出现重复条目。只有明确需要 Codex 专用副本时，才临时使用
`-Agent codex` 或在单个 skill 配置中显式声明 `agents`。
