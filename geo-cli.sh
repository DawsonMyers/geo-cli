#!/bin/bash
if [[ `whoami` = 'root' ]]; then echo 'ERROR: Do not run geo as root (sudo)'; exit; fi

# # . lib/
# Gives the path of the file that was passed in when the script was executed. Could be relative
# SOURCE="${BASH_SOURCE[0]}"
# DIR_NAME=`dirname $SOURCE`
# echo $SOURCE

# Gets the absolute path of the directory this script is in.
# export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 

# ThisScriptPath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")" 

# echo $GEO_CLI_DIR

# function geo
# {
#     echo 'geo'
# }

# . $GEO_CLI_DIR/init/init.sh
# . $GEO_CLI_DIR/utils/colors.sh
# . $GEO_CLI_DIR/utils/config-file-utils.sh
. $GEO_SRC_DIR/utils/cli-handlers.sh

function geo()
{
    # Save the first argument in cmd var, then shift all other args.
    # So the 2nd arg becomes the 1st, 3rd becomes the 2nd, and so on.
    cmd=$1
    shift

    # Display help for all commands and quit if it was requested.
    # Help can be requested in any of the following ways:
    #   geo help
    #   geo h
    #   geo -h
    #   geo --help
    if [[ $cmd =~ ^-*h(elp)? ]]; then
        detail_bi 'Available commands:'
        geo_help
        geo_show_msg_if_outdated
        # exit
        return
    fi

    # Display help for all commands and quit if it was requested.
    # Help can be requested in any of the following ways:
    #   geo version
    #   geo v
    #   geo -v
    #   geo --version
    if [[ $cmd =~ ^-*v(ersion)? ]]; then
        geo_version
        return
    fi
        

    # Quit if the command isn't valid
    if [ -z `cmd_exists $cmd` ]; then

        [ ${#cmd} -gt 0 ] && echo && verbose_bi 'Unknown command'
        
        # geotab_logo
        # geo_logo

        verbose ''
        verbose 'For help, run the following'
        detail '    geo --help'
        verbose 'or'
        detail '    geo -h'
        geo_show_msg_if_outdated
        # exit
        return
    fi

    # Show cmd help if the first arg to a command is some variant of 'help'. Then exit.
    # For example, a user could input any of the following to get command help:
    #  geo up -h
    #  geo up --h
    #  geo up --help
    #  geo up help
    if [[ $1 =~ ^-h$ ]] || [[ $1 =~ ^--help$ ]]; then
    # if [[ $1 =~ ^-*h(elp)? ]]; then
        "geo_${cmd}_doc"
        echo ''
        geo_show_msg_if_outdated
        # exit
        return
    fi

    # At this point we know that the command is valid and command help isn't being 
    # requested. So run the command.
    "geo_${cmd}" $1 $2 $3 $4 $5 $6 $7 $8
}

