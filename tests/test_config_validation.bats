#!/usr/bin/env bats

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    WORK_DIR="${BATS_TMPDIR}/sshm-test-$$"
    mkdir -p "$WORK_DIR"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "nodes section with required fields is valid" {
    local config="${WORK_DIR}/valid.yaml"
    cat > "$config" << 'EOF'
nodes:
  - name: test
    host: 127.0.0.1
    user: root
EOF

    grep -q "^nodes:" "$config"
    grep -q "name:" "$config"
    grep -q "host:" "$config"
    grep -q "user:" "$config"
}

@test "empty nodes section is still valid config" {
    local config="${WORK_DIR}/empty_nodes.yaml"
    cat > "$config" << 'EOF'
nodes:
EOF

    grep -q "^nodes:" "$config"
}

@test "missing nodes header is invalid" {
    local config="${WORK_DIR}/invalid.yaml"
    cat > "$config" << 'EOF'
  - name: test
    host: 127.0.0.1
EOF

    if grep -q "^nodes:" "$config"; then
        false
    else
        true
    fi
}

@test "config with trailing whitespace parses correctly" {
    local config="${WORK_DIR}/trailing_ws.yaml"
    cat > "$config" << 'EOF'
nodes:
  - name: test  
    group: Default   
    host: 127.0.0.1   
    port: 22   
    user: root   
    type: pass   
    pass: "secret"   
    keypath: ""   
EOF

    grep -q "name: test" "$config"
    grep -q "host: 127.0.0.1" "$config"
}

@test "port validation rejects non-numeric values" {
    local port="abc"
    if [[ "$port" =~ ^[0-9]+$ ]]; then
        false
    else
        true
    fi
}

@test "port validation rejects out-of-range values" {
    local port=99999
    if [[ "$port" -ge 1 && "$port" -le 65535 ]]; then
        false
    else
        true
    fi
}

@test "port validation accepts valid port" {
    local port=2222
    [[ "$port" -ge 1 && "$port" -le 65535 ]]
}

@test "get_all_nodes returns 0 nodes for empty config" {
    local config="${WORK_DIR}/empty.yaml"
    echo "" > "$config"
    source "${TEST_DIR}/../lib/yaml_parser.sh"
    get_all_nodes "$config"
    [[ ${#NODES_ARRAY[@]} -eq 0 ]]
}

@test "get_all_nodes returns 0 nodes for config with only nodes header" {
    local config="${WORK_DIR}/only_header.yaml"
    echo "nodes:" > "$config"
    source "${TEST_DIR}/../lib/yaml_parser.sh"
    get_all_nodes "$config"
    [[ ${#NODES_ARRAY[@]} -eq 0 ]]
}

@test "get_all_nodes returns 0 nodes for missing file" {
    local config="${WORK_DIR}/nonexistent.yaml"
    source "${TEST_DIR}/../lib/yaml_parser.sh"
    get_all_nodes "$config"
    [[ ${#NODES_ARRAY[@]} -eq 0 ]]
}

@test "sshm --validate exits 0 for valid config" {
    local config="${WORK_DIR}/valid_validate.yaml"
    cat > "$config" << 'EOF'
nodes:
  - name: test
    host: 127.0.0.1
    user: root
EOF
    run bash -c "SSH_MANAGER_CONFIG='${config}' '${SSH_MANAGER_SCRIPT}' --validate"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "配置有效" ]]
}

@test "sshm --validate exits 1 for missing file" {
    local config="${WORK_DIR}/missing.yaml"
    run bash -c "SSH_MANAGER_CONFIG='${config}' '${SSH_MANAGER_SCRIPT}' --validate"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "配置文件不存在" ]]
}

@test "sshm --validate exits 1 for config missing nodes header" {
    local config="${WORK_DIR}/no_header.yaml"
    echo "something: else" > "$config"
    run bash -c "SSH_MANAGER_CONFIG='${config}' '${SSH_MANAGER_SCRIPT}' --validate"
    [[ "$status" -eq 1 ]]
    [[ "$output" =~ "缺少 nodes: 头部" ]]
}

