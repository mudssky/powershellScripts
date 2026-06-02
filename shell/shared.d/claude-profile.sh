# Claude Code profile switcher for Bash/Zsh.
# Profile files live in ~/.claude/profiles/<name>.json and must contain an env object.

# 输出 claude-profile 的帮助信息。
# 参数：无。
# 返回值：总是返回 0。
_claude_profile_help() {
    cat <<'EOF'
Usage:
  claude-profile <command> [args]

Commands:
  run <profile> [claude args...]   使用 profile 临时启动 claude，不写项目配置
  use <profile>                    把 profile 写入当前目录 .claude/settings.local.json
  current                          显示当前项目 .claude/settings.local.json 中的 profile 摘要
  list                             列出 ~/.claude/profiles 下的 profile
  add <profile>                    创建 profile 模板并用 VISUAL/EDITOR 打开
  help                             显示帮助

Profile format:
  {
    "env": {
      "ANTHROPIC_API_KEY": "",
      "ANTHROPIC_BASE_URL": "http://127.0.0.1:34000"
    }
  }

Environment:
  CLAUDE_PROFILE_DIR               覆盖 profile 目录，默认 ~/.claude/profiles
EOF
}

# 输出带工具名前缀的错误信息。
# 参数：$@ 为错误消息。
# 返回值：总是返回 0。
_claude_profile_error() {
    printf '[claude-profile] %s\n' "$*" >&2
}

# 返回 profile 目录路径。
# 参数：无。
# 返回值：成功输出 profile 目录路径。
_claude_profile_dir() {
    printf '%s\n' "${CLAUDE_PROFILE_DIR:-$HOME/.claude/profiles}"
}

# 校验 profile 名称，避免路径穿越或意外文件名。
# 参数：$1 为 profile 名称。
# 返回值：名称合法返回 0，否则返回 1。
_claude_profile_validate_name() {
    local profile_name="${1:-}"

    if [[ -z "$profile_name" ]]; then
        _claude_profile_error "profile 名称不能为空"
        return 1
    fi

    if [[ ! "$profile_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        _claude_profile_error "profile 名称只能包含字母、数字、点、下划线和短横线，且必须以字母或数字开头: $profile_name"
        return 1
    fi
}

# 根据 profile 名称输出对应 JSON 文件路径。
# 参数：$1 为 profile 名称。
# 返回值：名称合法时输出文件路径并返回 0，否则返回 1。
_claude_profile_path() {
    local profile_name="$1"
    local profiles_dir

    _claude_profile_validate_name "$profile_name" || return 1
    profiles_dir="$(_claude_profile_dir)"
    printf '%s/%s.json\n' "$profiles_dir" "$profile_name"
}

# 检查 jq 是否可用。
# 参数：无。
# 返回值：jq 存在返回 0，否则返回 1。
_claude_profile_require_jq() {
    if command -v jq >/dev/null 2>&1; then
        return 0
    fi

    _claude_profile_error "需要 jq 来安全读写 JSON。安装示例: sudo apt install jq / brew install jq / scoop install jq"
    return 1
}

# 校验 profile 文件结构，确保 env 是字符串键值对象。
# 参数：$1 为 profile 文件路径。
# 返回值：结构合法返回 0，否则返回 1。
_claude_profile_validate_file() {
    local profile_path="$1"

    _claude_profile_require_jq || return 1

    if [ ! -f "$profile_path" ]; then
        _claude_profile_error "profile 不存在: $profile_path"
        return 1
    fi

    if ! jq -e '
        type == "object"
        and (.env? | type == "object")
        and all(
            .env | to_entries[];
            (.key | test("^[A-Za-z_][A-Za-z0-9_]*$"))
            and (.value | type == "string")
            and ((.value | test("[\r\n]")) | not)
        )
    ' "$profile_path" >/dev/null 2>&1; then
        _claude_profile_error "profile JSON 非法，必须包含字符串 env 对象: $profile_path"
        return 1
    fi
}

# 根据 profile 文件生成只包含 env 的 Claude Code 会话 settings JSON。
# 参数：$1 为 profile 文件路径，$2 为 profile 名称。
# 返回值：成功输出压缩 JSON，失败返回 1。
_claude_profile_settings_json() {
    local profile_path="$1"
    local profile_name="$2"

    jq -c --arg profile_name "$profile_name" '
        { env: (.env + { CLAUDE_PROFILE_NAME: $profile_name }) }
    ' "$profile_path"
}

# 把 profile env 转成 env 命令可接受的 KEY=VALUE 列表。
# 参数：$1 为 profile 文件路径，$2 为 profile 名称。
# 返回值：成功逐行输出 KEY=VALUE，失败返回 1。
_claude_profile_env_lines() {
    local profile_path="$1"
    local profile_name="$2"

    jq -r --arg profile_name "$profile_name" '
        .env + { CLAUDE_PROFILE_NAME: $profile_name }
        | to_entries[]
        | "\(.key)=\(.value)"
    ' "$profile_path"
}

# 脱敏显示密钥，只保留头尾少量字符。
# 参数：$1 为原始密钥值。
# 返回值：成功输出脱敏后的文本。
_claude_profile_mask_secret() {
    local secret_value="${1:-}"
    local secret_length
    local prefix
    local suffix

    if [ -z "$secret_value" ]; then
        printf '<empty>\n'
        return 0
    fi

    secret_length=${#secret_value}
    if [ "$secret_length" -le 8 ]; then
        printf '***\n'
        return 0
    fi

    prefix="${secret_value:0:4}"
    suffix="${secret_value: -4}"
    printf '%s...%s\n' "$prefix" "$suffix"
}

# 临时使用指定 profile 启动 Claude Code。
# 参数：$1 为 profile 名称，后续参数原样传给 claude。
# 返回值：返回 claude 进程的退出码；参数或 profile 非法时返回 1。
_claude_profile_run() {
    local profile_name="${1:-}"
    local profile_path
    local settings_json
    local settings_file
    local env_line
    local env_args=()
    local claude_exit_code

    if [ "$#" -lt 1 ]; then
        _claude_profile_error "用法: claude-profile run <profile> [claude args...]"
        return 1
    fi
    shift

    profile_path="$(_claude_profile_path "$profile_name")" || return 1
    _claude_profile_validate_file "$profile_path" || return 1

    if ! command -v claude >/dev/null 2>&1; then
        _claude_profile_error "未找到 claude 命令，请先安装 Claude Code CLI"
        return 1
    fi

    settings_json="$(_claude_profile_settings_json "$profile_path" "$profile_name")" || return 1
    settings_file="$(mktemp "${TMPDIR:-/tmp}/claude-profile-settings.XXXXXX")" || {
        _claude_profile_error "无法创建临时 settings 文件"
        return 1
    }
    chmod 600 "$settings_file" 2>/dev/null || true
    printf '%s\n' "$settings_json" > "$settings_file" || {
        rm -f "$settings_file"
        _claude_profile_error "无法写入临时 settings 文件: $settings_file"
        return 1
    }

    while IFS= read -r env_line; do
        env_args+=("$env_line")
    done < <(_claude_profile_env_lines "$profile_path" "$profile_name")

    env "${env_args[@]}" claude --settings "$settings_file" "$@"
    claude_exit_code=$?
    rm -f "$settings_file"
    return "$claude_exit_code"
}

# 将指定 profile 合并到当前目录 .claude/settings.local.json。
# 参数：$1 为 profile 名称。
# 返回值：写入成功返回 0；参数、JSON 或文件写入失败返回 1。
_claude_profile_use() {
    local profile_name="${1:-}"
    local profile_path
    local claude_dir="$PWD/.claude"
    local settings_path="$claude_dir/settings.local.json"
    local source_path
    local tmp_file

    if [ "$#" -ne 1 ]; then
        _claude_profile_error "用法: claude-profile use <profile>"
        return 1
    fi

    profile_path="$(_claude_profile_path "$profile_name")" || return 1
    _claude_profile_validate_file "$profile_path" || return 1

    if ! mkdir -p "$claude_dir"; then
        _claude_profile_error "无法创建目录: $claude_dir"
        return 1
    fi

    if [ -f "$settings_path" ]; then
        source_path="$settings_path"
    else
        source_path=""
    fi

    tmp_file="$(mktemp "$settings_path.tmp.XXXXXX")" || {
        _claude_profile_error "无法创建临时文件: $settings_path.tmp.*"
        return 1
    }

    if [ -n "$source_path" ]; then
        if ! jq --arg profile_name "$profile_name" --slurpfile profile "$profile_path" '
            if type != "object" then
                error("settings.local.json 必须是 JSON object")
            elif (.env? != null and (.env | type) != "object") then
                error("settings.local.json 的 env 必须是 JSON object")
            else
                ($profile[0].env + { CLAUDE_PROFILE_NAME: $profile_name }) as $profile_env
                | . + { env: ((.env // {}) + $profile_env) }
            end
        ' "$source_path" > "$tmp_file"; then
            rm -f "$tmp_file"
            _claude_profile_error "合并失败，原 settings.local.json 未修改: $settings_path"
            return 1
        fi
    else
        if ! printf '{}\n' | jq --arg profile_name "$profile_name" --slurpfile profile "$profile_path" '
            ($profile[0].env + { CLAUDE_PROFILE_NAME: $profile_name }) as $profile_env
            | . + { env: $profile_env }
        ' > "$tmp_file"; then
            rm -f "$tmp_file"
            _claude_profile_error "生成 settings.local.json 失败: $settings_path"
            return 1
        fi
    fi

    if ! mv "$tmp_file" "$settings_path"; then
        rm -f "$tmp_file"
        _claude_profile_error "写入失败: $settings_path"
        return 1
    fi

    printf '[claude-profile] 已使用 profile "%s" 更新 %s\n' "$profile_name" "$settings_path"
}

# 显示当前项目 Claude local settings 中的 profile 与关键 env 摘要。
# 参数：无。
# 返回值：settings 存在且可解析时返回 0；JSON 非法返回 1。
_claude_profile_current() {
    local settings_path="$PWD/.claude/settings.local.json"
    local profile_name
    local api_key
    local api_key_masked

    _claude_profile_require_jq || return 1

    printf 'settings: %s\n' "$settings_path"
    if [ ! -f "$settings_path" ]; then
        printf 'profile: <none>\n'
        return 0
    fi

    if ! jq -e 'type == "object" and (.env? == null or (.env | type == "object"))' "$settings_path" >/dev/null 2>&1; then
        _claude_profile_error "settings.local.json 非法或 env 不是对象: $settings_path"
        return 1
    fi

    profile_name="$(jq -r '.env.CLAUDE_PROFILE_NAME // "<unknown>"' "$settings_path")"
    api_key="$(jq -r '.env.ANTHROPIC_API_KEY // ""' "$settings_path")"
    api_key_masked="$(_claude_profile_mask_secret "$api_key")"

    printf 'profile: %s\n' "$profile_name"
    jq -r '
        .env // {}
        | . as $env
        | [
            "ANTHROPIC_BASE_URL",
            "ANTHROPIC_MODEL",
            "ANTHROPIC_DEFAULT_OPUS_MODEL",
            "ANTHROPIC_DEFAULT_SONNET_MODEL",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL",
            "CLAUDE_CODE_SUBAGENT_MODEL",
            "CLAUDE_CODE_EFFORT_LEVEL"
          ] as $keys
        | $keys[] as $key
        | select($env | has($key))
        | $key
    ' "$settings_path" | while IFS= read -r key_name; do
        printf '%s: %s\n' "$key_name" "$(jq -r --arg key "$key_name" '.env[$key]' "$settings_path")"
    done
    printf 'ANTHROPIC_API_KEY: %s\n' "$api_key_masked"
}

# 列出 profile 目录中的可用 profile，并显示关键摘要。
# 参数：无。
# 返回值：成功返回 0；jq 缺失返回 1。
_claude_profile_list() {
    local profiles_dir
    local profile_path
    local profile_name
    local base_url
    local model_name
    local api_key
    local api_key_masked
    local found=0

    _claude_profile_require_jq || return 1
    profiles_dir="$(_claude_profile_dir)"

    if [ ! -d "$profiles_dir" ]; then
        printf 'profile 目录不存在: %s\n' "$profiles_dir"
        return 0
    fi

    for profile_path in "$profiles_dir"/*.json; do
        [ -e "$profile_path" ] || continue
        found=1
        profile_name="$(basename "$profile_path" .json)"

        if ! _claude_profile_validate_file "$profile_path" >/dev/null 2>&1; then
            printf '%-24s invalid profile\n' "$profile_name"
            continue
        fi

        base_url="$(jq -r '.env.ANTHROPIC_BASE_URL // "<unset>"' "$profile_path")"
        model_name="$(jq -r '.env.ANTHROPIC_MODEL // .env.ANTHROPIC_DEFAULT_SONNET_MODEL // .env.ANTHROPIC_DEFAULT_OPUS_MODEL // "<unset>"' "$profile_path")"
        api_key="$(jq -r '.env.ANTHROPIC_API_KEY // ""' "$profile_path")"
        api_key_masked="$(_claude_profile_mask_secret "$api_key")"
        printf '%-24s base=%s model=%s key=%s\n' "$profile_name" "$base_url" "$model_name" "$api_key_masked"
    done

    if [ "$found" -eq 0 ]; then
        printf '未找到 profile: %s/*.json\n' "$profiles_dir"
    fi
}

# 通过 VISUAL、EDITOR 或常见编辑器打开文件。
# 参数：$1 为要打开的文件路径。
# 返回值：编辑器成功启动返回其退出码；找不到编辑器返回 1。
_claude_profile_open_editor() {
    local target_path="$1"
    local editor_command="${VISUAL:-${EDITOR:-}}"
    local candidate

    if [ -n "$editor_command" ]; then
        CLAUDE_PROFILE_EDITOR="$editor_command" sh -c 'exec $CLAUDE_PROFILE_EDITOR "$1"' sh "$target_path"
        return $?
    fi

    for candidate in vi nano code; do
        if command -v "$candidate" >/dev/null 2>&1; then
            "$candidate" "$target_path"
            return $?
        fi
    done

    _claude_profile_error "未找到编辑器，请设置 VISUAL 或 EDITOR 后重试: $target_path"
    return 1
}

# 创建 profile 模板，并立即打开编辑器。
# 参数：$1 为 profile 名称。
# 返回值：模板存在或创建成功且编辑器退出成功返回 0；失败返回 1。
_claude_profile_add() {
    local profile_name="${1:-}"
    local profile_path
    local profiles_dir

    if [ "$#" -ne 1 ]; then
        _claude_profile_error "用法: claude-profile add <profile>"
        return 1
    fi

    profile_path="$(_claude_profile_path "$profile_name")" || return 1
    profiles_dir="$(dirname "$profile_path")"

    if ! mkdir -p "$profiles_dir"; then
        _claude_profile_error "无法创建 profile 目录: $profiles_dir"
        return 1
    fi

    if [ ! -f "$profile_path" ]; then
        cat > "$profile_path" <<'EOF'
{
  "env": {
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_BASE_URL": "",
    "ANTHROPIC_MODEL": "",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "",
    "CLAUDE_CODE_SUBAGENT_MODEL": "",
    "CLAUDE_CODE_EFFORT_LEVEL": "max"
  }
}
EOF
        chmod 600 "$profile_path" 2>/dev/null || true
        printf '[claude-profile] 已创建 profile 模板: %s\n' "$profile_path"
    else
        printf '[claude-profile] profile 已存在，直接打开: %s\n' "$profile_path"
    fi

    _claude_profile_open_editor "$profile_path"
}

# claude-profile 主入口，分发子命令。
# 参数：$1 为子命令，后续参数传给子命令。
# 返回值：返回对应子命令退出码；未知子命令返回 1。
claude-profile() {
    local command_name="${1:-help}"

    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$command_name" in
        run)
            _claude_profile_run "$@"
            ;;
        use)
            _claude_profile_use "$@"
            ;;
        current)
            _claude_profile_current "$@"
            ;;
        list)
            _claude_profile_list "$@"
            ;;
        add)
            _claude_profile_add "$@"
            ;;
        help|--help|-h)
            _claude_profile_help
            ;;
        *)
            _claude_profile_error "未知命令: $command_name"
            _claude_profile_help >&2
            return 1
            ;;
    esac
}
