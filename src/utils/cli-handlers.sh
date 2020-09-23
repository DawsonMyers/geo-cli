#!/bin/bash
# echo 'init handlers'
# GEO_REPO_DIR=~/menlolab
# GEO_CLI_DIR=$HOME/.geo-cli/cli
. $GEO_SRC_DIR/utils/colors.sh
# . $GEO_CLI_DIR/utils/secrets.sh
. $GEO_SRC_DIR/utils/config-file-utils.sh

# ENV_CONF_FILE=$GEO_CLI_DIR/src/config/env.conf

IMAGE=postgres11
CONTAINER="geo_${IMAGE}"
CONTAINER_NAME=""


# A list of all of the commands
export COMMANDS=()

# First argument commands
###############################################################################
# Each command has three parts:
#   1. Its name is added to the COMMANDS array
#   2. Command documentation function (for printing help)
#   3. Command function
# Example:
#   COMMAND+=('command')
#   geo_command_doc() {...}
#   geo_command() {...}
#
# Template:
###########################################################
# COMMANDS+=('command')
# geo_command_doc() {
# 
# }
# geo_command() {
#  
# }
###############################################################################

###########################################################
COMMANDS+=('db')
geo_db_doc() {
    doc_cmd 'db'
    doc_cmd_desc 'Database commands'
}
geo_db() {
    db_version="$1"
    if [ -z "$db_version" ]; then
        db_version=`geo_get LAST_DB_VERSION`
        if [[ -z $db_version ]]; then
            error "No database version provided."
            return
        fi
    fi

    geo_set LAST_DB_VERSION "$db_version"

    VOL_NAME="geo_db_${db_version}"
    CONTAINER_NAME="${CONTAINER}_${db_version}"

    # docker run -v 2002:/var/lib/postgresql/11/main -p 5432:5432 postgres11

    VOLUME=`docker volume ls | grep " $VOL_NAME"`

    geo_stop $1
    CONTAINER_ID=`docker ps -aqf "name=$CONTAINER_NAME"`
    local volume_created=false

    if [ -z "$VOLUME" ]; then
        verbose "Creating volume: $VOL_NAME"
        docker volume create "$VOL_NAME" > /dev/null 
        info OK
        volume_created=true
    fi
    if [ -n "$CONTAINER_ID" ]; then
        
        verbose "Starting existing container:"
        verbose "  ID: $CONTAINER_ID"
        verbose "  NAME: $CONTAINER_NAME"
        docker start $CONTAINER_ID > /dev/null && info OK
    else
        verbose "Creating container:"
        verbose "  ID: $CONTAINER_ID"
        verbose "  NAME: $CONTAINER_NAME"
        docker run -v $VOL_NAME:/var/lib/postgresql/11/main -p 5432:5432 --name=$CONTAINER_NAME -d $IMAGE > /dev/null && info OK
        if [[ $volume_created = true ]]; then
            verbose "Waiting for container to start..."
            sleep 10
            verbose "Initiallizing geotab demo"
            geo_db_init
        fi
    fi
        
    # else
    #     if [ -n "$CONTAINER_ID" ]; then
    #         docker start $CONTAINER_ID
    #     else
    #         docker run -v $VOL_NAME:/var/lib/postgresql/11/main -p 5432:5432 --name=$CONTAINER_NAME -d $IMAGE
    #     fi
    # fi
}

function geo_db_init()
{
    local user=`geo_get DB_USER`
    local password=`geo_get DB_PASSWORD`
    local answer=''
    get_user() {
        prompt_n "Enter DB username: "
        read user
        geo_set DB_USER $user
    }

    get_password() {
        prompt_n "Enter DB password: "
        read password
        geo_set DB_PASSWORD $password
    }

    if [ -z "$user" ]; then
        get_user
    else
        verbose "Stored DB user: $user"
        prompt_n "Use stored user? (Y|n)"
        read answer
        [[ "$answer" =~ [nN] ]] && get_user
    fi

    if [ -z "$password" ]; then
        get_password
    else
        verbose "Stored DB password: $password"
        prompt_n "Use stored password? (Y|n)"
        read answer
        [[ "$answer" =~ [nN] ]] && get_password
    fi
    path=$HOME/repos/MyGeotab/Checkmate/bin/Debug/netcoreapp3.1
    # pushd $path
    debug $path
    debug $user
    # dotnet CheckmateServer.dll CreateDatabase postgres companyName=geotabdemo administratorUser=<your email address> administratorPassword=<choose a password> sqluser=geotabuser sqlpassword=vircom43
    # debug "${path}/CheckmateServer.dll" CreateDatabase postgres companyName=geotabdemo administratorUser="$user" administratorPassword="$password" sqluser=geotabuser sqlpassword=vircom43
    dotnet "${path}/CheckmateServer.dll" CreateDatabase postgres companyName=geotabdemo administratorUser="$user" administratorPassword="$password" sqluser=geotabuser sqlpassword=vircom43
    # dotnet CheckmateServer.dll CreateDatabase postgres companyName=geotabdemo administratorUser="$user" administratorPassword="$password" sqluser=geotabuser sqlpassword=vircom43
    # popd
}

function geo_db_rm()
{
    CONTAINER_NAME="${CONTAINER}_${1}"
    VOL_NAME="geo_db_${1}"
    CONTAINER_ID=`docker ps -aqf "name=$CONTAINER_NAME"`
    [ -n "$CONTAINER_ID" ] && docker stop $CONTAINER_ID
    docker container rm $CONTAINER_NAME
    docker volume rm $VOL_NAME

}

###########################################################
COMMANDS+=('stop')
geo_stop_doc() {
    doc_cmd 'stop [db]'
    doc_cmd_examples_title
    doc_cmd_example 'geo stop web'
}
geo_stop() {
    CONTAINER_NAME="${CONTAINER}_${1}"
    ID=`docker ps -qf "name=$CONTAINER_NAME"`

    if [ -n "$ID" ]; then
        docker stop $ID
    fi
}

###########################################################
COMMANDS+=('init')
geo_init_doc() {
    doc_cmd 'db'
    doc_cmd_desc 'Initiallize repo directory'

    doc_cmd_options_title
    doc_cmd_option '--here'
    doc_cmd_option_desc 'Init repo directory using the current directory'
    
    doc_cmd_examples_title
    doc_cmd_example 'geo init'
    doc_cmd_example 'geo init --here'
}
geo_init() {
    # if [ -z $MLO_REPO_DIR ]; then
    #     dir=`cfg_read $MLO_CONF_FILE MLO_REPO_DIR`
    #     [ -z $dir ] && export MLO_REPO_DIR=~/menlolab
    # fi

    # Check if mlo system is running, shut it down if it is. This is done by
    # checking the length of output from the mlo ps command; which will be
    # shorter than 200 characters if no containers are running.
    # if [ -d $MLO_REPO_DIR/env/full ]; then
    #     mps=`mlo ps`
    #     [ ${#mps} -gt 200 ] && mlo down
    # fi

    # local init_here=''

    # local declare -A options
    # Read all arguments
    # while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
    #     --here )
    #         options[here]=true
    #         init_here='here'
    #         shift
    #         ;;
    #     # Delete entire repo dir if it exists
    #     -c | --clean )
    #         shift;
    #         if [ -d $MLO_REPO_DIR ] && [ -d $MLO_REPO_DIR/env ]; then
    #             info "WARNING: Repo directory at $MLO_REPO_DIR will be deleted (any unpushed commits will be PERMANENTLY removed)"
    #             if prompt_continue ; then
    #                 debug "REMOVING $MLO_REPO_DIR"
    #                 sudo rm -rf $MLO_REPO_DIR
    #             else
    #                 verbose "Skipping repo directory removal"
    #             fi
    #         fi
    #         ;;
    #     # Delete all node_modules directories from repo dir
    #     --clean-npm )
    #         shift;
    #         if [[ -d $MLO_REPO_DIR && -d $MLO_REPO_DIR/env ]]; then
    #             cd $MLO_REPO_DIR
    #             info "WARNING: All node_modules directories in $MLO_REP_DIR will be PERMANENTLY removed"
    #             # find ./*/**/node_modules
    #             if prompt_continue ; then
    #                 debug "REMOVING node_modules:"
    #                 sudo rm -rf $MLO_REPO_DIR/*/**/node_modules
    #             else
    #                 verbose "Skipping node_modules directories removal"
    #             fi
    #         fi
    #         ;;
    #     --build | -b )
    #             options[build]=true
    #         ;;
    # esac; shift; done

    if [[ "$1" == '--' ]]; then shift; fi

    case $1 in
        'repo' | '' )
            local repo_dir=`pwd`
            geo_set GEO_CLI_MYGEOTAB_REPO_DIR "$repo_dir"
            verbose "MyGeotab base repo (Development) path set to:"
            detail "    $repo_dir"
            ;;
    esac
}

###########################################################
COMMANDS+=('start')
geo_start_doc() {
    doc_cmd 'start <service>'
    doc_cmd_desc 'Start individual service.'
    doc_cmd_examples_title
    doc_cmd_example 'geo start web'
}
geo_start() {
    exit_if_repo_dir_uninit
    if [ -n "${SERVICES_DICT[$1]}" ]; then
        if [[ $1 = 'runner' ]]; then
            # pm2-runtime start $GEO_REPO_DIR/runner/.geo-cli/ecosystem.config.js
            geo_runner start
        else
            cd $GEO_REPO_DIR/env/full
            dc_geo start $1
        fi
    else
        error "$1 is not a service"
    fi
}

# ###########################################################
# COMMANDS+=('stop')
# geo_stop_doc() {
#     doc_cmd 'stop <service>'
#     doc_cmd_examples_title
#     doc_cmd_example 'geo stop web'
# }
# geo_stop() {
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
#         error "$1 is not a service"
#     fi
# }

###########################################################
COMMANDS+=('restart')
geo_restart_doc() {
    doc_cmd 'restart [service]'
    doc_cmd_desc 'Restart container [service] or the entire system if no service is provided.'
    doc_cmd_examples_title
    doc_cmd_example 'geo restart web'
    doc_cmd_example 'geo restart'
}
geo_restart() {
    exit_if_repo_dir_uninit
    if [ -z $1 ]; then 
        # geo_down
        geo_stop
        geo_up
        geo_runner restart
        return
    fi
    
    if [ -n "${SERVICES_DICT[$1]}" ]; then
        if [[ $1 = 'runner' ]]; then
            # pm2 restart runner
            geo_runner restart
        else
            cd $GEO_REPO_DIR/env/full
            dc_geo restart "$1"
        fi
    else
        error "$1 is not a service"
    fi
}

###########################################################
COMMANDS+=('config')
geo_config_doc() {
    doc_cmd 'set <ENV_VAR> <value>'
    doc_cmd_desc 'Set geo environment variable'
    doc_cmd_examples_title
    doc_cmd_example 'geo set GEO_REPO_DIR ~/menlolab'
}
geo_config() {
    if [[ -z $1 ]]; then
        geo_config_doc
        return
    fi

    case $1 in
        'set' )
            shift
            geo_set "$@"
            ;;
        'get' )
            shift
            geo_get "$@"
            ;;
        'ls' )
            local env_vars=`cat $GEO_CONF_FILE`
            detail "$env_vars"
            ;;
    esac 
}

###########################################################
COMMANDS+=('set')
geo_set_doc() {
    doc_cmd 'set <ENV_VAR> <value>'
    doc_cmd_desc 'Set geo environment variable'
    doc_cmd_examples_title
    doc_cmd_example 'geo set GEO_REPO_DIR ~/menlolab'
}
geo_set() {
    # Set value of env var
    # $1 - name of env var in conf file
    # $2 - value 
    local key="$1"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"

    cfg_write $GEO_CONF_FILE $key $2
    export $key=$2
}

###########################################################
COMMANDS+=('get')
geo_get_doc() {
    doc_cmd 'get <ENV_VAR>'
    doc_cmd_desc 'Get geo environment variable.'

    doc_cmd_examples_title
    doc_cmd_example 'geo get GEO_REPO_DIR'
}
geo_get() {
    # Get value of env var
    local key="$1"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"

    value=`cfg_read $GEO_CONF_FILE $key`
    [[ -z $value ]] && return
    echo `cfg_read $GEO_CONF_FILE $key`
}

geo_haskey() {
    cfg_haskey $GEO_CONF_FILE $1
}

###########################################################
COMMANDS+=('update')
geo_update_doc() {
    doc_cmd 'update'
    doc_cmd_desc 'Update geo to latest version.'

    doc_cmd_examples_title
    doc_cmd_example 'geo update'
}
geo_update() {
   
    bash $GEO_CLI_DIR/install.sh
}

###########################################################
COMMANDS+=('version')
geo_version_doc() {
    doc_cmd 'version, -v, --version'
    doc_cmd_desc 'Update geo to latest version'
    
    doc_cmd_examples_title
    doc_cmd_example 'geo version'
}
geo_version() {
    verbose `geo_get GEO_CLI_VERSION`
}

###########################################################
COMMANDS+=('help')
geo_help_doc() {
    doc_cmd 'help, -h, --help'
    doc_cmd_desc 'Prints out help for all commands.'
}
geo_help() {
    for cmd in "${COMMANDS[@]}"; do
            "geo_${cmd}_doc"
        done
}

###########################################################
# COMMANDS+=('command')
# geo_command_doc() {
# 
# }
# geo_command() {
#  
# }

###########################################################
# COMMANDS+=('command')
# geo_command_doc() {
# 
# }
# geo_command() {
#  
# }

# Util
###############################################################################

cmd_exists() {
    cmd=$(echo "${COMMANDS[@]}" | tr ' ' '\n' | grep -E "`echo ^$1\$`")
    echo $cmd
    [ -z $cmd ] && return 1
}

# Docker Compose using the geo config file
dc_geo() {
    local dir=$GEO_REPO_DIR/env/full
    docker-compose -f $dir/docker-compose.yml -f $dir/docker-compose-geo.yml $@
    # docker-compose -f $GEO_REPO_DIR/env/full/docker-compose-geo.yml $1
}

# Check for updates. Return true (0 return value) if updates are available.
geo_check_for_updates() {
    # pu
    pushd $GEO_CLI_DIR
    [ ! git pull > /dev/null ] && error 'Unable to pull changes from remote'
    popd
    # The sed cmds filter out any colour codes that might be in the text
    local v_current=`geo_get GEO_CLI_VERSION  | sed -r "s/[[:cntrl:]]\[[0-9]{1,3}m//g"`
    # local v_npm=`npm show @geo/geo-cli version  | sed -r "s/[[:cntrl:]]\[[0-9]{1,3}m//g"`
    local v_repo=`cat $GEO_CLI_DIR/version.txt`

    if [ `ver $v_current` -lt `ver $v_repo` ]; then
        geo_set GEO_OUTDATED true
        return 0
    else
        geo_set GEO_OUTDATED false
        return 1
    fi
    
}

geo_is_outdated() {
    outdated=`geo_get GEO_OUTDATED`
    # [ -z $outdated ] && outdated=false
    # debug "o=$outdated"
    if [[ $outdated =~ true ]]; then
        # debug outdated
        return 0
    else
        return 1
    fi
}

# This was a lot of work to get working right. There were issues with comparing
# strings with number and with literal values. I would read the value 'true'
# or a version number from a file and then try comparing it in an if statement,
# but it wouldn't work because it was a string. Usually 'true' == true will
# work in bash, but when reading from a file if doesn't. This was remedied
# using a regex in the if (i.e., if [[ $outdated =~ true ]]) which was the only
# way it would work.
geo_show_msg_if_outdated() {
    echo "" > /dev/null
    # outdated=`geo_get GEO_OUTDATED`
    if geo_is_outdated ; then
    # if [[ $outdated =~ true ]]; then
        warn_bi "New version of geo available. Use 'geo update' to get it."
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
    v1=`fix_char $(echo "$1" | gawk -F. '{ printf("%s", $1) }')`
    v2=`fix_char $(echo "$1" | gawk -F. '{ printf("%s", $2) }')`
    v3=`fix_char $(echo "$1" | gawk -F. '{ printf("%s", $3) }')`

    # The parts are reconstructed in a new string (without the \027 char)
    echo "$v1.$v2.$v3" | gawk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }'; 
    # echo "$@" | gawk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }'; 
}

# Replace the char value 27 with the char '1'. For some reason the '1' char
# can get a value of 27 when read in from some sources. This should fix it.
# This issue causes errors when comparing semvar string versions.
fix_char() {
    local ord_val=`ord $1`
    # echo "ord_val = $ord_val"
    if [[ "$ord_val" = 27 ]]; then
        echo 1
    else
        echo $1
    fi
}

# Semver version $1 less than or equal to semver version $2 (1.1.1 < 1.1.2 => true).
ver_lte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}
ver_gt() { 
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; 
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

# Logging helpers
###########################################################

# Repeat string n number of times.
# 1: a string to repeat
# 2: the number of repeats
repeat_str() {
    echo $(printf "$1%.0s" `seq 1 $2`)
}
# Format long strings of text into lines of a certain width. All lines can also
# be indented.
# 1: the long string to format
# 2: the number of spaces to indent the text with
# 3: the string/char used to indent then text with (a space, by default)
fmt_text() {
    local indent=0
    local indent_len=0
    local indent_str=' '
    # Replace 2 or more spaces with a single space and \n with a single space.
    local txt=$(echo $1 | sed -E 's/ {2,}/ /g' | tr '\n' ' ')
    # Check if args 2 and 3 were provided.
    [ "$2" ] && indent=$2
    [ "$3" ] && indent_str=$3
    
    [[ $indent = 0 ]] && indent_str=''
    # Determin the total length of the repeated indent string.
    indent_len=$((${#indent_str}*indent))
    # Get the width of the console.
    local width=`tput cols`
    # Get max width of text after the indent widht is subtracted.
    width=$((width-indent_len))

    local sed_pattern="s/^/"
    # Repeate the indent string $indent number of times. seq is used to create
    # a seq from 1 ... $indent (e.g. 1 2 3 4, for $indent=4). So for 
    # $indent_str='=+' and $indent=3, this line, when evaluated, would print
    # '=+=+=+'. Note that printf "%.0s" "some-str" will print 0 chars of
    # "some-str". printf "%.3s" "some-str" would print 'som' (3 chars).
    sed_pattern+=$(printf "$indent_str%.0s" `seq 1 $indent`)
    sed_pattern+="/g"
    # Text is piped into fmt to format the text to the correct width, then
    # indented using the sed substitution.
    echo $txt | fmt -w $width | sed "$sed_pattern"
    # echo $1 | fmt -w $width | sed "s/^/$(printf '$%.0s' `seq 1 $indent`)/g"
}

# A function that dynamically creates multiple colour/format variants of logger functions.
# This works by using the eval function to dynamically create new functions each time
# make_logger_function is called.
# Args:
#   name: the base name of the logger function (e.g. verbose)
#   base_colour: the name of the base colour (from constants in colors.sh)
# Example:
#   make_logger_function info Green
#       This will create bold, intense, bold-intense, and underline variants of the info
#       functions. These functions will have suffixes of _b, _i, _bi, and _u. Also,
#       a base function with no suffix is created with the base colour (i.e. a function
#       with the name info and colour of green is created).
make_logger_function() {
    # The placement of the \ chars are very important for delaying the evaluation of
    # the shell vars in the strings. Notice how ${1}, ${2}, and ${Off} appear without
    # $ being prefixed with a \. This is because we want the the args to be filled in
    # immediately. So if this func is called with 'info' and 'Green' as args, the
    # string passed to eval would be "info() { echo -e \"\${Green}\$@${Off}"; }".
    # Which would then create a function called info that would take all of its args
    # and echo them out with green text colour. This is done by first echoing the
    # non-printable char for green text stored in the var $Green, then echoing the
    # text, and finally, echoing the remove all format char stored in $Off.
    
    # Creates log functions that take -p as an arg if you want the output to be on the same line (used when prompting the user for information).
    name=$1
    color=$2
    eval "${name}() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_b() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${B${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_i() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${I${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_bi() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${BI${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_u() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${U${color}}\${args[@]}\${Off}\"; }"
    
    # local variants=("e " "en _prompt")
    # for variant in "${variants[@]}"; do
    #     read -a args <<< "$variant"
    #     local options=${args[0]}
    #     local suffix=${args[1]}

    #     echo "${1}${suffix}() { echo -${options} \"\${${2}}\$@\${Off}\"; }"
    #     eval "${1}${suffix}() { echo -${options} \"\${${2}}\$@\${Off}\"; }"
    #     # Variants are created by creating var names through multiple passes of string
    #     # interpolation.
    #     eval "${1}_b${suffix}() { echo -${options} \"\${B${2}}\$@\${Off}\"; }"
    #     eval "${1}_i${suffix}() { echo -${options} \"\${I${2}}\$@\${Off}\"; }"
    #     eval "${1}_bi${suffix}() { echo -${options} \"\${BI${2}}\$@\${Off}\"; }"
    #     eval "${1}_u${suffix}() { echo -${options} \"\${U${2}}\$@\${Off}\"; }"
    # done

    # Note: echoing FUNCNAME[@] will print the call stack of cmds.
}

red() {
    echo -e "${Red}$@${Off}"
}


error() {
    echo -e "${BIRed}Error: $@${Off}"
}

make_logger_function warn Red
make_logger_function info Green
make_logger_function success Green
make_logger_function detail Yellow
make_logger_function data White
# make_logger_function warn Purple
make_logger_function verbose Cyan
make_logger_function debug Purple

prompt() {
    echo -e "${BCyan}$@${Off}"
}

# Echo without new line
prompt_n() {
    echo -en "${BCyan}$@${Off}"
}

valid_repo() {
    if [ ${REPOS_DICT[$1]+_} ]; then
        return 0
    else
        return 1
    fi
}

# Documentation helpers
###########################################################

# The name of a command
doc_cmd() {
    local indent=4
    local txt=$(fmt_text "$@" $indent)
    # detail_u "$txt"
    detail_b "$txt"
}

# Command description
doc_cmd_desc() {
    local indent=8
    local txt=$(fmt_text "$@" $indent)
    info_i "$txt"
}

doc_cmd_examples_title() {
    local indent=8
    local txt=$(fmt_text "Example:" $indent)
    info_i "$txt"
    # info_i "$(fmt_text "Example:" $indent)"
}

doc_cmd_example() {
    local indent=12
    local txt=$(fmt_text "$@" $indent)
    info_i "$txt"
}
doc_cmd_options_title() {
    local indent=8
    local txt=$(fmt_text "Options:" $indent)
    info_i "$txt"
}
doc_cmd_option() {
    local indent=12
    local txt=$(fmt_text "$@" $indent)
    verbose_bi "$txt"
}
doc_cmd_option_desc() {
    local indent=16
    local txt=$(fmt_text "$@" $indent)
    info_i "$txt"
}

prompt_continue_or_exit() {
    prompt_n "Do you want to continue? (Y|n): "
    read answer
    [[ "$answer" =~ [nN] ]] && return 1 || return 0
}
prompt_continue() {
    prompt_n "Do you want to continue? (Y|n): "
    read answer
    [[ "$answer" =~ [nN] ]] && return 1 || return 0
}

geo_logo() {
    detail '  ___  ____  __         ___  __    __ '
    detail ' / __)(  __)/  \  ___  / __)(  )  (  )'
    detail '( (_ \ ) _)(  O )(___)( (__ / (_/\ )( '
    detail ' \___/(____)\__/       \___)\____/(__)'
}

geotab_logo() 
{
    detail ''
    detail '===================================================='
    detail ''
    detail ' ██████  ███████  ██████  ████████  █████  ██████ '
    detail '██       ██      ██    ██    ██    ██   ██ ██   ██'
    detail '██   ███ █████   ██    ██    ██    ███████ ██████ '
    detail '██    ██ ██      ██    ██    ██    ██   ██ ██   ██'
    detail ' ██████  ███████  ██████     ██    ██   ██ ██████ '
    detail ''
    detail '===================================================='
}
# geo_logo() {
#     detail ''
#     detail '=============================================================================='
#     node $GEO_CLI_DIR/src/cli/logo/logo.js
#     detail ''
#     detail '=============================================================================='
#     # detail ''
# }

# Auto-complete for commands
completions=(
    "${COMMANDS[@]}"
    )

# Doesn't work for some reason
# complete -W "${completions[@]}" geo

# Get list of completions separated by spaces (required as imput to complete command)
comp_string=`echo "${completions[@]}"`
complete -W "$comp_string" geo