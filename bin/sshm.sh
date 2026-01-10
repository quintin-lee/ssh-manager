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

# --- 1. 环境初始化（优化权限处理）---
init_env() {
    local conf_dir=$(dirname "$CONF")

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
            local user_conf="${HOME}/.config/ssh-manager/config.yaml"

            # Create user config directory if it doesn't exist
            if [[ ! -d "$(dirname "$user_conf")" ]]; then
                mkdir -p "$(dirname "$user_conf")" 2>/dev/null || true
            fi

            # If user config doesn't exist, copy from system default
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
                        echo "nodes:" > /tmp/sshm_temp_config$$
                        cat "$CONF" >> /tmp/sshm_temp_config$$
                        mv /tmp/sshm_temp_config$$ "$CONF" 2>/dev/null || true
                    fi
                fi
            else
                # User has their own config, use that instead
                CONF="$user_conf"
            fi
        else
            # System config doesn't exist, suggest creating user config
            local user_conf="${HOME}/.config/ssh-manager/config.yaml"
            local user_conf_dir="$(dirname "$user_conf")"

            mkdir -p "$user_conf_dir"
            touch "$user_conf"
            chmod 600 "$user_conf"
            CONF="$user_conf"

            echo "nodes:" > "$CONF"
            echo -e "${YELLOW}已创建个人配置文件: $CONF${RESET}"
        fi
    else
        # Non-system config path, use original logic
        if [[ ! -w "$conf_dir" ]]; then
            echo -e "${RED}错误：目录 $conf_dir 不可写${RESET}"
            exit 1
        fi

        if [[ ! -f "$CONF" ]]; then
            # 仅创建空的配置文件结构，不添加示例节点
            echo "nodes:" > "$CONF"
            echo -e "${YELLOW}已创建默认配置文件，请编辑 $CONF 或使用添加功能添加节点${RESET}"
        fi
    fi

    # 优化的权限设置逻辑 - 适配不同目录和用户权限
    # 1. 先检查当前用户是否是文件所有者
    if [[ -f "$CONF" ]]; then
        local file_owner=$(stat -c "%U" "$CONF" 2>/dev/null || stat -f "%Su" "$CONF" 2>/dev/null)
        local current_user=$(whoami)

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

# --- 2. 简化版 YAML 解析（核心修复）---
read_node_info() {
    local id=$1
    unset NODE_NAME NODE_GROUP NODE_HOST NODE_PORT NODE_USER NODE_TYPE NODE_PASS NODE_KEYPATH
    
    local in_node=0
    local current_id=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            ((current_id++))
            in_node=1
            if [[ $current_id -eq $id ]]; then
                NODE_NAME=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')
            else
                in_node=0
            fi
            continue
        fi
        
        if [[ $in_node -eq 1 && $current_id -eq $id ]]; then
            if [[ "$line" =~ ^[[:space:]]*group:[[:space:]]* ]]; then
                NODE_GROUP=$(echo "$line" | sed 's/^[[:space:]]*group:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*host:[[:space:]]* ]]; then
                NODE_HOST=$(echo "$line" | sed 's/^[[:space:]]*host:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*port:[[:space:]]* ]]; then
                NODE_PORT=$(echo "$line" | sed 's/^[[:space:]]*port:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*user:[[:space:]]* ]]; then
                NODE_USER=$(echo "$line" | sed 's/^[[:space:]]*user:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]* ]]; then
                NODE_TYPE=$(echo "$line" | sed 's/^[[:space:]]*type:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*pass:[[:space:]]* ]]; then
                NODE_PASS=$(echo "$line" | sed 's/^[[:space:]]*pass:[[:space:]]*//' | sed 's/^["'\'']//;s/["'\'']$//')
            elif [[ "$line" =~ ^[[:space:]]*keypath:[[:space:]]* ]]; then
                NODE_KEYPATH=$(echo "$line" | sed 's/^[[:space:]]*keypath:[[:space:]]*//' | sed 's/^["'\'']//;s/["'\'']$//')
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                break
            fi
        fi
    done < "$CONF"
    
    NODE_GROUP=${NODE_GROUP:-Default}
    NODE_PORT=${NODE_PORT:-22}
    NODE_TYPE=${NODE_TYPE:-pass}
}

# --- 3. 获取所有节点列表 ---
get_all_nodes() {
    local filter_key="${1,,}"
    local group_filter="$2"
    unset NODES_ARRAY
    NODES_ARRAY=()
    
    local current_id=0
    local node_name=""
    local node_group=""
    local node_host=""
    local node_port=""
    local node_type=""
    local in_node=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            if [[ $in_node -eq 1 && -n "$node_name" ]]; then
                local match=1
                if [[ -n "$filter_key" && ! "${node_name,,}" =~ $filter_key && ! "$node_host" =~ $filter_key ]]; then
                    match=0
                fi
                if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
                    match=0
                fi
                if [[ $match -eq 1 ]]; then
                    NODES_ARRAY+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type")
                fi
            fi
            
            ((current_id++))
            in_node=1
            node_name=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')
            node_group="Default"
            node_host=""
            node_port="22"
            node_type="pass"
            continue
        fi
        
        if [[ $in_node -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]*group:[[:space:]]* ]]; then
                node_group=$(echo "$line" | sed 's/^[[:space:]]*group:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*host:[[:space:]]* ]]; then
                node_host=$(echo "$line" | sed 's/^[[:space:]]*host:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*port:[[:space:]]* ]]; then
                node_port=$(echo "$line" | sed 's/^[[:space:]]*port:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]* ]]; then
                node_type=$(echo "$line" | sed 's/^[[:space:]]*type:[[:space:]]*//')
            fi
        fi
    done < "$CONF"
    
    if [[ $in_node -eq 1 && -n "$node_name" ]]; then
        local match=1
        if [[ -n "$filter_key" && ! "${node_name,,}" =~ $filter_key && ! "$node_host" =~ $filter_key ]]; then
            match=0
        fi
        if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
            match=0
        fi
        if [[ $match -eq 1 ]]; then
            NODES_ARRAY+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type")
        fi
    fi
}

# --- 4. 核心连接逻辑 ---
ssh_connect() {
    local id=$1
    read_node_info "$id"
    
    if [[ -z "$NODE_HOST" ]]; then
        echo -e "${RED}无效 ID: $id (未找到节点)${RESET}"
        sleep 1
        return
    fi

    echo -e "${YELLOW}>>> 连接中: $NODE_NAME ($NODE_HOST)...${RESET}"

    pass_escaped=$(echo "$NODE_PASS" | sed 's/[\\\$\[\]{}()*.+?|^&!#~]/\\&/g')
    kp_escaped=$(echo "$NODE_KEYPATH" | sed 's/[\\\$\[\]{}()*.+?|^&!#~]/\\&/g')

    if [[ "$NODE_TYPE" == "key" ]]; then
        expect -c "
            set timeout 30
            spawn ssh -o StrictHostKeyChecking=no -i \"$kp_escaped\" -p $NODE_PORT $NODE_USER@$NODE_HOST
            expect {
                \"*password:*\" { send \"$pass_escaped\r\" }
                \"*passphrase*\" { send \"$pass_escaped\r\" }
                \"*yes/no*\" { send \"yes\r\"; exp_continue }
                timeout { puts \"连接超时\"; exit 1 }
                eof { exit }
            }
            interact
        "
    else
        expect -c "
            set timeout 30
            spawn ssh -o StrictHostKeyChecking=no -p $NODE_PORT $NODE_USER@$NODE_HOST
            expect {
                \"*password:*\" { send \"$pass_escaped\r\" }
                \"*yes/no*\" { send \"yes\r\"; exp_continue }
                timeout { puts \"连接超时\"; exit 1 }
                eof { exit }
            }
            interact
        "
    fi
}

# --- 5. 列表与交互界面（终极修复版）---
list_and_choose() {
    local filter_key="${1,,}"
    local group_filter="$2"
    local mode="$3"

    while true; do
        get_all_nodes "$filter_key" "$group_filter"

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
            IFS='|' read -r original_id name group host port type <<< "$node"
            display_nodes+=("$original_id|$name|$group|$host|$port|$type")
            found=1
        done

        for node in "${display_nodes[@]}"; do
            IFS='|' read -r original_id name group host port type <<< "$node"
            
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
            local id_str=$(printf "%-4d" $display_id)
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
                local target_node=${display_nodes[$((input-1))]}
                local original_id=$(echo "$target_node" | cut -d'|' -f1)
                perform_delete "$original_id"
                continue
            else
                echo -e "${RED}无效的显示ID，请重新输入${RESET}"
                sleep 1
            fi
        else
            case $input in
                /*) 
                    filter_key="${input:1}"; 
                    filter_key="${filter_key,,}";
                    ;;
                [0-9]*) 
                    if [[ $input -ge 1 && $input -lt $display_id ]]; then
                        local target_node=${display_nodes[$((input-1))]}
                        local original_id=$(echo "$target_node" | cut -d'|' -f1)
                        ssh_connect "$original_id"
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
    read_node_info "$id"

    if [[ -z "$NODE_NAME" ]]; then
        echo -e "${RED}无效 ID: $id${RESET}"; sleep 1; return 1
    fi

    read -p "确认永久删除节点 [$NODE_NAME] ? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}取消删除操作${RESET}"; sleep 1; return 0
    fi

    local tmp_file=$(mktemp)
    local in_node=0
    local current_id=0
    local skip=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            ((current_id++))
            if [[ $current_id -eq $id ]]; then
                skip=1
                in_node=1
                continue
            else
                skip=0
                in_node=0
            fi
        fi

        if [[ $skip -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                skip=0
                in_node=0
                echo "$line" >> "$tmp_file"
            fi
            continue
        fi

        echo "$line" >> "$tmp_file"
    done < "$CONF"

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

    local t="pass"; local kp=""; local ps=""
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
        read -s -p "私钥短语 (可选): " ps; echo ""
    else
        read -s -p "密码: " ps; echo ""
    fi

    sed_i -e '$a\' "$CONF" 2>/dev/null

    cat >> "$CONF" <<EOF
  - name: $n
    group: $g
    host: $h
    port: $p
    user: $u
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
    
    echo -e "\n--- ${BLUE}BASE64 配置导出${RESET} ---"
    echo "注意：此内容包含敏感的密码信息，请妥善保管！"
    echo
    base64 -w 0 "$CONF"
    echo -e "\n------------------------"
    read -n 1 -p "按任意键返回..."
    echo
}

import_config() {
    echo -e "\n--- ${BLUE}BASE64 配置导入${RESET} ---"
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
    
    if ! echo "$b64_clean" | base64 -d > /dev/null 2>&1; then
        echo -e "${RED}无效的 BASE64 格式${RESET}"
        sleep 1
        return 1
    fi
    
    echo "$b64_clean" | base64 -d > "$CONF"
    chmod 600 "$CONF" 2>/dev/null
    
    echo -e "${GREEN}配置导入成功${RESET}"
    sleep 1
    return 0
}

# --- 9. 主循环 ---
init_env
while true; do
    clear
    echo -e "${CYAN}==== SSH MANAGER v0.2 (Final Stable) ====${RESET}"
    echo "1) 节点列表与连接 (List & Connect)"
    echo "2) 快捷搜索节点 (Search)"
    echo "-----------------------------------"
    echo "3) 添加新节点 (Add)"
    echo "4) 删除旧节点 (Delete)"
    echo "5) 导出配置 (Base64)"
    echo "6) 导入配置 (Base64)"
    echo "q) 退出 (Quit)"
    echo "-----------------------------------"
    read -p "选择 >> " choice
    case $choice in
        1) list_and_choose ;;
        2) read -p "关键词: " kw; list_and_choose "$kw" ;;
        3) add_node ;;
        4) list_and_choose "" "" "delete" ;;
        5) export_config ;;
        6) import_config ;;
        q|Q) echo -e "${YELLOW}退出程序...${RESET}"; exit 0 ;;
        *) echo -e "${RED}无效选择，请重新输入${RESET}"; sleep 1 ;;
    esac
done

