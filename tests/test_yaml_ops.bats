#!/usr/bin/env bats

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    WORK_DIR="${BATS_TMPDIR}/sshm-yaml-ops-$$"
    mkdir -p "$WORK_DIR"
    source "${TEST_DIR}/../lib/yaml_parser.sh"
    source "${TEST_DIR}/../lib/yaml_ops.sh"
    source "${TEST_DIR}/../bin/sshm.sh"
}

teardown() {
    rm -rf "$WORK_DIR"
}

_yaml_ops_test_config() {
    cat > "$1" << 'EOF'
nodes:
  - name: keep1
    group: Default
    host: 10.0.0.1
    port: 22
    user: root
    type: pass
    pass: ""
    keypath: ""
  - name: delete-me
    group: Staging
    host: 10.0.0.2
    port: 22
    user: admin
    type: key
    pass: ""
    keypath: "/tmp/key"
  - name: keep2
    group: Production
    host: 10.0.0.3
    port: 22
    user: deploy
    type: pass
    pass: "secret"
    keypath: ""
EOF
}

@test "_yaml_node_block generates valid YAML node" {
    local block
    block=$(_yaml_node_block "myhost" "Default" "10.0.0.1" "22" "root" "pass" "secret" "" "")
    echo "$block" | grep -q "^- name: myhost"
    echo "$block" | grep -q "host: 10.0.0.1"
    echo "$block" | grep -q "port: 22"
    echo "$block" | grep -q "type: pass"
}

@test "_yaml_node_block quotes values with special characters" {
    local block
    block=$(_yaml_node_block "my:host" "Default" "10.0.0.1" "22" "root" "pass" "sec\"ret" "" "")
    echo "$block" | grep -q 'name: "my:host"'
    echo "$block" | grep -q 'pass: "sec\"ret"'
}

@test "_yaml_delete_node removes middle node correctly" {
    local config="${WORK_DIR}/delete_middle.yaml"
    _yaml_ops_test_config "$config"

    local result_file
    result_file=$(_yaml_delete_node "$config" 2)

    grep -q "^- name: keep1" "$result_file"
    grep -q "^- name: keep2" "$result_file"
    ! grep -q "^- name: delete-me" "$result_file"

    rm -f "$result_file"
}

@test "_yaml_delete_node removes first node correctly" {
    local config="${WORK_DIR}/delete_first.yaml"
    _yaml_ops_test_config "$config"

    local result_file
    result_file=$(_yaml_delete_node "$config" 1)

    ! grep -q "^- name: keep1" "$result_file"
    grep -q "^- name: delete-me" "$result_file"

    rm -f "$result_file"
}

@test "_yaml_delete_node removes last node correctly" {
    local config="${WORK_DIR}/delete_last.yaml"
    _yaml_ops_test_config "$config"

    local result_file
    result_file=$(_yaml_delete_node "$config" 3)

    grep -q "^- name: keep1" "$result_file"
    grep -q "^- name: delete-me" "$result_file"
    ! grep -q "^- name: keep2" "$result_file"

    rm -f "$result_file"
}

@test "_yaml_delete_node preserves nodes header" {
    local config="${WORK_DIR}/preserve_header.yaml"
    _yaml_ops_test_config "$config"

    local result_file
    result_file=$(_yaml_delete_node "$config" 2)

    head -n1 "$result_file" | grep -q "^nodes:"

    rm -f "$result_file"
}

@test "_yaml_delete_node leaves empty nodes header when all deleted" {
    local config="${WORK_DIR}/single.yaml"
    cat > "$config" << 'EOF'
nodes:
  - name: only
    host: 1.2.3.4
    user: root
EOF

    local result_file
    result_file=$(_yaml_delete_node "$config" 1)

    grep -q "^nodes:" "$result_file"

    rm -f "$result_file"
}

@test "_yaml_append_node appends node block to config" {
    local config="${WORK_DIR}/append.yaml"
    cat > "$config" << 'EOF'
nodes:
  - name: existing
    host: 10.0.0.1
    user: root
EOF

    _yaml_append_node "$config" "newnode" "Default" "10.0.0.2" "22" "root" "pass" "pass123" "" ""

    grep -q "^- name: existing" "$config"
    grep -q "^- name: newnode" "$config"
    grep -q "host: 10.0.0.2" "$config"
}

@test "_yaml_append_node handles special characters in values" {
    local config="${WORK_DIR}/append_special.yaml"
    cat > "$config" << 'EOF'
nodes:
EOF

    _yaml_append_node "$config" "my:node" "Default" "10.0.0.1" "22" "root" "pass" "p@ss#word" "" ""

    grep -q 'name: "my:node"' "$config"
    grep -q 'pass: "p@ss#word"' "$config"
}
