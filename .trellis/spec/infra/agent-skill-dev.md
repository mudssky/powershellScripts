# Agent Skill Development Spec

> 本规范记录 `ai/skills/dev` 下本地 agent skill 的开发、脚本构建、分发产物和安装态运行契约。

---

## Scenario: TypeScript 脚本型 Skill

### 1. Scope / Trigger

- Trigger: 新增或修改 `ai/skills/dev/<skill-name>/` 下的本地 skill，且该 skill 包含可执行脚本。
- Scope: 本地开发中的 agent skill，包括 `SKILL.md`、`references/`、`examples/`、TypeScript 源码、测试和构建后的 JavaScript。
- Design intent: 开发态可以使用 TypeScript 与 Vitest 提升可维护性；安装态必须能直接通过 `node scripts/*.js` 运行，不要求用户安装依赖或构建源码。

### 2. Signatures

- 推荐目录结构：

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
```

- `SKILL.md` 中的脚本调用签名：

```bash
node <installed-skill>/scripts/<script>.js [args]
```

- `package.json` 最少脚本：

```json
{
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "test": "vitest run tests/**/*.test.ts",
    "lint": "biome check src tests package.json tsconfig.json",
    "format": "biome format --write src tests package.json tsconfig.json",
    "check": "pnpm build && pnpm lint && pnpm test"
  }
}
```

### 3. Contracts

- `SKILL.md` 是必需文件，frontmatter 的 `name` 必须与目录名一致。
- `scripts/*.js` 是分发入口，必须提交到仓库，且不得手工修改；它由 TypeScript 构建生成时，不要在同一文件上做手写修补。
- TypeScript 脚本型 skill 的构建产物优先打包为单文件 `scripts/<script>.js`。默认不压缩，保留可读性；仅面向现代 Node.js 执行环境，不需要为了旧浏览器或旧 Node 做额外兼容降级。
- TypeScript CLI 默认推荐使用 `cac` 处理选项、校验和内置 `--help` 输出；极简脚本可以直接使用 Node 内置 `node:util` 的 `parseArgs`，避免引入不必要依赖。
- `src/`、`tests/`、`package.json`、`tsconfig.json` 是开发态资产；安装后即使被复制，也不能成为运行前提。
- TypeScript 脚本测试复用根目录已有的 `vitest`、`typescript` 等依赖，不在每个 skill 内重复声明同一套 dev dependency。
- TypeScript 脚本 lint/format 复用 monorepo 根目录已有的 Biome 配置和依赖，不在每个 skill 内重复声明 formatter/linter 依赖。
- `SKILL.md` 的示例命令必须指向 `scripts/*.js`，不得要求先运行 `pnpm install`、`pnpm build` 或 `tsx src/*.ts`。
- 私有配置示例使用 `*.local.*` 命名时，必须确认仓库 `.gitignore` 或目录局部 `.gitignore` 已忽略对应真实私有文件。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| `scripts/*.js` 缺失 | skill 脚本不可交付，必须先构建并提交产物 |
| 构建后产生多个 `scripts/*.js` 运行依赖文件 | 不推荐，优先打包成单文件入口，降低安装态心智负担 |
| `SKILL.md` 指向 `src/*.ts` | 不合规，安装态不能假设存在 TS 运行器 |
| 测试从 `node:test` 导入 API | 不合规，根 Vitest 可能发现文件但不注册 suite |
| `package.json` 重复声明根目录已有测试依赖 | 不推荐，增加 dev skill 维护负担 |
| `package.json` 重复声明根目录已有 Biome 依赖 | 不推荐，lint/format 应复用根目录工具 |
| 私有 YAML 示例对应真实文件未忽略 | 不合规，存在密钥误提交风险 |

### 5. Good/Base/Bad Cases

- Good: `src/database-query.ts` 维护统一 CLI 入口，`tests/check-sql.test.ts` 覆盖行为，`scripts/database-query.js` 由 `pnpm build` 生成并提交，`SKILL.md` 调用 `node scripts/database-query.js check-sql`。
- Base: 纯文档 skill 只有 `SKILL.md`、`references/`、`examples/`，不包含 `package.json`、`src/`、`tests/`、`scripts/`。
- Bad: `SKILL.md` 让用户执行 `npx tsx src/check-sql.ts`，安装后依赖开发工具链。
- Bad: 手工编辑生成的 `scripts/*.js` 修复问题，却不更新 TypeScript 源码和测试。

### 6. Tests Required

- Type check / build: 在 skill 目录执行 `pnpm build` 或等价命令。
- Unit tests: 在 skill 目录执行 `pnpm test`，测试应覆盖脚本参数解析、核心业务规则和错误退出。
- Lint/format: 在 skill 目录执行 `pnpm lint`，需要自动格式化时执行 `pnpm format`；默认只检查源码、测试和配置，不格式化构建生成的 `scripts/*.js`。
- Syntax smoke: 对分发产物执行 `node scripts/<script>.js --help` 或一个最小成功命令。
- Project gate: 代码改动完成后执行根目录 `pnpm qa`。

### 7. Wrong vs Correct

#### Wrong

```markdown
运行 SQL 检查：

```bash
npx tsx src/check-sql.ts --dialect postgres --level readonly --file query.sql
```
```

问题：这把开发态运行器暴露给安装态用户，skill 被复制到 agent 目录后不一定有 `tsx` 或依赖环境。

#### Correct

```markdown
运行 SQL 检查：

```bash
node scripts/database-query.js check-sql --dialect postgres --level readonly --file query.sql
```
```

理由：`scripts/database-query.js` 是提交的分发产物，安装后可直接由 Node.js 执行。

---

## Scenario: Python 脚本型 Skill

### 1. Scope / Trigger

- Trigger: 新增或修改 `ai/skills/dev/<skill-name>/` 下的本地 skill，且该 skill 包含 Python 可执行脚本。
- Scope: 本地开发中的 agent skill，包括 `SKILL.md`、`scripts/` 轻量 Python 脚本、可选 uv 项目结构、测试和依赖锁定文件。
- Design intent: Python 脚本默认保持轻量、标准库优先；只有复杂需求确实需要第三方包时，才升级为独立 uv 项目。安装态不得依赖未声明依赖、全局 pip 包、开发者本机虚拟环境或隐式构建步骤。

### 2. Signatures

- 轻量标准库脚本推荐目录结构：

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  scripts/
    <script>.py
  references/
  examples/
```

- 依赖型或复杂 Python 脚本推荐目录结构：

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

- `SKILL.md` 中的轻量脚本调用签名：

```bash
python scripts/<script>.py [args]
```

- `SKILL.md` 中的依赖型脚本调用签名：

```bash
uv run python -m <package>.cli [args]
```

- Python 脚本命令默认以 skill 根目录为工作目录。agent 调用安装态 skill 时，应先解析 `<installed-skill>` 到实际目录并进入该目录，再执行 `SKILL.md` 中的相对命令。

### 3. Contracts

- `SKILL.md` 是必需文件，frontmatter 的 `name` 必须与目录名一致。
- 轻量 Python 脚本应优先使用标准库，适合参数解析、JSON 或简单文本处理、文件 IO、无状态检查和明确的进程退出。
- 轻量 Python 脚本不得为了便利随意引入第三方包；一旦需要第三方依赖，应升级为依赖型 uv 项目。
- 依赖型 Python 脚本必须提交 `pyproject.toml` 与 `uv.lock`，并通过 `uv run` 运行；不得依赖全局 pip 包、未提交虚拟环境或用户本机已安装的包。
- `SKILL.md` 的 Python 示例命令不得要求用户先手工 `pip install`、激活本机 venv 或运行未记录的环境准备步骤。
- Python 代码应使用类型标注；公共函数和 CLI 入口应通过 docstring 或相邻注释说明核心功能、入参、返回值和退出码语义。注释解释复杂业务逻辑与设计意图，避免复述基础语法。
- 如果脚本会写文件、调用外部命令、检查危险操作或处理复杂输入，核心逻辑必须拆成可测试函数，CLI 层只负责参数解析、IO 与退出码。
- Python lint/format 复用仓库根目录 `uvx ruff` 约定；不要在轻量脚本 skill 内重复声明 formatter/linter 依赖。
- 私有配置示例使用 `*.local.*` 命名时，必须确认仓库 `.gitignore` 或目录局部 `.gitignore` 已忽略对应真实私有文件。

### 3.1 Configuration Files

- 少量、一次性、非敏感配置优先使用 CLI 参数，通过 `argparse` 明确默认值、类型和帮助文本。
- 轻量标准库脚本需要配置文件时，优先使用 JSON，通过标准库 `json` 读取；JSON 适合 agent 修改、机器生成和简单结构配置。
- 复杂人工维护的嵌套配置可以使用 YAML，例如多实例、多 profile、带注释的连接清单；但 Python 脚本一旦需要直接读取 YAML，应视为依赖型 uv 项目，提交 `pyproject.toml` 与 `uv.lock` 并锁定 `PyYAML` 或同类依赖。
- TOML 不作为新 Python skill 配置的默认推荐格式；仅在复用既有工具生态、已有项目配置或 `pyproject.toml` 相关配置时使用。
- `.env` 只用于 secret、token、连接串或机器差异值，不承载复杂嵌套结构；结构化配置文件应通过 `passwordEnv`、`tokenEnv`、`connectionStringEnv` 等字段引用环境变量名。
- 配置加载优先级推荐为：CLI 参数 > 环境变量 > 私有本机配置 `*.local.*` > 可提交默认配置或示例配置。脚本必须避免把真实 secret 写回可提交文件。
- 配置读取函数应显式接收 `Path`，返回有类型的配置对象或字典，并在缺失、格式错误、必填字段缺失时给出清晰错误消息和非零退出码。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| 轻量脚本导入第三方包 | 不合规；应改为标准库实现或升级为 uv 项目 |
| 依赖型脚本缺少 `uv.lock` | 不合规；安装态依赖不可复现 |
| `SKILL.md` 要求 `pip install` 或激活本机 venv | 不合规；安装态不能依赖手工环境准备 |
| `SKILL.md` 使用 `uv run` 但未要求从 skill 根目录执行 | 不合规；`uv` 可能找不到对应 `pyproject.toml` |
| 轻量脚本直接读取 YAML | 不合规；YAML 读取需要依赖，应升级为 uv 项目或改用 JSON |
| `.env` 承载复杂嵌套配置 | 不推荐；`.env` 只放 secret 或机器差异值 |
| 脚本把 secret 写回可提交配置 | 不合规，存在密钥误提交风险 |
| 高风险脚本只有 smoke test | 不合规；核心业务规则、危险操作保护或复杂解析必须有单元测试 |
| 低风险轻量脚本没有任何 smoke 验证 | 不合规；至少要验证 `--help` 或最小成功命令 |

### 5. Good/Base/Bad Cases

- Good: `scripts/normalize-json.py` 只使用标准库，`SKILL.md` 调用 `python scripts/normalize-json.py --input data.json`，并提供 `--help` smoke 验证。
- Good: 轻量脚本通过 `--config options.json` 读取简单 JSON 配置，secret 字段只保存环境变量名。
- Good: 复杂多实例配置使用 YAML，Python 读取代码放在 uv 项目中，依赖由 `pyproject.toml` 与 `uv.lock` 锁定。
- Good: 复杂脚本需要 `pydantic` 或 `requests`，skill 提交 `pyproject.toml` 与 `uv.lock`，入口为 `uv run python -m my_skill.cli`，测试通过 `uv run pytest` 执行。
- Base: 纯文档 skill 只有 `SKILL.md`、`references/`、`examples/`，不包含 Python 脚本或依赖文件。
- Bad: 轻量脚本因为输出好看而导入 `rich`，但没有 `pyproject.toml` 和 `uv.lock`。
- Bad: 轻量脚本直接 `import yaml` 读取配置，却没有 uv 项目和锁定依赖。
- Bad: 用 `.env` 表达多实例嵌套配置，或把真实 token 写进可提交 JSON/YAML。
- Bad: `SKILL.md` 让用户先执行 `pip install -r requirements.txt` 或激活开发者本机 venv。
- Bad: 复杂校验逻辑全部写在 CLI `main()` 中，只用 `python scripts/check.py --help` 做验证。

### 6. Tests Required

- Lint/format: 在仓库根目录执行 `pnpm lint:python` 或 `pnpm format:python`，底层复用 `uvx ruff`。
- Low-risk smoke: 低风险轻量脚本至少执行 `python scripts/<script>.py --help` 或一个最小成功命令。
- Unit tests for risky scripts: 轻量脚本只要包含业务规则、校验逻辑、危险操作保护、复杂输入解析、文件修改或外部命令调用，就必须有单元测试；优先使用标准库 `unittest`，避免为了测试轻量脚本引入 pytest。
- uv project tests: 依赖型 uv 项目必须有测试，优先使用锁定在项目中的 pytest，并通过 `uv run pytest` 或等价命令运行。
- Project gate: 代码改动完成后执行根目录 `pnpm qa`；如果只修改文档说明，可按项目规则不执行 `qa`。

### 7. Wrong vs Correct

#### Wrong

```markdown
运行报告生成：

```bash
pip install rich pydantic
python scripts/render-report.py --input report.json
```
```

问题：这把依赖安装暴露为手工步骤，安装态无法保证版本、锁定和可复现性。

#### Correct

```markdown
运行报告生成：

```bash
uv run python -m report_skill.cli --input report.json
```
```

理由：复杂依赖由 `pyproject.toml` 与 `uv.lock` 声明和锁定，`uv run` 从 skill 根目录执行时可以复现运行环境。
