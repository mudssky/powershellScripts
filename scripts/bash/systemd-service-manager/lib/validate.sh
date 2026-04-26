# shellcheck shell=bash

if [[ -n "${SSM_VALIDATE_LOADED:-}" ]]; then
  return 0
fi
SSM_VALIDATE_LOADED=1

# 限制 unit 前缀和逻辑名称字符集，避免后续生成非法 unit 名。
ssm_require_safe_name() {
  local field_name="$1"
  local value="$2"

  if [[ ! "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    ssm_die "Invalid ${field_name}: ${value}"
  fi
}

# 要求字段是大于等于最小值的十进制整数，用于 retry 等数值配置。
# 参数：$1 为字段名，$2 为字段值，$3 为允许的最小值。
# 返回值：校验通过返回 0；校验失败时退出 1。
ssm_require_integer_at_least() {
  local field_name="$1"
  local value="$2"
  local minimum="$3"

  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    ssm_die "Invalid ${field_name}: ${value}"
  fi

  if [[ "${value}" -lt "${minimum}" ]]; then
    ssm_die "Invalid ${field_name}: ${value}, must be >= ${minimum}"
  fi
}
