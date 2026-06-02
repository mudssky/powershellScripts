"""LiteLLM 网关统一 callback 入口。"""

from callbacks.framework.hub import GatewayCallbackHub

proxy_handler_instance = GatewayCallbackHub()
