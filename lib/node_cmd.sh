#!/usr/bin/env bash
# ============================================================================
# node_cmd.sh — Node CRUD operations
#
# Provides interactive functions to add, edit, delete, and clone SSH nodes
# through the TUI form interface.
#
# Key functions:
#   _add_node          — fill form → append to config
#   _edit_node         — fill form → update node in config
#   _delete_node       — confirm → remove from config
#   _clone_node        — duplicate a node
#   sanitize_yaml_value — escape YAML special chars in value
#
# All mutations create a backup (config.yaml.bak.<timestamp>) first.
# ============================================================================

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

_edit_node() {
    local target_node="$1"
    IFS='|' read -r id name group host port type <<<"$target_node"
    read_node_info "$_SSHM_CONF" "$id"

    local n="${NODE_NAME:-$name}" g="${NODE_GROUP:-$group}" h="${NODE_HOST:-$host}"
    local p="${NODE_PORT:-$port}" u="${NODE_USER:-$name}" t="${NODE_TYPE:-$type}"
    local kp="${NODE_KEYPATH:-}" ps="${NODE_PASS:-}" tags="${NODE_TAGS:-}"

    while true; do
        local aclabel="密码"; [[ "$t" == "key" ]] && aclabel="密钥"
        local pass_display=""; [[ -n "$ps" ]] && pass_display="****" || pass_display="(未设置)"
        printf '\033[H\033[J'
        _echo "\n${BLUE}[编辑节点: ${YELLOW}${n}${BLUE}]${RESET}\n"
        _echo "  ${GREEN}[1]${RESET} 名称: ${YELLOW}${n}${RESET}"
        _echo "  ${GREEN}[2]${RESET} 分组: ${YELLOW}${g}${RESET}"
        _echo "  ${GREEN}[3]${RESET} 主机: ${YELLOW}${h}${RESET}"
        _echo "  ${GREEN}[4]${RESET} 端口: ${YELLOW}${p}${RESET}"
        _echo "  ${GREEN}[5]${RESET} 用户: ${YELLOW}${u}${RESET}"
        _echo "  ${GREEN}[6]${RESET} 认证: ${YELLOW}${aclabel}${RESET}"
        if [[ "$t" == "key" ]]; then
            _echo "  ${GREEN}[7]${RESET} 私钥: ${YELLOW}${kp:-(必填)}${RESET}"
            _echo "  ${GREEN}[8]${RESET} 短语: ${YELLOW}${pass_display}${RESET}"
            _echo "  ${GREEN}[9]${RESET} 标签: ${YELLOW}${tags:-(无)}${RESET}"
            local tag_max=9
        else
            _echo "  ${GREEN}[7]${RESET} 密码: ${YELLOW}${pass_display}${RESET}"
            _echo "  ${GREEN}[8]${RESET} 标签: ${YELLOW}${tags:-(无)}${RESET}"
            local tag_max=8
        fi
        echo ""
        _echo "  ${GREEN}Enter${RESET}=保存  ${BLUE}1-${tag_max}${RESET}=编辑  ${RED}q${RESET}=取消"

        local key
        key=$(_read_key)
        case "$key" in
        ENTER)
            [[ -z "$n" || -z "$h" ]] && { _echo "\n${RED}名称和主机必填${RESET}"; sleep 1; continue; }
            [[ "$t" == "key" && -z "$kp" ]] && { _echo "\n${RED}私钥必填${RESET}"; sleep 1; continue; }
            break ;;
        q|Q) _echo "\n${YELLOW}取消编辑${RESET}"; sleep 1; return ;;
        1) read -r -p "名称: " v; v=$(echo "$v"|sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); [[ -n "$v" ]] && n="$v" ;;
        2) read -r -p "分组: " v; v=$(echo "$v"|sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); [[ -n "$v" ]] && g="$v" || g="Default" ;;
        3) while true; do read -r -p "主机: " v; v=$(echo "$v"|sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); [[ -z "$v" ]] && { _echo "${RED}主机必填${RESET}"; continue; }; [[ "$v" =~ [[:space:]\;\|\&\$\`\(\)\{\}\<\>\"\'] ]] && { _echo "${RED}非法字符${RESET}"; continue; }; h="$v"; break; done ;;
        4) read -r -p "端口 (${p}): " v; v=$(echo "$v"|sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); [[ -n "$v" && "$v" =~ ^[0-9]+$ && "$v" -ge 1 && "$v" -le 65535 ]] && p="$v" ;;
        5) while true; do read -r -p "用户 (${u}): " v; v=$(echo "$v"|sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); [[ -z "$v" ]] && break; [[ "$v" =~ [[:space:]\;\|\&\$\`\(\)\{\}\<\>\"\'] ]] && { _echo "${RED}非法字符${RESET}"; continue; }; u="$v"; break; done ;;
        6) read -r -p "认证 (1:密码 2:密钥): " v; [[ "$v" == "1" ]] && t="pass"; [[ "$v" == "2" ]] && t="key" ;;
        7) if [[ "$t" == "key" ]]; then
                while true; do read -r -p "私钥: " v; v=$(echo "$v"|sed 's/^[[:space:]]*//;s/[[:space:]]*$//'); [[ -z "$v" ]] && break; [[ -f "$v" ]] && { kp="$v"; break; }; _echo "${RED}文件不存在${RESET}"; done
           else read -s -r -p "密码: " v; echo ""; [[ -n "$v" ]] && ps="$v"; fi ;;
        8) if [[ "$t" == "key" ]]; then
                read -s -r -p "短语: " v; echo ""; [[ -n "$v" ]] && ps="$v"
            else
                read -r -p "标签(逗号分隔): " v; tags=$(echo "$v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            fi ;;
        9) read -r -p "标签(逗号分隔): " v; tags=$(echo "$v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') ;;
        esac
    done

    _backup_config
    local tmp_file
    tmp_file=$(_yaml_delete_node "$_SSHM_CONF" "$id") || return 1
    _yaml_append_node "$tmp_file" "$n" "$g" "$h" "$p" "$u" "$t" "$ps" "$kp" "$tags"
    if mv "$tmp_file" "$_SSHM_CONF"; then
        _echo "${GREEN}节点已更新: $n${RESET}"; sleep 1
    else
        _echo "${RED}保存失败${RESET}"; sleep 1; rm -f "$tmp_file"
    fi
}

_undo_delete() {
    if [[ -z "${_SSHM_DELETED_YAML:-}" ]]; then
        _echo "\n${YELLOW}没有可恢复的节点${RESET}"; sleep 1; return
    fi
    _backup_config
    if cat >>"$_SSHM_CONF" <<EOF
${_SSHM_DELETED_YAML}
EOF
    then
        local name
        name=$(echo "$_SSHM_DELETED_YAML" | grep 'name:' | sed 's/.*name: *//')
        _echo "${GREEN}已恢复节点: ${name}${RESET}"
        unset _SSHM_DELETED_YAML
    else
        _echo "${RED}恢复失败${RESET}"
    fi
    sleep 1
}

perform_delete() {
    local id=$1
    [[ "$id" =~ ^[0-9]+$ ]] || { _echo "${RED}无效 ID: $id${RESET}"; sleep 1; return 1; }
    read_node_info "$_SSHM_CONF" "$id"

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

    _SSHM_DELETED_YAML="  - name: $(sanitize_yaml_value "$NODE_NAME")
    group: $(sanitize_yaml_value "$NODE_GROUP")
    host: $(sanitize_yaml_value "$NODE_HOST")
    port: $NODE_PORT
    user: $(sanitize_yaml_value "$NODE_USER")
    type: $NODE_TYPE
    pass: $(sanitize_yaml_value "$NODE_PASS")
    keypath: $(sanitize_yaml_value "$NODE_KEYPATH")
    tags: ${NODE_TAGS:-}"

    _backup_config
    local tmp_file
    tmp_file=$(_yaml_delete_node "$_SSHM_CONF" "$id") || return 1
    if mv "$tmp_file" "$_SSHM_CONF"; then
        chmod 600 "$_SSHM_CONF" 2>/dev/null
        _echo "${GREEN}节点 [$NODE_NAME] 已成功删除。${RESET}"
    else
        _echo "${RED}错误：写入配置文件失败，备份已保存至 ${_SSHM_CONF}.bak.*${RESET}"
        return 1
    fi
    sleep 1
    return 0
}

add_node() {
    local n="" g="Default" h="" p="22" u="root" t="pass" kp="" ps="" tags=""

    while true; do
        case "$t" in key) aclabel="密钥" ;; *) aclabel="密码" ;; esac
        local pass_display=""
        [[ -n "$ps" ]] && pass_display="****" || pass_display="(未设置)"

        printf '\033[H\033[J'
        _echo "\n${BLUE}[添加新节点]${RESET}\n"
        _echo "  ${GREEN}[1]${RESET} 名称: ${YELLOW}${n:-(未设置)}${RESET}"
        _echo "  ${GREEN}[2]${RESET} 分组: ${YELLOW}${g}${RESET}"
        _echo "  ${GREEN}[3]${RESET} 主机: ${YELLOW}${h:-(必填)}${RESET}"
        _echo "  ${GREEN}[4]${RESET} 端口: ${YELLOW}${p}${RESET}"
        _echo "  ${GREEN}[5]${RESET} 用户: ${YELLOW}${u}${RESET}"
        _echo "  ${GREEN}[6]${RESET} 认证: ${YELLOW}${aclabel}${RESET}"
        if [[ "$t" == "key" ]]; then
            _echo "  ${GREEN}[7]${RESET} 私钥: ${YELLOW}${kp:-(必填)}${RESET}"
            _echo "  ${GREEN}[8]${RESET} 短语: ${YELLOW}${pass_display}${RESET}"
        else
            _echo "  ${GREEN}[7]${RESET} 密码: ${YELLOW}${pass_display}${RESET}"
        fi
        local tag_max=8; [[ "$t" == "key" ]] && tag_max=9
        _echo "  ${GREEN}[${tag_max}]${RESET} 标签: ${YELLOW}${tags:-(无)}${RESET}"
        echo ""
        if [[ -n "$n" && -n "$h" && ( "$t" != "key" || -n "$kp" ) ]]; then
            _echo "  ${GREEN}Enter${RESET}=保存  ${BLUE}1-${tag_max}${RESET}=编辑  ${RED}q${RESET}=取消"
        else
            _echo "  ${BLUE}1-${tag_max}${RESET}=编辑  ${RED}q${RESET}=取消"
        fi

        local key
        key=$(_read_key)

        case "$key" in
        ENTER)
            if [[ -n "$n" && -n "$h" ]]; then
                if [[ "$t" == "key" && -z "$kp" ]]; then
                    _echo "\n${RED}私钥路径不能为空${RESET}"; sleep 1; continue
                fi
                break
            fi
            _echo "\n${RED}名称和主机为必填项${RESET}"; sleep 1
            ;;
        q|Q) _echo "\n${YELLOW}取消添加${RESET}"; sleep 1; return ;;
        1)  read -r -p "名称: " n_val
            n_val=$(echo "$n_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [[ -n "$n_val" ]] && n="$n_val" ;;
        2)  read -r -p "分组: " g_val
            g_val=$(echo "$g_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [[ -n "$g_val" ]] && g="$g_val" || g="Default" ;;
        3)  while true; do
                read -r -p "主机: " h_val
                h_val=$(echo "$h_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [[ -z "$h_val" ]]; then _echo "${RED}主机不能为空${RESET}"; continue; fi
                if [[ "$h_val" =~ [[:space:]\;\|\&\$\`\(\)\{\}\<\>\"\'] ]]; then
                    _echo "${RED}主机包含非法字符${RESET}"; continue
                fi
                h="$h_val"; break
            done ;;
        4)  while true; do
                read -r -p "端口 (${p}): " p_val
                p_val=$(echo "$p_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [[ -z "$p_val" ]] && break
                if [[ "$p_val" =~ ^[0-9]+$ && "$p_val" -ge 1 && "$p_val" -le 65535 ]]; then
                    p="$p_val"; break
                fi
                _echo "${RED}端口无效 (1-65535)${RESET}"
            done ;;
        5)  while true; do
                read -r -p "用户 (${u}): " u_val
                u_val=$(echo "$u_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [[ -z "$u_val" ]]; then break; fi
                if [[ "$u_val" =~ [[:space:]\;\|\&\$\`\(\)\{\}\<\>\"\'] ]]; then
                    _echo "${RED}用户名包含非法字符${RESET}"; continue
                fi
                u="$u_val"; break
            done ;;
        6)  while true; do
                read -r -p "认证 (1:密码 2:密钥) [${t}]: " ac
                ac=$(echo "$ac" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [[ -z "$ac" ]]; then break; fi
                if [[ "$ac" == "1" ]]; then t="pass"; break
                elif [[ "$ac" == "2" ]]; then t="key"; break; fi
                _echo "${RED}请输入 1 或 2${RESET}"
            done ;;
        7)  if [[ "$t" == "key" ]]; then
                while true; do
                    read -r -p "私钥路径: " kp_val
                    kp_val=$(echo "$kp_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    if [[ -z "$kp_val" ]]; then break; fi
                    if [[ -f "$kp_val" ]]; then
                        if grep -q "PRIVATE KEY" "$kp_val" 2>/dev/null || ssh-keygen -l -f "$kp_val" &>/dev/null; then
                            kp="$kp_val"; break
                        fi
                        _echo "${RED}不是有效的SSH私钥${RESET}"; continue
                    fi
                    _echo "${RED}文件不存在${RESET}"
                done
            else
                read -s -r -p "密码: " ps_val
                echo ""
                [[ -n "$ps_val" ]] && ps="$ps_val"
            fi ;;
        8)  if [[ "$t" == "key" ]]; then
                read -s -r -p "短语: " ps_val
                echo ""
                [[ -n "$ps_val" ]] && ps="$ps_val"
            else
                read -r -p "标签(逗号分隔): " t_val
                tags=$(echo "$t_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            fi ;;
        9)  read -r -p "标签(逗号分隔): " t_val
            tags=$(echo "$t_val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') ;;
        esac
    done

    _backup_config
    _yaml_append_node "$_SSHM_CONF" "$n" "$g" "$h" "$p" "$u" "$t" "$ps" "$kp" "$tags"
    _echo "${GREEN}节点 [$n] 已成功添加。 (${h}:${p} ${u}@${t})${RESET}"
    sleep 1
}

export_config() {
    if [[ ! -f "$_SSHM_CONF" ]]; then
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
        if ! base64 < "$_SSHM_CONF" | tr -d '\n'; then
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

        if cp "$_SSHM_CONF" "$export_file"; then
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
        if echo "$b64_clean" | base64 -d >"$_SSHM_CONF"; then
            chmod 600 "$_SSHM_CONF" 2>/dev/null
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
        if cp "$import_file" "$_SSHM_CONF"; then
            chmod 600 "$_SSHM_CONF" 2>/dev/null
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
