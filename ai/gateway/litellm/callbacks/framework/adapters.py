"""LiteLLM 网关 callback adapter 抽象。"""

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class AdapterResult:
    """描述 adapter 执行后的安全诊断结果。

    Args:
        adapter: 产出结果的 adapter 名称。
        stage: LiteLLM 生命周期阶段名称。
        changed: 当前 adapter 是否修改了请求、状态或响应。
        diagnostics: 不含 prompt、密钥、完整 headers 的结构化诊断字段。

    Returns:
        数据类实例，无额外返回。
    """

    adapter: str
    stage: str
    changed: bool = False
    diagnostics: dict[str, Any] | None = None


class GatewayCallbackAdapter:
    """LiteLLM callback adapter 的最小协议。

    Args:
        enabled: 是否启用当前 adapter。
        fail_open: adapter 抛错时是否允许主请求继续执行。

    Returns:
        抽象基类实例。
    """

    name = "gateway_callback_adapter"

    def __init__(self, enabled: bool = True, fail_open: bool = True) -> None:
        """初始化 adapter 通用开关。

        Args:
            enabled: 为 False 时 hub 会跳过该 adapter。
            fail_open: 为 True 时 adapter 抛错只记录日志，不中断请求。

        Returns:
            无返回值。
        """
        self.enabled = enabled
        self.fail_open = fail_open


class SanitizerAdapter(GatewayCallbackAdapter):
    """请求清洗类 adapter 抽象。"""


class CooldownAdapter(GatewayCallbackAdapter):
    """限流冷却类 adapter 抽象。"""
