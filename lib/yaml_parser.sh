#!/usr/bin/env bash

_trim() {
    local var="$1"
    echo "${var%"${var##*[![:space:]]}"}"
}

# shellcheck disable=SC2034  # Variables are intentionally exported for callers
read_node_info() {
    local conf="$1"
    local id=$2
    unset NODE_NAME NODE_GROUP NODE_HOST NODE_PORT NODE_USER NODE_TYPE NODE_PASS NODE_KEYPATH NODE_TAGS

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
                if [[ "${NODE_PASS:0:1}${NODE_PASS:(-1)}" == '""' ]]; then
                    NODE_PASS="${NODE_PASS:1:-1}"
                elif [[ "${NODE_PASS:0:1}${NODE_PASS:(-1)}" == "''" ]]; then
                    NODE_PASS="${NODE_PASS:1:-1}"
                fi
            elif [[ "$line" =~ ^[[:space:]]*keypath:[[:space:]]* ]]; then
                NODE_KEYPATH=$(echo "$line" | sed 's/^[[:space:]]*keypath:[[:space:]]*//')
                if [[ "${NODE_KEYPATH:0:1}${NODE_KEYPATH:(-1)}" == '""' ]]; then
                    NODE_KEYPATH="${NODE_KEYPATH:1:-1}"
                elif [[ "${NODE_KEYPATH:0:1}${NODE_KEYPATH:(-1)}" == "''" ]]; then
                    NODE_KEYPATH="${NODE_KEYPATH:1:-1}"
                fi
            elif [[ "$line" =~ ^[[:space:]]*tags:[[:space:]]* ]]; then
                NODE_TAGS=$(echo "$line" | sed 's/^[[:space:]]*tags:[[:space:]]*//')
                NODE_TAGS="${NODE_TAGS// /}"
                NODE_TAGS="${NODE_TAGS#\"}"; NODE_TAGS="${NODE_TAGS%\"}"
                NODE_TAGS="${NODE_TAGS#\'}"; NODE_TAGS="${NODE_TAGS%\'}"
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                break
            fi
        fi
    done <"$conf"

    NODE_GROUP=${NODE_GROUP:-Default}
    NODE_PORT=${NODE_PORT:-22}
    NODE_TYPE=${NODE_TYPE:-pass}

    NODE_NAME=$(_trim "${NODE_NAME:-}")
    NODE_GROUP=$(_trim "${NODE_GROUP:-}")
    NODE_HOST=$(_trim "${NODE_HOST:-}")
    NODE_PORT=$(_trim "${NODE_PORT:-}")
    NODE_USER=$(_trim "${NODE_USER:-}")
    NODE_TYPE=$(_trim "${NODE_TYPE:-}")
    NODE_PASS=$(_trim "${NODE_PASS:-}")
    NODE_KEYPATH=$(_trim "${NODE_KEYPATH:-}")
    NODE_TAGS=$(_trim "${NODE_TAGS:-}")
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
    local node_tags=""
    local in_node=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            if [[ $in_node -eq 1 && -n "$node_name" ]]; then
                local match=1
                if [[ -n "$filter_key" && "${node_name,,}" != *"$filter_key"* && "$node_host" != *"$filter_key"* ]]; then
                    match=0
                fi
                if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
                    match=0
                fi
                if [[ $match -eq 1 ]]; then
                    NODES_ARRAY+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type|$node_tags")
                fi
            fi

            current_id=$((current_id + 1))
            in_node=1
            node_name=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')
            node_group="Default"
                node_host=""
                node_port="22"
                node_type="pass"
                node_tags=""
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
            elif [[ "$line" =~ ^[[:space:]]*tags:[[:space:]]* ]]; then
                node_tags=$(echo "$line" | sed 's/^[[:space:]]*tags:[[:space:]]*//')
                node_tags="${node_tags// /}"
                node_tags="${node_tags#\"}"; node_tags="${node_tags%\"}"
                node_tags="${node_tags#\'}"; node_tags="${node_tags%\'}"
            fi
        fi
    done <"$conf"

    node_name=$(_trim "$node_name")
    node_group=$(_trim "$node_group")
    node_host=$(_trim "$node_host")
    node_port=$(_trim "$node_port")
    node_type=$(_trim "$node_type")

    if [[ $in_node -eq 1 && -n "$node_name" ]]; then
        local match=1
        if [[ -n "$filter_key" && "${node_name,,}" != *"$filter_key"* && "$node_host" != *"$filter_key"* ]]; then
            match=0
        fi
        if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
            match=0
        fi
        if [[ $match -eq 1 ]]; then
            NODES_ARRAY+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type|$node_tags")
        fi
    fi
}
