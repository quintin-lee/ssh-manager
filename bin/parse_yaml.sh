#!/bin/bash

declare -g filename
declare -g prefix

function usage()
{
    echo "Usage:"
    echo "      $(basename $0) [-p <prefix>] filename"
    exit 1
}

function parse_param()
{
    while [ $# -gt 0 ]
    do
        case "$1" in
            -p)
                shift
                prefix=$1
                ;;
            *)
                filename="$1"
                ;;
        esac
        shift
    done
}

function file_is_exists()
{
    echo "$([ -e $1 ] && echo 1 || echo 0)"
}

function parse_yaml
{
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|,$s\]$s\$|]|" \
        -e ":1;s|^\($s\)\($w\)$s:$s\[$s\(.*\)$s,$s\(.*\)$s\]|\1\2: [\3]\n\1  - \4|;t1" \
        -e "s|^\($s\)\($w\)$s:$s\[$s\(.*\)$s\]|\1\2:\n\1  - \3|;p" $filename | \
   sed -ne "s|,$s}$s\$|}|" \
        -e ":1;s|^\($s\)-$s{$s\(.*\)$s,$s\($w\)$s:$s\(.*\)$s}|\1- {\2}\n\1  \3: \4|;t1" \
        -e    "s|^\($s\)-$s{$s\(.*\)$s}|\1-\n\1  \2|;p" | \
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)-$s[\"']\(.*\)[\"']$s\$|\1$fs$fs\2|p" \
        -e "s|^\($s\)-$s\(.*\)$s\$|\1$fs$fs\2|p" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" | \
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]; idx[i]=0}}
      if(length($2)== 0){  vname[indent]= ++idx[indent] };
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) { vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, vname[indent], $3);
      }
   }'
}

function main()
{
    parse_param $@

    if [ "x$filename" == "x" -o $(file_is_exists $filename) -eq 0 ]
    then
        echo "Error: No specified YAML file or file does not exist."
        usage
    fi

    if [ "x$prefix" == "x" ]
    then
        prefix="$(basename $filename | awk -F'.' '{print $1}')_"
    fi

    parse_yaml
}

main $@

