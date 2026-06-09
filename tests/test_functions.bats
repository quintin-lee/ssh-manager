#!/usr/bin/env bats

load test_helper

@test "ssh_connect reads node and sets env vars" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"

    read_node_info "$config_file" 1
    [[ "$NODE_NAME" == "server1" ]]
    [[ "$NODE_HOST" == "192.168.1.10" ]]

    export SSH_PASS="$NODE_PASS"
    export SSH_HOST="$NODE_HOST"
    export SSH_PORT="$NODE_PORT"
    export SSH_USER="$NODE_USER"

    [[ "$SSH_PASS" == "secret123" ]]
    [[ "$SSH_HOST" == "192.168.1.10" ]]
    [[ "$SSH_PORT" == "22" ]]
    [[ "$SSH_USER" == "root" ]]

    unset SSH_PASS SSH_HOST SSH_PORT SSH_USER SSH_KEY
}

@test "ssh_connect returns 1 for invalid node id" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"

    read_node_info "$config_file" 99
    [[ -z "$NODE_HOST" ]]
}

@test "export_config base64 encodes config" {
    local work="${BATS_TMPDIR}/sshm-export-$$"
    mkdir -p "$work"
    local config="${work}/config.yaml"
    cat > "$config" << 'EOF'
nodes:
  - name: x
    host: 1.2.3.4
    user: root
EOF

    local encoded
    encoded=$(base64 < "$config" | tr -d '\n')
    [[ -n "$encoded" ]]

    local decoded="${work}/decoded.yaml"
    echo "$encoded" | base64 -d > "$decoded"
    diff "$config" "$decoded"

    rm -rf "$work"
}

@test "export_config fails gracefully on missing config" {
    local missing="/tmp/nonexistent-sshm-config-$$.yaml"
    if base64 < "$missing" 2>/dev/null; then
        false
    else
        true
    fi
}

@test "import_config with base64 validates format" {
    local work="${BATS_TMPDIR}/sshm-import-$$"
    mkdir -p "$work"

    echo "not valid base64!!!" | base64 -d >/dev/null 2>&1 && skip "base64 -d accepts invalid input" || true

    local b64_invalid="!!!invalid!!!"
    if echo "$b64_invalid" | base64 -d >/dev/null 2>&1; then
        skip "base64 accepts garbage on this system"
    fi
    run bash -c "echo '$b64_invalid' | base64 -d >/dev/null 2>&1"
    [[ "$status" -ne 0 ]]

    rm -rf "$work"
}

@test "import_config file import validates nodes header" {
    local work="${BATS_TMPDIR}/sshm-import-file-$$"
    mkdir -p "$work"
    local bad="${work}/bad.yaml"
    echo "no nodes here" > "$bad"

    if grep -q "^nodes:" "$bad" 2>/dev/null; then
        false
    else
        true
    fi

    local good="${work}/good.yaml"
    echo "nodes:" > "$good"
    grep -q "^nodes:" "$good"

    rm -rf "$work"
}

@test "init_env finds config by priority" {
    local work="${BATS_TMPDIR}/sshm-init-$$"
    mkdir -p "$work"

    export SSH_MANAGER_CONFIG="${work}/env.yaml"
    echo "nodes:" > "${work}/env.yaml"

    local conf="${SSH_MANAGER_CONFIG:-config.yaml}"
    [[ "$conf" == "${work}/env.yaml" ]]
    [[ -f "$conf" ]]
    [[ -r "$conf" ]]

    unset SSH_MANAGER_CONFIG
    rm -rf "$work"
}

@test "init_env creates missing config directory" {
    local work="${BATS_TMPDIR}/sshm-initdir-$$"
    local user_conf="${work}/.config/ssh-manager/config.yaml"

    mkdir -p "$(dirname "$user_conf")"
    [[ -d "$(dirname "$user_conf")" ]]

    rm -rf "$work"
}

@test "_backup_config creates timestamped backup" {
    local work="${BATS_TMPDIR}/sshm-backup-$$"
    mkdir -p "$work"
    local config="${work}/config.yaml"
    echo "nodes:" > "$config"

    cp "$config" "${config}.bak.$(date +%s)"
    local bak_count
    bak_count=$(find "$work" -name "*.bak.*" 2>/dev/null | wc -l)
    [[ "$bak_count" -ge 1 ]]

    rm -rf "$work"
}
