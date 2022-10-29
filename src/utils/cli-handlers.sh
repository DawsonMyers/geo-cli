#!/bin/bash

# This file contains all geo-cli command logic.
# All geo-cli commands will have at least 2 functions defined that follow the following format: geo_<command_name> and 
# geo_<command_name>_doc (e.g. geo db has functions called geo_db and geo_db_doc). These functions are called from src/geo-cli.sh.

# Gets the absolute path of the root geo-cli directory.
export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
export GEO_CLI_SRC_DIR="${GEO_CLI_DIR}/src"

# Import colour constants/functions and config file read/write helper functions.
. $GEO_CLI_SRC_DIR/utils/colors.sh
. $GEO_CLI_SRC_DIR/utils/config-file-utils.sh
. $GEO_CLI_SRC_DIR/utils/log.sh

# Set up config paths (used to store config info about geo-cli)
export GEO_CLI_CONFIG_DIR="$HOME/.geo-cli"
export GEO_CLI_CONF_FILE="$GEO_CLI_CONFIG_DIR/.geo.conf"
export GEO_CLI_AUTOCOMPLETE_FILE="$GEO_CLI_CONFIG_DIR/geo-cli-autocompletions.txt"
export GEO_CLI_SCRIPT_DIR="${GEO_CLI_CONFIG_DIR}/scripts"

# The name of the base postgres image that will be used for creating all geo db containers.
export IMAGE=geo_cli_db_postgres
export GEO_DB_PREFIX=$IMAGE
export OLD_GEO_DB_PREFIX=geo_cli_db_postgres11

# A list of all of the top-level geo commands.
# This is used in geo-cli.sh to confirm that the first param passed to geo (i.e. in 'geo db ls', db is the top-level command) is a valid command.
export COMMANDS=()
declare -A SUBCOMMANDS
declare -A SUBCOMMAND_COMPLETIONS
export CURRENT_COMMAND=''
export CURRENT_SUBCOMMAND=''
export CURRENT_SUBCOMMANDS=()

# set -eE -o functrace
# set -x
# failure() {
#   local lineno=$1
#   local msg=$2
#   local func=$3
#   echo "Failed at $lineno: $msg in function: ${func}"
# }
# trap 'failure ${LINENO} "$BASH_COMMAND" ${FUNCNAME[0]}' ERR


# First argument commands
#######################################################################################################################
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
#######################################################################################################################
# COMMANDS+=('command')
# geo_command_doc() {
#
# }
# geo_command() {
#
# }
#######################################################################################################################


_geo_check_db_image() {
    local image=$(docker image ls | grep "$IMAGE")
    if [[ -z $image ]]; then
        if ! prompt_continue "geo-cli db image not found. Do you want to create one? (Y|n): "; then
            return 1
        fi
        geo_image create
    fi
}

#######################################################################################################################
COMMANDS+=('image')
geo_image_doc() {
    doc_cmd 'image'
    doc_cmd_desc 'Commands for working with db images.'
    doc_cmd_sub_cmds_title
        doc_cmd_sub_cmd 'create'
            doc_cmd_sub_cmd_desc 'Creates the base Postgres image configured to be used with geotabdemo.'
        doc_cmd_sub_cmd 'remove'
            doc_cmd_sub_cmd_desc 'Removes the base Postgres image.'
        doc_cmd_sub_cmd 'ls'
            doc_cmd_sub_cmd_desc 'List existing geo-cli Postgres images.'
        doc_cmd_examples_title
    doc_cmd_example 'geo image create'
}
geo_image() {
    case "$1" in
    rm | remove)
        docker image rm "$IMAGE"
        # if [[ -z $2 ]]; then
        #     log::Error "No database version provided for removal"
        #     return
        # fi
        # geo_db_rm "$2"
        return
        ;;
    create)
        log::status 'Building image...'
        local dir=$(geo_get DEV_REPO_DIR)
        dir="${dir}/Checkmate/Docker/postgres"
        local dockerfile="Debug.Dockerfile"
        (
            cd "$dir"
            docker build --file "$dockerfile" -t "$IMAGE" . && log::success 'geo-cli Postgres image created' || log::warn 'Failed to create geo-cli Postgres image'
        )
        return
        ;;
    ls)
        docker image ls | grep "$IMAGE"
        ;;
    esac

}

#######################################################################################################################
COMMANDS+=('db')
geo_db_doc() {
    doc_cmd 'db'
    doc_cmd_desc 'Database commands.'

    doc_cmd_sub_cmds_title

    doc_cmd_sub_cmd 'create [option] <name> [additional names]'
        doc_cmd_sub_cmd_desc 'Creates a versioned db container and volume. Multiple containers can be created at once by supplying additional names.'
        doc_cmd_sub_options_title
            doc_cmd_sub_option '-y'
                doc_cmd_sub_option_desc 'Accept all prompts.'
            doc_cmd_sub_option '-e'
                doc_cmd_sub_option_desc 'Create blank Postgres 12 container.'
            doc_cmd_sub_option '-d <database name>'
                doc_cmd_sub_option_desc 'Sets the name of the db to be created (only used if initializing it as well).'

    doc_cmd_sub_cmd 'start [option] [name]'
        doc_cmd_sub_cmd_desc 'Starts (creating if necessary) a versioned db container and volume. If no name is provided,
                            the most recent db container name is started.'
    doc_cmd_sub_options_title
        doc_cmd_sub_option '-y'
            doc_cmd_sub_option_desc 'Accept all prompts.'
        doc_cmd_sub_option '-b'
            doc_cmd_sub_option_desc 'Skip building MyGeotab when initializing a new db with geotabdemo. This is faster, but you have to make sure the correct version of MyGeotab has already been built'
        doc_cmd_sub_option '-d <database name>'
                doc_cmd_sub_option_desc 'Sets the name of the db to be created (only used if initializing it as well).'

    doc_cmd_sub_cmd 'cp <source_db> <destination_db>'
        doc_cmd_sub_cmd_desc 'Makes a copy of an existing database container.'

    doc_cmd_sub_cmd 'rm, remove [option] <version> [additional version to remove]'
        doc_cmd_sub_cmd_desc 'Removes the container and volume associated with the provided version (e.g. 2004).'
        doc_cmd_sub_options_title
            doc_cmd_sub_option '-a, --all [substring to match]'
                doc_cmd_sub_option_desc 'Remove all db containers and volumes. You can also add a substring that will be used to remove all containers that contain it. Example: geo db rm -a .0 => remove all containers that have .0 in their name (e.g. 10.0, 11.0).'

    doc_cmd_sub_cmd 'stop [version]'
        doc_cmd_sub_cmd_desc 'Stop geo-cli db container.'

    doc_cmd_sub_cmd 'ls [option]'
        doc_cmd_sub_cmd_desc 'List geo-cli db containers.'
        doc_cmd_sub_options_title
            doc_cmd_sub_option '-a, --all'
                doc_cmd_sub_option_desc 'Display all geo images, containers, and volumes.'

    doc_cmd_sub_cmd 'ps'
        doc_cmd_sub_cmd_desc 'List running geo-cli db containers.'

    doc_cmd_sub_cmd 'init'
        doc_cmd_sub_cmd_desc 'Initialize a running db container with geotabdemo or an empty db with a custom name.'
        doc_cmd_sub_options_title
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
        doc_cmd_sub_options_title
            doc_cmd_sub_option '-d'
                doc_cmd_sub_option_desc 'The name of the postgres database you want to connect to. The default value used is "geotabdemo"'
            doc_cmd_sub_option '-p'
                doc_cmd_sub_option_desc 'The admin sql password. The default value used is "vircom43"'
            doc_cmd_sub_option '-q'
                doc_cmd_sub_option_desc 'A query to run with psql in the running container. This option will cause the result of the query to be returned
                                                instead of starting an interactive psql terminal.'
            doc_cmd_sub_option '-u'
                doc_cmd_sub_option_desc 'The admin sql user. The default value used is "geotabuser"'

    doc_cmd_sub_cmd 'bash'
        doc_cmd_sub_cmd_desc 'Open a bash session with the running geo-cli db container.'

    doc_cmd_sub_cmd 'script <add|edit|ls|rm> <script_name>'
        doc_cmd_sub_cmd_desc "Add, edit, list, or remove scripts that can be run with $(log::txt_italic geo db psql -q script_name)."
        doc_cmd_sub_options_title
            doc_cmd_sub_sub_cmd 'add'
                doc_cmd_sub_sub_cmd_desc 'Adds a new script and opens it in a text editor.'
            doc_cmd_sub_sub_cmd 'edit'
                doc_cmd_sub_sub_cmd_desc 'Opens an existing script in a text editor.'
            doc_cmd_sub_sub_cmd 'ls'
                doc_cmd_sub_option_desc 'Lists existing scripts.'
            doc_cmd_sub_sub_cmd 'rm'
                doc_cmd_sub_sub_cmd_desc 'Removes a script.'

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
    doc_cmd_example 'geo db psql'
    doc_cmd_example 'geo db psql -u mySqlUser -p mySqlPassword -d dbName'
    doc_cmd_example 'geo db psql -q "SELECT * FROM deviceshare LIMIT 10"'
}
geo_db() {
    # Check to make sure that the current user is added to the docker group. All subcommands in this command need to use docker.
    if ! _geo_check_docker_permissions; then
        return 1
    fi

    _geo_db_check_for_old_image_prefix

    case "$1" in
    init)
        geo_db_init "${@:2}"
        return
        ;;
    ls)
        _geo_db_ls_containers

        # Show all geo-cli volumes and images if the user supplied some variant of all (-a, --all, all).
        if [[ $2 =~ ^-*a(ll)? ]]; then
            echo
            _geo_db_ls_volumes
            echo
            _geo_db_ls_images
        fi
        return
        ;;
    ps)
        docker ps --filter name="$IMAGE*"
        return
        ;;
    stop)
        _geo_db_stop "${@:2}"
        return
        ;;
    rm | remove)
        db_version="$2"

        if [[ -z $db_version ]]; then
            log::Error "No database version provided for removal"
            return
        fi

        geo_db_rm "${@:2}"
        return
        ;;
    create)
        _geo_db_create "${@:2}"
        ;;
    start)
        _geo_db_start "${@:2}"
        ;;
    cp | copy)
        _geo_db_copy "${@:2}"
        ;;
    psql)
        _geo_db_psql "${@:2}"
        ;;
    script)
        _geo_db_script "${@:2}"
        ;;
    bash | ssh)
        local running_container_id=$(_geo_get_running_container_id)
        if [[ -z $running_container_id ]]; then
            log::Error 'No geo-cli containers are running to connect to.'
            log::info "Run $(log::txt_underline 'geo db ls') to view available containers and $(log::txt_underline 'geo db start <name>') to start one."
            return 1
        fi

        docker exec -it $running_container_id /bin/bash
        ;;
    *)
        log::Error "Unknown subcommand '$1'"
        ;;
    esac
}

_geo_db_check_for_old_image_prefix() {
    old_container_prefix='geo_cli_db_postgres11_'
    containers=$(docker container ls -a --format '{{.Names}}' | grep $old_container_prefix)

    # Return if there aren't any containers with old prefixes.
    [[ -z $containers || -z $IMAGE ]] && return

    log::debug 'Fixing container names'
    for old_container_name in $containers; do
        cli_name=${old_container_name#$old_container_prefix}
        new_container_name="${IMAGE}_${cli_name}"
        log::debug "$old_container_name -> $new_container_name"
        docker rename $old_container_name $new_container_name
    done

    # Rename existing image.
    docker image tag geo_cli_db_postgres11 $IMAGE 2> /dev/null
}

_geo_db_stop() {
    local silent=false

    if [[ $1 =~ -s ]]; then
        silent=true
        shift
    fi
    local container_name=$(_geo_container_name $db_version)

    db_version="$1"

    if [[ -z $db_version ]]; then
        container_id=$(_geo_get_running_container_id)
        # container_id=`docker ps --filter name="$IMAGE*" --filter status=running -aq`
    else
        container_id=$(_geo_get_running_container_id "${container_name}")
        # container_id=`docker ps --filter name="${container_name}" --filter status=running -aq`
    fi

    if [[ -z $container_id ]]; then
        [[ $silent = false ]] &&
            log::warn 'No geo-cli db containers running'
        return
    fi

    log::status -b 'Stopping container...'

    # Stop all running containers.
    echo $container_id | xargs docker stop >/dev/null && log::success 'OK'
}

_geo_db_create() {
    local silent=false
    local accept_defaults=
    local no_prompt=
    local empty_db=false
    local db_name=
    local suppress_info=false
    local dont_prompt_for_db_name_confirmation=false

    # local build=false
    local OPTIND

    while getopts "sSyenbd:x" opt; do
        case "${opt}" in
            s ) silent=true ;;
            S ) suppress_info=true ;;
            y ) accept_defaults=true ;;
            n ) no_prompt=true ;;
            e ) empty_db=true && log::status -b 'Creating empty Postgres container';;
            d ) db_name="$OPTARG" ;;
            x ) dont_prompt_for_db_name_confirmation=true ;;
            # b ) build=true ;;
            : )
                log::Error "Option '${opt}' expects an argument."
                return 1
                ;;
            \? )
                log::Error "Invalid option: ${opt}"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    # if $build; then
    #     log::status -b 'Building MyGeotab'
    #     local dev_repo=$(geo_get DEV_REPO_DIR)
    #     myg_core_proj="$dev_repo/Checkmate/MyGeotab.Core.csproj"
    #     [[ ! -f $myg_core_proj ]] && Error "Build failed. Cannot find csproj file at: $myg_core_proj" && return 1;
    #     if ! dotnet build "${myg_core_proj}"; then
    #         Error "Building MyGeotab failed"
    #         return 1;
    #     fi
    # fi

    db_version="$1"
    db_version=$(_geo_make_alphanumeric "$db_version")
    # Create multiple containers if more than one container name was passed in (i.e., geo db create 8.0 9.0).
    if [[ -n $1 && -n $2 ]]; then
        log::debug 'Creating multiple containers'
        while [[ -n $1 ]]; do
            _geo_db_create -xS $1
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

    if ! _geo_check_db_image; then
        log::Error "Cannot create db without image. Run 'geo image create' to create a db image"
        return 1
    fi

    if [[ -z $accept_defaults && -z $no_prompt ]] && ! $dont_prompt_for_db_name_confirmation; then
        prompt_continue "Create db container with name $(log::txt_underline ${db_version})? (Y|n): " || return
    fi
    log::status -b "Creating volume:"
    log::status "  NAME: $container_name"
    docker volume create "$container_name" >/dev/null &&
        log::success 'OK' || { log::Error 'Failed to create volume' && return 1; }

    log::status -b "Creating container:"
    log::status "  NAME: $container_name"
    # docker run -v $container_name:/var/lib/postgresql/11/main -p 5432:5432 --name=$container_name -d $IMAGE > /dev/null && log::success OK
    local vol_mount="$container_name:/var/lib/postgresql/12/main"
    local port=5432:5432
    local image_name=$IMAGE
    local sql_user=postgres
    local sql_password='!@)(vircom44'
    local hostname=$container_name

    if [[ $empty_db == true ]]; then
        image_name=geo_cli_postgres
        dockerfile="
            FROM postgres:12
            ENV POSTGRES_USER postgres
            ENV POSTGRES_PASSWORD password
            RUN mkdir -p /var/lib/postgresql/12/main
        "
        sql_password=password
        docker build -t $image_name - <<< "$dockerfile"
    fi
   
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

_geo_copy_pgAdmin_server_config() {
    local iap=false
    local file_pattern=demo
    if [[ $1 == --iap ]]; then
        [[ -z $2 ]] && return
        iap=true
        file_pattern=iap
        # Replace : with \: to escape it (required format for passfiles).
        export iap_password="${2//:/\\:}"
        # export iap_database="$3"
        shift 3
        # shift 2
    fi
    export geotab_username=${1:-$USER}
    local config_file_dir="$GEO_CLI_SRC_DIR/includes/db"
    local destination_config_dir="$GEO_CLI_CONFIG_DIR/data/db"
    export passfile="$destination_config_dir/$file_pattern.passfile"
    mkdir -p "$destination_config_dir"

    (
        cd "$config_file_dir"
        for file in *$file_pattern*; do
            # Substitute in any environment variables and copy config files to the geo-cli config directory.
            envsubst < "$file" > "$destination_config_dir/$file"
        done
        # Required for pgAdmin to use it.
        [[ -f $passfile ]] && chmod 600 $passfile
    )
}

_geo_show_repo_dir_reminder() {
     local dev_repo=$(geo_get DEV_REPO_DIR)
    if [[ -n $dev_repo ]]; then
        log::info -f "Using the following path as the MyGeotab repo root. If this path needs to be updated, run $(txt_underline geo init repo) and select the correct location. Current MyGeotab repo path:"
        log::link "  $dev_repo"
        echo
    fi
}

_geo_db_start() {
    local accept_defaults=
    local no_prompt=
    local no_build=false
    local prompt_for_db=
    local db_version=
    local db_name=
    local OPTIND

    while getopts "ynbphd:" opt; do
        case "${opt}" in
            y ) accept_defaults=true ;;
            n ) no_prompt=true ;;
            b ) no_build=true ;;
            p ) prompt_for_db=true ;;
            h ) geo_db_doc && return ;;
            d ) db_name="$OPTARG" ;;
            : )
                log::Error "Option '${opt}' expects an argument."
                return 1
                ;;
            \? )
                log::Error "Invalid option: ${opt}"
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
            db_version=$(_geo_make_alphanumeric "$db_version")
        done
        # log::debug $db_version
    }
    
    

    if [[ $prompt_for_db == true ]]; then
        log::status -b 'Create Database'
        _geo_show_repo_dir_reminder
        log::info -f "Add the following options like this: [-option] <db name>. For example, '-by 10.0' would create a db named 10.0 using the 'skip build' and 'accept defaults' options"
        local skip_build_text="b: Skip building MyGeotab (faster, but the correct version of MyGeotab has to already be built."
        local accept_defaults_text="y: Accept defaults. Re-uses the previous username and passwords so that you aren't prompted to enter them again."
        log::detail "$(log::fmt_text_and_indent_after_first_line  "$skip_build_text" 0 3)"
        log::detail "$(log::fmt_text_and_indent_after_first_line  "$accept_defaults_text" 0 3)"
        prompt_for_db_version
        shift
    else
        _geo_show_repo_dir_reminder
        db_version="$1"
    fi

    db_version=$(_geo_make_alphanumeric "$db_version")
    # log::debug $db_version
    if [ -z "$db_version" ]; then
        db_version=$(geo_get LAST_DB_VERSION)
        if [[ -z $db_version ]]; then
            log::Error "No database version provided."
            return 1
        fi
    fi

    if ! _geo_check_db_image; then
        if ! prompt_continue "No database images exist. Would you like to create on? (Y|n): "; then
            log::Error "Cannot start db without image. Run 'geo image create' to create a db image"
            return 1
        fi
        geo image create
    fi

    geo_set LAST_DB_VERSION "$db_version"

    # VOL_NAME="geo_cli_db_${db_version}"
    local container_name=$(_geo_container_name $db_version)

    # docker run -v 2002:/var/lib/postgresql/11/main -p 5432:5432 postgres11

    # Check to see if the db is already running.
    local running_db=$(docker ps --format "{{.Names}}" -f name=geo_cli_db_)
    [[ $running_db == $container_name ]] && log::success "DB '$db_version' is already running" && return

    local volume=$(docker volume ls | grep " $container_name")
    # local volume_created=false
    # local recreate_container=false
    # [[ -n $volume ]] && volume_created=true

    # if [[ -z $volume ]]; then
    #     volume=$(docker volume ls | grep " geo_cli_db_postgres11_${db_version}")
    #     [[ -n $volume ]] && volume_created=true && recreate_container=true
    # fi

    geo_db stop -s

    # Check to see if a container is running that is bound to the postgres port (5432).
    # If it is already in use, the user will be prompted to stop it or exit.
    local port_in_use=$(docker ps --format '{{.Names}} {{.Ports}}' | grep '5432->')
    if [[ -n $port_in_use ]]; then
        # Get container name by triming off the port info from docker ps output.
        local container_name_using_postgres_port="${port_in_use%% *}"
        log::Error "Postgres port 5432 is currently bound to the following container: $container_name_using_postgres_port"
        [[ $no_prompt == true ]] && log::Error "Port error" && return 1
        if prompt_continue "Do you want to stop this container so that a geo db one can be started? (Y|n): "; then
            if docker stop "$container_name_using_postgres_port" > /dev/null; then
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

    if _geo_get_container_id -v container_id "$container_name"; then
        log::status -b "Starting existing container:"
        log::status "  ID: $container_id"
        log::status "  NAME: $container_name"

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
    else
        # db_version was getting overwritten somehow, so get its value from the config file.
        db_version=$(geo_get LAST_DB_VERSION)
        # db_version="$1"
        # db_version=$(_geo_make_alphanumeric "$db_version")

        if [[ -z $accept_defaults && -z $no_prompt ]]; then
            prompt_continue "Db container $(log::txt_underline ${db_version}) doesn't exist. Would you like to create it? (Y|n): " || return
        fi

        local opts=-sx
        [[ $accept_defaults == true ]] && opts+=y
        [[ $no_prompt == true ]] && opts+=n

        # log::debug "db_version: $db_version"

        _geo_db_create $opts "$db_version" ||
            { log::Error 'Failed to create db'; return 1; }

        try_to_start_db $container_name
        container_id=$(docker ps -aqf "name=$container_name")

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
        log::status "  ID: $container_id"
        log::status "  NAME: $container_name"

        [[ $no_prompt == true ]] && return
        
        opts=-
        [[ $accept_defaults == true ]] && opts+=y
        [[ $no_prompt == true ]] && opts+=n
        [[ $no_build == true ]] && opts+=b
        [[ ${#opts} -eq 1 ]] && opts=
        [[ -n $db_name ]] && opts+=" -d $db_name"
        echo
        # log::debug "geo_db_init $opts"
        if [[ $accept_defaults == true ]] || prompt_continue 'Would you like to initialize the db? (Y|n): '; then
            geo_db_init $opts
        else
            log::info "Initialize a running db anytime using $(log::txt_underline 'geo db init')"
        fi
    fi
    _geo_validate_server_config
    log::success Done
}

_geo_db_copy() {
    local interactive=false
    [[ $1 = -i ]] && interactive=true && shift

    local source_db="$1"
    local destination_db="$2"

    db_name_exists() {
        local name=$(_geo_container_name "$1")
        docker container inspect $name > /dev/null 2>&1
        # [[ $? == 0 ]]
    }

    source_db=$(_geo_make_alphanumeric "$source_db")
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

    destination_db=$(_geo_make_alphanumeric "$destination_db")
    local source_db_name=$(_geo_container_name "$source_db")
    local destination_db_name=$(_geo_container_name "$destination_db")


    # Make sure the destination database doesn't exist
    db_name_exists $destination_db && log::Error "There is already a container named '$destination_db'" && return 1

    log::status -b "\nCreating destination database volume '$destination_db'"
    docker volume create --name $destination_db_name > /dev/null

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

    prompt_continue "Would you like to start database container '$destination_db'? (Y/n): " && _geo_db_start $destination_db
}

_geo_db_psql() {
    local sql_user=$(geo_get SQL_USER)
    local sql_password=$(geo_get SQL_PASSWORD)
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
            script_path="$GEO_CLI_SCRIPT_DIR/$query".sql

            log::debug $script_path
            if [[ -f $script_path ]]; then
                query="$(cat $script_path | sed "s/'/\'/g")"
            fi
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
    log::debug $script_param_count
    if (( script_param_count > 0 )); then
        param_definitions="$(echo "$query" | grep '^--- ' | sed 's/--- //g')"
        param_names="$(sed 's/=.*//g' <<<"$param_definitions")"
        param_names_array=()
        default_param_values="$(sed 's/.*=//g' <<<"$param_definitions")"
        default_param_values_array=()
        declare -A param_lookup
        # Extract param names and values.
        default_param_count=0
        while read -r line; do
            param_names_array+=("$line")
            ((default_param_count++))
        done <<<"$param_names"
        while read -r line; do
            default_param_values_array+=("$line")
        done <<<"$default_param_values"

        for ((i = 0; i < default_param_count; i++)); do
            key="${param_names_array[$i]}"
            value="${default_param_values_array[$i]}"
            param_lookup["$key"]="$value"
        done
        for key in "${!cli_param_lookup[@]}"; do
            value="${cli_param_lookup[$key]}"
            param_lookup["$key"]="$value"
        done

        # log::debug "$query"

        # Remove all comments and empty lines.
        query="$(sed -e 's/--.*//g' -e '/^$/d' <<<"$query")"
        for key in "${!param_lookup[@]}"; do
            value="${param_lookup[$key]}"
            [[ -v cli_param_lookup["$key"] ]] && value="${cli_param_lookup[$key]}"
            log::debug "value=$value    key=$key"
            query="$(sed "s/{{$key}}/$value/g" <<<"$query")"
        done
        query="$(echo "$query" | tr '\n' ' ')"
        # log::debug "$query"
    fi

    # Assign default values for sql user/passord.
    [[ -z $db_name ]] && db_name=geotabdemo
    [[ -z $sql_user ]] && sql_user=geotabuser
    [[ -z $sql_password ]] && sql_password=vircom43

    local running_container_id=$(_geo_get_running_container_id)
    # log::debug $sql_user $sql_password $db_name $running_container_id

    if [[ -z $running_container_id ]]; then
        log::Error 'No geo-cli containers are running to connect to.'
        log::info "Run $(log::txt_underline 'geo db ls') to view available containers and $(log::txt_underline 'geo db start <name>') to start one."
        return 1
    fi

    if [[ -n $query ]]; then
        log::debug "docker exec $docker_options -e PGPASSWORD=$sql_password $running_container_id /bin/bash -c \"psql -U $sql_user -h localhost -p 5432 -d $db_name '$psql_options $query'\""
        eval "docker exec $docker_options -e PGPASSWORD=$sql_password $running_container_id /bin/bash -c \"psql -U $sql_user -h localhost -p 5432 -d $db_name '$psql_options $query'\""
    else
        docker exec -it -e PGPASSWORD=$sql_password $running_container_id psql -U $sql_user -h localhost -p 5432 -d $db_name
    fi
}

_geo_validate_server_config() {
    ! _geo_terminal_cmd_exists xmlstarlet && return 1;
    local server_config="$HOME/GEOTAB/Checkmate/server.config"
    local webPort=$(xmlstarlet sel -t -v //WebServerSettings/WebPort ~/GEOTAB/Checkmate/server.config)
    local sslPort=$(xmlstarlet sel -t -v //WebServerSettings/WebSSLPort ~/GEOTAB/Checkmate/server.config)

    if [[ $webPort == 80 || $sslPort == 443 ]]; then
        xmlstarlet ed --inplace -u "//WebServerSettings/WebPort" -v 10000 -u "//WebServerSettings/WebSSLPort" -v 10001 "$server_config" && \
            log::status "Setting server.config WebPort & WebSSLPort to correct values. From ($webPort, $sslPort) to (10000, 10001)." || \
            log::Error "Failed to update server.config with correct WebPort & WebSSLPort. Current values are ($webPort, $sslPort)."
    fi
    # xmlstarlet ed --inplace -u "//WebSSLPort" -v 10001 ~/GEOTAB/Checkmate/server.config

}

_geo_db_script() {
    [[ -z $GEO_CLI_SCRIPT_DIR ]] && log::Error "GEO_CLI_SCRIPT_DIR doesn't have a value" && return 1
    [[ ! -d $GEO_CLI_SCRIPT_DIR ]] && mkdir -p $GEO_CLI_SCRIPT_DIR
    [[ -z $EDITOR ]] && EDITOR=nano

    local command="$1"
    local script_name=$(_geo_make_alphanumeric $2)
    local script_path="$GEO_CLI_SCRIPT_DIR/$script_name".sql

    check_for_script() {
        if [[ -f $script_path ]]; then
            log::success 'Saved'
        else
            log::warn "Script '$script_name' wasn't found in script directory, did you save it before closing the text editor?"
        fi
    }

    case "$command" in
        add )
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
        edit )
            if [[ ! -f $script_path ]]; then
                if ! prompt_continue "Script '$script_name' doesn't exist. Would you like to create it? (Y|n): "; then
                    return
                fi
            fi
            $EDITOR $script_path
            check_for_script
            ;;
        ls )
            ls $GEO_CLI_SCRIPT_DIR | tr ' ' '\n'
            ;;
        rm )
            rm $GEO_CLI_SCRIPT_DIR/$2
            ;;
        *)
            log::Error "Unknown subcommand '$command'"
            ;;
    esac
}

_geo_make_alphanumeric() {
    # Replace any non-alphanumeric characters with '_', then replace 2 or more occurrences with a singe '_'.
    # Ex: some>bad()name -> some_bad__name -> some_bad_name
    echo "$@" | sed 's/[^0-9a-zA-Z_.-]/_/g' | sed -e 's/_\{2,\}/_/g'
}

_geo_db_ls_images() {
    log::info Images
    docker image ls geo_cli* #--format 'table {{.Names}}\t{{.ID}}\t{{.Image}}'
}
_geo_db_ls_containers() {
    log::info 'DB Containers'
    # docker container ls -a -f name=geo_cli
    if [[ $1 = -a ]]; then
        docker container ls -a -f name=geo_cli
        return
    fi

    local output=$(docker container ls -a -f name=geo_cli --format '{{.Names}}\t{{.ID}}\t{{.Names}}\t{{.CreatedAt}}')

    # local filtered=$(echo "$output" | awk 'printf "%-24s %-16s %-24s\n",$1,$2,$3 } ')
    local filtered=$(echo "$output" | awk '{ gsub("geo_cli_db_postgres_","",$1);  printf "%-20s %-16s %-28s\n",$1,$2,$3 } ')
    # echo "$output" | awk { gsub($3"_","",$1);  printf "%-24s %-16s %-24s\n",$3,$2,$1 } '
    # filtered=`echo $"$output" | awk 'BEGIN { format="%-24s %-24s %-24s\n"; ; printf format, "Name","Container ID","Image" } { gsub($3"_","",$1);  printf " %-24s %-24s %-24s\n",$1,$2,$3 } '`

    local names=$(docker container ls -a -f name=geo_cli --format '{{.Names}}')
    local longest_field_length=$(awk '{ print length }' <<<"$names" | sort -n | tail -1)
    local container_name_field_length=$((longest_field_length + 4))
    local name_field_length=$((${#longest_field_length} - ${#GEO_DB_PREFIX} + 4))
    ((name_field_length < 16)) && name_field_length=16

    local line_format="%-${name_field_length}s %-16s %-${container_name_field_length}s %-16s\n"
    local header=$(printf "$line_format" "geo-cli Name" "Container ID" "Container Name" "Created")
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

        created_date="${line_array[3]}"
        # Trim off timezone.
        created_date="${created_date:0:19}"

        days_since_created=$(_geo_datediff "$now" "$created_date")
        new_line="$(echo -e "${line_array[0]}\t${line_array[1]}\t${line_array[2]}\t$days_since")"
        # Remove the geo db prefix from the container name to get the geo-cli name for the db.
        line_array[0]="${line_array[0]#${GEO_DB_PREFIX}_}"
        printf "$line_format" "${line_array[0]}" "${line_array[1]}" "${line_array[2]}" "$days_since_created"
    done <<< "$output"
}

_geo_db_ls_volumes() {
    log::info Volumes
    docker volume ls -f name=geo_cli
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
        minutes=$(( diff_seconds / minute ))
        hours=$(( diff_seconds / hour ))
        days=$(( diff_seconds / day ))
        weeks=$(( diff_seconds / (day * 7) ))
        months=$(( diff_seconds / (day * 30) ))
        years=$(( diff_seconds / (day * 365) ))

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

_geo_container_name() {
    local name=$(_geo_make_alphanumeric $1)
    echo "${IMAGE}_${name}"
}

_geo_get_container_id() {
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

_geo_get_container_name_from_id() {
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
    local id=
    local variable=
    # Check if the caller supplied a variable name that they want the container id to be stored in.
    [[ $1 == -v ]] && local -n variable="$2" && shift 2 && variable=
    local container_name=$1

    [[ ! $container_name =~ geo_cli_db_postgres_ ]] && container_name="geo_cli_db_postgres_${container_name}"

    _geo_get_container_id -v id "$container_name" && variable="$id"
}

_geo_get_running_container_id() {
    local name=$1
    [[ -z $name ]] && name="$IMAGE*"
    echo $(docker ps --filter name="$name" --filter status=running -aq)
}

_geo_is_container_running() {
    local name=$(_geo_get_running_container_name)
    [[ -n $name ]]
}

_geo_get_running_container_name() {
    # local name=$1
    local name=
    [[ -z $name ]] && name="$IMAGE*"

    local container_name=$(docker ps --filter name="$name" --filter status=running -a --format="{{ .Names }}")
    if [[ $1 == -r ]]; then
        container_name=${container_name#geo_cli_db_postgres_}
        container_name=${container_name#geo_cli_db_postgres11_}
    fi
    echo $container_name
}

_geo_check_docker_permissions() {
    local ps_error_output=$(docker ps 2>&1 | grep docker.sock)
    local docker_group=$(cat /etc/group | grep 'docker:')
    if [[ -n $ps_error_output ]]; then
        debug "$ps_error_output"
        if ! [[ -z $docker_group || ! $docker_group =~ "$USER" ]]; then
            log::warn 'You ARE a member of the docker group, but are not able to use docker without sudo.'
            log::info 'Fix: You must completely log out and then back in again to resolve the issue.'
            return 1
        fi
        log::warn 'You are NOT a member of the docker group. This is required to be able to use the "docker" command without sudo.'
        log::Error "The current user does not have permission to use the docker command."
        log::info "Fix: Add the current user to the docker group."
        if prompt_continue 'Would you like to fix this now? (Y|n): '; then
            [[ -z $docker_group ]] && sudo groupadd docker
            sudo usermod -aG docker $USER || { log::Error "Failed to add '$USER' to the docker group"; return 1; }
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

function geo_db_init() {
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
            s ) silent=true ;;
            y ) accept_defaults=true ;;
            n ) no_prompt=true ;;
            b ) 
                no_build=true
                opts+=b
                ;;
            d ) db_name="$OPTARG" ;;
            : )
                log::Error "Option '${opt}' expects an argument."
                return 1
                ;;
            \? )
                log::Error "Invalid option: ${opt}"
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
        sleep 1;
        if (( wait_count++ > 10 )); then
            echo
            log::Error "Timeout. No database container running after waiting 10 seconds."
            return 1
        fi
    done
    echo

    local container_id=$(_geo_get_running_container_id)
    if [[ -z $container_id ]]; then
        log::Error 'No geo-cli containers are running to initialize.'
        log::info "Run $(log::txt_underline 'geo db ls') to view available containers and $(log::txt_underline 'geo db start <name>') to start one."
        return 1
    fi

    # log::status 'A db can be initialized with geotabdemo or with a custom db name (just creates an empty database with provided name).'
    # if ! [ $accept_defaults ] && ! prompt_continue 'Would you like to initialize the db with geotabdemo? (Y|n): '; then
    #     stored_name=`geo_get PREV_DB_NAME`
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
    #     geo_set PREV_DB_NAME "$db_name"
    # fi

    if [[ -z $db_name ]]; then
        log::Error 'Db name cannot be empty'
        return 1
    fi

    log::status -b "Initializing db $db_name\n"
    local user=$(geo_get DB_USER)
    local password=$(geo_get DB_PASSWORD)
    local sql_user=$(geo_get SQL_USER)
    local sql_password=$(geo_get SQL_PASSWORD)
    local answer=''

    # Assign default values for sql user/passord.
    [[ -z $user ]] && user="$USER@geotab.com"
    [[ -z $password ]] && password=passwordpassword
    [[ -z $sql_user ]] && sql_user=geotabuser
    [[ -z $sql_password ]] && sql_password=vircom43
    
    # Make sure there's a running db container to initialize.
    local container_id=$(_geo_get_running_container_id)
    if [[ -z $container_id ]]; then
        log::Error "There isn't a running geo-cli db container to initialize with geotabdemo."
        log::info 'Start one of the following db containers and try again:'
        _geo_db_ls_containers
        return 1
    fi

    get_user() {
        prompt_for_info_n -v user "Enter MyGeotab admin username (your email): "
        geo_set DB_USER "$user"
    }

    get_password() {
        prompt_for_info_n -v password "Enter MyGeotab admin password: "
        geo_set DB_PASSWORD "$password"
    }

    get_sql_user() {
        prompt_for_info_n -v sql_user "Enter db admin username: "
        geo_set SQL_USER "$sql_user"
    }

    get_sql_password() {
        prompt_for_info_n -v sql_password "Enter db admin password: "
        geo_set SQL_PASSWORD "$sql_password"
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
        log::detail "Using the default password $(txt_underline passwordpassword) is easiest, but you can change it if you like."
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
    # _geo_get_checkmate_dll_path $accept_defaults
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

    local dev_repo=$(geo_get DEV_REPO_DIR)
    local myg_core_proj="$dev_repo/Checkmate/MyGeotab.Core.csproj"
    
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
        log::success "$db_name initialized"
        echo
        _geo_copy_pgAdmin_server_config
        
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
        log::info "    Maintenance database: geotabdemo"
        log::info "    Username: $sql_user"
        log::info "    Password: $sql_password"
        echo
        log::info -b "Use geotabdemo"
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

geo_db_rm() {
    if [[ $1 =~ ^-*a(ll)?$ ]]; then
        shift
        local search_str="$1"
        names="$(docker container ls -a -f name=geo_cli --format "{{.Names}}")"
        [[ -n $search_str ]] && names="$(grep -F "$search_str" <<<"$names")"
        [[ -z $names ]] && log::warn "No containers to remove." && return 1
        log::detail "$names"
        local count=$(wc -l <<<"$names")
        local prompt_msg="Do you want to remove all ($count) containers? (Y|n): "
        (( count == 1 )) && prompt_msg="Do you want to remove this container? (Y|n): "
        prompt_continue "$prompt_msg" || return

        # Get list of contianer names
        # ids=`docker container ls -a -f name=geo_cli --format "{{.ID}}"`
        # echo "$ids" | xargs docker container rm
        local fail_count=0
        for name in $names; do
            # Remove image prefix from container name; leaving just the version/identier (e.g. geo_cli_db_postgres_10.0 => 10.0).
            geo_db_rm -n "$name" || ((fail_count++))

            # geo_db_rm "${name#${IMAGE}_}"
            # echo "${name#${IMAGE}_}"
        done
        local num_dbs=$(echo "$names" | wc -l)
        num_dbs=$((num_dbs - fail_count))
        log::success "Removed $num_dbs db(s)"
        [[ fail_count -gt 0 ]] && log::error "Failed to remove $fail_count dbs"
        return
    fi

    local container_name
    local db_name="$(_geo_make_alphanumeric $1)"
    # If the -n option is present, the full container name is passed in as an argument (e.g. geo_cli_db_postgres11_2101). Otherwise, the db name is passed in (e.g., 2101)
    if [[ $1 == -n ]]; then
        container_name="$2"
        db_name="${2#${IMAGE}_}"
        shift
    else
        container_name=$(_geo_container_name "$db_name")
    fi

    local container_id=$(_geo_get_running_container_id "$container_name")

    if [[ -n "$container_id" ]]; then
        log::status 'Trying to stop container...'
        docker stop $container_id >/dev/null && log::success "Container stopped"
    fi

    # Remove multiple containers if more than one container name was passed in (i.e., geo db rm 8.0 9.0).
    if [[ -n $1 && -n $2 ]]; then
        log::debug 'Removing multiple containers'
        while [[ -n $1 ]]; do
            geo_db_rm $1
            shift
        done
        return
    fi

    # container_name=bad

    if docker container rm $container_name >/dev/null; then
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

_geo_get_checkmate_dll_path() {
    local dev_repo=$(geo_get DEV_REPO_DIR)
    local output_dir="${dev_repo}/Checkmate/bin/Debug"
    local accept_defaults=$1
    # Get full path of CheckmateServer.dll files, sorted from newest to oldest.
    local files="$(find $output_dir -maxdepth 2 -name "CheckmateServer.dll" -print0 | xargs -r -0 ls -1 -t | tr '\n' ':')"
    local ifs=$IFS
    IFS=:
    read -r -a paths <<<"$files"
    IFS=$ifs
    local number_of_paths=${#paths[@]}
    [[ $number_of_paths = 0 ]] && log::Error "No output directories could be found in ${output_dir}. These folders should exist and contain CheckmateServer.dll. Build MyGeotab and try again."

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
    local dev_repo=$(geo_get DEV_REPO_DIR)

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
        echo $dev_repo
    }

    if ! is_valid_repo_dir "$dev_repo" && [[ "$dev_repo" != -- ]]; then
        log::status "Searching for possible repo locations..."
        _geo_init_repo_find_myg_repo -v dev_repo
    fi
    
    # Ask repeatedly for the dev repo dir until a valid one is provided.
    while ! is_valid_repo_dir "$dev_repo" && [[ "$dev_repo" != -- ]]; do
        get_dev_repo_dir
    done

    [[ "$dev_repo" == -- ]] && return

    log::success "Checkmate directory found"
    geo_set DEV_REPO_DIR "$dev_repo"
}

populate_prev_value_if_requested() {
    local key="$1"
    local -n value_ref="$2"
    [[ -z $value_ref ]] && return
    if [[ $value_ref == - ]]; then
        local saved_value=$(geo_get $key)
        [[ -z $saved_value ]] && log::Error "There is no value saved for key '$key'" && return 1
        value_ref="$saved_value"
        log::data "Using saved value: $(log::detail $value_ref)"
        return
    fi
    geo_set $key "$value_ref"
}

#######################################################################################################################
COMMANDS+=('ar')
geo_ar_doc() {
    doc_cmd 'ar'
    doc_cmd_desc 'Helpers for working with access requests.'
    doc_cmd_sub_cmds_title
        doc_cmd_sub_cmd 'create'
            doc_cmd_sub_cmd_desc 'Opens up the My Access Request page on the MyAdmin website in Chrome.'
        doc_cmd_sub_cmd 'tunnel [gcloud start-iap-tunnel cmd]'
            doc_cmd_sub_cmd_desc "Starts the IAP tunnel (using the gcloud start-iap-tunnel command copied from MyAdmin after opening
                            an access request) and then connects to the server over SSH. The port is saved and used when you SSH to the server using $(log::green 'geo ar ssh').
                            This command will be saved and re-used next time you call the command without any arguments (i.e. $(log::green geo ar tunnel))"
            doc_cmd_sub_options_title
            doc_cmd_sub_option '-s'
            doc_cmd_sub_option_desc "Only start the IAP tunnel without SSHing into it."
            doc_cmd_sub_option '-l'
            doc_cmd_sub_option_desc "List and choose from previous IAP tunnel commands."
            doc_cmd_sub_option '-p <port>'
            doc_cmd_sub_option_desc "Specifies the port to open the IAP tunnel on. This port must be greater than 1024 and not be in use."
            doc_cmd_sub_option '-L'
            doc_cmd_sub_option_desc "Bind local port 5433 to 5432 on remote host (through IAP tunnel). You can connect to the remote Postgres database 
                    using this port (5433) in pgAdmin. Note: you can also open up an ssh session to this server by opening another terminal and running
                     $(txt_underline geo ar ssh)"
            # doc_cmd_sub_option_desc "Starts an SSH session to the server immediately after opening up the IAP tunnel."
        doc_cmd_sub_cmd 'ssh'
            doc_cmd_sub_cmd_desc "SSH into a server through the IAP tunnel started with $(log::green 'geo ar ssh')."
            doc_cmd_sub_options_title
            doc_cmd_sub_option '-p <port>'
            doc_cmd_sub_option_desc "The port to use when connecting to the server. This value is optional since the port that the IAP tunnel was opened on using $(log::green 'geo ar ssh') is used as the default value"
            doc_cmd_sub_option '-u <user>'
            doc_cmd_sub_option_desc "The user to use when connecting to the server. This value is optional since the username stored in \$USER is used as the default value. The value supplied here will be stored and reused next time you call the command"
            doc_cmd_sub_option '-L'
            doc_cmd_sub_option_desc "Bind local port 5433 to 5432 on remote host (through IAP tunnel). You can connect to the remote Postgres database 
                    using this port (5433) in pgAdmin. Note: you can also open up an ssh session to this server by opening another terminal and running
                     $(txt_underline geo ar ssh)"
    doc_cmd_examples_title
        doc_cmd_example 'geo ar tunnel -s gcloud compute start-iap-tunnel gceseropst4-20220109062647 22 --project=geotab-serverops --zone=projects/709472407379/zones/northamerica-northeast1-b'
        doc_cmd_example 'geo ar ssh'
        doc_cmd_example 'geo ar ssh -p 12345'
        doc_cmd_example 'geo ar ssh -u dawsonmyers'
        doc_cmd_example 'geo ar ssh -u dawsonmyers -p 12345'
}
geo_ar() {
    # ssh -L 127.0.0.1:5433:localhost:5432 -N <username>@127.0.0.1 -p <port from IAP>
    show_iap_password_prompt_message() {
        log::status -bu "Binding local port 5433 to 5432 on remote host (through IAP tunnel)"
        echo
        log::info "$(txt_underline geo-cli) can configure pgAdmin to connect to Postgres over the IAP tunnel."
        log::info "Enter your Access Request password below to update the password file for the $(txt_underline MyGeotab Over IAP) server in pgAdmin, $(txt_underline OR) leave it blank if you already have a server in pgAdmin and plan to update its password manually."
        echo
        log::info "The $(txt_underline MyGeotab Over IAP) server needs to be imported $(txt_underline once) into pgAdmin."
        log::info "The instructions will be shown after you enter your password."
        echo
        log::info "After the server is added, you only need to paste in your password below to have its passfile updated. Make sure to refresh the server in pgAdmin after the port is bound."
        echo
        hint='* Leave the password empty if you will be manually updating an existing server in pgAdmin.'
        log::hint "$(log::fmt_text_and_indent_after_first_line "$hint" 0 2)"
        hint="* Enter '-' in any of the following inputs to re-use the last value used."
        log::hint "$(log::fmt_text_and_indent_after_first_line "$hint" 0 2)"

        # log::fmt_text_and_indent_after_first_line "$hint" 0 2
        # log::detail "Enter '-' in any of the following inputs to re-use the last value used."
        iap_password_prompt="Access Request password:\n> "
        iap_db_prompt="Database:\n> "

        prompt_for_info_n -v iap_password "$iap_password_prompt"
        while ! populate_prev_value_if_requested AR_PASSWORD iap_password; do
            prompt_for_info_n -v iap_password "$iap_password_prompt"
        done
        # prompt_for_info_n -v iap_db "$iap_db_prompt"
        # populate_prev_value_if_requested AR_DATABASE iap_db
        # while ! populate_prev_value_if_requested AR_DATABASE iap_db; do
        #     prompt_for_info_n -v iap_db "$iap_db_prompt"
        # done
        
        iap_skip_password=true
        reuse_msg_shown=true
        if [[ -n $iap_password ]]; then
            _geo_copy_pgAdmin_server_config --iap "$iap_password" "$user"
            # _geo_copy_pgAdmin_server_config --iap "$iap_password" "$iap_db" "$user"
        fi
    }
    local iap_password=
    local iap_db=
    local iap_skip_password=false
    local reuse_msg_shown=false

    case "$1" in
        create )
            google-chrome https://myadmin.geotab.com/accessrequest/requests
            ;;
        tunnel)
            # Catch EXIT so that it doesn't close the terminal (since geo runs as a function, not in it's own subshell)
            trap '' EXIT
            ( # Run in subshell to catch EXIT signals
                shift
                local start_ssh='true'
                local prompt_for_cmd='false'
                local list_previous_cmds='false'
                local bind_myadmin_port='false'
                local port=
                local user=
                
                
                [[ $@ =~ --prompt ]] && prompt_for_cmd=true && shift

                # while [[ $1 =~ ^- ]]; do
                #     case "$1" in
                #         -s ) start_ssh= ;;
                #         --prompt ) prompt_for_cmd=true ;;
                #         -l ) list_previous_cmds=true ;;
                #         -p ) port=$2 && shift ;;
                #         -L ) bind_myadmin_port=true ;;
                #         * ) log::Error "Unknown option '$1'" && return 1 ;;
                #     esac
                #     shift
                # done

                # TODO Add support for user argument.
                local OPTIND
                while getopts "slLp:u:" opt; do
                    case "${opt}" in
                        s ) start_ssh=  ;;
                        l ) list_previous_cmds=true ;;
                        L ) bind_myadmin_port=true ;;
                        p ) port="$OPTARG" ;;
                        u ) user="$OPTARG" ;;
                        : )
                            log::Error "Option '${opt}' expects an argument."
                            return 1
                            ;;
                        \? )
                            log::Error "Invalid option: ${opt}"
                            return 1
                            ;;
                    esac
                done
                shift $((OPTIND - 1))

                if $bind_myadmin_port; then
                    show_iap_password_prompt_message
                    # echo
                    # log::hint "Leave the password and database empty if you will be manually updating an existing server in pgAdmin."
                    # log::detail "Enter - in any of the following inputs to re-use the last value used."
                    # local iap_password_prompt="Access Request password:\n> "
                    # local iap_db_prompt="Database:\n> "

                    # prompt_for_info_n -v iap_password "$iap_password_prompt"
                    # prompt_for_info_n -v iap_db "$iap_db_prompt"
                    # populate_prev_value_if_requested AR_PASSWORD iap_password
                    # populate_prev_value_if_requested AR_DATABASE iap_db

                    # iap_skip_password=true
                    # if [[ -n $iap_password ]]; then
                    #     _geo_copy_pgAdmin_server_config --iap "$iap_password" "$iap_db" "$user"
                    # fi
                fi

                local gcloud_cmd="$*"
                local expected_cmd_start='gcloud compute start-iap-tunnel'
                local prompt_txt='Enter the gcloud IAP command that was copied from your MyAdmin access request:'
                if [[ $prompt_for_cmd == true ]]; then
                    ! $reuse_msg_shown && log::detail "Enter '-' below to re-use the last gcloud command used."
                    prompt_for_info -v gcloud_cmd "$prompt_txt"
                    populate_prev_value_if_requested AR_IAP_CMD gcloud_cmd
                    # gcloud_cmd="$prompt_return"
                fi

                if [[ $list_previous_cmds == true ]]; then
                    local prev_commands=$(_geo_ar_get_cmd_tags | tr '\n' ' ')
                    # log::debug "$prev_commands"
                    if [[ -n $prev_commands ]]; then
                        log::status -bi 'Enter the number for the gcloud IAP command you want to use:'
                        select tag in $prev_commands; do
                            [[ -z $tag ]] && log::warn "Invalid command number" && continue
                            gcloud_cmd=$(_geo_ar_get_cmd_from_tag $tag)
                            # log::debug "gcloud_cmd: $gcloud_cmd"
                            # log::debug "tag: $tag"
                            break
                        done
                    else
                        log::warn "'-l' option supplied, but there arn't any previous comands stored to choose from."
                    fi
                fi

                # log::debug $gcloud_cmd
                [[ -z $gcloud_cmd ]] && gcloud_cmd="$(geo_get AR_IAP_CMD)"
                [[ -z $gcloud_cmd ]] && log::Error 'The gcloud compute start-iap-tunnel command (copied from MyAdmin for your access request) is required.' && return 1

                
                while [[ ! $gcloud_cmd =~ ^$expected_cmd_start ]]; do
                    ! $reuse_msg_shown && log::warn -b "The command must start with 'gcloud compute start-iap-tunnel'" && reuse_msg_shown=true
                    prompt_for_info -v gcloud_cmd "$prompt_txt"
                    populate_prev_value_if_requested AR_IAP_CMD gcloud_cmd
                    # gcloud_cmd="$prompt_return"
                done

                geo_set AR_IAP_CMD "$gcloud_cmd"
                _geo_ar_push_cmd "$gcloud_cmd"
                local open_port=
                if [[ -n $port ]]; then
                    local port_open_check_python_code='import socket; s=socket.socket(); s.bind(("", '$port')); s.close()'
                    # 2>&1 redirects the stderr to stdout so that it can be stored in the variable.
                    local port_check_result=$(python3 -c "$port_open_check_python_code" 2>&1 )
                    if [[ $port_check_result =~ 'Address already in use' ]]; then
                        log::Error "Port $port is already in use."
                        return 1
                    fi
                    open_port=$port
                fi
                
                local get_open_port_python_code='import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()'
                [[ -z $open_port ]] && which python > /dev/null && open_port=$(python -c "$get_open_port_python_code")
                # Try using python3 if open port wasn't found.
                [[ -z $open_port ]] && open_port=$(python3 -c "$get_open_port_python_code")
                [[ -z $open_port ]] && log::Error 'Open port could not be found' && return 1

                echo
                log::status -bu 'Opening IAP tunnel'
                if [[ -n $open_port ]]; then
                    local port_arg='--local-host-port=localhost:'$open_port

                    geo_set AR_PORT "$open_port"
                    log::info "Using port: '$open_port' to open IAP tunnel"
                    log::info "Note: the port is saved and will be used when you call '$(log::txt_italic geo ar ssh)'"
                    echo
                    log::debug $gcloud_cmd $port_arg
                    sleep 1
                    echo
                fi

                local geo_config_dir="$(geo_get CONFIG_DIR)"
                local geo_tmp_ar_dir="$geo_config_dir/tmp/ar"
                [[ ! -d $geo_tmp_ar_dir ]] && mkdir -p "$geo_tmp_ar_dir"
                local ar_request_name="${gcloud_cmd#gcloud compute start-iap-tunnel }"
                ar_request_name="${ar_request_name% 22 --project*}"
                local regex='([[:alnum:]]+-[[:digit:]]+)'
                local connection_file=""
                [[ $gcloud_cmd =~ $regex ]] && ar_request_name="${BASH_REMATCH[1]}"
                [[ -n $open_port ]] && connection_file="$geo_tmp_ar_dir/${ar_request_name}__${open_port}"

                if [[ $start_ssh ]]; then
                    cleanup() {
                        echo
                        # log::status 'Closing IAP tunnel'
                        kill %1
                        # Remove the temporary output file if it exists.
                        [[ -f $tmp_output_file ]] && rm $tmp_output_file
                        exit
                    }
                    # Catch signals and run cleanup function to make sure the IAP tunnel is closed.
                    trap cleanup INT TERM QUIT EXIT

                    # Find the port by opening the IAP tunnel without specifying the port, then get the port number from the output of the gcloud command.
                    if [[ -z $open_port ]]; then
                        log::status "Finding open port..."
                        local tmp_output_file="/tmp/geo-ar-tunnel-$RANDOM.txt"
                        $gcloud_cmd &> >(tee -a $tmp_output_file) &
                        local attapts=0

                        # Write the output of the gcloud command to file then periodically scan it for the port number.
                        while (( ++attempts < 6 )) && [[ -z $open_port ]]; do
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
                        geo_set AR_PORT "$open_port"
                        # log::status -bu '\nOpening IAP tunnel'
                        log::info "Using port: '$open_port' to open IAP tunnel"
                        log::info "Note: the port is saved and will be used when you call '$(log::txt_italic geo ar ssh)'"
                        echo
                        log::debug $gcloud_cmd $port_arg
                        sleep 1
                        echo
                    else
                        # log::status -bu '\nOpening IAP tunnel'
                        # Start up IAP tunnel in the background.
                        if [[ -n $connection_file ]]; then
                            # log::debug 'running in loc'
                            run_command_with_lock_file "$connection_file" "$open_port" $gcloud_cmd $port_arg || { log::Error "failed to start IAP tunnel"; return 1; } &
                        else
                            # log::debug 'NOT running in loc'
                            $gcloud_cmd $port_arg &
                        fi
                    fi

                    # Wait for the tunnel to start.
                    log::status 'Waiting for tunnel to open before stating SSH session...'
                    echo
                    sleep 5
                    
                    local opts='-n'
                    # log::debug "tunnel"

                    # log::debug "iap_skip_password: $iap_skip_password"
                    # log::debug "bind_myadmin_port: $bind_myadmin_port"  
                    if $bind_myadmin_port; then
                        opts+='L'
                        $iap_skip_password && opts+='s'
                    fi

                    local username_option=
                    [[ -n $user ]] && username_option="-u $user"
                    # Continuously ask the user to re-open the ssh session (until ctrl + C is pressed, killing the tunnel).
                    # This allows users to easily re-connect to the server after the session times out.
                    # The -n option tells geo ar ssh not to store the port; the -p option specifies the ssh port.
                    geo_ar ssh $opts -p $open_port $username_option

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
            shift
            local user=$(geo_get AR_USER)
            [[ -z $user ]] && user="$USER"
            local port=$(geo_get AR_PORT)
            local option_count=0
            local save='true'
            local loop=true
            local bind_myadmin_port=false
            local iap_skip_password=false

            # while [[ ${1:0:1} == - ]]; do
            #     # log::debug "option $1"
            #     # Don't save port/user if -n (no save) option supplied. This option is used in geo ar tunnel so that re-opening
            #     # an SSH session doesn't overwrite the most recent port (from the newest IAP tunnel, which may be different from this one).
            #     [[ $1 == '-n' ]] && save= && shift
            #     # The -r option will cause the ssh tunnel to run ('r' for run) once and then return without looping.
            #     [[ $1 == '-r' ]] && loop=false && shift
            #     [[ $1 == '-p' ]] && port=$2 && shift 2 && ((option_count++))
            #     [[ $1 == '-u' ]] && user=$2 && shift 2 && ((option_count++))
            # done

            local OPTIND
            while getopts "nrLsp:u:" opt; do
                case "${opt}" in
                    # Don't save port/user if -n (no save) option supplied. This option is used in geo ar tunnel so that re-opening
                    # an SSH session doesn't overwrite the most recent port (from the newest IAP tunnel, which may be different from this one).
                    n ) save=  ;;
                    # The -r option will cause the ssh tunnel to run ('r' for run) once and then return without looping.
                    r ) loop=false ;;
                    p ) port="$OPTARG" ;;
                    u ) user="$OPTARG" ;;
                    L ) bind_myadmin_port=true ;;
                    s ) iap_skip_password=true ;;
                    : )
                        log::Error "Option '${opt}' expects an argument."
                        return 1
                        ;;
                    \? )
                        log::Error "Invalid option: ${opt}"
                        return 1
                        ;;
                esac
            done
            shift $((OPTIND - 1))

            [[ -z $port ]] && log::Error "No port found. Add a port with the -p <port> option." && return 1
            # log::debug "iap_skip_password: $iap_skip_password"
            # log::debug "bind_myadmin_port: $bind_myadmin_port"
            if $bind_myadmin_port && ! $iap_skip_password; then
                show_iap_password_prompt_message
                
                # log::hint "Leave the password and database empty if you will be manually updating an existing server in pgAdmin."
                # local iap_password_prompt="Access Request password:\n> "
                # local iap_db_prompt="Database:\n> "
                # prompt_for_info_n -v iap_password "$iap_password_prompt"
                # prompt_for_info_n -v iap_db "$iap_db_prompt"
                # if [[ -z $iap_password ]]; then
                #     iap_skip_password=true
                # else
                #     _geo_copy_pgAdmin_server_config --iap "$iap_password" "$iap_db" "$user"
                # fi
            fi

            echo
            log::status -bu 'Opening SSH session'
            log::info "Using user '$user' and port '$port' to open SSH session."

            [[ $option_count == 0 ]] && log::info "Note: The -u <user> or the -p <port> options can be used to supply different values."
            echo

            if [[ $save == true ]]; then
                geo_set AR_USER "$user"
                geo_set AR_PORT "$port"
            fi

            local bind_cmd="ssh -L 127.0.0.1:5433:localhost:5432 -N $user@127.0.0.1 -p $port"
            local cmd="ssh $user@localhost -p $port"

            if $bind_myadmin_port; then
                # log::status -b "Binding local port 5433 to 5432 on remote host (through IAP tunnel)"
                # log::info "geo-cli can configure pgAdmin to connect to Postgres over the IAP tunnel."
                # log::info "Enter your Access Request password below to update the password file for the MyGeotab Over IAP server in pgAdmin, or leave it blank if you already have a server in pgAdmin and plan to update its password manually."
                # log::hint "The MyGeotab Over IAP server needs to be imported once into pgAdmin. The instructions will be shown after you enter your password."
                # log::hint "After it has been added, you only need to paste in your password below to have its passfile updated."
                
                # local iap_password_prompt="Access Request password:\n> "
                # prompt_for_info_n -v iap_password "$iap_password_prompt"
                
                # _geo_copy_pgAdmin_server_config --iap "$iap_password" "$user"
        
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
                log::info "    Port: 5433"
                log::info "    Maintenance database: postgres"
                log::info "    Username: $user"
                log::info "    Password: the one you got from MyAdmin when you created the Access Request"              

                # log::info "    Host: localhost"
                # log::info "    Port: 5433"
                # log::info "    username: $user"
                # log::info "    Password: <the password you got from MyAdmin when you created the Access Request>"
                log::hint "\nYou can also open another terminal and start an ssh session with ther server using $(txt_underline geo ar ssh)"
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
                # log::status 'SSH closed. Listening to IAP tunnel again. Open a new terminal and run "geo ar ssh" to reconnect to this tunnel.'
                read response
                log::status -bu 'Reopening SSH session'
                echo
                sleep 1
            done
            ;;
        *)
            log::Error "Unknown subcommand '$1'"
            ;;
    esac
}

run_command_with_lock_file() {
    local lock_file="$1"
    local lock_file_content="$2"
    local cmd="${@:3}"
    touch "$lock_file"

    trap '' EXIT
    (
        cleanup() {
            flock -u "$FD"
            [[ -f $lock_file ]] && { rm "$lock_file" || log::Error "Failed to remove lock file"; }
            # log::warn "run_command_with_lock_file: cleaned up successfully after interrupt"
            exit
        }

        trap cleanup SIGINT SIGTERM ERR EXIT
        # Create file descriptor for the lock file.
        exec {FD}<>$lock_file
        echo "$lock_file_content" > "$lock_file"
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

# Save the previous 5 gcloud commands as a single value in the config file, delimited by the '@' character.
_geo_ar_push_cmd() {
    local cmd="$1"
    [[ -z $cmd ]] && return 1
    local prev_commands="$(geo_get AR_IAP_CMDS)"

    if [[ -z $prev_commands ]]; then
        # log::debug "_geo_ar_push_cmd[$LINENO]: cmds was empty"
        geo_set AR_IAP_CMDS "$cmd"
        return
    fi
    # Remove duplicates if cmd is already stored.
    prev_commands="${prev_commands//$cmd/}"
    # Remove any delimiters left over from removed commands.
    # The patterns remove lead and trailing @, as well as replaces 2 or more @ with a single one (3 patterns total).
    prev_commands=$(echo $prev_commands | sed -r 's/^@//; s/@$//; s/@{2,}/@/g')

    if [[ -z $prev_commands ]]; then
        # Can happen when there is only one item stored and the new item being added is a duplicate.
        # log::Error "_geo_ar_push_cmd[$LINENO]: cmds was empty"
        return
    fi
    # Add the new command to the beginning, delimiting it with the '@' character.
    prev_commands="$cmd@$prev_commands"
    # Get the count of how many commands there are.
    local count=$(echo $prev_commands | awk -F '@' '{ print NF }')
#    log::debug $count
    if (( count > 5 )); then
        # Remove the oldest command, keeping only 5.
        prev_commands=$(echo $prev_commands | awk -F '@' '{ print $1"@"$2"@"$3"@"$4"@"$5 }')
    fi
#    log::debug geo_set AR_IAP_CMDS "_geo_ar_push_cmd: setting cmds to: $prev_commands"
    geo_set AR_IAP_CMDS "$prev_commands"
}

_geo_ar_get_cmd_tags() {
    geo get AR_IAP_CMDS | tr '@' '\n' | awk '{ print $4 }'
}

_geo_ar_get_cmd_from_tag() {
    [[ -z $1 ]] && return
    geo get AR_IAP_CMDS | tr '@' '\n' | grep "$1"
}

_geo_ar_get_cmd() {
    local cmd_number="$1"
    [[ -z $cmd_number || $cmd_number -gt 5 || $cmd_number -lt 0 ]] && log::Error "Invalid command number. Expected a value between 0 and 5." && return 1

    local cmds=$(geo_get AR_IAP_CMDS)
    if [[ -z $cmds ]]; then
        return
    fi
    local awk_cmd='{ print $'$cmd_number' }'
    echo $(echo $cmds | awk -F '@' "$awk_cmd")
}

_geo_ar_get_cmd_count() {
    local cmds=$(geo_get AR_IAP_CMDS)
    # Get the count of how many commands there are.
    local count=$(echo $cmds | awk -F '@' '{ print NF }')
    echo $count
}

# pa() {
#     echo "$@"
#     # while getopts "p:u:" options ; do
#     #     echo "$optname + $options + $OPTARG + $1"
#     #     case "${options}" in
#     #         p) echo "p: $OPTARG" ;;
#     #         u) echo "u: $OPTARG" ;;
#     #         # \?)
#     #         #     log::Error "Invalid option: -$OPTARG"
#     #         #     return 1
#     #         #     ;;
#     #         :) # If expected argument omitted:
#     #             echo "Error: -${OPTARG} requires an argument."
#     #             ;;
#     #         *) log::warn "Unknown argument " ;;
#     #     esac
#     # done
# while getopts ":pu" opt; do
#   case ${opt} in
#     u ) echo "process option h"
#       ;;
#     p ) echo  "process option t"
#       ;;
#     \? ) echo "Usage: cmd [-h] [-t]"
#       ;;
#   esac
# done
# }
#  pa -p 234 -u dawson

#######################################################################################################################
COMMANDS+=('stop')
geo_stop_doc() {
    doc_cmd 'stop'
    doc_cmd_desc 'Stops all geo-cli containers.'
    doc_cmd_examples_title
    doc_cmd_example 'geo stop'
}
geo_stop() {
    geo_db stop "$1"
}

geo_is_valid_repo_dir() {
    test -d "${1}/Checkmate"
}

#######################################################################################################################
COMMANDS+=('init')
geo_init_doc() {
    doc_cmd 'init'
    doc_cmd_desc 'Initialize repo directory.'

    doc_cmd_sub_cmds_title
        doc_cmd_sub_cmd 'repo'
            doc_cmd_sub_cmd_desc 'Init Development repo directory using the current directory.'
        doc_cmd_sub_cmd 'npm'
            doc_cmd_sub_cmd_desc "Runs 'npm install' in both the wwwroot and drive CheckmateServer directories. This is quick way to fix the npm dependencies after Switching to a different MYG release branch."
        doc_cmd_sub_cmd 'pat'
            doc_cmd_sub_cmd_desc "Sets up the GitLab Personal Access Token environment variables."
            doc_cmd_sub_options_title
                doc_cmd_sub_option '-r'
                    doc_cmd_sub_option_desc 'Removes the PAT environment variables.'
                doc_cmd_sub_option '-l, --list'
                    doc_cmd_sub_option_desc 'List/display the current PAT environment variable file.'
                doc_cmd_sub_option '-v, --valid [PAT]'
                    doc_cmd_sub_option_desc 'Checks if the current PAT environment variable (or one that is supplied as an argument) is valid.'
        doc_cmd_sub_cmd 'git-hook'
            doc_cmd_sub_cmd_desc 'Add the prepare-commit-msg git hook to the Development repo. This hook prepends the Jira issue number in the branch name (e.g. for a branch named MYG-50500-my-branch, the issue number would be MYG-50500) to each commit message. So when you commit some changes with the message "Add test", the commit message would be automatically modified to look like this: [MYG-50500] Add test.'
            doc_cmd_sub_options_title
                doc_cmd_sub_option '-s, --show'
                    doc_cmd_sub_option_desc 'Print out the prepare-commit-msg hook code'

    doc_cmd_examples_title
        doc_cmd_example 'geo init repo'
        doc_cmd_example 'geo init npm'
        doc_cmd_example 'geo init git-hook'
}
geo_init() {
    if [[ "$1" == '--' ]]; then shift; fi

    case $1 in
    'repo' | '')
        local repo_dir=$(pwd)
        [[ $1 == repo && -n $2 ]] && repo_dir="$2"
        if ! geo_is_valid_repo_dir "$repo_dir"; then
            log::warn "MyGeotab repo not found in:"
            log::link "$repo_dir"
            log::status "Searching for possible repo locations..."
            _geo_init_repo_find_myg_repo -v repo_dir
            [[ -z $repo_dir ]] && log::log::Error "Faild to locate the MyGeotab repo directory." && return 1
        fi
        local current_repo_dir=$(geo_get DEV_REPO_DIR)
        if [[ -n $current_repo_dir ]]; then
            log::info -b "The current Development repo directory is:"
            log::info "    $current_repo_dir"
            if ! prompt_continue "Would you like to replace that with the current directory? (Y|n): "; then
                return
            fi
        fi
        geo_set DEV_REPO_DIR "$repo_dir"
        log::status "MyGeotab base repo (Development) path set to:"
        log::link "    $repo_dir"
        ;;
    # npmi )
    #     (
    #         cd ~/test
    #         npm i || log::Error "npm install failed" && return 1

    #     )
    #     ;;
    npm )
        local close_delayed=false
        local arg="$2"
        [[ $arg == -c ]] && close_delayed=true
        (
            local fail_count=0

            local current_repo_dir=$(geo_get DEV_REPO_DIR)
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
    pat )
        geo_init_pat "${@:2}"
        ;;
    git-hook* | git | gh )
        _geo_init_git_hook "${@:2}"
        ;;
    auto-switch | as )
        _geo_init_auto_switch "${@:2}"
        ;;
    esac
}

_geo_init_auto_switch() {
    local dev_repo_dir=$(geo_get DEV_REPO_DIR)
    (
        cd "$dev_repo_dir"
        local myg_branches="$(git branch -r | sed 's/  //g' | grep --color=never -P '^origin/(release/\d+\.0|main)$')"
        local branches=(${myg_branches[@]})
        if [[ -z ${branches[@]} ]]; then
            log::Error "Counldn't find any release branches in repo root: "
            log::link "$dev_repo_dir"
            return 1
        fi

        log::data_header "$(printf '%-4s %-42s\n' ID Release)"
        for branchId in ${!branches[@]}; do
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
        if [[ $valid_input = true ]]; then
            result_ref="$input_ids"
        fi
    done
}

_geo_init_repo_find_myg_repo() {
    local repo_path=
    local passed_ref=false
    if [[ $1 == -v ]]; then
        local -n repo_path="$2"
        passed_ref=true
        shift 2
    else
        local repo_path=
    fi
    # Search for possible locations for the MyG repo.
    local possible_repos="$(find "$HOME" -maxdepth 4 -type f -name MyGeotab.Core.csproj)"

    [[ -z $possible_repos ]] && return 1

    # Strip Checkmate/MyGeotab.Core.csproj from the end of each path.
    possible_repos="${possible_repos//\/Checkmate\/MyGeotab.Core.csproj/}"

    local path_count=$(wc -l <<<"$possible_repos")

    if (( $path_count == 1 )); then
        log::status "Found the following path for the MyGeotab repo:"
        log::link "   $possible_repos"
        prompt_continue "Is the above path the correct location of the MyGeotab repo? (Y/n): " || return 1
        repo_path="$possible_repos"
    elif (( $path_count > 1 )); then
        PS3="$(log::prompt 'Enter the number of the correct repo path: ')"
        select option in $r; do
            [[ -z $option ]] && log::warn "Invalid option: '$REPLY'" && continue
            repo_path="$option"
            break
        done
    fi

    $passed_ref && return
    prompt_return="$repo_path"
}

_geo_init_git_hook() {
    _geo_check_for_dev_repo_dir
    local dev_repo=$(geo_get DEV_REPO_DIR)
    local geo_src_dir=$(geo_get SRC_DIR)
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

geo_init_pat() {
    mkdir -p "$GEO_CLI_CONFIG_DIR/env"
    local pat_env_file_path="$GEO_CLI_CONFIG_DIR/env/gitlab-pat.sh"

    case $1 in
        -r | --remove )
            if prompt_continue "Remove geo-cli PAT environment variable initialization? (Y|n)"; then
                rm "$pat_env_file_path" && log::success "Done" || log::Error "Failed to remove file"
            fi
            return
            ;;
        -l | --list )
            if [[ ! -f "$pat_env_file_path" ]]; then
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
        -v | --valid )
            [[ -z $GITLAB_PACKAGE_REGISTRY_PASSWORD && -z $2 ]] && Error "GITLAB_PACKAGE_REGISTRY_PASSWORD is not defined." && return 1
            local pat=${2:-$GITLAB_PACKAGE_REGISTRY_PASSWORD}
            _is_pat_valid "$pat" && log::success "PAT is valid" || { log::Error "PAT is not valid. Response: '$pat_check_result'"; return 1; }
            return
            ;;
        -* )
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

        if ! _is_pat_valid "$pat"; then
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
    cat <<-EOF > "$pat_env_file_path"
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

_is_pat_valid() {
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
# geo_start_doc() {
#     doc_cmd 'start <service>'
#     doc_cmd_desc 'Start individual service.'
#     doc_cmd_examples_title
#     doc_cmd_example 'geo start web'
# }
# geo_start() {
#     exit_if_repo_dir_uninit
#     if [ -n "${SERVICES_DICT[$1]}" ]; then
#         if [[ $1 = 'runner' ]]; then
#             # pm2-runtime start $GEO_REPO_DIR/runner/.geo-cli/ecosystem.config.js
#             geo_runner start
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
#         log::Error "$1 is not a service"
#     fi
# }

#######################################################################################################################
# COMMANDS+=('restart')
# geo_restart_doc() {
#     doc_cmd 'restart [service]'
#     doc_cmd_desc 'Restart container [service] or the entire system if no service is provided.'
#     doc_cmd_examples_title
#     doc_cmd_example 'geo restart web'
#     doc_cmd_example 'geo restart'
# }
# geo_restart() {
#     exit_if_repo_dir_uninit
#     if [ -z $1 ]; then
#         # geo_down
#         geo_stop
#         geo_up
#         geo_runner restart
#         return
#     fi

#     if [ -n "${SERVICES_DICT[$1]}" ]; then
#         if [[ $1 = 'runner' ]]; then
#             # pm2 restart runner
#             geo_runner restart
#         else
#             cd $GEO_REPO_DIR/env/full
#             dc_geo restart "$1"
#         fi
#     else
#         log::Error "$1 is not a service"
#     fi
# }

#######################################################################################################################
COMMANDS+=('env')
geo_env_doc() {
    doc_cmd 'env <cmd> [arg1] [arg2]'
    doc_cmd_desc 'Get, set, or list geo environment variable.'

    doc_cmd_sub_cmds_title
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
geo_env() {
    # Check if there is any arguments.
    if [[ -z $1 ]]; then
        geo_env_doc
        return
    fi

    case $1 in
    'set')
        # Get the key from the second arg.
        local key="$2"
        # Get the new value by concatenating the rest of the args together.
        local value="${@:3}"
        geo_set -s "$key" "$value"
        ;;
    'get')
        # Show error message if the key doesn't exist.
        geo_haskey "$2" || { log::Error "Key '$2' does not exist."; return 1; }
        geo_get "$2"
        ;;
    'rm')
        # Show error message if the key doesn't exist.
        geo_haskey "$2" || { log::Error "Key '$2' does not exist."; return 1; }
        geo_rm "$2"
        ;;
    'ls')
        if [[ $2 == keys ]]; then
            awk -F= '{ gsub("GEO_CLI_","",$1); printf "%s ",$1 } ' $GEO_CLI_CONF_FILE | sort
            return
        fi
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
COMMANDS+=('set')
geo_set_doc() {
    doc_cmd 'set <env_var> <value>'
    doc_cmd_desc 'Set geo environment variable.'
    doc_cmd_options_title
    doc_cmd_option 's'
    doc_cmd_option_desc 'Shows the old and new value of the environment variable.'
    doc_cmd_examples_title
    doc_cmd_example 'geo set DEV_REPO_DIR /home/username/repos/Development'
}
geo_set() {
    # Set value of env var
    # $1 - name of env var in conf file
    # $2 - value
    local initial_line_count=$(wc -l $GEO_CLI_CONF_FILE | awk '{print $1}')
    local conf_backup=$(cat $GEO_CLI_CONF_FILE)
    local show_status=false
    local shifted=false
    [[ $1 == -s ]] && show_status=true && shift

    local key="${1^^}"
    local geo_key="$key"
    shift
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
            (( $? != 0 )) && log::Error "'geo set' failed to lock config file after timeout. Key: $geo_key, value: $value." && return 1
            # Write to the file atomically.
            cfg_write $GEO_CLI_CONF_FILE "$geo_key" "$value"
        # Open up the lock file for writing on file descriptor 200. The lock is release as soon as the subshell exits.
        ) 200> /tmp/.geo.conf.lock
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
COMMANDS+=('get')
geo_get_doc() {
    doc_cmd 'get <env_var>'
    doc_cmd_desc 'Get geo environment variable.'

    doc_cmd_examples_title
    doc_cmd_example 'geo get DEV_REPO_DIR'
}
geo_get() {
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

geo_haskey() {
    local key="${1^^}"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"
    cfg_haskey $GEO_CLI_CONF_FILE "$key"
}

#######################################################################################################################
COMMANDS+=('rm')
geo_rm_doc() {
    doc_cmd 'rm <env_var>'
    doc_cmd_desc 'Remove geo environment variable.'

    doc_cmd_examples_title
    doc_cmd_example 'geo rm DEV_REPO_DIR'
}
geo_rm() {
    # Get value of env var.
    local key="${1^^}"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"

    ! geo_haskey "$key" && return 1

    (
        # Get an exclusive lock on file descriptor 200, waiting only 5 second before timing out.
        flock -w 5 -e 200
        # Check if the lock was successfully acquired.
        (( $? != 0 )) && log::Error "'geo rm' failed to lock config file after timeout. Key: $key" && return 1
        # Write to the file atomically.
        cfg_delete "$GEO_CLI_CONF_FILE" "$key"
    # Open up the lock file for writing on file descriptor 200. The lock is release as soon as the subshell exits.
    ) 200> /tmp/.geo.conf.lock
    [[ $? != 0 ]] && return 1
}

geo_haskey() {
    local key="${1^^}"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"
    cfg_haskey "$GEO_CLI_CONF_FILE" "$key"
}

# Save the previous 5 items as a single value in the config file, delimited by the '@' character.
_geo_push() {
    local key="$1"
    local value="$2"
    [[ -z $key ]] && log::Error "_geo_push: Key cannot be empty" && return 1
    [[ -z $value ]] && log::Error "_geo_push: Value cannot be empty" && return 1
    local stored_items="$(geo_get $key)"

    if [[ -z $stored_items ]]; then
        # log::debug "_geo_push: stored_items was empty"
        geo_set $key "$value"
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
    if (( count > 5 )); then
        # Remove the oldest item, keeping only 5.
        stored_items=$(echo $stored_items | awk -F '@' '{ print $1"@"$2"@"$3"@"$4"@"$5 }')
    fi
#    log::debug geo_set $key "_geo_push: setting cmds to: $stored_items"
    geo_set $key "$stored_items"
}

_geo_push_get_items() {
    [[ -z $1 ]] && return
    geo_get $1 | tr '@' '\n'
}

_geo_push_get_item() {
    local key="$1"
    local item_number="$2"
    [[ -z $item_number || $item_number -gt 5 || $item_number -lt 0 ]] && log::Error "Invalid command number. Expected a value between 0 and 5." && return 1

    local items=$(geo_get $key)
    if [[ -z $items ]]; then
        return
    fi
    local awk_cmd='{ print $'$item_number' }'
    echo $(echo $items | awk -F '@' "$awk_cmd")
}

#######################################################################################################################
COMMANDS+=('update')
geo_update_doc() {
    doc_cmd 'update'
        doc_cmd_desc 'Update geo to latest version.'
    doc_cmd_options_title
        doc_cmd_option '-f, --force'
            doc_cmd_sub_option_desc 'Force update, even if already at latest version.'
    doc_cmd_sub_cmds_title
        doc_cmd_sub_cmd 'docker-compose'
            doc_cmd_sub_cmd_desc 'Updates docker-compose to the latest stable version.'
    doc_cmd_examples_title
        doc_cmd_example 'geo update'
        doc_cmd_example 'geo update --force'
        doc_cmd_example 'geo update docker-compose'
}
geo_update() {
    if [[ $1 == docker-compose ]]; then
        _geo_install_or_update_docker_compose
        return
    fi
    
    local force=false
    [[ $1 == '-f' || $1 == '--force' ]] && force=true
    # Don't install if already at latest version unless the force flag is present (-f or --force)
    if ! _geo_check_for_updates && ! $force; then
        log::Error 'The latest version of geo-cli is already installed'
        return 1
    fi

    local geo_cli_dir="$(geo_get GEO_CLI_DIR)"
    local prev_commit="$(geo_get GIT_PREVIOUS_COMMIT)"
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

        geo_set GIT_PREVIOUS_COMMIT "$new_commit"
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
COMMANDS+=('uninstall')
geo_uninstall_doc() {
    doc_cmd 'uninstall'
        doc_cmd_desc "Remove geo-cli installation. This prevents geo-cli from being loaded into new bash terminals, but does
            not remove the geo-cli repo directory. Navigate to the geo-cli repo directory and run 'bash install.sh' to reinstall."

    doc_cmd_examples_title
        doc_cmd_example 'geo uninstall'
}
geo_uninstall() {
    if ! prompt_continue "Are you sure that you want to remove geo-cli? (Y|n)"; then
        return
    fi

    geo_indicator disable
    geo_set disabled true

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
COMMANDS+=('analyze')
geo_analyze_doc() {
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
geo_analyze() {
    local dev_repo=$(geo_get DEV_REPO_DIR)
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
    
    log::hint "\nHint: When running all analyzers with the -a option, you can also add the -s option to skip long-running analyzers (GW-Linux-Debug and Build-All.sln). Example $(txt_underline geo analyze -as)."
    local prev_ids=$(geo_get ANALYZER_IDS)

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
            a )
                ids=$(seq -s ' ' 0 $max_id)
                echo
                log::status -b 'Running all analyzers'
                ;;
            # Check if the run individually option (-i) was supplied.
            i ) run_individually=true ;;
            # Check if the batch run option (-b) was supplied.
            b )
                run_individually=false
                # echo
                # log::status -b 'Running analyzers in batches'
                # echo
                ;;
            # Skip long running analyzers.
            s )
                include_long_running=false
                echo
                log::status -b 'Skip long running analyzers'
                ;;
            g )
                (
                    cd "$dev_repo"
                    pwd
                    dotnet build -c Debug -r ubuntu-x64 $MYG_GATEWAY_TEST_PROJ
                )
                return
                ;;
            d )
                (
                    cd "$dev_repo"
                    pwd
                    dotnet build All.sln
                )
                return
                ;;
            \? )
                log::Error "Invalid option: $1"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    [[ $run_individually == false ]] && log::status -b "\nRunning analyzers in batches"

    # Check if the run previous analyzers option (-) was supplied.
    if [[ $1 =~ ^-$ ]]; then
        ids=$(geo_get ANALYZER_IDS)
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
        if [[ $valid_input = true ]]; then
            ids="$prompt_return"
        fi
    done

    # The number of ids entered.
    local id_count=$(echo "$ids" | wc -w)
    local run_count=1

    geo_set ANALYZER_IDS "$ids"

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

            if [[ $run_individually = false ]]; then
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

                done;

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
COMMANDS+=('id')
geo_id_doc() {
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
geo_id() {
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
    
    # If the imput is wrapped in quotes (e.g. "123") or other invalid characters, remove them.
    arg="${arg//[\"\n\']/}"

    convert_id() {
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
            log::Error "Invalid input format. Length: ${#arg}, input: '$arg'"
            log::warn "Guid ids must be 36 characters long."
            log::warn "Encoded guid ids must be prefixed with 'a' and be 23 characters long."
            log::warn "Encoded long ids must be prefixed with 'b'."
            log::warn "Use 'geo id help' for usage info."
            return 1
        fi
    }

    if [[ $interactive == true || $use_clipboard == true ]]; then
        clipboard=$(xclip -o)
        # If the imput is wrapped in quotes (e.g. "123") or other invalid characters, remove them.
        clipboard="${clipboard//[\"\n\']/}"
        # log::debug "Clip $clipboard"
        local valid_id_re='^[a-zA-Z0-9_-]{1,36}$'
        # [[ $clipboard =~ $valid_id_re]]
        # First try to convert the contents of the clipboard as an id.
        if [[ -n $clipboard && ${#clipboard} -le 36 ]]; then
            # [[ $clipboard =~ $valid_id_re ]]
            # geo_id $clipboard
            # log::debug "Clip $clipboard"
            output=$(convert_id $clipboard)
            # log::debug $output

            if [[ $output =~ Error ]]; then
                log::detail 'No valid ID in clipboard'
            else
                log::detail "Converting the following id from clipboard: $clipboard"
                geo_id $clipboard
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
            geo_id $prompt_return
            echo
        done
        return
    fi

    # Convert the id.
    if ! convert_id $arg; then
        log::Error "Failed to convert id: $arg"
        return 1
    fi
    [[ $format_output == true ]] && log::status "$msg: "
    [[ $format_output == true ]] && log::detail -b $id || echo -n $id
    if ! type xclip > /dev/null; then
        log::warn 'Install xclip (sudo apt-get instal xclip) in order to have the id copied to your clipboard.'
        return
    fi
    echo -n $id | xclip -selection c
    [[ $format_output == true ]] && log::info "copied to clipboard"
}

#######################################################################################################################
COMMANDS+=('version')
geo_version_doc() {
    doc_cmd 'version, -v, --version'
    doc_cmd_desc 'Gets geo-cli version.'

    doc_cmd_examples_title
    doc_cmd_example 'geo version'
}
geo_version() {
    log::verbose $(geo_get VERSION)
}

#######################################################################################################################
COMMANDS+=('cd')
geo_cd_doc() {
    doc_cmd 'cd <dir>'
    doc_cmd_desc 'Change to directory'
    doc_cmd_sub_cmds_title

    doc_cmd_sub_cmd 'dev, myg'
    doc_cmd_sub_cmd_desc 'Change to the Development repo directory.'

    doc_cmd_sub_cmd 'geo, cli'
    doc_cmd_sub_cmd_desc 'Change to the geo-cli install directory.'

    doc_cmd_examples_title
    doc_cmd_example 'geo cd dev'
    doc_cmd_example 'geo cd cli'
}
geo_cd() {
    case "$1" in
        dev | myg)
            local path=$(geo_get DEV_REPO_DIR)
            if [[ -z $path ]]; then
                log::Error "Development repo not set."
                return 1
            fi
            cd "$path"
            ;;
        geo | cli)
            local path=$(geo_get DIR)
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
COMMANDS+=('indicator')
geo_indicator_doc() {
    doc_cmd 'indicator <command>'
    doc_cmd_desc 'Enables or disables the app indicator.'

    doc_cmd_sub_cmds_title
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
            doc_cmd_sub_options_title
                doc_cmd_sub_option '-b[-#]'
                    doc_cmd_sub_option_desc 'Shows logs since the last boot. Can also use -b-n (n is a number) to get logs from n boots ago.'

    doc_cmd_examples_title
    doc_cmd_example 'geo indicator enable'
    doc_cmd_example 'geo indicator disable'
}
geo_indicator() {
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
    _geo_indicator_check_dependencies
    case "$1" in
        enable )
            log::status -b "Enabling app indicator"
            geo_set 'APP_INDICATOR_ENABLED' 'true'

            # Directory where user service files are stored.
            mkdir -p  ~/.config/systemd/user/
            mkdir -p  ~/.geo-cli/.data
            mkdir -p  ~/.geo-cli/.indicator
            export src_dir=$(geo_get GEO_CLI_SRC_DIR)
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
                log::Error "App indicator service file not found at '$service_file_path'"
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
            envsubst < $service_file_path > $indicator_service_path
            # envsubst < $desktop_file_path > /tmp/$geo_indicator_desktop_file_name

            # desktop-file-install --dir=$app_desktop_entry_dir /tmp/$geo_indicator_desktop_file_name
            # envsubst < $desktop_file_path > $app_desktop_entry_dir/$geo_indicator_desktop_file_name
            # update-desktop-database $app_desktop_entry_dir
            # sudo chmod 777 $indicator_bin_path

            systemctl --user daemon-reload
            systemctl --user enable --now $geo_indicator_service_name
            systemctl --user restart $geo_indicator_service_name
            ;;
        start )
            systemctl --user start --now $geo_indicator_service_name
            ;;
        stop )
            systemctl --user stop --now $geo_indicator_service_name
            ;;
        disable )
            systemctl --user stop --now $geo_indicator_service_name
            systemctl --user disable --now $geo_indicator_service_name
            geo_set 'APP_INDICATOR_ENABLED' 'false'
            log::success 'Indicator disabled'
            ;;
        status )
            systemctl --user status $geo_indicator_service_name
            ;;
        restart )
            systemctl --user restart $geo_indicator_service_name
            ;;
        init )
            indicator_enabled=$(geo_get 'APP_INDICATOR_ENABLED')

            [[ -z $indicator_enabled ]] && indicator_enabled=true && geo_set 'APP_INDICATOR_ENABLED' 'true'
            [[ $indicator_enabled == false ]] && log::detail "Indicator is disabled. Run $(log::txt_underline geo indicator enable) to enable it.\n" && return
            geo_indicator enable
            ;;
        # Print out the geo-indicator.service file.
        cat )
            systemctl --user cat $geo_indicator_service_name
            ;;
        # Print out all configuration for the service.
        show )
            systemctl --user show $geo_indicator_service_name
            ;;
        # Edit the service file.
        edit )
            # systemctl --user edit $geo_indicator_service_name
            nano $indicator_service_path
            ;;
        no-service )
            (
                cd "$GEO_CLI_SRC_DIR/py/indicator"
                bash geo-indicator.sh
            )
            ;;
        log | logs )
            # Show all logs since last boot until now.
            local option='-b'
            # Can use -b-2 to get the logs since 2 boots ago or -b-3 to all since 3 boots ago.
            [[ -n $2 ]] && option="$2"
            journalctl --user -u $geo_indicator_service_name $option
            ;;
        * )
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
    local pkg_name="$1"
    ! type sudo &> /dev/null && sudo='' || sudo=sudo
    [[ -z $pkg_name ]] && log::warn 'No package name supplied' && return 1

    if ! dpkg -l $pkg_name &> /dev/null; then
        log::status "Installing missing package: $pkg_name"
        $sudo apt install -y "$pkg_name"
    fi
}
_geo_indicator_check_dependencies() {
    ! type sudo &> /dev/null && sudo='' || sudo=sudo
    if ! type python3 &> /dev/null; then
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
COMMANDS+=('test')
geo_test_doc() {
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
geo_test() {
    local dev_repo=$(geo_get DEV_REPO_DIR)
    local myg_tests_dir_path="${dev_repo}/Checkmate/MyGeotab.Core.Tests/"
    local script_path="${dev_repo}/gitlab-ci/scripts/StartDockerForTests.sh"
    local use_docker=false
    local interactive=false
    local seeds=(0)
    local is_number_re='^[0-9]+$'
    local find_unreliable='false'
    while [[ $1 =~ ^-+ ]]; do
        case "${1}" in
            -d | --docker )
                if [[ ! -f $script_path ]]; then
                    log::Error "Script to run ci docker environment locally not found in:\n  '${script_path}'."
                    log::warn "\nThis option is currently only supported for MyGeotab version 9.0 or later (current version is $(geo_dev release)). Running locally instead.\n"
                else
                    use_docker=true
                fi
                ;;
            -i )
                interactive=true
                ;;
            -n )
                [[ ! $2 =~ $is_number_re ]] && log::Error "The $1 option requires a number as an argument." && return 1
                for (( i = 1; i < $2; i++ )); do
                    seeds+=(0)
                done
                find_unreliable='true'
                shift
                ;;
            -r | --random-n )
                [[ ! $2 =~ $is_number_re ]] && log::Error "The $1 option requires a number as an argument." && return 1
                for (( i = 1; i < $2; i++ )); do
                    seeds+=($((RANDOM * RANDOM)))
                done
                find_unreliable='true'
                shift
                ;;
            --random-seeds )
                [[ ! $2 =~ $is_number_re ]] && log::Error "The $1 option requires a number as an argument." && return 1
                seeds=$2
                find_unreliable='true'
                ;;
            * )
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
                log::warn "\nThis option is currently only supported for MyGeotab version 9.0 or later (current version is $(geo_dev release)). Running locally instead.\n"
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
                echo "RandomSeed [$((i+1))/$seed_count]: ${seed}"
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
                        mv "$geotab_data_dir/UnitTestRunner" "$geotab_data_dir/UnitTestRunner_${i}_${seed}_`date +%Y-%m-%dT%H-%M-%S`"
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

#######################################################################################################################
COMMANDS+=('dev')
geo_dev_doc() {
    doc_cmd 'dev'
    doc_cmd_desc 'Commands used for internal geo-cli development.'

    doc_cmd_sub_cmds_title
        doc_cmd_sub_cmd 'update-available'
            doc_cmd_sub_cmd_desc 'Returns "true" if an update is available'
        doc_cmd_sub_cmd 'co <branch>'
            doc_cmd_sub_cmd_desc 'Checks out a geo-cli branch'
        doc_cmd_sub_cmd 'release'
            doc_cmd_sub_cmd_desc 'Returns the name of the MyGeotab release version of the currently checked out branch'
        doc_cmd_sub_cmd 'databases'
            doc_cmd_sub_cmd_desc 'Returns a list of all of the geo-cli database container names'
        doc_cmd_sub_cmd 'open-iap-tunnels'
            doc_cmd_sub_cmd_desc 'Gets a list of open-iap tunnels.'
}
geo_dev() {
    local geo_cli_dir="$(geo_get GEO_CLI_DIR)"
    local myg_dir="$(geo_get DEV_REPO_DIR)"
    local force_update_after_checkout=false
    [[ $1 == -u ]] && force_update_after_checkout=true && shift
    case "$1" in
        # Checks if an update is available.
        update-available )
            GEO_NO_UPDATE_CHECK=false
            if _geo_check_for_updates; then
                log::status true
                return
            fi
            log::status false
            ;;
        # Checks out a geo-cli branch.
        co )
            local branch=
            local checkout_failed=false
            (
                cd $geo_cli_dir
                [[ $2 == - ]] && branch=master || branch="$2"
                git checkout "$branch" || log::Error 'Failed to checkout branch' && checkout_failed=true
            )
            [[ $checkout_failed == true ]] && return 1
            [[ $force_update_after_checkout == true ]] && geo_update -f
            ;;
        # Gets the current MYG release (e.g. 10.0).
        release )
            (
                cd $myg_dir
                local cur_myg_branch=$(git branch --show-current)
                local prev_myg_branch=$(geo_get MYG_BRANCH)
                local prev_myg_release_tag=$(geo_get MYG_RELEASE)
                local cur_myg_release_tag=$prev_myg_release_tag

                if [[ -z $prev_myg_branch || -z $prev_myg_release_tag || $prev_myg_branch != $cur_myg_branch ]]; then
                    # The call to git describe is very CPU intensive, so only call it when the branch changes and then
                    # store the resulting myg release version tag. 
                    cur_myg_release_tag=$(git describe --tags --abbrev=0 --match MYG*)
                    
                    # Remove MYG/ prefix (present from 6.0 onwards).
                    [[ $cur_myg_release_tag =~ ^MYG/ ]] && cur_myg_release_tag=${cur_myg_release_tag##*/}
                    # Remove 5.7. prefix (present from 2104 and earlier).
                    [[ $cur_myg_release_tag =~ ^5.7. ]] && cur_myg_release_tag=${cur_myg_release_tag##*.}
                    
                    [[ $prev_myg_release_tag != $cur_myg_release_tag ]] && 
                        geo_set MYG_RELEASE "$cur_myg_release_tag"
                    [[ $prev_myg_branch != $cur_myg_branch ]] && 
                        geo_set MYG_BRANCH "$cur_myg_branch"
                fi
                echo -n $cur_myg_release_tag
            )
            ;;
        # Gets a list of all of the geo-cli databases.
        db|dbs|databases )
            echo $(docker container ls --filter name="geo_cli_db_"  -a --format="{{ .Names }}") | sed -e "s/geo_cli_db_postgres_//g"
            ;;
        auto-switch )
            _geo_auto_switch_server_config "$2" "$3"
            ;;
        open-iap-tunnels )
            local geo_config_dir="$(geo_get CONFIG_DIR)"
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
        tag )
            [[ $USER != dawsonmyers ]] && log::Error "This feature is for internal purposes only."
            local geo_cli_version=$(cat "$GEO_CLI_DIR/version.txt")
            [[ -z "$geo_cli_version" ]] && log::Error "Tag is empty" && return 1
            log::debug "git tag -a v$geo_cli_version -m 'geo-cli $geo_cli_version'"
            git tag -a "v$geo_cli_version" -m "geo-cli $geo_cli_version"
            git push origin "v$geo_cli_version"
            ;;
        * )
            log::Error "Unknown argument: '$1'"
            ;;
    esac
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
                [[ -f "$file" ]] && rm "$file"
            fi
        done
    )
}

#######################################################################################################################
COMMANDS+=('quarantine')
geo_quarantine_doc() {
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
geo_quarantine() {
    local interactive=false
    local blame=false
    local commit=false
    local commit_msg=

    [[ $1 == --interactive ]] && interactive=true && shift

    local OPTIND
    while getopts "bcim:" opt; do
        # log::debug "OPTIND: $OPTIND"
        # log::debug "OPTARG: $OPTARG"
        case "${opt}" in
            b ) blame=true ;;
            c ) commit=true ;;
            m ) commit_msg="$OPTARG" ;;
            i ) interactive=true ;;
            : )
                log::Error "Option '${opt}' expects an argument."
                return 1
                ;;
            \? )
                log::Error "Invalid option: -${opt}"
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

    local dev_repo=$(geo_get DEV_REPO_DIR)

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
                log::code ...
                log::code "$(grep -B 3 -e " $testname(" $file)"
                log::code ...
                echo
            }

            # Check to see if the test already has quarantine attributes.
            local attribute_text_check='"TestCategory", "Quarantine"|QuarantinedTestTicketLink'
            if grep -E "$attribute_text_check" <<<"$match" > /dev/null; then
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
        # log::detail ...
        # log::detail "$(grep -B 3 -e " $testname(" $file)"
        # log::detail ...

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
COMMANDS+=('mydecoder')
geo_mydecoder_doc() {
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
geo_mydecoder() {
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
            u ) make_unit_test=true ;;
            d ) database="$OPTARG" ;;
            n ) username="$OPTARG" ;;
            p ) password="$OPTARG" ;;
            i ) interactive=true ;;
            : )
                log::Error "Option '${opt}' expects an argument."
                return 1
                ;;
            \? )
                log::Error "Invalid option: -${opt}"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    local input_file_path="$1"
    local input_file_name=
    local output_file_path=
    local output_file_name=

    [[ -z $input_file_path ]] && log::Error "No input json file specified." && geo_mydecoder_doc && return 1
    [[ ! -f $input_file_path ]] && log::Error "Input file name does not exist." && return 1
    input_file_path=$(realpath $input_file_path)

    # debug "input: $input_file_path"
    # debug "make_unit_test: $make_unit_test"
    if $make_unit_test && [[ $input_file_path =~ \.txt$ ]]; then
        _geo_mydecoder_generate_unit_test "$input_file_path" "$database" "$username" "$password" && log::success "Done"
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
    #             log::Error "Option '${opt}' expects an argument."
    #             return 1
    #             ;;
    #         \? )
    #             log::Error "Invalid option: -${opt}"
    #             return 1
    #             ;;
    #     esac
    # done
    # shift $((OPTIND - 1))

    cleanup() {
        _geo_mydecoder_converter_check disable
    }
    trap cleanup INT TERM QUIT EXIT

    geo_set MYDECODER_CONVERTER_WAS_ENABLED false

    local dev_repo=$(geo_get DEV_REPO_DIR)

    (
        cd "$dev_repo"
        local demo_dir=Checkmate/Geotab.Checkmate.Demonstration
        cd $demo_dir
        local mydecoder_dir=src/demoresources/MyDecoder
        local mydecoder_dir_full=$(realpath $mydecoder_dir)
        [[ ! -d $mydecoder_dir ]] && log::Error "Directory '$demo_dir/$mydecoder_dir' does not exist. This feature is only available in MYG 9.0 and above." && return 1
        
        _geo_mydecoder_converter_check || return 1

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
        _geo_mydecoder_converter_check disable
        return 1
    fi

    _geo_mydecoder_converter_check disable

    # Make a unit test for log file if the -u option was passed in.
    $make_unit_test && _geo_mydecoder_generate_unit_test "$output_file_path" "$database" "$username" "$password"

    log::info "\nConverted log file path:"
    log::detail "$output_file_path\n"

    log::success "Done"
}

_geo_mydecoder_converter_check() {
    local action=$1
    local mydecoder_converter_was_enabled=$(geo_get MYDECODER_CONVERTER_WAS_ENABLED)
    local dev_repo=$(geo_get DEV_REPO_DIR)
    local converter_path="$dev_repo/Checkmate/Geotab.Checkmate.Demonstration/tests/ConvertMyDecoderJsonToTextLogFileMvp.cs"
    # log::debug "wasEnabled: $mydecoder_converter_was_enabled"
    [[ ! -f $converter_path ]] && log::Error "This feature is only available in MYG 9.0 and above. Checkout a compatible branch and rerun this command." && return 1
    if [[ $action == disable ]]; then
        if ! grep -E '// \[Fact\]' "$converter_path" > /dev/null 2>&1 && [[  $mydecoder_converter_was_enabled == true ]]; then
            sed -i -E 's_( {2,})\[Fact\]_\1// \[Fact\]_' "$converter_path"
            mydecoder_converter_was_enabled=false
        fi
    else
        if grep -E '// \[Fact\]' "$converter_path" > /dev/null 2>&1; then
            sed -i -E 's_// \[Fact\]_\[Fact\]_' "$converter_path"
            mydecoder_converter_was_enabled=true
        fi
    fi
    geo_set MYDECODER_CONVERTER_WAS_ENABLED $mydecoder_converter_was_enabled
}

_geo_mydecoder_generate_unit_test() {
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
}

#######################################################################################################################
COMMANDS+=('loc')
geo_loc_doc() {
    doc_cmd 'loc <file_extension>'
        doc_cmd_desc 'Counts the lines in all files in this directory and subdirectories. file_extension is the file type extension to count lines of code for (e.g., py, cs, sh, etc.).'
    doc_cmd_examples_title
        doc_cmd_example "geo loc cs # Counts the lines in all *.cs files."
}
geo_loc() {
    local file_type=$1
    find . -name '*'$file_type | xargs wc -l
}

_geo_get_mygeotab_csproj_path() {
    local dev_repo=$(geo_get DEV_REPO_DIR)
    myg_core_proj="$dev_repo/Checkmate/MyGeotab.Core.csproj"
    echo -n "$myg_core_proj"
}

#######################################################################################################################
COMMANDS+=('myg')
geo_myg_doc() {
    doc_cmd 'myg [subcommand | options]'
        doc_cmd_desc 'Performs various tasks related to building and running MyGeotab.'
    doc_cmd_sub_cmds_title
        doc_cmd_sub_cmd "start"
            doc_cmd_sub_cmd_desc "Starts MyGeotab."
        doc_cmd_sub_cmd 'build'
            doc_cmd_sub_cmd_desc "Builds MyGeotab.Core."
        doc_cmd_sub_cmd 'clean'
            doc_cmd_sub_cmd_desc "Runs $(txt_underline git clean -Xfd) if the Development repo."
        doc_cmd_sub_cmd 'stop'
            doc_cmd_sub_cmd_desc "Stops the running CheckmateServer (MyGeotab) instance."
        doc_cmd_sub_cmd 'restart'
            doc_cmd_sub_cmd_desc "Restarts the running CheckmateServer (MyGeotab) instance."
    doc_cmd_examples_title
        doc_cmd_example "geo myg start"
        doc_cmd_example "geo myg clean"
}
geo_myg() {
    local cmd="$1"
    shift
    local dev_repo=$(geo_get DEV_REPO_DIR)
    local myg_dir="$dev_repo/Checkmate"
    local myg_core_proj="$(_geo_get_mygeotab_csproj_path)"
    [[ ! -f $myg_core_proj ]] && Error "Cannot find csproj file at: $myg_core_proj" && return 1

    case "$cmd" in
        build )
            local project_path="$myg_dir"
            local project='MyGeotab.Core.csproj'
            case "$1" in
                sln )
                    project="MyGeotab.Core.sln"
                    ;;
                test | tests )
                    project="MyGeotab.Core.Tests.csproj"
                    project_path+="/MyGeotab.Core.Tests"
                    ;;
            esac
            log::status -b "Building $project"
            local build_command="dotnet build \"$project_path/$project\""
            log::debug "$build_command"
            if ! $build_command; then
                log::Error "Building $project failed"
                return 1;
            fi
            ;;
        stop )
            ! _geo_myg_is_running && log::Error "MyGeotab is not running" && return 1
            local myg_running_lock_file="$HOME/.geo-cli/tmp/myg/myg-running.lock"
            kill $(pgrep CheckmateServer) || log::Error "Failed to stop MyGeotab" && return 1
            log::success "Done"
            ;;
        restart )
            ! _geo_myg_is_running && log::Error "MyGeotab is not running" && return 1
            local checkmate_pid=$(pgrep CheckmateServer)
            # log::debug "Checkmate server PID: $checkmate_pid"
            kill $checkmate_pid  || { log::Error "Failed to restart MyGeotab"; return 1; }
            
            log::status -n "Waiting for MyGeotab to stop..."
            local wait_count=0
            while pgrep CheckmateServer > /dev/null; do
                log::status -n '.'
                (( wait_count++ >= 10 )) \
                    && log::Error "CheckmateServer failed to stop within 10 seconds" && return 1
                sleep 1
            done
            echo
            echo
            _geo_myg_is_running && log::Error "MyGeotab is still running" && return 1
            _geo_myg_start -r
            log::success "Done"
            ;;
        start )
            _geo_myg_start
            ;;
        is-running )
            local checkmate_pid=$(pgrep CheckmateServer)
            [[ -z $checkmate_pid ]] && return 1;
            echo -n $checkmate_pid
            ;;
        stop )
            local checkmate_pid=$(pgrep CheckmateServer)
            [[ -z $checkmate_pid ]] && log::Error "CheckmateServer isn't running." && return 1;
            
            kill $checkmate_pid \
                 && log::success "CheckmateServer stopped" \
                 || log::Error "Failed to stop CheckmateServer"
            ;;
        clean )
            (
                local opened_by_ui=false
                [[ $2 == --interactive ]] && opened_by_ui=true
                close_after_clean()
                { 
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

    esac
}

_geo_myg_is_running() {
    local myg_running_lock_file="$HOME/.geo-cli/tmp/myg/myg-running.lock"
    # Open a file descriptor on the lock file.
    [[ ! -f $myg_running_lock_file ]] && return 1
    exec {lock_fd}<> "$myg_running_lock_file"

    ! flock -w 0 $lock_fd || { eval "exec $lock_fd>&-";  return 1; }
    # Unlock the file.
    flock -u $lock_fd
    # Close the file descriptor.
    eval "exec $lock_fd>&-"
    return
}

_geo_myg_start() {
    local restarting=false
    [[ $1 == -r ]] && restarting=true
    export myg_core_proj="$(_geo_get_mygeotab_csproj_path)"
    local myg_running_lock_file="$HOME/.geo-cli/tmp/myg/myg-running.lock"
    mkdir -p "$(dirname $myg_running_lock_file)"
    [[ ! -f $myg_running_lock_file ]] && touch "$myg_running_lock_file"
    local proc_id=

    # Open a file descriptor on the lock file.
    exec {lock_fd}<> "$myg_running_lock_file"
    local wait_time=2
    export lock_file_fd=$lock_file

    if ! flock -w $wait_time $lock_fd; then
        log::debug ' Can not get lock on file'
        eval "exec $lock_fd>&-"
        return 1
    fi
   
    cleanup() {
        # echo "cleanup"
        [[ -n $proc_id ]] && kill $proc_id &> /dev/null
         # Unlock the file.
        flock -u $lock_fd &> /dev/null
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
COMMANDS+=('edit')
geo_edit_doc() {
    doc_cmd 'edit <file>'
        doc_cmd_desc 'Opens up files for editing.'
    doc_cmd_options_title
        doc_cmd_option '-e, --editor <editor_cmd>'
        doc_cmd_option_desc 'Sets the editor to open the files in (e.g. code, nano). VS Code (code) is the default editor.'
    doc_cmd_sub_cmds_title
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
geo_edit() {
    local editor=$(geo_get EDITOR)
    [[ $1 == -e || $1 == --editor ]] && editor=$2 && shift 2
    local file="$1"
    local file_path=
    local dev_repo=$(geo_get DEV_REPO_DIR)
    if [[ -z $editor ]]; then
        log::hint "You can set the default editor using: ""$(log::code -u 'geo set EDITOR <editor_command>')"
        if _geo_terminal_cmd_exists code; then
            editor=code
        elif _geo_terminal_cmd_exists nano; then
            editor=nano
        fi
    fi
    case "$file" in
        server.config | server | sconf | scf )
            file_path="${HOME}/GEOTAB/Checkmate/server.config"
            ;;
        *bashrc | brc | rc )
            file_path="${HOME}/.bashrc"
            ;;
        ci | cicd | *gitlab-ci* | git-ci )
            file_path="${dev_repo}/.gitlab-ci.yml"
            ;;
        cfg | geo.config | gconf )
            file_path="${HOME}/.geo-cli/.geo.conf"
            ;;
        * )
            log::Error "Arugument '$file' is invalid."
            return 1
            ;;
    esac
    [[ ! -f $file_path ]] && log::Error "File not found at: $file_path" && return 1
    
    log::debug "$editor '$file_path'"
    $editor "$file_path"
}

#######################################################################################################################
# COMMANDS+=('command')
# geo_command_doc() {
#
# }
# geo_command() {
#
# }

#######################################################################################################################
# COMMANDS+=('python-plugin')
# geo_python-plugin_doc() {

# }
# geo_python-plugin() {
#     python $path_to_py_file
# }

# Util
###########################################################################################################################################


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
#                 log::Error "Option '${opt}' expects an argument."
#                 return 1
#                 ;;
#             \? )
#                 log::Error "Invalid option: -${opt}"
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
_geo_cmd_exists() {
    cmd=$(echo "${COMMANDS[@]}" | tr ' ' '\n' | grep -E "$(echo ^$1$)")
    echo $cmd
    [[ -n $cmd ]]
}

# Checks if a command exists (i.e. docker, code).
# 1: the command to check
_geo_terminal_cmd_exists() {
    type "$1" &> /dev/null
}

# Install Docker and Docker Compose if needed.
_geo_check_docker_installation() {
    if ! type docker > /dev/null; then
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
    local current_compose_version=$(which docker-compose > /dev/null && docker-compose --version)
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
    sudo curl -L "https://github.com/docker/compose/releases/download/v${latest_compose_version:-2.12.0}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

    sudo chmod +x /usr/local/bin/docker-compose
    docker-compose --version
    log::success 'OK'
}

_geo_print_messages_between_commits_after_update() {
    [[ -z $1 || -z $2 ]] && return 1
    local prev_commit=$1
    local cur_commit=$2

    local geo_cli_dir="$(geo_get GEO_CLI_DIR)"

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
            (( line_count++ ))
            (( line_count > max_lines )) && continue
            # Trim off commit hash (trim off everything up to the first space).
            msg=${msg#* };
            # Format the text (wrap long lines and indent by 4).
            msg=$(log::fmt_text_and_indent_after_first_line "* $msg" 3 2)
            log::detail "$msg"
        done <<<$commit_msgs
        
        if (( line_count > max_lines )); then
            local msgs_not_shown=$(( line_count - max_lines ))
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
    local geo_cli_dir="$(geo_get GEO_CLI_DIR)"
    local cur_branch=$(cd $geo_cli_dir && git rev-parse --abbrev-ref HEAD)
    local v_remote=

    if [[ $cur_branch != master && -f $geo_cli_dir/feature-version.txt ]]; then
        geo_set FEATURE true
        # log::debug "cur_branch = $cur_branch"
        v_remote=$(git archive --remote=git@git.geotab.com:dawsonmyers/geo-cli.git $cur_branch feature-version.txt | tar -xO)
        # log::debug "v_remote = $v_remote"
        if [[ -n $v_remote ]]; then
            local feature_version=$(cat $geo_cli_dir/feature-version.txt)
            geo_set FEATURE_VER_LOCAL "${cur_branch}_V$feature_version"
            geo_set FEATURE_VER_REMOTE "${cur_branch}_V$v_remote"
            # log::debug "current feature version = $feature_version, remote = $v_remote"
            if [[ $feature_version == MERGED || $v_remote == MERGED || $v_remote -gt $feature_version ]]; then
                # log::debug setting outdated true
                geo_set OUTDATED true
                return
            fi
        fi
        geo_set OUTDATED false
        return 1
    fi
    geo_rm FEATURE
    geo_rm FEATURE_VER_LOCAL
    geo_rm FEATURE_VER_REMOTE

    # Gets contents of version.txt from remote.
    v_remote=$(git archive --remote=git@git.geotab.com:dawsonmyers/geo-cli.git HEAD version.txt | tar -xO)

    if [[ -z $v_remote ]]; then
        log::Error 'Unable to pull geo-cli remote version'
        v_remote='0.0.0'
    else
        geo_set REMOTE_VERSION "$v_remote"
    fi

    # The sed cmds filter out any colour codes that might be in the text
    local v_current=$(geo_get VERSION) #  | sed -r "s/[[:cntrl:]]\[[0-9]{1,3}m//g"`
    if [[ -z $v_current ]]; then
        geo_cli_dir="$(geo_get GEO_CLI_DIR)"
        v_current=$(cat "$geo_cli_dir/version.txt")
        geo_set VERSION "$v_current"
    fi
    # ver converts semver to int (e.g. 1.2.3 => 001002003) so that it can easliy be compared
    if [ $(ver $v_current) -lt $(ver $v_remote) ]; then
        geo_set OUTDATED true
        # _geo_show_update_notification
        return
    else
        geo_set OUTDATED false
        return 1
    fi
}

_geo_is_outdated() {
    outdated=$(geo_get OUTDATED)
    [[ $outdated =~ true ]]
}

# Sends an urgent geo-cli notification. This notification must be clicked by the user to dismiss.
_geo_show_update_notification() {
    # log::debug _geo_show_update_notification
    local notification_shown=$(geo_get UPDATE_NOTIFICATION_SENT)
    geo_set UPDATE_NOTIFICATION_SENT true
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
    ! type notify-send &> /dev/null && return 1
    [[ -z $GEO_CLI_DIR ]] && return
    local show_notifications=$(geo_get SHOW_NOTIFICATIONS)
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
    # outdated=`geo_get OUTDATED`
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
    if [[ "$ord_val" = 27 ]]; then
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

# The name of a command
doc_cmd() {
    doc_handle_command "$1"
    local indent=4
    local txt=$(log::fmt_text "$@" $indent)
    # detail_u "$txt"
    log::detail -b "$txt"
}

# Command description
doc_cmd_desc() {
    local indent=6
    local txt=$(log::fmt_text "$@" $indent)
    log::data -t "$txt"
}

doc_cmd_desc_note() {
    local indent=8
    local txt=$(log::fmt_text "$@" $indent)
    log::data -t "$txt"
}

doc_cmd_examples_title() {
    local indent=8
    local txt=$(log::fmt_text "Example:" $indent)
    log::info -t "$txt"
    # info_i "$(log::fmt_text "Example:" $indent)"
}

doc_cmd_example() {
    local indent=12
    local txt=$(log::fmt_text "$@" $indent)
    log::data "$txt"
}

doc_cmd_options_title() {
    local indent=8
    local txt=$(log::fmt_text "Options:" $indent)
    log::info -t "$txt"
    # log::data -b "$txt"
}
doc_cmd_option() {
    # doc_handle_subcommand "$1"
    local indent=12
    local txt=$(log::fmt_text "$@" $indent)
    log::verbose -bt "$txt"
}
doc_cmd_option_desc() {
    local indent=16
    local txt=$(log::fmt_text "$@" $indent)
    log::data "$txt"
}

doc_cmd_sub_cmds_title() {
    local indent=8
    local txt=$(log::fmt_text "Commands:" $indent)
    log::info -t "$txt"
    # log::data -b "$txt"
}
doc_cmd_sub_cmd() {
    doc_handle_subcommand "$1"
    local indent=12
    local txt=$(log::fmt_text "$@" $indent)
    log::verbose -b "$txt"
}
doc_cmd_sub_cmd_desc() {
    local indent=16
    local txt=$(log::fmt_text "$@" $indent)
    log::data "$txt"
}

doc_cmd_sub_sub_cmds_title() {
    local indent=18
    local txt=$(log::fmt_text "Commands:" $indent)
    log::info "$txt"
    # log::data -b "$txt"
}
doc_cmd_sub_sub_cmd() {
    local indent=20
    local txt=$(log::fmt_text "$@" $indent)
    log::verbose "$txt"
}
doc_cmd_sub_sub_cmd_desc() {
    local indent=22
    local txt=$(log::fmt_text "$@" $indent)
    log::data "$txt"
}

doc_cmd_sub_options_title() {
    local indent=18
    local txt=$(log::fmt_text "Options:" $indent)
    log::info "$txt"
    # log::data -b "$txt"
}
doc_cmd_sub_option() {
    local indent=20
    local txt=$(log::fmt_text "$@" $indent)
    log::verbose "$txt"
}
doc_cmd_sub_option_desc() {
    local indent=22
    local txt=$(log::fmt_text "$@" $indent)
    log::data "$txt"
}

prompt_continue_or_exit() {
    log::prompt_n "Do you want to continue? (Y|n): "
    read -e answer
    [[ ! $answer =~ [nN] ]]
}
prompt_continue() {
    # Yes by default, any input other that n/N/no will continue.
    local regex="[^nN]"
    local default=yes
    local prompt_msg="Do you want to continue? (Y|n): "
    # Default to no if the -n option is present. This means that the user is required to enter y/Y/yes to continue,
    # anything else will decline to continue.
    [[ $1 == -n ]] && regex="[yY]" && default=no && shift
    if [[ -n $1 ]]; then
        prompt_msg="$1"
    fi
    log::prompt_n "$prompt_msg"

    read -e answer
    # The read command doesn't add a new line with the -e option (allows for editing of the input with arrow keys, etc.)
    # when the user just presses Enter (with no input), read doesn't add a new line after. So add one.
    [[ -z $answer ]] && echo
    [[ $answer =~ $regex || -z $answer && $default == yes ]]
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

doc_handle_command() {
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
    local cmd=
    local completions=

    [[ ! -f $GEO_CLI_AUTOCOMPLETE_FILE ]] && touch "$GEO_CLI_AUTOCOMPLETE_FILE"

    while read line; do
        # Skip empty lines.
        (( ${#line} == 0 )) && continue
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
    # populate the command info by running all of geo's help commands
    geo_help > /dev/null
    doc_handle_command 'DONE'
    echo -n '' > "$GEO_CLI_AUTOCOMPLETE_FILE"

    for cmd in "${!SUBCOMMANDS[@]}"; do
        echo "$cmd=${SUBCOMMANDS[$cmd]}" >> "$GEO_CLI_AUTOCOMPLETE_FILE"
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
_geo_complete()
{
    local cur prev
    # echo "COMP_WORDS: ${COMP_WORDS[@]}" >> bcompletions.txt
    # echo "COMP_CWORD: $COMP_CWORD" >> bcompletions.txt
    cur=${COMP_WORDS[COMP_CWORD]}
    # echo "cur: ${COMP_WORDS[COMP_CWORD]}"  >> bcompletions.txt
    prev=${COMP_WORDS[$COMP_CWORD-1]}
    prevprev=${COMP_WORDS[$COMP_CWORD-2]}
    local full_cmd="${COMP_WORDS[@]}"
    # echo "prev: $prev"  >> bcompletions.txt
    case ${COMP_CWORD} in
        # e.g., geo
        1)
            local cmds="${COMMANDS[@]}"

            COMPREPLY=($(compgen -W "$cmds" -- ${cur}))
            ;;
        # e.g., geo db
        2)
            # echo "2: $prevprev/$prev/$cur" >> ~/bcompletions.txt
            # echo "2: SUBCOMMAND_COMPLETIONS[$prev] = ${SUBCOMMAND_COMPLETIONS[$prev]}" >> ~/bcompletions.txt
            # echo "$prevprev/$prev/$cur"
            if [[ -v SUBCOMMAND_COMPLETIONS[$prev] ]]; then
                # echo "SUBCOMMANDS[$cur]: ${SUBCOMMANDS[$prev]}" >> bcompletions.txt
                COMPREPLY=($(compgen -W "${SUBCOMMAND_COMPLETIONS[$prev]}" -- ${cur}))
                case $prev in
                    get|set|rm ) COMPREPLY=($(compgen -W "$(geo_env ls keys)" -- ${cur^^})) ;;
                esac
            else
                COMPREPLY=()

            fi

            case $prev in
                mydecoder ) 
                    # echo "2:if:case:mydecoder" >> ~/bcompletions.txt
                    COMPREPLY=($(compgen -W "$(ls -A)" -- ${cur})) ;;
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
                db ) [[ $prev =~ start|rm|remove|cp|copy ]] && COMPREPLY=($(compgen -W "$(geo_dev databases)" -- ${cur})) ;;
                env ) [[ $prev =~ ls|get|set|rm ]] && COMPREPLY=($(compgen -W "$(geo_env ls keys)" -- ${cur^^})) ;;
                # get|set|rm ) COMPREPLY=($(compgen -W "$(geo_env ls keys)" -- ${cur})) ;;
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
}

complete -F _geo_complete geo
