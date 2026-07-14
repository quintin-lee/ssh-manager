#!/usr/bin/env bash

_SSHM_CONF="${SSH_MANAGER_CONFIG:-config.yaml}"

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
VERSION=$(cat "${SCRIPT_DIR}/../VERSION" 2>/dev/null || cat "/usr/local/share/ssh-manager/VERSION" 2>/dev/null || cat "/usr/share/ssh-manager/VERSION" 2>/dev/null || true)
if [[ -z "$VERSION" ]]; then
    _die "Error: VERSION file not found. Checked: ${SCRIPT_DIR}/../VERSION, /usr/local/share/ssh-manager/VERSION, /usr/share/ssh-manager/VERSION"
fi

_backup_config() {
    if [[ -f "$_SSHM_CONF" ]]; then
        cp "$_SSHM_CONF" "${_SSHM_CONF}.bak.$(date +%s)" 2>/dev/null || true
    fi
}

_resolve_config() {
    local user_conf="${HOME}/.config/ssh-manager/config.yaml"
    local user_conf_dir
    user_conf_dir="$(dirname "$user_conf")"

    if [[ ! -d "$user_conf_dir" ]]; then
        mkdir -p "$user_conf_dir" 2>/dev/null || true
    fi

    if [[ -f "$user_conf" ]] && [[ -z "${SSH_MANAGER_CONFIG:-}" ]]; then
        _SSHM_CONF="$user_conf"
    fi

    local conf_dir
    conf_dir=$(dirname "$_SSHM_CONF")

    if [[ "$_SSHM_CONF" == /etc/* ]]; then
        if [[ -f "$_SSHM_CONF" ]]; then
            if [[ ! -r "$_SSHM_CONF" ]]; then
                _die "错误：系统配置文件 $_SSHM_CONF 不可读"
            fi
            if [[ ! -f "$user_conf" ]]; then
                if cp "$_SSHM_CONF" "$user_conf" 2>/dev/null; then
                    chmod 600 "$user_conf" 2>/dev/null || true
                    _echo "${GREEN}已复制系统配置到个人目录: $user_conf${RESET}"
                    _SSHM_CONF="$user_conf"
                else
                    _echo "${YELLOW}使用只读的系统配置文件（无法保存更改）${RESET}"
                    if ! grep -q "^nodes:" "$_SSHM_CONF" 2>/dev/null; then
                        _die "错误：系统配置文件缺少 nodes: 头部，请检查配置"
                    fi
                fi
            else
                _SSHM_CONF="$user_conf"
            fi
        else
            mkdir -p "$user_conf_dir"
            touch "$user_conf"
            chmod 600 "$user_conf"
            _SSHM_CONF="$user_conf"
            echo "nodes:" >"$_SSHM_CONF"
            _echo "${YELLOW}已创建个人配置文件: $_SSHM_CONF${RESET}"
        fi
    else
        if [[ ! -w "$conf_dir" ]]; then
            if [[ -w "$user_conf_dir" ]]; then
                _SSHM_CONF="$user_conf"
            else
                _die "错误：目录 $conf_dir 不可写"
            fi
        fi

        if [[ ! -f "$_SSHM_CONF" ]]; then
            echo "nodes:" >"$_SSHM_CONF"
            _echo "${YELLOW}已创建默认配置文件: $_SSHM_CONF${RESET}"
        elif [[ ! -r "$_SSHM_CONF" ]]; then
            _die "错误：配置文件 $_SSHM_CONF 不可读"
        fi
    fi
}

_setup_config_permissions() {
    if [[ ! -f "$_SSHM_CONF" ]]; then
        return
    fi

    local file_owner
    file_owner=$(stat -c "%U" "$_SSHM_CONF" 2>/dev/null || stat -f "%Su" "$_SSHM_CONF" 2>/dev/null)
    local current_user
    current_user=$(whoami)

    if [[ "$_SSHM_CONF" == /etc/* ]]; then
        if [[ "$current_user" != "root" ]]; then
            _echo "${YELLOW}提示：配置文件位于 /etc 目录，普通用户无法设置 600 权限，请以 root 身份运行或忽略此提示${RESET}"
        else
            if chmod 600 "$_SSHM_CONF"; then
                _echo "${GREEN}已将 /etc 目录下的配置文件权限设置为 600${RESET}"
            else
                _echo "${RED}错误：root 用户也无法设置 /etc 目录下配置文件的权限为 600${RESET}"
            fi
        fi
    else
        if [[ "$file_owner" == "$current_user" ]]; then
            if ! chmod 600 "$_SSHM_CONF"; then
                _echo "${YELLOW}警告：无法设置配置文件权限为 600${RESET}"
            fi
        else
            _echo "${YELLOW}提示：配置文件 $_SSHM_CONF 不属于当前用户 $current_user，无法设置 600 权限${RESET}"
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
