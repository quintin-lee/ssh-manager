#!/usr/bin/env bash

_term_width() {
    tput cols 2>/dev/null || echo "${COLUMNS:-80}"
}

declare -A _SSHM_PING_CACHE
_SSHM_HISTORY_FILE="${HOME}/.cache/ssh-manager-history"

_record_connection() {
    local name="$1" host="$2"
    mkdir -p "$(dirname "$_SSHM_HISTORY_FILE")" 2>/dev/null
    local entry
    entry="${name}|${host}|$(date +%s)"
    grep -vFx "$entry" "$_SSHM_HISTORY_FILE" 2>/dev/null > "${_SSHM_HISTORY_FILE}.tmp" || true
    echo "$entry" >> "${_SSHM_HISTORY_FILE}.tmp"
    tail -20 "${_SSHM_HISTORY_FILE}.tmp" > "$_SSHM_HISTORY_FILE"
    rm -f "${_SSHM_HISTORY_FILE}.tmp"
}

_get_recent() {
    if [[ -f "$_SSHM_HISTORY_FILE" ]]; then
        tac "$_SSHM_HISTORY_FILE" 2>/dev/null | head -10
    fi
}

_ping_check_cached() {
    local host="$1"
    local now
    now=$(date +%s)
    local cached_time=0
    if [[ -n "${_SSHM_PING_CACHE[$host]+x}" ]]; then
        cached_time="${_SSHM_PING_CACHE[$host]}"
    fi

    if [[ $((now - cached_time)) -lt 30 ]]; then
        return 0
    fi

    if [[ "$(uname)" == "Darwin" ]]; then
        ping -c 1 -t 1 "$host" &>/dev/null
    else
        ping -c 1 -W 1 "$host" &>/dev/null
    fi

    if [[ $? -eq 0 ]]; then
        _SSHM_PING_CACHE[$host]="$now"
        return 0
    else
        _SSHM_PING_CACHE[$host]="$now"
        return 1
    fi
}

_ping_check() {
    _ping_check_cached "$@"
}
