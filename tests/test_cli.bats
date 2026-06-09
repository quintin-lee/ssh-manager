#!/usr/bin/env bats

load test_helper

@test "sshm --version exits 0" {
    run bash "${TEST_DIR}/../bin/sshm.sh" --version
    [[ "$status" -eq 0 ]]
    [[ "$output" == "SSH Manager v0.2" ]]
}

@test "sshm --help exits 0" {
    run bash "${TEST_DIR}/../bin/sshm.sh" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage: sshm"* ]]
}

@test "sshm -h exits 0" {
    run bash "${TEST_DIR}/../bin/sshm.sh" -h
    [[ "$status" -eq 0 ]]
}

@test "sshm -v exits 0" {
    run bash "${TEST_DIR}/../bin/sshm.sh" -v
    [[ "$status" -eq 0 ]]
}

@test "sshm --unknown exits 1" {
    run bash "${TEST_DIR}/../bin/sshm.sh" --unknown
    [[ "$status" -eq 1 ]]
}

@test "sshm --config without value exits 1" {
    run bash "${TEST_DIR}/../bin/sshm.sh" --config
    [[ "$status" -eq 1 ]]
}

@test "sshm --config with valid file loads config" {
    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"

    run bash "${TEST_DIR}/../bin/sshm.sh" --config "$config_file" --version
    [[ "$status" -eq 0 ]]
}
