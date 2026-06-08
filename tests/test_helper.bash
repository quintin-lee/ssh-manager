setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    SSH_MANAGER_SCRIPT="${TEST_DIR}/../bin/sshm.sh"
}

load_test_fixture() {
    local fixture="$1"
    echo "${TEST_DIR}/fixtures/${fixture}"
}
