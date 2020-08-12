#!/bin/bash
# This file is sourced from ~/.bashrc to make the constants and the geo cli
# available from any bash terminal.

export GEO_CONFIG_DIR="$HOME/.geo-cli"
[ ! -d $GEO_CONFIG_DIR ] && mkdir -p $GEO_CONFIG_DIR

export GEO_CONF_FILE="$GEO_CONFIG_DIR/.geo.conf"
[ ! -f $GEO_CONF_FILE ] && touch $GEO_CONF_FILE
# export GEO_DEV_CREDENTIALS="$HOME/.geo-cli/.env"

# export GEO_CLI_DIR="$GEO_CONFIG_DIR/cli"

while read line; do
    [[ ${#line} < 3 ]] && continue
    export `eval echo $line` # Expand env vars, then export
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