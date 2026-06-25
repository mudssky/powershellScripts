# Python Skill 开发

## 选择模型

优先从轻量标准库脚本开始：

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  scripts/
    <script>.py
  references/
  examples/
```

当出现第三方依赖、复杂 HTML/WebUI、包内模板、复杂配置解析或需要锁定运行环境时，升级为 uv 项目：

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

## 运行入口

轻量脚本从 skill 根目录运行：

```bash
python scripts/<script>.py [args]
```

依赖型 uv 项目从 skill 根目录运行：

```bash
uv run python -m <package>.cli [args]
```

`SKILL.md` 不得要求用户先 `pip install`、激活本机 venv，或依赖开发者机器上已存在的全局包。

## 依赖规则

- 轻量脚本只用标准库，适合参数解析、JSON、文本处理、文件 IO、无状态检查和明确退出。
- 轻量脚本一旦需要 `requests`、`pydantic`、`PyYAML`、`rich`、`fastapi` 等第三方包，就升级为 uv 项目。
- uv 项目必须提交 `pyproject.toml` 和 `uv.lock`，并通过 `uv run` 运行测试和 CLI。
- Python lint/format 复用根目录 `uvx ruff` 约定，不在轻量脚本 skill 内重复声明 formatter/linter 依赖。

## 配置文件

- 少量一次性配置优先用 CLI 参数，并通过 `argparse` 声明默认值、类型和帮助文本。
- 轻量脚本需要配置文件时，优先使用 JSON，并用标准库 `json` 读取。
- 复杂人工维护的嵌套配置可以用 YAML；Python 代码直接读取 YAML 时必须是 uv 项目，并锁定 `PyYAML` 或同类依赖。
- TOML 不作为新 Python skill 配置默认选择，只在复用已有生态或 `pyproject.toml` 相关配置时使用。
- `.env` 只放 secret 或机器差异值，不承载复杂结构。
- 配置优先级推荐为 CLI 参数 > 环境变量 > `*.local.*` 私有本机配置 > 可提交默认配置或示例配置。
- 配置读取函数显式接收 `Path`，返回有类型对象或字典；缺失、格式错误、必填字段缺失时给出清晰错误和非零退出码。

## 代码组织

- Python 代码使用类型标注。
- 公共函数和 CLI 入口用 docstring 或相邻注释说明核心功能、入参、返回值和退出码语义。
- 会写文件、调用外部命令、检查危险操作或处理复杂输入时，把核心逻辑拆成可测试函数；CLI 层只做参数解析、IO 和退出码。
- 输出或服务端渲染复杂 HTML 时，把模板和静态资源放在包内 `templates/`、`static/`，不要把大段 HTML/CSS/JS 写成 Python 字符串。

## 本地 WebUI

带 review server、dashboard 或 preview server 时遵守：

- 默认绑定 `127.0.0.1`，不要默认绑定 `0.0.0.0`。
- `--port 0` 表示自动选择空闲端口。
- 启动成功后 stdout 打印 URL、PID、日志路径和自动关闭时间。
- 默认有自动关停时间，推荐 `--shutdown-after 3600`。
- 面向 agent 的默认流程应后台启动并立即返回；调试时提供 `--foreground`。
- 原始用户数据、选择记录、操作日志和导出文件写入用户指定 workspace，不写入 skill 安装目录。
- 服务内部日志使用标准 `logging`，Python 模块内使用 `logger = logging.getLogger(__name__)`。

## 测试和验证

- 低风险轻量脚本至少执行 `python scripts/<script>.py --help` 或一个最小成功命令。
- 含业务规则、校验逻辑、危险操作保护、复杂输入解析、文件修改或外部命令调用时必须有单元测试；轻量脚本优先用标准库 `unittest`。
- uv 项目优先用锁定在项目中的 pytest，通过 `uv run pytest` 或等价命令运行。
- 代码改动完成后按项目规则执行根目录 `pnpm qa`；只改文档说明可说明原因后跳过。
