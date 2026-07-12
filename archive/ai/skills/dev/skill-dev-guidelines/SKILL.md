---
name: skill-dev-guidelines
description: 指导创建、维护和检查可全局安装的 agent skill，覆盖自包含 SKILL.md、frontmatter、目录结构、Python/TypeScript 脚本、本地 WebUI、配置、secret 和验证边界。Use when 用户要求新增、更新、审查或规范化全局 skill，或需要把项目内经验沉淀为不依赖当前仓库的 skill。
---

# 全局 Skill 开发规范

## 使用时机

用于创建、维护、迁移或审查可在多个 agent / 多个项目中复用的全局 skill。使用后应把目标 skill 做成自包含能力包，而不是把当前工作仓库的规范、路径或任务系统复制成运行前提。

关键原则：

- `SKILL.md` 是必需入口，主体说明应足够独立，安装后不依赖原开发仓库。
- 不默认读取或引用当前项目的 `AGENTS.md`、`.trellis/`、`docs/`、`README.md`、本机绝对路径或私有配置。
- 只有当外部资源随 skill 一起打包在同一目录内，且 `SKILL.md` 明确何时读取时，才可以引用这些资源。
- 文档内容优先中文；英文仅用于固定字段、命令、API 名称或兼容 agent 触发语。

## 工作流程

1. 明确目标 skill 的使用者、触发场景、输入、输出、可选工具和不可做事项。
2. 判断类型：纯文档、轻量 Python 脚本、依赖型 Python 项目、TypeScript CLI、本地 WebUI 或混合型。
   - Python skill：继续读取 `references/python.md`。
   - TypeScript skill：继续读取 `references/typescript.md`。
3. 选择最小目录结构，只创建完成任务必需的文件。
4. 编写或更新 `SKILL.md`，把核心流程、约束、验证命令和失败处理写在 skill 自身。
5. 如需脚本，先实现可测试核心逻辑，再提供安装态可直接运行的入口。
6. 完成后做结构校验、命令 smoke test，并按风险运行单元测试或集成验证。

## 基础结构

最小结构：

```text
<skill-name>/
  SKILL.md
```

可选结构：

```text
<skill-name>/
  SKILL.md
  agents/
    openai.yaml
  references/
  examples/
  scripts/
  src/
  tests/
  assets/
```

规则：

- 目录名使用小写字母、数字和短横线，建议短而清晰。
- `SKILL.md` frontmatter 只要求 `name` 和 `description`；`name` 必须与目录名一致。
- `description` 是触发依据，要写清“能力 + 使用场景”，不要只写功能名。
- 不创建 `README.md`、`INSTALLATION_GUIDE.md`、`QUICK_REFERENCE.md`、`CHANGELOG.md` 等额外说明入口，除非用户明确要求。
- `agents/openai.yaml` 只作为 UI 元数据，内容必须与 `SKILL.md` 一致，不能放主要执行说明。

frontmatter 示例：

```markdown
---
name: my-skill
description: 管理某类可复用开发任务。Use when 用户要求创建、检查、修复或执行该类任务的配置、脚本和验证流程。
---
```

## 自包含边界

- `SKILL.md` 应包含完成任务所需的核心步骤、判断规则、边界和验证方式。
- `references/` 只放随 skill 一起分发的长规范、领域知识或低频分支；主文件必须说明何时读取。
- reference 文件保持一层深，避免 `references/a.md` 再要求读取 `references/nested/b.md`。
- 不把“开发该 skill 时所在项目”的规范当作安装后运行依据。
- 不写入真实 secret、token、Cookie、连接串、内网地址或只能在开发者机器成立的绝对路径。
- 用户数据、运行状态、缓存和导出文件写入用户指定 workspace 或 XDG 用户配置目录，不写入 skill 安装目录。

## 内容质量

- 默认假设 agent 已具备通用编程能力，skill 只写领域知识、流程、风险边界和容易遗忘的约束。
- 用清晰步骤替代长篇解释；复杂分支用表格或短清单。
- 公共接口、CLI 入口、配置读取函数和复杂逻辑必须说明核心功能、入参、返回值或退出码语义。
- 中文注释用于解释复杂业务逻辑、风险边界和设计意图，不重复基础语法。
- 需要稳定复用的脚本优先放入 `scripts/` 或语言项目中，不让 agent 每次重写脆弱代码。

## 路线选择

### 纯文档 Skill

适合只有流程、检查清单、提示约束或领域知识的 skill。

推荐：

```text
<skill-name>/
  SKILL.md
  references/
  examples/
```

`references/` 和 `examples/` 没有实际需要时不要创建空目录。

### 轻量 Python 脚本

适合参数解析、JSON、文本处理、文件 IO、无状态检查和明确退出码。创建或维护 Python skill 时读取 `references/python.md`。

推荐：

```text
<skill-name>/
  SKILL.md
  scripts/
    <script>.py
  tests/
    test_<script>.py
```

核心要求：只用标准库，入口为 `python scripts/<script>.py [args]`，有风险逻辑时拆出可测试函数。

### 依赖型 Python 项目

当需要 `requests`、`pydantic`、`PyYAML`、`rich`、`fastapi`、模板渲染或复杂依赖时，升级为 uv 项目。创建或维护依赖型 Python skill 时读取 `references/python.md`。

推荐：

```text
<skill-name>/
  SKILL.md
  pyproject.toml
  uv.lock
  src/
    <package>/
      __init__.py
      cli.py
  tests/
    test_cli.py
```

核心要求：提交 `pyproject.toml` 和 `uv.lock`，入口为 `uv run python -m <package>.cli [args]`，不依赖全局 Python 包或手工 venv。

### TypeScript CLI

适合可维护 CLI、业务规则测试、Node 生态依赖或需要构建产物的 skill。创建或维护 TypeScript skill 时读取 `references/typescript.md`。

推荐：

```text
<skill-name>/
  SKILL.md
  package.json
  tsconfig.json
  src/
    <script>.ts
  tests/
    <script>.test.ts
  scripts/
    <script>.js
```

核心要求：`scripts/*.js` 是安装态入口并必须提交，`SKILL.md` 命令指向 `node scripts/<script>.js [args]`，不要求安装态用户构建源码。

### 本地 WebUI

适合 review server、dashboard、preview server 或需要持续交互的 skill。

要求：

- 默认绑定 `127.0.0.1`，不要默认绑定 `0.0.0.0`。
- `--port 0` 表示自动选择空闲端口。
- 默认设置自动关停时间，推荐 `--shutdown-after 3600`；`0` 可表示不自动关闭，但不能作为默认。
- 面向 agent 的默认流程应后台启动并立即返回；调试时提供 `--foreground`。
- 启动成功后 stdout 打印 URL、PID、日志路径、workspace 和自动关闭时间。
- 详细日志进入日志文件；Python 使用 `logging.getLogger(__name__)`。
- 原始用户数据、选择记录、操作日志和导出文件写入用户指定 workspace，不写入 skill 安装目录。

## 配置和 Secret

- 少量非敏感配置优先用 CLI 参数。
- 轻量 Python 配置优先 JSON；直接读取 YAML 代表需要第三方依赖，应升级为 uv 项目。
- `.env` 只放 secret、token、连接串或机器差异值，不承载复杂嵌套结构。
- 结构化配置通过 `passwordEnv`、`tokenEnv`、`connectionStringEnv` 等字段引用环境变量名。
- 用户级配置使用 `$XDG_CONFIG_HOME/<skill-name>/`，未设置时回退 `~/.config/<skill-name>/`。
- 配置优先级推荐：显式 `--config` > 当前项目配置 > XDG 用户配置 > 可提交默认值。
- 不把全局私有配置放进 Codex、Claude 等某个 agent 专属目录，除非该 skill 本身只服务该 agent。

## 验证

基础校验：

```bash
python /path/to/skill-creator/scripts/quick_validate.py <skill-dir>
```

纯文档 skill：

- 检查 frontmatter、触发描述、自包含边界和无隐式外部引用。
- 如只改文档，可不跑项目级测试，但最终说明跳过原因。

轻量 Python：

```bash
python scripts/<script>.py --help
python -m unittest discover -s tests
```

依赖型 Python：

```bash
uv run python -m <package>.cli --help
uv run pytest
```

更多 Python 验证边界见 `references/python.md`。

TypeScript：

```bash
pnpm build
pnpm test
pnpm lint
node scripts/<script>.js --help
```

更多 TypeScript 验证边界见 `references/typescript.md`。

本地 WebUI：

- 用极短 TTL 验证会打印 URL 并自动退出。
- 测试 `--no-review` / `--no-server` 不启动服务。
- 测试 `--foreground` 走前台服务入口。

## 交付检查清单

- `name` 与目录名一致。
- `description` 清楚说明触发场景。
- `SKILL.md` 不依赖当前项目路径或外部规范源。
- 只创建必要文件，无空目录和多余说明入口。
- 脚本入口在安装态可直接运行。
- 依赖被声明和锁定，不依赖开发者本机环境。
- secret、私有路径和用户数据不会进入可提交文件。
- 代码公共接口有核心功能、入参、返回值或退出码说明。
- 已运行与改动风险匹配的校验命令。

## 常见错误

- 把当前仓库的 `AGENTS.md`、Trellis 规范或内部路径写成 skill 的运行前提。
- `SKILL.md` 只说“按项目规范执行”，但没有把真正需要的规则写进 skill。
- Python 轻量脚本偷偷导入第三方包。
- TypeScript skill 让用户运行源码而不是提交后的 `scripts/*.js`。
- WebUI 默认阻塞进程、默认开放到局域网，或启动后不打印 URL。
- 把真实本机配置、token、连接串或用户数据写入 skill 目录。
