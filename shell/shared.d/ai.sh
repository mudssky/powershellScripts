# ======================================================================
# 文件：ai.sh
# 作用：提供 Windows Terminal 通知与 Zellij bell 辅助函数。
# 兼容性：Bash / Zsh。
# ======================================================================

# ----------------------------------------------------------------------
# win_notify — 发送 Windows Terminal 桌面通知。
#
# 参数：$1 — 通知标题；$2 — 通知内容。
# 副作用：向终端写入 OSC 9 通知序列。
# 返回码：printf 的退出码。
# ----------------------------------------------------------------------
function win_notify() {
    # OSC 9 序列由 Windows Terminal 捕获并转换为系统通知。
    printf "\e]9;%s;%s\e\\" "$1" "$2"
}

# ----------------------------------------------------------------------
# invoke_bell — 在 Zellij 中发出终端 bell。
#
# 参数：无。
# 副作用：向终端写入 bell 字符。
# 返回码：echo 的退出码。
# ----------------------------------------------------------------------
function invoke_bell(){
     echo -e "\a"
}

# ----------------------------------------------------------------------
# agent-task — 以进程级配置启动支持的 AI 宿主。
#
# 参数：$1 — 宿主（omp、codex 或 pi）；$2 — profile（fast、slow 或 max）；
#       后续可选 --show-command、--dry-run、--，其余参数完整转发给宿主。
# 副作用：向 stderr 输出不含用户参数内容的路由摘要；除 --dry-run 外启动宿主进程。
# 返回码：帮助与 dry-run 返回 0；参数错误返回 64；否则原样返回宿主退出码。
# ----------------------------------------------------------------------
function agent-task() {
    if [ "${1-}" = "--help" ] || [ "${1-}" = "-h" ]; then
        printf '%s\n' \
            '用法：agent-task <host> <profile> [--show-command|--dry-run] [--] [args...]' \
            '' \
            '支持矩阵：' \
            '  omp   fast|slow|max  使用 $HOME/.omp/overlays/task-<profile>.yml' \
            '  codex fast|slow|max  仅覆盖当前进程的默认 subagent 模型与推理强度' \
            '  pi    fast|slow|max  设置当前进程的 PI_PROFILED_TASK_PROFILE' \
            '  claude              仅支持持久化 worker-fast' \
            '' \
            '快捷命令：' \
            '  omp-taskfast / omp-taskslow / omp-taskmax' \
            '  codex-taskfast / codex-taskslow / codex-taskmax' \
            '  pi-taskfast / pi-taskslow / pi-taskmax' \
            '' \
            '参数转发：' \
            '  dispatcher 选项应放在 host/profile 后、首个宿主参数前。' \
            '  使用 -- 结束 dispatcher 选项解析；其后参数会逐项原样转发。' \
            '  日志只显示用户参数数量，不会回显参数内容。' \
            '' \
            '命令显示：' \
            '  --show-command  打印安全的固定命令前缀，然后正常启动宿主。' \
            '  --dry-run       打印相同信息并返回 0，不启动宿主；与前者并用时优先。' \
            '' \
            '排错示例：' \
            '  agent-task omp fast --dry-run' \
            '  agent-task codex max --show-command -- --help' \
            '  agent-task pi fast -- --foo "two words"'
        return 0
    fi

    if [ "$#" -lt 2 ]; then
        printf '%s\n' 'agent-task: 需要 host 和 profile；请运行 agent-task --help。' >&2
        return 64
    fi

    local host="$1"
    local profile="$2"
    local show_command=0
    local dry_run=0
    local overlay=''
    local model=''
    local effort=''
    local argument_count
    local -a user_args
    shift 2

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --show-command)
                show_command=1
                shift
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done
    user_args=("$@")
    argument_count="${#user_args[@]}"

    case "$profile" in
        fast|slow|max) ;;
        *)
            printf 'agent-task: 未知 profile：%s（支持 fast、slow、max）；请运行 agent-task --help。\n' "$profile" >&2
            return 64
            ;;
    esac

    case "$host" in
        omp)
            overlay="$HOME/.omp/overlays/task-$profile.yml"
            printf 'agent-task: host=%s profile=%s overlay=%s (+%s user args)\n' \
                "$host" "$profile" "$overlay" "$argument_count" >&2
            if [ "$show_command" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
                printf 'agent-task command: omp --config "$HOME/.omp/overlays/task-%s.yml" (+%s user args)\n' \
                    "$profile" "$argument_count" >&2
            fi
            if [ "$dry_run" -eq 1 ]; then
                return 0
            fi
            command omp --config "$overlay" "${user_args[@]}"
            return $?
            ;;
        codex)
            case "$profile" in
                fast)
                    model='gpt-5.6-luna'
                    effort='xhigh'
                    ;;
                slow)
                    model='gpt-5.6-luna'
                    effort='max'
                    ;;
                max)
                    model='gpt-5.6-sol'
                    effort='medium'
                    ;;
            esac
            printf 'agent-task: host=%s profile=%s model=%s:%s (+%s user args)\n' \
                "$host" "$profile" "$model" "$effort" "$argument_count" >&2
            if [ "$show_command" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
                printf 'agent-task command: codex -c agents.default_subagent_model="%s" -c agents.default_subagent_reasoning_effort="%s" (+%s user args)\n' \
                    "$model" "$effort" "$argument_count" >&2
            fi
            if [ "$dry_run" -eq 1 ]; then
                return 0
            fi
            command codex \
                -c "agents.default_subagent_model=\"$model\"" \
                -c "agents.default_subagent_reasoning_effort=\"$effort\"" \
                "${user_args[@]}"
            return $?
            ;;
        pi)
            printf 'agent-task: host=%s profile=%s source-agent=worker_%s (+%s user args)\n' \
                "$host" "$profile" "$profile" "$argument_count" >&2
            if [ "$show_command" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
                printf 'agent-task command: PI_PROFILED_TASK_PROFILE=%s pi (+%s user args)\n' \
                    "$profile" "$argument_count" >&2
            fi
            if [ "$dry_run" -eq 1 ]; then
                return 0
            fi
            PI_PROFILED_TASK_PROFILE="$profile" command pi "${user_args[@]}"
            return $?
            ;;
        claude)
            printf '%s\n' 'agent-task: claude 仅支持持久化 Agent；请显式派发 worker-fast。' >&2
            return 64
            ;;
        *)
            printf 'agent-task: 未知 host：%s（支持 omp、codex、pi）；请运行 agent-task --help。\n' "$host" >&2
            return 64
            ;;
    esac
}

# ----------------------------------------------------------------------
# omp-taskfast — 使用 OMP fast task overlay 启动当前进程。
# 参数：全部参数原样转发给 agent-task；返回码：agent-task 的返回码。
# 副作用：输出安全路由摘要，并在非 dry-run 时启动 OMP。
# ----------------------------------------------------------------------
function omp-taskfast() {
    agent-task omp fast "$@"
}

# ----------------------------------------------------------------------
# omp-taskslow — 使用 OMP slow task overlay 启动当前进程。
# 参数：全部参数原样转发给 agent-task；返回码：agent-task 的返回码。
# 副作用：输出安全路由摘要，并在非 dry-run 时启动 OMP。
# ----------------------------------------------------------------------
function omp-taskslow() {
    agent-task omp slow "$@"
}

# ----------------------------------------------------------------------
# omp-taskmax — 使用 OMP max task overlay 启动当前进程。
# 参数：全部参数原样转发给 agent-task；返回码：agent-task 的返回码。
# 副作用：输出安全路由摘要，并在非 dry-run 时启动 OMP。
# ----------------------------------------------------------------------
function omp-taskmax() {
    agent-task omp max "$@"
}

# ----------------------------------------------------------------------
# codex-taskfast — 使用 Codex fast subagent 覆盖启动当前进程。
# 参数：全部参数原样转发给 agent-task；返回码：agent-task 的返回码。
# 副作用：输出安全路由摘要，并在非 dry-run 时启动 Codex。
# ----------------------------------------------------------------------
function codex-taskfast() {
    agent-task codex fast "$@"
}

# ----------------------------------------------------------------------
# codex-taskslow — 使用 Codex slow subagent 覆盖启动当前进程。
# 参数：全部参数原样转发给 agent-task；返回码：agent-task 的返回码。
# 副作用：输出安全路由摘要，并在非 dry-run 时启动 Codex。
# ----------------------------------------------------------------------
function codex-taskslow() {
    agent-task codex slow "$@"
}

# ----------------------------------------------------------------------
# codex-taskmax — 使用 Codex max subagent 覆盖启动当前进程。
# 参数：全部参数原样转发给 agent-task；返回码：agent-task 的返回码。
# 副作用：输出安全路由摘要，并在非 dry-run 时启动 Codex。
# ----------------------------------------------------------------------
function codex-taskmax() {
    agent-task codex max "$@"
}

# ----------------------------------------------------------------------
# pi-taskfast — 使用 Pi fast process profile 启动当前进程。
# 参数：全部参数原样转发给 agent-task；返回码：agent-task 的返回码。
# 副作用：输出安全路由摘要，并在非 dry-run 时启动 Pi。
# ----------------------------------------------------------------------
function pi-taskfast() {
    agent-task pi fast "$@"
}

# ----------------------------------------------------------------------
# pi-taskslow — 使用 Pi slow process profile 启动当前进程。
# 参数：全部参数原样转发给 agent-task；返回码：agent-task 的返回码。
# 副作用：输出安全路由摘要，并在非 dry-run 时启动 Pi。
# ----------------------------------------------------------------------
function pi-taskslow() {
    agent-task pi slow "$@"
}

# ----------------------------------------------------------------------
# pi-taskmax — 使用 Pi max process profile 启动当前进程。
# 参数：全部参数原样转发给 agent-task；返回码：agent-task 的返回码。
# 副作用：输出安全路由摘要，并在非 dry-run 时启动 Pi。
# ----------------------------------------------------------------------
function pi-taskmax() {
    agent-task pi max "$@"
}
