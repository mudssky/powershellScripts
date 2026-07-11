#!/usr/bin/env zsh

set -euo pipefail

DRY_RUN=false
EXCLUDES=()

# 功能：输出 shell 配置部署帮助。
# 参数：无。
# 返回：无，内容写入 stdout。
usage() {
    cat <<'EOF'
Usage: 04deployShellConfig.zsh [options]

Options:
  --preset Core|Full     由根编排器透传，不改变本步骤行为
  --exclude <pattern>    排除配置片段，可重复
  --unattended           接受根编排器交互参数
  --non-interactive      接受根编排器交互参数
  --dry-run              只显示计划
  -h, --help             显示帮助
EOF
}

# 功能：输出错误并结束。
# 参数：$1 消息，$2 可选退出码。
# 返回：不返回。
fail() {
    print -u2 -- "$1"
    exit "${2:-1}"
}

while (( $# > 0 )); do
    case "$1" in
        --preset)
            [[ $# -ge 2 && ( "$2" == 'Core' || "$2" == 'Full' ) ]] || fail '--preset 只支持 Core 或 Full' 2
            shift 2
            ;;
        --exclude)
            [[ $# -ge 2 ]] || fail '--exclude 需要一个值' 2
            EXCLUDES+=("$2")
            shift 2
            ;;
        --unattended|--non-interactive)
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "未知参数: $1" 2
            ;;
    esac
done

script_dir="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
deploy_script="$script_dir/../shell/deploy.sh"
[[ -f "$deploy_script" ]] || fail "shell 部署入口不存在: $deploy_script"

arguments=(--shell zsh)
if [[ "$DRY_RUN" == true ]]; then
    arguments+=(--dry-run)
fi
for pattern in "${EXCLUDES[@]}"; do
    arguments+=(--exclude "$pattern")
done

bash "$deploy_script" "${arguments[@]}"
