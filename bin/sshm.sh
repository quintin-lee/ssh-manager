#!/usr/bin/env bash
# Author: quintin
# Date: 2026-01-10
# Version: read from VERSION file at runtime

set -o pipefail

# shellcheck disable=SC1090
_echo() { printf '%b\n' "$*"; }
_die()  { _echo "${RED}$*${RESET}" >&2; exit 1; }

_require_bash4() {
    [[ "${BASH_VERSINFO[0]}" -ge 4 ]] || _die "Bash 4.0+ required (current: ${BASH_VERSION}). Install with: brew install bash"
}

sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
_source_lib() {
    local name="$1"
    if [[ -f "${SCRIPT_DIR}/../lib/${name}.sh" ]]; then
        source "${SCRIPT_DIR}/../lib/${name}.sh"
    elif [[ -f "/usr/local/lib/${name}.sh" ]]; then
        source "/usr/local/lib/${name}.sh"
    elif [[ -f "/usr/share/ssh-manager/${name}.sh" ]]; then
        source "/usr/share/ssh-manager/${name}.sh"
    elif [[ -f "/usr/local/share/ssh-manager/${name}.sh" ]]; then
        source "/usr/local/share/ssh-manager/${name}.sh"
    else
        _die "Error: ${name}.sh not found. Please reinstall ssh-manager."
    fi
}

_source_lib yaml_parser
_source_lib yaml_ops
_source_lib config
_source_lib util
_source_lib ssh
_source_lib node_cmd
_source_lib tui

_require_bash4

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "SSH Manager v${VERSION} - SSH connection management tool"
            echo ""
            echo "Usage:"
            echo "  sshm [keyword]        Search & connect directly"
            echo "  sshm                   Interactive mode (arrow keys, real-time filter)"
            echo ""
            echo "Options:"
            echo "  --help, -h            Show this help message"
            echo "  --version, -v         Show version information"
            echo "  --config <path>       Use specified config file"
            echo "  --validate            Validate config file syntax"
            echo "  --import-ssh-config f Import Host entries from SSH config"
            echo "  --export-ssh-config   Export nodes to SSH config format"
            echo "  --list                List nodes (use --format json for machine-readable output)"
            echo "  --format <fmt>        Output format: text (default), json"
            echo ""
            echo "Interactive keys:"
            echo "  ↑↓  Navigate   Enter  Connect    type  Filter"
            echo "  a   Add node    d     Delete     e     Export"
            echo "  i   Import      h     Help       q     Quit"
            echo ""
            echo "Environment:"
            echo "  SSH_MANAGER_CONFIG    Path to config file"
            exit 0
            ;;
        --version|-v)
            echo "SSH Manager v${VERSION}"
            exit 0
            ;;
        --config)
            shift
            if [[ -n "${1:-}" ]]; then
                export SSH_MANAGER_CONFIG="$1"
                _SSHM_CONF="$1"
                shift
            else
                _die "Error: --config requires a path argument"
            fi
            ;;
        --validate)
            init_env
            if [[ ! -f "$_SSHM_CONF" ]]; then
                _echo "${RED}配置文件不存在: $_SSHM_CONF${RESET}"
                exit 1
            fi
            if [[ ! -r "$_SSHM_CONF" ]]; then
                _echo "${RED}配置文件不可读: $_SSHM_CONF${RESET}"
                exit 1
            fi
            if ! grep -q "^nodes:" "$_SSHM_CONF" 2>/dev/null; then
                _echo "${RED}配置缺少 nodes: 头部${RESET}"
                exit 1
            fi
            get_all_nodes "$_SSHM_CONF" "" ""
            _echo "${GREEN}配置有效: ${#NODES_ARRAY[@]} 个节点${RESET}"
            exit 0
            ;;
        --import-ssh-config)
            shift
            _ssh_conf="${1:-${HOME}/.ssh/config}"
            if [[ ! -f "$_ssh_conf" ]]; then
                _die "SSH config not found: $_ssh_conf"
            fi
            init_env
            _count=0
            _ch="" _cn="" _cp="22" _cu=""
            while IFS= read -r line; do
                if [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+(.+) ]]; then
                    if [[ -n "$_cn" && -n "$_ch" ]]; then
                        cat >>"$_SSHM_CONF" <<NODE
  - name: $_cn
    group: Imported
    host: $_ch
    port: $_cp
    user: ${_cu:-root}
    type: key
    pass: ""
    keypath: ""
NODE
                        ((_count++))
                    fi
                    _cn="${BASH_REMATCH[1]}"
                    _cn="${_cn%% *}"
                    _ch=""
                elif [[ "$line" =~ ^[[:space:]]*HostName[[:space:]]+(.+) ]]; then
                    _ch="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*Port[[:space:]]+(.+) ]]; then
                    _cp="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ ^[[:space:]]*User[[:space:]]+(.+) ]]; then
                    _cu="${BASH_REMATCH[1]}"
                fi
            done <"$_ssh_conf"
            if [[ -n "$_cn" && -n "$_ch" ]]; then
                cat >>"$_SSHM_CONF" <<NODE
  - name: $_cn
    group: Imported
    host: $_ch
    port: $_cp
    user: ${_cu:-root}
    type: key
    pass: ""
    keypath: ""
NODE
                ((_count++))
            fi
            if [[ $_count -gt 0 ]]; then
                _echo "${GREEN}从 $_ssh_conf 导入了 ${_count} 个主机${RESET}"
            else
                _echo "${YELLOW}未找到可导入的主机条目${RESET}"
            fi
            exit 0
            ;;
        --export-ssh-config)
            init_env
            get_all_nodes "$_SSHM_CONF" "" ""
            echo "# Generated by ssh-manager"
            for node in "${NODES_ARRAY[@]}"; do
                IFS='|' read -r id name group host port type <<<"$node"
                echo ""
                echo "Host $name"
                echo "    HostName $host"
                echo "    Port $port"
                [[ -n "$group" && "$group" != "Default" ]] && echo "    # Group: $group"
            done
            exit 0
            ;;
        --list)
            shift
            _list_format="text"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --format)
                        shift
                        _list_format="${1:-text}"
                        shift
                        ;;
                    *)
                        break
                        ;;
                esac
            done
            init_env
            get_all_nodes "$_SSHM_CONF" "" ""
            case "$_list_format" in
                json)
                    echo "["
                    first=1
                    for node in "${NODES_ARRAY[@]}"; do
                        IFS='|' read -r id name group host port type tags <<<"$node"
                        [[ $first -eq 0 ]] && echo ","
                        first=0
                        printf '  {"id":%d,"name":"%s","group":"%s","host":"%s","port":%s,"type":"%s","tags":"%s"}' \
                            "$id" "$name" "$group" "$host" "$port" "$type" "${tags:-}"
                    done
                    echo ""
                    echo "]"
                    ;;
                *)
                    for node in "${NODES_ARRAY[@]}"; do
                        IFS='|' read -r id name group host port type tags <<<"$node"
                        echo "[$id] $name ($host:$port) [$group] [$type]${tags:+ [tags:$tags]}"
                    done
                    ;;
            esac
            exit 0
            ;;
        *)
            if [[ "$1" == -* ]]; then
                _die "Unknown option: $1. Use --help for usage information."
            fi
            break
            ;;
    esac
done

init_env

if [[ $# -gt 0 ]]; then
    keyword="${1,,}"
    shift
    get_all_nodes "$_SSHM_CONF" "$keyword" ""
    if [[ ${#NODES_ARRAY[@]} -eq 0 ]]; then
        _die "无匹配节点: $keyword"
    elif [[ ${#NODES_ARRAY[@]} -eq 1 ]]; then
        IFS='|' read -r id name group host port type <<<"${NODES_ARRAY[0]}"
        _echo "连接: $name ($host:$port)"
        ssh_connect "$id"
    else
        _echo "${YELLOW}找到 ${#NODES_ARRAY[@]} 个匹配节点:${RESET}"
        for node in "${NODES_ARRAY[@]}"; do
            IFS='|' read -r id name group host port type <<<"$node"
            echo "  [$id] $name ($host:$port) [$group]"
        done
        echo ""
        _echo "请运行 ${GREEN}sshm${RESET} 进入交互界面选择，或输入更精确的关键词"
        exit 1
    fi
    exit 0
fi

_interactive_list
