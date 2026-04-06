#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! command -v codex >/dev/null 2>&1; then
  echo "codex command not found" >&2
  exit 1
fi

mkdir -p "$TMP_DIR/.codex/rules"
cp "$ROOT_DIR/config.toml" "$TMP_DIR/.codex/config.toml"
cp -R "$ROOT_DIR/rules/." "$TMP_DIR/.codex/rules/"

if [ -f "$ROOT_DIR/auth.json" ]; then
  cp "$ROOT_DIR/auth.json" "$TMP_DIR/.codex/auth.json"
fi

cat > "$TMP_DIR/.codex/rules/comment-smoke.rules" <<'EOF'
# smoke file to validate comment parsing
prefix_rule(pattern=["pwd"], decision="allow")
EOF

run_codex_smoke() {
  local logfile="$1"

  set +e
  timeout 20s env HOME="$TMP_DIR" codex --ask-for-approval never exec --skip-git-repo-check --sandbox read-only --color never "Reply with OK and do not use any tools." >"$logfile" 2>&1
  local status=$?
  set -e

  echo "$status"
}

success_log="$TMP_DIR/success.log"
success_status="$(run_codex_smoke "$success_log")"

if grep -q "Error loading rules:" "$success_log"; then
  echo "rules parse failed with current ruleset" >&2
  cat "$success_log" >&2
  exit 1
fi

if [ "$success_status" -ne 0 ] && [ "$success_status" -ne 124 ]; then
  echo "warning: Codex did not complete normally, but no rule parse error was detected." >&2
  cat "$success_log" >&2
fi

cat > "$TMP_DIR/.codex/rules/invalid-smoke.rules" <<'EOF'
this is invalid
EOF

invalid_log="$TMP_DIR/invalid.log"
run_codex_smoke "$invalid_log" >/dev/null

if ! grep -q "Error loading rules:" "$invalid_log"; then
  echo "expected invalid smoke rule to fail parsing, but it did not" >&2
  cat "$invalid_log" >&2
  exit 1
fi

if ! grep -q "invalid-smoke.rules" "$invalid_log"; then
  echo "invalid smoke failure did not point at invalid-smoke.rules" >&2
  cat "$invalid_log" >&2
  exit 1
fi

echo "Codex rules smoke validation passed."
