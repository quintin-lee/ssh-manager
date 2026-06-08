#!/usr/bin/env bash

# shellcheck disable=SC2034  # Variables are intentionally exported for callers
read_node_info() {
    local conf="$1"
    local id=$2
    unset NODE_NAME NODE_GROUP NODE_HOST NODE_PORT NODE_USER NODE_TYPE NODE_PASS NODE_KEYPATH

    local in_node=0
    local current_id=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            current_id=$((current_id + 1))
            in_node=1
            if [[ $current_id -eq $id ]]; then
                NODE_NAME=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')
            else
                in_node=0
            fi
            continue
        fi

        if [[ $in_node -eq 1 && $current_id -eq $id ]]; then
            if [[ "$line" =~ ^[[:space:]]*group:[[:space:]]* ]]; then
                NODE_GROUP=$(echo "$line" | sed 's/^[[:space:]]*group:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*host:[[:space:]]* ]]; then
                NODE_HOST=$(echo "$line" | sed 's/^[[:space:]]*host:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*port:[[:space:]]* ]]; then
                NODE_PORT=$(echo "$line" | sed 's/^[[:space:]]*port:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*user:[[:space:]]* ]]; then
                NODE_USER=$(echo "$line" | sed 's/^[[:space:]]*user:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]* ]]; then
                NODE_TYPE=$(echo "$line" | sed 's/^[[:space:]]*type:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*pass:[[:space:]]* ]]; then
                NODE_PASS=$(echo "$line" | sed 's/^[[:space:]]*pass:[[:space:]]*//')
                NODE_PASS="${NODE_PASS#\"}"
                NODE_PASS="${NODE_PASS%\"}"
                NODE_PASS="${NODE_PASS#\'}"
                NODE_PASS="${NODE_PASS%\'}"
            elif [[ "$line" =~ ^[[:space:]]*keypath:[[:space:]]* ]]; then
                NODE_KEYPATH=$(echo "$line" | sed 's/^[[:space:]]*keypath:[[:space:]]*//')
                NODE_KEYPATH="${NODE_KEYPATH#\"}"
                NODE_KEYPATH="${NODE_KEYPATH%\"}"
                NODE_KEYPATH="${NODE_KEYPATH#\'}"
                NODE_KEYPATH="${NODE_KEYPATH%\'}"
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                break
            fi
        fi
    done <"$conf"

    NODE_GROUP=${NODE_GROUP:-Default}
    NODE_PORT=${NODE_PORT:-22}
    NODE_TYPE=${NODE_TYPE:-pass}
}

get_all_nodes() {
    local conf="$1"
    local filter_key="${2,,}"
    local group_filter="$3"
    unset NODES_ARRAY
    NODES_ARRAY=()

    local current_id=0
    local node_name=""
    local node_group=""
    local node_host=""
    local node_port=""
    local node_type=""
    local in_node=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            if [[ $in_node -eq 1 && -n "$node_name" ]]; then
                local match=1
                if [[ -n "$filter_key" && ! "${node_name,,}" =~ $filter_key && ! "$node_host" =~ $filter_key ]]; then
                    match=0
                fi
                if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
                    match=0
                fi
                if [[ $match -eq 1 ]]; then
                    NODES_ARRAY+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type")
                fi
            fi

            current_id=$((current_id + 1))
            in_node=1
            node_name=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')
            node_group="Default"
            node_host=""
            node_port="22"
            node_type="pass"
            continue
        fi

        if [[ $in_node -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]*group:[[:space:]]* ]]; then
                node_group=$(echo "$line" | sed 's/^[[:space:]]*group:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*host:[[:space:]]* ]]; then
                node_host=$(echo "$line" | sed 's/^[[:space:]]*host:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*port:[[:space:]]* ]]; then
                node_port=$(echo "$line" | sed 's/^[[:space:]]*port:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]* ]]; then
                node_type=$(echo "$line" | sed 's/^[[:space:]]*type:[[:space:]]*//')
            fi
        fi
    done <"$conf"

    if [[ $in_node -eq 1 && -n "$node_name" ]]; then
        local match=1
        if [[ -n "$filter_key" && ! "${node_name,,}" =~ $filter_key && ! "$node_host" =~ $filter_key ]]; then
            match=0
        fi
        if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
            match=0
        fi
        if [[ $match -eq 1 ]]; then
            NODES_ARRAY+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type")
        fi
    fi
}
