#!/usr/bin/env bats

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    WORK_DIR="${BATS_TMPDIR}/sshm-delete-test-$$"
    mkdir -p "$WORK_DIR"
    CONFIG_FILE="${WORK_DIR}/config.yaml"

    cat > "$CONFIG_FILE" << 'EOF'
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

teardown() {
    rm -rf "$WORK_DIR"
}

@test "perform_delete removes middle node correctly" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    # Count nodes before
    get_all_nodes "$CONFIG_FILE"
    local count_before=${#NODES_ARRAY[@]}
    [[ "$count_before" -eq 3 ]]

    # Simulate perform_delete logic
    local id=2
    local tmp_file=$(mktemp)
    local in_node=0
    local current_id=0
    local skip=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            current_id=$((current_id + 1))
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
                echo "$line" >>"$tmp_file"
            fi
            continue
        fi

        echo "$line" >>"$tmp_file"
    done <"$CONFIG_FILE"

    # Verify result
    get_all_nodes "$tmp_file"
    [[ ${#NODES_ARRAY[@]} -eq 2 ]]

    # Verify remove-me is gone
    get_all_nodes "$tmp_file" "delete-me"
    [[ ${#NODES_ARRAY[@]} -eq 0 ]]

    # Verify keep1 and keep2 remain
    get_all_nodes "$tmp_file" "keep1"
    [[ ${#NODES_ARRAY[@]} -eq 1 ]]

    get_all_nodes "$tmp_file" "keep2"
    [[ ${#NODES_ARRAY[@]} -eq 1 ]]

    rm -f "$tmp_file"
}

@test "perform_delete on non-existent id makes no changes" {
    local id=99
    local tmp_file=$(mktemp)
    local in_node=0
    local current_id=0
    local skip=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            current_id=$((current_id + 1))
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
                echo "$line" >>"$tmp_file"
            fi
            continue
        fi

        echo "$line" >>"$tmp_file"
    done <"$CONFIG_FILE"

    diff "$CONFIG_FILE" "$tmp_file"
    rm -f "$tmp_file"
}

@test "perform_delete on first node works" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local id=1
    local tmp_file=$(mktemp)
    local in_node=0
    local current_id=0
    local skip=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            current_id=$((current_id + 1))
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
                echo "$line" >>"$tmp_file"
            fi
            continue
        fi

        echo "$line" >>"$tmp_file"
    done <"$CONFIG_FILE"

    get_all_nodes "$tmp_file"
    [[ ${#NODES_ARRAY[@]} -eq 2 ]]

    get_all_nodes "$tmp_file" "keep1"
    [[ ${#NODES_ARRAY[@]} -eq 0 ]]

    rm -f "$tmp_file"
}

@test "perform_delete on only node leaves empty nodes header" {
    local config="${WORK_DIR}/single.yaml"
    cat > "$config" << 'EOF'
nodes:
  - name: only
    host: 1.2.3.4
    user: root
EOF

    local id=1
    local tmp_file=$(mktemp)
    local in_node=0
    local current_id=0
    local skip=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            current_id=$((current_id + 1))
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
                echo "$line" >>"$tmp_file"
            fi
            continue
        fi

        echo "$line" >>"$tmp_file"
    done <"$config"

    grep -q "^nodes:" "$tmp_file"
    rm -f "$tmp_file"
}
