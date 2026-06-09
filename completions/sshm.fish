function __sshm_nodes
    set -l conf "$SSH_MANAGER_CONFIG"
    test -z "$conf" && set conf "$HOME/.config/ssh-manager/config.yaml"
    test -f /etc/ssh-manager/config.yaml && set conf "/etc/ssh-manager/config.yaml"
    if test -f "$conf"
        grep -E '^\s*-?\s*name:\s*' "$conf" 2>/dev/null | sed 's/.*name:\s*//;s/^"//;s/"$//'
    end
end

complete -c sshm -s h -l help -d "Show help message"
complete -c sshm -s v -l version -d "Show version information"
complete -c sshm -l config -r -d "Use specified config file"
complete -c sshm -f -a "(__sshm_nodes)" -d "Node name"
