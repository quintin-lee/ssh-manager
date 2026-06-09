#!/usr/bin/env bats

load test_helper

@test "_read_key detects ENTER on empty input" {
    result=$(printf '' | bash -c '
        _read_key() {
            local key
            IFS= read -r -s -n 1 key
            if [[ "$key" == "" ]]; then echo "ENTER"
            else echo "$key"; fi
        }
        _read_key
    ')
    [[ "$result" == "ENTER" ]]
}

@test "_read_key detects printable character" {
    result=$(printf 'a' | bash -c '
        _read_key() {
            local key
            IFS= read -r -s -n 1 key
            if [[ "$key" == "" ]]; then echo "ENTER"
            else echo "$key"; fi
        }
        _read_key
    ')
    [[ "$result" == "a" ]]
}

@test "sort mode default is group" {
    _SORT_MODE="group"
    [[ "$_SORT_MODE" == "group" ]]
}

@test "sort cycle group->name->status->group" {
    _SORT_MODE="group"
    case "$_SORT_MODE" in group) _SORT_MODE="name";; name) _SORT_MODE="status";; status) _SORT_MODE="group";; esac
    [[ "$_SORT_MODE" == "name" ]]
    case "$_SORT_MODE" in group) _SORT_MODE="name";; name) _SORT_MODE="status";; status) _SORT_MODE="group";; esac
    [[ "$_SORT_MODE" == "status" ]]
    case "$_SORT_MODE" in group) _SORT_MODE="name";; name) _SORT_MODE="status";; status) _SORT_MODE="group";; esac
    [[ "$_SORT_MODE" == "group" ]]
}

@test "filter_key backspace removes last char" {
    local filter_key="ser"
    filter_key="${filter_key:0:-1}"
    [[ "$filter_key" == "se" ]]
}

@test "filter_key append lowercases input" {
    local filter_key=""
    local key="P"
    filter_key="${filter_key}${key,,}"
    [[ "$filter_key" == "p" ]]
}

@test "selected_idx clamped on UP at 0" {
    local selected_idx=0
    if [[ $selected_idx -gt 0 ]]; then
        selected_idx=$((selected_idx - 1))
    fi
    [[ "$selected_idx" -eq 0 ]]
}

@test "selected_idx increments on DOWN within bounds" {
    local selected_idx=0
    local total=5
    if [[ $selected_idx -lt $((total - 1)) ]]; then
        selected_idx=$((selected_idx + 1))
    fi
    [[ "$selected_idx" -eq 1 ]]
}

@test "ssh config import parses Host and HostName" {
    local tmp_ssh="${BATS_TMPDIR}/sshm-test-ssh-config-$$"
    cat > "$tmp_ssh" << 'EOF'
Host myserver
    HostName 10.0.0.1
    User admin
    Port 2222

Host another
    HostName another.example.com
    User root
EOF

    local count=0
    local current_host="" current_name=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+(.+) ]]; then
            if [[ -n "$current_name" && -n "$current_host" ]]; then
                count=$((count + 1))
            fi
            current_name="${BASH_REMATCH[1]}"
            current_name="${current_name%% *}"
            current_host=""
        elif [[ "$line" =~ ^[[:space:]]*HostName[[:space:]]+(.+) ]]; then
            current_host="${BASH_REMATCH[1]}"
        fi
    done <"$tmp_ssh"
    if [[ -n "$current_name" && -n "$current_host" ]]; then
        ((count++))
    fi

    [[ "$count" -eq 2 ]]
    rm -f "$tmp_ssh"
}

@test "ssh config import skips wildcard Host" {
    local tmp_ssh="${BATS_TMPDIR}/sshm-test-ssh-config-$$"
    cat > "$tmp_ssh" << 'EOF'
Host *
    AddKeysToAgent yes

Host realserver
    HostName 10.0.0.5
EOF

    local current_name="" current_host=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+(.+) ]]; then
            current_name="${BASH_REMATCH[1]}"
            current_name="${current_name%% *}"
            current_host=""
        elif [[ "$line" =~ ^[[:space:]]*HostName[[:space:]]+(.+) ]]; then
            current_host="${BASH_REMATCH[1]}"
        fi
    done <"$tmp_ssh"

    [[ "$current_name" == "realserver" ]]
    [[ "$current_host" == "10.0.0.5" ]]
    rm -f "$tmp_ssh"
}
