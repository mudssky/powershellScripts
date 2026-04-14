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
