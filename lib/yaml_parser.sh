#!/usr/bin/env bash

# shellcheck disable=SC2034  # NODE_* variables are intentionally exported for callers

# Trim leading and trailing whitespace from a string
_trim() {
    local var="$1"
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

read_node_info() {
    local conf="$1"
    local id=$2
    unset NODE_NAME NODE_GROUP NODE_HOST NODE_PORT NODE_USER NODE_TYPE NODE_PASS NODE_KEYPATH NODE_TAGS

    local in_node=0
    local current_id=0
    local _name="" _group="" _host="" _port="22" _user="" _type="pass" _pass="" _keypath="" _tags=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            current_id=$((current_id + 1))
            in_node=1
            if [[ $current_id -eq $id ]]; then
                _name=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*//')
            else
                in_node=0
            fi
            continue
        fi

        if [[ $in_node -eq 1 && $current_id -eq $id ]]; then
            if [[ "$line" =~ ^[[:space:]]*group:[[:space:]]* ]]; then
                _group=$(echo "$line" | sed 's/^[[:space:]]*group:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*host:[[:space:]]* ]]; then
                _host=$(echo "$line" | sed 's/^[[:space:]]*host:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*port:[[:space:]]* ]]; then
                _port=$(echo "$line" | sed 's/^[[:space:]]*port:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*user:[[:space:]]* ]]; then
                _user=$(echo "$line" | sed 's/^[[:space:]]*user:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*type:[[:space:]]* ]]; then
                _type=$(echo "$line" | sed 's/^[[:space:]]*type:[[:space:]]*//')
            elif [[ "$line" =~ ^[[:space:]]*pass:[[:space:]]* ]]; then
                _pass=$(echo "$line" | sed 's/^[[:space:]]*pass:[[:space:]]*//')
                if [[ "${_pass:0:1}${_pass:(-1)}" == '""' ]]; then
                    _pass="${_pass:1:-1}"
                elif [[ "${_pass:0:1}${_pass:(-1)}" == "''" ]]; then
                    _pass="${_pass:1:-1}"
                fi
            elif [[ "$line" =~ ^[[:space:]]*keypath:[[:space:]]* ]]; then
                _keypath=$(echo "$line" | sed 's/^[[:space:]]*keypath:[[:space:]]*//')
                if [[ "${_keypath:0:1}${_keypath:(-1)}" == '""' ]]; then
                    _keypath="${_keypath:1:-1}"
                elif [[ "${_keypath:0:1}${_keypath:(-1)}" == "''" ]]; then
                    _keypath="${_keypath:1:-1}"
                fi
            elif [[ "$line" =~ ^[[:space:]]*tags:[[:space:]]* ]]; then
                _tags=$(echo "$line" | sed 's/^[[:space:]]*tags:[[:space:]]*//')
                _tags="${_tags// /}"
                _tags="${_tags#\"}"; _tags="${_tags%\"}"
                _tags="${_tags#\'}"; _tags="${_tags%\'}"
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
                break
            fi
        fi
    done <"$conf"

    NODE_GROUP=${_group:-Default}
    NODE_PORT=${_port:-22}
    NODE_TYPE=${_type:-pass}

    NODE_NAME=$(_trim "${_name:-}")
    NODE_GROUP=$(_trim "${NODE_GROUP:-}")
    NODE_HOST=$(_trim "${_host:-}")
    NODE_PORT=$(_trim "${NODE_PORT:-}")
    NODE_USER=$(_trim "${_user:-}")
    NODE_TYPE=$(_trim "${NODE_TYPE:-}")
    NODE_PASS=$(_trim "${_pass:-}")
    NODE_KEYPATH=$(_trim "${_keypath:-}")
    NODE_TAGS=$(_trim "${_tags:-}")
}

get_all_nodes() {
    local conf="$1"
    local filter_key="${2,,}"
    local group_filter="$3"
    unset NODES_ARRAY
    NODES_ARRAY=()

    local current_id=0
    local node_name="" node_group="" node_host="" node_port="22" node_type="pass" node_tags=""
    local in_node=0
    local _nodes=()
    local match=1

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]* ]]; then
            if [[ $in_node -eq 1 && -n "$node_name" ]]; then
                match=1
                if [[ -n "$filter_key" && "${node_name,,}" != *"$filter_key"* && "$node_host" != *"$filter_key"* ]]; then
                    match=0
                fi
                if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
                    match=0
                fi
                if [[ $match -eq 1 ]]; then
                    _nodes+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type|$node_tags")
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
        match=1
        if [[ -n "$filter_key" && "${node_name,,}" != *"$filter_key"* && "$node_host" != *"$filter_key"* ]]; then
            match=0
        fi
        if [[ -n "$group_filter" && "$node_group" != "$group_filter" ]]; then
            match=0
        fi
        if [[ $match -eq 1 ]]; then
            _nodes+=("$current_id|$node_name|$node_group|$node_host|$node_port|$node_type|$node_tags")
        fi
    fi

    # shellcheck disable=SC2034
    NODES_ARRAY=("${_nodes[@]}")
}
