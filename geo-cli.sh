#!/bin/bash
if [[ `whoami` = 'root' ]]; then echo 'ERROR: Do not run mlo as root (sudo)'; exit; fi

# # . lib/
# Gives the path of the file that was passed in when the script was executed. Could be relative
# SOURCE="${BASH_SOURCE[0]}"
# DIR_NAME=`dirname $SOURCE`
# echo $SOURCE

# Gets the absolute path of the directory this script is in.
export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
# ThisScriptPath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")" 

echo $GEO_CLI_DIR
# function geo
# {
#     echo 'geo'
# }

. $GEO_CLI_DIR/init/init.sh
. $GEO_CLI_DIR/utils/colors.sh
. $GEO_CLI_DIR/utils/config-file-utils.sh
. $GEO_CLI_DIR/utils/cli-handlers.sh

# Auto-complete
completions=(
    "${COMMANDS[@]}"
    )

# Doesn't work for some reason
# complete -W "${completions[@]}" geo

# Get list of completions separated by spaces (required as imput to complete command)
comp_string=`echo "${completions[@]}"`
complete -W "$comp_string" geo

IMAGE=postgres11
CONTAINER="geo_${IMAGE}"
CONTAINER_NAME=""
function geodb()
{
    VOL_NAME="geo_db_${1}"
    CONTAINER_NAME="${CONTAINER}_${1}"

    # docker run -v 2002:/var/lib/postgresql/11/main -p 5432:5432 postgres11

    VOLUME=`docker volume ls | grep " $VOL_NAME"`

    geostop $1
    CONTAINER_ID=`docker ps -aqf "name=$CONTAINER_NAME"`
    
    if [ -z "$VOLUME" ]; then
        docker volume create "$VOL_NAME"

        if [ -n "$CONTAINER_ID" ]; then
            docker start $CONTAINER_ID
        else
            docker run -v $VOL_NAME:/var/lib/postgresql/11/main -p 5432:5432 --name=$CONTAINER_NAME -d $IMAGE
        fi
        sleep 10
        geo_init_db
    else
        if [ -n "$CONTAINER_ID" ]; then
            docker start $CONTAINER_ID
        else
            docker run -v $VOL_NAME:/var/lib/postgresql/11/main -p 5432:5432 --name=$CONTAINER_NAME -d $IMAGE
        fi
    fi
}

function geostop()
{
    CONTAINER_NAME="${CONTAINER}_${1}"
    ID=`docker ps -qf "name=$CONTAINER_NAME"`

    if [ -n "$ID" ]; then
        docker stop $ID
    fi
}

function geo_db_init()
{
    cd ~/repos/MyGeotab/Checkmate/bin/Debug/netcoreapp3.1/
    dotnet CheckmateServer.dll CreateDatabase postgres companyName=geotabdemo administratorUser=dawsonmyers@geotab.com administratorPassword=password sqluser=geotabuser sqlpassword=vircom43
}

function geo_db_rm()
{
    CONTAINER_NAME="${CONTAINER}_${1}"
    VOL_NAME="geo_db_${1}"
    docker container rm $CONTAINER_NAME
    docker volume rm $VOL_NAME

}