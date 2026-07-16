#!/usr/bin/env bash
# ============================================================================
# util.sh — Terminal utilities, formatting helpers, connection history
#
# Small reusable functions used across the TUI and CLI.
#
# Key functions:
#   _term_width              — get terminal width (cols)
#   _pad_right <str> <len>   — right-pad string to byte length
#   _pad_center <str> <len>  — center-pad string
#   _record_connection       — log connection to history file
#   _sshm_history_menu       — render connection history picker
#
# History file: ~/.cache/ssh-manager-history (last 100 entries)
# ============================================================================

_term_width() {
    tput cols 2>/dev/null || echo "${COLUMNS:-80}"
}

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

_ping_check() {
    local host="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        ping -c 1 -t 1 "$host" &>/dev/null
    else
        ping -c 1 -W 1 "$host" &>/dev/null
    fi
}
