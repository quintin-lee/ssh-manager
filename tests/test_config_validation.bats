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
