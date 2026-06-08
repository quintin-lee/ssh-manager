#!/usr/bin/env bats

load test_helper

sanitize_yaml_value() {
    local val="$1"
    local need_quote=0

    if [[ "$val" == *:* || "$val" == *\#* || "$val" == *\"* || "$val" == *\\* ]]; then
        need_quote=1
    elif [[ "$val" =~ ^[[:space:]] || "$val" =~ [[:space:]]$ ]]; then
        need_quote=1
    fi

    if [[ "$need_quote" -eq 1 ]]; then
        val="${val//\\/\\\\}"
        val="${val//\"/\\\"}"
        echo "\"$val\""
    else
        echo "$val"
    fi
}

@test "sanitize: plain string passes through" {
    result=$(sanitize_yaml_value "hello")
    [[ "$result" == "hello" ]]
}

@test "sanitize: value with colon gets quoted" {
    result=$(sanitize_yaml_value "host:port")
    [[ "$result" == '"host:port"' ]]
}

@test "sanitize: value with hash gets quoted" {
    result=$(sanitize_yaml_value "some # comment")
    [[ "$result" == '"some # comment"' ]]
}

@test "sanitize: leading space triggers quoting" {
    result=$(sanitize_yaml_value " starts with space")
    [[ "$result" == '" starts with space"' ]]
}

@test "sanitize: internal double quotes are escaped" {
    result=$(sanitize_yaml_value 'he"llo')
    [[ "$result" == '"he\"llo"' ]]
}

@test "sanitize: backslashes are escaped" {
    result=$(sanitize_yaml_value 'path\to\file')
    [[ "$result" == '"path\\to\\file"' ]]
}

@test "sanitize: IP address passes through unquoted" {
    result=$(sanitize_yaml_value "192.168.1.1")
    [[ "$result" == "192.168.1.1" ]]
}

@test "sanitize: simple name passes through" {
    result=$(sanitize_yaml_value "production-server")
    [[ "$result" == "production-server" ]]
}
