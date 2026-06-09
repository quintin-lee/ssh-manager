#!/usr/bin/env bash
# Author: quintin
# Date: 2026-01-10
# Version: 0.2 (Final Stable)

set -o pipefail

_echo() { printf '%b\n' "$*"; }
_die()  { _echo "${RED}$*${RESET}" >&2; exit 1; }

sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

_backup_config() {
    if [[ -f "$CONF" ]]; then
        cp "$CONF" "${CONF}.bak.$(date +%s)" 2>/dev/null || true
    fi
}

declare -A _PING_CACHE

_ping_check_cached() {
    local host="$1"
    local now
    now=$(date +%s)
    local cached_time="${_PING_CACHE[$host]:-0}"

    if [[ $((now - cached_time)) -lt 30 ]]; then
        return 0
    fi

    if [[ "$(uname)" == "Darwin" ]]; then
        ping -c 1 -t 1 "$host" &>/dev/null
    else
        ping -c 1 -W 1 "$host" &>/dev/null
    fi

    if [[ $? -eq 0 ]]; then
        _PING_CACHE[$host]="$now"
        return 0
    else
        _PING_CACHE[$host]="$now"
        return 1
    fi
}

_ping_check() {
    _ping_check_cached "$@"
}

# 颜色定义（使用 $'\033' 确保转义码生效）
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
PURPLE=$'\033[35m'
CYAN=$'\033[36m'
RESET=$'\033[0m'

CONF="${SSH_MANAGER_CONFIG:-config.yaml}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../lib/yaml_parser.sh" ]]; then
    source "${SCRIPT_DIR}/../lib/yaml_parser.sh"
elif [[ -f "/usr/local/share/ssh-manager/yaml_parser.sh" ]]; then
    source "/usr/local/share/ssh-manager/yaml_parser.sh"
else
    _die "Error: yaml_parser.sh not found. Please reinstall ssh-manager."
fi

# --- 1. 环境初始化 ---

_resolve_config() {
    local user_conf="${HOME}/.config/ssh-manager/config.yaml"
    local user_conf_dir
    user_conf_dir="$(dirname "$user_conf")"

    if [[ ! -d "$user_conf_dir" ]]; then
        mkdir -p "$user_conf_dir" 2>/dev/null || true
    fi

    if [[ -f "$user_conf" ]]; then
        CONF="$user_conf"
    fi

    local conf_dir
    conf_dir=$(dirname "$CONF")

    if [[ "$CONF" == /etc/* ]]; then
        if [[ -f "$CONF" ]]; then
            if [[ ! -r "$CONF" ]]; then
                _die "错误：系统配置文件 $CONF 不可读"
            fi
            if [[ ! -f "$user_conf" ]]; then
                if cp "$CONF" "$user_conf" 2>/dev/null; then
                    chmod 600 "$user_conf" 2>/dev/null || true
                    _echo "${GREEN}已复制系统配置到个人目录: $user_conf${RESET}"
                    CONF="$user_conf"
                else
                    _echo "${YELLOW}使用只读的系统配置文件（无法保存更改）${RESET}"
                    if ! grep -q "^nodes:" "$CONF" 2>/dev/null; then
                        _die "错误：系统配置文件缺少 nodes: 头部，请检查配置"
                    fi
                fi
            else
                CONF="$user_conf"
            fi
        else
            mkdir -p "$user_conf_dir"
            touch "$user_conf"
            chmod 600 "$user_conf"
            CONF="$user_conf"
            echo "nodes:" >"$CONF"
            _echo "${YELLOW}已创建个人配置文件: $CONF${RESET}"
        fi
    else
        if [[ ! -w "$conf_dir" ]]; then
            if [[ -w "$user_conf_dir" ]]; then
                CONF="$user_conf"
            else
                _die "错误：目录 $conf_dir 不可写"
            fi
        fi

        if [[ ! -f "$CONF" ]]; then
            echo "nodes:" >"$CONF"
            _echo "${YELLOW}已创建默认配置文件: $CONF${RESET}"
        elif [[ ! -r "$CONF" ]]; then
            _die "错误：配置文件 $CONF 不可读"
        fi
    fi
}

_setup_config_permissions() {
    if [[ ! -f "$CONF" ]]; then
        return
    fi

    local file_owner
    file_owner=$(stat -c "%U" "$CONF" 2>/dev/null || stat -f "%Su" "$CONF" 2>/dev/null)
    local current_user
    current_user=$(whoami)

    if [[ "$CONF" == /etc/* ]]; then
        if [[ "$current_user" != "root" ]]; then
            _echo "${YELLOW}提示：配置文件位于 /etc 目录，普通用户无法设置 600 权限，请以 root 身份运行或忽略此提示${RESET}"
        else
            if chmod 600 "$CONF"; then
                _echo "${GREEN}已将 /etc 目录下的配置文件权限设置为 600${RESET}"
            else
                _echo "${RED}错误：root 用户也无法设置 /etc 目录下配置文件的权限为 600${RESET}"
            fi
        fi
    else
        if [[ "$file_owner" == "$current_user" ]]; then
            if ! chmod 600 "$CONF"; then
                _echo "${YELLOW}警告：无法设置配置文件权限为 600${RESET}"
            fi
        else
            _echo "${YELLOW}提示：配置文件 $CONF 不属于当前用户 $current_user，无法设置 600 权限${RESET}"
        fi
    fi
}

_check_dependencies() {
    local missing_tools=()
    for tool in expect sed awk ping base64; do
        command -v "$tool" &>/dev/null || missing_tools+=("$tool")
    done
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        _die "缺少依赖: ${missing_tools[*]}"
    fi
}

init_env() {
    _resolve_config
    _setup_config_permissions
    _check_dependencies
}

# --- 2. 简化版 YAML 解析 ---
# Functions now sourced from lib/yaml_parser.sh
# read_node_info <config_file> <id>
# get_all_nodes <config_file> [filter_key] [group_filter]

# --- 3. 核心连接逻辑 ---
ssh_connect() {
    local id=$1
    read_node_info "$CONF" "$id"

    if [[ -z "$NODE_HOST" ]]; then
        _echo "${RED}无效 ID: $id (未找到节点)${RESET}"
        sleep 1
        return 1
    fi

    _echo "${YELLOW}>>> 连接中: $NODE_NAME ($NODE_HOST)...${RESET}"

    export SSH_PASS="$NODE_PASS"
    export SSH_KEY="$NODE_KEYPATH"
    export SSH_HOST="$NODE_HOST"
    export SSH_PORT="$NODE_PORT"
    export SSH_USER="$NODE_USER"

    local ssh_extra=""
    local passphrase_branch=""
    if [[ "$NODE_TYPE" == "key" ]]; then
        ssh_extra='-i "$key"'
        passphrase_branch='
                "*passphrase*" {
                    send -- "$pass\r"
                    expect {
                        "*passphrase*" { puts "密钥短语错误"; set exit_code 2 }
                        "*Permission denied*" { puts "认证失败"; set exit_code 2 }
                        "*Last login*" { }
                        timeout { puts "登录后超时"; set exit_code 1 }
                    }
                }'
    fi

    local exit_code=0

    # shellcheck disable=SC2089,SC2090  # ssh_extra/set_passkey quoted correctly in TCL
    expect -c "
        set timeout 30
        set pass \$env(SSH_PASS)
        set host \$env(SSH_HOST)
        set port \$env(SSH_PORT)
        set user \$env(SSH_USER)
        set key \$env(SSH_KEY)
        set exit_code 0

        spawn ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o ServerAliveInterval=60 ${ssh_extra} -p \$port \$user@\$host
        expect {
            \"*password:*\" {
                send -- \"\$pass\r\"
                expect {
                    \"*password:*\" { puts \"密码错误\"; set exit_code 2 }
                    \"*Permission denied*\" { puts \"认证失败\"; set exit_code 2 }
                    \"*Last login*\" { }
                    timeout { puts \"登录后超时\"; set exit_code 1 }
                }
            }${passphrase_branch}
            \"*yes/no*\" { send \"yes\r\"; exp_continue }
            \"*Connection refused*\" { puts \"连接被拒绝\"; set exit_code 3 }
            \"*No route to host*\" { puts \"主机不可达\"; set exit_code 4 }
            \"*Connection timed out*\" { puts \"连接超时\"; set exit_code 1 }
            \"*Host key verification failed*\" { puts \"主机密钥验证失败\"; set exit_code 5 }
            \"*Could not resolve hostname*\" { puts \"无法解析主机名\"; set exit_code 6 }
            timeout { puts \"连接超时\"; set exit_code 1 }
            eof { catch wait result; set exit_code [lindex \$result 3] }
        }
        if {\$exit_code == 0} {
            interact
            catch wait result; set exit_code [lindex \$result 3]
        }
        exit \$exit_code
    "
    exit_code=$?

    unset SSH_PASS SSH_KEY SSH_HOST SSH_PORT SSH_USER
    return $exit_code
}

# --- 5. 交互式列表（方向键导航 + 实时过滤）---

_read_key() {
    local key key2 key3
    IFS= read -r -s -n 1 key
    if [[ "$key" == $'\033' ]]; then
        IFS= read -r -s -n 1 -t 0.01 key2 2>/dev/null
        if [[ "$key2" == "[" ]]; then
            IFS= read -r -s -n 1 -t 0.01 key3 2>/dev/null
            case "$key3" in
                A) echo "UP" ;;
                B) echo "DOWN" ;;
                *) echo "ESC" ;;
            esac
        else
            echo "ESC"
        fi
    elif [[ "$key" == "" ]]; then
        echo "ENTER"
    else
        echo "$key"
    fi
}

_render_list() {
    local selected_idx="$1"
    local filter_key="${2,,}"
    local highlight="${3:-0}"  # 0=normal, 1=delete mode

    get_all_nodes "$CONF" "$filter_key" ""

    if [[ ${#NODES_ARRAY[@]} -gt 0 ]]; then
        local sorted_output
        sorted_output=$(printf "%s\n" "${NODES_ARRAY[@]}" | sort -t'|' -k3,3 -k2,2)
        NODES_ARRAY=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && NODES_ARRAY+=("$line")
        done <<<"$sorted_output"
    fi

    clear
    local FORMAT_STR="%-4s | %-4s | %-12s | %-16s | %-21s | %-5s"

    _echo "${CYAN}$(printf "${FORMAT_STR}" "St" "ID" "Group" "Name" "Host:Port" "Auth")${RESET}"
    echo "-------------------------------------------------------------------------------"

    local display_id=1
    local current_group=""
    local disp_nodes=()
    local found=0

    for node in "${NODES_ARRAY[@]}"; do
        IFS='|' read -r original_id name group host port type <<<"$node"
        disp_nodes+=("$original_id|$name|$group|$host|$port|$type")
        found=1
    done

    _RENDERED_NODES=("${disp_nodes[@]}")

    local idx=0
    for node in "${disp_nodes[@]}"; do
        IFS='|' read -r original_id name group host port type <<<"$node"

        if [[ -z "$filter_key" && "$group" != "$current_group" ]]; then
            local sel=""
            [[ "$highlight" -eq 1 && $idx -eq $selected_idx ]] && sel="${BLUE}>${RESET} "
            _echo "${PURPLE}${sel}$(printf "${FORMAT_STR}" "" "" "[$group]" "" "" "")${RESET}"
            current_group="$group"
            ((idx++))
        fi

        local st="●   "
        if _ping_check "$host"; then
            st="${GREEN}●${RESET}   "
        else
            st="${RED}●${RESET}   "
        fi

        local id_str
        id_str=$(printf "%-4d" $display_id)
        id_str="${GREEN}${id_str}${RESET}"

        local line_color=""
        [[ "$highlight" -eq 1 && $idx -eq $selected_idx ]] && line_color="${BLUE}>${RESET} "
        [[ "$highlight" -eq 2 && $idx -eq $selected_idx ]] && line_color="${RED}>${RESET} "

        local node_line
        node_line="$(printf "${FORMAT_STR}" "$st" "$id_str" "$group" "$name" "$host:$port" "$type")"
        _echo "${line_color}${node_line}"
        ((display_id++))
        ((idx++))
    done

    if [[ $found -eq 0 ]]; then
        local empty_msg=""
        [[ -n "$filter_key" ]] && empty_msg="无匹配 [${filter_key}]" || empty_msg="暂无节点，请先添加 (按 a)"
        echo ""
        _echo "${YELLOW}  ${empty_msg}${RESET}"
        echo ""
    fi

    echo "-------------------------------------------------------------------------------"
    local mode_hint=""
    [[ "$highlight" -eq 2 ]] && mode_hint="${RED}[删除模式]${RESET} " 
    local total=$(( ${#disp_nodes[@]} + 0 ))
    _echo "${mode_hint}节点: ${total} | ${BLUE}↑↓${RESET}选择 ${BLUE}Enter${RESET}连接 | ${BLUE}输入${RESET}过滤 | ${BLUE}a${RESET}添加 ${BLUE}d${RESET}删除 ${BLUE}q${RESET}退出"
    [[ -n "$filter_key" ]] && _echo "过滤: ${YELLOW}${filter_key}${RESET} (ESC 清除)"
}

_interactive_list() {
    local filter_key=""
    local selected_idx=0
    local mode="normal"
    _RENDERED_NODES=()  # normal or delete

    while true; do
        _render_list "$selected_idx" "$filter_key" "$([[ "$mode" == "delete" ]] && echo 2 || echo 1)"

        local key
        key=$(_read_key)

        case "$key" in
        UP)
            ((selected_idx > 0)) && ((selected_idx--))
            ;;
        DOWN)
            local total=${#_RENDERED_NODES[@]}
            ((selected_idx < total - 1)) && ((selected_idx++))
            ;;
        ENTER)
            if [[ $selected_idx -ge 0 && $selected_idx -lt ${#_RENDERED_NODES[@]} ]]; then
                local target_node="${_RENDERED_NODES[$selected_idx]}"
                local original_id
                original_id=$(echo "$target_node" | cut -d'|' -f1)
                if [[ "$mode" == "delete" ]]; then
                    _echo "\n"
                    perform_delete "$original_id"
                    mode="normal"
                    selected_idx=0
                else
                    ssh_connect "$original_id"
                    local conn_status=$?
                    if [[ $conn_status -ne 0 ]]; then
                        case $conn_status in
                            1) _echo "${RED}连接超时${RESET}" ;;
                            2) _echo "${RED}认证失败${RESET}" ;;
                            3) _echo "${RED}连接被拒绝${RESET}" ;;
                            4) _echo "${RED}主机不可达${RESET}" ;;
                            5) _echo "${RED}主机密钥验证失败${RESET}" ;;
                            6) _echo "${RED}无法解析主机名${RESET}" ;;
                            *) _echo "${RED}连接异常退出 ($conn_status)${RESET}" ;;
                        esac
                        sleep 1.5
                    fi
                fi
            fi
            ;;
        ESC)
            filter_key=""
            selected_idx=0
            ;;
        a|A)
            add_node
            ;;
        d|D)
            if [[ "$mode" == "delete" ]]; then
                mode="normal"
            else
                mode="delete"
                selected_idx=0
            fi
            ;;
        e|E)
            export_config
            ;;
        i|I)
            import_config
            ;;
        h|H)
            show_help
            ;;
        q|Q)
            return
            ;;
        $'\177'|$'\010')
            # Backspace
            if [[ -n "$filter_key" ]]; then
                filter_key="${filter_key:0:-1}"
                selected_idx=0
            fi
            ;;
        [[:print:]])
            filter_key="${filter_key}${key,,}"
            selected_idx=0
            ;;
        esac
    done
}

# --- 6. 删除逻辑 ---
perform_delete() {
    local id=$1
    [[ "$id" =~ ^[0-9]+$ ]] || { _echo "${RED}无效 ID: $id${RESET}"; sleep 1; return 1; }
    read_node_info "$CONF" "$id"

    if [[ -z "$NODE_HOST" ]]; then
        _echo "${RED}无效 ID: $id (未找到节点)${RESET}"
        sleep 1
        return 1
    fi

    read -p "确认永久删除节点 [$NODE_NAME] ? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        _echo "${YELLOW}取消删除操作${RESET}"
        sleep 1
        return 0
    fi

    local tmp_file
    tmp_file=$(mktemp) || { _echo "${RED}错误：无法创建临时文件${RESET}"; return 1; }
    local current_id=0
    local skip=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            current_id=$((current_id + 1))
            if [[ $current_id -eq $id ]]; then
                skip=1
                continue
            else
                skip=0
            fi
        fi

        if [[ $skip -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                skip=0
                echo "$line" >>"$tmp_file"
            fi
            continue
        fi

        echo "$line" >>"$tmp_file"
    done <"$CONF"

    sed_i '/^[[:space:]]*$/N;/^[[:space:]]*\n[[:space:]]*$/D' "$tmp_file"
    if [[ $(head -n1 "$tmp_file" | tr -d '[:space:]') != "nodes:" ]]; then
        sed_i '1i nodes:' "$tmp_file"
    fi
    _backup_config
    if mv "$tmp_file" "$CONF"; then
        chmod 600 "$CONF" 2>/dev/null
	_echo "${GREEN}节点 [$NODE_NAME] 已成功删除。${RESET}"
    else
	_echo "${RED}错误：写入配置文件失败，备份已保存至 ${CONF}.bak.*${RESET}"
	return 1
    fi
    sleep 1
    return 0
}

# --- 7. 添加节点功能 ---
sanitize_yaml_value() {
    local val="$1"
    local need_quote=0

    if [[ "$val" == *:* || "$val" == *\#* || "$val" == *\"* || "$val" == *\\* ]]; then
        need_quote=1
    elif [[ "$val" =~ ^[[:space:]] || "$val" =~ [[:space:]]$ ]]; then
        need_quote=1
    fi

    if [[ "$need_quote" -eq 1 ]]; then
        val="${val//\\/\\\\}"
        val="${val//\"/\\\"}"
        echo "\"$val\""
    else
        echo "$val"
    fi
}

add_node() {
    _echo "\n${BLUE}[添加新节点]${RESET}"

    while true; do
        read -p "名称: " n
        n=$(echo "$n" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$n" ]]; then
            break
        fi
        _echo "${RED}名称不能为空，请重新输入${RESET}"
    done

    read -p "分组 (默认 Default): " g
    g=$(echo "$g" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    g=${g:-Default}

    while true; do
        read -r -p "主机 (IP/域名): " h
        h=$(echo "$h" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$h" ]]; then
            _echo "${RED}主机不能为空，请重新输入${RESET}"
            continue
        fi
        if [[ "$h" =~ [[:space:]\;\|\&\$\`\(\)\{\}\<\>\"\'] ]]; then
            _echo "${RED}主机包含非法字符，请重新输入${RESET}"
            continue
        fi
        break
    done

    while true; do
        read -p "端口 (默认 22): " p
        p=$(echo "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        p=${p:-22}
        if [[ "$p" =~ ^[0-9]+$ && "$p" -ge 1 && "$p" -le 65535 ]]; then
            break
        fi
        _echo "${RED}端口无效（必须是 1-65535 之间的数字），请重新输入${RESET}"
    done

    while true; do
        read -r -p "用户: " u
        u=$(echo "$u" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$u" ]]; then
            _echo "${RED}用户不能为空，请重新输入${RESET}"
            continue
        fi
        if [[ "$u" =~ [[:space:]\;\|\&\$\`\(\)\{\}\<\>\"\'] ]]; then
            _echo "${RED}用户名包含非法字符，请重新输入${RESET}"
            continue
        fi
        break
    done

    local t="pass"
    local kp=""
    local ps=""
    while true; do
        read -p "认证类型 (1:密码 2:密钥，默认 1): " ac
        ac=${ac:-1}
        if [[ "$ac" == "1" || "$ac" == "2" ]]; then
            break
        fi
        _echo "${RED}无效选择，请输入 1 或 2${RESET}"
    done

    if [[ "$ac" == "2" ]]; then
        t="key"
        while true; do
            read -r -p "私钥路径: " kp
            kp=$(echo "$kp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -z "$kp" ]]; then
                _echo "${RED}私钥路径不能为空，请重新输入${RESET}"
                continue
            fi
            if [[ -f "$kp" ]]; then
                if grep -q "PRIVATE KEY" "$kp" 2>/dev/null || ssh-keygen -l -f "$kp" &>/dev/null; then
                    break
                fi
                _echo "${RED}文件不是有效的SSH私钥，请重新输入${RESET}"
                continue
            fi
            _echo "${RED}私钥文件不存在，请重新输入${RESET}"
        done
        read -s -p "私钥短语 (可选): " ps
        echo ""
    else
        read -s -p "密码: " ps
        echo ""
    fi

    # shellcheck disable=SC1003  # sed append syntax, not a shell escape
    sed_i -e '$a\' "$CONF" 2>/dev/null || true

    _backup_config
    if cat >>"$CONF" <<EOF
  - name: $(sanitize_yaml_value "$n")
    group: $(sanitize_yaml_value "$g")
    host: $(sanitize_yaml_value "$h")
    port: $p
    user: $(sanitize_yaml_value "$u")
    type: $t
    pass: $(sanitize_yaml_value "$ps")
    keypath: $(sanitize_yaml_value "$kp")
EOF
    then
        _echo "${GREEN}节点 [$n] 已成功添加。 (${h}:${p} ${u}@${t})${RESET}"
    else
        _echo "${RED}错误：写入配置文件失败，备份已保存${RESET}"
        return 1
    fi
    sleep 1
}

# --- 8. 导入导出功能 ---
export_config() {
    if [[ ! -f "$CONF" ]]; then
        _echo "${RED}配置文件不存在${RESET}"
        sleep 1
        return 1
    fi

    _echo "\n--- ${BLUE}配置导出选项${RESET} ---"
    echo "1) ${YELLOW}屏幕输出 Base64${RESET} (适合复制分享)"
    echo "2) ${YELLOW}保存到文件${RESET} (适合备份)"
    printf "${GREEN}选择导出方式 (1/2): ${RESET}"

    read -n 1 export_choice
    echo # 换行

    case $export_choice in
    1)
        _echo "\n--- ${BLUE}BASE64 配置导出${RESET} ---"
        _echo "${YELLOW}注意：此内容包含敏感的密码信息，请妥善保管！${RESET}"
        echo
        if ! base64 "$CONF" | tr -d '\n'; then
            _echo "${RED}导出失败：无法读取配置文件${RESET}"
            sleep 2
            return 1
        fi
        _echo "\n------------------------"
        read -n 1 -p "按任意键返回..."
        echo
        ;;
    2)
        read -r -p "请输入导出文件路径 (默认: ./ssh-manager-config.yaml): " export_file
        export_file=${export_file:-"./ssh-manager-config.yaml"}

        if cp "$CONF" "$export_file"; then
            chmod 600 "$export_file" 2>/dev/null
            _echo "${GREEN}配置已导出到: $export_file${RESET}"
        else
            _echo "${RED}导出失败${RESET}"
        fi
        sleep 2
        ;;
    *)
        _echo "${RED}无效选择${RESET}"
        sleep 1
        ;;
    esac
}

import_config() {
    _echo "\n--- ${BLUE}配置导入选项${RESET} ---"
    echo "1) ${YELLOW}从 Base64 字符串导入${RESET} (从剪贴板)"
    echo "2) ${YELLOW}从文件导入${RESET} (从备份文件)"
    printf "${GREEN}选择导入方式 (1/2): ${RESET}"

    read -n 1 import_choice
    echo # 换行

    case $import_choice in
    1)
        _echo "${BLUE}从 Base64 字符串导入${RESET}"
        _echo "${YELLOW}警告：此操作将覆盖现有配置！${RESET}"
        read -p "是否继续? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            _echo "${YELLOW}取消导入操作${RESET}"
            sleep 1
            return 0
        fi

        read -p "粘贴 BASE64 内容: " b64
        if [[ -z "$b64" ]]; then
            _echo "${RED}输入为空，导入失败${RESET}"
            sleep 1
            return 1
        fi

        b64_clean=$(echo "$b64" | tr -d '[:space:]')

        if ! echo "$b64_clean" | base64 -d >/dev/null 2>&1; then
            _echo "${RED}无效的 BASE64 格式${RESET}"
            sleep 1
            return 1
        fi

        _backup_config
        if echo "$b64_clean" | base64 -d >"$CONF"; then
            chmod 600 "$CONF" 2>/dev/null
            _echo "${GREEN}配置导入成功${RESET}"
        else
            _echo "${RED}错误：写入配置文件失败，备份已保存${RESET}"
            return 1
        fi
        sleep 1
        return 0
        ;;
    2)
        _echo "${BLUE}从文件导入${RESET}"
        _echo "${YELLOW}警告：此操作将覆盖现有配置！${RESET}"
        read -p "是否继续? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            _echo "${YELLOW}取消导入操作${RESET}"
            sleep 1
            return 0
        fi

        read -r -p "请输入配置文件路径: " import_file

        if [[ ! -f "$import_file" ]]; then
            _echo "${RED}文件不存在: $import_file${RESET}"
            sleep 2
            return 1
        fi

        if ! grep -q "^nodes:" "$import_file" 2>/dev/null; then
            _echo "${RED}验证失败：文件可能不是有效的SSH管理器配置文件${RESET}"
            sleep 2
            return 1
        fi

        _backup_config
        if cp "$import_file" "$CONF"; then
            chmod 600 "$CONF" 2>/dev/null
            _echo "${GREEN}配置从文件导入成功: $import_file${RESET}"
        else
            _echo "${RED}导入失败，备份已保存${RESET}"
        fi
        sleep 2
        ;;
    *)
        _echo "${RED}无效选择${RESET}"
        sleep 1
        ;;
    esac
}

# --- 9. 主循环 ---

VERSION=$(cat "${SCRIPT_DIR}/../VERSION" 2>/dev/null || cat "/usr/local/share/ssh-manager/VERSION" 2>/dev/null || echo "0.2")

while [[ $# -gt 0 ]]; do
    case "$1" in
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
                shift
            else
                _die "Error: --config requires a path argument"
            fi
            ;;
        *)
            if [[ "$1" == -* ]]; then
                _die "Unknown option: $1. Use --help for usage information."
            fi
            break
            ;;
    esac
done

CONF="${SSH_MANAGER_CONFIG:-config.yaml}"

init_env

show_help() {
    echo ""
    _echo "${CYAN}==== SSH MANAGER v0.2 帮助 ====${RESET}"
    echo ""
    _echo "${GREEN}列表导航:${RESET}"
    echo "  ${BLUE}↑↓${RESET}        - 选择节点, 当前行高亮"
    echo "  ${BLUE}Enter${RESET}     - 连接到选中节点"
    echo "  ${BLUE}输入文字${RESET}  - 实时过滤节点列表"
    echo "  ${BLUE}ESC${RESET}       - 清除过滤条件"
    echo "  ${BLUE}退格${RESET}      - 删除最后一个过滤字符"
    echo ""
    _echo "${GREEN}快捷键:${RESET}"
    echo "  ${BLUE}a${RESET} - 添加节点   ${BLUE}d${RESET} - 删除模式(再按退出)"
    echo "  ${BLUE}e${RESET} - 导出配置   ${BLUE}i${RESET} - 导入配置"
    echo "  ${BLUE}h${RESET} - 帮助       ${BLUE}q${RESET} - 退出程序"
    echo ""
    _echo "${GREEN}命令行:${RESET}"
    echo "  sshm prod         - 直接搜索并连接匹配节点"
    echo "  sshm --config <f>  - 使用指定配置文件"
    echo "  sshm --help        - 显示此帮助"
    echo ""
    read -n 1 -r -p "按任意键返回..." _
    echo
}

# CLI direct connect: sshm <keyword>
if [[ $# -gt 0 ]]; then
    keyword="${1,,}"
    shift
    get_all_nodes "$CONF" "$keyword" ""
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
