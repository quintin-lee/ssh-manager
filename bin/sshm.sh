#!/usr/bin/env bash
# Author: quintin
# Date: 2026-01-10
# Version: 0.2 (Final Stable)

# 强制启用转义序列解析
shopt -s xpg_echo 2>/dev/null

# 兼容 macOS 的 sed -i 命令
sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
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
fi

# --- 1. 环境初始化（优化权限处理）---
init_env() {
    # First check if user has personal config file
    local user_conf="${HOME}/.config/ssh-manager/config.yaml"
    local user_conf_dir
    user_conf_dir="$(dirname "$user_conf")"

    # Create user config directory if it doesn't exist
    if [[ ! -d "$user_conf_dir" ]]; then
        mkdir -p "$user_conf_dir" 2>/dev/null || true
    fi

    # If user config exists, use it instead of default
    if [[ -f "$user_conf" ]]; then
        CONF="$user_conf"
    fi

    local conf_dir
    conf_dir=$(dirname "$CONF")

    # Check if config is in system directory like /etc
    if [[ "$CONF" == /etc/* ]]; then
        # System-wide config file exists, but users shouldn't write to /etc directory
        if [[ -f "$CONF" ]]; then
            # Just verify the system config file exists and is readable, no write check
            if [[ ! -r "$CONF" ]]; then
                echo -e "${RED}错误：系统配置文件 $CONF 不可读${RESET}"
                exit 1
            fi

            # Check if user has a personal config - this should be prioritized
            # Already checked above, but if we reach here, copy from system default
            if [[ ! -f "$user_conf" ]]; then
                if cp "$CONF" "$user_conf" 2>/dev/null; then
                    chmod 600 "$user_conf" 2>/dev/null || true
                    echo -e "${GREEN}已复制系统配置到个人目录: $user_conf${RESET}"
                    # Switch to use user config instead of system config
                    CONF="$user_conf"
                else
                    # If can't copy, continue with system config (read-only mode)
                    echo -e "${YELLOW}使用只读的系统配置文件（无法保存更改）${RESET}"

                    # For read-only system config, just ensure basic structure exists
                    if ! grep -q "^nodes:" "$CONF" 2>/dev/null; then
                        echo "nodes:" >/tmp/sshm_temp_config$$
                        cat "$CONF" >>/tmp/sshm_temp_config$$
                        mv /tmp/sshm_temp_config$$ "$CONF" 2>/dev/null || true
                    fi
                fi
            else
                # User has their own config, use that instead
                CONF="$user_conf"
            fi
        else
            # System config doesn't exist, suggest creating user config
            mkdir -p "$user_conf_dir"
            touch "$user_conf"
            chmod 600 "$user_conf"
            CONF="$user_conf"

            echo "nodes:" >"$CONF"
            echo -e "${YELLOW}已创建个人配置文件: $CONF${RESET}"
        fi
    else
        # Non-system config path, use original logic
        if [[ ! -w "$conf_dir" ]]; then
            # Change to user config path if it's writable
            if [[ -w "$user_conf_dir" ]]; then
                CONF="$user_conf"
                conf_dir="$user_conf_dir"
            else
                echo -e "${RED}错误：目录 $conf_dir 不可写${RESET}"
                exit 1
            fi
        fi

        if [[ ! -f "$CONF" ]]; then
            # Create config file in final location
            echo "nodes:" >"$CONF"
            echo -e "${YELLOW}已创建默认配置文件: $CONF${RESET}"
        fi
    fi

    # 优化的权限设置逻辑 - 适配不同目录和用户权限
    # 1. 先检查当前用户是否是文件所有者
    if [[ -f "$CONF" ]]; then
        local file_owner
        file_owner=$(stat -c "%U" "$CONF" 2>/dev/null || stat -f "%Su" "$CONF" 2>/dev/null)
        local current_user
        current_user=$(whoami)

        # 2. 判断配置文件路径是否在系统目录（/etc）下
        if [[ "$CONF" == /etc/* ]]; then
            # /etc 目录下：普通用户通常无权限修改权限，仅给出提示
            if [[ "$current_user" != "root" ]]; then
                echo -e "${YELLOW}提示：配置文件位于 /etc 目录，普通用户无法设置 600 权限，请以 root 身份运行或忽略此提示${RESET}"
            else
                # root 用户尝试设置权限
                if chmod 600 "$CONF"; then
                    echo -e "${GREEN}已将 /etc 目录下的配置文件权限设置为 600${RESET}"
                else
                    echo -e "${RED}错误：root 用户也无法设置 /etc 目录下配置文件的权限为 600${RESET}"
                fi
            fi
        else
            # 非 /etc 目录：正常尝试设置权限
            if [[ "$file_owner" == "$current_user" ]]; then
                # 当前用户是文件所有者，尝试设置 600 权限
                if ! chmod 600 "$CONF"; then
                    echo -e "${YELLOW}警告：无法设置配置文件权限为 600${RESET}"
                fi
            else
                # 当前用户不是文件所有者，给出明确提示
                echo -e "${YELLOW}提示：配置文件 $CONF 不属于当前用户 $current_user，无法设置 600 权限${RESET}"
            fi
        fi
    fi

    # 检查依赖工具
    local missing_tools=()
    for tool in expect sed awk ping base64; do
        command -v "$tool" &>/dev/null || missing_tools+=("$tool")
    done
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "${RED}缺少依赖: ${missing_tools[*]}${RESET}"
        exit 1
    fi
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
        echo -e "${RED}无效 ID: $id (未找到节点)${RESET}"
        sleep 1
        return 1
    fi

    echo -e "${YELLOW}>>> 连接中: $NODE_NAME ($NODE_HOST)...${RESET}"

    export SSH_PASS="$NODE_PASS"
    export SSH_KEY="$NODE_KEYPATH"
    export SSH_HOST="$NODE_HOST"
    export SSH_PORT="$NODE_PORT"
    export SSH_USER="$NODE_USER"

    local exit_code=0

    if [[ "$NODE_TYPE" == "key" ]]; then
        expect -c "
            set timeout 30
            set pass \$env(SSH_PASS)
            set key \$env(SSH_KEY)
            set host \$env(SSH_HOST)
            set port \$env(SSH_PORT)
            set user \$env(SSH_USER)
            set exit_code 0

            spawn ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -i \"\$key\" -p \$port \$user@\$host
            expect {
                \"*password:*\" {
                    send -- \"\$pass\r\"
                    expect {
                        \"*password:*\" { puts \"密码错误\"; set exit_code 2 }
                        \"*Permission denied*\" { puts \"认证失败\"; set exit_code 2 }
                        \"*Last login*\" { }
                        timeout { puts \"登录后超时\"; set exit_code 1 }
                    }
                }
                \"*passphrase*\" {
                    send -- \"\$pass\r\"
                    expect {
                        \"*passphrase*\" { puts \"密钥短语错误\"; set exit_code 2 }
                        \"*Permission denied*\" { puts \"认证失败\"; set exit_code 2 }
                        \"*Last login*\" { }
                        timeout { puts \"登录后超时\"; set exit_code 1 }
                    }
                }
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
    else
        expect -c "
            set timeout 30
            set pass \$env(SSH_PASS)
            set host \$env(SSH_HOST)
            set port \$env(SSH_PORT)
            set user \$env(SSH_USER)
            set exit_code 0

            spawn ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -p \$port \$user@\$host
            expect {
                \"*password:*\" {
                    send -- \"\$pass\r\"
                    expect {
                        \"*password:*\" { puts \"密码错误\"; set exit_code 2 }
                        \"*Permission denied*\" { puts \"认证失败\"; set exit_code 2 }
                        \"*Last login*\" { }
                        timeout { puts \"登录后超时\"; set exit_code 1 }
                    }
                }
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
    fi
    exit_code=$?

    unset SSH_PASS SSH_KEY SSH_HOST SSH_PORT SSH_USER
    return $exit_code
}

# --- 5. 列表与交互界面（终极修复版）---
list_and_choose() {
    local filter_key="${1,,}"
    local group_filter="$2"
    local mode="$3"

    while true; do
        get_all_nodes "$CONF" "$filter_key" "$group_filter"

        # 优化：按分组聚合排序，防止同一分组被拆分显示
        # Sort by Group (field 3) then Name (field 2)
        if [[ ${#NODES_ARRAY[@]} -gt 0 ]]; then
            local sorted_output
            sorted_output=$(printf "%s\n" "${NODES_ARRAY[@]}" | sort -t'|' -k3,3 -k2,2)
            NODES_ARRAY=()
            while IFS= read -r line; do
                [[ -n "$line" ]] && NODES_ARRAY+=("$line")
            done <<<"$sorted_output"
        fi

        clear
        local FORMAT_STR="%-4s | %-4s | %-12s | %-14s | %-19s | %-5s"

        # 表头（直接用 echo -e 确保颜色生效）
        echo -e "${CYAN}$(printf "${FORMAT_STR}" "St" "ID" "Group" "Name" "Host:Port" "Auth")${RESET}"
        echo "---------------------------------------------------------------------------"

        local display_id=1
        local found=0
        local current_group=""
        local display_nodes=()

        for node in "${NODES_ARRAY[@]}"; do
            IFS='|' read -r original_id name group host port type <<<"$node"
            display_nodes+=("$original_id|$name|$group|$host|$port|$type")
            found=1
        done

        for node in "${display_nodes[@]}"; do
            IFS='|' read -r original_id name group host port type <<<"$node"

            if [[ -z "$filter_key" && "$group" != "$current_group" ]]; then
                # 分组行：echo -e 解析颜色
                echo -e "${PURPLE}$(printf "${FORMAT_STR}" "" "" "[$group]" "" "" "")${RESET}"
                current_group="$group"
            fi

            # 状态列：固定宽度+颜色生效
            local st="●   "
            if ping -c 1 -W 0.3 "$host" &>/dev/null; then
                st="${GREEN}●${RESET}   "
            else
                st="${RED}●${RESET}   "
            fi

            # ID列：先格式化再加颜色
            local id_str
            id_str=$(printf "%-4d" $display_id)
            id_str="${GREEN}${id_str}${RESET}"

            # 节点行：用 echo -e 确保颜色转义
            echo -e "$(printf "${FORMAT_STR}" "$st" "$id_str" "$group" "$name" "$host:$port" "$type")"
            ((display_id++))
        done

        if [[ $found -eq 0 ]]; then
            local empty_msg=""
            if [[ -n "$filter_key" ]]; then
                empty_msg="无匹配 [${filter_key}] 的节点"
            else
                empty_msg="暂无节点，请先添加"
            fi
            echo -e "${YELLOW}$(printf "${FORMAT_STR}" "" "" "${empty_msg}" "" "" "")${RESET}"
        fi

        echo "---------------------------------------------------------------------------"
        if [[ "$mode" == "delete" ]]; then
            echo -e "${RED}[删除模式]${RESET} 输入 ${YELLOW}显示ID${RESET} 执行删除 | ${GREEN}q${RESET} 返回"
        else
            echo -e "操作: ${YELLOW}显示ID${RESET} 连接 | ${BLUE}/关键词${RESET} 搜索 | ${GREEN}q${RESET} 返回主菜单"
        fi

        read -p ">> " input
        [[ "$input" == "q" || "$input" == "Q" ]] && return

        if [[ "$mode" == "delete" ]]; then
            if [[ "$input" =~ ^[0-9]+$ && $input -ge 1 && $input -lt $display_id ]]; then
                local target_node=${display_nodes[$((input - 1))]}
                local original_id
                original_id=$(echo "$target_node" | cut -d'|' -f1)
                perform_delete "$original_id"
                continue
            else
                echo -e "${RED}无效的显示ID，请重新输入${RESET}"
                sleep 1
            fi
        else
            case $input in
            /*)
                filter_key="${input:1}"
                filter_key="${filter_key,,}"
                ;;
            [0-9]*)
                if [[ $input -ge 1 && $input -lt $display_id ]]; then
                    local target_node=${display_nodes[$((input - 1))]}
                    local original_id
                original_id=$(echo "$target_node" | cut -d'|' -f1)
                    ssh_connect "$original_id"
                    local conn_status=$?
                    case $conn_status in
                        0) ;;
                        1) echo -e "${RED}连接超时，按任意键返回...${RESET}" ;;
                        2) echo -e "${RED}认证失败（密码或密钥错误），按任意键返回...${RESET}" ;;
                        3) echo -e "${RED}连接被拒绝（目标主机拒绝连接），按任意键返回...${RESET}" ;;
                        4) echo -e "${RED}主机不可达，按任意键返回...${RESET}" ;;
                        5) echo -e "${RED}主机密钥验证失败，按任意键返回...${RESET}" ;;
                        6) echo -e "${RED}无法解析主机名，按任意键返回...${RESET}" ;;
                        *) echo -e "${RED}连接异常退出 ($conn_status)，按任意键返回...${RESET}" ;;
                    esac
                    if [[ $conn_status -ne 0 ]]; then
                        read -n 1 -s -r
                    fi
                else
                    echo -e "${RED}无效的显示ID，请重新输入${RESET}"
                    sleep 1
                fi
                ;;
            *)
                echo -e "${RED}无效输入，请重新输入${RESET}"
                sleep 1
                ;;
            esac
        fi
    done
}

# --- 6. 删除逻辑 ---
perform_delete() {
    local id=$1
    read_node_info "$CONF" "$id"

    if [[ -z "$NODE_NAME" ]]; then
        echo -e "${RED}无效 ID: $id${RESET}"
        sleep 1
        return 1
    fi

    read -p "确认永久删除节点 [$NODE_NAME] ? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}取消删除操作${RESET}"
        sleep 1
        return 0
    fi

    local tmp_file
    tmp_file=$(mktemp)
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
    mv "$tmp_file" "$CONF"
    chmod 600 "$CONF" 2>/dev/null

    echo -e "${GREEN}节点 [$NODE_NAME] 已成功删除。${RESET}"
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
    echo -e "\n${BLUE}[添加新节点]${RESET}"

    while true; do
        read -p "名称: " n
        n=$(echo "$n" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$n" ]]; then
            break
        fi
        echo -e "${RED}名称不能为空，请重新输入${RESET}"
    done

    read -p "分组 (默认 Default): " g
    g=$(echo "$g" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    g=${g:-Default}

    while true; do
        read -p "主机 (IP/域名): " h
        h=$(echo "$h" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$h" ]]; then
            break
        fi
        echo -e "${RED}主机不能为空，请重新输入${RESET}"
    done

    while true; do
        read -p "端口 (默认 22): " p
        p=$(echo "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        p=${p:-22}
        if [[ "$p" =~ ^[0-9]+$ && "$p" -ge 1 && "$p" -le 65535 ]]; then
            break
        fi
        echo -e "${RED}端口无效（必须是 1-65535 之间的数字），请重新输入${RESET}"
    done

    while true; do
        read -p "用户: " u
        u=$(echo "$u" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -n "$u" ]]; then
            break
        fi
        echo -e "${RED}用户不能为空，请重新输入${RESET}"
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
        echo -e "${RED}无效选择，请输入 1 或 2${RESET}"
    done

    if [[ "$ac" == "2" ]]; then
        t="key"
        while true; do
            read -p "私钥路径: " kp
            kp=$(echo "$kp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -z "$kp" ]]; then
                echo -e "${RED}私钥路径不能为空，请重新输入${RESET}"
                continue
            fi
            if [[ -f "$kp" ]]; then
                break
            fi
            echo -e "${RED}私钥文件不存在，请重新输入${RESET}"
        done
        read -s -p "私钥短语 (可选): " ps
        echo ""
    else
        read -s -p "密码: " ps
        echo ""
    fi

    # shellcheck disable=SC1003  # sed append syntax, not a shell escape
    sed_i -e '$a\' "$CONF" 2>/dev/null

    cat >>"$CONF" <<EOF
  - name: $(sanitize_yaml_value "$n")
    group: $(sanitize_yaml_value "$g")
    host: $(sanitize_yaml_value "$h")
    port: $p
    user: $(sanitize_yaml_value "$u")
    type: $t
    pass: "$ps"
    keypath: "$kp"
EOF

    echo -e "${GREEN}节点 [$n] 已成功添加。${RESET}"
    sleep 1
}

# --- 8. 导入导出功能 ---
export_config() {
    if [[ ! -f "$CONF" ]]; then
        echo -e "${RED}配置文件不存在${RESET}"
        sleep 1
        return 1
    fi

    echo -e "\n--- ${BLUE}配置导出选项${RESET} ---"
    echo "1) ${YELLOW}屏幕输出 Base64${RESET} (适合复制分享)"
    echo "2) ${YELLOW}保存到文件${RESET} (适合备份)"
    echo -e "${GREEN}选择导出方式 (1/2): ${RESET}\c"

    read -n 1 export_choice
    echo # 换行

    case $export_choice in
    1)
        echo -e "\n--- ${BLUE}BASE64 配置导出${RESET} ---"
        echo -e "${YELLOW}注意：此内容包含敏感的密码信息，请妥善保管！${RESET}"
        echo
        base64 -w 0 "$CONF"
        echo -e "\n------------------------"
        read -n 1 -p "按任意键返回..."
        echo
        ;;
    2)
        read -p "请输入导出文件路径 (默认: ./ssh-manager-config.yaml): " export_file
        export_file=${export_file:-"./ssh-manager-config.yaml"}

        if cp "$CONF" "$export_file"; then
            chmod 600 "$export_file" 2>/dev/null
            echo -e "${GREEN}配置已导出到: $export_file${RESET}"
        else
            echo -e "${RED}导出失败${RESET}"
        fi
        sleep 2
        ;;
    *)
        echo -e "${RED}无效选择${RESET}"
        sleep 1
        ;;
    esac
}

import_config() {
    echo -e "\n--- ${BLUE}配置导入选项${RESET} ---"
    echo "1) ${YELLOW}从 Base64 字符串导入${RESET} (从剪贴板)"
    echo "2) ${YELLOW}从文件导入${RESET} (从备份文件)"
    echo -e "${GREEN}选择导入方式 (1/2): ${RESET}\c"

    read -n 1 import_choice
    echo # 换行

    case $import_choice in
    1)
        echo -e "${BLUE}从 Base64 字符串导入${RESET}"
        echo -e "${YELLOW}警告：此操作将覆盖现有配置！${RESET}"
        read -p "是否继续? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "${YELLOW}取消导入操作${RESET}"
            sleep 1
            return 0
        fi

        read -p "粘贴 BASE64 内容: " b64
        if [[ -z "$b64" ]]; then
            echo -e "${RED}输入为空，导入失败${RESET}"
            sleep 1
            return 1
        fi

        b64_clean=$(echo "$b64" | tr -d '[:space:]')

        if ! echo "$b64_clean" | base64 -d >/dev/null 2>&1; then
            echo -e "${RED}无效的 BASE64 格式${RESET}"
            sleep 1
            return 1
        fi

        echo "$b64_clean" | base64 -d >"$CONF"
        chmod 600 "$CONF" 2>/dev/null

        echo -e "${GREEN}配置导入成功${RESET}"
        sleep 1
        return 0
        ;;
    2)
        echo -e "${BLUE}从文件导入${RESET}"
        echo -e "${YELLOW}警告：此操作将覆盖现有配置！${RESET}"
        read -p "是否继续? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo -e "${YELLOW}取消导入操作${RESET}"
            sleep 1
            return 0
        fi

        read -p "请输入配置文件路径: " import_file

        if [[ ! -f "$import_file" ]]; then
            echo -e "${RED}文件不存在: $import_file${RESET}"
            sleep 2
            return 1
        fi

        # Validate that it's a valid YAML file by checking if it has the nodes section
        if ! head -20 "$import_file" | grep -q "nodes:"; then
            echo -e "${RED}验证失败：文件可能不是有效的SSH管理器配置文件${RESET}"
            sleep 2
            return 1
        fi

        # Copy the file to the current config location
        if cp "$import_file" "$CONF"; then
            chmod 600 "$CONF" 2>/dev/null
            echo -e "${GREEN}配置从文件导入成功: $import_file${RESET}"
        else
            echo -e "${RED}导入失败${RESET}"
        fi
        sleep 2
        ;;
    *)
        echo -e "${RED}无效选择${RESET}"
        sleep 1
        ;;
    esac
}

# --- 9. 主循环 ---

VERSION="0.2"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "SSH Manager v${VERSION} - SSH connection management tool"
            echo ""
            echo "Usage: sshm [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --help, -h        Show this help message"
            echo "  --version, -v     Show version information"
            echo "  --config <path>   Use specified config file"
            echo ""
            echo "Environment variables:"
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
                shift 2>/dev/null || true
            else
                echo -e "${RED}Error: --config requires a path argument${RESET}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${RESET}"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

init_env

# 显示帮助信息
show_help() {
    clear
    echo -e "${CYAN}==== SSH MANAGER v0.2 帮助 ====${RESET}"
    echo -e "${GREEN}主菜单快捷键:${RESET}"
    echo "  [Enter]     - 显示节点列表并连接"
    echo "  [/]         - 搜索节点"
    echo "  [a]         - 添加新节点"
    echo "  [d]         - 删除节点"
    echo "  [e]         - 导出配置 (Base64 或 文件)"
    echo "  [i]         - 导入配置 (Base64 或 文件)"
    echo "  [h]         - 显示此帮助"
    echo "  [q]         - 退出程序"
    echo ""
    echo -e "${GREEN}节点列表快捷键:${RESET}"
    echo "  [1-9]       - 连接到对应编号的节点"
    echo "  [/] + 关键词 - 搜索节点"
    echo "  [回车]      - 返回上级菜单"
    echo ""
    echo -e "${YELLOW}提示: 输入 'q' 或 'Ctrl+C' 可随时退出当前操作${RESET}"
    echo ""
    read -n 1 -r -p "按任意键返回主菜单..." _
    echo
}

while true; do
    clear
    echo -e "${CYAN}==== SSH MANAGER v0.2 (Final Stable) ====${RESET}"
    echo -e "${GREEN}请选择操作:${RESET}"
    echo -e "  ${BLUE}[回车]${RESET} 节点列表与连接 ${YELLOW}(List & Connect)${RESET}"
    echo -e "  ${BLUE}[/]${RESET}    快捷搜索节点 ${YELLOW}(Search)${RESET}"
    echo -e "  ${BLUE}[a]${RESET}    添加新节点 ${YELLOW}(Add)${RESET}"
    echo -e "  ${BLUE}[d]${RESET}    删除节点 ${YELLOW}(Delete)${RESET}"
    echo -e "  ${BLUE}[e]${RESET}    导出配置 ${YELLOW}(Export)${RESET}"
    echo -e "  ${BLUE}[i]${RESET}    导入配置 ${YELLOW}(Import)${RESET}"
    echo -e "  ${BLUE}[h]${RESET}    帮助 ${YELLOW}(Help)${RESET}"
    echo -e "  ${BLUE}[q]${RESET}    退出 ${YELLOW}(Quit)${RESET}"
    echo ""
    echo -e "${YELLOW}提示: 直接按回车将进入节点列表${RESET}"

    # 读取单个字符，不需要按回车
    read -n 1 -s choice

    # 添加换行以便输出更清晰
    echo

    case $choice in
    "") list_and_choose ;; # 回车键
    1) list_and_choose ;;  # 数字1 (向后兼容)
    [aA]) add_node ;;
    [dD]) list_and_choose "" "" "delete" ;;
    [eE]) export_config ;;
    [iI]) import_config ;;
    [hH]) show_help ;;
    [qQ])
        echo -e "${YELLOW}退出程序...${RESET}"
        exit 0
        ;;
    [/])
        read -p "关键词: " kw
        list_and_choose "$kw"
        ;;
    *)
        echo -e "${RED}无效选择: '$choice'，请输入 h 查看帮助${RESET}"
        sleep 2
        ;;
    esac
done
