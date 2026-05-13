"""Coding Plan window warmer 目标服务访问。"""

from __future__ import annotations

import json
import os
import subprocess
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from .models import PlanConfig, TargetConfig


def read_env_file(path: Path | None) -> dict[str, str]:
    """读取简单 KEY=value 环境变量文件。

    Args:
        path: env 文件路径；为空或不存在时返回空字典。

    Returns:
        环境变量映射。
    """
    values: dict[str, str] = {}
    if path is None or not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        values[key] = value
    return values


def read_api_key(config: TargetConfig) -> str | None:
    """读取目标服务 API key。

    Args:
        config: 目标服务连接配置。

    Returns:
        找到时返回 API key，否则返回 None。
    """
    if config.api_key_env is None:
        return None
    env_value = os.getenv(config.api_key_env)
    if env_value:
        return env_value
    return read_env_file(config.env_file).get(config.api_key_env)


def is_container_running(container_name: str) -> tuple[bool, str]:
    """检查 Docker 容器是否处于 running 状态。

    Args:
        container_name: Docker 容器名称。

    Returns:
        `(是否运行, 诊断信息)`。
    """
    command = ["docker", "inspect", "-f", "{{.State.Running}}", container_name]
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return False, "未找到 docker 命令"

    if result.returncode != 0:
        message = (result.stderr or result.stdout or "docker inspect failed").strip()
        return False, message
    return result.stdout.strip().lower() == "true", "container is running"


def is_target_api_ready(config: TargetConfig, api_key: str | None) -> tuple[bool, str]:
    """检查目标 API 是否可访问。

    Args:
        config: 目标服务连接配置。
        api_key: 可选 API key。

    Returns:
        `(是否可访问, 诊断信息)`。
    """
    if config.health_path is None:
        return True, "health check disabled"

    url = join_url(config.base_url, config.health_path)
    try:
        request_json("GET", url, api_key, None, config.request_timeout_seconds)
    except RuntimeError as exc:
        return False, str(exc)
    return True, "target api is ready"


def join_url(base_url: str, path: str) -> str:
    """拼接基础地址与 API 路径。

    Args:
        base_url: 基础地址。
        path: API 路径。

    Returns:
        完整 URL。
    """
    return f"{base_url.rstrip('/')}/{path.lstrip('/')}"


def request_json(
    method: str,
    url: str,
    api_key: str | None,
    payload: dict[str, Any] | None,
    timeout_seconds: int,
) -> Any:
    """发送 JSON HTTP 请求。

    Args:
        method: HTTP 方法。
        url: 请求 URL。
        api_key: 可选 API key。
        payload: JSON 请求体；GET 请求可为空。
        timeout_seconds: 请求超时时间。

    Returns:
        JSON 响应；响应为空或非 JSON 时返回 None。
    """
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        detail = safe_error_detail(exc)
        raise RuntimeError(f"HTTP {exc.code} {exc.reason}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"request failed: {exc.reason}") from exc
    except TimeoutError as exc:
        raise RuntimeError("request timed out") from exc

    if not response_body:
        return None
    try:
        return json.loads(response_body.decode("utf-8"))
    except json.JSONDecodeError:
        return None


def safe_error_detail(error: urllib.error.HTTPError) -> str:
    """读取不包含请求正文的 HTTP 错误摘要。

    Args:
        error: HTTPError 实例。

    Returns:
        截断后的错误响应摘要。
    """
    try:
        return error.read(240).decode("utf-8", errors="replace")
    except OSError:
        return ""


def send_warm_completion(config: TargetConfig, plan: PlanConfig, api_key: str | None) -> None:
    """通过 LiteLLM SDK 直连目标端点发送预热请求。

    Args:
        config: 目标服务连接配置。
        plan: plan 配置。
        api_key: 可选 API key。

    Returns:
        无返回值；请求失败时由 LiteLLM 抛出异常。
    """
    call_litellm_completion(
        model=plan.model,
        messages=[{"role": "user", "content": plan.prompt}],
        api_base=config.base_url,
        api_key=api_key,
        timeout=config.request_timeout_seconds,
        max_tokens=plan.max_tokens,
        temperature=plan.temperature,
    )


def call_litellm_completion(**kwargs: Any) -> None:
    """懒加载 LiteLLM SDK 并发送 completion 请求。

    Args:
        kwargs: 透传给 `litellm.completion` 的参数。

    Returns:
        无返回值；请求失败时由 LiteLLM 抛出异常。
    """
    from litellm import completion

    completion(**kwargs)


def ensure_target_ready(config: TargetConfig) -> tuple[bool, str, str | None]:
    """确认目标前置条件与 API 均可用。

    Args:
        config: 目标服务连接配置。

    Returns:
        `(是否可用, 诊断信息, API key)`。
    """
    if config.container_name is not None:
        container_running, container_message = is_container_running(config.container_name)
        if not container_running:
            return False, f"容器 {config.container_name} 未就绪: {container_message}", None

    api_key = read_api_key(config)
    if config.api_key_env is not None and api_key is None:
        return False, f"未找到 {config.api_key_env}", None

    api_ready, api_message = is_target_api_ready(config, api_key)
    if not api_ready:
        return False, f"{config.name} API 未就绪: {api_message}", api_key
    return True, f"{config.name} 已就绪", api_key
