#!/usr/bin/env bash
set -Eeuo pipefail
browserctl_invoked=$0


# Validates browserctl arguments. Setup delegates to the PowerShell browserctl source;
# all daily actions call only the installed browser-host control.
browserctl_error() { local message=${1//\\/\\\\}; message=${message//\"/\\\"}; local command=${action:-unknown}; command=${command//\\/\\\\}; command=${command//\"/\\\"}; printf '{"schemaVersion":1,"error":"%s","action":"%s"}\n' "$message" "$command" >&2; exit 2; }
browserctl_not_initialized() { local message='browser runtime is not initialized; run browserctl setup windows from the self-hosted-compose checkout or pass --source-root'; printf '{"schemaVersion":1,"error":"%s","action":"%s"}\n' "$message" "${action:-unknown}" >&2; exit 127; }
browserctl_host_path() {
  if [[ -n "${BROWSER_HOST_CONTROL_PATH:-}" ]]; then printf '%s\n' "$BROWSER_HOST_CONTROL_PATH"; return; fi
  powershell.exe -NoLogo -NoProfile -NonInteractive -Command '[Console]::Out.Write((Join-Path $HOME ".local\share\selfhosted-compose\browser-runtime\browser-host.ps1"))'
}
browserctl_powershell_entry() {
  if [[ -n "${BROWSERCTL_POWERSHELL_ENTRY_PATH:-}" ]]; then printf '%s\n' "$BROWSERCTL_POWERSHELL_ENTRY_PATH"; return; fi
  local invoked=${browserctl_invoked%/*}; [[ "$invoked" != "$browserctl_invoked" ]] || invoked=.
  local script_dir; script_dir=$(cd -P "$invoked" && pwd)
  local candidate
  for candidate in \
    "$script_dir/../pwsh/devops/browser-control/main.ps1" \
    "$script_dir/../scripts/pwsh/devops/browser-control/main.ps1"; do
    if [[ -f "$candidate" ]]; then printf '%s\n' "$candidate"; return; fi
  done
  return 1
}

action=${1:-status}
shift || true
case "$action" in
  setup)
    [[ $# -ge 1 && "$1" == windows ]] || browserctl_error 'setup target must be windows'
    shift
    setup_args=(setup windows)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --source-root|--profile-root|--runtime-root)
          [[ $# -ge 2 && -n "$2" ]] || browserctl_error "$1 requires a path"
          case "$1" in
            --source-root) setup_args+=(-SourceRoot "$2") ;;
            --profile-root) setup_args+=(-ProfileRoot "$2") ;;
            --runtime-root) setup_args+=(-RuntimeRoot "$2") ;;
          esac
          shift 2 ;;
        *) browserctl_error "unsupported setup argument: $1" ;;
      esac
    done
    powershell_entry=$(browserctl_powershell_entry) || browserctl_error 'PowerShell browserctl source is missing; reinstall powershellScripts or set BROWSERCTL_POWERSHELL_ENTRY_PATH'
    exec powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$powershell_entry" "${setup_args[@]}" ;;
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
host_path=$(browserctl_host_path) || browserctl_error 'unable to resolve installed browser-host control'
[[ -n "$host_path" ]] || browserctl_error 'installed browser-host control path is empty'
if [[ ! -f "$host_path" ]]; then browserctl_not_initialized; fi
exec powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$host_path" "${args[@]}"
