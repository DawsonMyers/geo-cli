#!/bin/bash
[[ -z $BASH_VERSION ]] \
    && echo "ERROR: geo:cli-handlers.sh: Not sourced into a BASH shell! This file MUST be sourced, not executed (i.e. 'source cli-handlers.sh' vs. '[bash|sh|zsh|fish] cli-handlers.sh)' into a BASH shell environtment by the main geo-cli file (geo-cli.sh) ONLY. geo-cli won't work properly in other shell environments." && exit 1

# This file contains all geo-cli command logic.
# All geo-cli commands will have at least 2 functions defined that follow the following format: @geo_<command_name> and
# @geo_<command_name>_doc (e.g. geo db has functions called @geo_db and @geo_db_doc). These functions are called from src/geo-cli.sh.

# Gets the absolute path of the root geo-cli directory.
[[ -z $GEO_CLI_DIR ]] && export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"

if [[ -z $GEO_CLI_DIR || ! -f $GEO_CLI_DIR/install.sh ]]; then
    msg="cli-handlers.sh[$LINENO]: ERROR: Can't find geo-cli repo path."
    [[ ! -f $HOME/.geo-cli/data/geo/repo-dir ]] && echo "$msg" && exit 1
    # Running via symbolic link from geo-cli.sh. Try to get geo-cli from config dir.
    GEO_CLI_DIR="$(cat "$HOME/.geo-cli/data/geo/repo-dir")"
    [[ ! -f $GEO_CLI_DIR/install.sh ]] && echo "$msg" && exit 1

fi

geo-cli::import() {
    [[ ! -v LOADED_MODULES ]] && declare -A LOADED_MODULES && export LOADED_MODULES
    [[ -z $1 ]] && log::Error "geo-cli::import expects a file to import." && return 1
    local file_name=$(basename $1)
    [[ -n ${LOADED_MODULES[$file_name]} ]] && return
    geo_dir=$(cat ~/.geo-cli/data/geo/repo-dir)
    set -e
    echo "eval source $geo_dir/$1"
    LOADED_MODULES[$file_name]=true
    set +e
}

kilobyte=1024
megabyte=$(( kilobyte * 1000))
export MAX_CONFIG_FILE_SIZE=$(( megabyte * 1000))

export GEO_CLI_SRC_DIR="${GEO_CLI_DIR}/src"
export GEO_CLI_UTILS_DIR="${GEO_CLI_SRC_DIR}/utils"

# Import colour constants/functions and config file read/write helper functions.
# shellcheck source=../utils/colors.sh

$(geo-cli::import 'src/utils/colors.sh')

#. $GEO_CLI_UTILS_DIR/colors.sh
# shellcheck source=../utils/config-file-utils.sh
. $GEO_CLI_UTILS_DIR/config-file-utils.sh
# shellcheck source=../utils/log.sh
. $GEO_CLI_UTILS_DIR/log.sh
# shellcheck source=../utils/util.sh
. $GEO_CLI_UTILS_DIR/util.sh

# Set up config paths (used to store config info about geo-cli)
export GEO_CLI_CONFIG_DIR="$HOME/.geo-cli"
export GEO_CLI_CONF_FILE="$GEO_CLI_CONFIG_DIR/.geo.conf"
export GEO_CLI_CONF_JSON_FILE="$GEO_CLI_CONFIG_DIR/.geo.conf.json"
export GEO_CLI_AUTOCOMPLETE_FILE="$GEO_CLI_CONFIG_DIR/geo-cli-autocompletions.txt"
export GEO_CLI_SCRIPT_DIR="${GEO_CLI_CONFIG_DIR}/scripts"

# The name of the base postgres image that will be used for creating all geo db containers.
export IMAGE=geo_cli_db_postgres
export GEO_DB_PREFIX=$IMAGE
export OLD_GEO_DB_PREFIX=geo_cli_db_postgres11

# A list of all the top-level geo commands.
# This is used in geo-cli.sh to confirm that the first param passed to geo (i.e. in 'geo db ls', db is the top-level command) is a valid command.
export COMMANDS=()
export ALIASES=()

#TODO: Update this comment.
# Maps geo-cli command names to their corresponding function names. This makes command alias possible.
# Example: 'ui' is aliased to 'indicator', so calling 'geo ui' is equivalent to 'geo indicator'
# Some aliases:
#     * geo db/database => geo db === geo database
#       - COMMAND_FUNCTION_NAMES[db] = @geo_db
#       - COMMAND_FUNCTION_NAMES[database] = @geo_db
#     * geo ui/indicator
declare -A COMMAND_INFO
declare -A SUBCOMMANDS
declare -A SUBCOMMAND_COMPLETIONS
export CURRENT_COMMAND=''
export CURRENT_SUBCOMMAND=''
export CURRENT_SUBCOMMANDS=()

_geo_get_cmd_func_name() {
    local get_doc_func=false
    [[ $1 == --doc  ]] && get_doc_func=true && shift

    local root_cmd_name=$(_get_root_cmd_name $1)
    $get_doc_func \
        && echo "${COMMAND_INFO[$root_cmd_name,doc]}" \
        || echo "${COMMAND_INFO[$root_cmd_name]}"
}

_geo_ls_cmd_info() {
    local count=${#COMMAND_INFO}
    echo "COMMAND_INFO[$count]"
    local i=0
    local keys=$(echo "${!COMMAND_INFO[@]}" | tr ' ' '\n' | sort)
    for key in $keys; do
        echo "  COMMAND_INFO[$key] = ${COMMAND_INFO[$key]}" || echo "${COMMAND_INFO[$key]}"
    done
}

current_command=

# Adds the provided command name to the COMMANDS array so that it can be called via 'geo <cmd_name>'. This each geo-cli
# command must call this function once when it is defined. Example:
#  @register_geo_cmd 'db'
#  @geo_db_doc() {...}
#  @geo_db() {...}
@register_geo_cmd() {
    current_command=$1
    local cmd_name=$1
    shift
#    evar cmd_name
    [[ -z $cmd_name || ! $cmd_name =~ ^([a-z][-a-z_]*)$ ]] \
        && log::Error "'$cmd_name' is not a valid geo-cli command name." \
        && return 1
    COMMAND_INFO[$cmd_name]="@geo_${cmd_name}"
    COMMAND_INFO[$cmd_name,doc]="@geo_${cmd_name}_doc"
    COMMAND_INFO[$cmd_name,source]="${BASH_SOURCE[1]}, line: ${BASH_LINENO[0]}"

    # Only add once.
    [[ ! ${COMMAND_INFO[_commands]} =~ $$cmd_name ]] && COMMAND_INFO[_commands]+=" $cmd_name"

    while [[ $1 == --alias && -n $2 ]]; do
        local alias_name="$2"

        [[ -z $alias_name || ! $alias_name =~ ^([a-z][-a-z_]+)$ ]] \
            && log::Error "'$alias_name' is not a valid geo-cli command alias for '$cmd_name'." \
            && return 1
         @register_geo_cmd_alias "$cmd_name" "$alias_name"
         shift 2
     done
}

_get_root_cmd_name() {
    local cmd_name=$1
    local cmd_alias_to="${COMMAND_INFO[$cmd_name,alias_to]}"
    # Basically Union Find
    while [[ -n $cmd_alias_to ]]; do
        cmd_name=$cmd_alias_to
        cmd_alias_to="${COMMAND_INFO[$cmd_name,alias_to]}"
    done
    echo "$cmd_name"
    return
}

@register_geo_cmd_alias() {
    local cmd_name=$1
    local alias_name=$2
    [[ $# -eq 1 ]] && cmd_name=$current_command && alias_name=$1
    [[ -z $cmd_name || -z $alias_name ]] \
        && log::Error "Command name or alias cannot be empty. (name: $cmd_name, alias: $alias_name)" \
        && return 1
    ALIASES+=("$alias_name")
    COMMAND_INFO[$alias_name]="${COMMAND_INFO[$cmd_name]}"
    COMMAND_INFO[$alias_name,doc]="${COMMAND_INFO[$cmd_name,doc]}"
    COMMAND_INFO[$alias_name,alias_to]=$cmd_name
    local cmd_aliases="${COMMAND_INFO[$cmd_name,aliases]}"
    [[ -z ${COMMAND_INFO[$cmd_name,aliases]} ]] \
        && COMMAND_INFO[$cmd_name,aliases]+="$alias_name"
    [[ ! $cmd_aliases =~ $alias_name ]] && COMMAND_INFO[$cmd_name,aliases]+=",$alias_name"
    [[ ${COMMAND_INFO[$cmd_name,aliases]} =~ $alias_name ]]
}

#* export GEO_ERR_TRAP='$BCyan\${BASH_SOURCE[0]##\${HOME}*/}${Purple}[\$LINENO]:${Yellow}\${FUNCNAME:-FuncNameNull}: $Off'
# export GEO_ERR_TRAP="$BCyan\${BASH_SOURCE[0]##\${HOME}*/}${Purple}[\$LINENO]:${Yellow}\${FUNCNAME:-FuncNameNull}: $Off"
#export GEO_ERR_TRAP="$BCyan\${BASH_SOURCE[0]}${Purple}[\$LINENO]:${Yellow}\${FUNCNAME:-FuncNameNull}: $Off"
# The set -x debug line prefix
# export PS4=".${GEO_ERR_TRAP}"
#PS4='.'
# export PS4='.${BASH_SOURCE[0]##*/}[$LINENO]:${FUNCNAME:-FuncNameNull} '
# PS4='.${BASH_SOURCE[0]}[$LINENO]: '
# PS4=$(log::code "line: $LINENO: ")
# PS4=$(log::code ${BASH_SOURCE[0]##*/}" $LINENO:

# set -eE -o functrace
# set -x
# failure() {
#   local lineno=$1
#   local msg=$2
#   local func=$3
#   echo "Failed at $lineno: $msg in function: ${func}"
# }
# trap 'failure ${LINENO} "$BASH_COMMAND" ${FUNCNAME[0]}' ERR

#######################################################################################################################
#### Create a new command (e.g. 'geo <some_new_command>')
# First argument commands
#######################################################################################################################
## First argument commands
#----------------------------------------------------------
# Each command definition requires three parts for it to be available as a command to geo-cli (i.e. 'db' is the command in 'geo db'):
#   1. Its name is added to the COMMANDS array
#        - This array lets geo check if a command exists. If geo is run with an unknown command, an error message will
#          shown to the user.
#   2. Command documentation function (for printing help)
#        - This function is run when the user requests help via 'geo <command> --help'. Also, these functions are called
#           for every command in the COMMANDS array when the user runs 'geo help' or 'geo -h'.
#   3. Command function
#       - The actual command that gets executed when the user runs 'geo <your_command>'. All the arguments passed to
#           geo following the command name will be passed to this function as positional arguments (e.g.. $1, $2, ...).
#
# The three parts above have the following structure:
#   COMMAND+=('command')
#  @geo_command_doc() {...}
#  @geo_command() {...}
# Example for the definition of 'geo db' command:
#   COMMAND+=('db')
#  @geo_db_doc() {...}
#  @geo_db() {...}
#
## Start off a new command definition by making a copy of the template above and fill in your own logic.
# Some example documentation functions are also included in the template. They take care of formatting/colouring the
# text when printing it out for the user. Replace the example documentation with your own.
#------------------------------------------------------------
# Template:
#######################################################################################################################
# COMMANDS+=('command')
#@geo_command_doc() {
#   doc_cmd 'command'
#       doc_cmd_desc 'Commands description.'
#
#       doc_cmd_sub_cmd_title
#
#       doc_cmd_sub_cmd 'start [options] <name>'
#           doc_cmd_sub_cmd_desc 'Creates a versioned db container and...'
#           doc_cmd_sub_option_title
#               doc_cmd_sub_option '-y'
#                   doc_cmd_sub_option_desc 'Accept all prompts.'
#               doc_cmd_sub_option '-d <database name>'
#                   doc_cmd_sub_option_desc 'Sets the name of the db to...'
#
#       doc_cmd_examples_title
#           doc_cmd_example 'geo db start 11.0'
#           doc_cmd_example 'geo db start -y 11.0'
# }
#@geo_command() {
#
# }
#######################################################################################################################
#
# Also, add a section to the README with instructions on how to use your command.
#

#
#*** Short/long option parsing template
#######################################################################################################################
#** Parses both short and long options
# some_function() {
    # local use_docker=false interactive=false find_unreliable=false
    # while [[ $1 =~ ^-+ ]]; do
    #     case "${1}" in
    #         -d | --docker) use_docker=true ;;
    #         -i) interactive=true ;;
    #         -n)
    #             local option_arg="$2"
    #             [[ ! $option_arg =~ $is_number_re ]] && log::Error "The $1 option requires a number as an argument." && return 1
    #             for ((i = 1; i < $option_arg; i++)); do
    #                 seeds+=(0)
    #             done
    #             find_unreliable='true'
    #             shift
    #             ;;
    #         *) log::Error "Invalid option: '$1'" && return 1 ;;
    #     esac
    #     shift
    # done



    #*** Less boilerplate
    # while [[ $1 =~ ^-+ ]]; do
    #     case "${1}" in
    #         -d | --docker) use_docker=true ;;
    #         -n) name="$OPTARG" ;;
    #         *) log::Error "Invalid option: '$1'" && return 1 ;;
    #     esac
    #     shift
    # done
#*
#######################################################################################################################
#**  Parses short options only using getopts
# some_function() {
    # local OPTIND
    # local add_padding=true delimiter=' '
    # while getopts "Pv:d:" opt; do
    #     case "${opt}" in
    #         P ) add_padding=false ;;
    #         d ) delimiter="${OPTARG:-$delimiter_default}" ;;
    #         v )
    #             key_name="$OPTARG"
    #             [[ -z $key_name ]] && log::Error "log::keyvalue: The variable cannot be empty (-v <variable>)." && return 1
    #             ;;
    #         # Standard error handling.
    #         : ) log::Error "Option '${OPTARG}' expects an argument."; return 1 ;;
    #         \? ) log::Error "Invalid option: ${OPTARG}"; return 1 ;;
    #     esac
    # done
    # shift $((OPTIND - 1))
#}

    # local opt=false
    # local opt_arg=
    # local OPTIND
    # while getopts "Pv:a:" opt; do
    #     case "${opt}" in
    #         a ) opt=false ;;
    #         b ) opt_arg="$OPTARG" ;;
    #         # Standard error handling.
    #         : ) log::Error "Option '${OPTARG}' expects an argument."; return 1 ;;
    #         \? ) log::Error "Invalid option: ${OPTARG}"; return 1 ;;
    #     esac
    # done
    # shift $((OPTIND - 1))
#######################################################################################################################

# The directory path to this file.
export FILE_DIR="$(dirname "${BASH_SOURCE[0]}")"

export GEO_CLI_COMMAND_DIR="$FILE_DIR/commands"
export GEO_CLI_USER_COMMAND_DIR="$GEO_CLI_CONFIG_DIR/data/commands"

repo_cmd_files="$(find "$GEO_CLI_SRC_DIR/cli/commands" -name '*.cmd.sh' 2>/dev/null)"
export GEO_COMMAND_REPO_FILE_PATHS=($repo_cmd_files) #"$(find "$GEO_CLI_SRC_DIR/cli/commands" -name '*.cmd.sh' 2> /dev/null)"
user_cmd_files="$(find "$GEO_CLI_USER_COMMAND_DIR" -name '*.cmd.sh' 2>/dev/null)"
export GEO_COMMAND_USER_FILE_PATHS=($user_cmd_files)

export GEO_COMMAND_FILE_PATHS=("${GEO_COMMAND_REPO_FILE_PATHS[@]}" "${GEO_COMMAND_USER_FILE_PATHS[@]}")

# Load command files.
if [[ -n ${#GEO_COMMAND_FILE_PATHS[@]} ]]; then
    for command_file in "${GEO_COMMAND_FILE_PATHS[@]}"; do
        . "$command_file"
    done
fi

_geo_image__exists() {
    docker image inspect "$1" &>/dev/null
}

_geo_image__get_name() {
    local repo_pg_version=$(_geo_db__get_pg_version_from_dockerfile)
    local pg_version=${1:-$repo_pg_version}
    local image_name="$IMAGE"
    [[ -n $pg_version ]] && image_name+="_${pg_version}"
    echo -n "$image_name"
}

_geo_check_db_image() {
    local repo_pg_version=$(_geo_db__get_pg_version_from_dockerfile)
    local image_name="$(_geo_image__get_name)"
    # local image=$(docker image ls | grep "$IMAGE")
    if ! _geo_image__exists "$image_name"; then
        log::detail "The Postgres version for the current repo is '$repo_pg_version', but there isn't a geo-cli image built for it yet."
        prompt_continue "Do you want to create one? (Y|n): " \
            || return 1
        @geo_image create
    fi
}

# Make sure that the postgres version in the main geo-cli myg db image is up to date.
_geo_check_db_image_pg_version() {
    local image_name=$(_geo_image__get_name)
    [[ -n $1 ]] && image_name="$1"
    local image_postgres_version=$(_geo_db__get_pg_version_from_docker_object "$image_name")
    if [[ -n $image_postgres_version ]] && ((image_postgres_version < 11)); then
        log::caution "Your current geo-cli db image is out of date. Its Postgres version is $image_postgres_version and the minimum supported version is 11."
        if ! prompt_continue "Rebuild the image now to update Postgres? (Y|n): "; then
            return 1
        fi
        @geo_image create
    fi
}

#######################################################################################################################
@register_geo_cmd 'image'
@geo_image_doc() {
    doc_cmd 'image'
    doc_cmd_desc 'Commands for working with db images.'
    doc_cmd_sub_cmd_title
        doc_cmd_sub_cmd 'create [-f | -v <pg version>]'
            doc_cmd_sub_cmd_desc 'Creates the base Postgres image configured to be used with geotabdemo.'
            doc_cmd_sub_option_title
                doc_cmd_sub_option '-v <pg version>'
                    doc_cmd_sub_option_desc "The Postgres version for the image."
                doc_cmd_sub_option -f
                    doc_cmd_sub_option_desc "Force the build to build without using cached layers."
        doc_cmd_sub_cmd 'remove [image name]'
            doc_cmd_sub_cmd_desc 'Removes the provided image if an image name was passed in. Otherwise, the base geo-cli Postgres image is removed.'
        doc_cmd_sub_cmd 'ls'
            doc_cmd_sub_cmd_desc 'List existing geo-cli Postgres images.'
        doc_cmd_examples_title
    doc_cmd_example 'geo image create'
}
@geo_image() {
    local cmd=$1
    local pg_version=
    [[ $cmd =~ ^-|^$ ]] \
        && log::Error "$FUNCNAME: '$cmd' is not a valid command name" && return 1
    shift

    # local OPTIND
    # while getopts ":v:" opt; do
    #     case "${opt}" in
    #         v) [[ $OPTARG =~ ^[[:digit:]]+$ ]] && pg_version=$OPTARG ;;
    #         :)
    #             log::Error "Option '${OPTARG}' expects an argument."
    #             return 1
    #             ;;
    #         \?)
    #             log::Error "Invalid option: ${OPTARG}"
    #             return 1
    #             ;;
    #     esac
    # done
    # shift $((OPTIND - 1))

    case "$cmd" in
        # TODO: This needs to take the image name as an arg or prompt the user for one to remove.
        rm | remove)
            docker image rm "${1:$IMAGE}"
            # if [[ -z $2 ]]; then
            #     log::Error "No database version provided for removal"
            #     return
            # fi
            # @geo_db_rm "$2"
            return
            ;;
        create)
            local image_name=
            local options=
            local OPTIND
            while getopts ":v:n:f" opt; do
                case "${opt}" in
                    v)
                        pg_version="$OPTARG"
                        ! [[ $pg_version =~ ^[[:digit:]]+$ ]] \
                            && log::Error "geo image create: The -v option must be a number and valid Postgres version. '$pg_version' is invalid." \
                            && return 1
                        ;;
                    n)
                        # TODO: Add logic for this.
                        image_name=$OPTARG
                        # ! [[ $pg_version =~ ^[[:digit:]]+$ ]] \
                        #     && log::Error "geo image create: The -v option must be a number and valid Postgres version. '$pg_version' is invalid." \
                        #     && return 1
                        ;;
                    f) force_no_cache_rebuild=true options=--no-cache ;;
                    :)
                        log::Error "Option '${OPTARG}'  expects an argument."
                        return 1
                        ;;
                    \?)
                        log::Error "Invalid option: ${OPTARG}"
                        return 1
                        ;;
                esac
            done
            shift $((OPTIND - 1))

            log::status 'Building image...'
            local repo_dir="$(@geo_get DEV_REPO_DIR)"
            local docker_pg_dir="${repo_dir}/Checkmate/Docker/postgres"
            local dockerfile="Debug.Dockerfile"

            (
                cd "$docker_pg_dir"
                local repo_pg_version=$(_geo_db__get_pg_version_from_dockerfile)
                log::debug "Building with --no-cache"
                local image_name="$(_geo_image__get_name)"
                if [[ -z $pg_version ]]; then
                    docker build $options --file "$dockerfile" -t "$image_name" . \
                        && log::success 'geo-cli Postgres image created' \
                        || { log::Error 'Failed to create geo-cli Postgres image' && return 1; }
                else
                    local dockerfile_contents="$(cat "$dockerfile")"
                    log::status "Creating geo-cli Postgres $pg_version image"
                    if [[ $dockerfile_contents =~ 'ENV POSTGRES_VERSION=$POSTGRES_VERSION_ARG' ]]; then
                        log::debug "Using build arg: POSTGRES_VERSION_ARG=$pg_version"
                        docker build $options --file "$dockerfile" \
                            --build-arg "POSTGRES_VERSION_ARG=$pg_version" \
                            -t "$image_name" . \
                            && log::success 'geo-cli Postgres image created' \
                            || { log::Error 'Failed to create geo-cli Postgres image' && return 1; }
                    else
                        dockerfile_contents="$(sed -E "s/ENV POSTGRES_VERSION .+/ENV POSTGRES_VERSION $pg_version/g" <<<"$dockerfile_contents")"
                        local tmp_dockerfile="$dockerfile.pg$pg_version"
                        log::debug "Using temp dockerfile: $tmp_dockerfile"
                        echo "$dockerfile_contents" >$tmp_dockerfile
                        echo
                        log::debug "docker build $options -t ${IMAGE}_${pg_version} -f $tmp_dockerfile ."
                        docker build $options -t "$image_name" -f $tmp_dockerfile . \
                            && log::success 'geo-cli Postgres image created' \
                            || { log::Error 'Failed to create geo-cli Postgres image' && return 1; }
                        rm $tmp_dockerfile
                    fi
                fi
            )
            return
            ;;
        ls)
            docker image ls | grep "$IMAGE"
            ;;
    esac
}

#######################################################################################################################
@register_geo_cmd 'db'
@geo_db_doc() {
    doc_cmd 'db'
    doc_cmd_desc 'Database commands.'

    doc_cmd_sub_cmd_title

    doc_cmd_sub_cmd 'create [option] <name> [additional names]'
        doc_cmd_sub_cmd_desc 'Creates a versioned db container and volume. Multiple containers can be created at once by supplying additional names.'
        doc_cmd_sub_option_title
            doc_cmd_sub_option '-y'
                doc_cmd_sub_option_desc 'Accept all prompts.'
            doc_cmd_sub_option '-e'
                doc_cmd_sub_option_desc 'Create blank Postgres 12 container.'
            doc_cmd_sub_option '-d <database name>'
                doc_cmd_sub_option_desc 'Sets the name of the db to be created (only used if initializing it as well).'
            doc_cmd_sub_option '-v <pg version>'
                doc_cmd_sub_option_desc 'Sets the Postgres version (e.g. 14) to use when creating the container.'
            doc_cmd_sub_option -f
                doc_cmd_sub_option_desc "Force the image and container to be built without using cached layers."

    doc_cmd_sub_cmd 'start [option] [name]'
        doc_cmd_sub_cmd_desc 'Starts (creating if necessary) a versioned db container and volume. If no name is provided,
                            the most recent db container name is started.'
        doc_cmd_sub_option_title
            doc_cmd_sub_option '-y'
                doc_cmd_sub_option_desc 'Accept all prompts.'
            doc_cmd_sub_option '-b'
                doc_cmd_sub_option_desc 'Skip building MyGeotab when initializing a new db with geotabdemo. This is faster, but you have to make sure the correct version of MyGeotab has already been built'
            doc_cmd_sub_option '-d <database name>'
                    doc_cmd_sub_option_desc 'Sets the name of the db to be created (only used if initializing it as well).'
                doc_cmd_sub_option '-v <pg version>'
                    doc_cmd_sub_option_desc 'Sets the Postgres version (e.g. 14) to use when creating the container.'
            doc_cmd_sub_option -f
                doc_cmd_sub_option_desc "Force the image and container to be built without using cached layers."

    doc_cmd_sub_cmd 'cp <source_db> <destination_db>'
        doc_cmd_sub_cmd_desc 'Makes a copy of an existing database container.'

    doc_cmd_sub_cmd 'rm, remove [option] <version> [additional version to remove]'
        doc_cmd_sub_cmd_desc 'Removes the container and volume associated with the provided version (e.g. 2004).'
        doc_cmd_sub_option_title
            doc_cmd_sub_option '-a, --all [substring to match]'
                doc_cmd_sub_option_desc 'Remove all db containers and volumes. You can also add a substring that will be used to remove all containers that contain it. Example: geo db rm -a .0 => remove all containers that have .0 in their name (e.g. 10.0, 11.0).'

    doc_cmd_sub_cmd 'stop [version]'
        doc_cmd_sub_cmd_desc 'Stop geo-cli db container.'

    doc_cmd_sub_cmd 'ls [option]'
        doc_cmd_sub_cmd_desc 'List geo-cli db containers.'
        doc_cmd_sub_option_title
            doc_cmd_sub_option '-a, --all'
                doc_cmd_sub_option_desc 'Display all geo images, containers, and volumes.'

    doc_cmd_sub_cmd 'ps'
        doc_cmd_sub_cmd_desc 'List running geo-cli db containers.'

    doc_cmd_sub_cmd 'init'
        doc_cmd_sub_cmd_desc 'Initialize a running db container with geotabdemo or an empty db with a custom name.'
        doc_cmd_sub_option_title
            doc_cmd_sub_option '-y'
                doc_cmd_sub_option_desc 'Accept all prompts.'
            doc_cmd_sub_option '-b'
                doc_cmd_sub_option_desc 'Skip building MyGeotab when initializing a new db with geotabdemo. This is faster, but you have to make sure the correct version of MyGeotab has already been built'
            doc_cmd_sub_option '-d <database name>'
                doc_cmd_sub_option_desc 'Sets the name of the db to be created.'

    doc_cmd_sub_cmd 'psql [options]'
    doc_cmd_sub_cmd_desc 'Open an interactive psql session to geotabdemo (or a different db, if a db name was provided with the -d option) in
                            the running geo-cli db container. You can also use the -q option to execute a query on the
                            database instead of starting an interactive session. The default username and password used to
                            connect is geotabuser and vircom43, respectively.'
    doc_cmd_sub_option_title
    doc_cmd_sub_option '-d'
    doc_cmd_sub_option_desc 'The name of the postgres database you want to connect to. The default value used is "geotabdemo"'
    doc_cmd_sub_option '-p'
    doc_cmd_sub_option_desc 'The admin sql password. The default value used is "vircom43"'
    doc_cmd_sub_option '-q'
    doc_cmd_sub_option_desc 'A query to run with psql in the running container. This option will cause the result of the query to be returned
                                                instead of starting an interactive psql terminal.'
    doc_cmd_sub_option '-u'
    doc_cmd_sub_option_desc 'The admin sql user. The default value used is "geotabuser"'

    doc_cmd_sub_cmd 'ssh|bash'
    doc_cmd_sub_cmd_desc 'Open a bash session with the running geo-cli db container.'
    doc_cmd_sub_option_title
    doc_cmd_sub_option '-c <bash command>'
    doc_cmd_sub_option_desc 'Run a bash command in the container and return the result'

    doc_cmd_sub_cmd 'logs'
        doc_cmd_sub_cmd_desc 'Displays the logs for the running geo-cli container.'
    # doc_cmd_sub_cmd 'script <add|edit|ls|rm> <script_name>'
    #     doc_cmd_sub_cmd_desc "Add, edit, list, or remove scripts that can be run with $(log::txt_italic geo db psql -q script_name)."
    #     doc_cmd_sub_option_title
    #         doc_cmd_sub_sub_cmd 'add'
    #             doc_cmd_sub_sub_cmd_desc 'Adds a new script and opens it in a text editor.'
    #         doc_cmd_sub_sub_cmd 'edit'
    #             doc_cmd_sub_sub_cmd_desc 'Opens an existing script in a text editor.'
    #         doc_cmd_sub_sub_cmd 'ls'
    #             doc_cmd_sub_option_desc 'Lists existing scripts.'
    #         doc_cmd_sub_sub_cmd 'rm'
    #             doc_cmd_sub_sub_cmd_desc 'Removes a script.'

    doc_cmd_examples_title
    doc_cmd_example 'geo db start 2004'
    doc_cmd_example 'geo db start -y 2004'
    doc_cmd_example 'geo db create 2004'
    doc_cmd_example 'geo db rm 2004'
    doc_cmd_example 'geo db rm --all'
    doc_cmd_example 'geo db rm 7.0 8.0 9.0'
    doc_cmd_example 'geo db cp 9.0 9.1'
    doc_cmd_example 'geo db rm --all'
    doc_cmd_example 'geo db ls'
    doc_cmd_example "geo db ssh -c \"echo 'this ran in the db container'\""
    doc_cmd_example 'geo db psql'
    doc_cmd_example 'geo db psql -u mySqlUser -p mySqlPassword -d dbName'
    doc_cmd_example 'geo db psql -q "SELECT * FROM deviceshare LIMIT 10"'
}
function @geo_db() {
    # Check to make sure that the current user is added to the docker group. All subcommands in this command need to use docker.
    if ! _geo_check_docker_permissions; then
        return 1
    fi

    _geo_db__check_for_old_image_prefix

    local db_subcommand="$1"
    case "$db_subcommand" in
        init)
            _geo_db__init "${@:2}"
            return
            ;;
        ls)
            _geo_db__ls_containers "${@:2}"

            # Show all geo-cli volumes and images if the user supplied some variant of all (-a, --all, all).
            if [[ $2 =~ ^-*a(ll)? ]]; then
                echo
                _geo_db__ls_volumes
                echo
                _geo_db__ls_images
            fi
            return
            ;;
        ps)
            docker ps --filter name="$IMAGE*"
            return
            ;;
        stop)
            _geo_db__stop "${@:2}"
            return
            ;;
        rm | remove)
            local db_version="$2"

            if [[ -z $db_version ]]; then
                log::Error "No database version provided for removal"
                return
            fi

            _geo_db__rm "${@:2}"
            return
            ;;
        create)
            _geo_db__create "${@:2}"
            ;;
        start)
            _geo_db__start "${@:2}"
            ;;
        cp | copy)
            _geo_db__copy "${@:2}"
            ;;
        psql)
            _geo_db__psql "${@:2}"
            ;;
        script)
            _geo_db__script "${@:2}"
            ;;
        bash | ssh)
            local running_container_id=$(_geo_db__get_running_container_id)
            if [[ -z $running_container_id ]]; then
                log::Error 'No geo-cli containers are running to connect to.'
                log::info "Run $(log::txt_underline 'geo db ls') to view available containers and $(log::txt_underline 'geo db start <name>') to start one."
                return 1
            fi

            if [[ $2 == -c ]]; then
                docker exec $(_geo_db__get_running_container_id) bash -c "$3"
                return
            fi

            docker exec -it $running_container_id /bin/bash
            ;;
        log | logs) docker logs $(_geo_get_running_container_id) ;;
        *)
            if [[ -z $db_subcommand ]]; then
                log::Error "geo-db: No command provided."
            else
                log::Error "Unknown subcommand '$1'"
            fi
            echo
            log::status "Available commands:"
            log::data "  ${SUBCOMMAND_COMPLETIONS['db']}"
            return 1
            ;;
    esac
}

_geo_db__check_for_old_image_prefix() {
    old_container_prefix='geo_cli_db_postgres11_'
    containers=$(docker container ls -a --format '{{.Names}}' | grep $old_container_prefix)

    # Return if there aren't any containers with old prefixes.
    [[ -z $containers || -z $IMAGE ]] && return

    log::debug 'Fixing container names'
    for old_container_name in $containers; do
        local cli_name=${old_container_name#$old_container_prefix}
        local new_container_name="${IMAGE}_${cli_name}"
        log::debug "$old_container_name -> $new_container_name"
        docker rename $old_container_name $new_container_name
    done

    # Rename existing image.
    docker image tag geo_cli_db_postgres11 $IMAGE 2>/dev/null
}

_geo_db__stop() {
    local silent=false

    if [[ $1 =~ -s ]]; then
        silent=true
        shift
    fi

    local container_id
    local db_version="$1"
    local container_name=$(_geo_container_name $db_version)

    if [[ -z $db_version ]]; then
        container_id=$(_geo_db__get_running_container_id)
        # container_id=`docker ps --filter name="$IMAGE*" --filter status=running -aq`
    else
        container_id=$(_geo_db__get_running_container_id "${container_name}")
        # container_id=`docker ps --filter name="${container_name}" --filter status=running -aq`
    fi

    if [[ -z $container_id ]]; then
        [[ $silent == false ]] \
            && log::warn 'No geo-cli db containers running'
        return
    fi

    log::status -b 'Stopping container...'

    # Stop all running containers.
    echo $container_id | xargs docker stop >/dev/null \
        && log::success 'OK' \
        || { log::Error "Failed to stop container" && return 1; }
}

_geo_db__create() {
    local silent=false
    local accept_defaults=
    local no_prompt=
    local empty_db=false
    local db_name=
    local pg_version=
    local suppress_info=false
    local no_cache=false
    local img_options=false
    local dont_prompt_for_db_name_confirmation=false

    # local build=false
    local OPTIND

    while getopts ":sSyend:xv:f" opt; do
        case "${opt}" in
            s) silent=true ;;
            S) suppress_info=true ;;
            y) accept_defaults=true ;;
            n) no_prompt=true ;;
            e) empty_db=true && log::status -b 'Creating empty Postgres container' ;;
            d) db_name="$OPTARG" ;;
            x) dont_prompt_for_db_name_confirmation=true ;;
            f) no_cache=true img_options=-f ;;
            v)
                pg_version="$OPTARG"
                ! [[ $pg_version =~ ^[[:digit:]]+$ ]] \
                    && log::Error "geo image create: The -v option must be a number and valid Postgres version. '$pg_version' is invalid." \
                    && return 1
                ;;
            # b ) build=true ;;
            :)
                log::Error "Option '${OPTARG}'  expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: ${OPTARG}"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    # if $build; then
    #     log::status -b 'Building MyGeotab'
    #     local dev_repo=$(@geo_get DEV_REPO_DIR)
    #     myg_core_proj="$dev_repo/Checkmate/MyGeotab.Core.csproj"
    #     [[ ! -f $myg_core_proj ]] && Error "Build failed. Cannot find csproj file at: $myg_core_proj" && return 1;
    #     if ! dotnet build "${myg_core_proj}"; then
    #         Error "Building MyGeotab failed"
    #         return 1;
    #     fi
    # fi

    db_version="$1"
    db_version=$(_geo__make_alphanumeric "$db_version")
    # Create multiple containers if more than one container name was passed in (i.e., geo db create 8.0 9.0).
    if [[ -n $1 && -n $2 ]]; then
        log::debug 'Creating multiple containers'
        while [[ -n $1 ]]; do
            # local option_count=0
            # local option_index=2
            #  while [[ ${@:option_index++:1} =~ ^- ]]; do ((option_count++)); done;
            #  echo $option_count;
            #  shift $((option_count + 1))
            #  echo acount="$#"
            #  echo args "$@"
            _geo_db__create -xS $1
            shift
        done
        return
    fi

    if [[ -z $db_version ]]; then
        log::Error "No database version provided."
        return
    fi

    local container_name=$(_geo_container_name "$db_version")

    if _geo_container_exists $container_name; then
        log::Error 'Container already exists'
        return 1
    fi

    local image_name=$(_geo_image__get_name)
    # local image_name=$IMAGE

    if [[ -n $pg_version ]]; then
        image_name="${IMAGE}_${pg_version}"
        # Create custom image if it doesn't exist.

        ! _geo_image__exists $image_name || $no_cache \
            && { @geo_image create $img_options -v $pg_version || return 1; }
    fi

    if ! _geo_check_db_image; then
        log::Error "Cannot create db without image. Run 'geo image create' to create a db image"
        return 1
    fi

    if [[ -z $accept_defaults && -z $no_prompt ]] && ! $dont_prompt_for_db_name_confirmation; then
        prompt_continue "Create db container with name $(log::txt_underline ${db_version})? (Y|n): " || return
    fi

    local using_custom_pg_version=$pg_version
    pg_version=${pg_version:-12}

    log::status -b "Creating volume:"
    log::status "  Docker name: $container_name"
    docker volume create "$container_name" >/dev/null \
        && log::success 'OK' || { log::Error 'Failed to create volume' && return 1; }

    log::status -b "Creating container:"
    log::status "  Name: $db_version"
    log::status "  Docker name: $container_name"
    # docker run -v $container_name:/var/lib/postgresql/11/main -p 5432:5432 --name=$container_name -d $IMAGE > /dev/null && log::success OK
    local vol_mount="$container_name:/var/lib/postgresql/$pg_version/main"

    # TODO: Figure out how to mount the container's psql binary to host if the correct pg version doesn't exist.
    # So, if /usr/lib/postgresql/$pg_version doesn't exist, mount the container's dir to the local one.
    #   i.e /usr/lib/postgresql/$pg_version:/usr/lib/postgresql/$pg_version
    # Might have to mount container to the volume, then the host to the same dir in the vol.
    # local host_pg_path="/usr/lib/postgresql/$pg_version"
    # local psql_vol_mount="$host_pg_path:/usr/lib/postgresql/$pg_version"
    # [[ ! -d $host_pg_path ]] && mkdir $host_pg_path
    # vol_mount+=" $host_pg_path" && log::debug "Adding host vol mount: $host_pg_path"

    local port=5432:5432

    local sql_user=postgres
    local sql_password='!@)(vircom44'
    local hostname=$container_name

    if [[ $empty_db == true ]]; then
        # [[ -z $using_custom_pg_version ]] &&image_name=geo_cli_postgres
        # TODO: Name the image something other than geo_cli_postgres and logic to handle that.
        # IMAGE = geo_cli_db_postgres.
        image_name=geo_cli_postgres
        dockerfile="
            FROM postgres:$pg_version
            ENV POSTGRES_USER postgres
            ENV POSTGRES_PASSWORD password
            RUN mkdir -p /var/lib/postgresql/$pg_version/main
        "
        sql_password=password
        ! docker build -t $image_name - <<<"$dockerfile" \
            && log::Error "Failed to create empty Postgres $pg_version image for container." \
                return 1
    fi

    log::debug "\ndocker create -v $vol_mount -p $port --name=$container_name --hostname=$hostname $image_name >/dev/null"

    if docker create -v $vol_mount -p $port --name=$container_name --hostname=$hostname $image_name >/dev/null; then
        echo
        log::success 'OK'
    else
        log::Error 'Failed to create container'
        return 1
    fi
    echo

    if [[ $silent == false ]] && ! $suppress_info; then
        log::info "Start your new db with $(log::txt_underline geo db start $db_version)"
        log::info "Initialize it with geotabdemo using $(log::txt_underline geo db init $db_version)"
        echo
        log::info -b "Connect with pgAdmin (after starting with $(log::txt_underline geo db start $db_version))"
        log::info 'Create a new server and entering the following information:'
        log::info "  Name: Postgres (or whatever you want)"
        log::info "  Connection tab"
        log::info "    Host: localhost"
        log::info "    Port: 5432"
        log::info "    Maintenance database: postgres"
        log::info "    Username: $sql_user"
        log::info "    Password: $sql_password"
    fi
}

# Updates/creates db credential files that allow pgAdmin && Rider to connect both to geo dbs and remote ones over IAP tunnels.
# Arguments:
#   [--iap <iap_password>]
#   [-d,--db <db_name>]
#   [-u,--user <username>]
_geo_ar__copy_pgAdmin_server_config() {
    local iap=false
    # Variables that are exported are used to populate the template credential files using the envsubst command.
    export ar_config_file_type=demo
    export geotab_username=${USER}
    export iap_database="postgres"
    local globbing_was_disabled=true

    # Enables file name generation (globbing).
    # Globbing allows file name patterns to be expanded. If the 'f' shell option is present, globbing is disabled.
    # Unset the f option using set +f.
    [[ $- =~ f ]] && globbing_was_disabled=true && set +f

    while [[ $1 =~ -+ ]]; do
        case "$1" in
            --iap)
                [[ -z $2 && -z $GEO_AR_IAP_PASSWORD ]] && log::Error "The $1 option requires the iap password as a parameter, but none was provided" && return 1
                iap=true
                ar_config_file_type=iap
                # Replace : with \: to escape it (required format for passfiles).
                export iap_password
                iap_password=${2:-$GEO_AR_IAP_PASSWORD}
                iap_password="${iap_password//:/\\:}"
                log::debug -d "$iap_password"
                shift
                ;;
            -d|--db|--database)
                [[ -z $2 ]] && log::Error "The $1 option requires a database name as a parameter, but none was provided" && return 1
                iap_database=${2:-$iap_database}
                shift
                ;;
            -u|--user*)
                [[ -z $2 ]] && log::Error "The $1 option requires a username as a parameter, but none was provided" && return 1
                geotab_username=${2:-$geotab_username}
                shift
                ;;
        esac
        shift
    done

    local config_file_dir="${GEO_CLI_SRC_DIR}/includes/db"
    local destination_config_dir="${GEO_CLI_CONFIG_DIR}/data/db"
    export passfile="${destination_config_dir}/${ar_config_file_type}.passfile"

    log::status "Updating credentials for pgAdmin"

    mkdir -p "$destination_config_dir"
    set +f
    for file in "$config_file_dir"/*$ar_config_file_type*; do
        # Substitute in any environment variables and copy config files to the geo-cli config directory.
        local dest_file_path="$destination_config_dir/${file##*/}"
        local text="$(envsubst < "$file")"
        echo "$text" > "$dest_file_path"
        chmod 0600 "$dest_file_path"
    done

    _geo_ar__update_pgpass_file
    # $globbing_was_disabled && set -f && log::debug "$FUNCNAME: Re-disabling globbling."
}
# _geo_ar__copy_pgAdmin_server_config --iap "=9265x|jb8)MgnW*:&zjTzL7Lr>)Ve" dawsonmyers
# _geo_ar__copy_pgAdmin_server_config --iap '4g6Yqy|dgp*)1(ZlD$q39x}Is2r8KN'

_geo_ar__update_pgpass_file() {
    local destination_config_dir="${GEO_CLI_CONFIG_DIR}/data/db"
    local passfile="${destination_config_dir}/iap.passfile"
    local user_pgpass_file="$HOME/.pgpass"

    log::status -b "Updating IAP credentials for Rider"
    # shopt -s extglob
    # e user_pgpass_file passfile
    # Required for Rider to be able to use it to connect to the db.
    if [[ -f $passfile && $passfile =~ iap ]]; then
        # Make a copy of the existing file.
        [[ -f $user_pgpass_file && ! -f $user_pgpass_file.bac ]] \
            && log::status "Making backup of existing .pgpass -> .pgpass.bac" \
            && cp "$user_pgpass_file"{,.bac}
        local new_creds="$(tail -1 "$passfile")"
        local old_creds="$(tail -1 "$HOME/.pgpass")"
        if [[ $old_creds != $new_creds ]]; then
            log::debug ".pgpass"
            log::debug "   OLD: $old_creds"
            log::debug "   NEW: $new_creds"
            cp -f "$passfile" "$HOME/.pgpass" && log::success ".pgpass updated" || log::failed "Failed to update .pgpass"
        else
            log::status ".pgpass was already up to date"
        fi
    else
        log::warn "passfile wasn't found. Unable to update ~/.pgpass with IAP credentials."
    fi
}
# _geo_ar__update_pgpass_file

_geo_show_repo_dir_reminder() {
    local dev_repo=$(@geo_get DEV_REPO_DIR)
    if [[ -n $dev_repo ]]; then
        log::info -f "Using the following path as the MyGeotab repo root. If this path needs to be updated, run $(txt_underline geo init repo) and select the correct location. Current MyGeotab repo path:"
        log::link "  $dev_repo"
        echo
    fi
}

_geo_db__start() {
    local accept_defaults=
    local no_prompt=
    local no_build=false
    local prompt_for_db=
    local db_version=
    local db_name=
    local pg_version=
    local force_no_cache=false
    local image_options=
    local OPTIND

    while getopts ":ynbphd:v:f" opt; do
        case "${opt}" in
            y) accept_defaults=true ;;
            n) no_prompt=true ;;
            b) no_build=true ;;
            p) prompt_for_db=true ;;
            h) _geo_db__doc && return ;;
            d) db_name="$OPTARG" ;;
            v)
                pg_version="$OPTARG"
                ! [[ $pg_version =~ ^[[:digit:]]+$ ]] \
                    && log::Error "geo-db-start: The -v option must be a number and valid Postgres version. '$pg_version' is invalid." \
                    && return 1
                ;;
            f ) force_no_cache=true ;;
            :)
                log::Error "Option '${OPTARG}'  expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: ${OPTARG}"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))
    # log::debug "===== $db_name"
    # log::Error "Port error" && return 1

    prompt_for_db_version() {
        while [[ -z $db_version ]]; do
            prompt_for_info -v db_version "Enter an alphanumeric name (including .-_) for the new database version: "
            # log::debug "db_version: $db_version"
            # Parse any options supplied by the user.
            local options_regex='-([[:alpha:]]+) .*'
            if [[ $db_version =~ $options_regex ]]; then
                local options=${BASH_REMATCH[1]}
                # log::debug "opts: $options"
                [[ $options =~ b ]] && no_build=true
                [[ $options =~ y ]] && accept_defaults=true
                # Remove the options from the user input.
                db_version=${db_version#-* }
                # log::debug "db_version: $db_version"
            fi
            db_version=$(_geo__make_alphanumeric "$db_version")
        done
        # log::debug $db_version
    }

    if [[ $prompt_for_db == true ]]; then
        log::status -b 'Create Database'
        _geo_show_repo_dir_reminder
        log::info -f "Add the following options like this: [-option] <db name>. For example, '-by 10.0' would create a db named 10.0 using the 'skip build' and 'accept defaults' options"
        local skip_build_text="b: Skip building MyGeotab (faster, but the correct version of MyGeotab has to already be built."
        local accept_defaults_text="y: Accept defaults. Re-uses the previous username and passwords so that you aren't prompted to enter them again."
        log::detail "$(log::fmt_text_and_indent_after_first_line "$skip_build_text" 0 3)"
        log::detail "$(log::fmt_text_and_indent_after_first_line "$accept_defaults_text" 0 3)"
        prompt_for_db_version
        while [[ $db_version =~ ^-[yb]{1,2}$ ]]; do
            log::caution "No database name supplied, only the following option(s) '$db_version'"
            db_version=
            prompt_for_db_version
        done
        shift
    else
        _geo_show_repo_dir_reminder
        db_version="$1"
    fi

    db_version=$(_geo__make_alphanumeric "$db_version")

    if [[ -z $db_version ]]; then
        db_version=$(@geo_get LAST_DB_VERSION)
        if [[ -z $db_version ]]; then
            log::Error "No database version provided."
            return 1
        fi
    fi

    if [[ -n $pg_version ]]; then
        image_name="${IMAGE}_${pg_version}"
        # Create custom image if it doesn't exist.
        _geo_image__exists "$image_name" \
            && prompt_continue "Postgres $pg_version image '$image_name' already exists. Would you like to rebuild it? (Y|n): " \
            && @geo_image create $image_options -v $pg_version
    else
        if ! _geo_check_db_image; then
            if ! prompt_continue "No database images exist. Would you like to create on? (Y|n): "; then
                log::Error "Cannot start db without image. Run 'geo image create' to create a db image"
                return 1
            fi
            @geo_image create $image_options
        fi
        _geo_check_db_image_pg_version
    fi

    @geo_set LAST_DB_VERSION "$db_version"

    # VOL_NAME="geo_cli_db_${db_version}"
    local container_name=$(_geo_container_name "$db_version")

    # docker run -v 2002:/var/lib/postgresql/11/main -p 5432:5432 postgres11

    # Check to see if the db is already running.
    # _geo_db__get_running_container_name
    local running_db=$(_geo_db__get_running_container_name)
    [[ $running_db == $container_name ]] && log::success "DB '$db_version' is already running" && return

    local volume=$(docker volume ls | grep " $container_name")
    # local volume_created=false
    # local recreate_container=false
    # [[ -n $volume ]] && volume_created=true

    # if [[ -z $volume ]]; then
    #     volume=$(docker volume ls | grep " geo_cli_db_postgres11_${db_version}")
    #     [[ -n $volume ]] && volume_created=true && recreate_container=true
    # fi

    @geo_db stop -s

    # Check to see if a container is running that is bound to the postgres port (5432).
    # If it is already in use, the user will be prompted to stop it or exit.
    local port_in_use=$(docker ps --format '{{.Names}} {{.Ports}}' | grep '5432->')
    if [[ -n $port_in_use ]]; then
        # Get container name by triming off the port info from docker ps output.
        local container_name_using_postgres_port="${port_in_use%% *}"
        log::Error "Postgres port 5432 is currently bound to the following container: $container_name_using_postgres_port"
        [[ $no_prompt == true ]] && log::Error "Port error" && return 1
        if prompt_continue "Do you want to stop this container so that a geo db one can be started? (Y|n): "; then
            if docker stop "$container_name_using_postgres_port" >/dev/null; then
                log::status 'Container stopped'
            else
                log::Error 'Unable to stop container'
                return 1
            fi
        else
            log::error 'Cannot continue while port 5432 is already in use.'
            return 1
        fi
    fi

    local output=''

    try_to_start_db() {
        output=''
        output="$(docker start $1 2>&1 | grep '0.0.0.0:5432: bind: address already in use')"
    }

    local container_id=

    if _geo_db__get_container_id -v container_id "$container_name"; then
        log::status -b "Starting existing container:"
        [[ -z $db_version ]] && db_version=$(@geo_get LAST_DB_VERSION)
        [[ -n $db_version ]] && log::keyvalue "Name" "$db_version"
        log::keyvalue "Docker name" "$container_name"
        # log::status -n "  Name: " && log::data "$db_version"
        # log::status -n "  Docker name: " && log::data "$container_name"

        # if [[ $recreate_container == true ]]; then
        #     docker container rm $container_id
        #     local vol_mount="geo_cli_db_postgres11_${db_version}:/var/lib/postgresql/12/main"
        #     local port=5432:5432
        #     docker create -v $vol_mount -p $port --name=$container_name $IMAGE > /dev/null
        # fi

        try_to_start_db $container_id

        if [[ -n $output ]]; then
            [[ $no_prompt == true ]] && log::Error "Port error" && return 1
            log::Error "Port 5432 is already in use."
            log::info "Fix: Stop postgresql"
            if prompt_continue "Do you want to try to stop the postgresql service? (Y|n): "; then
                sudo service postgresql stop
                sleep 2
                log::status -b "Trying to start existing container again"
                try_to_start_db $container_id
                if [[ -n $output ]]; then
                    log::Error "Port 5432 is still in use. It's not possible to start a db container until this port is available."
                    return 1
                fi
                log::success OK
            fi
        fi

        # TODO: FIX issue #8 https://git.geotab.com/dawsonmyers/geo-cli/-/issues/8
        #   Auto-switch switches the server.config after it detects that the branch has changes. Make sure that this password
        #   change isn't happening before the switch happens (leaving the current db's password in the config file that was
        #   just replaced.
        #  * Also, add separate cmd and json file for metadata related to dbs
        #     - dates - created, modified, last used/started/accessed
        #     - password, username
        #     - myg release, branch name

        #  Restore db user password in server.config
        _geo_update_server_config_with_db_user_password
#        local db_user_password=$(@geo_get "${container_name}_db_user_password")
#        if _geo_terminal_cmd_exists xmlstarlet && [[ -n $db_user_password && -f "$HOME/GEOTAB/Checkmate/server.config" ]]; then
#            xmlstarlet ed --inplace -u "//LoginSettings/Password" -v "$db_user_password" "$HOME/GEOTAB/Checkmate/server.config"
#        fi

    else
        # db_version was getting overwritten somehow, so get its value from the config file.
        db_version=$(@geo_get LAST_DB_VERSION)
        # db_version="$1"
        # db_version=$(_geo__make_alphanumeric "$db_version")

        if [[ -z $accept_defaults && -z $no_prompt ]]; then
            [[ -n $pg_version ]] && log::detail "Postgres version: $pg_version\n"
            prompt_continue "Db container $(log::txt_underline ${db_version}) doesn't exist. Would you like to create it? (Y|n): " || return 1
        fi

        local opts=-sx
        [[ $accept_defaults == true ]] && opts+=y
        [[ $no_prompt == true ]] && opts+=n
        $force_no_cache && opts+="f"
        [[ -n $pg_version ]] && opts+=" -v $pg_version"

        # log::debug "db_version: $db_version"

        _geo_db__create $opts "$db_version" \
            || {
                log::Error 'Failed to create db'
                return 1
            }

        try_to_start_db $container_name
        container_id=$(_geo_db__get_running_container_id)

        if [[ -n $output ]]; then
            log::Error "Port 5432 is already in use."
            log::info "Fix: Stop postgresql"
            [[ $no_prompt == true ]] && return 1
            if prompt_continue "Do you want to try to stop the postgresql service? (Y|n): "; then
                sudo service postgresql stop && log::success 'postgresql service stopped'
                sleep 2
                log::status -b "Trying to start new container"
                try_to_start_db $container_name
                if [[ -n $output ]]; then
                    log::Error "Port 5432 is still in use. It's not possible to start a db container until this port is available."
                    return 1
                fi
            else
                log::Error 'Cannot start db while port 5432 is in use.'
                return 1
            fi

        fi

        log::status -b "Starting new container:"
        log::keyvalue "Name" "$db_version"
        log::keyvalue "Docker name" "$container_name"
        # log::status -n "  Name: " && log::data "$db_version"
        # log::status -n "  Docker name: " && log::data "$container_name"

        [[ $no_prompt == true ]] && return

        opts=-
        [[ $accept_defaults == true ]] && opts+=y
        [[ $no_prompt == true ]] && opts+=n
        [[ $no_build == true ]] && opts+=b
        [[ ${#opts} -eq 1 ]] && opts=
        [[ -n $db_name ]] && opts+=" -d $db_name"
        echo
        # log::debug @geo_db_init $opts"
        if [[ $accept_defaults == true ]] || prompt_continue 'Would you like to initialize the db? (Y|n): '; then
            _geo_db__init $opts
        else
            log::info "Initialize a running db anytime using $(log::txt_underline 'geo db init')"
        fi
    fi
    _geo_validate_server_config
    log::success Done
}

_geo_update_server_config_with_db_user_password() {
    local container_name=$(_geo_db__get_running_container_name)
    local db_user_password=$(@geo_get "${container_name}_db_user_password")
    [[ $(@geo_get auto_db_user_password) == false || -z $container_name || -z $db_user_password ]] && return

    if _geo_terminal_cmd_exists xmlstarlet && [[ -n $db_user_password && -f "$HOME/GEOTAB/Checkmate/server.config" ]]; then
        xmlstarlet ed --inplace -u "//LoginSettings/Password" -v "$db_user_password" "$HOME/GEOTAB/Checkmate/server.config"
    fi
}

_geo_db__copy() {
    local interactive=false
    [[ $1 == -i ]] && interactive=true && shift

    local source_db="$1"
    local destination_db="$2"

    db_name_exists() {
        local name=$(_geo_container_name "$1")
        docker container inspect $name >/dev/null 2>&1
        # [[ $? == 0 ]]
    }

    source_db=$(_geo__make_alphanumeric "$source_db")
    # Make sure the source database exists.
    ! db_name_exists $source_db && log::Error "The source database container '$source_db' does not exist" && return 1

    [[ -z $source_db ]] && log::Error "The source database cannot be empty" && return 1
    if [[ -z $destination_db ]]; then
        if [[ $interactive == true ]]; then
            log::info -b "Source database: '$source_db'"
            prompt_return=''
            while [[ -z $prompt_return ]] || db_name_exists "$prompt_return"; do
                db_name_exists "$prompt_return" && log::warn "Database container '$prompt_return' already exists"
                prompt_for_info_n 'Enter a name for the new database container: '
            done
            destination_db="$prompt_return"
        else
            log::Error "The destination database name cannot be empty" && return 1
        fi
    fi

    [[ -z $destination_db ]] && log::Error "The destination database name cannot be empty" && return 1

    destination_db=$(_geo__make_alphanumeric "$destination_db")
    local source_db_name=$(_geo_container_name "$source_db")
    local destination_db_name=$(_geo_container_name "$destination_db")

    # Make sure the destination database doesn't exist
    db_name_exists $destination_db && log::Error "There is already a container named '$destination_db'" && return 1

    log::status -b "\nCreating destination database volume '$destination_db'"
    docker volume create --name $destination_db_name >/dev/null

    log::status -b "\nCopying data from source database volume '$source_db' to '$destination_db'"
    docker run \
        --rm \
        -it \
        -v $source_db_name:/from \
        -v $destination_db_name:/to \
        alpine ash -c "cd /from; cp -av . /to" #> /dev/nullge
    [[ $? -eq 0 ]] && log::success 'Done' || log::Error 'Volume creation failed'

    log::status -b "\nCreating destination database container '$destination_db'"
    local vol_mount="$destination_db_name:/var/lib/postgresql/12/main"
    local port=5432:5432
    if docker create -v $vol_mount -p $port --name=$destination_db_name $IMAGE >/dev/null; then
        log::success 'Done'
    else
        log::Error 'Failed to create container'
        return 1
    fi

    prompt_continue "Would you like to start database container '$destination_db'? (Y/n): " && _geo_db__start $destination_db
}

_geo_db__psql() {
    local sql_user=$(@geo_get SQL_USER)
    local sql_password=$(@geo_get SQL_PASSWORD)
    local db_name=geotabdemo
    local query=
    local docker_options='-it'
    local psql_options=
    # local OPTIND
    # local -
    # set -o noglob
    # while getopts ":d:u:q:p:" opt; do
    #     log::debug opt = "$opt", arg = "$OPTARG"
    #     case "$opt" in
    #         d )
    #             db_name="${OPTARG:-$db_name}"
    #             ;;
    #         u )
    #             sql_user="${OPTARG:-$sql_user}"
    #             ;;
    #         p )
    #             sql_password="${OPTARG:-$sql_password}"
    #             ;;
    #         s )
    #             query="$OPTARG"
    #             docker_options=''
    #             psql_options='-c'
    #             ;;
    #         \? )
    #             log::Error "Unknown option '$OPTARG'."
    #             return 1
    #             ;;
    #         : )
    #             log::Error "Invalid argument for '$OPTARG'."
    #             return 1
    #             ;;
    #     esac
    # done
    # log::debug db_name=$db_name, sql_user=$sql_user, query=$query, psql_options=$psql_options
    # return
    local script_param_count=0
    declare -A cli_param_lookup
    while [[ $1 =~ ^-{1,2}[a-z] ]]; do
        local option=$1
        local arg="$2"
        shift
        # It's an error if the argument to an option is an option.
        [[ ! $arg || $arg =~ ^-[a-z] ]] && log::Error "Argument missing for option ${option}" && return 1

        # log::debug "op=$option    arg=$arg"
        case $option in
            -d)
                db_name="$arg"
                ;;
            -u)
                sql_user="$arg"
                ;;
            -p)
                sql_password="$arg"
                ;;
            -q)
                query="$arg"
                docker_options=''
                psql_options='-c'
                # script_path="$GEO_CLI_SCRIPT_DIR/$query".sql

                # log::debug $script_path
                # if [[ -f $script_path ]]; then
                #     query="$(cat $script_path | sed "s/'/\'/g")"
                # fi
                ;;
            --*)
                option="${option#--}"
                log::debug $option $arg
                cli_param_lookup["$option"]="$arg"
                ((script_param_count++))
                ;;
            *)
                log::Error "Unknown option '$option'."
                return 1
                ;;
        esac
        shift
    done

    # This isn't currently working
    # log::debug $script_param_count
    # if (( script_param_count > 0 )); then
    #     param_definitions="$(echo "$query" | grep '^--- ' | sed 's/--- //g')"
    #     param_names="$(sed 's/=.*//g' <<<"$param_definitions")"
    #     param_names_array=()
    #     default_param_values="$(sed 's/.*=//g' <<<"$param_definitions")"
    #     default_param_values_array=()
    #     declare -A param_lookup
    #     # Extract param names and values.
    #     default_param_count=0
    #     while read -r line; do
    #         param_names_array+=("$line")
    #         ((default_param_count++))
    #     done <<<"$param_names"
    #     while read -r line; do
    #         default_param_values_array+=("$line")
    #     done <<<"$default_param_values"

    #     for ((i = 0; i < default_param_count; i++)); do
    #         key="${param_names_array[$i]}"
    #         value="${default_param_values_array[$i]}"
    #         param_lookup["$key"]="$value"
    #     done
    #     for key in "${!cli_param_lookup[@]}"; do
    #         value="${cli_param_lookup[$key]}"
    #         param_lookup["$key"]="$value"
    #     done

    #     # log::debug "$query"

    #     # Remove all comments and empty lines.
    #     query="$(sed -e 's/--.*//g' -e '/^$/d' <<<"$query")"
    #     for key in "${!param_lookup[@]}"; do
    #         value="${param_lookup[$key]}"
    #         [[ -v cli_param_lookup["$key"] ]] && value="${cli_param_lookup[$key]}"
    #         log::debug "value=$value    key=$key"
    #         query="$(sed "s/{{$key}}/$value/g" <<<"$query")"
    #     done
    #     query="$(echo "$query" | tr '\n' ' ')"
    #     # log::debug "$query"
    # fi

    # Assign default values for sql user/passord.
    [[ -z $db_name ]] && db_name=geotabdemo
    [[ -z $sql_user ]] && sql_user=geotabuser
    [[ -z $sql_password ]] && sql_password=vircom43

    local running_container_id=$(_geo_db__get_running_container_id)
    # log::debug $sql_user $sql_password $db_name $running_container_id

    if [[ -z $running_container_id ]]; then
        log::Error 'No geo-cli containers are running to connect to.'
        log::info "Run $(log::txt_underline 'geo db ls') to view available containers and $(log::txt_underline 'geo db start <name>') to start one."
        return 1
    fi

    if [[ -n $query ]]; then
        # args=(
        #     "docker exec"
        #     $docker_options
        #     -e
        #     PGPASSWORD=$sql_password
        #     $running_container_id
        #     /bin/bash
        #     -c
        #     "\"psql -U $sql_user -h localhost -p 5432 -d $db_name '$psql_options $query'\""
        # )
        # log::debug "${args[@]}"
        log::debug "docker exec $docker_options -e PGPASSWORD=$sql_password $running_container_id /bin/bash -c \"psql -U geotabuser -h localhost -p 5432 -d $db_name \"$psql_options $query\""
        # log::debug "docker exec $docker_options -e PGPASSWORD=$sql_password $running_container_id /bin/bash -c \"psql -U $sql_user -h localhost -p 5432 -d $db_name '$psql_options $query'\""
        # docker exec $docker_options -e PGPASSWORD=$sql_password $running_container_id /bin/bash -c "psql -U $sql_user -h localhost -p 5432 -d $db_name '$psql_options $query'\""
        docker exec $docker_options -e PGPASSWORD=$sql_password $running_container_id /bin/bash -c "psql -U geotabuser -h localhost -p 5432 -d $db_name \"$psql_options $query\""
        # docker exec -e PGPASSWORD=vircom43 94563ab3da3e /bin/bash -c "psql -U geotabuser -h localhost -p 5432 -d geotabdemo \"$psql_options $query\""

        # eval "docker exec $docker_options -e PGPASSWORD=$sql_password $running_container_id /bin/bash -c \"psql -U $sql_user -h localhost -p 5432 -d $db_name '$psql_options $query'\""
    else
        docker exec -it -e PGPASSWORD=$sql_password $running_container_id psql -U $sql_user -h localhost -p 5432 -d $db_name
    fi
}

_geo_validate_server_config() {
    ! _geo_terminal_cmd_exists xmlstarlet && return 1
    local server_config="$HOME/GEOTAB/Checkmate/server.config"
    local server_config="$HOME/test/server.config"
    local webPort sslPort
    _geo_xml_upsert_server_config --inplace -x //WebServerSettings/WebPort -v 10000 --replace-default 80 $server_config
    _geo_xml_upsert_server_config --inplace -x //WebServerSettings/WebSSLPort -v 10001 --replace-default 443 $server_config
#     set +x
}

_geo_xml_upsert_server_config() {
    log::debug "args: $*"
    local default_server_config="$HOME/GEOTAB/Checkmate/server.config"
    local xml_file
    local xpath
    local xpath_parent=//WebServerSettings
    local name
    local upsert_value
    local replace_default_value
    local xpath
    local xml_file
    local inplace=
    local OPTIND
    while [[ $1 =~ ^-+ ]]; do
        log::debug "while = $1"
         case "${1}" in
             -x | --xpath )
                xpath="$2"
                xpath_parent="${xpath%/*}"
                shift
                ;;
             -p | --parent) xpath_parent="$2" && shift;;
             -i | --inplace) inplace=--inplace ;;
             -n | --name) name="$2" && shift;;
             -v | --value) upsert_value="$2" && shift;;
             -r | --replace-default) replace_default_value="$2" && shift;;
             -f | --file) xml_file="$2" && shift ;;
             *) log::Error "Invalid option: '$1'" && return 1 ;;
         esac
         shift
     done

    [[ -z $xpath && -n $1 ]] && xpath="$1" && shift
    [[ -z $xml_file && -n $1 ]] && xml_file="$1" && shift
    [[ -z $xml_file ]] && xml_file="$default_server_config"
#    xml_file="$HOME/GEOTAB/Checkmate/server.config"
    [[ -z $xpath_parent ]] && xpath_parent="${xpath%/*}"
    [[ -z $name ]] && name="${xpath##*/}"

    log::debug "
    xpath=$xpath
    xpath_parent=$xpath_parent
    name=$name
    upsert_value=$upsert_value
    replace_default_value="$replace_default_value"
    xml_file="$xml_file"
    "
    local current_value
#    log::debug "Checking current value"
#    log::debug xmlstarlet ed $inplace --subnode "$xpath_parent" -t elem -n "$name" -v "$upsert_value" "$xml_file"
#    _geo_xml_get --var current_value "$xpath" "$xml_file"
#    if ! _geo_xml_get --var current_value "$xpath" "$xml_file"; then
    if ! current_value=$(xmlstarlet sel -t -v "$xpath" "$xml_file"); then
        log::debug About to run:
        log::debug xmlstarlet ed $inplace --subnode "$xpath_parent" -t elem -n "$name" -v "$upsert_value" "$xml_file"
        ! xmlstarlet ed $inplace --subnode "$xpath_parent" -t elem -n "$name" -v "$upsert_value" "$xml_file" \
            && log::Error "Failed to insert $name element into server.config: $xml_file" \
            && return 1
        ! current_value=$(xmlstarlet sel -t -v "$xpath" "$xml_file") \
            && log::Error "Attempt to insert element $name failed: $xml_file" \
            && return 1
    fi

    # Update the value if it's empty or if it's equal to replace_if_value_is
    if [[ -z $current_value || $current_value == $replace_default_value ]]; then
        log::status "Updating server.config: $xpath: $current_value => $upsert_value"

        log::debug xmlstarlet ed $inplace -u "$xpath" -v "$upsert_value" "$xml_file"

        xmlstarlet ed $inplace -u "$xpath" -v "$upsert_value" "$xml_file" \
            && log::success "OK." \
            || log::Error "Failed to update server.config with correct $name value."
    elif [[  $current_value != $upsert_value ]]; then
        log::warn "Warning: server.config: $xpath == $current_value. The default for local development is $upsert_value"
    fi
}

_geo_xml_node_exists() {
     _geo_xml_get "$@" >/dev/null
    }

_geo_xml_get() {
    log::debug "args: $*"
    local xml_file=
    local xpath=
    local var=
    while [[ $1 =~ ^-+ ]]; do
        [[ ! $2 =~ ^[[:alnum:]] ]] && break
         case "${1}" in
             -x | --xpath) value="$2" && shift ;;
             -n | --name) name="$2" && shift ;;
             -f | --file) xml_file="$2" && shift ;;
             -v | --var)
                [[ $(util::get_var_type $2) == none && -n $2 ]] \
                    && eval "$2=''"
             local -n var="$2" && shift ;;
             *) log::Error "Invalid option: '$1'" && return 1 ;;
         esac
         shift
     done
     [[ -z $xpath && -n $1 ]] && xpath="$1" && shift
     [[ -z $xml_file && -n $1 ]] && xml_file="$1"
     [[ -z $xml_file && -n $1 ]] && xml_file="$1"
     : ${xml_file:="$HOME/GEOTAB/Checkmate/server.config"}

     log::debug xmlstarlet sel -t -v "$xpath" "$xml_file"
     local value="$(xmlstarlet sel -t -v "$xpath" "$xml_file")"
     log::debug util::is_ref_var var && var="$value" || echo "$value"
     util::typeofvar var && var="$value" || echo "$value"
     util::is_ref_var var && log::debug "var is ref = $var" || echo NOT REF
    }

_geo_xml_upsert() {
    log::debug "args: $*"
    local xml_file="$HOME/GEOTAB/Checkmate/server.config"
    local xpath="$1"
    local xpath_parent="${xpath%/*}"
    local name="${xpath##*/}"
    local value="$2"
    local disallowed_value="$3"
    local xml_file="$4"
    local inplace=false
    while [[ $1 =~ ^-+ ]]; do
         case "${1}" in
             -x | --xpath )
                xpath="$2"
                xpath_parent="${xpath%/*}"
                shift
                ;;
             -i | --inplace) inplace=true ;;
             -n | --name) value="$2" && shift;;
             -v | --value) name="$2" && shift;;
             -f | --file) xml_file="$2" && shift ;;
             -n)
                 ;;
             *) log::Error "Invalid option: '$1'" && return 1 ;;
         esac
         shift
     done
    shift $((OPTIND - 1))
    log::debug "
    xpath="$1"
    xpath_parent="${xpath%*/}"
    name="${xpath##*/}"
    value="$2"
    disallowed_value="$3"
    xml_file="$4"
    "
    local current_value=""
#    log::debug "Checking current value"
    if ! current_value=$(xmlstarlet sel -t -v "$xpath" "$xml_file"); then
        ! xmlstarlet ed --inplace --subnode "$xpath_parent" -t elem -n "$name" -v "$default_value" "$xml_file" \
            && log::Error "Failed to insert $name element into server.config: $xml_file" \
            && return 1
        ! current_value=$(xmlstarlet sel -t -v "$xpath" "$xml_file") \
            && log::Error "Attempt to insert element $name failed: $xml_file" \
            && return 1
    fi

    if [[ $current_value == $disallowed_value ]]; then
        log::status "Updating server.config: $xpath: $current_value => $default_value"
        xmlstarlet ed --inplace -u "$xpath" -v "$default_value" "$xml_file" \
            && log::success "OK." \
            || log::Error "Failed to update server.config with correct $name value."
    elif [[  $current_value != $default_value ]]; then
        log::warn "Warning: server.config: $xpath == $current_value. The default for local development is $default_value"
    fi
}

_geo_db__script() {
    [[ -z $GEO_CLI_SCRIPT_DIR ]] && log::Error "GEO_CLI_SCRIPT_DIR doesn't have a value" && return 1
    [[ ! -d $GEO_CLI_SCRIPT_DIR ]] && mkdir -p $GEO_CLI_SCRIPT_DIR
    [[ -z $EDITOR ]] && EDITOR=nano

    local command="$1"
    local script_name=$(_geo__make_alphanumeric $2)
    local script_path="$GEO_CLI_SCRIPT_DIR/$script_name".sql

    check_for_script() {
        if [[ -f $script_path ]]; then
            log::success 'Saved'
        else
            log::warn "Script '$script_name' wasn't found in script directory, did you save it before closing the text editor?"
        fi
    }

    case "$command" in
        add)
            if [[ -f $script_path ]]; then
                if ! prompt_continue "Script '$script_name' already exists. Would you like to edit it? (Y|n): "; then
                    return
                fi
            else
                if ! prompt_continue "Create script called '$script_name'? (Y|n): "; then
                    return
                fi
            fi
            log::debug "$GEO_CLI_SRC_DIR/templates/geo-db-script.sql" "$script_path"
            cp "$GEO_CLI_SRC_DIR/templates/geo-db-script.sql" "$script_path"
            $EDITOR "$script_path"
            check_for_script
            ;;
        edit)
            if [[ ! -f $script_path ]]; then
                if ! prompt_continue "Script '$script_name' doesn't exist. Would you like to create it? (Y|n): "; then
                    return
                fi
            fi
            $EDITOR $script_path
            check_for_script
            ;;
        ls)
            ls $GEO_CLI_SCRIPT_DIR | tr ' ' '\n'
            ;;
        rm)
            rm $GEO_CLI_SCRIPT_DIR/$2
            ;;
        *)
            log::Error "Unknown subcommand '$command'"
            ;;
    esac
}

# Replace any non-alphanumeric characters with '_', then replace 2 or more occurrences with a singe '_'.
# Ex: some>bad()name -> some_bad__name -> some_bad_name
_geo__make_alphanumeric() {
    echo "$@" | sed 's/[^0-9a-zA-Z_.-]/_/g' | sed -e 's/_\{2,\}/_/g'
}

_geo_db__get_pg_version_from_docker_object() {
    local result="$(docker inspect "$1" --format '{{ json .Config.Env }}' | jq '.[] | select(match("POSTGRES_VERSION="))')"
    result=${result##*=}
    result=${result//\"/}
    echo -n "$result"
}

_geo_db__get_pg_version_from_dockerfile() {
    [[ $1 == -v ]] && local -n var=$2 && shift 2
    local repo_dir=$(@geo_get DEV_REPO_DIR) 2>/dev/null
    local dockerfile_dir="${repo_dir}/Checkmate/Docker/postgres"
    local dockerfile="$dockerfile_dir/Debug.Dockerfile"

    local pg_version=$(grep -E 'POSTGRES_VERSION_ARG=|ENV POSTGRES_VERSION ' "$dockerfile") 2>/dev/null
    # New way of defining the pg version: POSTGRES_VERSION_ARG=14
    #   Remove 'POSTGRES_VERSION_ARG=', leaving the version, 14
    pg_version="${pg_version##*=}"
    # Old way of defining the pg version: ENV POSTGRES_VERSION 10
    #   Remove 'ENV POSTGRES_VERSION ', leaving the version, 10
    pg_version="${pg_version##* }"
    [[ $pg_version =~ ([0-9]+) ]] && pg_version=${BASH_REMATCH[1]} || return 1
    [[ -v var ]] && var=$pg_version
    echo -n "$pg_version"
}

_geo_db__ls_images() {
    log::info Images
    docker image ls geo_cli* #--format 'table {{.Names}}\t{{.ID}}\t{{.Image}}'
}
_geo_db__ls_containers() {
    log::info 'DB Containers'
    # docker container ls -a -f name=geo_cli

    local include_ids=false

    local OPTIND
    while getopts "ai" opt; do
        case "${opt}" in
            a) docker container ls -a -f name=geo_cli && return ;;
            i) include_ids=true ;;
            # i ) [[ $OPTARG =~ ^[[:digit:]]+$ ]] && pg_version=$OPTARG ;;
            :)
                log::Error "Option '${OPTARG}'  expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: ${OPTARG}"
                return 1
                ;;
        esac
    done

    shift $((OPTIND - 1))

    local output=$(docker container ls -a -f name=geo_cli --format '{{.Names}}\t{{.ID}}\t{{.Names}}\t{{.CreatedAt}}')

    # local filtered=$(echo "$output" | awk 'printf "%-24s %-16s %-24s\n",$1,$2,$3 } ')
    local filtered=$(echo "$output" | awk '{ gsub("geo_cli_db_postgres_","",$1);  printf "%-20s %-16s %-28s\n",$1,$2,$3 } ')
    # echo "$output" | awk { gsub($3"_","",$1);  printf "%-24s %-16s %-24s\n",$3,$2,$1 } '
    # filtered=`echo $"$output" | awk 'BEGIN { format="%-24s %-24s %-24s\n"; ; printf format, "Name","Container ID","Image" } { gsub($3"_","",$1);  printf " %-24s %-24s %-24s\n",$1,$2,$3 } '`

    local names=$(docker container ls -a -f name=geo_cli --format '{{.Names}}')
    local longest_field_length=$(awk '{ print length }' <<<"$names" | sort -n | tail -1)
    local container_name_field_length=$((longest_field_length + 2))
    local name_field_length=$((${#longest_field_length} - ${#GEO_DB_PREFIX} + 2))
    ((name_field_length < 14)) && name_field_length=14

    local col2_name="PG Version"
    $include_ids && col2_name="Container ID"

    local line_format=" %-${name_field_length}s %-14s %-${container_name_field_length}s %-12s\n"
    local header=$(printf "$line_format" "geo-cli Name" "$col2_name" "Container Name" "Created")
    local total_line_length=${#header}

    # Print the table header.
    log::data_header "$header"

    local created_date=
    local rest_of_line=

    # Get the date in seconds.
    local now="$(date +%s)"

    while read -r line; do
        _ifs=$IFS
        # Split the 4 fields in the line into an array (using tab as the delimiter).
        IFS=$'\t' read -r -a line_array <<<"$line"
        IFS=$_ifs

        # Remove the geo db prefix from the container name to get the geo-cli name for the db.
        local col1_geo_container_name="${line_array[0]#${GEO_DB_PREFIX}_}"

        local container_id="${line_array[1]}"
        local col2_value=
        # If the user has included the -i option, then the second column will be the container ids, otherwise, the
        # postgres version will shown.
        if $include_ids; then
            col2_value="$container_id"
        else
            # Try to get pg version (e.g., 14) from the PG_VERSION environment variable by inspecting the docker
            # container object. Ignore any errors and just leave the value empty if we can't get the version.
            local postgres_version=$(_geo_db__get_pg_version_from_docker_object $container_id 2>/dev/null)
            col2_value="$postgres_version"
        fi

        local col3_docker_container_name="${line_array[2]}"

        created_date="${line_array[3]}"
        # Trim off timezone.
        created_date="${created_date:0:19}"
        local col4_days_since_created=$(_geo_datediff "$now" "$created_date")

        local line_values_array=(
            "$col1_geo_container_name"
            "$col2_value"
            "$col3_docker_container_name"
            "$col4_days_since_created"
        )

        printf "$line_format" "${line_values_array[@]}"
    done <<<"$output"

    local terminal_width=$(tput cols)
    ((total_line_length > terminal_width)) \
        && log::detail "\nExpand the width of your terminal to display the table correctly."
}

_geo_db__ls_volumes() {
    log::info Volumes
    docker volume ls -f name=geo_cli
}

_geo_db__pg_db_exists() {
    local pg_db_name="$1"
    [[ -z $pg_version ]] && log::Error "_geo_db__pg_db_exists: No database name supplied" && return 1
    local query="SELECT datname FROM pg_catalog.pg_database WHERE lower($pg_version) = lower('$pg_version')"
    _geo_is_container_running || return 1
    geo ssh -q "$query"
}

_geo_datediff() {
    number_re='^[0-9]+$'
    # Parse if a date string was passed in
    [[ $1 =~ $number_re ]] && d1=$1 || d1=$(date -d "$1" +%s)
    [[ $2 =~ $number_re ]] && d2=$2 || d2=$(date -d "$2" +%s)
    # The dates are now in seconds.

    # The difference in seconds between the two dates.
    diff_seconds=$((d1 - d2))

    # Some seconds-based constants.
    minute=60
    hour=$((minute * 60))
    day=$((hour * 24))

    seconds=$diff_seconds
    minutes=$((diff_seconds / minute))
    hours=$((diff_seconds / hour))
    days=$((diff_seconds / day))
    weeks=$((diff_seconds / (day * 7)))
    months=$((diff_seconds / (day * 30)))
    years=$((diff_seconds / (day * 365)))

    msg=$days
    ((seconds > 1)) && msg="seconds ago"
    ((minutes == 1)) && msg="1 minute ago"
    ((minutes > 1)) && msg="$minutes minutes ago"
    ((hours == 1)) && msg="1 hour ago"
    ((hours > 1)) && msg="$hours hours ago"
    ((days == 1)) && msg="yesterday"
    ((days > 1)) && msg="$days days ago"
    ((weeks == 1)) && msg="1 week ago"
    ((weeks > 1)) && msg="$weeks weeks ago"
    ((months == 1)) && msg="1 month ago"
    ((months > 1)) && msg="$months months ago"
    ((years == 1)) && msg="1 year ago"
    ((years > 1)) && msg="$years years ago"
    echo $msg
}

# Converts a string into a valid container name by replacing any invalid characters
_geo_container_name() {
    local name=$(_geo__make_alphanumeric $1)
    echo "${IMAGE}_${name}"
}

_geo_db__get_container_id() {
    local is_by_ref=false
    local variable=
    # Check if the caller supplied a variable name that they want the result to be stored in.
    [[ $1 == -v ]] && local -n variable="$2" && shift 2 && is_by_ref=true

    local name=$1
    # [[ -z $name ]] && name="$IMAGE*"
    # echo `docker container ls -a --filter name="$name" -aq`
    local result=$(docker inspect "$name" --format='{{.ID}}' 2>&1)

    if $is_by_ref; then
        variable="$result"
    else
        echo $result
    fi

    local container_does_not_exists=$(echo $result | grep -i "error")
    [[ -z $container_does_not_exists ]]
}

geo_db__get_container_name_from_id() {
    local is_by_ref=false
    local variable=
    # Check if the caller supplied a variable name that they want the result to be stored in.
    [[ $1 == -v ]] && local -n variable="$2" && shift 2 && is_by_ref=true

    local id=$1
    # [[ -z $name ]] && name="$IMAGE*"
    # echo `docker container ls -a --filter name="$name" -aq`
    local result=$(docker inspect "$id" --format='{{.Name}}' 2>&1)

    # Remove / from start of name.
    result="${result//\//}"

    if $is_by_ref; then
        variable="$result"
    else
        echo $result
    fi

    local container_does_not_exists=$(echo $result | grep -i "error")
    [[ -z $container_does_not_exists ]]
}

_geo_container_exists() {
    local _var_ref=
    # Check if the caller supplied a variable name that they want the container id to be stored in.
    [[ $1 == -v ]] && local -n _var_ref="$2" && shift 2 && _var_ref=
    local container_name=$1
    [[ ! $container_name =~ geo_cli_db_postgres_ ]] && container_name="geo_cli_db_postgres_${container_name}"

    _geo_db__get_container_id -v _var_ref "$container_name"
}

_geo_db__get_running_container_id() {
    local name=$1
    [[ -z $name ]] && name="geo_cli_*"
    # [[ -z $name ]] && name="$IMAGE*"
    echo $(docker ps --filter name="$name" --filter status=running -aq)
}

_geo_is_container_running() {
    local name=$(_geo_db__get_running_container_name)
    [[ -n $name ]]
}

_geo_db__get_running_container_name() {
    # local name=$1
    local name=
    [[ -z $name ]] && name="$IMAGE*"

    local container_name=$(docker ps --filter name="$name" --filter status=running -a --format="{{ .Names }}")
    if [[ $1 == -r ]]; then
        container_name=${container_name#geo_cli_db_postgres_}
        container_name=${container_name#geo_cli_db_postgres11_}
    fi
    echo "$container_name"
}

_geo_check_docker_permissions() {
    local ps_error_output=$(docker ps 2>&1 | grep docker.sock)
    local docker_group=$(cat /etc/group | grep 'docker:')
    if [[ -n $ps_error_output ]]; then
        debug "$ps_error_output"
        if ! [[ -z $docker_group || ! $docker_group =~ $USER ]]; then
            log::warn 'You ARE a member of the docker group, but are not able to use docker without sudo.'
            log::info 'Fix: You must completely log out and then back in again to resolve the issue.'
            return 1
        fi
        log::warn 'You are NOT a member of the docker group. This is required to be able to use the "docker" command without sudo.'
        log::Error "The current user does not have permission to use the docker command."
        log::info "Fix: Add the current user to the docker group."
        if prompt_continue 'Would you like to fix this now? (Y|n): '; then
            [[ -z $docker_group ]] && sudo groupadd docker
            sudo usermod -aG docker $USER || {
                log::Error "Failed to add '$USER' to the docker group"
                return 1
            }
            newgrp docker
            log::warn 'You must completely log out of you account and then log back in again for the changes to take effect.'
        fi
        return 1
    fi
}

# function check_for_docker_group_membership() {
#     local docker_group=$(cat /etc/group | grep 'docker:')
#     if [[ -z $docker_group || ! $docker_group =~ "$USER" ]]; then
#         log::warn 'You are not a member of the docker group. This is required to be able to use the "docker" command without sudo.'
#         if prompt_continue "Add your username to the docker group? (Y|n): "; then
#             [[ -z $docker_group ]] && sudo groupadd docker
#             sudo usermod -aG docker $USER || { log::Error "Failed to add '$USER' to the docker group"; return 1; }
#             log::success "Added $USER to the docker group"
#             log::warn 'You may need to fully log out and then back in again for these changes to take effect.'
#             newgrp docker
#         else
#             log::warn "geo-cli won't be able to use docker until you're user is added to the docker group"
#         fi
#         return 1
#     fi
# }

function _geo_db__init() {
    # local accept_defaults=$1
    local silent=false
    local accept_defaults=false
    local no_prompt=false
    local no_build=false
    local db_name=geotabdemo
    local opts=

    local OPTIND
    while getopts "synbd:" opt; do
        case "${opt}" in
            s) silent=true ;;
            y) accept_defaults=true ;;
            n) no_prompt=true ;;
            b)
                no_build=true
                opts+=b
                ;;
            d) db_name="$OPTARG" ;;
            :)
                log::Error "Option '${OPTARG}' expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: ${OPTARG}"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    $accept_defaults && log::info 'Waiting for db to start...' && sleep 5

    local wait_count=0
    local msg_shown=
    while ! _geo_is_container_running; do
        [[ -z $msg_shown ]] && log::info -n 'Waiting for db to start' && msg_shown=true
        # Write progress.
        log::cyan -n '.'
        sleep 1
        if ((wait_count++ > 10)); then
            echo
            log::Error "Timeout. No database container running after waiting 10 seconds."
            return 1
        fi
    done
    echo

    local myg_version="$(@geo_dev release)"
    if [[ -n $myg_version ]]; then
        log::detail "MyGeotab version of current branch: $myg_version"
        prompt_continue "Initialize db with this version? (Y|n): " \
            || {
                log::info "You can checkout the desired MyGeotab version and run 'geo db init' to initialize it later.\n"
                return 1
            }
    fi
    local container_id=$(_geo_db__get_running_container_id)
    if [[ -z $container_id ]]; then
        log::Error 'No geo-cli containers are running to initialize.'
        log::info "Run $(log::txt_underline 'geo db ls') to view available containers and $(log::txt_underline 'geo db start <name>') to start one."
        return 1
    fi

    # log::status 'A db can be initialized with geotabdemo or with a custom db name (just creates an empty database with provided name).'
    # if ! [ $accept_defaults ] && ! prompt_continue 'Would you like to initialize the db with geotabdemo? (Y|n): '; then
    #     stored_name=`@geo_get PREV_DB_NAME`
    #     prompt_txt='Enter the name of the db you would like to create: '
    #     if [[ -n $stored_name ]]; then
    #         log::data "Stored db name: $stored_name"
    #         if ! prompt_continue 'Use stored db name? (Y|n): '; then
    #             prompt_for_info_n "$prompt_txt"
    #             while ! prompt_continue "Create db called '$prompt_return'? (Y|n): "; do
    #                 prompt_for_info_n "$prompt_txt"
    #             done
    #             db_name="$prompt_return"
    #         else
    #             db_name="$stored_name"
    #         fi
    #     else
    #         prompt_for_info_n "$prompt_txt"
    #         while ! prompt_continue "Create db called '$prompt_return'? (Y|n): "; do
    #             prompt_for_info_n "$prompt_txt"
    #         done
    #         db_name="$prompt_return"
    #     fi
    #     @geo_set PREV_DB_NAME "$db_name"
    # fi

    if [[ -z $db_name ]]; then
        log::Error 'Db name cannot be empty'
        return 1
    fi

    log::status -b "Initializing db $db_name\n"
    local user=$(@geo_get DB_USER)
    local password=$(@geo_get DB_PASSWORD)
    local sql_user=$(@geo_get SQL_USER)
    local sql_password=$(@geo_get SQL_PASSWORD)
    local answer=''

    # Assign default values for sql user/passord.
    [[ -z $user ]] && user="$USER@geotab.com"
    [[ -z $password ]] && password=passwordpassword
    [[ -z $sql_user ]] && sql_user=geotabuser
    [[ -z $sql_password ]] && sql_password=vircom43

    # Make sure there's a running db container to initialize.
    local container_id=$(_geo_db__get_running_container_id)
    if [[ -z $container_id ]]; then
        log::Error "There isn't a running geo-cli db container to initialize with geotabdemo."
        log::info 'Start one of the following db containers and try again:'
        _geo_db__ls_containers
        return 1
    fi

    get_user() {
        prompt_for_info_n -v user "Enter MyGeotab admin username (your email): "
        @geo_set DB_USER "$user"
    }

    get_password() {
        prompt_for_info_n -v password "Enter MyGeotab admin password: "
        @geo_set DB_PASSWORD "$password"
    }

    get_sql_user() {
        prompt_for_info_n -v sql_user "Enter db admin username: "
        @geo_set SQL_USER "$sql_user"
    }

    get_sql_password() {
        prompt_for_info_n -v sql_password "Enter db admin password: "
        @geo_set SQL_PASSWORD "$sql_password"
    }

    if ! $accept_defaults; then
        # Get sql user.
        log::detail "The db admin user should almost always be $(txt_underline geotabuser). Only change this if you know what you are doing."
        log::data "Stored db admin user: $(log::info $sql_user)"
        prompt_continue "Use stored user? (Y|n): " || get_sql_user

        # Get sql password.
        echo
        log::detail "The db admin password should almost always be $(txt_underline vircom43). Only change this if you know what you are doing."
        log::data "Stored db admin password: $(log::info $sql_password)"
        prompt_continue "Use stored password? (Y|n): " || get_sql_password

        # Get MyGeotab admin user.
        echo
        log::detail "The MyGeotab admin user should be your email address. This user is used to login to the MyGeotab web app."
        if [[ -z $user ]]; then
            get_user
        else
            log::data "Stored MyGeotab admin user: $(log::info $user)"
            prompt_continue "Use stored user? (Y|n): " || get_user
        fi

        # Get MyGeotab admin password.
        echo
        log::detail "Using the default password $(txt_underline passwordpassword) is easiest, but you can change it if you like. $(txt_underline 'Note:') This should $(txt_underline NOT) be a sensitive password (like the one for your email) since it is stored as plain text on this machine."
        if [[ -z $password ]]; then
            get_password
        else
            log::data "Stored MyGeotab admin password: $(log::info $password)"
            prompt_continue "Use stored password? (Y|n): " || get_password
        fi
    fi

    # path=$HOME/repos/MyGeotab/Checkmate/bin/Debug/netcoreapp3.1

    if ! _geo_check_for_dev_repo_dir; then
        log::Error "Unable to init db: can't find MyGeotab repo. Run 'geo db init' to try again on a running db container."
        return 1
    fi

    # local path=''
    # _geo_db__get_checkmate_dll_path $accept_defaults
    # path=$prompt_return

    # [ $accept_defaults ] && log::info 'Waiting...' && sleep 5

    # log::info 'Waiting for db to start...'

    # local wait_count=0
    # while ! _geo_is_container_running; do
    #     sleep 1;
    #     if (( wait_count++ > 10 )); then
    #         Error "Timeout. No database container running after waiting 10 seconds."
    #         return 1
    #     fi
    # done

    local dev_repo=$(@geo_get DEV_REPO_DIR)
    local myg_core_proj="$dev_repo/Checkmate/MyGeotab.Core.csproj"
    log::debug "dotnet build --project=$myg_core_proj"
    dotnet build --project=$myg_core_proj

    # Minimum verbosity level (m).
    opts="-v m"

    if $no_build; then
        opts+=' --no-build'
        log::status -b '\nSkipping build'
        log::hint 'Reminder: MyGeotab needs to be re-built after checking out a different release branch (i.e. 9.0 to 10.0).'
    else
        log::status -b '\nBuilding MyGeotab'
        log::hint 'Hint: If MyGeotab is already built, add the -b option to skip re-building it. This is much faster, but you have to make sure the correct version of MyGeotab has already been built.'
    fi

    if dotnet run $opts --project "$myg_core_proj" -- CreateDatabase postgres companyName="$db_name" administratorUser="$user" administratorPassword="$password" sqluser="$sql_user" sqlpassword="$sql_password" useMasterLogin='true'; then
        # if dotnet "${path}" CreateDatabase postgres companyName="$db_name" administratorUser="$user" administratorPassword="$password" sqluser="$sql_user" sqlpassword="$sql_password" useMasterLogin='true'; then
        local container_name=$(_geo_db__get_running_container_name)
        @geo_set "${container_name}_username" "$user"
        @geo_set "${container_name}_password" "$password"
        @geo_set "${container_name}_database" "$db_name"

        if _geo_terminal_cmd_exists xmlstarlet; then
            local db_user_password=$(xmlstarlet sel -t -v //LoginSettings/Password "$HOME/GEOTAB/Checkmate/server.config")
            [[ -n $db_user_password ]] && @geo_set "${container_name}_db_user_password" "$db_user_password"
        fi

        log::success "$db_name initialized"
        echo
        _geo_ar__copy_pgAdmin_server_config

        log::info -b 'Connect with pgAdmin (if not already set up)'
        log::info "  1. Open pgAdmin"
        log::info "  2. From the toolbar, click $(txt_underline 'Tools > Import/Export Servers')"
        log::info "  3. Paste the following path into the 'Filename' input box and then click $(txt_underline 'Next'):"
        log::data "     $(log::link $GEO_CLI_CONFIG_DIR/data/db/myg-demo-pgAdmin.json)"
        log::info "  4. Click on the Servers checkbox and then click $(txt_underline 'Next')"
        log::info "  5. Click $(txt_underline 'Finish') to complete the import process"
        echo
        log::info -b "\nAlternatively, you can create a server manually:"
        log::info "Create a new server in pgAdmin via $(txt_underline 'Objects > Register > Server') and enter the following information:"
        log::info "  Name: MyGeotab (or whatever you want)"
        log::info "  Connection tab"
        log::info "    Host: localhost"
        log::info "    Port: 5432"
        log::info "    Maintenance database: $db_name"
        log::info "    Username: $sql_user"
        log::info "    Password: $sql_password"
        echo
        log::info -b "Use $db_name"
        log::info "1. Run MyGeotab.Core in your IDE"
        log::info "2. Navigate to https://localhost:10001"
        log::info "3. Log in using:"
        log::info "  User: $user"
        log::info "  Password: $password"
    else
        log::Error 'Failed to initialize db'
        log::error 'Have you built the assembly for the current branch?'
        return 1
    fi
}

_geo_db__rm() {
    if [[ $1 =~ ^-*a(ll)?$ ]]; then
        shift
        local search_str="$1"
        names="$(docker container ls -a -f name=geo_cli --format "{{.Names}}")"
        [[ -n $search_str ]] && names="$(grep -F "$search_str" <<<"$names")"
        [[ -z $names ]] && log::warn "No containers to remove." && return 1
        log::detail "$names"
        local count=$(wc -l <<<"$names")
        local prompt_msg="Do you want to remove all ($count) containers? (Y|n): "
        ((count == 1)) && prompt_msg="Do you want to remove this container? (Y|n): "
        prompt_continue "$prompt_msg" || return

        # Get list of contianer names
        # ids=`docker container ls -a -f name=geo_cli --format "{{.ID}}"`
        # echo "$ids" | xargs docker container rm
        local fail_count=0
        for name in $names; do
            # Remove image prefix from container name; leaving just the version/identier (e.g. geo_cli_db_postgres_10.0 => 10.0).
            _geo_db__rm -n "$name" || ((fail_count++))

            # @geo_db_rm "${name#${IMAGE}_}"
            # echo "${name#${IMAGE}_}"
        done
        local num_dbs=$(echo "$names" | wc -l)
        num_dbs=$((num_dbs - fail_count))
        log::success "Removed $num_dbs db(s)"
        [[ fail_count -gt 0 ]] && log::error "Failed to remove $fail_count dbs"
        return
    fi

    local container_name
    local db_name="$(_geo__make_alphanumeric $1)"
    # If the -n option is present, the full container name is passed in as an argument (e.g. geo_cli_db_postgres11_2101). Otherwise, the db name is passed in (e.g., 2101)
    if [[ $1 == -n ]]; then
        container_name="$2"
        db_name="${2#${IMAGE}_}"
        shift
    else
        container_name=$(_geo_container_name "$db_name")
    fi

    local container_id=$(_geo_db__get_running_container_id "$container_name")

    if [[ -n $container_id ]]; then
        log::status 'Trying to stop container...'
        docker stop $container_id >/dev/null && log::success "Container stopped"
    fi

    # Remove multiple containers if more than one container name was passed in (i.e., geo db rm 8.0 9.0).
    if [[ -n $1 && -n $2 ]]; then
        log::debug 'Removing multiple containers'
        while [[ -n $1 ]]; do
            _geo_db__rm $1
            shift
        done
        return
    fi

    # container_name=bad

    if docker container rm $container_name >/dev/null; then
        @geo_rm "${container_name}_username"
        @geo_rm "${container_name}_password"
        @geo_rm "${container_name}_db_user_password"
        @geo_rm "${container_name}_database"

        log::success "Container $db_name removed"
    else
        log::Error "Could not remove container $container_name"
        return 1
    fi

    # Check if the volume has the old container prefix.
    local volume_name=$(docker volume ls -f name=geo_cli --format '{{.Name}}' | grep $container_name'$')
    if [[ -z $volume_name ]]; then
        old_container_prefix='geo_cli_db_postgres11_'
        volume_name=$(docker volume ls -f name=geo_cli --format '{{.Name}}' | grep "${old_container_prefix}${db_name}"'$')
    fi
    [[ -z $volume_name ]] && log::Error "Failed to find volume $container_name" && return 1
    if docker volume rm $volume_name >/dev/null; then
        log::success "Volume $db_name removed"
    else
        log::Error "Could not remove volume $volume_name"
        return 1
    fi

}

_geo_db__get_checkmate_dll_path() {
    local dev_repo=$(@geo_get DEV_REPO_DIR)
    local output_dir="${dev_repo}/Checkmate/bin/Debug"
    local accept_defaults=$1
    # Get full path of CheckmateServer.dll files, sorted from newest to oldest.
    local files="$(find "$output_dir" -maxdepth 2 -name "CheckmateServer.dll" -print0 | xargs -r -0 ls -1 -t | tr '\n' ':')"
    local ifs="$IFS"
    IFS=:
    read -r -a paths <<<"$files"
    IFS="$ifs"
    local number_of_paths=${#paths[@]}
    [[ $number_of_paths == 0 ]] && log::Error "No output directories could be found in ${output_dir}. These folders should exist and contain CheckmateServer.dll. Build MyGeotab and try again."

    if [[ $number_of_paths -gt 1 ]]; then
        log::warn "Multiple CheckmateServer.dll output directories exist."
        log::info -b "Available executables in directory $(log::txt_italic "${output_dir}"):"
        local i=0

        log::data_header "  Id    Directory                                      "
        for d in "${paths[@]}"; do
            local line="  ${i}    ...${d##*Debug}"
            [ $i = 0 ] && line="${line}   $(log::info -bn '(NEWEST)')"
            log::data "$line"
            ((i++))
        done

        if [ $accept_defaults ]; then
            log::info 'Using newest'
            path="${paths[0]}"
            prompt_return="$path"
            return
        fi

        local msg="Enter the id of the directory you would like to use: "
        prompt_for_info_n "$msg"
        while [[ -z $prompt_return || $prompt_return -lt 0 || $prompt_return -ge $i ]]; do
            prompt_for_info_n "$msg"
        done
        path="${paths[prompt_return]}"
    else
        path="${paths[0]}"
    fi
    prompt_return="$path"
}

_geo_check_for_dev_repo_dir() {
    local dev_repo=$(@geo_get DEV_REPO_DIR)

    is_valid_repo_dir() {
        test -d "${1}/Checkmate"
    }

    get_dev_repo_dir() {
        local prompt_text='Enter the full path (e.g. ~/code/Development or ~/code/mygeotab) to the Development repo directory. This directory must contain the Checkmate directory (Type "--" to skip for now):'
        log::prompt "$(log::fmt_text "$prompt_text")"
        # log::prompt -n '> '
        # read -e dev_repo
        prompt_for_info_n -v dev_repo '> '
        # Expand home directory (i.e. ~/repo to /home/user/repo).
        dev_repo=${dev_repo/\~/$HOME}
        if [[ ! -d $dev_repo ]]; then
            log::warn "The provided path is not a directory"
            return 1
        fi
        if [[ ! -d "$dev_repo/Checkmate" ]]; then
            log::warn "The provided path does not contain the Checkmate directory"
            return 1
        fi
        # echo $dev_repo
    }

    if ! is_valid_repo_dir "$dev_repo" && [[ $dev_repo != -- ]]; then
        # log::status "Searching for possible repo locations..."
        _geo_init__find_myg_repo -v dev_repo
    fi

    # Ask repeatedly for the dev repo dir until a valid one is provided.
    while ! is_valid_repo_dir "$dev_repo" && [[ $dev_repo != -- ]]; do
        get_dev_repo_dir
    done

    [[ $dev_repo == -- ]] && return

    log::success "Checkmate directory found"
    @geo_set DEV_REPO_DIR "$dev_repo"
}

# Concatenates two lines using ' ' (or what was passed in as an arg to the -d delimeter option) if they can both fit on
# the same line (their total width doesn't exceed the width of the terminal). Otherwise, the lines will be separated by
# a line break. Non-printable characters are temporarily removed from the two strings in order to get their true width,
# Arguments:
#     [-s <start_len> | -e <end_len> | -d <delimeter>]
#     1: String 1
#     2: String 2
# Returns:
#     If total length < terminal width:
#         string1<delimeter>string2
#      Otherwise:
#         string1
#         string2
break_lines_if_term_width_exceeded() {
    local start_len end_len delim=' '
    local OPTIND

    while getopts ":s:e:d:" opt; do
        case "${opt}" in
            s) start_len="$OPTARG" ;;
            e) end_len="$OPTARG" ;;
            d) delim="$OPTARG" ;;
            :) log::Error "Option '${OPTARG}' expects an argument." && return 1 ;;
            \?) log::Error "Invalid option: ${OPTARG}" && return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    local newline=$'\n'
    local start="$1"
    local end="$2"

    # Remove non-printable character so that they don't affect line width.
    start_clean="$(echo -n "$start" | log::strip_color_codes)"
    : "${start_len:=${#start_clean}}"
    end_clean="$(echo -n "$end" | log::strip_color_codes)"
    : "${end_len:=${#end_clean}}"

    local cols msg
    cols=$(tput cols)

    # log::debug "((${#start} + ${#end} + 1 < $cols)) = $((${#start} + ${#end} + 2 < cols))"

    ((start_len + end_len < cols)) \
        && msg="${start}${delim}${end}" \
        || msg="${start}${newline}${end}"
    echo -n "$msg"
}

# Prompts for either reusing the previous value or entering a new one.
# Arguments:
#     [--no-save]: If present, the value entered will NOT be persisted.
#     1: The key for the persisted value.
#     2: The name of the caller variable to write the new value to.
#     [3]: The message to show when prompting for user input.
#     [4]: A regex that the entered value must match to be considered valid.
#     [5]: The message to show if the value is invalid.
prompt_for_info_with_previous_value() {
    local persist_value=true; [[ $1 == --no-save ]] && persist_value=false && shift
    local key="${1?$FUNCNAME 'Argument missing (#1): value for property key is required'}"
    local value_var_ref_name="${2?$FUNCNAME 'Argument missing (#1)'}"
    local -n value_var_ref="$2"
    local prompt_msg="${3:-"Enter a new value for $value_var_ref_name"}"
    local valid_regex="$4"
    local invalid_input_msg="${5:-'Invalid input value'}"

    # [[ -z $value_var_ref ]] && return

    local can_reuse_previous_value=false
    local saved_value="$(@geo_get "$key")"

    # e saved_value prompt_msg

    # if [[ -n $prompt_msg ]]; then
        local newline=$'\n'
        local stored_value_msg="$(log::detail -n Leave blank to use previous value:)"
        local value_msg="$(log::data -n "$saved_value")"

        local stored_value_prompt="$(break_lines_if_term_width_exceeded "$stored_value_msg" "$value_msg")"
        [[ -n $saved_value ]] \
            && log::info "$stored_value_prompt" \
            && can_reuse_previous_value=true
            # && log::info "Leave blank to use previous value: \n$(log::note "$saved_value")" \

        prompt_for_info -v "$value_var_ref_name" "$prompt_msg"

#        e $value_var_ref
        if [[ -z $value_var_ref ]] && $can_reuse_previous_value; then
            value_var_ref="$saved_value"
            log::status "Using previous value"
        elif [[ -z $value_var_ref || -n $valid_regex && ! $value_var_ref =~ $valid_regex ]]; then
            echo "elif [[ -z $value_var_ref || -n $valid_regex && ! $value_var_ref =~ $valid_regex ]]"
            while [[ -z $value_var_ref || -n $valid_regex && ! $value_var_ref =~ $valid_regex ]]; do
                log::warn "$invalid_input_msg"
                prompt_for_info -v "$value_var_ref_name" "$prompt_msg"
            done
        fi
    # elif [[ $value_var_ref =~ ^-?$ ]]; then
    #     echo "elif [[ $value_var_ref =~ ^-?$ ]]"
    #     [[ -z $saved_value ]] && log::Error "There is no value saved for key '$key'" && return 1
    #     value_var_ref="$saved_value"
    #     log::data "Using saved value: $(log::detail "$value_var_ref")"
    #     return
    # fi

    $persist_value && [[ -n $value_var_ref && $value_var_ref != $saved_value ]] \
        && @geo_set "$key" "$value_var_ref"
        # || log::debug "not saving data"
}
# prompt_for_info_with_previous_value ppv result "enter result: " '[[:digit:]]+' 'Your input is awful'

#######################################################################################################################
@register_geo_cmd 'ar'
@geo_ar_doc() {
    doc_cmd 'ar'
    doc_cmd_desc 'Helpers for working with access requests.'
    doc_cmd_sub_cmd_title
        doc_cmd_sub_cmd 'create'
            doc_cmd_sub_cmd_desc 'Opens up the My Access Request page on the MyAdmin website in Chrome.'
        doc_cmd_sub_cmd 'tunnel [gcloud start-iap-tunnel cmd]'
            doc_cmd_sub_cmd_desc "Starts the IAP tunnel (using the gcloud start-iap-tunnel command copied from MyAdmin after opening
                            an access request) and then connects to the server over SSH. The port is saved and used when you SSH to the server using $(log::green 'geo ar ssh').
                            This command will be saved and re-used next time you call the command without any arguments (i.e. $(log::green geo ar tunnel))"
            doc_cmd_sub_option_title
                doc_cmd_sub_option '-s'
                    doc_cmd_sub_option_desc "Only start the IAP tunnel without SSHing into it."
                doc_cmd_sub_option '-l'
                    doc_cmd_sub_option_desc "List and choose from previous IAP tunnel commands."
                doc_cmd_sub_option '-p <port>'
                    doc_cmd_sub_option_desc "Specifies the port to open the IAP tunnel on. This port must be greater than 1024 and not be in use."
                doc_cmd_sub_option '-P <port>'
                    doc_cmd_sub_option_desc "Specifies the local port to bind to port 5432 on the remote system (this can be used instead of the -L option). This port defaults to 5433. This port must be greater than 1024 and not be in use."
                doc_cmd_sub_option '-L'
                    doc_cmd_sub_option_desc "Bind local port 5433 to 5432 on remote host (through IAP tunnel). You can connect to the remote Postgres database
                        using this port (5433) in pgAdmin. Note: you can also open up an ssh session to this server by opening another terminal and running
                        $(log::green  geo ar ssh)."
            # doc_cmd_sub_option_desc "Starts an SSH session to the server immediately after opening up the IAP tunnel."
        doc_cmd_sub_cmd 'ssh'
            doc_cmd_sub_cmd_desc "SSH into a server through the IAP tunnel started with $(log::green 'geo ar ssh')."
            doc_cmd_sub_option_title
                doc_cmd_sub_option '-p <port>'
                    doc_cmd_sub_option_desc "The port to use when connecting to the server. This value is optional since the port that the IAP tunnel was opened on using $(log::green 'geo ar ssh') is used as the default value."
                doc_cmd_sub_option '-P <port>'
                    doc_cmd_sub_option_desc "Specifies the local port to bind to port 5432 on the remote system (this can be used instead of the -L option). This port defaults to 5433. This port must be greater than 1024 and not be in use."
                doc_cmd_sub_option '-u <user>'
                    doc_cmd_sub_option_desc "The user to use when connecting to the server. This value is optional since the username stored in \$USER is used as the default value. The value supplied here will be stored and reused next time you call the command."
                doc_cmd_sub_option '-L'
                    doc_cmd_sub_option_desc "Bind local port 5433 to 5432 on remote host (through IAP tunnel). You can connect to the remote Postgres database
                        using this port (5433) in pgAdmin. Note: you can also open up an ssh session to this server by opening another terminal and running
                        $(log::green  geo ar ssh)."
    doc_cmd_examples_title
        doc_cmd_example 'geo ar tunnel -s gcloud compute start-iap-tunnel gceseropst4-20220109062647 22 --project=geotab-serverops --zone=projects/709472407379/zones/northamerica-northeast1-b'
        doc_cmd_example 'geo ar ssh'
        doc_cmd_example 'geo ar ssh -p 12345'
        doc_cmd_example 'geo ar ssh -u dawsonmyers'
        doc_cmd_example 'geo ar ssh -u dawsonmyers -p 12345'
}
@geo_ar() {
    export GEO_AR_IAP_PASSWORD=
    local arguments=("$@")
    # ssh -L 127.0.0.1:5433:localhost:5432 -N <username>@127.0.0.1 -p <port from IAP>
    show_iap_password_prompt_message() {
        log::status -bu "Binding local port ${bind_port:-5432} to 5432 on remote host (through IAP tunnel)"
        echo
        log::info "$(txt_underline geo-cli) can configure pgAdmin to connect to Postgres over the IAP tunnel."
        log::info "Enter your Access Request password below to update the password file for the $(txt_underline MyGeotab Over IAP) server in pgAdmin"
        # log::info "$(txt_underline OR) leave it blank if you already have a server in pgAdmin and plan to update its password manually."
        echo
        log::info -n "The $(txt_underline MyGeotab Over IAP) server needs to be imported $(txt_underline once) into pgAdmin. "
        log::info "The instructions will be shown after you enter your password."
        echo
        log::info "After the server is added, you only need to paste in your password below to have its passfile updated. Make sure to refresh the server in pgAdmin after the port is bound."
        echo
        # hint='* Leave the password empty if you will be manually updating an existing server in pgAdmin.'
        # log::hint "$(log::fmt_text_and_indent_after_first_line "$hint" 0 2)"
        # hint="* Enter '-' in any of the following inputs to re-use the last value used."
        # log::hint "$(log::fmt_text_and_indent_after_first_line "$hint" 0 2)"

        # log::fmt_text_and_indent_after_first_line "$hint" 0 2
        # log::detail "Enter '-' in any of the following inputs to re-use the last value used."
        iap_password_prompt="Access Request password:"
        # iap_db_prompt="Database:\n> "

        prompt_for_info_with_previous_value AR_PASSWORD iap_password "$iap_password_prompt"

        # prompt_for_info_n -v iap_password "$iap_password_prompt"
        # while ! prompt_for_info_with_previous_value AR_PASSWORD iap_password "$iap_password_prompt"; do
        #     prompt_for_info_n -v iap_password "$iap_password_prompt"
        # done
        # prompt_for_info_n -v iap_db "$iap_db_prompt"
        # prompt_for_info_with_previous_value AR_DATABASE iap_db
        # while ! prompt_for_info_with_previous_value AR_DATABASE iap_db; do
        #     prompt_for_info_n -v iap_db "$iap_db_prompt"
        # done

        iap_skip_password=true
        reuse_msg_shown=true
        if [[ -n $iap_password ]]; then
            GEO_AR_IAP_PASSWORD="$iap_password"
            _geo_ar__copy_pgAdmin_server_config --iap "$iap_password" --user "$user"
            # _geo_ar__copy_pgAdmin_server_config --iap "$iap_password" "$iap_db" "$user"
        fi
    }
    local iap_password=
    local iap_db=
    local iap_skip_password=false
    local reuse_msg_shown=false
    local caller_args='ar'
#    local
    local cmd="$1"
    [[ -z $cmd ]] && log::Error "$FUNCNAME: Command argument missing" && return
    case "$1" in
        create)
            xdg-open https://myadmin.geotab.com/accessrequest/requests
#            google-chrome https://myadmin.geotab.com/accessrequest/requests
            ;;
        tunnel)
            # Catch EXIT so that it doesn't close the terminal (since geo runs as a function, not in it's own subshell)
            trap '' EXIT
            ( # Run in subshell to catch EXIT signals
                shift
                local start_ssh='true'
                local prompt_for_cmd='false'
                local list_previous_cmds='false'
                local bind_db_port='false'
                local port=
                local bind_port=
                local user=$USER

                caller_args+=" tunnel"
                _geo__set_terminal_title -G "$caller_args"

                [[ $* =~ --prompt ]] && prompt_for_cmd=true && shift

                local options='-'
                local OPTIND
                while getopts "slLp:P:u:" opt; do
                    options+="$opt"
                    case "${opt}" in
                        s) start_ssh= ;;
                        l) list_previous_cmds=true ;;
                        L) bind_db_port=true ;;
                        p) port="$OPTARG" ;;
                        P)
                            bind_port="$OPTARG"
                            bind_db_port=true
                            ;;
                        u) user="$OPTARG" ;;
                        :) log::getopts_option_invalid_error
                            log::Error "Option '${OPTARG}' expects an argument."
                            return 1
                            ;;
                        \?)
                            log::Error "Invalid option: ${OPTARG}"
                            return 1
                            ;;
                    esac
                done
                shift $((OPTIND - 1))

                if $bind_db_port; then
                    show_iap_password_prompt_message
                fi

                local gcloud_cmd="$*"
                local expected_cmd_start='gcloud compute start-iap-tunnel'
                local iap_cmd_prompt_txt='Enter the gcloud IAP command that was copied from your MyAdmin access request:'
                if [[ $prompt_for_cmd == true ]]; then
                    # prompt_for_info -v gcloud_cmd "$iap_cmd_prompt_txt"
                    prompt_for_info_with_previous_value AR_IAP_CMD gcloud_cmd "$iap_cmd_prompt_txt"
                fi

                if [[ $list_previous_cmds == true ]]; then
                    local prev_commands=$(_geo_ar__get_cmd_tags | tr '\n' ' ')
                    if [[ -n $prev_commands ]]; then
                        log::status -bi 'Enter the number for the gcloud IAP command you want to use:'
                        select tag in $prev_commands; do
                            [[ -z $tag ]] && log::warn "Invalid command number" && continue
                            gcloud_cmd=$(_geo_ar__get_cmd_from_tag $tag)
                            break
                        done
                    else
                        log::warn "'-l' option supplied, but there aren't any previous commands stored to choose from."
                    fi
                fi

                [[ -z $gcloud_cmd ]] && gcloud_cmd="$(@geo_get AR_IAP_CMD)"
                [[ -z $gcloud_cmd ]] && log::Error 'The gcloud compute start-iap-tunnel command (copied from MyAdmin for your access request) is required.' && return 1

                while [[ ! $gcloud_cmd =~ ^$expected_cmd_start ]]; do
                    ! $reuse_msg_shown && log::warn -b "The command must start with 'gcloud compute start-iap-tunnel'" && reuse_msg_shown=true
                    # prompt_for_info -v gcloud_cmd "$iap_cmd_prompt_txt"
                    prompt_for_info_with_previous_value AR_IAP_CMD gcloud_cmd
                done

                local server_tag="$(_geo_ar__get_tag_from_cmd $gcloud_cmd)"
                @geo_set AR_IAP_CMD "$gcloud_cmd"
                _geo_ar__push_cmd "$gcloud_cmd"

                local open_port=
                if [[ -n $port ]]; then
                    local port_open_check_python_code='import socket; s=socket.socket(); s.bind(("", '$port')); s.close()'
                    # 2>&1 redirects the stderr to stdout so that it can be stored in the variable.
                    local port_check_result=$(python3 -c "$port_open_check_python_code" 2>&1)
                    if [[ $port_check_result =~ 'Address already in use' ]]; then
                        log::Error "Port $port is already in use."
                        return 1
                    fi
                    open_port=$port
                fi

                local get_open_port_python_code='import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()'
                [[ -z $open_port ]] && which python >/dev/null && open_port=$(python -c "$get_open_port_python_code")
                # Try using python3 if open port wasn't found.
                [[ -z $open_port ]] && open_port=$(python3 -c "$get_open_port_python_code")
                [[ -z $open_port ]] && log::Error 'Open port could not be found' && return 1

                _geo__set_terminal_title -d -G "$caller_args" "$server_tag" "($open_port)"

                echo

                log::status -bu 'Opening IAP tunnel'

                if [[ -n $open_port ]]; then
                    local port_arg='--local-host-port=localhost:'$open_port

                    @geo_set AR_PORT "$open_port"
                    log::info "Using port: '$open_port' to open IAP tunnel"
                    log::info "Note: the port is saved and will be used when you call '$(log::txt_italic geo ar ssh)'"
                    echo
                    log::debug $gcloud_cmd $port_arg
                    sleep 1
                    echo
                fi

                local geo_config_dir="$(@geo_get CONFIG_DIR)"
                local geo_tmp_ar_dir="$geo_config_dir/tmp/ar"

                [[ ! -d $geo_tmp_ar_dir ]] && mkdir -p "$geo_tmp_ar_dir"

                local ar_request_name="${gcloud_cmd#gcloud compute start-iap-tunnel }"
                ar_request_name="${ar_request_name% 22 --project*}"

                local regex='([[:alnum:]]+-[[:digit:]]+)'
                local connection_file=""

                [[ $gcloud_cmd =~ $regex ]] && ar_request_name="${BASH_REMATCH[1]}"
                [[ -n $open_port ]] && connection_file="$geo_tmp_ar_dir/${ar_request_name}__${open_port}"
                local tmp_output_file="/tmp/geo-ar-tunnel-$(date +%s).txt"
                touch $tmp_output_file

                # Try to listen for changes in connection status.
                monitor_tunnel_status() {
                    log::debug "Monitoring output file for connections status changes..."
                    tail -f $tmp_output_file | while read -d '\n' line; do
                        local width=$((COLUMNS - 15))
                        width=$((width < 0 ? 0 : width))
                        log::debug "line read: ${line:0:$width}..."
                        [[ ${line,,} =~ disconnected|terminated|error  ]] && log::error "gcloud disconnect detected"
                    done
                }
                (monitor_tunnel_status) &

                if [[ $start_ssh ]]; then
                    cleanup() {
                        echo
                        # log::status 'Closing IAP tunnel'
                        # Kill any remaining jobs.
                        for job_pid in $(jobs -p); do kill $job_pid &>/dev/null; done
                        # Remove the temporary output file if it exists.
#                        [[ -f $tmp_output_file ]] && rm $tmp_output_file
                        # Remove the connection file if it exists.
                        [[ -f $connection_file ]] && rm $connection_file
                        exit
                    }
                    # Catch signals and run cleanup function to make sure the IAP tunnel is closed.
                    trap cleanup INT TERM QUIT EXIT

                    # Find the port by opening the IAP tunnel without specifying the port, then get the port number from the output of the gcloud command.
                    if [[ -z $open_port ]]; then
                        log::status "Finding open port..."
                        log::debug "Using log file: $tmp_output_file"
                        $gcloud_cmd &> >(tee -a $tmp_output_file) &
                        local attempts=0

                        # Write the output of the gcloud command to file then periodically scan it for the port number.
                        while ((++attempts < 6)) && [[ -z $open_port ]]; do
                            sleep 1
                            # cat $tmp_output_file
                            # log::debug $tmp_output_file
                            local gcloud_output=$(cat $tmp_output_file)
                            local port_line_regex='unused port \[([[:digit:]]+)\]'
                            if [[ $gcloud_output =~ $port_line_regex ]]; then
                                open_port=${BASH_REMATCH[1]}
                                local is_number_re='^[0-9]+$'
                                if [[ $open_port =~ $is_number_re ]]; then
                                    # kill %1
                                    # sleep 1
                                    break
                                fi
                            fi
                        done
                        [[ -z $open_port ]] && log::Error 'Open port could not be found' && return 1
                        @geo_set AR_PORT "$open_port"
                        log::info "Using port: '$open_port' to open IAP tunnel"
                        log::info "Note: the port is saved and will be used when you call '$(log::txt_italic geo ar ssh)'"
                        echo
                        log::debug $gcloud_cmd $port_arg
                        sleep 1
                        echo
                    else

                        # Set up to test precess substitution:
                        # load the following functions in a terminal
                        # f() {
                        #     local i=0;
                        #     while true; do
                        #         echo $((i++));
                        #         sleep 5;
                        #     done
                        # }
                        # g() {
                        #     while true; do
                        #         read input;
                        #         [[ -n $input ]] && echo "Received: $input";
                        #         sleep 2;
                        #     done
                        # }
                        # Start them using:
                        # { f  || echo FAIL; } &>  >(tee -a test/procsub.log )
                        #
                        # Open another terminal to see that f is piping to g, who inturn pipes the tee, which pipes to both the terminal and the log file.
                        # tail -f test/procsub.log


                        # log::status -bu '\nOpening IAP tunnel'
                        # Start up IAP tunnel in the background.
                        if [[ -n $connection_file ]]; then
                            # log::debug 'running in loc'
                            # Run command with a lock file and capture all of its output the the log file.
                            {
                                run_command_with_lock_file "$connection_file" "$open_port" $gcloud_cmd $port_arg  \
                                    || {
                                        log::Error "failed to start IAP tunnel"
                                        return 1
                                    }
                            } &> >(tee -a $tmp_output_file) &
                                # { f  || echo FAIL; }>  >(tee -a test/procsub.log )
                        else
                            # log::debug 'NOT running in loc'
                            $gcloud_cmd $port_arg  &> >(tee -a $tmp_output_file) &
                        fi
                    fi

                    # Wait for the tunnel to start.
                    log::status 'Waiting for tunnel to open before stating SSH session...'
                    echo
                    sleep 5

                    local opts='-n'

                    if $bind_db_port; then
                        opts+='L'
                        $iap_skip_password && opts+='s'
                        [[ -n $bind_port ]] && opts+=" -P $bind_port "
                    fi

                    local username_option=
                    [[ -n $user ]] && username_option=" -u $user "

                    echo
                    # Continuously ask the user to re-open the ssh session (until ctrl + C is pressed, killing the tunnel).
                    # This allows users to easily re-connect to the server after the session times out.
                    # The -n option tells geo ar ssh not to store the port; the -p option specifies the ssh port.
                    log::debug @geo_ar ssh $opts -p $open_port $username_option
                    @geo_ar ssh $opts -p $open_port $username_option

                    fg
                else
                    if [[ -n $connection_file ]]; then
                        run_command_with_lock_file "$connection_file" "$open_port" $gcloud_cmd $port_arg
                    else
                        $gcloud_cmd $port_arg
                    fi
                fi
            )
            ;;
        ssh)
            set -ve
            shift
            local user=$(@geo_get AR_USER)
            [[ -z $user ]] && user="$USER"
            local port=$(@geo_get AR_PORT)
            local bind_port=5433
            local option_count=0
            local save='true'
            local loop=true
            local bind_db_port=false
            local iap_skip_password=false

            local OPTIND
            while getopts ":nrLsp:P:u:" opt; do
                case "${opt}" in
                    # Don't save port/user if -n (no save) option supplied. This option is used in geo ar tunnel so that re-opening
                    # an SSH session doesn't overwrite the most recent port (from the newest IAP tunnel, which may be different from this one).
                    n) save= ;;
                    # The -r option will cause the ssh tunnel to run ('r' for run) once and then return without looping.
                    r) loop=false ;;
                    p) port="$OPTARG" ;;
                    P)
                        bind_port="$OPTARG"
                        bind_db_port=true
                        ;;
                    u) user="$OPTARG" ;;
                    L) bind_db_port=true ;;
                    s) iap_skip_password=true ;;
                    :)
                        log::Error "Option '${OPTARG}' expects an argument."
                        return 1
                        ;;
                    \?)
                        log::Error "Invalid option: ${OPTARG}"
                        return 1
                        ;;
                esac
            done
            shift $((OPTIND - 1))

            [[ -z $port ]] && log::Error "No port found. Add a port with the -p <port> option." && return 1

            if $bind_db_port && ! $iap_skip_password; then
                show_iap_password_prompt_message
            fi

            echo
            log::status -bu 'Opening SSH session'
            log::info "Using user '$user' and port '$port' to open SSH session."

            [[ $option_count == 0 ]] && log::info "Note: The -u <user> or the -p <port> options can be used to supply different values."
            echo

            if [[ $save == true ]]; then
                @geo_set AR_USER "$user"
                @geo_set AR_PORT "$port"
            fi

            local bind_cmd="ssh -L 127.0.0.1:$bind_port:localhost:5432 -N $user@127.0.0.1 -p $port"
            local cmd="ssh $user@localhost -p $port"

            if $bind_db_port; then
                # log::status -b "Binding local port 5433 to 5432 on remote host (through IAP tunnel)"
                # log::info "geo-cli can configure pgAdmin to connect to Postgres over the IAP tunnel."
                # log::info "Enter your Access Request password below to update the password file for the MyGeotab Over IAP server in pgAdmin, or leave it blank if you already have a server in pgAdmin and plan to update its password manually."
                # log::hint "The MyGeotab Over IAP server needs to be imported once into pgAdmin. The instructions will be shown after you enter your password."
                # log::hint "After it has been added, you only need to paste in your password below to have its passfile updated."

                # local iap_password_prompt="Access Request password:\n> "
                # prompt_for_info_n -v iap_password "$iap_password_prompt"
                log::debug "bind_db_port: iap_password = $iap_password"
                _geo_ar__copy_pgAdmin_server_config --iap "$iap_password" --user "$user"

                log::info -b 'Connect with pgAdmin (if not already set up)'
                log::info "  1. Open pgAdmin"
                log::info "  2. From the toolbar, click $(txt_underline 'Tools > Import/Export Servers')"
                log::info "  3. Paste the following path into the 'Filename' input box and then click $(txt_underline 'Next'):"
                log::data "     $(log::link $GEO_CLI_CONFIG_DIR/data/db/iap-pgAdmin.json)"
                log::info "  4. Click on the $(txt_underline 'Servers') checkbox and then click $(txt_underline 'Next')"
                log::info "  5. Click $(txt_underline 'Finish') to complete the import process"
                echo
                log::info -b "\nAlternatively, you can create a server manually:"
                log::info "Create a new server in pgAdmin via $(txt_underline 'Objects > Register > Server') and enter the following information:"
                log::info "  Name: MyGeotab IAP (or whatever you want)"
                log::info "  Connection tab"
                log::info "    Host: localhost"
                log::info "    Port: $bind_port"
                log::info "    Maintenance database: postgres"
                log::info "    Username: $user"
                log::info "    Password: the one you got from MyAdmin when you created the Access Request"

                log::hint "\nYou can also open another terminal and start an ssh session with the server using $(txt_underline geo ar ssh)"
                cmd="$bind_cmd"
            fi

            # Run the ssh command once and then return if loop was disabled (with the -r option)
            if [[ $loop == false ]]; then
                log::debug "\n$cmd"
                echo
                $cmd
                return
            fi

            # Continuously ask the user to re-open the ssh session (until ctrl + C is pressed, killing the tunnel).
            # This allows users to easily re-connect to the server after the session times out.
            while true; do
                log::debug "\n$cmd"
                echo
                sleep 1
                # Run ssh command.
                $cmd
                echo
                sleep 1
                log::status -bu 'SSH closed'
                log::info "Options:"
                log::info "    - Press ENTER to SSH back into the server"
                log::info "    - Press CTRL + C to close this tunnel (running on port: $open_port)"
                log::info "    - Open a new terminal and run $(txt_underline geo ar ssh) to reconnect to this tunnel"
                log::caution "If the this fails multiple times, the IAP tunnel may have bee closed. You can type 'restart' and press enter to try to restart the IAP tunnel, or you can close this window and start a new one through the geo-ui menu. If that doesn't work, then you're access request may have expired."
                # log::status 'SSH closed. Listening to IAP tunnel again. Open a new terminal and run "geo ar ssh" to reconnect to this tunnel.'
                read response
                [[ $response =~ r.* ]] && {
                    @geo_ar "${arguments[@]}"
                    break
                }
                log::status -bu 'Reopening SSH session'
                echo
                sleep 1
            done
            ;;

        kill-iap-by-port | kill-iap | kiap)
            local port=$2
            [[ ! $port =~ [[:digit:]]+ ]] && log::Error "$FUNCNAME:kill-iap-by-port: '$port' is not a valid port." && return 1
            local tunnel_pid="$(ps -ef | grep localhost:$port | grep -v grep | awk '{print $2}')"
#            local tunnel_pid="$(ps -ef | grep localhost:$port | grep -v grep | cut -d' ' -f 2)"
            log::debug "ps -ef | grep localhost:52879 | grep -v grep | cut -d' ' -f 2"
            [[ ! $tunnel_pid =~ [[:digit:]]+ ]] && log::Error "$FUNCNAME:kill-iap-by-port: '$tunnel_pid' failed to find pid for IAP tunnel with port '$port'." && return 1
            kill $tunnel_pid && log::success "IAP tunnel killed" || log::Error "Failed to kill IAP tunnel"
            ;;
        list-iap-processes | ls-iap) ps -ef | grep start-iap-tunnel
            ;;
        *)
            log::Error "$FUNCNAME: Unknown subcommand '$1'"
            ;;
    esac
}

# TODO: look into lockfile command.
# Create a lock file so that the UI can see how many open IAP tunnels there are.
run_command_with_lock_file() {
    local lock_file="$1"
    local lock_file_content="$2"
    local cmd="${@:3}"

    [[ -f $lock_file ]] && _geo_remove_file_if_older_than_last_reboot "$lock_file" &>/dev/null
    touch "$lock_file"

    trap '' EXIT
    (
        cleanup() {
            # Unlock file descriptor.
            flock -u "$FD"
            [[ -f $lock_file ]] && { rm "$lock_file" &>/dev/null || log::Error "Failed to remove lock file"; }
            # log::warn "run_command_with_lock_file: cleaned up successfully after interrupt"
            exit
        }

        trap cleanup SIGINT SIGTERM ERR EXIT
        local FD
        # Create file descriptor for the lock file.
        exec {FD}<>$lock_file
        echo "$lock_file_content" >"$lock_file"
        # trap all interrupts and remove the lock file

        # Get an exclusive lock on file descriptor 200, waiting only 5 second before timing out.
        if ! flock -x -w 5 $FD; then
            log::Error "run_command_with_lock_file: failed to lock port info file at: $lock_file."
            return 1
        fi

        # debug "Running command: $cmd"
        # Run command.
        $cmd

        # Unlock file descriptor.
        flock -u "$FD"

        # Remove lock file.
        [[ -f $lock_file ]] && rm "$lock_file" || log::Error "Failed to remove lock file"
    )

}

# get_lock() {
#     local file="$1";
#     local cmd="
#     local fd
#     exec {fd}<>$file;
#     flock -w 1 $fd && echo got lock || echo 'failed to get lock'
#     ";
#     echo "eval '$cmd'"
# }

# Save the previous 5 gcloud commands as a single value in the config file, delimited by the '@' character.
_geo_ar__push_cmd() {
    local cmd="$1"
    [[ -z $cmd ]] && return 1
    local prev_commands="$(@geo_get AR_IAP_CMDS)"

    if [[ -z $prev_commands ]]; then
        # log::debug "_geo_ar__push_cmd[$LINENO]: cmds was empty"
        @geo_set AR_IAP_CMDS "$cmd"
        return
    fi
    # Remove duplicates if cmd is already stored.
    prev_commands="${prev_commands//$cmd/}"
    # Remove any delimiters left over from removed commands.
    # The patterns remove lead and trailing @, as well as replaces 2 or more @ with a single one (3 patterns total).
    prev_commands=$(echo $prev_commands | sed -r 's/^@//; s/@$//; s/@{2,}/@/g')

    if [[ -z $prev_commands ]]; then
        # Can happen when there is only one item stored and the new item being added is a duplicate.
        # log::Error "_geo_ar__push_cmd[$LINENO]: cmds was empty"
        return
    fi
    # Add the new command to the beginning, delimiting it with the '@' character.
    prev_commands="$cmd@$prev_commands"
    # Get the count of how many commands there are.
    local count=$(echo $prev_commands | awk -F '@' '{ print NF }')
    #    log::debug $count
    if ((count > 5)); then
        # Remove the oldest command, keeping only 5.
        prev_commands=$(echo $prev_commands | awk -F '@' '{ print $1"@"$2"@"$3"@"$4"@"$5 }')
    fi
    #    log::debug @geo_set AR_IAP_CMDS "_geo_ar__push_cmd: setting cmds to: $prev_commands"
    @geo_set AR_IAP_CMDS "$prev_commands"
}

_geo_ar__get_tag_from_cmd() {
    local include_date=false
    [[ $1 =~ ^-f|--full ]] && include_date=true && shift
    # Extracts supportpql5 from commands like the following:
    # gcloud compute start-iap-tunnel supportpql5-20230305060936 22 ...
    local tag="$(echo "$@" | awk '{ print $4 }')"
    $include_date && echo "$tag" && return
    echo "${tag%-*}"
}

_geo_ar__get_cmd_tags() {
    geo get AR_IAP_CMDS | tr '@' '\n' | awk '{ print $4 }'
}

_geo_ar__get_cmd_from_tag() {
    [[ -z $1 ]] && return
    geo get AR_IAP_CMDS | tr '@' '\n' | grep "$1"
}

_geo_ar__get_cmd() {
    local cmd_number="$1"
    [[ -z $cmd_number || $cmd_number -gt 5 || $cmd_number -lt 0 ]] && log::Error "Invalid command number. Expected a value between 0 and 5." && return 1

    local cmds=$(@geo_get AR_IAP_CMDS)
    if [[ -z $cmds ]]; then
        return
    fi
    local awk_cmd='{ print $'$cmd_number' }'
    echo $(echo $cmds | awk -F '@' "$awk_cmd")
}

_geo_ar__get_cmd_count() {
    local cmds=$(@geo_get AR_IAP_CMDS)
    # Get the count of how many commands there are.
    local count=$(echo $cmds | awk -F '@' '{ print NF }')
    echo $count
}

#######################################################################################################################
@register_geo_cmd 'stop'
@geo_stop_doc() {
    doc_cmd 'stop'
    doc_cmd_desc 'Stops all geo-cli containers.'
    doc_cmd_examples_title
    doc_cmd_example 'geo stop'
}
@geo_stop() {
    @geo_db stop "$1"
}

geo_is_valid_repo_dir() {
    test -d "${1}/Checkmate"
}

#######################################################################################################################
@register_geo_cmd  'init'
@geo_init_doc() {
    doc_cmd 'init'
    doc_cmd_desc 'Initialize repo directory.'

    doc_cmd_sub_cmd_title
        doc_cmd_sub_cmd 'repo'
            doc_cmd_sub_cmd_desc 'Init Development repo directory using the current directory.'
        doc_cmd_sub_cmd 'npm'
            doc_cmd_sub_cmd_desc "Runs 'npm install' in both the wwwroot and drive CheckmateServer directories. This is a quick way to fix the npm dependencies after switching to a different MYG release branch."
        doc_cmd_sub_cmd 'pat'
            doc_cmd_sub_cmd_desc "Sets up the GitLab Personal Access Token environment variables."
            doc_cmd_sub_option_title
                doc_cmd_sub_option '-r'
                    doc_cmd_sub_option_desc 'Removes the PAT environment variables.'
                doc_cmd_sub_option '-l, --list'
                    doc_cmd_sub_option_desc 'List/display the current PAT environment variable file.'
                doc_cmd_sub_option '-v, --valid [PAT]'
                    doc_cmd_sub_option_desc 'Checks if the current PAT environment variable (or one that is supplied as an argument) is valid.'
        doc_cmd_sub_cmd 'git-hook'
            doc_cmd_sub_cmd_desc 'Add the prepare-commit-msg git hook to the Development repo. This hook prepends the Jira issue number in the branch name (e.g. for a branch named MYG-50500-my-branch, the issue number would be MYG-50500) to each commit message. So when you commit some changes with the message "Add test", the commit message would be automatically modified to look like this: [MYG-50500] Add test.'
            doc_cmd_sub_option_title
                doc_cmd_sub_option '-s, --show'
                    doc_cmd_sub_option_desc 'Print out the prepare-commit-msg hook code'

    doc_cmd_examples_title
        doc_cmd_example 'geo init repo'
        doc_cmd_example 'geo init npm'
        doc_cmd_example 'geo init git-hook'
}
@geo_init() {
    local ui_mode=false
    [[ $1 == '--' ]] && shift
    [[ $1 == --ui ]] && ui_mode=true && shift

    case $1 in
        'repo' | '')
            local repo_dir=$(pwd)
            [[ $1 == repo && -n $2 ]] && repo_dir="$2"
            if ! geo_is_valid_repo_dir "$repo_dir"; then
                log::warn "MyGeotab repo not found in current directory:"
                log::link "$repo_dir\n"
                # log::status "Searching for possible repo locations..."
                _geo_init__find_myg_repo -v repo_dir
                [[ -z $repo_dir ]] && log::log::Error "\nFailed to locate the MyGeotab repo directory." && return 1
            fi
            local current_repo_dir=$(@geo_get DEV_REPO_DIR)
            if [[ -n $current_repo_dir ]]; then
                log::info -b "Current Mygeotab Development repo directory is:"
                log::info "    $current_repo_dir"
                if ! prompt_continue "Would you like to replace that with the current directory? (Y|n): "; then
                    return
                fi
            fi
            @geo_set DEV_REPO_DIR "$repo_dir"
            log::status "MyGeotab base repo (Development) path set to:"
            log::link "    $repo_dir"
            ;;
        npm)
            local close_delayed=false
            local arg="$2"
            [[ $arg == -c ]] && close_delayed=true
            (
                local fail_count=0

                local current_repo_dir=$(@geo_get DEV_REPO_DIR)
                [[ -z $current_repo_dir ]] && log::Error "MyGeotab repo directory not set." && return 1

                cd $current_repo_dir/Checkmate/CheckmateServer/src/wwwroot
                # Possible error if you switch nodejs version and don't update the symlinks in /usr/bin (node, npm, and npx) to point to the new version. The PATH variable that is available in the non-interactive terminal (used by geo-ui) is different than the one available in the interactive terminal (uses .bash_profile).
                # log::debug $PATH
                log::status -b '\nInstalling npm packages for CheckmateServer/src/wwwroot\n'
                npm i || ((fail_count++))
                log::status -b '\nInstalling npm packages for CheckmateServer/src/wwwroot/drive\n'
                cd drive
                npm i || ((fail_count++))
                # log::debug "fail $fail_count"
                ((fail_count == 0))
            )

            if [[ $? != 0 ]]; then
                log::Error "npm install failed $"
                if [[ $close_delayed == true ]]; then
                    log::detail 'Press Enter to exit'
                    read
                    exit 1
                fi
                return 1
            fi

            log::success 'npm install was successful'
            if [[ $close_delayed == true ]]; then
                log::detail 'closing in 5 seconds'
                sleep 5
                exit 0
            fi
            ;;
        pat)
            _geo_init__pat "${@:2}"
            ;;
        git-hook* | git | gh)
            _geo_init__git_hook "${@:2}"
            ;;
        auto-switch | as)
            _geo_init__auto_switch "${@:2}"
            ;;
    esac
}

_geo_init__auto_switch() {
    local dev_repo_dir=$(@geo_get DEV_REPO_DIR)
    (
        cd "$dev_repo_dir"
        local myg_branches="$(git branch -r | sed 's/  //g' | grep --color=never -P '^origin/(release/\d+\.0|main)$')"
        local branches=("${myg_branches[@]}")
        if [[ -z ${branches[*]} ]]; then
            log::Error "Counldn't find any release branches in repo root: "
            log::link "$dev_repo_dir"
            return 1
        fi

        log::data_header "$(printf '%-4s %-42s\n' ID Release)"
        for branchId in "${!branches[@]}"; do
            branch="${branches[branchId]}"
            printf '%-4d %-42s\n' $branchId "${branch#origin/}"
        done

        local branch_count=${#branches[@]}
        local ids=
        _geo_prompt_for_ids ids $((branch_count - 1)) "Enter the ids (space separated) for the branches you would like to create database containers for:"
        echo "the ids: $ids"
    )
}

# Prompts the user for 1 or more ids.
#   1: the name of the variable ref to store the result in.
#   2: the max number of ids.
#   3: the text to prompt the user to enter ids.
_geo_prompt_for_ids() {
    local -n result_ref=$1
    local max_id=$2
    local prompt_txt="$3"
    local input_ids
    local valid_input=false

    until $valid_input; do
        prompt_for_info -v input_ids "$prompt_txt"
        # Make sure the input consists of only numbers separated by spaces.
        while [[ ! $input_ids =~ ^( *[0-9]+ *)+$ ]]; do
            log::warn 'Invalid input. Only space-separated integer IDs are accepted'
            prompt_for_info -v input_ids "$prompt_txt"
        done
        # Make sure the numbers are valid ids between 0 and max_id.
        for id in $input_ids; do
            if ((id < 0 | id > max_id)); then
                log::warn "Invalid ID: ${id}. Only IDs from 0 to ${max_id} are valid"
                # Set valid_input = false and break out of this for loop, causing the outer until loop to run again.
                valid_input=false
                break
            fi
            valid_input=true
        done
        if [[ $valid_input == true ]]; then
            result_ref="$input_ids"
        fi
    done
}

_geo_search_for_myg_repo_dir() {
    find "$HOME" -maxdepth ${1:-10} -type f -path '*Checkmate/MyGeotab.Core.csproj'
}

_geo_init__find_myg_repo() {
    local repo_path=
    local passed_ref=false
    if [[ $1 == -v ]]; then
        local -n repo_path="$2"
        passed_ref=true
        shift 2
    fi
    # [[ -f $* ]] && log::warn "The provided path MyGeotab repo path is invalid\n"

    log::status -b "Searching for MyGeotab repos..."

    # Search for possible locations for the MyG repo.
    local possible_repos="$(_geo_search_for_myg_repo_dir)"
    # echo 1
    # e possible_repos
    if [[ -n $possible_repos ]]; then
        # possible_repos="${possible_repos//\/Checkmate/MyGeotab.Core.csproj/}"
        possible_repos="${possible_repos//\/Checkmate\/MyGeotab.Core.csproj/}"
    else
        log::debug "find "$HOME" -maxdepth 10 -type f -path '*Checkmate/MyGeotab.Core.csproj'\n"

        log::caution "\ngeo-cli searched for the MyGeotab Development repo, but wasn't able to find it.\n"
        log::status -b "Fix:"
        log::info "1) Ensure you have cloned the MyGeotab repo:"
        log::code "    git clone git@git.geotab.com:dev/Development.git"
        log::info "2) Either re-run this command with the path to the MyGeotab repo; or"
        log::info "3) cd into the repo directory and run this command without any arguments\n"
        return
    fi
    echo 3

    # Strip Checkmate/MyGeotab.Core.csproj from the end of each path.
    # possible_repos="${possible_repos//\/Checkmate\/MyGeotab.Core.csproj/}"

    local path_count="$(wc -l <<<"$possible_repos")"
    if ((path_count == 1)); then
        log::status "Found the following path for the MyGeotab repo:"
        log::link -r "   $possible_repos"

        prompt_continue "Is the above path the correct location of the MyGeotab repo? (Y/n): " || return 1

        repo_path="$possible_repos"
        $passed_ref && return
        prompt_return="$repo_path"
        return
    fi
    if [[ path_count -gt 1 ]]; then
        echo 111
        PS3="$(log::prompt 'Enter the number of the correct repo path: ')"
        # ! TODO: Separate lines in a way that accounts for the word splitting that occurs when possible_repos is created.
        # Files with space in there names will be split.
        opts=($possible_repos)
        select option in "${opts[@]}"; do
            [[ -z $option ]] && log::warn "Invalid option: '$REPLY'" && continue
            repo_path="$option"
            break
        done
    fi

    $passed_ref && return
    prompt_return="$repo_path"
}

_geo_init__git_hook() {
    _geo_check_for_dev_repo_dir
    local dev_repo=$(@geo_get DEV_REPO_DIR)
    local geo_src_dir=$(@geo_get SRC_DIR)
    # cd "$dev_repo"
    if [[ ! -d $dev_repo/.git/hooks ]]; then
        log::Error ".git/hooks directory doesn't exist in Development repo directory."
        return 1
    fi

    hook="$geo_src_dir/includes/git/prepare-commit-msg"
    destination_hook_path="$dev_repo/.git/hooks/prepare-commit-msg"
    if [[ -f $destination_hook_path ]]; then
        log::warn "The $(txt_underline prepare-commit-msg) git hook already exists in the Development repo."
        prompt_continue "Would you like to replace the exiting $(txt_underline prepare-commit-msg) commit hook (Y|n): " || return 1
    fi
    [[ $1 == --show || $1 == -s ]] && cat "$hook" && return
    if ! cp "$hook" "$dev_repo/.git/hooks/prepare-commit-msg"; then
        log::Error "Failed to copy git hook to: $dev_repo/.git/hooks/"
        return 1
    fi
    log::success "prepare-commit-msg git hook added to Development repo"

}

_geo_init__pat() {
    mkdir -p "$GEO_CLI_CONFIG_DIR/env"
    local pat_env_file_path="$GEO_CLI_CONFIG_DIR/env/gitlab-pat.sh"

    case $1 in
        -r | --remove)
            if prompt_continue "Remove geo-cli PAT environment variable initialization? (Y|n)"; then
                rm "$pat_env_file_path" && log::success "Done" || log::Error "Failed to remove file"
            fi
            return
            ;;
        -l | --list)
            if [[ ! -f $pat_env_file_path ]]; then
                log::Error "PAT environment variable file doesn't exist"
                [[ -z $GITLAB_PACKAGE_REGISTRY_USERNAME && -z $GITLAB_PACKAGE_REGISTRY_PASSWORD ]] && return 1
                log::warn "The PAT environment variables are NOT defined by geo-cli, but do exist in the environment:"
                log::data "    GITLAB_PACKAGE_REGISTRY_USERNAME=$(log::detail $GITLAB_PACKAGE_REGISTRY_USERNAME)"
                log::data "    GITLAB_PACKAGE_REGISTRY_PASSWORD=$(log::detail $GITLAB_PACKAGE_REGISTRY_PASSWORD)"
                return
            fi
            cat "$pat_env_file_path"
            return
            ;;
        -v | --valid)
            [[ -z $GITLAB_PACKAGE_REGISTRY_PASSWORD && -z $2 ]] && Error "GITLAB_PACKAGE_REGISTRY_PASSWORD is not defined." && return 1
            local pat=${2:-$GITLAB_PACKAGE_REGISTRY_PASSWORD}
            _geo_init__is_pat_valid "$pat" && log::success "PAT is valid" || {
                log::Error "PAT is not valid. Response: '$pat_check_result'"
                return 1
            }
            return
            ;;
        -*)
            log::Error "Invalid option: '$1'"
            return 1
            ;;
    esac

    log::info "Note: This feature automates the environment variable setup from the following GitLab PAT setup guide:"
    log::link "https://docs.google.com/document/d/13TbaF2icEWqtxg1altUbI0Jn18KxoSPb9eKvKuxcxHg/edit?hl=en&forcehl=1"
    echo
    prompt_for_info "Enter your GitLab username (what comes before @geotab.com): "
    local username="$prompt_return"
    echo
    log::status -b "Create your GitLab Personal Access Token (PAT) at the following link and then paste it in below:"
    log::link "https://git.geotab.com/-/profile/personal_access_tokens?name=geotab-gitlab-package-repository&scopes=read_api"

    while true; do
        echo
        prompt_for_info_n "Enter your GitLab PAT: "
        local pat="$prompt_return"

        if ! _geo_init__is_pat_valid "$pat"; then
            log::warn "The PAT entered could not be validated"
            log::warn "The expected return value was '[]' but got this instead: '$pat_check_result'"
            if prompt_continue "Would you like to use this PAT anyways? (Y|n): "; then
                break
            fi
            continue
        fi
        log::success "PAT is valid"
        break
    done
    cat <<-EOF >"$pat_env_file_path"
export GITLAB_PACKAGE_REGISTRY_USERNAME=$username
export GITLAB_PACKAGE_REGISTRY_PASSWORD=$pat
EOF
    chmod 600 "$pat_env_file_path"

    # Export the variables here so that they will be available in this terminal.
    export GITLAB_PACKAGE_REGISTRY_USERNAME=$username
    export GITLAB_PACKAGE_REGISTRY_PASSWORD=$pat

    echo
    log::info "Evironment variables created:"
    log::data "    GITLAB_PACKAGE_REGISTRY_USERNAME=$(log::detail $username)"
    log::data "    GITLAB_PACKAGE_REGISTRY_PASSWORD=$(log::detail $pat)"
    echo
    log::info "Variable file created at:"
    log::data "    $pat_env_file_path"
    echo
    log::success "Done"
}

_geo_init__is_pat_valid() {
    local pat="$1"
    local repo_url='https://git.geotab.com/api/v4/projects/4953/registry/repositories'
    local curl_command='curl --header "PRIVATE-TOKEN: '$pat'" "'$repo_url'"'
    local curl_args=(--header "PRIVATE-TOKEN: $pat" "$repo_url")
    log::status -b "Testing PAT using the following command:"
    log::data $curl_command

    pat_check_result=$(curl "${curl_args[@]}")

    [[ $pat_check_result == '[]' ]]
}

#######################################################################################################################
# COMMANDS+=('start')
# @geo_start_doc() {
#     doc_cmd 'start <service>'
#     doc_cmd_desc 'Start individual service.'
#     doc_cmd_examples_title
#     doc_cmd_example 'geo start web'
# }
# @geo_start() {
#     exit_if_repo_dir_uninit
#     if [ -n "${SERVICES_DICT[$1]}" ]; then
#         if [[ $1 = 'runner' ]]; then
#             # pm2-runtime start $GEO_REPO_DIR/runner/.geo-cli/ecosystem.config.js
#             @geo_runner start
#         else
#             cd $GEO_REPO_DIR/env/full
#             dc_geo start $1
#         fi
#     else
#         log::Error "$1 is not a service"
#     fi
# }

# #######################################################################################################################
# COMMANDS+=('stop')
# @geo_stop_doc() {
#     doc_cmd 'stop <service>'
#     doc_cmd_examples_title
#     doc_cmd_example 'geo stop web'
# }
# @geo_stop() {
#     exit_if_repo_dir_uninit
#     if [ -z $1 ]; then
#         dc_geo stop
#         return
#     fi
#     if [ -n "${SERVICES_DICT[$1]}" ]; then
#         if [[ $1 = 'runner' ]]; then
#             pm2 stop runner
#         else
#             cd $GEO_REPO_DIR/env/full
#             dc_geo stop "$1"
#         fi
#     else
#         log::Error "$1 is not a service"
#     fi
# }

#######################################################################################################################
# COMMANDS+=('restart')
# @geo_restart_doc() {
#     doc_cmd 'restart [service]'
#     doc_cmd_desc 'Restart container [service] or the entire system if no service is provided.'
#     doc_cmd_examples_title
#     doc_cmd_example 'geo restart web'
#     doc_cmd_example 'geo restart'
# }
# @geo_restart() {
#     exit_if_repo_dir_uninit
#     if [ -z $1 ]; then
#         # @geo_down
#         @geo_stop
#         @geo_up
#         @geo_runner restart
#         return
#     fi

#     if [ -n "${SERVICES_DICT[$1]}" ]; then
#         if [[ $1 = 'runner' ]]; then
#             # pm2 restart runner
#             @geo_runner restart
#         else
#             cd $GEO_REPO_DIR/env/full
#             dc_geo restart "$1"
#         fi
#     else
#         log::Error "$1 is not a service"
#     fi
# }

#######################################################################################################################
@register_geo_cmd 'env'
@geo_env_doc() {
    doc_cmd 'env <cmd> [arg1] [arg2]'
    doc_cmd_desc 'Get, set, or list geo environment variable.'

    doc_cmd_sub_cmd_title
        doc_cmd_sub_cmd 'get <env_var>'
            doc_cmd_sub_cmd_desc 'Gets the value for the env var.'

        doc_cmd_sub_cmd 'set <env_var> <value>'
            doc_cmd_sub_cmd_desc 'Sets the value for the env var.'

        doc_cmd_sub_cmd 'rm <env_var>'
            doc_cmd_sub_cmd_desc 'Remove geo environment variable.'

        doc_cmd_sub_cmd 'ls'
            doc_cmd_sub_cmd_desc 'Lists all env vars.'

    doc_cmd_examples_title
    doc_cmd_example 'geo env get DEV_REPO_DIR'
    doc_cmd_example 'geo env set DEV_REPO_DIR /home/username/repos/Development'
    doc_cmd_example 'geo env ls'
}
@geo_env() {
    # Check if there is any arguments.
    if [[ -z $1 ]]; then
        @geo_env_doc
        return
    fi

    case $1 in
        'set')
            # Get the key from the second arg.
            local key="$2"
            # Get the new value by concatenating the rest of the args together.
            local value="${@:3}"
            @geo_set -s "$key" "$value"
            ;;
        'get')
            # Show error message if the key doesn't exist.
            @geo_haskey "$2" || {
                log::Error "Key '$2' does not exist."
                return 1
            }
            @geo_get "$2"
            ;;
        'rm')
            # Show error message if the key doesn't exist.
            @geo_haskey "$2" || {
                log::Error "Key '$2' does not exist."
                return 1
            }
            @geo_rm "$2"
            ;;
        'ls')
            if [[ $2 == keys ]]; then
                awk -F= '{ gsub("GEO_CLI_","",$1); printf "%s ",$1 } ' $GEO_CLI_CONF_FILE | sort
                return
            fi
            # Alternative way: column -s '=' --table -l 2 -N Key,Value -T Value .geo-cli/.geo.conf
            local header=$(printf "%-26s %-26s\n" 'Variable' 'Value')
            local env_vars=$(awk -F= '{ gsub("GEO_CLI_","",$1); printf "%-26s %-26s\n",$1,$2 } ' $GEO_CLI_CONF_FILE | sort)
            log::info -b "$header"
            log::data "$env_vars"
            ;;
        *)
            log::Error "Unknown subcommand '$1'"
            ;;
    esac
}

#######################################################################################################################
@register_geo_cmd 'set'
@geo_set_doc() {
    doc_cmd 'set <env_var> <value>'
    doc_cmd_desc 'Set geo environment variable.'
    doc_cmd_options_title
    doc_cmd_option 's'
    doc_cmd_option_desc 'Shows the old and new value of the environment variable.'
    doc_cmd_examples_title
    doc_cmd_example 'geo set DEV_REPO_DIR /home/username/repos/Development'
}
@geo_set() {
    # Set value of geo-cli env var
    # $1 - name of env var in conf file
    # $2 - value
    local initial_line_count=$(wc -l $GEO_CLI_CONF_FILE | awk '{print $1}')
    local conf_backup=$(cat $GEO_CLI_CONF_FILE)
    local show_status=false
    local shifted=false
    local shifted='config'
#    [[ $1 == -s ]] && show_status=true && shift

    [[ -v GEO_CONFIG_LOG ]] && log::debug "@geo_set: $*"

    local OPTIND
    while getopts ":sp" opt; do
        case "${opt}" in
            s ) show_status=false ;;
            p ) json_path="${OPTARG}" ;;
            # Standard error handling.
            : ) log::Error "Option '${OPTARG}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${OPTARG}"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    # To uppercase.
    local key="${1^^}"
    local geo_key="$key"
    shift

    local json_key="${json_path}.${key#GEO_CLI_}"
    # To lowercase.
    json_key="${key,,}"
    json_key="${json_key//_/-}"

    [[ ! $key =~ ^GEO_CLI_ ]] && geo_key="GEO_CLI_${key}"

    local value="$@"
    local old=$(cfg_read $GEO_CLI_CONF_FILE "$geo_key")

    local value_changed=true
    [[ $value == $old ]] && value_changed=false

    # Only write to file if the value has changed.
    if [[ $value_changed == true ]]; then
        (
            # Get an exclusive lock on file descriptor 200, waiting only 5 second before timing out.
            flock -w 5 -e 200
            # Check if the lock was successfully acquired.
            (($? != 0)) && log::Error "'geo set' failed to lock config file after timeout. Key: $geo_key, value: $value." && return 1
            # Write to the file atomically.
            cfg_write $GEO_CLI_CONF_FILE "$geo_key" "$value"
            # Open up the lock file for writing on file descriptor 200. The lock is release as soon as the subshell exits.
            _geo_jq_set -i -L "$json_key" "$value" "$GEO_CLI_CONF_JSON_FILE"
        ) 200>/tmp/.geo.conf.lock
        [[ $? != 0 ]] && return 1
    fi

    # local final_line_count=$(wc -l $GEO_CLI_CONF_FILE | awk '{print $1}')

    # log::debug "$initial_line_count, $final_line_count"
    # log::debug "$conf_backup"
    # Restore original configuration file and try to write to it again. The conf file can be corrupted
    # if two processes try to write to it at the same time.
    # if (( final_line_count < initial_line_count )); then
    #     echo "$conf_backup" > $GEO_CLI_CONF_FILE
    #     [[ $value_changed == true ]] && cfg_write $GEO_CLI_CONF_FILE "$geo_key" "$value"
    # fi

    if [[ $show_status == true ]]; then
        log::info -b "$key"
        log::info -p '  New value: ' && log::data "$value"
        if [[ -n $old ]]; then
            log::info -p '  Old value: ' && log::data "$old"
        fi
    fi
}

#######################################################################################################################
@register_geo_cmd 'get'
@geo_get_doc() {
    doc_cmd 'get <env_var>'
    doc_cmd_desc 'Get geo environment variable.'

    doc_cmd_examples_title
    doc_cmd_example 'geo get DEV_REPO_DIR'
}
@geo_get() {
    [[ -v GEO_CONFIG_LOG ]] && log::debug "@geo_get: $*"
    # Get value of env var.
    local key="${1^^}"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"

    value=$(cfg_read $GEO_CLI_CONF_FILE $key)

    # Prevent the geo-cli repo dir from being set to ''.
    [[ $key == GEO_CLI_DIR && -z $value && -n $GEO_CLI_DIR ]] && value="$GEO_CLI_DIR"

    [[ -z $value ]] && return
    local opts=
    [[ $GEO_RAW_OUTPUT == true ]] && opts=-n
    echo $opts "$value"
}

@register_geo_cmd 'haskey'
@geo_haskey_doc() {
    doc_cmd 'haskey <env_var>'
    doc_cmd_desc 'Checks if a geo environment variable exists.'

    doc_cmd_examples_title
    doc_cmd_example 'geo haskey DEV_REPO_DIR'
}
@geo_haskey() {
    local key="${1^^}"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"
    cfg_haskey $GEO_CLI_CONF_FILE "$key"
}

#######################################################################################################################
@register_geo_cmd 'rm'
@geo_rm_doc() {
    doc_cmd 'rm <env_var>'
    doc_cmd_desc 'Removes a geo environment variable.'

    doc_cmd_examples_title
    doc_cmd_example 'geo rm DEV_REPO_DIR'
}
@geo_rm() {
    [[ -v GEO_CONFIG_LOG ]] && log::debug "$FUNCNAME: $*"

    [[ $# -gt 1 ]] && log::Error "$FUNCNAME takes exactly one argument, the name of the key that is to be removed from geo-cli's config data. Did you mean to run 'geo db rm [list of dbs to remove]' instead?"
    # Get value of env var.
    local key="${1^^}"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"

    ! @geo_haskey "$key" && return 1

    (
        # Get an exclusive lock on file descriptor 200, waiting only 5 second before timing out.
        flock -w 5 -e 200
        # Check if the lock was successfully acquired.
        (($? != 0)) && log::Error "'geo rm' failed to lock config file after timeout. Key: $key" && return 1
        # Write to the file atomically.
        cfg_delete "$GEO_CLI_CONF_FILE" "$key"
        # Open up the lock file for writing on file descriptor 200. The lock is release as soon as the subshell exits.
    ) 200>/tmp/.geo.conf.lock
    [[ $? != 0 ]] && return 1
}

#@geo_haskey() {
#    local key="${1^^}"
#    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"
#    cfg_haskey "$GEO_CLI_CONF_FILE" "$key"
#}

# Save the previous 5 items as a single value in the config file, delimited by the '@' character.
_geo_push() {
    local key="$1"
    local value="$2"
    [[ -z $key ]] && log::Error "_geo_push: Key cannot be empty" && return 1
    [[ -z $value ]] && log::Error "_geo_push: Value cannot be empty" && return 1
    local stored_items="$(@geo_get $key)"

    if [[ -z $stored_items ]]; then
        # log::debug "_geo_push: stored_items was empty"
        @geo_set $key "$value"
        return
    fi
    # Remove duplicates if cmd is already stored.
    stored_items="${stored_items//$value/}"
    # Remove any delimiters left over from removed items.
    # The patterns remove lead and trailing @, as well as replaces 2 or more @ with a single one (3 patterns total).
    stored_items=$(echo $stored_items | sed -r 's/^@//; s/@$//; s/@{2,}/@/g')

    if [[ -n $stored_items ]]; then
        # Add the new item to the beginning, delimiting it with the '@' character.
        stored_items="$value@$stored_items"
    else
        stored_items="$value"
    fi

    # Get the count of how many items there are.
    local count=$(echo $stored_items | awk -F '@' '{ print NF }')
    #    log::debug $count
    if ((count > 5)); then
        # Remove the oldest item, keeping only 5.
        stored_items=$(echo $stored_items | awk -F '@' '{ print $1"@"$2"@"$3"@"$4"@"$5 }')
    fi
    #    log::debug @geo_set $key "_geo_push: setting cmds to: $stored_items"
    @geo_set $key "$stored_items"
}

_geo_push_get_items() {
    [[ -z $1 ]] && return
    @geo_get $1 | tr '@' '\n'
}

_geo_push_get_item() {
    local key="$1"
    local item_number="$2"
    [[ -z $item_number || $item_number -gt 5 || $item_number -lt 0 ]] && log::Error "Invalid command number. Expected a value between 0 and 5." && return 1

    local items=$(@geo_get $key)
    if [[ -z $items ]]; then
        return
    fi
    local awk_cmd='{ print $'$item_number' }'
    echo $(echo $items | awk -F '@' "$awk_cmd")
}

# Use node to get/modify json
# $ read -r -d '' js <<-'EOF'
# > 'let a1=process.argv[1]; let a2=process.argv[2];eval(`a=${a2}`); eval(`r=a.${a1}`);console.log(a, " = ", r)
# > ^C
# ✘ dawsonmyers:~
# $ read -r -d '' js <<-'EOF'
# > let a1=process.argv[1];
# > let a2=process.argv[2];
# > eval(`a=${a2}`);
# > eval(`r=a.${a1}`);
# > console.log(a, " = ", r)
# > EOF
# ✘ dawsonmyers:~
# $ code -e "$js" 'x.b'
# Warning: 'e' is not in the list of known options, but still passed to Electron/Chromium.
# ✔ dawsonmyers:~
# $ code -e "$js" 'x.b' '{x: {b: 10}, y:{z:{zz:"hello"}}}'
# Warning: 'e' is not in the list of known options, but still passed to Electron/Chromium.
# ✔ dawsonmyers:~
# $ node -e "$js" 'x.b' '{x: {b: 10}, y:{z:{zz:"hello"}}}'
# { x: { b: 10 }, y: { z: { zz: 'hello' } } }  =  10
# ✔ dawsonmyers:~
# $ node -e "$js" 'y.z.zz' '{x: {b: 10}, y:{z:{zz:"hello"}}}'
# { x: { b: 10 }, y: { z: { zz: 'hello' } } }  =  hello

# Exec code on js obj arg:
# read -r -d '' js1 <<-'EOF'
#    let a1=process.argv[1];
#    let a2=process.argv[2];
#    eval(`a=${a2}`);
#    eval(a1);
#    console.log(a1, "\n", a2, r)
# EOF
#
# a1='r=a.map(i => i+1).filter(i=>i%2==0)'
# node -e "$js1" "$a1" "$a2"
#     r=a.map(i => i+1).filter(i=>i%2==0)
#     [1,2,3,4,5] [ 2, 4, 6 ]

# ** Pipe in args:
# echo "${args[@]}" | xargs node -e

_geo_jq_rm() {
    local inplace_edit=false
    local use_lock_file=true
    local OPTIND
    while getopts "in" opt; do
        case "${opt}" in
            i) inplace_edit=true ;;
            n) use_lock_file=false ;;
            :)
                log::Error "Option '${OPTARG}' expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: $OPTARG"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    local key="$1"
    local file="$2"
    local json="$(cat "$file")"
    json="${json:-'{}'}"

    run_jq() {
        # echo "$json" | jq --arg key_path "$key" --arg val "$value" '. | delpath(($key_path |  split(".")))' > "$file";
        # json="$(echo "$json" | jq --arg key_path "$key" --arg val "$value" '. | setpath(($key_path |  split(".")); $val)')";
        if $inplace_edit; then
            json="$(echo "$json" | jq --arg key_path "$key" '. | delpaths([($key_path |  split("."))])')"
            # json="${json:-'{}'}"
            log::debug "$json"
            [[ -z $json ]] && log::Error "Resulting JSON was empty. Skipping writing to file: '$file'" && return 1
            # echo "$json" > "$file" | { log::Error "Failed to write json to '$file'"; return 1; }
        else
            echo "$json" | jq --arg key_path "$key" '. | delpaths([($key_path |  split("."))])'
            # log::code "j: $json"
        fi
    }
    if $use_lock_file; then
        run_command_with_lock_file "$file.lock" ' ' run_jq
    else
        run_jq
    fi
}

_geo_jq_set_value() {
    local value_is_json=false
    local OPTIND
    while getopts ":j" opt; do
        case "${opt}" in
            j) value_is_json=true ;;
            : ) log::Error "Option '${OPTARG}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: '${OPTARG}'"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    local key="$1"
    local value="$2"
    local json="$3"
    [[ -z $json ]] && json='{}'

    local val_args=(--arg val "$value")
    $value_is_json && val_args[0]='--argjson'

    local updated_json="$(echo "$json" | jq --arg key_path "$key" "${val_args[@]}" '. | setpath(($key_path |  split(".")); $val)')"
    echo "$updated_json"
}

########################################################################################################################
# Sets a key to a value in a json file in. The a write lock is used to prevent concurrent writes.
# Usage: _geo_jq_set [-inpPv] <key> <value> <json-file-path>
# Example _geo_jq_set a.b 1 file.json
#  Assuming file.json was empty/none-existent before running, its contents would now be:
########################################################################################################################
# Options:
#    -i  inplace_edit=true
#    -L  use_lock_file=false
#    -p  print_json=true
#    -P  print_initial_json=true
# Params
#    1:  key
#    2:  value
#    3:  file - The json file path to edit. It will be created if it doesn't exist.
########################################################################################################################
_geo_jq_set() {
    _geo_install_apt_package_if_missing 'jq' || return 1
    local inplace_edit=true
    local print_json=false
    local print_initial_json=false
    local use_lock_file=true
    local OPTIND
    while getopts ":iLpP" opt; do
        case "${opt}" in
            i ) inplace_edit=true ;;
            L ) use_lock_file=false ;;
            p ) print_json=true ;;
            P ) print_initial_json=true ;;
            : ) log::Error "Option '${OPTARG}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${OPTARG}"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    local key="$1"
    local value="$2"
    local file="$3"
    local json=

    # Create file if a name was provided, and it doesn't already exist
    if [[ -n $file && ! -f $file ]]; then
        log::status "Creating json file: $file"
        echo '{}' > "$file"
    fi

    local max_file_size="$(@geo_get MAX_CONFIG_FILE_SIZE)"
    util::is_alphanumeric
    : ${max_file_size:=$MAX_CONFIG_FILE_SIZE}
    local file_size="$(stat -c %s $file)"
    (( file_size > MAX_CONFIG_FILE_SIZE )) \
        && log::Error "File exceeds the maximum size of $MAX_CONFIG_FILE_SIZE. Inspect the file to make sure that it hasn't been currupted: $(log::file $file)"

    [[ -n $file ]] && json="$(cat "$file")"
    [[ ${#json} -lt 2 || $json == '{}' ]] && json='{}'

    $print_initial_json && log::info "Initial json:" && log::code "$json\n"
    #lockfile

    # Function to set json using jq. It will either be called with or without locking the file.
    run_jq() {
        local updated_json="$(_geo_jq_set_value "$key" "$value" "$json")"
        [[ -n $GEO_JSON_DEBUG ]] && log::code "Updated JSON: $updated_json"
        # Something went wrong with jq if not even an empty object was returned for the updated json. Don't write this back to the json file.
        if [[ ${#updated_json} -lt 2 ]]; then
            log::Error "jq failed to set value in json file."
            return 1
        fi

        if $inplace_edit; then
            echo "$updated_json" >"$file" || {
                log::Error "Failed to write json to '$file'"
                return 1
            }
        fi

        if $print_json; then
            log::info "Updated json:"
            log::code "$(cat $file)\n"
        fi
    }

    if $use_lock_file; then
        run_command_with_lock_file "$file.lock" ' ' run_jq
    else
        run_jq
    fi
}

_geo_jq_get() {
    local inplace_edit=false
    local raw=false
    local OPTIND
    while getopts "i" opt; do
        case "${opt}" in
            i) inplace_edit=true ;;
            r) raw=true ;;
            :)
                log::Error "Option '${OPTARG}' expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: $OPTARG"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    local key="$1"
    # local value="$2"
    local file="$2"
    local json="$(cat "$file")"
    local options=
    $raw && options='-n'

    echo "$json" | jq --arg key_path "$key" '. | getpath(($key_path |  split(".")))'
    # run_jq() {
    # }
    # run_command_with_lock_file "$file.lock" ' ' run_jq
}

_geo_jq_props_to_json() {
    (($# == 0)) && log::Error "No json arguments provided" && return 1
    local raw=false
    local add_timestamp=false

    local OPTIND
    while getopts "rt" opt; do
        case "${opt}" in
            r) raw=true ;;
            t) add_timestamp=true ;;
            :)
                log::Error "Option '${OPTARG}' expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: $OPTARG"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    local jq_args=()
    $raw && jq_args+=(-c)
    local i=0
    for arg in "$@"; do
        if ((i++ % 2 == 0)); then
            # [[ $arg == -argjson]] \
            #     && jq_args+=(--argjson "$arg")
            #     && jq_args+=(--argjson "$arg")
            # key
            jq_args+=(--arg "$arg")
        else
            # value
            jq_args+=("$arg")
        fi
    done

    $add_timestamp && jq_args+=(--arg timestamp "$(_geo_timestamp)")

    jq "${jq_args[@]}" \
        '$ARGS.named' <<<'{}'
}

_geo_jq_args_to_json() {
    (($# == 0)) && log::Error "No json arguments provided" && return 1
    local raw=false
    local add_timestamp=false

    local jq_args=()
    $raw && jq_args+=(-c)

    local OPTIND
    while [[ -n $1 && $1 =~ ^-{1,2} ]]; do
        # while getopts "rtk:K:" opt; do
        opt="$(echo $1 | sed -E 's/^-{1,2}//g')"
        case "${opt}" in
            r) raw=true ;;
            t) add_timestamp=true ;;
            a | arg)
                shift
                jq_args+=(--arg "$1" "$2")
                shift
                ;;
            A | argjson)
                shift
                jq_args+=(--argjson "$1" "$2")
                shift
                ;;
            K) add_timestamp=true ;;
            :)
                log::Error "Option '${OPTARG}' expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: $OPTARG"
                return 1
                ;;
        esac
        shift
    done
    # shift $((OPTIND - 1))

    # local i=0
    # for arg in "$@"; do
    #     if (( i++ % 2 == 0 )); then
    #         # [[ $arg == -argjson]] \
    #         #     && jq_args+=(--argjson "$arg")
    #         #     && jq_args+=(--argjson "$arg")
    #         # key
    #         jq_args+=(--arg "$arg")
    #     else
    #         # value
    #         jq_args+=("$arg")
    #     fi
    # done

    $add_timestamp && jq_args+=(--arg timestamp "$(_geo_timestamp)")

    jq "${jq_args[@]}" \
        '$ARGS.named' <<<'{}'
}

_geo_json_array() {
    (($# == 0)) && log::Error "No json arguments provided" && return 1
    local raw=false
    local push=false
    local pop=false
    local back=true

    # local OPTIND
    # while getopts "rt" opt; do
    #     case "${opt}" in
    #         r ) raw=true ;;
    #         p ) add_timestamp=true ;;
    #         : ) log::Error "Option '${OPTARG}' expects an argument."; return 1 ;;
    #         \? ) log::Error "Invalid option: $OPTARG"; return 1 ;;
    #     esac
    # done
    # shift $((OPTIND - 1))

    parse_option() {
        local opt="$1"
        case "${opt}" in
            r | raw) raw=true && echo raw ;;
            t) add_timestamp=true ;;
            a | arg)
                shift
                jq_args+=(--arg "$1" "$2")
                shift
                ;;
            A | argjson)
                shift
                jq_args+=(--argjson "$1" "$2")
                shift
                ;;
            K) add_timestamp=true ;;
            :)
                log::Error "Option '${OPTARG}' expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: $OPTARG"
                return 1
                ;;
        esac
    }

    while [[ -n $1 && $1 =~ ^-{1,2} ]]; do
        local option="$1"
        # while getopts "rtk:K:" opt; do
        # opt="$(echo $1 | sed -E 's/^-{1,2}//g')"
        if [[ $1 =~ ^-[[:alpha:]]{1,} ]]; then
            local option_count=${#option}
            # (( option_count ))
            local single_option=
            for ((i = 1; i < option_count; i++)); do
                single_option="${option:i:1}"
                parse_option "$single_option"
            done
            shift
            continue
        fi
        long_option="$(echo $option | sed -E 's/^-{1,2}//g')"
        parse_option "$long_option"
        shift
    done

    local jq_args=()
    $raw && jq_args+=(-c)
}

_geo_timestamp() {
    # date +"%Y-%m-%dT%H:%M:%S%z"
    # '2023-02-01T16:52:38-05:00'
    date -Iseconds
}

_geo_timestamp_to_seconds() {
    # date +"%Y-%m-%dT%H:%M:%S%z"
    # date -Iseconds
    # '2023-02-01T16:52:38-05:00' =>
    # date -d '2023-02-01T16:51:31-05:00' +%s
    # date -d "$1"
    date -d "$1" +%s
}

#######################################################################################################################
@register_geo_cmd 'update'
@geo_update_doc() {
    doc_cmd 'update'
        doc_cmd_desc 'Update geo to latest version.'
    doc_cmd_options_title
        doc_cmd_option '-f, --force'
            doc_cmd_sub_option_desc 'Force update, even if already at latest version.'
    doc_cmd_sub_cmd_title
        doc_cmd_sub_cmd 'docker-compose'
            doc_cmd_sub_cmd_desc 'Updates docker-compose to the latest stable version.'
    doc_cmd_examples_title
        doc_cmd_example 'geo update'
        doc_cmd_example 'geo update --force'
        doc_cmd_example 'geo update docker-compose'
}
@geo_update() {
    if [[ $1 == docker-compose ]]; then
        _geo_install_or_update_docker_compose
        return
    fi

    local force=false
    [[ $1 == '--force' ]] && force=true && shift

    local OPTIND
    while getopts ":fi" opt; do
        case "${opt}" in
            i) # install only
                (
                    bash "$GEO_CLI_DIR/install.sh"
                    return
                )
                ;;
            f) force=true ;;
                # ;;
                #            n ) use_lock_file=false ;;
            :)
                log::Error "Option '${OPTARG}' expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: $OPTARG"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    # Don't install if already at latest version unless the force flag is present (-f or --force)
    if ! _geo_check_for_updates && ! $force; then
        log::success 'The latest version of geo-cli is already installed'
        # log::Error 'The latest version of geo-cli is already installed'
        return 1
    fi

    local geo_cli_dir="$(@geo_get GEO_CLI_DIR)"
    local prev_commit="$(@geo_get GIT_PREVIOUS_COMMIT)"
    local new_commit=

    (
        cd $geo_cli_dir
        [[ -z $prev_commit ]] && prev_commit=$(git rev-parse HEAD)
        if ! $force && ! git pull >/dev/null; then
            log::Error 'Unable to pull changes from remote'
            return 1
        fi
        new_commit=$(git rev-parse HEAD)

        # Pass in the previous and current commit hashes so that the commit messages between them can be displayed under
        # the "What's new" section during upating. This shows the user what new changes are included in the  update.
        bash $geo_cli_dir/install.sh $prev_commit $new_commit

        @geo_set GIT_PREVIOUS_COMMIT "$new_commit"
    )
    # log::debug "$prev_commit $new_commit"

    # Re-source .bashrc to reload geo in this terminal
    . ~/.bashrc
}

_geo_check_if_feature_branch_merged() {
    [[ ! -f $GEO_CLI_DIR/feature-version.txt ]] && return 1

    local feature_version=$(cat "$GEO_CLI_DIR/feature-version.txt")
    [[ $feature_version != MERGED ]] && return 1

    local msg="The feature branch you are on has been merged and is no longer being maintained.\nSwitch back to the main branch now? (Y|n): "

    if prompt_continue "$msg"; then
        (
            cd "$GEO_CLI_DIR"
            if ! git checkout master; then
                log::Error "Failed to checkout main"
                return 1
            fi
            if ! git pull; then
                log::Error "Failed to pull changes from main"
                return 1
            fi
        )
        return $?
    else
        log::warn "This feature branch is no longer being maintained. You should switch back to the main branch ASAP."
    fi
    return 1
}

#######################################################################################################################

@register_geo_cmd 'uninstall'
@geo_uninstall_doc() {
    doc_cmd 'uninstall'
        doc_cmd_desc "Remove geo-cli installation. This prevents geo-cli from being loaded into new bash terminals, but does
            not remove the geo-cli repo directory. Navigate to the geo-cli repo directory and run 'bash install.sh' to reinstall."

    doc_cmd_examples_title
        doc_cmd_example 'geo uninstall'
}
@geo_uninstall() {
    if ! prompt_continue "Are you sure that you want to remove geo-cli? (Y|n)"; then
        return
    fi
    # TODO: Update with additional uninstall tasks
    @geo_indicator disable
    @geo_set disabled true

    # Remove lines from .bashrc that load geo-cli into terminals.
    sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.bashrc
    sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.profile

    # Re-source .bashrc to remove geo-cli from current terminal (it will still be loaded into other existing ones though).
    . ~/.bashrc

    log::success OK
    log::info 'geo-cli will not be loaded into any new terminals.'
    log::info "Navigate to the geo-cli repo directory and run 'bash install.sh' to reinstall it."
}

#######################################################################################################################

@register_geo_cmd 'analyze'
@geo_analyze_doc() {
    doc_cmd 'analyze [option or analyzerIds]'
    doc_cmd_desc 'Allows you to select and run various pre-build analyzers. You can optionally include the list of analyzers if already known.'

    doc_cmd_options_title
        doc_cmd_option -
            doc_cmd_option_desc 'Run previous analyzers'
        doc_cmd_option -a
            doc_cmd_option_desc 'Run all analyzers'
        doc_cmd_option -s
            doc_cmd_option_desc 'Skip long-running analyzers'
        # doc_cmd_option -b
        #     doc_cmd_option_desc 'Run analyzers in batches (reduces runtime, but is only supported in 2104+)'
        doc_cmd_option -g
            doc_cmd_option_desc 'Run run GW-Linux-Debug pipeline analyzer.'
        doc_cmd_option -d
            doc_cmd_option_desc "Run 'dotnet build All.sln' in the development repo directory"
        doc_cmd_option -i
            doc_cmd_option_desc 'Run analyzers individually (building each time)'

    doc_cmd_examples_title
        doc_cmd_example 'geo analyze'
        doc_cmd_example 'geo analyze -a'
        doc_cmd_example 'geo analyze -as # Run all analyzers, but skip the long-running ones'
        doc_cmd_example 'geo analyze 0 3 6'
}
@geo_analyze() {
    local dev_repo=$(@geo_get DEV_REPO_DIR)
    MYG_CORE_PROJ='Checkmate/MyGeotab.Core.csproj'
    MYG_TEST_PROJ='Checkmate/MyGeotab.Core.Tests/MyGeotab.Core.Tests.csproj'

    # TODO: Add better support for GW-Linux-Debug pipeline test.
    # Run with: dotnet build -c Debug -r ubuntu-x64 GatewayServer.Tests.csproj
    MYG_GATEWAY_TEST_PROJ='Checkmate/GatewayServer/tests/GatewayServer.Tests.csproj'
    if [[ $1 == -g ]]; then
        (
            cd "$dev_repo"
            pwd
            dotnet build -c Debug -r ubuntu-x64 $MYG_GATEWAY_TEST_PROJ
        )
        return
    fi

    # Analyzer info: an array containing "name project" strings for each analyzer.
    analyzers=(
        "CSharp.CodeStyle $MYG_TEST_PROJ"
        "Threading.Analyzers $MYG_TEST_PROJ"
        "SecurityCodeScan $MYG_CORE_PROJ"
        "CodeAnalysis.FxCopAnalyzer $MYG_TEST_PROJ"
        "StyleCop.Analyzers $MYG_CORE_PROJ"
        "Roslynator.Analyzers $MYG_TEST_PROJ"
        "Meziantou.Analyzer $MYG_TEST_PROJ"
        "Microsoft.CodeAnalysis.NetAnalyzers $MYG_TEST_PROJ"
        "SonarAnalyzer.CSharp $MYG_CORE_PROJ"
        "GW-Linux-Debug $MYG_GATEWAY_TEST_PROJ"
        "Build-All.sln $dev_repo"
    )
    local len=${#analyzers[@]}
    local max_id=$((len - 1))
    local name=0
    local proj=1
    # Print header for analyzer table. Which has two columns, ID and Name.
    log::data_header "$(printf '%-4s %-38s %-8s\n' ID Name Project)"
    # Print each analyzer's id and name.
    for ((id = 0; id < len; id++)); do
        # Convert a string containing "name project" into an array [name, project] so that name can be printed with its id.
        read -r -a analyzer <<<"${analyzers[$id]}"
        local project="$(log::info -b Core)"
        [[ ${analyzer[$proj]} == $MYG_TEST_PROJ ]] && project=$(log::info 'Test')
        [[ ${analyzer[$proj]} == $MYG_GATEWAY_TEST_PROJ ]] && project=$(log::info 'GW')
        [[ ${analyzer[$proj]} == $dev_repo ]] && project=$(log::info 'All')

        printf '%-4d %-38s %-8s\n' $id "${analyzer[$name]}" "$project"
    done

    log::hint "$(log::fmt_text "\nHint: When running all analyzers with the -a option, you can also add the -s option to skip long-running analyzers (GW-Linux-Debug and Build-All.sln). Example $(txt_underline geo analyze -as).")"
    local prev_ids=$(@geo_get ANALYZER_IDS)

    log::status "\nValid IDs from 0 to ${max_id}"
    local prompt_txt='Enter the analyzer IDs that you would like to run (separated by spaces): '

    local valid_input=false
    local include_long_running=true
    local ids=

    # Default to running in batches (much faster).
    local run_individually=false

    local OPTIND
    while getopts "abids" opt; do
        case "${opt}" in
            # Check if the run all analyzers option (-a) was supplied.
            a)
                ids=$(seq -s ' ' 0 $max_id)
                echo
                log::status -b 'Running all analyzers'
                ;;
            # Check if the run individually option (-i) was supplied.
            i) run_individually=true ;;
            # Check if the batch run option (-b) was supplied.
            b)
                run_individually=false
                # echo
                # log::status -b 'Running analyzers in batches'
                # echo
                ;;
            # Skip long running analyzers.
            s)
                include_long_running=false
                echo
                log::status -b 'Skip long running analyzers'
                ;;
            g)
                (
                    cd "$dev_repo"
                    pwd
                    dotnet build -c Debug -r ubuntu-x64 $MYG_GATEWAY_TEST_PROJ
                )
                return
                ;;
            d)
                (
                    cd "$dev_repo"
                    pwd
                    dotnet build All.sln
                )
                return
                ;;
            \?)
                log::Error "Invalid option: $OPTARG"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    [[ $run_individually == false ]] && log::status -b "\nRunning analyzers in batches"

    # Check if the run previous analyzers option (-) was supplied.
    if [[ $1 =~ ^-$ ]]; then
        ids=$(@geo_get ANALYZER_IDS)
        [[ -n $ids ]] && echo && log::status "\nUsing previous analyzer id(s): $ids"
        shift
    fi

    # See if only the core/test project should be run.
    local run_project_only=
    [[ $1 == 'core' || $1 == 'test' ]] && run_project_only="$1"

    # Get supplied test ids (if any, e.g., the user ran 'geo analyze 1 4 5').
    while [[ $1 =~ ^[0-9]+$ ]]; do
        ids+="$1 "
        shift
    done

    # Validate id list (if the user passed in ids when running the command).
    if [[ $ids =~ ^( *[0-9]+ *)+$ ]]; then
        # Make sure the numbers are valid ids between 0 and max_id.
        for id in $ids; do
            if ((id < 0 | id > max_id)); then
                log::error "\nInvalid ID: ${id}. Only IDs from 0 to ${max_id} are valid"
                # Set valid_input = false and break out of this for loop, causing the outer until loop to run again.
                valid_input=false
                break
            fi
            prompt_return="$ids"
            valid_input=true
        done
    fi

    # If the user didn't pass in a list of ids, then get the list of ids from the user, interactively. Asking repeatedly if invalid input is given.
    until [[ $valid_input == true ]]; do
        [[ -n $prev_ids ]] && log::status "Enter '-' to reuse previous ids: '$prev_ids'" && echo
        prompt_for_info "$prompt_txt"
        [[ $prompt_return == - ]] && prompt_return="$prev_ids"
        # Make sure the input consists of only numbers separated by spaces.
        while [[ ! $prompt_return =~ ^( *[0-9]+ *)+$ ]]; do
            log::error 'Invalid input. Only space-separated integer IDs are accepted'
            prompt_for_info "$prompt_txt"
        done
        # Make sure the numbers are valid ids between 0 and max_id.
        for id in $prompt_return; do
            if ((id < 0 | id > max_id)); then
                log::error "Invalid ID: ${id}. Only IDs from 0 to ${max_id} are valid"
                # Set valid_input = false and break out of this for loop, causing the outer until loop to run again.
                valid_input=false
                break
            fi
            valid_input=true
        done
        if [[ $valid_input == true ]]; then
            ids="$prompt_return"
        fi
    done

    # The number of ids entered.
    local id_count=$(echo "$ids" | wc -w)
    local run_count=1

    @geo_set ANALYZER_IDS "$ids"

    # Switch to the development repo directory so that dotnet build can be run.
    (
        cd "$dev_repo"
        local fail_count=0
        local failed_tests=''

        # Run analyzers in a function so that the total time for all analyzers to run can be calculated.
        run_analyzers() {
            echo
            log::warn "Press 'ctrl + \' to abort analyzers"
            local stop_requested=false
            quit() {
                exit
            }
            trap quit INT TERM QUIT EXIT

            if [[ $run_individually == false ]]; then
                declare -A target_analyzers
                declare -A target_analyzers_count
                declare -A target_analyzers_result
                declare -A target_analyzer_project_name
                for id in $ids; do
                    # echo $id
                    read -r -a analyzer <<<"${analyzers[$id]}"
                    analyzer_name="${analyzer[$name]}"
                    analyzer_proj="${analyzer[$proj]}"
                    target_analyzers[$analyzer_proj]+="$analyzer_name "
                    ((target_analyzers_count[$analyzer_proj]++))
                    # Checkmate/MyGeotab.Core.csproj => MyGeotab.Core.csproj
                    local project_name=${analyzer_proj##*/}
                    # MyGeotab.Core.csproj => MyGeotab.Core
                    project_name=${project_name/.csproj/}
                    target_analyzer_project_name[$analyzer_proj]=$project_name
                done

                print_analyzers() {
                    for analyzer in $1; do status_i "  * $analyzer"; done
                }

                for analyzer_project in ${!target_analyzers[@]}; do
                    [[ ${target_analyzers_count[$analyzer_project]} -eq 0 ]] && continue
                    # Checkmate/MyGeotab.Core.csproj => MyGeotab.Core
                    local project_name="${target_analyzer_project_name[$analyzer_project]}"
                    local target_analyzer="${target_analyzers[$analyzer_project]}"
                    target_analyzer="${target_analyzer% }"
                    echo
                    log::status -b "Running the following ${target_analyzers_count[$analyzer_project]} analyzer(s) against $(log::txt_underline $project_name):"
                    print_analyzers "$target_analyzer"
                    echo

                    [[ $stop_requested == true ]] && break

                    dotnet_build() {
                        debug "dotnet build -p:DebugAnalyzers=\"$target_analyzer\" -p:TreatWarningsAsErrors=false -p:RunAnalyzersDuringBuild=true $analyzer_project"
                        dotnet build -p:DebugAnalyzers="$target_analyzer" -p:TreatWarningsAsErrors=false -p:RunAnalyzersDuringBuild=true $analyzer_project
                    }

                    local cmd=dotnet_build

                    if [[ $target_analyzer =~ Build-All.sln ]]; then
                        ! $include_long_running && log::status "Skipping $target_analyzer" && continue
                        cmd="dotnet build All.sln"
                    elif [[ $target_analyzer =~ GW-Linux-Debug ]]; then
                        ! $include_long_running && log::status "Skipping $target_analyzer" && continue
                        cmd="dotnet build $MYG_GATEWAY_TEST_PROJ"
                    fi

                    # case "$target_analyzer" in
                    #     Build-All.sln )
                    #         ! $include_long_running && continue
                    #         cmd="dotnet build All.sln"
                    #         ;;
                    #     GW-Linux-Debug )
                    #         ! $include_long_running && continue
                    #         cmd="dotnet build $MYG_GATEWAY_TEST_PROJ"
                    #         ;;
                    # esac
                    # debug "$project_name"
                    # debug "$target_analyzer"

                    [[ $cmd != dotnet_build ]] && debug "$cmd"

                    if ! $cmd; then
                        echo
                        log::Error "Running $project_name analyzer(s) failed"
                        target_analyzers_result[$analyzer_project]=$(log::red FAIL)
                    else
                        log::success "$project_name analyzer(s) done"
                        target_analyzers_result[$analyzer_project]=$(log::green PASS)
                    fi

                done

                echo
                log::info -b 'Results'
                log::data_header "$(printf '%-32s %-8s' Project Status)"
                for analyzer_project in ${!target_analyzers_result[@]}; do
                    name=${target_analyzer_project_name[$analyzer_project]}
                    result=${target_analyzers_result[$analyzer_project]}
                    log::data "$(printf '%-33s %-8s' $name $result)"
                done
                echo
                log::info -b 'The total time was:'
                return
            fi

            # Run each analyzer.
            for id in $ids; do
                # echo $id
                read -r -a analyzer <<<"${analyzers[$id]}"
                analyzer_name="${analyzer[$name]}"
                analyzer_proj="${analyzer[$proj]}"

                if [[ $fail_count -gt 0 ]]; then
                    echo
                    log::warn "$fail_count failed test$([[ $fail_count -gt 1 ]] && echo s) so far"
                fi
                echo
                log::status -b "Running ($((run_count++)) of $id_count): $analyzer_name"
                echo

                dotnet build -p:DebugAnalyzers=${analyzer_name} -p:TreatWarningsAsErrors=false -p:RunAnalyzersDuringBuild=true ${analyzer_proj}

                # Check the return code to see if there were any errors.
                if [[ $? != 0 ]]; then
                    echo
                    log::Error "$analyzer_name failed"
                    ((fail_count++))
                    failed_tests+="  *  $analyzer_name\n"
                else
                    log::success 'Analyzer done'
                fi
            done

            echo

            if [[ $fail_count -gt 0 ]]; then
                log::warn "$fail_count out of $id_count analyzers failed. The following analyzers failed:"
                failed_tests=$(echo -e "$failed_tests")
                log::detail "$failed_tests"
            else
                log::success 'All analyzers completed successfully'
            fi
            echo
            log::info -b 'The total time was:'
        }

        time run_analyzers

        echo
    )
}

#######################################################################################################################
@register_geo_cmd 'id'
@geo_id_doc() {
    doc_cmd 'id'
        doc_cmd_desc "Both encodes and decodes long and guid ids to simplify working with the MyGeotab API. The result is copied to your clipboard. Guid encoded ids must be prefixed with 'a' and long encoded ids must be prefixed with 'b'"
    doc_cmd_options_title
    doc_cmd_option '-o'
    doc_cmd_option_desc 'Do not format output.'
    doc_cmd_examples_title
        doc_cmd_example 'geo id 1234 => b4d2'
        doc_cmd_example 'geo id b4d2 => 1234'
        doc_cmd_example 'geo id 00e74ee1-97e7-4f28-9f5e-2ad222451f6d => aAOdO4ZfnTyifXirSIkUfbQ'
        doc_cmd_example 'geo id aAOdO4ZfnTyifXirSIkUfbQ => 00e74ee1-97e7-4f28-9f5e-2ad222451f6d'
}
@geo_id() {
    local interactive=false
    local use_clipboard=false
    local format_output=true
    [[ $1 == -c ]] && use_clipboard=true && shift
    [[ $1 == -i ]] && interactive=true && shift
    [[ $1 == -o ]] && format_output=false && shift
    local arg="$1"

    local id=
    # The regex for identifying guids (e.g., 00e74ee1-97e7-4f28-9f5e-2ad222451f6d).
    local guid_re='^[[:alnum:]]+-[[:alnum:]]+-[[:alnum:]]+-[[:alnum:]]+-[[:alnum:]]+$'
    # Matches an unencoded guid without dashes: cfc4a516477e39428dcb130b81c2efb3
    local guid_re_no_dashes='^[[:alnum:]]{32,32}$'
    local encoded_guid_re='^a[a-zA-Z0-9_-]{22,22}$'
    local msg=
    number_re='^[0-9]+$'

    # Remove invalid characters (quotes, new lines).
    arg="$(echo "$arg" | tr -d "\n'\"")"

    convert_id() {
        local silent=false
        local write_to_ref_var=false
        [[ $1 == -s ]] && local silent=true && shift
        [[ $1 == -v ]] && local -n _var_ref=$2 && write_to_ref_var=true && shift 2
        arg=${1:-$arg}
        local first_char=${arg:0:1}
        # log::debug "arg='$arg'"
        # Guid encode.
        if [[ $arg =~ $guid_re || $arg =~ $guid_re_no_dashes ]]; then
            if [[ ${#arg} -ne 36 && ${#arg} -ne 32 ]]; then
                log::Error "Invalid input format."
                log::warn "Guid ids must be 36 characters long. The input string length was ${#arg}"
                return 1
            fi
            id=$arg
            # Remove all occurrences of '-'.
            id=${id//-/}
            # Reorder bytes to match the C# Guid.TryWriteBytes() ordering.
            id=${id:6:2}${id:4:2}${id:2:2}${id:0:2}${id:10:2}${id:8:2}${id:14:2}${id:12:2}${id:16:4}${id:20:12}
            # Convert to bytes and then encode to base64.
            id=$(echo $id | xxd -r -p | base64)
            # Remove trailing'=='.
            id=${id:0:-2}
            # Replace '+' with '-'.
            id=${id//+/-}
            # Replace '/' with '_'.
            id=${id//\//_}
            id='a'$id
            msg='Encoded guid id'
        # Guid decode.
        elif [[ $first_char =~ a ]]; then
            #        elif [[ $arg =~ $encoded_guid_re ]]; then
            if [[ ! $arg =~ $encoded_guid_re ]]; then
                # if [[ ${#arg} -ne 23 ]]; then
                log::Error "Invalid input format."
                log::warn "Guid encoded ids must be prefixed with 'a' and be 23 characters long."
                [[ ${#arg} -ne 23 ]] && log::warn "The input string length was: ${#arg}"
                return 1
            fi
            id=${arg:1}
            # Add trailing'=='.
            id+="=="
            # Replace '-' with '+'.
            id=${id//-/+}
            # Replace '_' with '/'.
            id=${id//_/\/}
            # Decode base64 to bytes and then to a hex string.
            id=$(echo $id | base64 -d | xxd -p)
            # Reorder bytes to match the C# Guid.TryWriteBytes() ordering.
            id=${id:6:2}${id:4:2}${id:2:2}${id:0:2}${id:10:2}${id:8:2}${id:14:2}${id:12:2}${id:16:4}${id:20:12}
            # Format the decoded guid with hyphens so that it takes the same form as this example: 9567aac6-b5a9-4561-8b82-ca009760b1b3.
            id=${id:0:8}-${id:8:4}-${id:12:4}-${id:16:4}-${id:20}
            # To upper case.
            id=${id^^}
            msg='Decoded guid id'
        # Long encode.
        elif [[ $arg =~ $number_re ]]; then
            id=$(printf '%x' $arg)
            # To upper case.
            id=b${id^^}
            msg='Encoded long id'
        # Long decode
        elif [[ $first_char == b ]]; then
            # Trim 'b' suffix.
            id=${arg:1}
            # Convert from hex to long.
            id=$(printf '%d' 0x$id)
            msg='Decoded long id'
        else
            echo
            log::Error "Invalid input format. Length: ${#arg}, input: '$arg'"
            log::info "Guid ids must be 36 characters long."
            log::info "Encoded guid ids must be prefixed with 'a' and be 23 characters long."
            log::info "Encoded long ids must be prefixed with 'b'."
            log::info "Use 'geo id help' for usage info."
            return 1
        fi
        $write_to_ref_var && _var_ref= $id && return
        $silent && return
        echo -n $id
    }

    if [[ $interactive == true || $use_clipboard == true ]]; then
        clipboard=$(xclip -o)
        # If the imput is wrapped in quotes (e.g. "123") or other invalid characters, remove them.
        clipboard="${clipboard//[\"\n\']/}"
        # log::debug "Clip $clipboard"
        local valid_id_re='^[a-zA-Z0-9_-]{1,36}$'
        # [[ $clipboard =~ $valid_id_re]]
        # First try to convert the contents of the clipboard as an id.
        if [[ -n $clipboard && ${#clipboard} -le 36 ]] && convert_id $clipboard &>/dev/null; then
            # [[ $clipboard =~ $valid_id_re ]]
            # @geo_id $clipboard
            # log::debug "Clip $clipboard"
            output=$(convert_id $clipboard 2>&1)
            # log::debug $output

            if [[ $output =~ Error ]]; then
                log::detail 'No valid ID in clipboard'
            else
                log::detail "Converting the following id from clipboard: $clipboard"
                @geo_id $clipboard
                echo
            fi
        else
            log::detail 'No valid ID in clipboard'
        fi

        if [[ $use_clipboard == true ]]; then
            log::detail 'closing in 5 seconds'
            sleep 5
            exit
        fi
        # Prompt repetitively to convert ids.
        while true; do
            prompt_for_info_n "Enter ID to encode/decode: "
            @geo_id $prompt_return
            echo
        done
        return
    fi

    if [[ $# -gt 1 ]]; then
        ids=()
        res=
        for _id in "$@"; do
            res=$(convert_id $_id 2>/dev/null)
            if [[ -n $res ]]; then
                ids+=($res)
                $format_output && log::detail -b $res || echo $res
            fi
        done
        echo -n "${ids[@]}" | xclip -selection c
        [[ $format_output == true ]] && log::info "copied to clipboard"
        return
    fi

    # Convert the id.
    if ! convert_id -s $arg /dev/null 2>&1; then
        log::Error "Failed to convert id: $arg"
        return 1
    fi
    [[ $format_output == true ]] && log::status "$msg: "
    [[ $format_output == true ]] && log::detail -b $id || echo -n $id
    if ! type xclip >/dev/null; then
        log::warn 'Install xclip (sudo apt-get instal xclip) in order to have the id copied to your clipboard.'
        return
    fi
    echo -n $id | xclip -selection c
    [[ $format_output == true ]] && log::info "copied to clipboard"
}

#######################################################################################################################
@register_geo_cmd 'version'
@geo_version_doc() {
    doc_cmd 'version, -v, --version'
    doc_cmd_desc 'Gets geo-cli version.'

    doc_cmd_examples_title
    doc_cmd_example 'geo version'
}
@geo_version() {
    log::verbose $(@geo_get VERSION)
}

#######################################################################################################################
@register_geo_cmd 'cd'
@geo_cd_doc() {
    doc_cmd 'cd <dir>'
    doc_cmd_desc 'Change to directory'
    doc_cmd_sub_cmd_title

    doc_cmd_sub_cmd 'dev, myg'
    doc_cmd_sub_cmd_desc 'Change to the Development repo directory.'

    doc_cmd_sub_cmd 'geo, cli'
    doc_cmd_sub_cmd_desc 'Change to the geo-cli install directory.'

    doc_cmd_examples_title
    doc_cmd_example 'geo cd dev'
    doc_cmd_example 'geo cd cli'
}
@geo_cd() {
    case "$1" in
        dev | myg)
            local path=$(@geo_get DEV_REPO_DIR)
            if [[ -z $path ]]; then
                log::Error "Development repo not set."
                return 1
            fi
            cd "$path"
            ;;
        geo | cli)
            local path=$(@geo_get DIR)
            if [[ -z $path ]]; then
                log::Error "geo-cli directory not set."
                return 1
            fi
            cd "$path"
            ;;
        *)
            log::Error "Unknown subcommand '$1'"
            ;;
    esac
}

#######################################################################################################################
@register_geo_cmd 'indicator' --alias 'ui'
@geo_indicator_doc() {
    doc_cmd 'indicator <command>'
    doc_cmd_desc 'Enables or disables the app indicator.'

    doc_cmd_sub_cmd_title
        doc_cmd_sub_cmd 'enable'
            doc_cmd_sub_cmd_desc 'Enable the app indicator.'
        doc_cmd_sub_cmd 'disable'
            doc_cmd_sub_cmd_desc 'Disable the app indicator.'
        doc_cmd_sub_cmd 'start'
            doc_cmd_sub_cmd_desc 'Start the app indicator.'
        doc_cmd_sub_cmd 'stop'
            doc_cmd_sub_cmd_desc 'Stop the app indicator.'
        doc_cmd_sub_cmd 'restart'
            doc_cmd_sub_cmd_desc 'Restart the app indicator.'
        doc_cmd_sub_cmd 'status'
            doc_cmd_sub_cmd_desc 'Gets the systemctl service status for the app indicator.'
        doc_cmd_sub_cmd 'cat'
            doc_cmd_sub_cmd_desc 'Print out the geo-indicator.service file.'
        doc_cmd_sub_cmd 'show'
            doc_cmd_sub_cmd_desc 'Print out all configuration for the service.'
        doc_cmd_sub_cmd 'edit'
            doc_cmd_sub_cmd_desc 'Edit the service file.'
        doc_cmd_sub_cmd 'no-service'
            doc_cmd_sub_cmd_desc 'Runs the indicator directly (using python3).'
        doc_cmd_sub_cmd 'log'
            doc_cmd_sub_cmd_desc '# Show service logs.'
            doc_cmd_sub_option_title
                doc_cmd_sub_option '-b[-#]'
                    doc_cmd_sub_option_desc 'Shows logs since the last boot. Can also use -b-n (n is a number) to get logs from n boots ago.'

    doc_cmd_examples_title
    doc_cmd_example 'geo indicator enable'
    doc_cmd_example 'geo indicator disable'
}
@geo_indicator() {
    local running_in_headless_ubuntu=$(dpkg -l ubuntu-desktop | grep 'no packages found')
    if [[ -n $running_in_headless_ubuntu ]]; then
        log::Error 'Cannot use geo-cli indicator with headless versions of Ubuntu.'
        return 1
    fi

    local geo_indicator_service_name=geo-indicator.service
    local geo_indicator_desktop_file_name=geo.indicator.desktop
    # local indicator_bin_path=~/.geo-cli/bin/geo-indicator
    # local indicator_bin_path=/usr/local/bin/geo-indicator
    local indicator_service_path=~/.config/systemd/user/$geo_indicator_service_name
    local app_desktop_entry_dir="$HOME/.local/share/applications"
    _geo_indicator__check_dependencies
    case "$1" in
        enable)
            log::status -b "Enabling app indicator"
            @geo_set 'APP_INDICATOR_ENABLED' 'true'

            # Directory where user service files are stored.
            mkdir -p ~/.config/systemd/user/
            mkdir -p ~/.geo-cli/.data
            mkdir -p ~/.geo-cli/.indicator
            export src_dir=$(@geo_get GEO_CLI_SRC_DIR)
            # echo $src_dir > ~/.geo-cli/.data/geo-cli-src-dir.txt
            export geo_indicator_app_dir="$src_dir/py/indicator"
            local init_script_path="$geo_indicator_app_dir/geo-indicator.sh"
            local service_file_path="$geo_indicator_app_dir/$geo_indicator_service_name"

            # local desktop_file_path="$geo_indicator_app_dir/$geo_indicator_desktop_file_name"

            if [[ ! -f $init_script_path ]]; then
                log::Error "App indicator script not found at '$init_script_path'"
                return 1
            fi
            if [[ ! -f $service_file_path ]]; then
                log::Error "App indicator service file not found at:\n    $(log::make_path_relative_to_user_dir $service_file_path)"
                return 1
            fi
            if [[ ! -d $app_desktop_entry_dir ]]; then
                mkdir -p $app_desktop_entry_dir
            fi
            # Replace the environment variables in the script file (with the ones loaded in this context)
            # and then copy the contents to a file at the bin path
            # tmp_file=/tmp/geo_ind_init_script.sh

            export geo_indicator_path="$init_script_path"
            # export indicator_py_path="$src_dir/indicator/geo-indicator.py"
            envsubst <$service_file_path >$indicator_service_path
            # envsubst < $desktop_file_path > /tmp/$geo_indicator_desktop_file_name

            # desktop-file-install --dir=$app_desktop_entry_dir /tmp/$geo_indicator_desktop_file_name
            # envsubst < $desktop_file_path > $app_desktop_entry_dir/$geo_indicator_desktop_file_name
            # update-desktop-database $app_desktop_entry_dir
            # sudo chmod 777 $indicator_bin_path

            systemctl --user daemon-reload
            systemctl --user enable --now $geo_indicator_service_name
            systemctl --user restart $geo_indicator_service_name
            ;;
        start)
            systemctl --user start --now $geo_indicator_service_name
            ;;
        stop)
            systemctl --user stop --now $geo_indicator_service_name
            ;;
        disable)
            systemctl --user stop --now $geo_indicator_service_name
            systemctl --user disable --now $geo_indicator_service_name
            @geo_set 'APP_INDICATOR_ENABLED' 'false'
            log::success 'Indicator disabled'
            ;;
        status)
            systemctl --user status $geo_indicator_service_name
            ;;
        restart)
            systemctl --user restart $geo_indicator_service_name
            ;;
        init)
            indicator_enabled=$(@geo_get 'APP_INDICATOR_ENABLED')

            [[ -z $indicator_enabled ]] && indicator_enabled=true && @geo_set 'APP_INDICATOR_ENABLED' 'true'
            [[ $indicator_enabled == false ]] && log::detail "Indicator is disabled. Run $(log::txt_underline geo indicator enable) to enable it.\n" && return
            @geo_indicator enable
            ;;
        # Print out the geo-indicator.service file.
        cat)
            systemctl --user cat $geo_indicator_service_name
            ;;
        # Print out all configuration for the service.
        show)
            systemctl --user show $geo_indicator_service_name
            ;;
        # Edit the service file.
        edit)
            # systemctl --user edit $geo_indicator_service_name
            nano $indicator_service_path
            ;;
        no-service)
            (
                cd "$GEO_CLI_SRC_DIR/py/indicator"
                bash geo-indicator.sh
            )
            ;;
        log | logs)
            # Show all logs since last boot until now.
            local option='-b'
            # Can use -b-2 to get the logs since 2 boots ago or -b-3 to all since 3 boots ago.
            [[ -n $2 ]] && option="$2"
            # -r reverses logs, showing newest first
            journalctl --user -r -u $geo_indicator_service_name $option
            ;;
        *)
            log::Error "Unknown argument: '$1'"
            ;;
    esac
}

_geo_service_exists() {
    local n=$1
    if [[ $(systemctl --user list-units --all -t service --full --no-legend "$n.service" | sed 's/^\s*//g' | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
    fi
}
_geo_install_apt_package_if_missing() {
    local prompt force=false
    local OPTIND
    while getopts ":fp:" opt; do
        case "${opt}" in
            f ) force=true ;;
            p ) prompt="$1" ;;
            : ) log::Error "Option '${OPTARG}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${OPTARG}"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    local pkg_name="$1"
    ! type sudo &>/dev/null && sudo='' || sudo=sudo
    [[ -z $pkg_name ]] && log::warn 'No package name supplied' && return 1
    if ! dpkg -l $pkg_name &>/dev/null; then
        echo in
        local install_msg_key="install-msg-disabled-$pkg_name"
        ! $force && [[ $(@geo_get $install_msg_key) == true ]] \
            && log::caution "Install prompt disabled for missing apt dependency: $(log::txt_underline $pkg_name)" \
            && log::detail "* Re-enable by running: $(log::txt_underline geo set $install_msg_key false)" \
            && log::detail "* Install manually: $(log::txt_underline sudo apt install -y "$pkg_name")" \
            && return 1
        if ! $force && [[ -n $prompt ]]; then
            log::caution "Missing apt dependency: $(log::txt_underline $pkg_name)"
            log::detail "geo-cli requires this package in order to function correctly."
            if ! prompt_continue -a "Install required package"; then
                prompt_continue -a -n "Disable this warning in the future" \
                    && @geo_set $install_msg_key true
                return 1
            fi
            log::status -b "Installing..."
        fi
        $sudo apt install -y "$pkg_name"
    fi
}
_geo_indicator__check_dependencies() {
    ! type sudo &>/dev/null && sudo='' || sudo=sudo
    if ! type python3 &>/dev/null; then
        if ! prompt_continue "python3 is required for geo indicator. Install now (Y|n)?"; then
            return
        fi
        $sudo apt update
        $sudo apt install software-properties-common
        $sudo add-apt-repository ppa:deadsnakes/ppa
        $sudo apt update
        $sudo apt install python3.8
        # $sudo apt install gir1.2-appindicator3-0.1 libappindicator3-1
    fi

    _geo_install_apt_package_if_missing 'gir1.2-appindicator3-0.1'
    _geo_install_apt_package_if_missing 'libappindicator3-1'
    _geo_install_apt_package_if_missing 'gir1.2-notify-0.7'
    _geo_install_apt_package_if_missing 'xclip'
}

#######################################################################################################################
@register_geo_cmd 'test'
@geo_test_doc() {
    doc_cmd 'test <filter>'
        doc_cmd_desc 'Runs tests on the local build of MyGeotab.'

    doc_cmd_options_title
        doc_cmd_option '-d, --docker'
            doc_cmd_option_desc 'Run tests in a docker environment matching the one used in ci/cd pipelines. Requires docker to be logged into gitlab.'
        doc_cmd_option '-n <number of iterations>'
            doc_cmd_option_desc 'Runs the test(s) n times.'
        doc_cmd_option '-r, --random-n <number of iterations>'
            doc_cmd_option_desc 'Runs the test(s) n times using random seeds.'
        doc_cmd_option '--random-seed <seed>'
            doc_cmd_option_desc 'Runs the test(s) a supplied random seed.'

    doc_cmd_examples_title
        doc_cmd_example 'geo test UserTest.AddDriverScopeTest'
        doc_cmd_example 'geo test -r 3 UserTest.AddDriverScopeTest'
        doc_cmd_example 'geo test "FullyQualifiedName=Geotab.Checkmate.ObjectModel.Tests.JSONSerializer.DisplayDiagnosticSerializerTest.DateRangeTest|FullyQualifiedName=Geotab.Checkmate.ObjectModel.Tests.JSONSerializer.DisplayDiagnosticSerializerTest.NotificationUserModifiedValueInfoTest"'
}
@geo_test() {
    local dev_repo=$(@geo_get DEV_REPO_DIR)
    local myg_tests_dir_path="${dev_repo}/Checkmate/MyGeotab.Core.Tests/"
    local script_path="${dev_repo}/gitlab-ci/scripts/StartDockerForTests.sh"
    local use_docker=false
    local interactive=false
    local seeds=(0)
    local is_number_re='^[0-9]+$'
    local find_unreliable='false'
    while [[ $1 =~ ^-+ ]]; do
        case "${1}" in
            -d | --docker)
                if [[ ! -f $script_path ]]; then
                    log::Error "Script to run ci docker environment locally not found in:\n  '${script_path}'."
                    log::warn "\nThis option is currently only supported for MyGeotab version 9.0 or later (current version is $(@geo_dev release)). Running locally instead.\n"
                else
                    use_docker=true
                fi
                ;;
            -i)
                interactive=true
                ;;
            -n)
                [[ ! $2 =~ $is_number_re ]] && log::Error "The $1 option requires a number as an argument." && return 1
                for ((i = 1; i < $2; i++)); do
                    seeds+=(0)
                done
                find_unreliable='true'
                shift
                ;;
            -r | --random-n)
                [[ ! $2 =~ $is_number_re ]] && log::Error "The $1 option requires a number as an argument." && return 1
                for ((i = 1; i < $2; i++)); do
                    seeds+=($((RANDOM * RANDOM)))
                done
                find_unreliable='true'
                shift
                ;;
            --random-seeds)
                [[ ! $2 =~ $is_number_re ]] && log::Error "The $1 option requires a number as an argument." && return 1
                seeds=$2
                find_unreliable='true'
                ;;
            *)
                log::Error "Invalid option: '$1'"
                return 1
                ;;
        esac
        shift
    done

    local test_filter="$1"

    if [[ $interactive == true || -z $test_filter ]]; then
        log::status -b "Example tests filters:"
        log::info "* UserTest.AddDriverScopeTest"
        local long_example="FullyQualifiedName=Geotab.Checkmate.ObjectModel.Tests.JSONSerializer\n .DisplayDiagnosticSerializerTest.DateRangeTest|FullyQualifiedName=Geotab..."
        log::info "* $long_example"
        echo

        local prev_tests="$(_geo_push_get_items TEST_FILTERS)"
        local prev_tests_array=($prev_tests)
        local i=0
        if [[ -n $prev_tests ]]; then
            # select prev_test_filter in $prev_tests; do
            log::status -b "Previous test filters:"
            for filter in $prev_tests; do
                log::info "  ${i}) $filter"
                ((i++))
            done
            echo
            log::info "Reuse one of the above test filters by entering its id."
        fi
        prompt_for_info '\nEnter a test filter: '
        test_filter="$prompt_return"

        # Check if a previous test filter id was entered (a number prefixed with -, e.g., -1).
        if [[ $test_filter =~ ^[0-9] ]]; then
            # Trip the hyphen off the id.
            local i=${test_filter}
            # Get the test filter using the id as the index.
            test_filter=${prev_tests_array[i]}
            [[ -n $test_filter ]] && log::status "\nUsing test filter:\n$test_filter"
        fi
        [[ -z $test_filter ]] && log::Error "Test filter cannot be empty." && return 1

        if prompt_continue -n '\nRun tests in docker container\n(requires GitLab api access token, see Readme for setup instructions)?: (y|N) '; then
            if [[ ! -f $script_path ]]; then
                log::Error "Script to run ci docker environment locally not found in:\n  '${script_path}'."
                log::warn "\nThis option is currently only supported for MyGeotab version 9.0 or later (current version is $(@geo_dev release)). Running locally instead.\n"
            else
                log::status '\nRunning in docker\n'
                use_docker=true
            fi
        else
            log::status '\nRunning locally\n'
        fi
    fi

    _geo_push TEST_FILTERS "$test_filter"

    local geotab_data_dir="$HOME/GEOTAB/Checkmate/"
    log::debug "$geotab_data_dir"
    if [[ $find_unreliable == true ]]; then
        (
            log::debug "seeds: ${seeds[@]}"
            cd "$myg_tests_dir_path"
            seed_count=${#seeds[@]}
            for i in "${!seeds[@]}"; do
                seed=${seeds[i]}
                options="--filter='${test_filter}' --randomseed='$seed' --find-unreliable"
                echo "RandomSeed [$((i + 1))/$seed_count]: ${seed}"
                if [[ $use_docker == true ]]; then
                    local test_container_name="ci_test_container"
                    $script_path $test_container_name
                    docker exec -it $test_container_name /bin/bash -c "pushd MyGeotabRepository/publish; ./CheckmateServer.Tests $options"
                else
                    cmd="dotnet run $options"
                    # cmd="dotnet run --filter='UserTest.AddDriverScopeTest' --randomseed=2 --find-unreliable"
                    log::debug "$cmd"
                    tester_output=$($cmd)
                    if [[ $tester_output == *"Failed     | 0"* && $tester_output == *"Unreliable | 0"* ]]; then
                        echo "$tester_output" | tail -13
                    else
                        echo "$tester_output"
                        mv "$geotab_data_dir/UnitTestRunner" "$geotab_data_dir/UnitTestRunner_${i}_${seed}_$(date +%Y-%m-%dT%H-%M-%S)"
                    fi
                fi
            done
        )
        return
    fi

    if [[ $use_docker == true ]]; then
        local test_container_name="ci_test_container"
        $script_path $test_container_name
        docker exec -it $test_container_name /bin/bash -c "pushd MyGeotabRepository/publish; ./CheckmateServer.Tests --filter='${test_filter}'"
    else
        (
            log::debug "dotnet run --filter='${test_filter}' --displayresults"
            cd "$myg_tests_dir_path"
            if dotnet run --filter="${test_filter}" --displayresults; then
                log::success 'OK'
            else
                log::Error 'dotnet run failed'
            fi
        )
    fi
}

#######################################################################################################################
@register_geo_cmd 'help'
@geo_help_doc() {
    doc_cmd 'help, -h, --help'
    doc_cmd_desc 'Prints out help for all commands.'
}
@geo_help() {
    local cmds=$(echo ${COMMAND_INFO[_commands]}  | tr ' ' $'\n'  | sort)
    for cmd in $(util::array_sort cmds); do
        $(_geo_get_cmd_func_name --doc $cmd)
    done
}

#######################################################################################################################
@register_geo_cmd 'dev'
@geo_dev_doc() {
    doc_cmd 'dev'
    doc_cmd_desc 'Commands used for internal geo-cli development.'

    doc_cmd_sub_cmd_title
        doc_cmd_sub_cmd 'update-available'
            doc_cmd_sub_cmd_desc 'Returns "true" if an update is available'
        doc_cmd_sub_cmd 'co <branch>'
            doc_cmd_sub_cmd_desc 'Checks out a geo-cli branch'
        doc_cmd_sub_cmd 'release'
            doc_cmd_sub_cmd_desc 'Returns the name of the MyGeotab release version of the currently checked out branch'
        doc_cmd_sub_cmd 'databases'
            doc_cmd_sub_cmd_desc 'Returns a list of all the geo-cli database container names'
        doc_cmd_sub_cmd 'open-iap-tunnels'
            doc_cmd_sub_cmd_desc 'Gets a list of open-iap tunnels.'
        doc_cmd_sub_cmd 'api'
            doc_cmd_sub_cmd_desc 'Opens the api runner and logs into geotabdemo.'
        doc_cmd_sub_cmd 'open'
            doc_cmd_sub_cmd_desc 'Opens the geo-cli repo folder in a new VS Code window.'
}
@geo_dev() {
    local geo_cli_dir="$(@geo_get GEO_CLI_DIR)"
    local myg_dir="$(@geo_get DEV_REPO_DIR)"
    local force_update_after_checkout=false
    [[ $1 == -u ]] && force_update_after_checkout=true && shift
    case "$1" in
        # Checks if an update is available.
        update-available)
            GEO_NO_UPDATE_CHECK=false
            if _geo_check_for_updates; then
                log::status true
                return
            fi
            log::status false
            ;;
        # Checks out a geo-cli branch.
        co)
            local branch=
            local checkout_failed=false
            (
                cd $geo_cli_dir
                [[ $2 == - ]] && branch=master || branch="$2"
                git checkout "$branch" || log::Error 'Failed to checkout branch' && checkout_failed=true
            )
            [[ $checkout_failed == true ]] && return 1
            [[ $force_update_after_checkout == true ]] && @geo_update -f
            ;;
        # Gets the current MYG release (e.g. 10.0).
        release)
            (
                cd $myg_dir
                local cur_myg_branch=$(git branch --show-current)
                local prev_myg_branch=$(@geo_get MYG_BRANCH)
                local prev_myg_release_tag=$(@geo_get MYG_RELEASE)
                local cur_myg_release_tag=$prev_myg_release_tag

                if [[ -z $prev_myg_branch || -z $prev_myg_release_tag || $prev_myg_branch != $cur_myg_branch ]]; then
                    # The call to git describe is very CPU intensive, so only call it when the branch changes and then
                    # store the resulting myg release version tag.
                    cur_myg_release_tag=$(git describe --tags --abbrev=0 --match MYG*)

                    # Remove MYG/ prefix (present from 6.0 onwards).
                    [[ $cur_myg_release_tag =~ ^MYG/ ]] && cur_myg_release_tag=${cur_myg_release_tag##*/}
                    # Remove 5.7. prefix (present from 2104 and earlier).
                    [[ $cur_myg_release_tag =~ ^5.7. ]] && cur_myg_release_tag=${cur_myg_release_tag##*.}

                    [[ $prev_myg_release_tag != $cur_myg_release_tag ]] \
                        && @geo_set MYG_RELEASE "$cur_myg_release_tag"
                    [[ $prev_myg_branch != $cur_myg_branch ]] \
                        && @geo_set MYG_BRANCH "$cur_myg_branch"
                fi
                echo -n $cur_myg_release_tag
            )
            ;;
        # Gets a list of all the geo-cli databases.
        db | dbs | databases)
            echo $(docker container ls --filter name="geo_cli_db_" -a --format="{{ .Names }}") | sed -e "s/geo_cli_db_postgres_//g"
            ;;
        auto-switch)
            _geo_auto_switch_server_config "$2" "$3"
            ;;
        open-iap-tunnels)
            local geo_config_dir="$(@geo_get CONFIG_DIR)"
            local geo_tmp_ar_dir="$geo_config_dir/tmp/ar"
            [[ ! -d $geo_tmp_ar_dir ]] && return

            (
                local open_tunnels=''
                cd "$geo_tmp_ar_dir"

                # First remove all files that no longer have locks on them
                remove_unused_lock_files_in_current_directory

                # Files sorted from newest to oldest.
                local files="$(ls -lt | awk '{print $9}')"
                local regex='(.+)__(.+)'
                for file in $files; do
                    # AR request name = port of open IAP tunnel
                    [[ ! $file =~ $regex ]] && continue
                    local ar_name="${BASH_REMATCH[1]}"
                    local iap_port="${BASH_REMATCH[2]}"
                    open_tunnels+="$ar_name=$iap_port|"
                done
                [[ -z $open_tunnels ]] && return
                # Trim off the trailing '|' and echo result
                echo -n "${open_tunnels:0:-1}"
            )
            ;;
        tag)
            (
                cd "$geo_cli_dir"
                [[ $USER != dawsonmyers ]] && log::Error "This feature is for internal purposes only."
                local geo_cli_version=$(cat "$GEO_CLI_DIR/version.txt")
                [[ -z $geo_cli_version ]] && log::Error "Tag is empty" && return 1
                log::debug "git tag -a v$geo_cli_version -m 'geo-cli $geo_cli_version'"
                git tag -a "v$geo_cli_version" -m "geo-cli $geo_cli_version"
                git push origin "v$geo_cli_version"
            )
            ;;
        bump)
            # 1.2.3 => 1 2 3
            local geo_cli_version=$(cat "$GEO_CLI_DIR/version.txt" | tr '.' ' ')
            local major minor patch
            local version_parts=($geo_cli_version) # 1 2 3 => [1, 2, 3]
            local major=${version_parts[0]}
            local minor=${version_parts[1]}
            local patch=${version_parts[2]}
            case $2 in
                major | ma) ((major++, minor = 0, patch = 0)) ;;
                minor | mi) ((minor++, patch = 0)) ;;
                patch | *) ((patch++)) ;;
            esac
            echo "$major.$minor.$patch"
            ;;
        open) code -n -a "$GEO_CLI_DIR" ;;
        *)
            log::Error "Unknown argument: '$1'"
            return 1
            ;;
    esac
}

_geo_url_encode() {
    local url="$(jq -sRrc @uri <<<"$@")"
    # Remove trailing '%0A' (new line). jq always adds a new line for some reason.
    url=${url%\%0A}
    echo -n $url
}

remove_unused_lock_files_in_current_directory() {
    # Run in subshell to ensure that file descriptor and lock are released before exiting this function.
    (
        # Check each file by trying to lock it, if we ackquire a lock, then the IAP tunnel isn't active, so we delete it.
        # The remaining files represent active IAP tunnels. This is how the UI knows what tunnels are active.
        for file in *; do
            exec {fd}>$file
            if flock -w 0 $fd; then
                # log::debug "Removing unused lock file $file"
                # Unlock the file.
                flock -u $fd
                # Close the file descriptor.
                eval "exec $fd>&-"
                # Remove the unused lock file.
                [[ -f $file ]] && rm "$file"
            fi
        done
    )
}

#######################################################################################################################
@register_geo_cmd 'quarantine'
@geo_quarantine_doc() {
    doc_cmd 'quarantine [options] <FullyQualifiedTestName>'
    doc_cmd_desc 'Adds quarantine attributes to a broken test and, optionally, commits the test file.'

    doc_cmd_options_title
        doc_cmd_option '-b'
            doc_cmd_option_desc 'Only print out the git blame for the test.'
        doc_cmd_option '-c'
            doc_cmd_option_desc 'Commit the file after adding the attributes to it.'
        doc_cmd_option '-m <msg>'
            doc_cmd_option_desc 'Add a custom commit message. If absent, the default commit message will be "Quarantined test $testclass.$testname".'
    doc_cmd_examples_title
        doc_cmd_example "geo quarantine -c CheckmateServer.Tests.Web.DriveApp.Login.ForgotPasswordTest.Test"
        doc_cmd_example "geo quarantine -c -m 'Quarentine test' CheckmateServer.Tests.Web.DriveApp.Login.ForgotPasswordTest.Test"
}
@geo_quarantine() {
    local interactive=false
    local blame=false
    local commit=false
    local commit_msg=

    [[ $1 == --interactive ]] && interactive=true && shift

    local OPTIND
    while getopts "bcim:" opt; do
        case "${opt}" in
            b) blame=true ;;
            c) commit=true ;;
            m) commit_msg="$OPTARG" ;;
            i) interactive=true ;;
            :)
                log::Error "Option '${OPTARG}' expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: -${OPTARG}"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))
    # log::debug "commit: $commit"
    # log::debug "commit_msg: $commit_msg"
    # return

    $interactive && log::status -bu "Quarantine Test"

    local full_name="$1"

    # [[ -z $full_name && $interactive == false ]] && log::Error "You must specify the fully qualified name of the test to quarantine." && return 1
    # [[ -z $full_name ]] && $interactive = true

    local dev_repo=$(@geo_get DEV_REPO_DIR)

    (
        cd "$dev_repo"
        local match=
        local test_can_be_quarantined=false
        local test_line=
        # Matches a.b.c and beyond (i.e. a.b.c.d, a.b.c.d.e, etc).
        local valid_test_name_re='\w+(\.\w+){2,}'

        # Keep asking for the fully qualified test name until a valid one is entered.
        while [[ -z $match && $test_can_be_quarantined == false ]]; do
            if [[ -z $full_name ]]; then
                echo
                prompt_for_info "Enter the fully qualified name (namespace.TestClass.TestName) of a test to quarantine:"
                full_name=$prompt_return
                [[ -z $full_name ]] && continue
            fi

            if [[ ! $full_name =~ $valid_test_name_re ]]; then
                echo
                log::Error "The fully qualified name of the test must be of the form:\n namspace.TestClassName.TestName"
                if [[ $interactive == true ]]; then
                    full_name=
                    continue
                fi
                return 1
            fi
            namespace=$(echo $full_name | awk 'BEGIN{FS=OFS="."}{NF--;NF--; print}')
            testclass=$(echo $full_name | awk 'BEGIN{FS=OFS="."}{print $(NF-1)}')
            testname=$(echo $full_name | awk 'BEGIN{FS=OFS="."}{print $NF}')
            file=$(timeout 5 grep -l -m 1 " $testname(" $(timeout 5 grep -l "$testclass" $(timeout 5 grep -r -l --include \*.cs "$namespace" .)))

            if [[ -z $file ]]; then
                log::Error "Couldn't find test file"
                if [[ $interactive == true ]]; then
                    full_name=
                    continue
                fi
                return 1
            fi

            if [[ $(wc -l <<<"$file") -gt 1 ]]; then
                log::Error "Multiple files found matching the provided test name"
                if [[ $interactive == true ]]; then
                    full_name=
                    continue
                fi
                return 1
            fi

            echo
            log::status "Found test in file:"
            # Print the absolute file path. Remove the first character from the path since it's relative (starts with a './', e.g. ./Checkmate/...)
            log::filepath "$(pwd)${file:1}"

            [[ $blame == true ]] && git blame $file -L /$testname\(/ --show-email && return

            # Prefix with line number.
            # local match=grep -n -e " $testname(" $file


            #! TODO: - Confirm that the test def that we found is the right one before adding the attributes to it.
            #!       - Check if there is a Theory or Fact attribute
            #!       - Add an undo feature to remove the tags.
            #!       - Add syntax highlighting to print_test_definition
            #!       - Store gcloud cmd and password in json to allow them to be easily reconnected to later. Add a date as well and mark ones older that 9 hours as expired.
            #!       -
            #!       -
            # Match the test line and the previous 3 lines.
            match=$(grep -B 3 -e " $testname(" $file)
            if [[ -z $match ]]; then
                log::Error "Test not found"
                if [[ $interactive == true ]]; then
                    full_name=
                    continue
                fi
                return 1
            fi

            print_test_definition() {
                echo
                log::warn -b ".\n..\n...\n"
                log::code  "$(grep -n -B 3 -e " $testname(" $file)"
                log::warn -b "...\n..\n."
                echo
            }

# lg() {
# echo
# log::$1 -b ".\n..\n..."
# log::code  '    [Fact]
#     [Trait("TestCategory", "Quarantine")]
#     [Trait("QuarantinedTestTicketLink", "")]
#     public void NearestVehicles_DispatzchVehicleOnPanelTest()'
# log::$1 -b "...\n..\n."
# }

            # Check to see if the test already has quarantine attributes.
            local attribute_text_check='"TestCategory", "Quarantine"|QuarantinedTestTicketLink'
            if grep -E "$attribute_text_check" <<<"$match" >/dev/null; then
                echo
                log::warn 'Test definition:'
                print_test_definition
                log::Error 'Test is already quarantined.'

                if [[ $interactive == true ]]; then
                    echo
                    full_name=
                    match=
                    continue
                fi
                return 1
            fi
            test_can_be_quarantined=true
        done

        # Get the last line, which is the test definition line (i.e. public void Test()).
        test_line=$(echo "$match" | tail -1)

        #     [Fact]
        #     public void Test()
        # Strip evertything from public onwards to get just the indentation.
        local padding="${test_line%public*}"

        local trait_category_attribute='[Trait("TestCategory", "Quarantine")]'
        # Prepend '\' to the line so that leading spaces won't be removed by sed.
        local trait_category_attribute_pad='\'"$padding"$trait_category_attribute
        local trait_ticket_attribute='[Trait("QuarantinedTestTicketLink", "")]'
        local trait_ticket_attribute_pad="$padding"$trait_ticket_attribute

        local attributes="$trait_category_attribute_pad\n$trait_ticket_attribute_pad"

        # Add the attributes to the test.
        if ! sed -i "/ $testname(/i $attributes" "$file"; then
            log::Error "Failed to add attributes to test"
            return 1
        fi

        # echo
        # log::status "Found test in file:"
        # log::filepath "$file"

        log::status -b "\nAttributes added to test"
        print_test_definition

        local msg="Quarantined test $testclass.$testname"
        if [[ $interactive == true ]]; then
            if prompt_continue -n "Would you like to add a commit for this test? (y|N): "; then
                commit=true
                if ! prompt_continue "Use '$(log::txt_underline $msg)' for the commit message? (Y|n): "; then
                    prompt_for_info "Enter commit message: "
                    commit_msg="$prompt_return"
                    [[ -z $commit_msg ]] && commit_msg="$msg"
                fi
            fi
        fi

        if [[ $commit == true ]]; then
            echo
            commit_msg="${commit_msg:-$msg}"
            git add "$file"
            git commit -m "$commit_msg"
        fi

        log::success "Done"
    )
}

#######################################################################################################################
@register_geo_cmd 'mydecoder'
@geo_mydecoder_doc() {
    doc_cmd 'mydecoder [options] <MyDecoderExportedDeviceData.json>'
        doc_cmd_desc 'Converts device data from MyDecoder (exported as JSON) into a MyGeotab text log file. The output file will be in the same directory, with the same name, but with a .txt file extension (i.e. filename.json => filename.txt).'
        doc_cmd_desc 'An HOS unit test can also be created for the data by using the -u option. When using this option, you can pass in the name of a log file (with a .txt extension) instead of a json one.'
        doc_cmd_desc 'NOTE: This feature is only available for MYG 9.0 and above, so you must have a compatible version of MYG checked out for it to work.'

    doc_cmd_options_title
        doc_cmd_option '-u'
            doc_cmd_option_desc 'Create an HOS unit test for the converted data.'
        doc_cmd_option '-d <database>'
            doc_cmd_option_desc 'The database to get data from when creating a unit test.'
        doc_cmd_option '-n <username>'
            doc_cmd_option_desc 'The geotab email to use when logging into the database creating a unit test. If this option is not specified, then $USER@geotab.com will be used.'
    doc_cmd_examples_title
        doc_cmd_example "geo mydecoder MyDecoder_554215428_04_07_2022.json"
        doc_cmd_example "geo mydecoder -u -d g560 MyDecoder_554215428_04_07_2022.json"
        doc_cmd_example "geo mydecoder -u -d g560 MyDecoder_554215428_04_07_2022.txt"
}
@geo_mydecoder() {
    local interactive=false
    local make_unit_test=false
    local database=
    local username="$USER@geotab.com"
    local password=

    local OPTIND
    while getopts "uid:n:p:" opt; do
        # log::debug "OPTIND: $OPTIND"
        # log::debug "OPTARG: $OPTARG"
        case "${opt}" in
            u) make_unit_test=true ;;
            d) database="$OPTARG" ;;
            n) username="$OPTARG" ;;
            p) password="$OPTARG" ;;
            i) interactive=true ;;
            :)
                log::Error "Option '${OPTARG}' expects an argument."
                return 1
                ;;
            \?)
                log::Error "Invalid option: -${OPTARG}"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    local input_file_path="$1"
    local input_file_name=
    local output_file_path=
    local output_file_name=

    [[ -z $input_file_path ]] && log::Error "No input json file specified." && @geo_mydecoder_doc && return 1
    [[ ! -f $input_file_path ]] && log::Error "Input file name does not exist." && return 1
    input_file_path=$(realpath $input_file_path)

    # debug "input: $input_file_path"
    # debug "make_unit_test: $make_unit_test"
    if $make_unit_test && [[ $input_file_path =~ \.txt$ ]]; then
        _geo_mydecoder__generate_unit_test "$input_file_path" "$database" "$username" "$password" && log::success "Done"
        return
    fi

    [[ ! $input_file_path =~ \.json$ ]] && log::Error "Input file must have a .json file extension." && return 1

    input_file_name="${input_file_path##*/}"
    output_file_path="${input_file_path%.json}.txt"
    output_file_name="${output_file_path##*/}"

    # local OPTIND
    # while getopts "bcim:" opt; do
    #     # log::debug "OPTIND: $OPTIND"
    #     # log::debug "OPTARG: $OPTARG"
    #     case "${opt}" in
    #         b ) blame=true ;;
    #         c ) commit=true ;;
    #         m ) commit_msg="$OPTARG" ;;
    #         i ) interactive=true ;;
    #         : )
    #             log::Error "Option '${OPTARG}' expects an argument."
    #             return 1
    #             ;;
    #         \? )
    #             log::Error "Invalid option: -${OPTARG}"
    #             return 1
    #             ;;
    #     esac
    # done
    # shift $((OPTIND - 1))

    cleanup() {
        _geo_mydecoder__converter_check disable
    }
    trap cleanup INT TERM QUIT EXIT

    @geo_set MYDECODER_CONVERTER_WAS_ENABLED false

    local dev_repo=$(@geo_get DEV_REPO_DIR)

    (
        cd "$dev_repo"
        local demo_dir=Checkmate/Geotab.Checkmate.Demonstration
        cd $demo_dir
        local mydecoder_dir=src/demoresources/MyDecoder
        local mydecoder_dir_full=$(realpath $mydecoder_dir)
        [[ ! -d $mydecoder_dir ]] && log::Error "Directory '$demo_dir/$mydecoder_dir' does not exist. This feature is only available in MYG 9.0 and above." && return 1

        _geo_mydecoder__converter_check || return 1

        log::status -b "Copying input file to MyDecoder directory"
        cp "$input_file_path" $mydecoder_dir/
        cd tests

        log::status -b 'Generating log file'
        log::debug "dotnet test --filter ConvertMyDecoderJsonToTextFileTest"
        if ! dotnet test --filter ConvertMyDecoderJsonToTextFileTest; then
            log::Error "Failed to generate log file."
            rm "$mydecoder_dir_full/$input_file_name"
            return 1
        fi

        [[ ! -f $mydecoder_dir_full/$output_file_name ]] && log::Error "Output file '$output_file_name' was not found in MyDecoder directory" && return 1

        log::status -b "Copying output file to destination directory"
        cp "$mydecoder_dir_full/$output_file_name" "$output_file_path"
        log::status -b "Cleaning up MyDecoder directory"
        rm "$mydecoder_dir_full/$output_file_name"
        rm "$mydecoder_dir_full/$input_file_name"
    )
    if [[ $? != 0 ]]; then
        _geo_mydecoder__converter_check disable
        return 1
    fi

    _geo_mydecoder__converter_check disable

    # Make a unit test for log file if the -u option was passed in.
    $make_unit_test && _geo_mydecoder__generate_unit_test "$output_file_path" "$database" "$username" "$password"

    log::info "\nConverted log file path:"
    log::detail "$output_file_path\n"

    log::success "Done"
}

_geo_mydecoder__converter_check() {
    local action=$1
    local mydecoder_converter_was_enabled=$(@geo_get MYDECODER_CONVERTER_WAS_ENABLED)
    local dev_repo=$(@geo_get DEV_REPO_DIR)
    local converter_path="$dev_repo/Checkmate/Geotab.Checkmate.Demonstration/tests/ConvertMyDecoderJsonToTextLogFileMvp.cs"
    # log::debug "wasEnabled: $mydecoder_converter_was_enabled"
    [[ ! -f $converter_path ]] && log::Error "This feature is only available in MYG 9.0 and above. Checkout a compatible branch and rerun this command." && return 1
    if [[ $action == disable ]]; then
        if ! grep -E '// \[Fact\]' "$converter_path" >/dev/null 2>&1 && [[ $mydecoder_converter_was_enabled == true ]]; then
            sed -i -E 's_( {2,})\[Fact\]_\1// \[Fact\]_' "$converter_path"
            mydecoder_converter_was_enabled=false
        fi
    else
        if grep -E '// \[Fact\]' "$converter_path" >/dev/null 2>&1; then
            sed -i -E 's_// \[Fact\]_\[Fact\]_' "$converter_path"
            mydecoder_converter_was_enabled=true
        fi
    fi
    @geo_set MYDECODER_CONVERTER_WAS_ENABLED $mydecoder_converter_was_enabled
}

_geo_mydecoder__generate_unit_test() {
    local output_file_path="$1"
    local database="$2"
    local username="$3"
    local password="$4"

    local bug_hunter_path="$GEO_CLI_DIR/modules/BugHunter/HosProcessorBugHunter"
    [[ ! -d $bug_hunter_path ]] && log::Error "BugHunter not found at path:\n$bug_hunter_path" && return 1

    local cmd="dotnet run --log-path '$output_file_path'"
    [[ -n $database ]] && cmd+=" --database $database"
    [[ -n $username ]] && cmd+=" --username $username"
    [[ -n $password ]] && cmd+=" --password $password"
    log::debug $cmd
    (
        cd "$bug_hunter_path"
        eval $cmd
    )
    [[ $? != 0 ]] && log::Error "Failed to create unit test" && return 1

    local test_file="${output_file_path%.*}.test"
    [[ -f $test_file ]] && cat "$test_file" | xclip -selection c && log::info -b "\nTest copied to clipboard\n"
    log::info "Unit test file path:"
    log::detail "$test_file"
}

_geo_auto_switch_server_config() {
    [[ $(@geo_get auto_server_config)  == false ]] && return
    local cur_myg_release=$1
    local prev_myg_release=$2
    local server_config_path="${HOME}/GEOTAB/Checkmate/server.config"
    local server_config_storage_path="${HOME}/.geo-cli/data/server-config"
    local server_config_backup_path="${HOME}/.geo-cli/data/server-config/backup"
    local prev_server_config_path="$server_config_storage_path/server.config_${prev_myg_release}"
    local prev_server_config_backup_path="$server_config_storage_path/backup/server.config_${prev_myg_release}"
    local next_server_config_name="server.config_${cur_myg_release}"
    local next_server_config_path="$server_config_storage_path/${next_server_config_name}"

    [[ -z $cur_myg_release || -z $prev_myg_release ]] && log::Error "cur_myg_release or prev_myg_release missing" && return 1

    if [[ ! -f $server_config_path ]]; then
        log::Error "server.config not found at path: '$server_config_path'"
        return 1
    fi

    if [[ ! -d $server_config_storage_path ]]; then
        mkdir -p "$server_config_storage_path"
    fi

    if [[ ! -d $server_config_backup_path ]]; then
        mkdir -p "$server_config_backup_path"
    fi

    # Make backup if this is the first time we're switching this version's config.
    if [[ ! -f $prev_server_config_backup_path ]]; then
        cp $server_config_path $prev_server_config_backup_path
    fi

    # Copy server.config to storage.
    cp $server_config_path $prev_server_config_path

    # If there is a server.config in storage that matches the current myg version, switch it in now.
    if [[ -f $next_server_config_path ]]; then
        cp $next_server_config_path $server_config_path
        log::status "server.config replaced with '$next_server_config_path'"
    fi

    _geo_update_server_config_with_db_user_password
}

#######################################################################################################################
@register_geo_cmd 'loc'
@geo_loc_doc() {
    doc_cmd 'loc <file_extension>'
    doc_cmd_desc 'Counts the lines in all files in this directory and subdirectories. file_extension is the file type extension to count lines of code for (e.g., py, cs, sh, etc.).'
    doc_cmd_examples_title
    doc_cmd_example "geo loc cs # Counts the lines in all *.cs files."
}
@geo_loc() {
    local file_type=$1
    find . -name '*'$file_type | xargs wc -l
}

_geo_myg__get_myg_csproj_path() {
    local dev_repo=$(@geo_get DEV_REPO_DIR)
    myg_core_proj="$dev_repo/Checkmate/MyGeotab.Core.csproj"
    echo -n "$myg_core_proj"
}

#######################################################################################################################
@register_geo_cmd 'myg'
@geo_myg_doc() {
    doc_cmd 'myg [subcommand | options]'
        doc_cmd_desc 'Performs various tasks related to building and running MyGeotab.'
    doc_cmd_sub_cmd_title
        doc_cmd_sub_cmd "start"
            doc_cmd_sub_cmd_desc "Starts MyGeotab."
        doc_cmd_sub_cmd 'build'
            doc_cmd_sub_cmd_desc "Builds MyGeotab.Core."
        doc_cmd_sub_cmd 'clean'
            doc_cmd_sub_cmd_desc "Runs $(txt_underline git clean -Xfd) in the Development repo."
        doc_cmd_sub_cmd 'stop'
            doc_cmd_sub_cmd_desc "Stops the running CheckmateServer (MyGeotab) instance."
        doc_cmd_sub_cmd 'restart'
            doc_cmd_sub_cmd_desc "Restarts the running CheckmateServer (MyGeotab) instance."
    doc_cmd_examples_title
        doc_cmd_example "geo myg start"
        doc_cmd_example "geo myg clean"
}
@geo_myg() {
    local cmd="$1"
    shift
    local dev_repo=$(@geo_get DEV_REPO_DIR)
    local myg_dir="$dev_repo/Checkmate"
    local myg_core_proj="$(_geo_myg__get_myg_csproj_path)"
    [[ ! -f $myg_core_proj ]] && Error "Cannot find csproj file at: $myg_core_proj" && return 1

    case "$cmd" in
        build)
            local project_path="$myg_dir"
            local project='MyGeotab.Core.csproj'
            case "$1" in
                sln)
                    project="MyGeotab.Core.sln"
                    ;;
                test | tests)
                    project="MyGeotab.Core.Tests.csproj"
                    project_path+="/MyGeotab.Core.Tests"
                    ;;
            esac
            log::status -b "Building $project"
            local build_command="dotnet build \"$project_path/$project\""
            log::debug "$build_command"
            if ! $build_command; then
                log::Error "Building $project failed"
                return 1
            fi
            ;;
        stop)
            _geo_myg__stop
            ;;
        stop-myg-gw)
            ! _geo_myg__is_running_with_gw && log::Error "MyGeotab is not running with Gateway" && return 1
            _geo_gw__stop
            _geo_myg__stop
            log::success "Done"
            ;;
        restart)
            ! _geo_myg__is_running && log::Error "MyGeotab is not running" && return 1
            local checkmate_pid=$(_get_myg_pid)
            # log::debug "Checkmate server PID: $checkmate_pid"
            kill $checkmate_pid || {
                log::Error "Failed to restart MyGeotab"
                return 1
            }

            log::status -n "Waiting for MyGeotab to stop..."
            local wait_count=0
            while pgrep CheckmateServer >/dev/null; do
                log::status -n '.'
                ((wait_count++ >= 10)) \
                    && log::Error "CheckmateServer failed to stop within 10 seconds" && return 1
                sleep 1
            done
            echo
            echo
            _geo_myg__is_running && log::Error "MyGeotab is still running" && return 1
            _geo_myg__start -r
            log::success "Done"
            ;;
        start)
            _geo_myg__start
            ;;
        is-running)
            local service='MyGeotab'
            if _geo_myg__is_running; then
                [[ $GEO_RAW_OUTPUT == true ]] && echo -n true && return
                log::success "${service} is running"
                return
            fi
            [[ $GEO_RAW_OUTPUT == true ]] \
                && echo false \
                || log::error "${service} is not running"
            return 1
            ;;
        is-running-with-gw)
            if [[ $GEO_RAW_OUTPUT == true ]]; then
                _geo_myg__is_running_with_gw && echo -n true || echo -n false
                return
            fi
            ! _geo_myg__is_running_with_gw && log::error "MyG is not running with GW" && return 1
            log::success "Running MyG: $(_get_myg_pid)"
            log::success "Running GW: $(_get_gw_pid)"
            ;;
        clean)
            (
                local opened_by_ui=false
                [[ $2 == --interactive ]] && opened_by_ui=true
                close_after_clean() {
                    # Count down from 5 to allow the user time to keep the terminal open.
                    for i in $(seq 5 -1 0); do
                        log::status -n "$i.."
                        sleep 1
                    done
                    kill $1
                    exit
                }
                cd "$dev_repo"
                log::status -b "Cleanning the Development repo"
                log::debug "\ngit clean -Xfd -e '!.idea'"
                if git clean -Xfd -e '!.idea'; then
                    echo
                    log::success "Done"
                    if $opened_by_ui; then
                        log::status "\nClosing in 5 seconds..."
                        log::info "\nPress Enter to stay open"
                        # Start in background, if it's not killed (via user input) it will exit.
                        close_after_clean $$ &
                        local pid=$!

                        read
                        # Kill the close_after_clean process to prevent it from exiting.
                        kill $pid

                        log::info "\nPress Enter again to exit"
                        # Wait here until the user presses enter to exit.
                        read
                    fi
                else
                    log::Error "Git failed to clean the Development repo."
                    log::info "\nPress Enter to exit"
                    # Wait here until the user presses enter to exit.
                    read
                fi
            )
            ;;
        api | runner | api-runner)
            _geo_myg__api_runner
            ;;
        gw)
            _geo_run_myg_gw
            ;;
        *)
            log::Error "Unknown argument: '$cmd'"
            return 1
            ;;
    esac
}

_geo_myg__stop() {
    ! _geo_myg__is_running && log::Error "MyGeotab is not running" && return 1
    kill $(_get_myg_pid) || {
        log::Error "Failed to stop MyGeotab"
        return 1
    }
    log::success "MyG stopped"
}

_get_myg_pid() {
    set -o pipefail
    ps -fp $(pgrep CheckmateServer) | grep 'CheckmateServer login' | awk -F ' ' '{print $2}'
}

_geo_run_myg_gw() {
    local myg_gw_running_lock_file="$HOME/.geo-cli/tmp/myg/myg-gw-running.lock"
    mkdir -p "$(dirname $myg_gw_running_lock_file)"
    [[ ! -f $myg_gw_running_lock_file ]] && touch $myg_gw_running_lock_file
    local proc_id=

    # Open a file descriptor on the lock file and store the FD number in myg_gw_lock_fd.
    exec {myg_gw_lock_fd}<>$myg_gw_running_lock_file
    local wait_time=2
    export lock_file_fd=$lock_file

    if ! flock -w $wait_time $myg_gw_lock_fd; then
        log::debug ' Can not get lock on file'
        eval "exec $myg_gw_lock_fd>&-"
        return 1
    fi

    cleanup() {
        # echo "cleanup"
        [[ -n $proc_id ]] && kill $proc_id &>/dev/null
        # Unlock the file.
        flock -u $myg_gw_lock_fd &>/dev/null
        # Close the file descriptor.
        eval "exec $myg_gw_lock_fd>&- &> /dev/null"
    }
    trap cleanup INT TERM QUIT EXIT

    local db_name=""
    local is_valid_db_name=true

    prompt_for_db_name() {
        while [[ -z $db_name ]]; do
            prompt_for_info -v db_name "Enter an alphanumeric name (including .-_) with no capital letters for the new company: "
            # Parse any options supplied by the user.
            local options_regex='-([[:alpha:]]+) .*'
            if [[ $db_name =~ $options_regex ]]; then
                log::debug "db_name: $db_name"
            fi
            db_name=$(_geo__make_alphanumeric "$db_name")
            local has_caps_regex='[[:upper:]]'
            if [[ $db_name =~ $has_caps_regex ]]; then
                is_valid_db_name=false
                log::Error 'Please provide an alphanumeric name with no capital letters for the database.'
                break
            elif [[ $db_name == "geotabdemo" ]]; then
                is_valid_db_name=false
                log::Error 'Please provide any other name than geotabdemo for the database.'
                break
            else
                is_valid_db_name=true
            fi
        done
    }

    # Get the db name from user until it is not geotabdemo
    prompt_for_db_name
    while [ $is_valid_db_name == false ]; do
        db_name=""
        prompt_for_db_name
    done

    # Create a empty database with container
    @geo_db start -d $db_name -py

    # Only insert if db does not exist
    @geo_db psql -d $db_name -q "INSERT INTO public.vehicle (iid, sserialno, ihardwareid, sdescription, iproductid, svin, slicenseplate, slicensestate, scomments, isecstodownload, dtignoredownload, iworktimesheaderid, stimezoneid, sparameters, ienginetypeid, irowversion, senginevin, dtactivefrom, dtactiveto) VALUES (1, 'GV0100000001', 1, 'DeviceSimulator', 81, '', '', '', '', 86400, '1986-01-01 00:00:00', 1, 'America/New_York', '{\\\"major\\\": 14, \\\"minor\\\": 20, \\\"autoHos\\\": \\\"AUTO\\\", \\\"channel\\\": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], \\\"version\\\": \\\"0000000000000004\\\", \\\"activeTo\\\": \\\"2050-01-01T00:00:00.000Z\\\", \\\"rpmValue\\\": 3500, \\\"pinDevice\\\": true, \\\"activeFrom\\\": \\\"2020-12-03T19:38:13.727Z\\\", \\\"speedingOn\\\": 100.0, \\\"gpsOffDelay\\\": 0, \\\"idleMinutes\\\": 3, \\\"speedingOff\\\": 90.0, \\\"channelCount\\\": 1, \\\"licensePlate\\\": \\\"\\\", \\\"licenseState\\\": \\\"\\\", \\\"disableBuzzer\\\": false, \\\"isAuxInverted\\\": [false, false, false, false, false, false, false, false], \\\"ensureHotStart\\\": false, \\\"goTalkLanguage\\\": \\\"English\\\", \\\"immobilizeUnit\\\": false, \\\"odometerFactor\\\": 1.0, \\\"odometerOffset\\\": 0.0, \\\"auxWarningSpeed\\\": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], \\\"enableBeepOnRpm\\\": false, \\\"frequencyOffset\\\": 1, \\\"isAuxIgnTrigger\\\": [false, false, false, false], \\\"customParameters\\\": [], \\\"enableAuxWarning\\\": [false, false, false, false, false, false, false, false], \\\"enableBeepOnIdle\\\": false, \\\"engineHourOffset\\\": 0, \\\"fuelTankCapacity\\\": 0.0, \\\"immobilizeArming\\\": 30, \\\"isSpeedIndicator\\\": false, \\\"minAccidentSpeed\\\": 4.0, \\\"parameterVersion\\\": 1, \\\"isAidedGpsEnabled\\\": false, \\\"isReverseDetectOn\\\": false, \\\"enableSpeedWarning\\\": false, \\\"rfParameterVersion\\\": 0, \\\"disableSleeperBerth\\\": false, \\\"enableMustReprogram\\\": false, \\\"seatbeltWarningSpeed\\\": 10.0, \\\"maxSecondsBetweenLogs\\\": 200.0, \\\"isIoxConnectionEnabled\\\": true, \\\"isRfUploadOnWhenMoving\\\": false, \\\"brakingWarningThreshold\\\": -34, \\\"isActiveTrackingEnabled\\\": false, \\\"parameterVersionOnDevice\\\": 0, \\\"corneringWarningThreshold\\\": 26, \\\"isDriverSeatbeltWarningOn\\\": false, \\\"enableControlExternalRelay\\\": false, \\\"externalDeviceShutDownDelay\\\": 0, \\\"accelerationWarningThreshold\\\": 24, \\\"enableBeepOnDangerousDriving\\\": false, \\\"isPassengerSeatbeltWarningOn\\\": false, \\\"accelerometerThresholdWarningFactor\\\": 0, \\\"isExternalDevicePowerControlSupported\\\": true}', 9999, 5, '?', '2020-12-03T19:38:13.727Z', '2050-01-01T00:00:00.000Z')"
    @geo_db psql -d $db_name -q "INSERT INTO public.nodevehicle (inodeid, ivehicleid, gid) VALUES (9998, 1, '52bc3790-01b4-47ef-9853-255589e30997')"

    # Update server.config & storeforward.config
    local server_config="$HOME/GEOTAB/Checkmate/server.config"
    local store_config="$HOME/GEOTAB/Checkmate/storeforward.config"

    [[ ! -f $server_config ]] && log::Error "Cannot find server.config at $server_config, please run MyG locally to generate it first." && return 1
    xmlstarlet ed --inplace -u "//WebServerSettings/WebPort" -v 10000 -u "//WebServerSettings/WebSSLPort" -v 10001 "$server_config"

    # Delete LiveSettings for this db if any & add new settings
    xmlstarlet ed --inplace -d "//WebServerSettings/ServiceSettings/ServerSettings[DatabaseSettingsInternal[ConnectedSqlServerDatabase='$db_name']]/LiveSettings" "$server_config"
    xmlstarlet ed --inplace -s "//WebServerSettings/ServiceSettings/ServerSettings[DatabaseSettingsInternal[ConnectedSqlServerDatabase='$db_name']]" -t elem -n LiveSettings -v "" "$server_config"
    xmlstarlet ed --inplace -s "//WebServerSettings/ServiceSettings/ServerSettings[DatabaseSettingsInternal[ConnectedSqlServerDatabase='$db_name']]/LiveSettings" -t elem -n ServerAddress -v 127.0.0.1 "$server_config"
    xmlstarlet ed --inplace -s "//WebServerSettings/ServiceSettings/ServerSettings[DatabaseSettingsInternal[ConnectedSqlServerDatabase='$db_name']]/LiveSettings" -t elem -n ServerPort -v 3982 "$server_config"
    xmlstarlet ed --inplace -s "//WebServerSettings/ServiceSettings/ServerSettings[DatabaseSettingsInternal[ConnectedSqlServerDatabase='$db_name']]/LiveSettings" -t elem -n PingTimeout -v 1200 "$server_config"

    [[ ! -f $store_config ]] && log::Error "Cannot find storeforward.config at $store_config, please run Gateway locally to generate it first." && return 1
    xmlstarlet ed --inplace -u "//StoreForwardSettings/Type" -v Developer "$store_config"
    xmlstarlet ed --inplace -u "//StoreForwardSettings/GatewayWebServerSettings/WebPort" -v 10002 -u "//StoreForwardSettings/GatewayWebServerSettings/WebSSLPort" -v 10003 "$store_config"
    xmlstarlet ed --inplace -u "//StoreForwardSettings/CertifiedConnectionsOnly" -v false "$store_config"

    xmlstarlet ed --inplace -d "//StoreForwardSettings/ClientListenerEndPoints/IPEndPoint" "$store_config"
    xmlstarlet ed --inplace -s "//StoreForwardSettings/ClientListenerEndPoints" -t elem -n IPEndPoint -v "" "$store_config"
    xmlstarlet ed --inplace -s "//StoreForwardSettings/ClientListenerEndPoints/IPEndPoint" -t elem -n Address -v 0.0.0.0 "$store_config"
    xmlstarlet ed --inplace -s "//StoreForwardSettings/ClientListenerEndPoints/IPEndPoint" -t elem -n Port -v 3982 "$store_config"

    # Build MYG
    geo_myg build

    # Copy certs if not present
    local dev_repo=$(@geo_get DEV_REPO_DIR)
    if [[ ! -f /usr/local/share/ca-certificates/myggatewayroot.crt ]]; then
        echo "copying cert"
        sudo cp $dev_repo/gitlab-ci/dockerfiles/MygTestContainer/geotabcommoncertroot.crt /usr/local/share/ca-certificates/myggatewayroot.crt
        sudo update-ca-certificates
    fi

    # Start GW
#    x-terminal-emulator --title="Gateway [ geo-cli ]" -e "bash -c '$GEO_CLI_SRC_DIR/geo-cli.sh gw start; sleep 3'"
    gnome-terminal --title="Gateway [ geo-cli ]" -e "bash -c '$GEO_CLI_SRC_DIR/geo-cli.sh gw start; sleep 3'"

    # Start MYG
    geo_myg start

    # Unlock the file.
    flock -u $myg_gw_lock_fd
    # Close the file descriptor.
    eval "exec $myg_gw_lock_fd>&-"
}

_geo_myg__api_runner() {
    local use_local_api=$(@geo_get USE_LOCAL_API)
    local username=$(@geo_get DB_USER)
    local password=$(@geo_get DB_PASSWORD)
    local database=geotabdemo

    local container_name=$(_geo_db__get_running_container_name)

    [[ -z $container_name ]] && log::Error 'No container running' && return 1

    # Check if there is a specific user username/password that was saved when the db was created.
    local db_username=$(@geo_get "${container_name}_username")
    local db_password=$(@geo_get "${container_name}_password")
    local db_name=$(@geo_get "${container_name}_database")

    # Use the versioned credentials if they exist.
    username=${db_username:-$username}
    password=${db_password:-$password}
    database=${db_name:-$database}

    # Use default credentials if none exist.
    [[ -z $username ]] && username="$USER@geotab.com"
    [[ -z $password ]] && password=passwordpassword

    # local webPort=$(xmlstarlet sel -t -v //WebServerSettings/WebPort "$HOME/GEOTAB/Checkmate/server.config")
    local sslPort=$(xmlstarlet sel -t -v //WebServerSettings/WebSSLPort "$HOME/GEOTAB/Checkmate/server.config")
    local server="localhost:$sslPort"

    local url="https://geotab.github.io/sdk/software/api/runner.html"
    [[ $use_local_api == true ]] && url="http://localhost:3000/software/api/runner.html"

    # url encode the parameters.
    server=$(_geo_url_encode "$server")
    database=$(_geo_url_encode "$database")
    username=$(_geo_url_encode "$username")
    password=$(_geo_url_encode "$password")
    local params="server=$server&database=$database&username=$username&password=$password"
    params=$(base64 <<<$params)
    echo $params
    google-chrome "$url?$params#"
}

_geo_remove_file_if_older_than_last_reboot() {
    local file="$1"
    [[ -f $file ]] && _geo_file_older_than_last_reboot "$file" && rm "$file" &>/dev/null
}

_geo_file_older_than_last_reboot() {
    local file="$1"
    [[ ! -f $file ]] && return 1
    local file_time=$(_geo_time_since_file_creation "$file")
    local reboot_time=$(_geo_time_since_reboot)
    ((file_time > reboot_time))
}
_geo_time_since_file_creation() {
    local seconds_since_modified="$(expr $(date +%s) - $(stat -c %Y $1))"
    [[ -z $seconds_since_modified ]] && seconds_since_modified=0
    echo -n $seconds_since_modified
}
_geo_time_since_reboot() {
    local seconds="$(expr $(date +%s) - $(date -d "$(uptime -s)" +%s))"
    [[ -z $seconds ]] && seconds=0
    echo -n $seconds
}

_geo__set_terminal_title() {
    # local d="$(date '+%d %H:%M:%S')"
    #  local date_str=
    local title=""
    local date_str=
    local geo_title=
    # local geo_arg=
    local OPTIND
    while getopts "dgG:" opt; do
        case "${opt}" in
            d) date_str="$(date '+%d %H:%M:%S')" ;;
            g) geo_title="[ geo-cli ]" ;;
            G) geo_title="[ geo $OPTARG ]" ;;

        esac
    done
    shift $((OPTIND - 1))

    local title=
    [[ -n $geo_title ]] && title="$geo_title"
    [[ $# -gt 0 ]] && title+=" | $*"
    [[ -n $date_str ]] && title="$title | $date_str"
    echo -ne "\033]0;${title}${msg}\007"
}

check_is_running() {
    local running_lock_file=$1
    # is_file_locked
    _geo_remove_file_if_older_than_last_reboot "$running_lock_file"
    [[ ! -f $running_lock_file ]] && return 1
    # Open a file descriptor on the lock file.
    exec {lock_fd}<>"$running_lock_file"

    # if flock -w 0 $lock_fd; then
    #      # Unlock the file.
    #     flock -u $lock_fd
    #     return 1
    ! flock -w 0 $lock_fd || {
        eval "exec $lock_fd>&-"
        return 1
    }
    # Unlock the file.
    flock -u $lock_fd
    # Close the file descriptor.
    eval "exec $lock_fd>&-"
    return
}

is_file_locked() {
    local lock_file=$1
    _geo_remove_file_if_older_than_last_reboot "$lock_file"

    # The file isn't locked if it doesn't exist.
    [[ -f $lock_file ]] || return 1

    local lock_fd
    # Open a file descriptor on the lock file.
    exec {lock_fd}<>"$lock_file"

    local file_is_locked=true

    if flock -w 0 $lock_fd; then
        # We got the lock on the file, so it wasn't locked.
        # Unlock the file.
        flock -u $lock_fd
        file_is_locked=false
    fi

    # Close the file descriptor.
    eval "exec $lock_fd>&-"

    $file_is_locked
}

_geo_myg__is_running() {
    is_file_locked "$HOME/.geo-cli/tmp/myg/myg-running.lock" || pgrep Checkmate &> /dev/null
    # check_is_running "$HOME/.geo-cli/tmp/myg/myg-running.lock" || pgrep Checkmate &> /dev/null
}

_geo_myg__is_running_with_gw() {
    is_file_locked "$HOME/.geo-cli/tmp/myg/myg-gw-running.lock"
    # check_is_running "$HOME/.geo-cli/tmp/myg/myg-gw-running.lock"
}

_geo_myg__start() {
    local restarting=false
    [[ $1 == -r ]] && restarting=true
    export myg_core_proj="$(_geo_myg__get_myg_csproj_path)"
    # TODO: Move lock files to a temp dir that is deleted between boots.
    local myg_running_lock_file="$HOME/.geo-cli/tmp/myg/myg-running.lock"
    mkdir -p "$(dirname $myg_running_lock_file)"
    [[ ! -f $myg_running_lock_file ]] && touch "$myg_running_lock_file"
    local proc_id=

    local lock_fd
    # Open a file descriptor on the lock file.
    exec {lock_fd}<>"$myg_running_lock_file"
    local wait_time=2
    export lock_file_fd=$lock_file

    if ! flock -w $wait_time $lock_fd; then
        log::debug ' Can not get lock on file'
        eval "exec $lock_fd>&-"
        return 1
    fi

    cleanup() {
        # echo "cleanup"
        [[ -n $proc_id ]] && kill $proc_id &>/dev/null
        # Unlock the file.
        flock -u $lock_fd &>/dev/null
        # Close the file descriptor.
        eval "exec $lock_fd>&- &> /dev/null"
    }
    trap cleanup INT TERM QUIT EXIT

    log::status -b "Starting MyGeotab"
    dotnet run -v m --project "${myg_core_proj}" -- login

    # Unlock the file.
    flock -u $lock_fd
    # Close the file descriptor.
    eval "exec $lock_fd>&-"
}

#######################################################################################################################
@register_geo_cmd 'gw'
@geo_gw_doc() {
    doc_cmd 'gw [subcommand | options]'
        doc_cmd_desc 'Performs various tasks related to building and running Gateway.'
    doc_cmd_sub_cmd_title
        doc_cmd_sub_cmd "start"
            doc_cmd_sub_cmd_desc "Starts Gateway."
        doc_cmd_sub_cmd 'build'
            doc_cmd_sub_cmd_desc "Builds MyGeotab.Core: Gateway.Debug.Core"
        doc_cmd_sub_cmd 'clean'
            doc_cmd_sub_cmd_desc "Runs $(txt_underline git clean -Xfd) in the Development repo."
        doc_cmd_sub_cmd 'stop'
            doc_cmd_sub_cmd_desc "Stops the running CheckmateServer (Gateway) instance."
        doc_cmd_sub_cmd 'restart'
            doc_cmd_sub_cmd_desc "Restarts the running CheckmateServer (Gateway) instance."
    doc_cmd_examples_title
        doc_cmd_example "geo gw start"
        doc_cmd_example "geo gw clean"
}
@geo_gw() {
    local cmd="$1"
    shift
    local dev_repo=$(@geo_get DEV_REPO_DIR)
    local myg_dir="$dev_repo/Checkmate"
    local myg_core_proj="$(_geo_myg__get_myg_csproj_path)"
    [[ ! -f $myg_core_proj ]] && Error "Cannot find csproj file at: $myg_core_proj" && return 1

    case "$cmd" in
        build)
            local project_path="$myg_dir"
            local project='MyGeotab.Core.csproj'
            case "$1" in
                sln)
                    project="MyGeotab.Core.sln"
                    ;;
                test | tests)
                    project="MyGeotab.Core.Tests.csproj"
                    project_path+="/MyGeotab.Core.Tests"
                    ;;
            esac
            log::status -b "Building $project"
            local build_command="dotnet build \"$project_path/$project\""
            log::debug "$build_command"
            if ! $build_command; then
                log::Error "Building $project failed"
                return 1
            fi
            ;;
        stop)
            _geo_gw__stop
            ;;
        restart)
            ! _geo_gw__is_running && log::Error "Gateway is not running" && return 1
            local checkmate_pid=$(_get_gw_pid)
            # log::debug "Checkmate server PID: $checkmate_pid"
            kill $checkmate_pid || {
                log::Error "Failed to restart Gateway"
                return 1
            }

            log::status -n "Waiting for Gateway to stop..."
            local wait_count=0
            while pgrep CheckmateServer >/dev/null; do
                log::status -n '.'
                ((wait_count++ >= 10)) \
                    && log::Error "CheckmateServer failed to stop within 10 seconds" && return 1
                sleep 1
            done
            echo
            echo
            _geo_gw__is_running && log::Error "Gateway is still running" && return 1
            _geo_gw__start -r
            log::success "Done"
            ;;
        start)
            # Create an empty database with container
            @geo_db start -d $db_name -p
            _geo_gw__start
            ;;
        is-running)
            local service='Gateway'
            if _geo_gw__is_running; then
                [[ $GEO_RAW_OUTPUT == true ]] && echo -n true && return
                log::success "${service} is running"
                return
            fi
            [[ $GEO_RAW_OUTPUT == true ]] \
                && echo -n false \
                || log::error "${service} is not running"
            return 1
            ;;
        clean)
            (
                local opened_by_ui=false
                [[ $2 == --interactive ]] && opened_by_ui=true
                close_after_clean() {
                    # Count down from 5 to allow the user time to keep the terminal open.
                    for i in $(seq 5 -1 0); do
                        log::status -n "$i.."
                        sleep 1
                    done
                    kill $1
                    exit
                }
                cd "$dev_repo"
                log::status -b "Cleanning the Development repo"
                log::debug "\ngit clean -Xfd -e '!.idea'"
                if git clean -Xfd -e '!.idea'; then
                    echo
                    log::success "Done"
                    if $opened_by_ui; then
                        log::status "\nClosing in 5 seconds..."
                        log::info "\nPress Enter to stay open"
                        # Start in background, if it's not killed (via user input) it will exit.
                        close_after_clean $$ &
                        local pid=$!

                        read
                        # Kill the close_after_clean process to prevent it from exiting.
                        kill $pid

                        log::info "\nPress Enter again to exit"
                        # Wait here until the user presses enter to exit.
                        read
                    fi
                else
                    log::Error "Git failed to clean the Development repo."
                    log::info "\nPress Enter to exit"
                    # Wait here until the user presses enter to exit.
                    read
                fi
            )
            ;;
        *)
            log::Error "Unknown argument: '$cmd'"
            return 1
            ;;
    esac
}

_geo_gw__stop() {
    ! _geo_gw__is_running && log::error "Gateway is not running" && return 1
    kill $(_get_gw_pid) || {
        log::Error "Failed to stop Gateway"
        return 1
    }
    log::success "Gateway stopped"
}

_get_gw_pid() {
    set -o pipefail
    ps -fp $(pgrep CheckmateServer) | grep 'CheckmateServer StoreForwardDebug' | awk -F ' ' '{print $2}'
}

_geo_gw__is_running() {
    is_file_locked "$HOME/.geo-cli/tmp/gw/gw-running.lock"
    # check_is_running "$HOME/.geo-cli/tmp/gw/gw-running.lock"
}

_geo_gw__start() {
    local restarting=false
    [[ $1 == -r ]] && restarting=true
    export myg_core_proj="$(_geo_myg__get_myg_csproj_path)"
    local gw_running_lock_file="$HOME/.geo-cli/tmp/gw/gw-running.lock"
    mkdir -p "$(dirname $gw_running_lock_file)"
    [[ ! -f $gw_running_lock_file ]] && touch $gw_running_lock_file
    local proc_id=

    local lock_fd
    # Open a file descriptor on the lock file.
    exec {gw_lock_fd}<>$gw_running_lock_file
    local wait_time=2
    export lock_file_fd=$lock_file

    if ! flock -w $wait_time $gw_lock_fd; then
        log::debug ' Can not get lock on file'
        eval "exec $gw_lock_fd>&-"
        return 1
    fi

    cleanup() {
        # echo "cleanup"
        [[ -n $proc_id ]] && kill $proc_id &>/dev/null
        # Unlock the file.
        flock -u $gw_lock_fd &>/dev/null
        # Close the file descriptor.
        eval "exec $gw_lock_fd>&- &> /dev/null"
    }
    trap cleanup INT TERM QUIT EXIT

    log::status -b "Starting Gateway"
    dotnet run -v m --project "${myg_core_proj}" StoreForwardDebug

    # Unlock the file.
    flock -u $gw_lock_fd
    # Close the file descriptor.
    eval "exec $gw_lock_fd>&-"
}

#######################################################################################################################
@register_geo_cmd 'edit' --alias 'editor'
@geo_edit_doc() {
    doc_cmd 'edit <file>'
        doc_cmd_desc 'Opens up files for editing.'
    doc_cmd_options_title
        doc_cmd_option '-e, --editor <editor_cmd>'
        doc_cmd_option_desc 'Sets the editor to open the files in (e.g. code, nano). VS Code (code) is the default editor.'
    doc_cmd_sub_cmd_title
        doc_cmd_sub_cmd 'server.config'
            doc_cmd_sub_cmd_desc 'Opens "~/GEOTAB/Checkmate/server.config" for editing.'
        doc_cmd_sub_cmd 'bashrc'
            doc_cmd_sub_cmd_desc 'Opens "~/.bashrc" for editing.'
        doc_cmd_sub_cmd 'gitlab-ci'
            doc_cmd_sub_cmd_desc 'Opens "~/GEOTAB/Checkmate/server.config" for editing.'

    doc_cmd_examples_title
        doc_cmd_example "geo edit server.config"
        doc_cmd_example "geo edit --editor nano server.config"
}
@geo_edit() {
    local editor="$(@geo_get EDITOR)"
    editor="${editor:-$EDITOR}"
    [[ $1 == -e || $1 == --editor ]] && editor=$2 && shift 2
    local file="$1"
    local file_path=
    local dev_repo="$(@geo_get DEV_REPO_DIR)"
    if [[ -z $editor ]]; then
        log::hint "You can set the default editor using: $(log::code -u 'geo set EDITOR "<editor_command>"')"
        editor=xdg-open
        # if _geo_terminal_cmd_exists code; then
        #     editor=code
        # elif _geo_terminal_cmd_exists nano; then
        #     editor=nano
        # fi
    fi
    shopt -s extglob
    case "$file" in
        server.config | server | sconf | scf) file_path="${HOME}/GEOTAB/Checkmate/server.config" ;;
        *bashrc | brc | rc) file_path="${HOME}/.bashrc" ;;
        ci | cicd | *gitlab-ci* | git-ci) file_path="${dev_repo}/.gitlab-ci.yml" ;;
        cfg | geo.conf* | conf | config) file_path="${HOME}/.geo-cli/.geo.conf" ;;
         cj | conf*json | geo*json | json) file_path="${HOME}/.geo-cli/.geo.conf.json" ;;
        *)
            log::Error "Arugument '$file' is invalid."
            return 1
            ;;
    esac
    [[ ! -f $file_path ]] && log::Error "File not found at: $file_path" && return 1

    log::debug "$editor '$file_path'"
    $editor "$file_path"
}

# TODO: Add 'geo repo' cmd for chosing what myg repo you what geo to use. Also show the recent paths to choose from

#######################################################################################################################
# COMMANDS+=('command')
# @geo_command_doc() {
#
# }
# @geo_command() {
#
# }

#######################################################################################################################
# COMMANDS+=('python-plugin')
# @geo_python_plugin_doc() {

# }
# @geo_python_plugin() {
#     python $path_to_py_file
# }

# Util
###########################################################################################################################################

_geo_check_if_git_branch_exists() {
    git rev-parse --verify "$1" &>/dev/null
}

_geo_is_valid_git_new_branch_name() {
    [[ -z $1 ]] && return 1
    ! _geo_check_if_git_branch_exists "$1"
}

# Parses long options that don't take arguments
# example() {
#     _geo_parse_long_options long_opts remaining_args "$@"
#     # Set function args to the remaining args (with the long args removed); overwriting all positional arguments for
#     # this function (i.e. $1, $2, etc.).
#     set -- $remaining_args
#     for arg in $long_opts; do
#         case "$arg" in
#             --help) echo "help option" ;;
#             --example) echo "example option" ;;
#         esac
#     done
#     # Parse short options.
#     local OPTIND
#     while getopts "ud:" opts; do
#         case "${opt}" in
#             u ) make_unit_test=true ;;
#             d ) database="$OPTARG" ;;
#             : )
#                 log::Error "Option '${OPTARG}' expects an argument."
#                 return 1
#                 ;;
#             \? )
#                 log::Error "Invalid option: -${OPTARG}"
#                 return 1
#                 ;;
#         esac
#     done
#     shift $((OPTIND - 1))
# }
_geo_parse_long_options() {
    local -n long=$1
    local -n remaining=$2
    shift 2
    long=''
    remaining=''
    for arg; do
        if [[ $arg =~ ^-{2,2} ]]; then
            long+=" $arg"
        else
            remaining+=" $arg"
        fi
    done
}

# Checks if a geo-cli command exists.
# 1: the command to check
_geo__is_registered_cmd() {
    local cmd_name=$1
    [[ -n $cmd_name && -n ${COMMAND_INFO[$cmd_name]} ]]
}

# Checks if a command exists (i.e. docker, code).
# 1: the command to check
_geo_terminal_cmd_exists() {
    type "$1" &>/dev/null
}

# Install Docker and Docker Compose if needed.
_geo_check_docker_installation() {
    if ! type docker >/dev/null; then
        log::warn 'Docker is not installed'
        prompt_for_info_n -v answer 'Install Docker and Docker Compose? (Y|n): '
        if [[ ! $answer =~ [n|N] ]]; then
            log::info 'Installing Docker and Docker Compose'
            # sudo apt-get remove docker docker-engine docker.io
            sudo apt update
            sudo apt upgrade
            sudo apt-get install \
                apt-transport-https \
                ca-certificates \
                curl \
                software-properties-common
            sudo apt-get install -y build-essential make gcc g++ python
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

            sudo apt-key fingerprint 0EBFCD88
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

            sudo apt-get update
            sudo apt-get install -y docker-ce

            # Add user to the docker group to allow docker to be run without sudo.
            sudo usermod -aG docker $USER
            sudo usermod -a -G docker $USER

            _geo_install_or_update_docker_compose

            log::warn 'You must completely log out of your account and log back in again to begin using docker.'
            log::success 'OK'
        fi
    fi
}

_geo_install_or_update_docker_compose() {
    # Get the latest docker-compose version
    latest_compose_version=$(git ls-remote https://github.com/docker/compose | grep refs/tags | grep -oE "[0-9]+\.[0-9][0-9]+\.[0-9]+$" | sort --version-sort | tail -n 1)

    # If docker-compose is installed, get its version.
    local current_compose_version=$(which docker-compose >/dev/null && docker-compose --version)
    # The version will be like Docker Compose version v2.12.0, so remove 'Docker Compose version v' to get just the version.
    current_compose_version="${current_compose_version#Docker Compose version v}"
    # log::debug "$current_compose_version == $latest_compose_version"
    # Don't install if the latest docker-compose is already up-to-date.
    [[ $current_compose_version == $latest_compose_version ]] && log::success "Latest docker-compose version ($current_compose_version) is already installed." && return

    # Remove old version of docker-compose
    if [ -f /usr/bin/docker-compose || -f /usr/local/bin/docker-compose ]; then
        log::status "Removing previous version of docker-compose"
        [ -f /usr/bin/docker-compose ] && sudo rm /usr/bin/docker-compose
        [ -f /usr/local/bin/docker-compose ] && sudo rm /usr/local/bin/docker-compose
    fi

    log::status "Installing docker-compose $latest_compose_version"
    # Download docker-compose to /usr/local/bin/docker-compose
    sudo curl -L "https://github.com/docker/compose/releases/download/v${latest_compose_version:-2.15.1}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

    sudo chmod +x /usr/local/bin/docker-compose
    docker-compose --version
    log::success 'OK'
}

_geo_print_messages_between_commits_after_update() {
    [[ -z $1 || -z $2 ]] && return 1
    local prev_commit=$1
    local cur_commit=$2

    local geo_cli_dir="$(@geo_get GEO_CLI_DIR)"

    (
        cd $geo_cli_dir
        local commit_msgs=$(git log --oneline --ancestry-path $prev_commit..$cur_commit)
        # log::debug "$commit_msgs"
        # Each line will look like this: a62b81f Fix geo id parsing order.
        [[ -z $commit_msgs ]] && return 1

        local line_count=0
        local max_lines=20

        log::info -b "What's new:"

        while read msg; do
            ((line_count++))
            ((line_count > max_lines)) && continue
            # Trim off commit hash (trim off everything up to the first space).
            msg=${msg#* }
            # Format the text (wrap long lines and indent by 4).
            msg=$(log::fmt_text_and_indent_after_first_line "* $msg" 3 2)
            log::detail "$msg"
        done <<<$commit_msgs

        if ((line_count > max_lines)); then
            local msgs_not_shown=$((line_count - max_lines))
            msg="   => Plus $msgs_not_shown more changes"
            log::detail "$msg"
        fi
    )
    [[ $? -eq 0 ]]
}

# Docker Compose using the geo config file
# dc_geo() {
#     local dir=$GEO_REPO_DIR/env/full
#     docker-compose -f $dir/docker-compose.yml -f $dir/docker-compose-geo.yml $@
#     # docker-compose -f $GEO_REPO_DIR/env/full/docker-compose-geo.yml $1
# }

# Check for updates. Return true (0 return value) if updates are available.
_geo_check_for_updates() {
    [[ $GEO_NO_UPDATE_CHECK == true ]] && return 1
    local geo_cli_dir="$(@geo_get GEO_CLI_DIR)"
    local cur_branch=$(cd $geo_cli_dir && git rev-parse --abbrev-ref HEAD)
    local v_remote=

    if [[ $cur_branch != master && -f $geo_cli_dir/feature-version.txt ]]; then
        @geo_set FEATURE true
        # log::debug "cur_branch = $cur_branch"
        v_remote=$(git archive --remote=git@git.geotab.com:dawsonmyers/geo-cli.git $cur_branch feature-version.txt | tar -xO)
        # log::debug "v_remote = $v_remote"
        if [[ -n $v_remote ]]; then
            local feature_version=$(cat $geo_cli_dir/feature-version.txt)
            @geo_set FEATURE_VER_LOCAL "${cur_branch}_V$feature_version"
            @geo_set FEATURE_VER_REMOTE "${cur_branch}_V$v_remote"
            # log::debug "current feature version = $feature_version, remote = $v_remote"
            if [[ $feature_version == MERGED || $v_remote == MERGED || $v_remote -gt $feature_version ]]; then
                # log::debug setting outdated true
                @geo_set OUTDATED true
                return
            fi
        fi
        @geo_set OUTDATED false
        return 1
    fi
    @geo_rm FEATURE
    @geo_rm FEATURE_VER_LOCAL
    @geo_rm FEATURE_VER_REMOTE

    # Gets contents of version.txt from remote.
    v_remote=$(git archive --remote=git@git.geotab.com:dawsonmyers/geo-cli.git HEAD version.txt | tar -xO)

    if [[ -z $v_remote ]]; then
        log::Error 'Unable to pull geo-cli remote version'
        v_remote='0.0.0'
    else
        @geo_set REMOTE_VERSION "$v_remote"
    fi

    # The sed cmds filter out any colour codes that might be in the text
    local v_current=$(@geo_get VERSION) #  | sed -r "s/[[:cntrl:]]\[[0-9]{1,3}m//g"`
    if [[ -z $v_current ]]; then
        geo_cli_dir="$(@geo_get GEO_CLI_DIR)"
        v_current=$(cat "$geo_cli_dir/version.txt")
        @geo_set VERSION "$v_current"
    fi
    # ver converts semver to int (e.g. 1.2.3 => 001002003) so that it can easliy be compared
    if [ $(ver $v_current) -lt $(ver $v_remote) ]; then
        @geo_set OUTDATED true
        # _geo_show_update_notification
        return
    else
        @geo_set OUTDATED false
        return 1
    fi
}

_geo_is_outdated() {
    outdated=$(@geo_get OUTDATED)
    [[ $outdated =~ true ]]
}

# Sends an urgent geo-cli notification. This notification must be clicked by the user to dismiss.
_geo_show_update_notification() {
    # log::debug _geo_show_update_notification
    local notification_shown=$(@geo_get UPDATE_NOTIFICATION_SENT)
    @geo_set UPDATE_NOTIFICATION_SENT true
    [[ $notification_shown == true ]] && return
    local title="Update Available"
    local msg="Run 'geo update' in a terminal to update geo-cli."
    _geo_show_critical_notification "$msg" "$title"

    # TODO uncomment before release
}

_geo_show_critical_notification() {
    local msg="$1"
    local title="$2"
    _geo_show_notification "$msg" 'critical' "$title"
}

_geo_show_notification() {
    ! type notify-send &>/dev/null && return 1
    [[ -z $GEO_CLI_DIR ]] && return
    local show_notifications=$(@geo_get SHOW_NOTIFICATIONS)
    [[ $show_notifications != true ]] && return

    local msg="$1"
    local urgency=${2:-normal}
    local title="${3:-geo-cli}"

    notify-send -i $GEO_CLI_DIR/res/geo-cli-logo.png -u "$urgency" "$title" "$msg"
}

# This was a lot of work to get working right. There were issues with comparing
# strings with number and with literal values. I would read the value 'true'
# or a version number from a file and then try comparing it in an if statement,
# but it wouldn't work because it was a string. Usually 'true' == true will
# work in bash, but when reading from a file if doesn't. This was remedied
# using a regex in the if (i.e., if [[ $outdated =~ true ]]) which was the only
# way it would work.
_geo_show_msg_if_outdated() {
    [[ $GEO_RAW_OUTPUT == true ]] && return
    # outdated=`@geo_get OUTDATED`
    if _geo_is_outdated; then
        # if [[ $outdated =~ true ]]; then
        log::warn -b "New version of geo-cli is available. Run $(log::txt_underline 'geo update') to get it."
    fi
}

# This was the only way I could get semver version comparisons to work with
# versions read from a file. It converts a string '1.2.3' version to
# 001002003 which can then be compared. All other methods broke down when
# reading the semver from a file for some reason.
# https://stackoverflow.com/questions/16989598/bash-comparing-version-numbers/24067243
ver() {
    # Input would be a semvar like 1.1.2. Each part is extracted into its own var.
    # Then make sure that any char values of 27 are replaced with a '1' char (fix_char).
    v1=$(fix_char $(echo "$1" | awk -F. '{ printf("%s", $1) }'))
    v2=$(fix_char $(echo "$1" | awk -F. '{ printf("%s", $2) }'))
    v3=$(fix_char $(echo "$1" | awk -F. '{ printf("%s", $3) }'))

    # The parts are reconstructed in a new string (without the \027 char)
    echo "$v1.$v2.$v3" | awk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }'
    # echo "$@" | gawk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }';
}

# Replace the char value 27 with the char '1'. For some reason the '1' char
# can get a value of 27 when read in from some sources. This should fix it.
# This issue causes errors when comparing semvar string versions.
fix_char() {
    local ord_val=$(ord $1)
    # echo "ord_val = $ord_val"
    if [[ $ord_val == 27 ]]; then
        echo 1
    else
        echo $1
    fi
}

# Semver version $1 less than or equal to semver version $2 (1.1.1 < 1.1.2 => true).
ver_lte() {
    [ "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]
}
ver_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}
# Semver version $1 less than to semver version $2 (1.1.1 < 1.1.2 => true).
ver_lt() {
    [ "$1" = "$2" ] && return 1 || ver_lte $1 $2
}

# Print ascii character for int value
chr() {
    [ "$1" -lt 256 ] || return 1
    printf "\\$(printf '%03o' "$1")"
}

# Print int value for character
ord() {
    LC_CTYPE=C printf '%d' "'$1"
}

# Documentation helpers
#######################################################################################################################
declare -A doc_call_lookup

remove_doc_tags() {
    local _var_ref
    [[ $1 == -v ]] && local -n _var_ref="$2" && shift 2
    local result=${*//[<>\]\[]*/}
    result="${result//[,|]/ }"
    # e result _var_ref
    # util::is_ref_var _var_ref && echo isREF || echo NOT REF
    util::is_ref_var _var_ref && _var_ref="$result" && return
    echo "$result"
    # e result var_ref
}

doc_add_cmd_info() {
    local unique=true append=true
}

doc_set_cmds() {
    CURRENT_COMMAND=${1:-$CURRENT_COMMAND}
    CURRENT_SUBCOMMAND=${2:-$CURRENT_SUBCOMMAND}
}

doc_add_item() {
    set -x
    [[ -v GEO_TEST_DICT ]] && local -n COMMAND_INFO=GEO_TEST_DICT
    local doc_type=$1 && shift
    local doc
    remove_doc_tags -v doc "$*"
    local key=$CURRENT_COMMAND
    [[ -z $key ]] && log::Error "CURRENT_COMMAND was empty"

    case "$doc_type" in
        subcmd)
            [[ ! ${COMMAND_INFO[$key._subcmds]} =~ $doc ]] \
                && COMMAND_INFO[$key._subcmds]+=" $doc"
            ;;
        option)
            [[ ! ${COMMAND_INFO[$key._options]} =~ $doc ]]
            COMMAND_INFO[$key._options]+=" $doc"
            # && COMMAND_INFO[$key.${value}]="$cmd"
            ;;
        *) key+=.$CURRENT_SUBCOMMAND ;;&
        subcmd2)
            [[ ! ${COMMAND_INFO[$key._subcmds]} =~ $doc ]] \
                && COMMAND_INFO[$key._subcmds]+=" $doc"
            ;;

        option2)
            [[ ! ${COMMAND_INFO[$key._options]} =~ $doc ]] \
                && COMMAND_INFO[$key._options]+=" $doc"
                ;;
        # subcmd2) ;;
        # *) key+=.$CURRENT_SUBSUBCOMMAND ;;&
        # cmd3) ;;
        # option3) ;;
        # subcmd3) ;;
    esac

[[ -v GEO_TEST_DICT ]] && e GEO_TEST_DICT
    set +x
}

# The name of a command
doc_cmd() {
    # CURRENT_COMMAND="$1"
    local top_level_geo_cmd="$1"
    doc_handle_command "$top_level_geo_cmd"
    local indent=4
    local txt=$(log::fmt_text --x "$@" $indent)
    # detail_u "$txt"
    log::detail -b "$txt"
#     local key="$CURRENT_COMMAND" \
#         && COMMAND_INFO[$key]="$1" \
#         && COMMAND_INFO[_commands]+=" $1"
}

# Command description
doc_cmd_desc() {
    local indent=6
    local txt=$(log::fmt_text --x "$@" $indent)
    log::data -t "$txt"
    # COMMAND_INFO[$CURRENT_COMMAND]="$1" \
    #     && COMMAND_INFO[$CURRENT_COMMAND.description]+=" $1" \
    #     && COMMAND_INFO[$CURRENT_COMMAND.desc]+=" $1"
}

doc_cmd_desc_note() {
    local indent=8
    local txt=$(log::fmt_text --x "$@" $indent)
    log::data -t "$txt"
}

doc_cmd_examples_title() {
    local indent=8
    local txt=$(log::fmt_text --x "Example:" $indent)
    log::info -t "$txt"
    # info_i "$(log::fmt_text "Example:" $indent)"
}

doc_cmd_example() {
    local indent=12
    local txt=$(log::fmt_text --x "$@" $indent)
    log::data "$txt"
}

doc_cmd_options_title() {
    local indent=8
    local txt=$(log::fmt_text --x "Options:" $indent)
    log::info -t "$txt"
    # log::data -b "$txt"
}
doc_cmd_option() {
    if [[ -n $GEO_GEN_DOCS ]]; then
        doc_add_item option "$*"
        return
    fi
    # doc_handle_subcommand "$1"
    local indent=12
    local txt=$(log::fmt_text --x "$@" $indent)
    log::verbose -bt "$txt"

    # doc_add_item option "$*"
    # remove_doc_tags -v option "$*"
    # [[ -n $CURRENT_COMMAND ]] \
    #     && local key="$CURRENT_COMMAND" \
    #     && COMMAND_INFO[$key._options]+=" $option"
}
doc_cmd_option_desc() {
    local indent=16
    local txt=$(log::fmt_text --x "$@" $indent)
    log::data "$txt"
}

doc_cmd_sub_cmd_title() {
    local indent=8
    local txt=$(log::fmt_text --x "Commands:" $indent)
    log::info -t "$txt"
    # log::data -b "$txt"
}

doc_cmd_sub_cmd() {
    if [[ -n $GEO_GEN_DOCS ]]; then
        doc_handle_subcommand "$1"
        local value="$CURRENT_SUBCOMMAND" #"$(remove_doc_tags "$*")"
        local path=$CURRENT_COMMAND
    # CURRENT_SUBCOMMAND="$1"
        doc_add_item subcmd "$*"
        return
    fi
    # remove_doc_tags cmd "$*"
    # [[ ! ${COMMAND_INFO[${path}._subcmds]} =~ $cmd ]] \
    #     && COMMAND_INFO[${path}._subcmds]+=" $cmd" \
    #     && COMMAND_INFO[${path}.${value}]="$cmd"
    local indent=12
    local txt=$(log::fmt_text --x "$@" $indent)
    log::verbose -b "$txt"
}
doc_cmd_sub_cmd_desc() {
    local indent=16
    local txt=$(log::fmt_text --x "$@" $indent)
    log::data "$txt"
}

doc_cmd_sub_sub_cmds_title() {
    local indent=18
    local txt=$(log::fmt_text --x "Commands:" $indent)
    log::info "$txt"
    # log::data -b "$txt"
}
doc_cmd_sub_sub_cmd() {
    # CURRENT_SUBCOMMAND="$1"
    if [[ -n $GEO_GEN_DOCS ]]; then
        doc_add_item subcmd2 "$*"
        return
    fi
    local indent=20
    local txt=$(log::fmt_text --x "$@" $indent)
    log::verbose "$txt"

    # # remove_doc_tags "$*"
    # [[ -z $CURRENT_COMMAND || -z $CURRENT_SUBCOMMAND ]] && log::Error "Missing doc command path: CURRENT_COMMAND = $CURRENT_COMMAND, CURRENT_SUBCOMMAND = $CURRENT_SUBCOMMAND" return 1
    # local key="$CURRENT_COMMAND.$CURRENT_SUBCOMMAND"
    # for cmd in $(remove_doc_tags "$*"); do
    #     COMMAND_INFO[$key._subcmds]+=" $cmd"
    #     COMMAND_INFO[$key.$cmd]="$cmd"
    #     echo '${COMMAND_INFO['$key.$cmd']} = '"${COMMAND_INFO[$key.$cmd]}"
    # done
}
doc_cmd_sub_sub_cmd_desc() {
    local indent=22
    local txt=$(log::fmt_text --x "$@" $indent)
    log::data "$txt"
}

doc_cmd_sub_option_title() {
    local indent=18
    local txt=$(log::fmt_text --x "Options:" $indent)
    log::info "$txt"
    # log::data -b "$txt"
}
doc_cmd_sub_option() {
    if [[ -n $GEO_GEN_DOCS ]]; then
        doc_add_item option2 "$*"
        return
    fi
    local indent=20
    local txt=$(log::fmt_text --x "$@" $indent)
    log::verbose "$txt"
    # [[ -n $CURRENT_COMMAND ]] \
    #     && local key="$CURRENT_COMMAND.$CURRENT_SUBCOMMAND" \
    #     && COMMAND_INFO[$key._options]+=" $1"
    # [[ -n $CURRENT_COMMAND && -n $CURRENT_SUBCOMMAND ]] && log::Error "Missing doc command path" return 1
    # local key="$CURRENT_COMMAND.$CURRENT_SUBCOMMAND"
    # for cmd in $(remove_doc_tags "$*"); do
    #     COMMAND_INFO[$key._options]+=" $cmd"
    #     # COMMAND_INFO[$key]="$cmd"
    # done
}
doc_cmd_sub_option_desc() {
    local indent=22
    local txt=$(log::fmt_text --x "$@" $indent)
    log::data "$txt"
}

prompt_continue_or_exit() {
    log::prompt_n "Do you want to continue? (Y|n): "
    read -e answer
    [[ ! $answer =~ [nN] ]]
}

################################################################################
# prompt_continue [-nfaw] <message>

# Arguments:
#    -n  Default to NO when the user pressed Enter without typing anything.
#    -f  Force either 'yes' or 'no' to be typed in order to continue.
#    -a  Add '(Y|n): ' to the supplied message.
#    -w  Whole word - uses (yes|no) instead of (y|n).
################################################################################
prompt_continue() {
    # Yes by default, any input other that n/N/no will continue.
    local regex_no='^[nN][oO]{0,}$'
    local regex_yes='^[yY]([eE][sS])?$'
    local regex="$regex_no"
    local default=yes
    local answer=
    local prompt_msg="Do you want to continue?"

    local force_answer=false
    local add_suffix=false
    local whole_word_answer=false

    local OPTIND
    while getopts ":nfaw" opt; do
        case "${opt}" in
            n) default=no ;;
            # Force either yes or no to be entered.
            f) force_answer=true && default= ;;
            a) add_suffix=true ;;
            # Uses (yes|no) instead of (y|n).
            w) whole_word_answer=true && default= ;;
            :) log::Error "Option '${OPTARG}' expects an argument." && return 1 ;;
            \?) log::Error "Invalid option: ${OPTARG}" && return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    [[ $# -gt 0 ]] && prompt_msg="$*" || add_suffix=true

    # Replace multiple spaces with a single space and remove trailing/leading spaces.
    prompt_msg="$(echo "$prompt_msg" | sed -E 's/^ +//g; s/ +$//g; s/ +/ /g;')"

    local prompt_suffix=
    local has_suffix_regex='[\(\[].{1,}|.{1,}[\)\]]:'' ''?$'
    if $add_suffix && ! [[ $prompt_msg =~ $has_suffix_regex ]]; then
        case $default in
            'yes') prompt_suffix='Y|n' ;;
            'no') prompt_suffix='y|N' ;;
            '') $whole_word_answer && prompt_suffix='yes|no' || prompt_suffix='y|n' ;;
        esac

        [[ ! $prompt_msg =~ \?$ ]] && prompt_msg+='?'
        $force_answer && prompt_suffix="($prompt_suffix)" || prompt_suffix="[$prompt_suffix]"
        prompt_msg+=" $prompt_suffix: "
    fi

    $whole_word_answer && regex_yes=yes && regex_no=no

    # Default to no if the -n option is present. This means that the user is required to enter y/Y/yes to continue,
    # anything else will decline to continue.
    prompt_msg="$prompt_msg "
    # Replace 2+ spaces with 1; remove space between ')' and ':' (e.g. 'Continue? (Y|n) :' => 'Continue? (Y|n):'
    prompt_msg="$(echo $prompt_msg | sed -E 's/ +/ /g; s/\) :/\):/g')"
    while true; do
        log::prompt_n "$prompt_msg"' '
        answer=

        read -e answer
        answer=${answer,,}
        # The read command doesn't add a new line with the -e option (allows for editing of the input with arrow keys, etc.)
        # when the user just presses Enter (with no input), read doesn't add a new line after. So add one.
        # if [[ -z $answer ]]; then
        #     [[ -n $default ]] && echo
        [[ -z $answer ]] && echo $default

        [[ $answer =~ $regex_yes || $default == yes && -z $answer ]] && return
        [[ $answer =~ $regex_no || $default == no && -z $answer ]] && return 1
        # [[ $answer =~ $regex || -z $answer && $default == true ]] && continue
    done
}

# =====================================================================================================================
# prompt_for_info [-n] [-v <variable_name>] <prompt_text>
# =====================================================================================================================
# Prompts the user for information, displaying the prompt text, and then the user input section on the next line.
# The -n option will prompt the user for information on the same line as the prompt text.
# The -v option allows for a variable name to be passed in that the user info is to be assigned to. If no variable name
# is passed in, then the info will be stored in the global variable prompt_return.
prompt_for_info() {
    local prompt_on_same_line=false
    [[ $1 == -n ]] && prompt_on_same_line=true && shift

    local user_info=
    # Check if the caller supplied a variable name that they want the result to be stored in. If they did, then define
    # user_info to be a reference (the -n option to local) to the variable name passed in as the second argument ($2).
    [[ $1 == -v ]] && local -n user_info="$2" && shift 2

    if $prompt_on_same_line; then
        log::prompt_n "$1"
    else
        log::prompt "$(log::fmt_text "$1")"
        log::prompt_n '> '
    fi
    # Assign the user input to the variable (or variable reference) user_info.
    # This allows the callers to supply the variable name that they want the result stored in.
    read -e user_info
    # The read command doesn't add a new line with the -e option (allows for editing of the input with arrow keys, etc.)
    # when the user just presses Enter (with no input), read doesn't add a new line after. So add one.
    [[ -z $user_info ]] && echo
    # Store the user input to the global variable prompt_return to give the caller access to the user info (without
    # passing in a variable name to reference).
    prompt_return="$user_info"
}

# =====================================================================================================================
# prompt_for_info_n [-v <variable_name>] <prompt_text>
# =====================================================================================================================
# Prompts the user for information, displaying the prompt text, and then the user input section ON THE SAME LINE (_n
# suffix for no new line).
# The -v option allows for a variable name to be passed in that the user info is to be assigned to. If no variable name
# is passed in, then the info will be stored in the global variable prompt_return.
prompt_for_info_n() {
    prompt_for_info -n "$@"
}

_geo_replace_home_path_with_tilde() {
    echo "$@" | sed -e "s%$HOME%~%g"
}

_geo_print_array() {
    [[ $1 == -r ]] && local -n array=BASH_REMATCH || local -n array="$1"
    for item in "${array[@]}"; do
        echo "$item"
    done
}

# _geo_extract_re() {
#     local -n array=$1
#     for item in "${array[@]}"; do
#         echo "$item"
#     done
# }

typeofvar() {
    local type_signature=$(declare -p "$1" 2>/dev/null)

    if [[ $type_signature =~ "declare --" ]]; then
        printf "string"
    elif [[ $type_signature =~ "declare -a" ]]; then
        printf "array"
    elif [[ $type_signature =~ "declare -A" ]]; then
        printf "map"
    else
        printf "none"
    fi
}

geotab_logo() {
    echo
    log::cyan -b '===================================================='
    echo
    log::cyan -b ' ██████  ███████  ██████  ████████  █████  ██████ '
    log::cyan -b '██       ██      ██    ██    ██    ██   ██ ██   ██'
    log::cyan -b '██   ███ █████   ██    ██    ██    ███████ ██████ '
    log::cyan -b '██    ██ ██      ██    ██    ██    ██   ██ ██   ██'
    log::cyan -b ' ██████  ███████  ██████     ██    ██   ██ ██████ '
    echo
    log::cyan -b '===================================================='
}
geo_logo1() {
    log::green -b '       ___  ____  __         ___  __    __ '
    log::green -b '      / __)(  __)/  \  ___  / __)(  )  (  )'
    log::green -b '     ( (_ \ ) _)(  O )(___)( (__ / (_/\ )( '
    log::green -b '      \___/(____)\__/       \___)\____/(__)'
}

geo_logo() {
    log::green -b '                                     _ _'
    log::green -b '          __ _  ___  ___         ___| (_)'
    log::green -b '         / _` |/ _ \/ _ \ _____ / __| | |'
    log::green -b '        | (_| |  __/ (_) |_____| (__| | |'
    log::green -b '         \__, |\___|\___/       \___|_|_|'
    log::green -b '         |___/ '
    # log::green -b '   ____   ____  ____             ____ |  | |__|'
    # log::green -b '  / ___\_/ __ \/  _ \   ______ _/ ___\|  | |  |'
    # log::green -b ' / /_/  >  ___(  <_> ) /_____/ \  \___|  |_|  |'
    # log::green -b ' \___  / \___  >____/           \___  >____/__|'
    # log::green -b '/_____/      \/                     \/ '
    # log::green -b '   ____   ____  ____             ____ |  | |__|'
    # log::green -b '  / ___\_/ __ \/  _ \   ______ _/ ___\|  | |  |'
    # log::green -b ' / /_/  >  ___(  <_> ) /_____/ \  \___|  |_|  |'
    # log::green -b ' \___  / \___  >____/           \___  >____/__|'
    # log::green -b '/_____/      \/                     \/ '
    # log::green -b ''
    # log::green -b '┌─┐┌─┐┌─┐   ┌─┐┬  ┬'
    # log::green -b '│ ┬├┤ │ │───│  │  │'
    # log::green -b '└─┘└─┘└─┘   └─┘┴─┘┴'
}

# 🇬​​​​​🇪​​​​​🇴​​​​​-🇨​​​​​🇱​​​​​🇮​​​​​
# geo_logo() {
#     echo
#     log::detail '=============================================================================='
#     node $GEO_CLI_DIR/src/cli/logo/logo.js
#     echo
#     log::detail '=============================================================================='
#     # echo
# }

# Store commands and there subcommands/options so that tab completions can be generated at the command line.
doc_handle_command() {
    # log::debug "$1"
    local cur="${1/[, <]*/}"
    [[ -z $CURRENT_COMMAND ]] && CURRENT_COMMAND="$cur" && return
    if [[ $cur != $CURRENT_COMMAND ]]; then
        SUBCOMMANDS[$CURRENT_COMMAND]="${CURRENT_SUBCOMMANDS[@]}"
        CURRENT_SUBCOMMANDS=()
    fi
    CURRENT_COMMAND="$cur"
}

doc_handle_subcommand() {
    local cur="${1/[, <]*/}"
    [[ -z $cur ]] && return
    CURRENT_SUBCOMMANDS+=("$cur")
}

init_completions() {
    # log::debug init_completions
    [[ -z $GEO_CLI_AUTOCOMPLETE_FILE ]] \
        && log::warn "GEO_CLI_AUTOCOMPLETE_FILE environment variable wasn't set. Skipping initializing autocompletions for geo."
    # && return 1
    local cmd=
    local completions=

    # Make sure that completions have been generated before trying to load them .
    [[ -d $GEO_CLI_CONFIG_DIR && ! -f $GEO_CLI_AUTOCOMPLETE_FILE ]] \
        && touch "$GEO_CLI_AUTOCOMPLETE_FILE" && return

    while read line; do
        # Skip empty lines.
        ((${#line} == 0)) && continue
        # log::debug $line
        # This is an example of a line: 'db=create start rm stop ls ps init psql bash script'
        # Get the name of the command by removing everything after and including '='.
        cmd=${line%=*}
        # Get the name of the command completions by removing everything before and including '='.
        completions=${line#*=}
        # Store the completions for the command in the SUBCOMMAND_COMPLETIONS dictionary.
        SUBCOMMAND_COMPLETIONS[$cmd]="$completions"
    done <"$GEO_CLI_AUTOCOMPLETE_FILE"

    # for x in "${!SUBCOMMAND_COMPLETIONS[@]}"; do echo "[$x] = '${SUBCOMMAND_COMPLETIONS[$x]}'"; done
}

geo_generate_autocompletions() {
    ! tty -s && log::warn "Skipping geo-cli completion generation since not in an interactive shell"
    [[ -z $GEO_CLI_AUTOCOMPLETE_FILE ]] \
        && log::warn "GEO_CLI_AUTOCOMPLETE_FILE environment variable wasn't set. Skipping autocompletion file generation for geo."
    # populate the command info by running all of geo's help commands
    @geo_help >/dev/null
    doc_handle_command 'DONE'
    echo -n '' >"$GEO_CLI_AUTOCOMPLETE_FILE"

    for cmd in "${!SUBCOMMANDS[@]}"; do
        echo "$cmd=${SUBCOMMANDS[$cmd]}" >>"$GEO_CLI_AUTOCOMPLETE_FILE"
    done
}

init_completions

# Auto-complete for commands
# completions=(
#     "${COMMANDS[@]}"
# )

# Doesn't work for some reason
# complete -W "${completions[@]}" geo

# Get list of completions separated by spaces (required as imput to complete command)
# comp_string=$(echo "${completions[@]}")
# complete -W "$comp_string" geo

# echo "" > bcompletions.txt
_geo_complete() {
    # Disable ERR trap inheritance.
    # set +E
    # Prevent inherited ERR trap funciton from running.
    trap -- ERR
    # Uncomment line below to enable debug output
    local cur prev
    # echo "COMP_WORDS: ${COMP_WORDS[@]}" >> $HOME/.geo-cli/bcompletions.txt
    # echo "COMP_CWORD: $COMP_CWORD" >> bcompletions.txt
    cur=${COMP_WORDS[COMP_CWORD]}
    # echo "cur: ${COMP_WORDS[COMP_CWORD]}"  >> bcompletions.txt
    prev=${COMP_WORDS[COMP_CWORD - 1]}
    prevprev=${COMP_WORDS[COMP_CWORD - 2]}
    local full_cmd="${COMP_WORDS[@]}"
    echo "_geo_complete[$COMP_CWORD]: $full_cmd" >> /tmp/geo-complete
    # echo "prev: $prev"  >> bcompletions.txt
    local cmd_key="${full_cmd// /.}"
    cmd_key=${cmd_key:0:-1}
    e cmd_key  >> /tmp/geo-complete
    case ${COMP_CWORD} in
        0) COMPREPLY=($(compgen -W "geo geo-cli" -- ${cur})) ;;
        # e.g., geo
        1)
            local cmds="${COMMAND_INFO[_commands]}"
            # local cmds="${COMMANDS[*]}"

            COMPREPLY=($(compgen -W "$cmds" -- ${cur}))
            ;;
        # e.g., geo db
        2)
            # echo "2: $prevprev/$prev/$cur" >> ~/bcompletions.txt
            # echo "2: SUBCOMMAND_COMPLETIONS[$prev] = ${SUBCOMMAND_COMPLETIONS[$prev]}" >> ~/bcompletions.txt
            # echo "$prevprev/$prev/$cur"
            if [[ -n ${COMMAND_INFO[$cmd_key]} ]]; then
                if [[ $cur =~ ^- && -n ${COMMAND_INFO[$cmd_key.options]} ]]; then
                    COMPREPLY=($(compgen -W "${COMMAND_INFO[$cmd_key.options]}" -- ${cur}))
                elif [[ -n ${COMMAND_INFO[$cmd_key._subcmds]}  ]]; then
                    # echo "SUBCOMMANDS[$cur]: ${SUBCOMMANDS[$prev]}" >> bcompletions.txt
                    COMPREPLY=($(compgen -W "${COMMAND_INFO[$cmd_key._subcmds]}" -- ${cur}))
                fi
            elif [[ -v SUBCOMMAND_COMPLETIONS[$prev] ]]; then
                COMPREPLY=($(compgen -W "${SUBCOMMAND_COMPLETIONS[$prev]}" -- ${cur}))
                case $prev in
                    get | set | rm) COMPREPLY=($(compgen -W "$(@geo_env ls keys)" -- ${cur^^})) ;;
                esac
            else
                COMPREPLY=()

            fi

            case $prev in
                mydecoder)
                    # echo "2:if:case:mydecoder" >> ~/bcompletions.txt
                    COMPREPLY=($(compgen -W "$(ls -A)" -- ${cur}))
                    ;;
            esac
            # case ${prev} in
            #     configure)
            #         COMPREPLY=($(compgen -W "CM DSP NPU" -- ${cur}))
            #         ;;
            #     show)
            #         COMPREPLY=($(compgen -W "some other args" -- ${cur}))
            #         ;;
            # esac
            _geo_autocomplete_filename
            ;;
        # e.g., geo db start
        3)
            case $prevprev in
                db) [[ $prev =~ start|rm|remove|cp|copy ]] && COMPREPLY=($(compgen -W "$(geo_dev databases)" -- ${cur})) ;;
                env) [[ $prev =~ ls|get|set|rm ]] && COMPREPLY=($(compgen -W "$(@geo_env ls keys)" -- ${cur^^})) ;;
                    # get|set|rm ) COMPREPLY=($(compgen -W "$(@geo_env ls keys)" -- ${cur})) ;;
            esac
            # geo db start
            # if [[ $prevprev == db && $prev =~ start|rm ]]; then
            #     COMPREPLY=($(compgen -W "$(geo_dev databases)" -- ${cur}))
            # fi
            _geo_autocomplete_filename
            ;;
        *)
            # echo "star: $prevprev/$prev/$cur" >> ~/bcompletions.txt
            COMPREPLY=()
            _geo_autocomplete_filename
            # Autocomplete file namse in current directory if the current word doesn't start with '-' (an option).
            # [[ $full_cmd =~ mydecoder && ! $cur =~ ^- ]] && COMPREPLY=($(compgen -W "$(ls -A)" -- ${cur}))
            # echo ${cur}
            ;;
    esac
}

_geo_autocomplete_filename() {
    [[ $full_cmd =~ mydecoder && ! $cur =~ ^- ]] && COMPREPLY=($(compgen -W "$(ls -A)" -- ${cur}))
    return 0
}

complete -F _geo_complete geo
complete -F _geo_complete geo-cli
