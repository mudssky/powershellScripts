#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
printf 'WARNING: linux/03deployShellConfig.sh 已弃用，请改用 04deployShellConfig.sh\n' >&2
exec bash "$SCRIPT_DIR/04deployShellConfig.sh" "$@"
