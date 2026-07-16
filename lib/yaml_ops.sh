#!/usr/bin/env bash
# ============================================================================
# yaml_ops.sh — YAML serialization for node operations
#
# Generates YAML output blocks for saving/exporting node configuration.
# Used by node CRUD functions to construct proper YAML syntax.
#
# Key functions:
#   _yaml_node_block     — generate YAML block for a single node
#   _build_config_yaml   — compose full config YAML from updated node list
#   _export_nodes        — render config as SSH config format
# ============================================================================

_yaml_node_block() {
    local name="$1" group="$2" host="$3" port="$4" user="$5" type="$6" pass="$7" keypath="$8" tags="$9"
    cat <<EOF
  - name: $(sanitize_yaml_value "$name")
    group: $(sanitize_yaml_value "$group")
    host: $(sanitize_yaml_value "$host")
    port: ${port}
    user: $(sanitize_yaml_value "$user")
    type: ${type}
    pass: $(sanitize_yaml_value "$pass")
    keypath: $(sanitize_yaml_value "$keypath")
    tags: $(sanitize_yaml_value "$tags")
EOF
}

_yaml_delete_node() {
    local conf="$1"
    local id=$2
    local tmp_file
    tmp_file=$(mktemp) || { _echo "${RED}错误：无法创建临时文件${RESET}" >&2; return 1; }
    local current_id=0 skip=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            current_id=$((current_id + 1))
            if [[ $current_id -eq $id ]]; then
                skip=1
                continue
            else
                skip=0
            fi
        fi

        if [[ $skip -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                skip=0
                echo "$line" >>"$tmp_file"
            fi
            continue
        fi

        echo "$line" >>"$tmp_file"
    done <"$conf"

    sed_i '/^[[:space:]]*$/N;/^[[:space:]]*\n[[:space:]]*$/D' "$tmp_file"
    if [[ $(head -n1 "$tmp_file" | tr -d '[:space:]') != "nodes:" ]]; then
        sed_i '1i nodes:' "$tmp_file"
    fi

    echo "$tmp_file"
}

_yaml_append_node() {
    local conf="$1"
    shift
    sed_i -e '$a\' "$conf" 2>/dev/null || true
    _yaml_node_block "$@" >>"$conf"
}
