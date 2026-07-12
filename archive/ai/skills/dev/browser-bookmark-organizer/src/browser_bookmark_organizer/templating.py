"""包内 HTML 模板渲染工具。"""

from __future__ import annotations

from importlib.resources import files
from pathlib import Path
from typing import Any

from jinja2 import Environment, PackageLoader, select_autoescape

PACKAGE_NAME = "browser_bookmark_organizer"


def build_template_environment() -> Environment:
    """创建 Jinja 模板环境。

    Args:
        None.

    Returns:
        Environment: 已启用 HTML 自动转义的 Jinja 环境。
    """

    return Environment(
        loader=PackageLoader(PACKAGE_NAME, "templates"),
        autoescape=select_autoescape(("html", "xml", "j2")),
    )


TEMPLATE_ENV = build_template_environment()


def render_template(template_name: str, **context: Any) -> str:
    """渲染包内模板。

    Args:
        template_name: `templates/` 下的模板文件名。
        **context: 模板上下文。

    Returns:
        str: 渲染后的文本。
    """

    return TEMPLATE_ENV.get_template(template_name).render(**context)


def package_static_dir() -> Path:
    """返回包内静态资源目录。

    Args:
        None.

    Returns:
        Path: 可交给 FastAPI StaticFiles 使用的目录路径。
    """

    return Path(str(files(PACKAGE_NAME).joinpath("static")))


def read_static_text(relative_path: str) -> str:
    """读取包内静态文本资源。

    Args:
        relative_path: `static/` 下的相对路径。

    Returns:
        str: UTF-8 文本内容。
    """

    return files(PACKAGE_NAME).joinpath("static", relative_path).read_text(encoding="utf-8")
