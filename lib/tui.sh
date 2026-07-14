#!/usr/bin/env bash

# Base colors
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
CYAN=$'\033[36m'
WHITE=$'\033[37m'

# Style modifiers
BOLD=$'\033[1m'
DIM=$'\033[2m'
# shellcheck disable=SC2034
UNDERLINE=$'\033[4m'
# shellcheck disable=SC2034
BLINK=$'\033[5m'
# shellcheck disable=SC2034
REVERSE=$'\033[7m'
RESET=$'\033[0m'

declare -A _SSHM_THEMES
# Format: name="fg_red fg_green fg_yellow fg_blue fg_magenta fg_cyan fg_white bold_color label"
_SSHM_THEMES[dark]="31 32 33 94 35 36 37 37 深色"
_SSHM_THEMES[light]="91 92 93 34 95 96 97 97 亮色"
_SSHM_THEMES[ocean]="36 34 37 33 36 34 37 36 海洋"
_SSHM_THEMES[sunset]="31 33 35 33 31 33 37 33 日落"
_SSHM_THEMES[forest]="32 36 33 34 32 36 37 32 森林"
_SSHM_THEMES[monokai]="208 151 228 81 189 117 255 228 Monokai"
_SSHM_THEMES[nord]="94 76 93 80 129 108 218 218 Nord"
_SSHM_THEMES[dracula]="255 121 250 189 255 80 248 255 Dracula"
_SSHM_THEMES[gruvbox]="204 184 180 110 188 143 146 184 Gruvbox"
_SSHM_THEMES[tokyo-night]="73 187 152 122 187 130 219 187 TokyoNight"
_SSHM_THEMES[catppuccin]="243 166 249 111 203 116 230 249 Catppuccin"
_SSHM_THEMES[ayu]="231 185 95 79 127 23 253 231 Ayu"
_SSHM_THEME_NAMES=(dark light ocean sunset forest monokai nord dracula gruvbox tokyo-night catppuccin ayu)
_SSHM_THEME_IDX=0

_apply_theme() {
    local name="$1"
    IFS=' ' read -r r g y b m c w bold _ <<<"${_SSHM_THEMES[$name]}"
    RED=$'\033['"${r}"'m'
    GREEN=$'\033['"${g}"'m'
    YELLOW=$'\033['"${y}"'m'
    BLUE=$'\033['"${b}"'m'
    MAGENTA=$'\033['"${m}"'m'
    CYAN=$'\033['"${c}"'m'
    WHITE=$'\033['"${w}"'m'
    BOLD=$'\033['"${bold}"';1m'
}

_theme_swatch() {
    local name="$1"
    IFS=' ' read -r r g y b m c w bold _ <<<"${_SSHM_THEMES[$name]}"
    printf "  \033[%sm●\033[%sm●\033[%sm●\033[%sm●\033[%sm●\033[%sm●\033[%sm %s %s${RESET}\n" \
        "$r" "$g" "$y" "$b" "$m" "$c" "$w" "$BOLD" "${_}"
}

_theme_preview_line() {
    local name="$1"
    IFS=' ' read -r r g y b m c w bold _ <<<"${_SSHM_THEMES[$name]}"
    local red=$'\033['"${r}"'m'
    local green=$'\033['"${g}"'m'
    local yellow=$'\033['"${y}"'m'
    local blue=$'\033['"${b}"'m'
    local cyan=$'\033['"${c}"'m'
    local white=$'\033['"${w}"'m'
    local bold=$'\033['"${bold}"';1m'
    printf "  ${bold}${cyan}▶${RESET} ${yellow}%s${RESET} ${green}%s${RESET}  ${white}%s${RESET}  ${red}%s${RESET}:${green}%s${RESET} ${blue}%s${RESET} ${cyan}%s${RESET}\n" \
        " 1" "▸" "Default" "web01" "22" "[pass]" "🔒"
}

_sshm_theme_file() {
    local conf_dir
    conf_dir=$(dirname "$_SSHM_CONF")
    echo "${conf_dir}/.theme"
}

_sshm_load_theme() {
    local theme_file
    theme_file=$(_sshm_theme_file)
    if [[ -f "$theme_file" ]]; then
        local saved_theme
        saved_theme=$(cat "$theme_file" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$saved_theme" && -n "${_SSHM_THEMES[$saved_theme]+x}" ]]; then
            _SSHM_THEME_IDX=0
            for i in "${!_SSHM_THEME_NAMES[@]}"; do
                [[ "${_SSHM_THEME_NAMES[$i]}" == "$saved_theme" ]] && _SSHM_THEME_IDX=$i && break
            done
            _apply_theme "$saved_theme"
        fi
    fi
}

_sshm_save_theme() {
    local theme_file
    theme_file=$(_sshm_theme_file)
    local current_name="${_SSHM_THEME_NAMES[$_SSHM_THEME_IDX]}"
    echo "$current_name" > "$theme_file" 2>/dev/null || true
}

_theme_preview_line() {
    local name="$1"
    IFS=' ' read -r r g y b m c w bold _ <<<"${_SSHM_THEMES[$name]}"
    local red=$'\033['"${r}"'m'
    local green=$'\033['"${g}"'m'
    local yellow=$'\033['"${y}"'m'
    local blue=$'\033['"${b}"'m'
    local cyan=$'\033['"${c}"'m'
    local white=$'\033['"${w}"'m'
    local bold=$'\033['"${bold}"';1m'
    printf "  ${bold}${cyan}▶${RESET} ${yellow}%s${RESET} ${green}%s${RESET}  ${white}%s${RESET}  ${red}%s${RESET}:${green}%s${RESET} ${cyan}%s${RESET}\n" \
        " 1" "▸" "Default" "web01" "22" "🔒"
}

_choose_theme() {
    local sel=0
    local orig_r="$RED" orig_g="$GREEN" orig_y="$YELLOW" orig_b="$BLUE" orig_m="$MAGENTA" orig_c="$CYAN" orig_w="$WHITE" orig_bold="$BOLD"
    _apply_theme "${_SSHM_THEME_NAMES[$sel]}"
    while true; do
        printf '\033[H\033[J'
        echo ""
        _echo "  ${BOLD}${CYAN}==== 选择主题 (实时预览) ====${RESET}\n"
        for i in "${!_SSHM_THEME_NAMES[@]}"; do
            local tname="${_SSHM_THEME_NAMES[$i]}"
            local label="${_SSHM_THEMES[$tname]##* }"
            local arrow="  "
            [[ $i -eq $sel ]] && arrow="${BOLD}${BLUE}>${RESET} "
            _echo "${arrow}$(_theme_swatch "$tname") ${label}"
            [[ $i -eq $sel ]] && _echo "      ${DIM}${CYAN}示例:${RESET}$(_theme_preview_line "$tname")"
        done
        echo ""
        _echo "  ${BLUE}↑↓${RESET}选择(实时预览)  ${BLUE}Enter${RESET}确认  ${BLUE}q${RESET}取消"

        local key
        key=$(_read_key)
        case "$key" in
            UP)    ((sel > 0)) && ((sel--)) && _apply_theme "${_SSHM_THEME_NAMES[$sel]}" ;;
            DOWN)  ((sel < ${#_SSHM_THEME_NAMES[@]} - 1)) && ((sel++)) && _apply_theme "${_SSHM_THEME_NAMES[$sel]}" ;;
            ENTER) _sshm_save_theme; return ;;
            q|Q)   RED="$orig_r"; GREEN="$orig_g"; YELLOW="$orig_y"; BLUE="$orig_b"; MAGENTA="$orig_m"; CYAN="$orig_c"; WHITE="$orig_w"; BOLD="$orig_bold"; return ;;
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

_auth_icon() {
    [[ "$1" == "key" ]] && echo "🔑" || echo "🔒"
}

_auth_label() {
    [[ "$1" == "key" ]] && echo "密钥" || echo "密码"
}

_render_list() {
    local selected_idx="$1"
    local filter_key="${2,,}"
    local highlight="${3:-0}"
    local term_h visible_h
    term_h=$(tput lines 2>/dev/null || echo 24)
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

    local disp_nodes=()
    for node in "${NODES_ARRAY[@]}"; do
        IFS='|' read -r original_id name group host port type tags <<<"$node"
        disp_nodes+=("$original_id|$name|$group|$host|$port|$type|${tags:-}")
    done
    _SSHM_RENDERED_NODES=("${disp_nodes[@]}")

    local total=${#disp_nodes[@]}
    if [[ $selected_idx -lt ${_SSHM_SCROLL_OFFSET:-0} ]]; then _SSHM_SCROLL_OFFSET=$selected_idx; fi
    if [[ $total -gt 0 && $selected_idx -ge $((_SSHM_SCROLL_OFFSET + visible_h)) ]]; then _SSHM_SCROLL_OFFSET=$((selected_idx - visible_h + 1)); fi
    [[ ${_SSHM_SCROLL_OFFSET:-0} -lt 0 ]] && _SSHM_SCROLL_OFFSET=0

    printf '\033[H\033[J'
    local hdr="${BOLD}${CYAN}SSH Manager v${VERSION}${RESET}"
    [[ -n "$filter_key" ]] && hdr="${hdr}  ${DIM}${CYAN}过滤: ${filter_key}${RESET} ${DIM}(ESC清除)${RESET}"
    local sort_l="组"; case "${_SSHM_SORT_MODE:-group}" in name) sort_l="名" ;; status) sort_l="状态" ;; esac
    _echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════${RESET}"
    _echo " ${hdr}"
    _echo " ${DIM}${CYAN}排序: ${sort_l} | 主题: ${_SSHM_THEME_NAMES[$((_SSHM_THEME_IDX))]}${RESET}"
    _echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════${RESET}"

    if [[ $total -eq 0 ]]; then
        echo ""
        _echo "  ${YELLOW}${BOLD}  暂无节点${RESET}"
        _echo "  ${DIM}  请按 ${RESET}${BOLD}a${RESET}${DIM} 添加新节点${RESET}"
        [[ -n "$filter_key" ]] && _echo "  ${DIM}  或按 ${RESET}${BOLD}ESC${RESET}${DIM} 清除过滤条件${RESET}"
        echo ""
        _echo "${BOLD}${CYAN}────────────────────────────────────────────────────────────${RESET}"
        _echo " ${DIM}sshm v${VERSION} | 按 ${BOLD}h${RESET}${DIM} 查看帮助 | ${BOLD}q${RESET}${DIM} 退出${RESET}"
        return
    fi

    local display_id=1 idx=0 row=0
    for node in "${disp_nodes[@]}"; do
        [[ $idx -lt ${_SSHM_SCROLL_OFFSET:-0} ]] && { ((idx++)); ((display_id++)); continue; }
        [[ $row -ge $visible_h ]] && break

        IFS='|' read -r original_id name group host port type tags <<<"$node"
        local prefix=" "
        local cursor=" "
        if [[ "$highlight" -eq 1 && $idx -eq $selected_idx ]]; then
            prefix="${BOLD}${BLUE}▶${RESET}"
            cursor="${BOLD}${BLUE}▸${RESET}"
        elif [[ "$highlight" -eq 2 && $idx -eq $selected_idx ]]; then
            prefix="${BOLD}${RED}▶${RESET}"
            cursor="${BOLD}${RED}▸${RESET}"
        fi
        local auth_icon
        auth_icon=$(_auth_icon "$type")
        local id_str
        id_str=$(printf "%2d" $display_id)
        local group_display="$group"
        [[ -z "$group_display" ]] && group_display="Default"
        local name_display="$name"
        if [[ -n "$filter_key" ]]; then
            local hl_name="${name//${filter_key}/\\033[7m${filter_key}\\033[0m}"
            [[ "$hl_name" != "$name" ]] && name_display="$hl_name"
        fi
        local tag_display=""
        [[ -n "${tags:-}" ]] && tag_display=" ${CYAN}#${tags//,/ #}${RESET}"
        _echo " ${prefix} ${YELLOW}${id_str}${RESET} ${cursor} ${DIM}●${RESET} ${group_display}  ${name_display}  ${host}:${port} ${auth_icon}${tag_display}"
        ((display_id++)); ((idx++)); ((row++))
    done

    if [[ ${_SSHM_SCROLL_OFFSET:-0} -gt 0 ]]; then _echo "  ${DIM}${CYAN}▲${RESET}"; fi
    if [[ $total -gt $((_SSHM_SCROLL_OFFSET + visible_h)) ]]; then _echo "  ${DIM}${CYAN}▼ 还有 $((total - _SSHM_SCROLL_OFFSET - visible_h)) 项${RESET}"; fi

    echo ""
    local mode_hint=""
    [[ "$highlight" -eq 2 ]] && mode_hint="${BOLD}${RED}[删除模式]${RESET} "
    local sel_info=""
    if [[ $total -gt 0 && $selected_idx -lt $total ]]; then
        local sn sh; sn=$(echo "${disp_nodes[$selected_idx]}" | cut -d'|' -f2); sh=$(echo "${disp_nodes[$selected_idx]}" | cut -d'|' -f4)
        sel_info="${BOLD}${BLUE}${sn}${RESET}@${GREEN}${sh}${RESET} "
    fi
    _echo " ${mode_hint}${total}个节点 ${sel_info}${DIM}| 1-9直连 Enter连接 e编辑 p预览 s排序 u撤销 d删除 x导出 i导入 t主题 h帮助 q退出${RESET}"
}

_preview_node() {
    local target_node="$1"
    IFS='|' read -r id name group host port type tags <<<"$target_node"
    printf '\033[H\033[J'
    echo ""
    _echo "  ${BOLD}${CYAN}节点详情${RESET}"
    _echo "  ${DIM}${CYAN}────────────────────────────────────────────────────────────${RESET}"
    _echo ""
    _echo "  ${BOLD}名称:${RESET}  ${YELLOW}${name}${RESET}"
    _echo "  ${BOLD}分组:${RESET}  ${group:-Default}"
    _echo "  ${BOLD}主机:${RESET}  ${GREEN}${host}${RESET}"
    _echo "  ${BOLD}端口:${RESET}  ${GREEN}${port}${RESET}"
    _echo "  ${BOLD}用户:${RESET}  ${name}"
    _echo "  ${BOLD}认证:${RESET}  $(_auth_label "$type") $(_auth_icon "$type")"
    [[ -n "${tags:-}" ]] && _echo "  ${BOLD}标签:${RESET}  ${CYAN}#${tags//,/ #}${RESET}"
    echo ""
    local alive="无法检测"
    _ping_check "$host" && alive="${GREEN}可达${RESET}" || alive="${RED}不可达${RESET}"
    _echo "  ${BOLD}状态:${RESET}  ${alive}"
    echo ""
    _echo "  ${DIM}${BLUE}Enter${RESET} 连接   ${BLUE}e${RESET} 编辑   ${DIM}其他键返回${RESET}"
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
                    _echo "\n  ${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
                    _echo "  ${BLUE}║${RESET}  ${YELLOW}${BOLD}连接中:${RESET} ${conn_name}"
                    _echo "  ${BLUE}║${RESET}  ${GREEN}${conn_host}${RESET}"
                    _echo "  ${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
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
                _echo "  ${BOLD}${CYAN}最近连接${RESET}"
                _echo "  ${DIM}${CYAN}────────────────────────────────────────────────────────────${RESET}"
                echo ""
                local i=1
                while IFS='|' read -r name host ts; do
                    local dt
                    dt=$(date -d "@$ts" '+%m-%d %H:%M' 2>/dev/null || date -r "$ts" '+%m-%d %H:%M' 2>/dev/null || echo "---")
                    printf "  ${YELLOW}%2d.${RESET} %-16s %-22s %s\n" "$i" "$name" "$host" "$dt"
                    ((i++))
                done < <(_get_recent)
                echo ""
                _echo "  ${DIM}按任意键返回...${RESET}"
                read -n 1 -r -p "" _
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
                _echo "\n  ${BLUE}>>> ${YELLOW}${ode_name}${RESET} @ ${GREEN}${ode_host}${RESET}\n"
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
    printf '\033[H\033[J'
    echo ""
    _echo "  ${BOLD}${CYAN}SSH Manager v${VERSION} 帮助${RESET}"
    _echo "  ${DIM}${CYAN}────────────────────────────────────────────────────────────${RESET}"
    echo ""
    _echo "  ${BOLD}${GREEN}列表导航${RESET}"
    _echo "    ${BLUE}↑ ↓${RESET}        选择节点，当前行高亮"
    _echo "    ${BLUE}Enter${RESET}     连接到选中节点"
    _echo "    ${BLUE}输入文字${RESET}   实时过滤节点列表"
    _echo "    ${BLUE}ESC${RESET}       清除过滤条件"
    _echo "    ${BLUE}退格${RESET}      删除最后一个过滤字符"
    echo ""
    _echo "  ${BOLD}${GREEN}快捷键${RESET}"
    _echo "    ${BLUE}a${RESET}   添加节点     ${BLUE}d${RESET}   删除模式     ${BLUE}e${RESET}   编辑节点"
    _echo "    ${BLUE}p${RESET}   预览详情     ${BLUE}x${RESET}   导出配置     ${BLUE}i${RESET}   导入"
    _echo "    ${BLUE}t${RESET}   主题切换     ${BLUE}h${RESET}   帮助         ${BLUE}q${RESET}   退出"
    echo ""
    _echo "  ${BOLD}${GREEN}命令行${RESET}"
    _echo "    sshm <keyword>       直接搜索并连接匹配节点"
    _echo "    sshm --config <f>    使用指定配置文件"
    _echo "    sshm --list          列出所有节点"
    _echo "    sshm --list --format json   JSON 格式输出"
    _echo "    sshm --validate      校验配置文件"
    _echo "    sshm --help          显示帮助"
    echo ""
    _echo "  ${BOLD}${GREEN}环境变量${RESET}"
    echo "    ${BLUE}SSH_MANAGER_CONFIG${RESET}   配置文件路径"
    echo ""
    _echo "  ${YELLOW}${BOLD}安全提示${RESET}"
    _echo "    ${DIM}密码以明文存储在 config.yaml 中，请确保文件权限为 600，${RESET}"
    _echo "    ${DIM}并推荐使用 SSH 密钥认证。${RESET}"
    echo ""
    _echo "  ${DIM}按任意键返回...${RESET}"
    read -n 1 -r -p "" _
    echo
}
