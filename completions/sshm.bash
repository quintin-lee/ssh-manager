#!/usr/bin/env bash
# shellcheck disable=SC2207  # COMPREPLY array assignment is standard completion pattern
_sshm_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        --config)
            COMPREPLY=($(compgen -f -- "$cur"))
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        opts="--help -h --version -v --config"
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
        return 0
    fi

    local conf="${SSH_MANAGER_CONFIG:-${HOME}/.config/ssh-manager/config.yaml}"
    if [[ -f "$conf" ]]; then
        local nodes
        nodes=$(grep -E '^\s*-?\s*name:\s*' "$conf" 2>/dev/null | sed 's/.*name:\s*//' | sed 's/^"//;s/"$//')
        COMPREPLY=($(compgen -W "$nodes" -- "$cur"))
    fi
}

complete -F _sshm_completion sshm
