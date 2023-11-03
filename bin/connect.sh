#!/bin/bash

CMD_DIR=$(dirname $(readlink -f $0))

source ${CMD_DIR}/config.sh
get_servers

PS3="Enter a number[1-${#servers[*]}]:"
select server in ${servers[@]}
do
    if [ "x$server" != "x" ]
    then
        get_host_info $server
        ${CMD_DIR}/login.exp ${host} ${username} "${password}" ${port}
        break;
    fi
    echo "Invalid selected"
done
