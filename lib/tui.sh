#!/usr/bin/env bash

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
CYAN=$'\033[36m'
RESET=$'\033[0m'

declare -A _SSHM_THEMES
_SSHM_THEMES[dark]="31 32 33 34 36 深色"
_SSHM_THEMES[light]="91 92 93 94 96 亮色"
_SSHM_THEMES[ocean]="36 34 37 36 34 海洋"
_SSHM_THEMES[sunset]="31 33 35 33 31 日落"
_SSHM_THEMES[forest]="32 36 33 34 32 森林"
_SSHM_THEME_NAMES=(dark light ocean sunset forest)
_SSHM_THEME_IDX=0

_apply_theme() {
    local name="$1"
    IFS=' ' read -r r g y b c _ <<<"${_SSHM_THEMES[$name]}"
    RED=$'\033['"${r}"'m'
    GREEN=$'\033['"${g}"'m'
    YELLOW=$'\033['"${y}"'m'
    BLUE=$'\033['"${b}"'m'
    CYAN=$'\033['"${c}"'m'
}

_choose_theme() {
    local sel=0 orig_r="$RED" orig_g="$GREEN" orig_y="$YELLOW" orig_b="$BLUE" orig_c="$CYAN"
    _apply_theme "${_SSHM_THEME_NAMES[$sel]}"
    while true; do
        printf '\033[H\033[J'
        echo ""
        _echo "  ${CYAN}==== 选择主题 (实时预览) ====${RESET}\n"
        for i in "${!_SSHM_THEME_NAMES[@]}"; do
            local tname="${_SSHM_THEME_NAMES[$i]}"
            local label="${_SSHM_THEMES[$tname]##* }"
            local arrow="  "
            [[ $i -eq $sel ]] && arrow="${BLUE}>${RESET} "
            local r g y b c
            IFS=' ' read -r r g y b c _ <<<"${_SSHM_THEMES[$tname]}"
            local sample="\033[${r}m●\033[${g}m●\033[${y}m●\033[${b}m●\033[${c}m●${RESET}"
            _echo "${arrow}${sample}  ${label}"
        done
        echo ""
        _echo "  ${BLUE}↑↓${RESET}选择(实时预览)  ${BLUE}Enter${RESET}确认  ${BLUE}q${RESET}取消"

        local key
        key=$(_read_key)
        case "$key" in
            UP)    ((sel > 0)) && ((sel--)) && _apply_theme "${_SSHM_THEME_NAMES[$sel]}" ;;
            DOWN)  ((sel < ${#_SSHM_THEME_NAMES[@]} - 1)) && ((sel++)) && _apply_theme "${_SSHM_THEME_NAMES[$sel]}" ;;
            ENTER) return ;;
            q|Q)   RED="$orig_r"; GREEN="$orig_g"; YELLOW="$orig_y"; BLUE="$orig_b"; CYAN="$orig_c"; return ;;
        esac
    done
}

_read_key() {
    local key seq
    IFS= read -r -s -n 1 key
    if [[ "$key" == $'\033' ]]; then
        IFS= read -r -s -n 2 -t 0.1 seq 2>/dev/null
        case "$seq" in
            '[A') echo "UP" ;;
            '[B') echo "DOWN" ;;
            '')   echo "ESC" ;;
            *)    echo "ESC" ;;
        esac
    elif [[ "$key" == "" ]]; then
        echo "ENTER"
    else
        echo "$key"
    fi
}

_render_list() {
    local selected_idx="$1"
    local filter_key="${2,,}"
    local highlight="${3:-0}"
    local term_h term_w visible_h
    term_h=$(tput lines 2>/dev/null || echo 24)
    term_w=$(_term_width)
    visible_h=$((term_h - 4))

    local current_mtime
    current_mtime=$(stat -c %Y "$_SSHM_CONF" 2>/dev/null || stat -f %m "$_SSHM_CONF" 2>/dev/null || echo 0)
    if [[ "$current_mtime" != "${_SSHM_CONF_MTIME:-0}" || "$filter_key" != "${_SSHM_LAST_FILTER:-}" ]]; then
        get_all_nodes "$_SSHM_CONF" "$filter_key" ""
        _SSHM_CONF_MTIME="$current_mtime"
        _SSHM_LAST_FILTER="$filter_key"
        if [[ ${#NODES_ARRAY[@]} -gt 0 ]]; then
            local sorted_output
            local tag_filters=()
            local name_filter="$filter_key"
            for word in $filter_key; do
                [[ "$word" == \#* ]] && tag_filters+=("${word#\#}") && name_filter="${name_filter//$word/}"
            done
            name_filter=$(echo "$name_filter" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ ${#tag_filters[@]} -gt 0 ]]; then
                local filtered=()
                for node in "${NODES_ARRAY[@]}"; do
                    local node_tags
                    node_tags=$(echo "$node" | cut -d'|' -f7)
                    local match=1
                    for tf in "${tag_filters[@]}"; do
                        [[ ",${node_tags}," != *",${tf},"* ]] && match=0 && break
                    done
                    [[ $match -eq 1 ]] && filtered+=("$node")
                done
                NODES_ARRAY=("${filtered[@]}")
            fi
            if [[ ${#NODES_ARRAY[@]} -gt 0 ]]; then
                local sorted_output
                case "${_SSHM_SORT_MODE:-group}" in
                    name)   sorted_output=$(printf "%s\n" "${NODES_ARRAY[@]}" | sort -t'|' -k2,2) ;;
                    status) sorted_output=$(printf "%s\n" "${NODES_ARRAY[@]}") ;;
                    *)      sorted_output=$(printf "%s\n" "${NODES_ARRAY[@]}" | sort -t'|' -k3,3 -k2,2) ;;
                esac
                NODES_ARRAY=()
                while IFS= read -r line; do [[ -n "$line" ]] && NODES_ARRAY+=("$line"); done <<<"$sorted_output"
            fi
        fi
    fi

    local disp_nodes=() found=0
    for node in "${NODES_ARRAY[@]}"; do
        IFS='|' read -r original_id name group host port type tags <<<"$node"
        disp_nodes+=("$original_id|$name|$group|$host|$port|$type|${tags:-}")
        found=1
    done
    _SSHM_RENDERED_NODES=("${disp_nodes[@]}")

    local total=${#disp_nodes[@]}
    if [[ $selected_idx -lt ${_SSHM_SCROLL_OFFSET:-0} ]]; then _SSHM_SCROLL_OFFSET=$selected_idx; fi
    if [[ $total -gt 0 && $selected_idx -ge $((_SSHM_SCROLL_OFFSET + visible_h)) ]]; then _SSHM_SCROLL_OFFSET=$((selected_idx - visible_h + 1)); fi
    [[ ${_SSHM_SCROLL_OFFSET:-0} -lt 0 ]] && _SSHM_SCROLL_OFFSET=0

    local name_w=$(( term_w > 100 ? 24 : 16 ))
    local host_w=$(( term_w > 100 ? 26 : 21 ))
    local FMT="%-6s | %-4s | %-12s | %-${name_w}s | %-${host_w}s | %-5s"

    printf '\033[H\033[J'
    local hdr="SSH Manager v${VERSION}"
    [[ -n "$filter_key" ]] && hdr="${hdr}  过滤: ${filter_key} (ESC清除)"
    local sort_l="组"; case "${_SSHM_SORT_MODE:-group}" in name) sort_l="名" ;; status) sort_l="状态" ;; esac
    _echo "${CYAN}═══ ${hdr}  排序:${sort_l} ═══${RESET}"
    _echo "${CYAN}$(printf "$FMT" "Sel/St" "ID" "Group" "Name" "Host:Port" "Auth")${RESET}"

    local display_id=1 idx=0 row=0
    for node in "${disp_nodes[@]}"; do
        [[ $idx -lt ${_SSHM_SCROLL_OFFSET:-0} ]] && { ((idx++)); ((display_id++)); continue; }
        [[ $row -ge $visible_h ]] && break

        IFS='|' read -r original_id name group host port type tags <<<"$node"
        local alive="●"
        _ping_check "$host" && alive="${GREEN}●${RESET}" || alive="${RED}●${RESET}"
        local st="  ${alive}   "
        if [[ "$highlight" -eq 1 && $idx -eq $selected_idx ]]; then st="${BLUE}>${RESET} ${alive}   "; fi
        if [[ "$highlight" -eq 2 && $idx -eq $selected_idx ]]; then st="${RED}>${RESET} ${alive}   "; fi
        local id_str; id_str=$(printf "%-4d" $display_id); id_str="${GREEN}${id_str}${RESET}"
        local disp_name="$name"
        if [[ -n "$filter_key" ]]; then
            local hl_name="${name//${filter_key}/\\033[7m${filter_key}\\033[0m}"
            [[ "$hl_name" != "$name" ]] && disp_name="$hl_name"
        fi
        local disp_tags="${tags//\"/}"
        disp_tags="${disp_tags//,/ }"
        _echo "$(printf "$FMT" "$st" "$id_str" "$group" "$disp_name" "$host:$port" "$type")${disp_tags:+ ${CYAN}[${disp_tags}]${RESET}}"
        ((display_id++)); ((idx++)); ((row++))
    done

    if [[ $found -eq 0 ]]; then
        local empty_msg="暂无节点，请先添加 (按 a)"
        [[ -n "$filter_key" ]] && empty_msg="无匹配 [${filter_key}]"
        echo ""
        _echo "${YELLOW}  ${empty_msg}${RESET}"
        echo ""
    fi

    if [[ ${_SSHM_SCROLL_OFFSET:-0} -gt 0 ]]; then _echo "${YELLOW}  ▲ 上方还有节点${RESET}"; fi
    if [[ $total -gt $((_SSHM_SCROLL_OFFSET + visible_h)) ]]; then _echo "${YELLOW}  ▼ 下方还有节点 ($((total - _SSHM_SCROLL_OFFSET - visible_h)))${RESET}"; fi

    echo ""
    local mode_hint=""; [[ "$highlight" -eq 2 ]] && mode_hint="${RED}[删除]${RESET} "
    local sel_info=""
    if [[ $total -gt 0 && $selected_idx -lt $total ]]; then
        local sn sh; sn=$(echo "${disp_nodes[$selected_idx]}" | cut -d'|' -f2); sh=$(echo "${disp_nodes[$selected_idx]}" | cut -d'|' -f4)
        sel_info="${BLUE}${sn}${RESET}@${GREEN}${sh}${RESET} "
    fi
    _echo "${CYAN}───${RESET} ${mode_hint}${total}个 ${sel_info}${CYAN}───${RESET}"
    _echo "↑↓选 1-9快连 Enter连 e编 p预览 s排 u撤删 a加 d删 x导出 t主题 q退"
}

_preview_node() {
    local target_node="$1"
    IFS='|' read -r id name group host port type <<<"$target_node"
    printf '\033[H\033[J'
    _echo "\n${CYAN}==== 节点详情 ====${RESET}\n"
    _echo "  名称: ${YELLOW}${name}${RESET}"
    _echo "  分组: ${YELLOW}${group}${RESET}"
    _echo "  主机: ${GREEN}${host}${RESET}"
    _echo "  端口: ${GREEN}${port}${RESET}"
    _echo "  用户: ${GREEN}${type}${RESET}"
    _echo "  认证: ${YELLOW}$([[ "$type" == "key" ]] && echo "密钥" || echo "密码")${RESET}"
    echo ""
    local alive="无法检测"
    _ping_check "$host" && alive="${GREEN}可达${RESET}" || alive="${RED}不可达${RESET}"
    _echo "  状态: ${alive}"
    echo ""
    _echo "  ${BLUE}Enter${RESET}=连接  ${BLUE}e${RESET}=编辑  其他键=返回"
    local key
    key=$(_read_key)
    case "$key" in
        ENTER) ssh_connect "$id"; return 0 ;;
        e|E) _edit_node "$target_node"; return 0 ;;
    esac
}

_interactive_list() {
    local filter_key=""
    local selected_idx=0
    local mode="normal"
    _SSHM_RENDERED_NODES=()
    _SSHM_SORT_MODE="group"
    _SSHM_SCROLL_OFFSET=0

    trap 'filter_key=""; selected_idx=0' SIGINT

    while true; do
        _render_list "$selected_idx" "$filter_key" "$([[ "$mode" == "delete" ]] && echo 2 || echo 1)"

        local key
        key=$(_read_key)

        case "$key" in
        UP)
            ((selected_idx > 0)) && ((selected_idx--))
            ;;
        DOWN)
            local total=${#_SSHM_RENDERED_NODES[@]}
            ((selected_idx < total - 1)) && ((selected_idx++))
            ;;
        ENTER)
            if [[ $selected_idx -ge 0 && $selected_idx -lt ${#_SSHM_RENDERED_NODES[@]} ]]; then
                local target_node="${_SSHM_RENDERED_NODES[$selected_idx]}"
                local original_id
                original_id=$(echo "$target_node" | cut -d'|' -f1)
                if [[ "$mode" == "delete" ]]; then
                    _echo "\n"
                    perform_delete "$original_id"
                    mode="normal"
                    selected_idx=0
                else
                    local conn_name conn_host
                    conn_name=$(echo "$target_node" | cut -d'|' -f2)
                    conn_host=$(echo "$target_node" | cut -d'|' -f4)
                    _record_connection "$conn_name" "$conn_host"
                    printf '\033[H\033[J'
                    _echo "\n\n  ${BLUE}╔══════════════════════════════╗${RESET}"
                    _echo "  ${BLUE}║${RESET}  ${YELLOW}连接中: ${conn_name}${RESET}"
                    _echo "  ${BLUE}║${RESET}  ${GREEN}${conn_host}${RESET}"
                    _echo "  ${BLUE}╚══════════════════════════════╝${RESET}"
                    echo ""
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
            _SSHM_SCROLL_OFFSET=0
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
        s|S)
            case "$_SSHM_SORT_MODE" in
                group)  _SSHM_SORT_MODE="name" ;;
                name)   _SSHM_SORT_MODE="status" ;;
                status) _SSHM_SORT_MODE="group" ;;
            esac
            selected_idx=0
            _SSHM_SCROLL_OFFSET=0
            ;;
        r|R)
            if [[ -f "$_SSHM_HISTORY_FILE" ]]; then
    printf '\033[H\033[J'
                _echo "${CYAN}==== 最近连接 ====${RESET}"
                echo ""
                local i=1
                while IFS='|' read -r name host ts; do
                    local dt
                    dt=$(date -d "@$ts" '+%m-%d %H:%M' 2>/dev/null || date -r "$ts" '+%m-%d %H:%M' 2>/dev/null || echo "---")
                    printf "  %2d. %-16s %-22s %s\n" "$i" "$name" "$host" "$dt"
                    ((i++))
                done < <(_get_recent)
                echo ""
                read -n 1 -r -p "按任意键返回..." _
            else
                _echo "\n${YELLOW}暂无连接历史${RESET}"
                sleep 1
            fi
            ;;
        e|E)
            if [[ $selected_idx -ge 0 && $selected_idx -lt ${#_SSHM_RENDERED_NODES[@]} ]]; then
                _edit_node "${_SSHM_RENDERED_NODES[$selected_idx]}"
            fi
            ;;
        x|X)
            export_config
            ;;
        p|P)
            if [[ $selected_idx -ge 0 && $selected_idx -lt ${#_SSHM_RENDERED_NODES[@]} ]]; then
                _preview_node "${_SSHM_RENDERED_NODES[$selected_idx]}"
            fi
            ;;
        t|T)
            _choose_theme
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
        g)
            selected_idx=0
            ;;
        G)
            local total=${#_SSHM_RENDERED_NODES[@]}
            ((total > 0)) && selected_idx=$((total - 1))
            ;;
        u|U)
            _undo_delete
            ;;
        1|2|3|4|5|6|7|8|9)
            local num_idx=$((key - 1))
            if [[ $num_idx -lt ${#_SSHM_RENDERED_NODES[@]} ]]; then
                local tn ode_id ode_name ode_host
                tn="${_SSHM_RENDERED_NODES[$num_idx]}"
                ode_id=$(echo "$tn" | cut -d'|' -f1)
                ode_name=$(echo "$tn" | cut -d'|' -f2)
                ode_host=$(echo "$tn" | cut -d'|' -f4)
                _record_connection "$ode_name" "$ode_host"
                printf '\033[H\033[J'
                _echo "\n\n  ${BLUE}>>> ${YELLOW}${ode_name}${RESET} @ ${GREEN}${ode_host}${RESET}\n"
                ssh_connect "$ode_id"
                local cs=$?; [[ $cs -ne 0 ]] && sleep 1.5
            fi
            ;;
        $'\177'|$'\010')
            if [[ -n "$filter_key" ]]; then
                filter_key="${filter_key%?}"
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

show_help() {
    echo ""
    _echo "${CYAN}==== SSH MANAGER v${VERSION} 帮助 ====${RESET}"
    echo ""
    _echo "${GREEN}列表导航:${RESET}"
    echo "  ${BLUE}↑↓${RESET}        - 选择节点, 当前行高亮"
    echo "  ${BLUE}Enter${RESET}     - 连接到选中节点"
    echo "  ${BLUE}输入文字${RESET}  - 实时过滤节点列表"
    echo "  ${BLUE}ESC${RESET}       - 清除过滤条件"
    echo "  ${BLUE}退格${RESET}      - 删除最后一个过滤字符"
    echo ""
    _echo "${GREEN}快捷键:${RESET}"
    echo "  ${BLUE}a${RESET} - 添加节点   ${BLUE}d${RESET} - 删除模式   ${BLUE}e${RESET} - 编辑节点"
    echo "  ${BLUE}p${RESET} - 预览详情   ${BLUE}x${RESET} - 导出配置   ${BLUE}i${RESET} - 导入"
    echo "  ${BLUE}t${RESET} - 主题切换   ${BLUE}h${RESET} - 帮助       ${BLUE}q${RESET} - 退出"
    echo ""
    _echo "${GREEN}命令行:${RESET}"
    echo "  sshm prod         - 直接搜索并连接匹配节点"
    echo "  sshm --config <f>  - 使用指定配置文件"
    echo "  sshm --help        - 显示此帮助"
    echo ""
    _echo "${YELLOW}安全提示: 密码以明文存储在 config.yaml 中，请确保文件权限为 600，并推荐使用 SSH 密钥认证。${RESET}"
    echo ""
    read -n 1 -r -p "按任意键返回..." _
    echo
}
