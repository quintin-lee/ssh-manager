#!/usr/bin/env bash
# ============================================================================
# ssh.sh — SSH connection and credential handling
#
# Resolves credentials (password from plaintext or env var), builds SSH
# command line, and delegates to expect-based auto-login via ssh_connect.tcl.
#
# Key functions:
#   _sshm_resolve_pass   — resolve password literal / (env:VAR) / ${VAR}
#   _ssh_connect         — run expect to automate SSH login
#   _ssh_login           — connect to already-selected node entry
#
# Auth types: pass (password), key (SSH key), env (env var reference)
# ============================================================================

_sshm_resolve_pass() {
    local val="$1"
    if [[ "$val" =~ ^\(env:([A-Za-z_][A-Za-z0-9_]*)\)$ ]]; then
        echo "${!BASH_REMATCH[1]}"
    elif [[ "$val" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
        echo "${!BASH_REMATCH[1]}"
    else
        echo "$val"
    fi
}

ssh_connect() {
    local id=$1
    read_node_info "$_SSHM_CONF" "$id"

    if [[ -z "$NODE_HOST" ]]; then
        _echo "${RED}无效 ID: $id (未找到节点)${RESET}"
        sleep 1
        return 1
    fi

    _echo "${YELLOW}>>> 连接中: $NODE_NAME ($NODE_HOST)...${RESET}"

    local resolved_pass
    resolved_pass=$(_sshm_resolve_pass "$NODE_PASS")
    export SSH_PASS="$resolved_pass"
    export SSH_KEY="$NODE_KEYPATH"
    export SSH_HOST="$NODE_HOST"
    export SSH_PORT="$NODE_PORT"
    export SSH_USER="$NODE_USER"

    local ssh_extra=""
    local passphrase_branch=""
    if [[ "$NODE_TYPE" == "key" ]]; then
        ssh_extra="-i $NODE_KEYPATH"
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
    local tcl_template tcl_path
    if [[ -f "${SCRIPT_DIR}/../lib/ssh_connect.tcl" ]]; then
        tcl_path="${SCRIPT_DIR}/../lib/ssh_connect.tcl"
    elif [[ -f "/usr/local/lib/ssh_connect.tcl" ]]; then
        tcl_path="/usr/local/lib/ssh_connect.tcl"
    elif [[ -f "/usr/share/ssh-manager/ssh_connect.tcl" ]]; then
        tcl_path="/usr/share/ssh-manager/ssh_connect.tcl"
    elif [[ -f "/usr/local/share/ssh-manager/ssh_connect.tcl" ]]; then
        tcl_path="/usr/local/share/ssh-manager/ssh_connect.tcl"
    else
        _die "Error: ssh_connect.tcl not found. Please reinstall ssh-manager."
    fi
    tcl_template="$(cat "$tcl_path")"
    tcl_template="${tcl_template//__SSH_EXTRA__/${ssh_extra}}"
    tcl_template="${tcl_template//__PASSPHRASE_BRANCH__/${passphrase_branch}}"

    expect -c "$tcl_template"
    exit_code=$?

    unset SSH_PASS SSH_KEY SSH_HOST SSH_PORT SSH_USER
    return $exit_code
}
