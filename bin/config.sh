#!/bin/bash

CONF_FILE=${CONF_FILE:-${CMD_DIR}/../conf/conf.yml}

declare -g prefix="conf_"

declare -a servers
declare -g servers_number
declare -g server
declare -g host
declare -g username
declare -g password
declare -g port

function get_servers()
{
    servers_number=$(declare -p | grep ${prefix}servers | wc -l)

    for i in $(seq 1 $servers_number)
    do
        servers[`expr "$i -1"`]=$(eval echo '$'"${prefix}servers_$i")
    done
}

function get_host_info()
{
    server=$1

    host=$(eval echo '$'"$prefix${server}_ip")
    username=$(eval echo '$'"$prefix${server}_user")
    pwd_var=${prefix}${server}_password
    password=${!pwd_var}
    port=$(eval echo '$'"$prefix${server}_port")
}

function main()
{
    if [ ! -f ${CONF_FILE} ]
    then
        echo "ERROR: CONFIG_FILE not specified or not exists"
        exit 1
    fi

    eval $(bash ${CMD_DIR}/parse_yaml.sh -p $prefix ${CONF_FILE})
}

main $*
