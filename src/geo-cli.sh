#!/bin/bash
# This file is sourced from ~/.bashrc to make geo cli available from any bash terminal.
if [[ `whoami` = 'root' ]]; then echo 'ERROR: Do not run geo as root (sudo)'; exit; fi

# Init geo config directory if it doesn't exist.
export GEO_CONFIG_DIR="$HOME/.geo-cli"
[ ! -d $GEO_CONFIG_DIR ] && mkdir -p $GEO_CONFIG_DIR

# Init geo config file if it doesn't exist. This file stores key-value settings (i.e. username and password used to
# initialize geotabdemo database) for geo.
export GEO_CONF_FILE="$GEO_CONFIG_DIR/.geo.conf"
[ ! -f $GEO_CONF_FILE ] && touch $GEO_CONF_FILE

# Load all saved key-value settings into the environment.
while read line; do
    # Skip lines less than 3 characters long (i.e. the minimum key-value can be of the form x=1).
    [[ ${#line} < 3 ]] && continue
    # Expand env vars, then export
    export `eval echo $line`
done < $GEO_CONF_FILE

# [ -z $GEO_REPO_DIR ] && echo REPO DIRECTORY NOT set

# Import cli handlers to get access to all of the command names (through functions calls and the COMMMAND array)
# . ~/.geo-cli/cli/utils/cli-handlers.sh

alias d-c='docker-compose'
alias dcm=dc_geo
# alias dcm="docker-compose -f $GEO_REPO_DIR/env/full/docker-compose.yml -f $GEO_REPO_DIR/env/full/docker-compose-geo.yml"
alias brc=". ~/.bashrc"
alias zrc=". ~/.zshrc"

# # Auto-complete
# completions=(
#     "${COMMANDS[@]}"
#     )

# # Doesn't work for some reason
# # complete -W "${completions[@]}" geo

# # Get list of completions separated by spaces (required as imput to complete command)
# comp_string=`echo "${completions[@]}"`
# complete -W "$comp_string" geo

export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
export GEO_SRC_DIR="${GEO_CLI_DIR}/src"

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

