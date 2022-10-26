#!/bin/bash
# This file is sourced from ~/.bashrc to make geo cli available from any bash terminal.
if [[ `whoami` = 'root' && -z $GEO_ALLOW_ROOT ]]; then echo 'ERROR: Do not run geo as root (sudo)'; exit; fi

# Init geo config directory if it doesn't exist.
export GEO_CLI_CONFIG_DIR="$HOME/.geo-cli"
[[ ! -d $GEO_CLI_CONFIG_DIR ]] && mkdir -p $GEO_CLI_CONFIG_DIR

# Init geo config file if it doesn't exist. This file stores key-value settings (i.e. username and password used to
# initialize geotabdemo database) for geo.
export GEO_CLI_CONF_FILE="$GEO_CLI_CONFIG_DIR/.geo.conf"
[[ ! -f $GEO_CLI_CONF_FILE ]] && touch $GEO_CLI_CONF_FILE

# Load all saved key-value settings into the environment.
# while read line; do
#     # Skip lines less than 3 characters long (i.e. the minimum key-value can be of the form x=1).
#     [[ ${#line} < 3 ]] && continue
#     # Expand env vars, then export
#     line=`echo $line | tr ' ' '='`
#     export `eval echo $line`
# done < $GEO_CLI_CONF_FILE

alias d-c='docker-compose'
# alias dcm=dc_geo
alias brc=". ~/.bashrc"
alias zrc=". ~/.zshrc"

# Gets the absolute path of the root geo-cli directory.
export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
export GEO_CLI_SRC_DIR="${GEO_CLI_DIR}/src"

# Load environment variable files.
[[ ! -d $GEO_CLI_CONFIG_DIR/env ]] && mkdir -p "$GEO_CLI_CONFIG_DIR/env"
if [[ $(ls -A $GEO_CLI_CONFIG_DIR/env) ]]; then
    for file in $GEO_CLI_CONFIG_DIR/env/*.sh ; do
        . $file
    done
fi

# Gives the path of the file that was passed in when the script was executed. Could be relative
# SOURCE="${BASH_SOURCE[0]}"
# DIR_NAME=`dirname $SOURCE`
# echo $SOURCE

# Import cli handlers to get access to all of the geo-cli commands and command names (through the COMMMAND array).
. "$GEO_CLI_SRC_DIR/utils/cli-handlers.sh"
. "$GEO_CLI_SRC_DIR/utils/log.sh"

function geo()
{
    # Log call.
    [[ $(geo_get LOG_HISTORY) == true ]] && echo "[$(date +"%Y-%m-%d_%H:%M:%S")] geo $@" >> ~/.geo-cli/history.txt

    while [[ $1 == --raw-output || $1 == --no-update-check ]]; do
        case "$1" in
             # Disabled formatted output if the --raw-output option is present.
            --raw-output ) export GEO_RAW_OUTPUT=true ;;
            --no-update-check ) export GEO_NO_UPDATE_CHECK=true ;;
        esac
        shift
    done

    # Check for updates in background process
    ( _geo_check_for_updates >& /dev/null & )

    # Check if the MyGeotab base repo dir has been set.
    if ! geo_haskey DEV_REPO_DIR && [[ "$1 $2" != "init repo" ]]; then
        log::warn 'MyGeotab repo directory not set.'
        log::detail 'Fix: Navigate to MyGeotab base repo (Development) directory, then run "geo init repo".\n'
    fi

    

    # Check if colour variables have been changed by the terminal (wraped in \[ ... \]). Reload everything if they have to fix.
    # This issue would cause coloured log output to start with '\[\] some log message'.
    if [[ $Green =~ ^'\['.*'\]' ]]; then
        . "$GEO_CLI_SRC_DIR/utils/cli-handlers.sh"
        # log::debug 'Colours reloaded'
    fi

    # Save the first argument in cmd var, then shift all other args.
    # So the 2nd arg becomes the 1st, 3rd becomes the 2nd, and so on.
    local cmd="$1"
    shift

    # Display help for all commands and quit if it was requested.
    # Help can be requested in any of the following ways:
    #   geo help
    #   geo h
    #   geo -h
    #   geo --help
    if [[ $cmd =~ ^-*h(elp)? ]]; then
        log::detail -bu 'Available commands:'
        geo_help
        _geo_show_msg_if_outdated
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
        _geo_show_msg_if_outdated
        return
    fi

    # This can happen after force updating because we re-source .bashrc after updating. Just ignore it.
    [[ $cmd == -f ]] && return
        
    # Quit if the command isn't valid
    if [[ -z `_geo_cmd_exists $cmd` ]]; then
        [[ ${#cmd} == 0 ]] && echo && log::warn "geo was run without any command"
        [[ ${#cmd} -gt 0 ]] && echo && log::warn "Unknown command: '$cmd'"
        
        # geotab_logo
        # geo_logo

        echo
        log::verbose 'For help, run the following:'
        log::detail '    geo --help'
        log::verbose 'or'
        log::detail '    geo -h'
        _geo_show_msg_if_outdated
        # exit
        return
    fi

    # Show cmd help if the first arg to a command is some variant of 'help'. Then exit.
    # For example, a user could input any of the following to get command help:
    #  geo up -h
    #  geo up --h
    #  geo up --help
    #  geo up help
    # if [[ $1 =~ ^-h$ ]] || [[ $1 =~ ^--help$ ]]; then
    if [[ $1 =~ ^-*h(elp)? ]]; then
        "geo_${cmd}_doc"
        echo
        _geo_show_msg_if_outdated
        # exit
        return
    fi

    check_for_docker_group_membership

    local was_successfull=true

    # At this point we know that the command is valid and command help isn't being 
    # requested. So run the command.
    "geo_${cmd}" "$@" || was_successfull=false
    
    # Don't show outdated msg if update was just run.
    [[ $cmd != update ]] && _geo_show_msg_if_outdated

    [[ $was_successfull == true ]]
}

function check_for_docker_group_membership() {
    local docker_group=$(cat /etc/group | grep 'docker:')
    if [[ -z $docker_group || ! $docker_group =~ "$USER" ]]; then
        log::warn 'You are not a member of the docker group. This is required to be able to use the "docker" command without sudo.'
        if prompt_continue "Add your username to the docker group? (Y|n): "; then
            [[ -z $docker_group ]] && sudo groupadd docker
            sudo usermod -aG docker $USER || { log::Error "Failed to add '$USER' to the docker group"; return 1; }
            log::success "Added $USER to the docker group"
            log::warn 'You may need to fully log out and then back in again for these changes to take effect.'
            newgrp docker
        else
            log::warn "geo-cli won't be able to use docker until you're user is added to the docker group"
        fi
    fi
}

# Run geo if this file was executed (instead of sourced) as a stand-alone script and arguments were passed in.
if [[ -n $@ ]]; then
    geo "$@"
fi