#!/usr/bin/env bats

load test_helper

@test "read_node_info parses first node correctly" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    read_node_info "$config_file" 1

    [[ "$NODE_NAME" == "server1" ]]
    [[ "$NODE_GROUP" == "Production" ]]
    [[ "$NODE_HOST" == "192.168.1.10" ]]
    [[ "$NODE_PORT" == "22" ]]
    [[ "$NODE_USER" == "root" ]]
    [[ "$NODE_TYPE" == "pass" ]]
    [[ "$NODE_PASS" == "secret123" ]]
}

@test "read_node_info parses second node with key auth" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    read_node_info "$config_file" 2

    [[ "$NODE_NAME" == "server2" ]]
    [[ "$NODE_GROUP" == "Staging" ]]
    [[ "$NODE_HOST" == "10.0.0.5" ]]
    [[ "$NODE_PORT" == "2222" ]]
    [[ "$NODE_USER" == "admin" ]]
    [[ "$NODE_TYPE" == "key" ]]
    [[ "$NODE_KEYPATH" == "/home/admin/.ssh/id_rsa" ]]
}

@test "read_node_info handles special characters in password" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    read_node_info "$config_file" 3

    [[ "$NODE_NAME" == "server3" ]]
    [[ "$NODE_PASS" == "p@ss!with#special\$chars" ]]
}

@test "read_node_info defaults missing group to Default" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    read_node_info "$config_file" 1

    [[ "$NODE_GROUP" != "Default" ]]
}

@test "read_node_info defaults missing port to 22" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    read_node_info "$config_file" 1

    [[ "$NODE_PORT" == "22" ]]
}

@test "read_node_info with invalid id returns empty NODE_NAME" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    read_node_info "$config_file" 99

    [[ -z "$NODE_NAME" ]]
}

@test "get_all_nodes returns all nodes from config" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    get_all_nodes "$config_file"

    [[ ${#NODES_ARRAY[@]} -eq 3 ]]
}

@test "get_all_nodes with keyword filter" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture sample_config.yaml)"
    get_all_nodes "$config_file" "server2"

    [[ ${#NODES_ARRAY[@]} -eq 1 ]]
}

@test "read_node_info on config with no nodes returns empty" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture config_no_nodes.yaml)"
    read_node_info "$config_file" 1

    [[ -z "$NODE_NAME" ]]
}

@test "read_node_info on empty config returns empty" {
    source "${TEST_DIR}/../lib/yaml_parser.sh"

    local config_file
    config_file="$(load_test_fixture config_empty.yaml)"
    read_node_info "$config_file" 1

    [[ -z "$NODE_NAME" ]]
}
