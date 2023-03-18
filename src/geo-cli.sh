#!/bin/bash
[[ -z $BASH_VERSION ]] \
    && echo "ERROR: geo-cli.sh: Not sourced into a BASH shell! This file can be sourced (to load the geo command) or executed directly, but it must do so in a BASH shell environtment ONLY. Example: 'source geo-cli.sh; geo <args>' OR 'geo-cli.sh <args>)' 4 geo-cli won't work properly in other shell environments." && exit 1

# This file is sourced from ~/.bashrc to make geo cli available from any bash terminal.
if [[ `whoami` = 'root' && -z $GEO_ALLOW_ROOT ]]; then echo 'ERROR: Do not run geo as root (sudo)'; exit; fi

# echo "install.sh: \${BASH_SOURCE[0]} =  ${BASH_SOURCE[0]}"
# cat ~/.config/fish/config.fish
# set -E
# err_trap() {
#     echo "err_trap: args: $*"
#     echo "err_trap: ${FUNCNAME[*]}"
#     # echo "err_trap: ${BASH_SOURCE[*]}"
# }
# trap 'err_trap source "${BASH_SOURCE[0]}[$LINENO]" trace "${FUNCNAME[*]}"' ERR

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
[[ -z $GEO_CLI_DIR ]] \
    && export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
if [[ -z $GEO_CLI_DIR || ! -f $GEO_CLI_DIR/install.sh ]]; then
    msg="cli-handlers.sh: ERROR: Can't find geo-cli repo path."
    [[ ! -f $HOME/data/geo/repo-dir ]] && echo "$msg" && exit 1;
    # Running from a symbolic link from geo-cli.sh. Try to get geo-cli from config dir.
    GEO_CLI_DIR="$(cat "$GEO_CLI_CONFIG_DIR/data/geo/repo-dir")"
    [[ ! -f $GEO_CLI_DIR/install.sh ]] && echo "$msg" && exit 1;

fi
export GEO_CLI_SRC_DIR="${GEO_CLI_DIR}/src"

# Load environment variable files.
[[ ! -d $GEO_CLI_CONFIG_DIR/env ]] && mkdir -p "$GEO_CLI_CONFIG_DIR/env"
if [[ $(ls -A $GEO_CLI_CONFIG_DIR/env) ]]; then
    for file in $GEO_CLI_CONFIG_DIR/env/*.sh ; do
        . "$file"
    done
fi

# Gives the path of the file that was passed in when the script was executed. Could be relative
# SOURCE="${BASH_SOURCE[0]}"
# DIR_NAME=`dirname $SOURCE`
# echo $SOURCE
# EMOJI_CHECK_MARK_GREEN='\033[0;32m✔\033[0m'
# EMOJI_RED_X_SMALL_RED='\033[0;31m✘\033[0m'
# =$'\033[32m'
# red_color=$'\033[41m'
# exit_color=$normal_color

# Define error handlers before loading cli-handlers.sh, then set again with color afterwards.
# This is because we need to have util::array_concat imported.
export GEO_ERR_TRAP='${BASH_SOURCE[0]##*/}[$LINENO]:${FUNCNAME:-FuncNameNull}: '
export PS4=".${GEO_ERR_TRAP}"
export PS4='.${BASH_SOURCE[0]##*/}[$LINENO]:${FUNCNAME:-FuncNameNull}: '

# Import cli handlers to get access to all of the geo-cli commands and command names (through the COMMANDS array).
# shellcheck source=cli/cli-handlers.sh
. "$GEO_CLI_SRC_DIR/cli/cli-handlers.sh"

exit_color() {
    exit_code=$?
    if [ "$exit_code" != 0 ]; then
        echo -e "$Red✘"
    else
        echo -e "$Green✔"
    fi
    return "$exit_code"
}
# '$(echo -e ${log_RETURN_CODE_TO_EMOJI[$?]}-)'
# ret_emoji='$(exit_color)'
# ret_emoji='$([[ $? -eq 0 ]] && echo "\033[0;32m✔\033[0m" || echo "\033[0;32m✔\033[0m")'
trap_string_parts=('$(exit_color) ' "$BCyan" '${BASH_SOURCE[0]##${HOME}*/}' "${Purple}" '\[$LINENO]:' "${Yellow}" '${FUNCNAME:-FuncNameNull}:' "$Off ")
#trap_string_parts=('$(exit_color ) ' "\[$BCyan\]" '${BASH_SOURCE[0]##${HOME}*/}' "\[${Purple}\]" '[$LINENO]:' "\[${Yellow}\]" '${FUNCNAME:-FuncNameNull}:'\["$Off\] ")
#trap_string_parts=("echo -en " '"' '$(exit_color ) ' "\[$BCyan\]" '${BASH_SOURCE[0]##${HOME}*/}' "\[${Purple}\]" '[$LINENO]:' "\[${Yellow}\]" '${FUNCNAME:-FuncNameNull}:'\["$Off\] " '"')
#GEO_ERR_TRAP1="echo -en \"$(util::array_concat -z trap_string_parts)\""
#***  GEO_ERR_TRAP="$(echo -en "$(util::array_concat -z trap_string_parts)")"
#GEO_ERR_TRAP="echo -en \"$(util::array_concat -z trap_string_parts)\""
#GEO_ERR_TRAP1="$"
#***  geo_err_trap() {
#***      GEO_ERR_TRAP="$(util::array_concat -z trap_string_parts)"
#***       eval $GEO_ERR_TRAP 2>&1 | grep -Ev 'config-file|cfg_.*|geo_get|log::|util::|gitprompt|bashrc-utils'
#***  }
#type util::array_concat
#***  PS4='.${geo_err_trap}'

#PS4=".${GEO_ERR_TRAP}"


# export GEO_ERR_TRAP="$BCyan"${BASH_SOURCE[0]##${HOME}*/}${Purple}[$LINENO]:${Yellow}${FUNCNAME:-FuncNameNull}:$Off '
# export GEO_ERR_TRAP='${BASH_SOURCE[*]}[$LINENO]: '
# export GEO_ERR_TRAP='${BASH_SOURCE[*]}[$LINENO]: '
# export GEO_ERR_TRAP="\$BCyan\${BASH_SOURCE[0]}\${Purple}[\$LINENO]:\${Yellow}\${FUNCNAME:-FuncNameNull0}: \$Off"
# export GEO_ERR_TRAP='${BASH_SOURCE[0]##*/}[$LINENO]:${FUNCNAME:-FuncNameNull}: '
#export GEO_ERR_TRAP="$BCyan\${BASH_SOURCE[0]##*/}${Purple}[\$LINENO]:${Yellow}\${FUNCNAME:-FuncNameNull}: $Off"
# export GEO_ERR_TRAP="$BCyan\${BASH_SOURCE[1]}.\${BASH_SOURCE[0]}${Purple}[\$LINENO]:${Yellow}\${FUNCNAME:-FuncNameNull}: $Off"
# export PS4='.${BASH_SOURCE[0]##*/}[$LINENO]:${FUNCNAME:-FuncNameNull}: '
# export PS4='.${BASH_SOURCE[*]}[$LINENO]:  '
# export PS4='.${BASH_SOURCE[0]##*/}[$LINENO]:  '
# export GEO_ERR_TRAP='${BASH_SOURCE[0]##*/}[$LINENO]: '
export GEO_DEV_MODE=false

export GEO_RAW_OUTPUT=false
export GEO_NO_UPDATE_CHECK=false

# set -E
# trap "$GEO_ERR_TRAP" ERR

# function geo() {
#     if [[ $(@geo_get debug) == true || -n $GEO_DEBUG ]]; then
#         export GEO_DEBUG=true
#         # set -E
#         # trap "$GEO_ERR_TRAP" ERR

#     fi
#     # TODO: Allow commands to specify if they should not run in a subshell (to persist a dir change (for@geo_cd), for example).
#     if [[ $(@geo_get dev_mode) == true ]] || $GEO_DEV_MODE; then
#         export GEO_DEV_MODE=true
#         (
#             __geo "$@"
#         )
#     else
#         __geo "$@"
#     fi
# }

function geo() {

#     set -E
#     set -e
#     trap "geo_err_trap" ERR
#     trap "$GEO_ERR_TRAP" ERR
    # Log call.
    [[ $(@geo_get LOG_HISTORY) == true ]] && echo "[$(date +"%Y-%m-%d_%H:%M:%S")] geo $*" >> ~/.geo-cli/history.txt

    # Suppresses some output and prompts when false, used by the ui to reduce the output/formatting of the text returned
    # by geo.
    export GEO_INTERACTIVE=true
    export GEO_SILENT=false
    # [[ $- =~ i ]] && GEO_INTERACTIVE=false

    local OPTIND
    while [[ $# -gt 0 && $1 =~ ^-{1,2} ]]; do
    # echo "arg = $1"
    # while [[ $# -gt 0 && $1 == --raw-output || $1 == --no-update-check ]]; do
        # Extracts the option prefix (- or --). Removes everything from to end of the string up to and including the first hyphen.
        # A hyphen is then concatenated to the result to account for the one that was removed.
        local opt_prefix="${1%-*}-"
        # Strips '-' or '--' option prefix.
        local arg="${1/-?}"
        arg="${arg:-$opt_prefix}"
        case "$arg" in
             # Disabled formatted output if the --raw-output option is present.
            raw-output | r ) GEO_RAW_OUTPUT=true ;;
            no-update-check | U) GEO_NO_UPDATE_CHECK=true ;;
            non-interactive | I ) GEO_INTERACTIVE=false ;;
            # Runs the geo-cmd ina new interactive terminal.
            launch-in-term | ui | T)
                shift
                gnome-terminal --title="geo ${@}" -- bash -i -c "echo ${*}; echo -e \"\nPress Enter to exit\"; read"
                echo "Launching terminal..."
                return
                ;;
            silent | s) GEO_SILENT=true ;;
            -- )  break ;;
            # - ) log::Error "${FUNCNAME}: '-' is not an option."; return 1 ;; # TODO: Rerun prev cmd
            * ) break ;; # End of options.
        esac
        shift
    done
    # e $GEO_RAW_OUTPUT
    # shift $((OPTIND - 1))

    # Check for updates in background process
    ( _geo_check_for_updates >& /dev/null & )

    # Check if the MyGeotab base repo dir has been set.
    if ! @geo_haskey DEV_REPO_DIR && [[ "$1 $2" != "init repo" ]]; then
        log::warn 'MyGeotab repo directory not set.'
        log::detail "Fix: Run $(txt_underline geo init repo) and select from possible repo locations that geo-cli finds. Alternatively, navigate to the MyGeotab base repo (Development) directory, then run $(txt_underline geo init repo) for geo-cli to use the current directory as the repo root.\n"
    fi

    # Check if colour variables have been changed by the terminal (wraped in \[ ... \]). Reload everything if they have to fix.
    # This issue would cause coloured log output to start with '\[\] some log message'.
    if [[ $Green =~ ^'\['.*'\]' ]]; then
        . "$GEO_CLI_SRC_DIR/cli/cli-handlers.sh"
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
    re='^-{1,2}h(elp)?$'
    if [[ $cmd =~ $re ]]; then
        log::detail -bu 'Available commands:'
        @geo_help
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
        @geo_version
        _geo_show_msg_if_outdated
        return
    fi

    # This can happen after force updating because we re-source .bashrc after updating. Just ignore it.
    [[ $cmd == -f ]] && return

    # Quit if the command isn't valid
    if ! _geo__is_registered_cmd "$cmd"; then
        [[ -z $cmd ]] && echo && log::warn "geo was run without any command"
        [[ -n $cmd ]] && echo && log::warn "Unknown command: '$cmd'"

        # geotab_logo
        # geo_logo

        echo
        _geo_who_help_message
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
        "@geo_${cmd}_doc"
        echo
        _geo_show_msg_if_outdated
        # exit
        return
    fi

    check_for_docker_group_membership

    local was_successful=true

    # At this point we know that the command is valid and command help isn't being
    # requested. So run the command.
    "@geo_${cmd}" "$@" || was_successful=false

    # Don't show outdated msg if update was just run.
    [[ $cmd != update ]] && _geo_show_msg_if_outdated

    trap '' ERR
    [[ $was_successful == true ]]
}

_geo_who_help_message() {
    log::verbose 'For help, run the following:'
    log::detail '    geo --help'
    log::verbose 'or'
    log::detail '    geo -h'
}

function check_for_docker_group_membership() {
    local docker_group=$(cat /etc/group | grep 'docker:')
    if [[ -z $docker_group || ! $docker_group =~ $USER ]]; then
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
if [[ -n $* ]]; then
    geo "$@"
fi
