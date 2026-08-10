#!/usr/bin/env bash
set -Eeuo pipefail

# Validates browserctl arguments and calls only installed browser-host.
# Parameters: documented action, target, and recovery confirmation.
# Returns: browser-host stdout, stderr, and exit code unchanged.
browserctl_error() { local message=${1//\\/\\\\}; message=${message//\"/\\\"}; local command=${action:-unknown}; command=${command//\\/\\\\}; command=${command//\"/\\\"}; printf '{"schemaVersion":1,"error":"%s","action":"%s"}\n' "$message" "$command" >&2; exit 2; }
browserctl_host_path() {
  if [[ -n "${BROWSER_HOST_CONTROL_PATH:-}" ]]; then printf '%s\n' "$BROWSER_HOST_CONTROL_PATH"; return; fi
  powershell.exe -NoLogo -NoProfile -NonInteractive -Command '[Console]::Out.Write((Join-Path $HOME ".local\share\selfhosted-compose\browser-runtime\browser-host.ps1"))'
}

action=${1:-status}
shift || true
host_path=$(browserctl_host_path) || browserctl_error 'unable to resolve installed browser-host control'
[[ -n "$host_path" ]] || browserctl_error 'installed browser-host control path is empty'
case "$action" in
  status|stop|detach|diagnose)
    [[ $# -eq 0 ]] || browserctl_error "$action does not accept positional arguments"
    args=("$action") ;;
  start)
    [[ $# -eq 1 && ( "$1" == windows || "$1" == wsl ) ]] || browserctl_error 'start target must be windows or wsl'
    args=(start -Runtime "$1") ;;
  attach)
    [[ $# -eq 1 && ( "$1" == agent-browser || "$1" == playwright ) ]] || browserctl_error 'attach target must be agent-browser or playwright'
    args=(attach -Client "$1") ;;
  recover-owner)
    [[ $# -eq 2 && "$1" == --confirm-service-name && "$2" == browser-runtime ]] || browserctl_error 'recover-owner requires --confirm-service-name browser-runtime'
    args=(recover-owner -ConfirmServiceName browser-runtime) ;;
  *) browserctl_error "unsupported browserctl action: $action" ;;
esac
exec powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$host_path" "${args[@]}"
