#!/usr/bin/env bats

load test_helper

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    WORK_DIR="${BATS_TMPDIR}/sshm-test-$$"
    mkdir -p "$WORK_DIR"
    CONFIG_FILE="${WORK_DIR}/config.yaml"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "base64 roundtrip encodes and decodes config correctly" {
    cat > "$CONFIG_FILE" << 'EOF'
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

    encoded=$(base64 "$CONFIG_FILE" | tr -d '\n')
    echo "$encoded" | base64 -d > "${WORK_DIR}/decoded.yaml"
    diff "$CONFIG_FILE" "${WORK_DIR}/decoded.yaml"
}

@test "base64 import detects invalid input" {
    run bash -c 'echo "not valid base64!!!" | base64 -d >/dev/null 2>&1'
    [[ "$status" -ne 0 ]]
}

@test "config file with special characters survives export/import roundtrip" {
    cat > "$CONFIG_FILE" << 'EOF'
nodes:
  - name: test
    group: Default
    host: 127.0.0.1
    port: 22
    user: root
    type: pass
    pass: "p@ss!with#special\$chars"
    keypath: ""
EOF

    encoded=$(base64 "$CONFIG_FILE" | tr -d '\n')
    echo "$encoded" | base64 -d > "${WORK_DIR}/decoded.yaml"

    original_pass=$(grep 'pass:' "$CONFIG_FILE" | sed 's/.*pass: *//')
    decoded_pass=$(grep 'pass:' "${WORK_DIR}/decoded.yaml" | sed 's/.*pass: *//')
    [[ "$original_pass" == "$decoded_pass" ]]
}
