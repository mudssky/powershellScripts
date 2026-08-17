# ======================================================================
# 文件：ai.sh
# 作用：提供终端通知、Zellij bell 与 AI 宿主进程级启动函数。
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

# -- Pi capability mode 上下文参考 ------------------------------------
#
# 测量口径（2026-08-17）：Pi 0.84.2，thinking=off，在本仓根目录以固定首轮
# 消息测量；模型为 `local/deepseek-v4-flash` 与 `local/gpt-5.6-luna`。
# Luna 走 Codex 订阅链路，其 provider usage 可能包含订阅侧注入的额外上下文。
# 探针本身不额外注册工具，也不覆盖 mode 组装后的 system prompt；`full` 是当前 43 Skills、19 tools 的安装快照。
# 旧行为测量已按新矩阵迁移：core→core-search、read→read-search、chat→chat-search、offline→chat。
# 新增本地 `core` 与 `read` 同样使用真实 provider usage 与探针字符统计；
# 不使用字符长度估算 token，也不编造占位数值。
#
# 表一：实际 provider input tokens。
#   - DeepSeek/Luna 两列均为模型返回的 `input + cacheRead + cacheWrite`。
#   - 这是完整首轮输入 token，包含可见 prompt、tool definitions 与 provider 开销。
#
# 模式              DeepSeek Flash     Luna（Codex 订阅）
#   full               24,612 tokens       26,325 tokens
#   project            20,675 tokens       22,039 tokens
#   no-skill           18,836 tokens       20,311 tokens
#   core                2,291 tokens        6,525 tokens
#   core-search         5,053 tokens        8,813 tokens
#   read                2,171 tokens        6,398 tokens
#   read-search         4,933 tokens        8,686 tokens
#   chat                131 tokens          4,821 tokens
#   chat-search         3,005 tokens        7,017 tokens
#
# 表二：可见请求结构的 JavaScript 字符长度，不是 token。
#   - DS prompt chars / Luna prompt chars：各模型最终 `systemPrompt.length`。
#   - tool schema chars：provider 请求中 `JSON.stringify(payload.tools).length`。
#   - 三个 chars 列不能与表一 token 相加；仅用于定位 prompt/schema 的体积来源。
#
# 模式              DS prompt chars   Luna prompt chars   tool schema chars
#   full                   39,507              39,507              39,503；43 Skills；19 tools；完整插件组。
#   project                28,016              27,590              39,503；15 project Skills；完整插件组。
#   no-skill               20,880              20,454              39,503；无 Skills；完整插件组。
#   core                    4,730               4,730               2,788；无 Skills、无 extensions；4 个内置编码工具。
#   core-search            5,374               5,374              12,276；无 Skills；仅 pi-web-access。
#   read                    3,995               3,995               2,764；无 Skills、无 extensions；read/grep/find/ls。
#   read-search            4,639               4,639              12,252；无 Skills；仅 pi-web-access。
#   chat                     195                 195                   2；无 Skills、插件、工具与项目 context。
#   chat-search              299                 299               9,489；无 Skills；仅 pi-web-access。
# 相比对应 *-search 模式，本地模式的首轮 input 减少：
#   core/read：DeepSeek Flash 2,762 tokens；Luna（Codex 订阅）2,288 tokens。
#   chat：DeepSeek Flash 2,874 tokens；Luna（Codex 订阅）2,196 tokens。
#
# `/supi-context` 的组成明细读取 JavaScript `text.length`，再以
# `Math.ceil(chars / 4)` 标为估算 tokens；这不是模型 tokenizer 的精确结果。
# `/4` 更接近英文文本，中文常见约 1–2 个汉字/token，中文较多时会明显低估。
#
# 当前完整插件组：
#   package — pi-web-access、pi-statusline、rpiv-todo、pi-subagents、
#             supi-context、rpiv-ask-user-question、pi-permission-system。
#   local   — output-style、orca-agent-status、orca-prefill、
#             orca-titlebar-spinner、profiled-task-dispatcher、model-fallback、
#             native-model-search、openviking。
#   pi-mcp-adapter 当前在 settings 中过滤了 extensions/skills，不计入插件组。

# -- OMP capability mode 上下文参考 -----------------------------------
#
# 测量口径（2026-08-17）：OMP 17.3.0，thinking=off，与 Pi 使用相同 cwd、
# 固定首轮消息和模型。`full` 是当前 49 个可见 Skills 的安装快照；
# `no-skill` 使用现有 `omp-mode no-skill`（即 `omp --no-skills`）。
# OMP 当前没有原生或包装层 `project` 模式，因此不构造不可复现的数据。
#
# 实际 provider input tokens：
# 模式        DeepSeek Flash     Luna（Codex 订阅）
#   full         31,340 tokens       31,467 tokens
#   no-skill     26,637 tokens       26,678 tokens
#
# 可见请求结构的 JavaScript 字符长度：OMP system prompt 是有序 `string[]`，
# prompt chars 按 `blocks.join("\n").length` 统计；tool schema chars 仍按
# `JSON.stringify(payload.tools).length` 统计。
#
# 模式        DS prompt chars   Luna prompt chars   DS schema chars   Luna schema chars
#   full             55,888              54,702            34,286              38,449；49 Skills。
#   no-skill         39,706              38,520            34,286              38,449；无 Skills。
#
# 相同模型、相同模式下，OMP 相对 Pi 的完整首轮输入增量：
#   full      DeepSeek +6,728 tokens；Luna +5,142 tokens。
#   no-skill  DeepSeek +7,801 tokens；Luna +6,367 tokens。
# OMP 的 active tools 受模型/provider 能力投影影响：本次 DeepSeek 为 38，Luna 为 37。

# ----------------------------------------------------------------------
# _pi_mode_help — 输出 Pi 父会话 capability mode 帮助。
#
# 参数：无。
# 输出：stdout — mode 能力、联网边界、环境覆盖与示例。
# 返回码：cat 的退出码。
# ----------------------------------------------------------------------
function _pi_mode_help() {
    cat <<'EOF'
用法：pi-mode <full|project|no-skill|core|core-search|read|read-search|chat|chat-search> [pi args...]

模式：
  full         完整 Pi 默认能力。
  project      仅显式加载 cwd 的 .pi/skills 与 cwd 到 Git 根（非 Git 到文件系统根）的 .agents/skills。
               移除 global/package/settings Skills；显式路径不受自动 project trust gate 控制。
  no-skill     不加载任何 Skill；保留 extensions、context、工具与 Web。
  core         本地编码模式：无 Skills、无 extensions，保留项目 context 与 Pi 内置编码工具。
  core-search  在 core 基础上显式加载 pi-web-access，增加联网搜索能力。
  read         本地只读模式：仅保留 read/grep/find/ls，不加载 Web extension。
  read-search  在 read 基础上显式加载 pi-web-access，并使用可覆盖的搜索工具名。
  chat         本地中性聊天：无 Skills、extensions、tools 或项目 context。
  chat-search  在 chat 基础上显式加载 pi-web-access，只保留搜索 extension tools。

联网边界：
  full、project、no-skill 保持默认联网行为；只有 *-search 模式显式加载 pi-web-access。
  core、read、chat 不加载 Web extension；任何 mode 都不是模型或进程级断网沙箱。
  mode 是启动默认值，不是安全沙箱；后续原生 Pi 参数可以显式覆盖资源或工具选择。

环境覆盖：
  PI_CODING_AGENT_DIR     覆盖 Pi agentDir，默认 $HOME/.pi/agent。
  PI_MODE_WEB_EXTENSION   覆盖 *-search 模式使用的 pi-web-access index.ts 路径。
  PI_MODE_WEB_TOOLS       覆盖 read-search 的逗号分隔搜索工具名。

示例：
  pi-mode no-skill
  pi-mode project --help
  pi-mode core
  pi-mode core-search
  pi-mode read-search
  pi-mode chat
EOF
}

# ----------------------------------------------------------------------
# _omp_mode_help — 输出 OMP 父会话 capability mode 帮助。
#
# 参数：无。
# 输出：stdout — OMP 支持的 mode 与参数转发方式。
# 返回码：cat 的退出码。
# ----------------------------------------------------------------------
function _omp_mode_help() {
    cat <<'EOF'
用法：omp-mode no-skill [omp args...]

模式：
  no-skill   使用 --no-skills 启动 OMP，其余能力保持默认。

示例：
  omp-mode no-skill
  omp-mode no-skill --help
EOF
}

# ----------------------------------------------------------------------
# _pi_mode_run — 组装并执行一个 Pi capability mode。
#
# 设计意图：
#   pi-mode 与 agent-task 共享 project/no-skill 的唯一 argv 组装路径，避免
#   项目 Skill 发现和 profile 组合长期漂移；本地与 *-search 模式保持显式分界。
#
# 参数：$1 — mode；$2 — 可选 task profile，空字符串表示普通启动；
#       $3 — 是否显示安全命令摘要；$4 — 是否 dry-run；其余为 Pi 原生参数。
# 输出：stderr — profile 启动摘要、mode 错误或搜索扩展资源错误；普通 pi-mode 启动不输出摘要。
# 副作用：除 dry-run 外启动 Pi；profile 仅注入被启动进程，不修改父 Shell。
# 返回码：0 — dry-run/宿主成功；64 — mode 非法；69 — *-search Web 扩展不可读；
#         其它 — 原样透传 Pi 退出码。
# ----------------------------------------------------------------------
function _pi_mode_run() {
    local mode="$1"
    local profile="$2"
    local show_command="$3"
    local dry_run="$4"
    local current
    local parent
    local git_root=''
    local agent_dir=''
    local search_extension=''
    local search_tools=''
    local local_chat_prompt="You are a concise, helpful conversational assistant. Answer directly and reply in the user's language unless asked otherwise."
    local search_chat_prompt="You are a concise, helpful conversational assistant with web search and page-fetching tools. Answer directly, use tools when current or source-backed information is needed, and reply in the user's language unless asked otherwise."
    local argument_count
    local -a fixed_args
    local -a user_args
    shift 4
    user_args=("$@")
    argument_count="${#user_args[@]}"
    fixed_args=()

    case "$mode" in
        full)
            ;;
        project)
            fixed_args+=(--no-skills)
            current="$(pwd -P)" || return 70
            if [ -d "$current/.pi/skills" ]; then
                fixed_args+=(--skill "$current/.pi/skills")
            fi
            git_root="$(command git -C "$current" rev-parse --show-toplevel 2>/dev/null)" || git_root=''
            if [ -n "$git_root" ]; then
                git_root="$(cd "$git_root" && pwd -P)" || return 70
            fi
            while :; do
                if [ -d "$current/.agents/skills" ]; then
                    fixed_args+=(--skill "$current/.agents/skills")
                fi
                if { [ -n "$git_root" ] && [ "$current" = "$git_root" ]; } || [ "$current" = '/' ]; then
                    break
                fi
                parent="${current%/*}"
                [ -n "$parent" ] || parent='/'
                current="$parent"
            done
            ;;
        no-skill)
            fixed_args+=(--no-skills)
            ;;
        core)
            fixed_args+=(--no-skills --no-extensions)
            ;;
        core-search)
            agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
            search_extension="${PI_MODE_WEB_EXTENSION:-$agent_dir/npm/node_modules/pi-web-access/index.ts}"
            if [ ! -f "$search_extension" ] || [ ! -r "$search_extension" ]; then
                printf 'pi-mode: pi-web-access 不存在或不可读：%s\n' "$search_extension" >&2
                return 69
            fi
            fixed_args+=(--no-skills --no-extensions -e "$search_extension")
            ;;
        read)
            fixed_args+=(--no-skills --no-extensions --tools 'read,grep,find,ls')
            ;;
        read-search)
            agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
            search_extension="${PI_MODE_WEB_EXTENSION:-$agent_dir/npm/node_modules/pi-web-access/index.ts}"
            if [ ! -f "$search_extension" ] || [ ! -r "$search_extension" ]; then
                printf 'pi-mode: pi-web-access 不存在或不可读：%s\n' "$search_extension" >&2
                return 69
            fi
            search_tools="${PI_MODE_WEB_TOOLS:-web_search,source_check,fetch_content,get_search_content}"
            fixed_args+=(--no-skills --no-extensions -e "$search_extension")
            fixed_args+=(--tools "read,grep,find,ls,$search_tools")
            ;;
        chat)
            fixed_args+=(
                --no-skills
                --no-extensions
                --no-context-files
                --no-tools
                --system-prompt "$local_chat_prompt"
            )
            ;;
        chat-search)
            agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
            search_extension="${PI_MODE_WEB_EXTENSION:-$agent_dir/npm/node_modules/pi-web-access/index.ts}"
            if [ ! -f "$search_extension" ] || [ ! -r "$search_extension" ]; then
                printf 'pi-mode: pi-web-access 不存在或不可读：%s\n' "$search_extension" >&2
                return 69
            fi
            fixed_args+=(
                --no-skills
                --no-extensions
                -e "$search_extension"
                --no-context-files
                --no-builtin-tools
                --system-prompt "$search_chat_prompt"
            )
            ;;
        *)
            printf 'pi-mode: 未知 mode：%s；请运行 pi-mode help。\n' "$mode" >&2
            return 64
            ;;
    esac

    if [ -n "$profile" ]; then
        if [ "$mode" = 'full' ]; then
            printf 'agent-task: host=pi profile=%s source-agent=worker_%s (+%s user args)\n' \
                "$profile" "$profile" "$argument_count" >&2
            if [ "$show_command" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
                printf 'agent-task command: PI_PROFILED_TASK_PROFILE=%s pi (+%s user args)\n' \
                    "$profile" "$argument_count" >&2
            fi
        else
            printf 'agent-task: host=pi profile=%s mode=%s source-agent=worker_%s (+%s user args)\n' \
                "$profile" "$mode" "$profile" "$argument_count" >&2
            if [ "$show_command" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
                printf 'agent-task command: PI_PROFILED_TASK_PROFILE=%s pi mode=%s (+%s user args)\n' \
                    "$profile" "$mode" "$argument_count" >&2
            fi
        fi
        if [ "$dry_run" -eq 1 ]; then
            return 0
        fi
        PI_PROFILED_TASK_PROFILE="$profile" command pi "${fixed_args[@]}" "${user_args[@]}"
        return $?
    fi

    command pi "${fixed_args[@]}" "${user_args[@]}"
    return $?
}

# ----------------------------------------------------------------------
# pi-mode — 按 capability mode 启动 Pi 父会话。
#
# 参数：$1 — full、project、no-skill、core、core-search、read、read-search、chat、chat-search 或 help；
#       其余参数逐项原样转发给 Pi。
# 输出：help 写入 stdout；参数或搜索扩展资源错误写入 stderr。
# 副作用：除 help/参数错误外启动 Pi；不修改持久配置或父 Shell 环境。
# 返回码：help 返回 0；mode 错误返回 64；*-search Web 扩展错误返回 69；
#         其它原样透传 Pi 退出码。
# ----------------------------------------------------------------------
function pi-mode() {
    local mode="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$mode" in
        help|--help|-h)
            _pi_mode_help
            return $?
            ;;
    esac

    _pi_mode_run "$mode" '' 0 0 "$@"
}

# ----------------------------------------------------------------------
# omp-mode — 按 capability mode 启动 OMP 父会话。
#
# 参数：$1 — no-skill 或 help；其余参数逐项原样转发给 OMP。
# 输出：help 写入 stdout；未知 mode 写入 stderr。
# 副作用：除 help/参数错误外启动 OMP；不修改持久配置或父 Shell 环境。
# 返回码：help 返回 0；mode 错误返回 64；其它原样透传 OMP 退出码。
# ----------------------------------------------------------------------
function omp-mode() {
    local mode="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$mode" in
        help|--help|-h)
            _omp_mode_help
            return $?
            ;;
        no-skill)
            command omp --no-skills "$@"
            return $?
            ;;
        *)
            printf 'omp-mode: 未知 mode：%s；请运行 omp-mode help。\n' "$mode" >&2
            return 64
            ;;
    esac
}

# ----------------------------------------------------------------------
# agent-task — 以进程级 profile 与可兼容父会话 mode 启动 AI 宿主。
#
# 参数：$1 — 宿主（omp、codex 或 pi）；$2 — profile（fast、medium、slow 或 max）；
#       后续可选 --mode、--show-command、--dry-run、--，其余参数完整转发给宿主。
# 副作用：向 stderr 输出不含用户参数内容的路由摘要；除 --dry-run 外启动宿主进程。
# 返回码：帮助与 dry-run 返回 0；参数或组合错误返回 64；OMP overlay 错误返回 66；
#         Pi mode 资源错误返回 69；否则原样返回宿主退出码。
# ----------------------------------------------------------------------
function agent-task() {
    if [ "${1-}" = "--help" ] || [ "${1-}" = "-h" ]; then
        printf '%s\n' \
            '用法：agent-task <host> <profile> [--mode <mode>] [--show-command|--dry-run] [--] [args...]' \
            '' \
            'Profile 支持：' \
            '  omp   fast|medium|slow|max  使用 $HOME/.omp/overlays/task-<profile>.yml' \
            '  codex fast|medium|slow|max  仅覆盖当前进程的默认 subagent 模型与推理强度' \
            '  pi    fast|medium|slow|max  设置当前进程的 PI_PROFILED_TASK_PROFILE' \
            '  claude                     仅支持持久化 worker-fast' \
            '' \
            'Mode 支持：' \
            '  pi    full|project|no-skill' \
            '  omp   full|no-skill' \
            '  codex full' \
            '  未指定 --mode 时保持原 full 行为；Pi 更低档会移除 Subagent，不能组合 profile。' \
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
            '示例：' \
            '  agent-task pi fast --mode project' \
            '  agent-task pi fast --mode no-skill' \
            '  agent-task omp fast --mode no-skill --dry-run' \
            '  agent-task codex max --show-command -- --help'
        return 0
    fi

    if [ "$#" -lt 2 ]; then
        printf '%s\n' 'agent-task: 需要 host 和 profile；请运行 agent-task --help。' >&2
        return 64
    fi

    local host="$1"
    local profile="$2"
    local mode='full'
    local show_command=0
    local dry_run=0
    local overlay=''
    local model=''
    local effort=''
    local argument_count
    local -a host_args
    local -a user_args
    shift 2

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --mode)
                if [ "$#" -lt 2 ]; then
                    printf '%s\n' 'agent-task: --mode 需要值；请运行 agent-task --help。' >&2
                    return 64
                fi
                mode="$2"
                shift 2
                ;;
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
        fast|medium|slow|max) ;;
        *)
            printf 'agent-task: 未知 profile：%s（支持 fast、medium、slow、max）；请运行 agent-task --help。\n' "$profile" >&2
            return 64
            ;;
    esac

    case "$host" in
        omp)
            case "$mode" in
                full|no-skill) ;;
                *)
                    printf 'agent-task: OMP 不支持 mode：%s（支持 full、no-skill）。\n' "$mode" >&2
                    return 64
                    ;;
            esac
            overlay="$HOME/.omp/overlays/task-$profile.yml"
            if [ ! -f "$overlay" ] || [ ! -r "$overlay" ]; then
                printf 'agent-task: OMP overlay 不存在或不可读：%s\n' "$overlay" >&2
                return 66
            fi
            host_args=(--config "$overlay")
            if [ "$mode" = 'no-skill' ]; then
                host_args+=(--no-skills)
                printf 'agent-task: host=%s profile=%s mode=%s overlay=%s (+%s user args)\n' \
                    "$host" "$profile" "$mode" "$overlay" "$argument_count" >&2
            else
                printf 'agent-task: host=%s profile=%s overlay=%s (+%s user args)\n' \
                    "$host" "$profile" "$overlay" "$argument_count" >&2
            fi
            if [ "$show_command" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
                if [ "$mode" = 'no-skill' ]; then
                    printf 'agent-task command: omp --config "$HOME/.omp/overlays/task-%s.yml" mode=no-skill (+%s user args)\n' \
                        "$profile" "$argument_count" >&2
                else
                    printf 'agent-task command: omp --config "$HOME/.omp/overlays/task-%s.yml" (+%s user args)\n' \
                        "$profile" "$argument_count" >&2
                fi
            fi
            if [ "$dry_run" -eq 1 ]; then
                return 0
            fi
            command omp "${host_args[@]}" "${user_args[@]}"
            return $?
            ;;
        codex)
            if [ "$mode" != 'full' ]; then
                printf 'agent-task: Codex 只支持 full mode，收到：%s。\n' "$mode" >&2
                return 64
            fi
            case "$profile" in
                fast)
                    model='gpt-5.6-luna'
                    effort='high'
                    ;;
                medium)
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
            case "$mode" in
                full|project|no-skill) ;;
                *)
                    printf 'agent-task: Pi 不支持 mode：%s（profile 仅支持 full、project、no-skill）。\n' "$mode" >&2
                    return 64
                    ;;
            esac
            _pi_mode_run "$mode" "$profile" "$show_command" "$dry_run" "${user_args[@]}"
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

