# Python 项目目录结构

## 先识别

- 是否有 `pyproject.toml`、`setup.cfg`、`setup.py`、`requirements*.txt`、`uv.lock`、`poetry.lock`。
- 是库、应用、CLI、脚本集合、数据项目，还是框架项目。
- 是否使用 Django、FastAPI、Flask、Airflow、Jupyter 等框架或平台。框架项目先查框架官方文档。

## 常见结构

库或应用推荐优先考虑 `src` layout：

```text
project/
  pyproject.toml
  src/
    package_name/
      __init__.py
      module.py
  tests/
    test_module.py
```

简单脚本或内部工具可以保持轻量：

```text
project/
  scripts/
    task.py
  tests/
    test_task.py
  pyproject.toml
```

数据项目常见分层：

```text
project/
  data/
    raw/
    processed/
  notebooks/
  src/
    package_name/
  tests/
```

`data/raw` 通常只读；大数据和私有数据不应默认提交。

## 放置建议

- 可导入包放 `src/<package_name>/` 或项目既有包目录。
- CLI 入口优先通过 `pyproject.toml` 的 scripts 声明，入口函数保持薄。
- 测试放 `tests/` 或与模块邻近；团队已有约定优先。
- 配置示例可提交，真实本机配置用 `.env.local`、`*.local.*` 或环境变量。
- 生成文件、缓存、虚拟环境、coverage 和 notebook checkpoint 不进源码目录。

## 避免

- 把复杂业务堆在单个脚本入口。
- 同时维护 `src` layout 和 flat layout 的两套导入心智。
- 把 notebooks 当作唯一源码真相。
- 把真实凭据写进示例配置。
