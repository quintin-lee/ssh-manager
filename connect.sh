#!/bin/bash

CMD_DIR=$(dirname $(readlink -f $0))
CONF=${CONF:-${CMD_DIR}/host.conf}

i=0
while read line 
do
    echo ${line} | egrep '^( |\t)*#' >/dev/null 2>&1
    if [ $? -eq 1 ]
    then
        HOSTS="$HOSTS $(echo ${line} | awk '{print $1}')"
    fi
    ALL_SERVERS[${i}]=${line}
    i=`expr $i + 1`;
done < ${CONF}

# string to array
IFS=" "
servers=(${HOSTS})

if [ ${#servers[*]} -eq 0 ]
then
    echo "No services to connect!!"
    exit 1
fi

PS3="Enter a number[1-${#servers[*]}]:"
select server in ${servers[@]}
do
    # $REPLY 输入的标号
    # convert tab to space
    str=$(echo ${ALL_SERVERS[${REPLY}]} | sed 's#\t# #g');
    info=(${str})
    if [ "x${server}" != "x" ]
    then
        host=${info[1]}
        user_name=${info[2]}
        user_passwd=${info[3]}
        port=${info[4]}
        ${CMD_DIR}/login.exp ${host} ${user_name} ${user_passwd} ${port}
        break;
    fi
    echo "Invalid selected"
done
