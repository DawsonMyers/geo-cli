#!/bin/bash

# Gets the absolute path of the root geo-cli directory.
export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
export GEO_CLI_SRC_DIR="${GEO_CLI_DIR}/src"

# Import colour constants/functions and config file read/write helper functions.
. $GEO_CLI_SRC_DIR/utils/colors.sh
. $GEO_CLI_SRC_DIR/utils/config-file-utils.sh

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

geo_check_db_image() {
    local image=$(docker image ls | grep "$IMAGE")
    if [[ -z $image ]]; then
        if ! prompt_continue "geo-cli db image not found. Do you want to create one? (Y|n): "; then
            return 1
        fi
        geo_image create
    fi
}

###########################################################
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
        #     Error "No database version provided for removal"
        #     return
        # fi
        # geo_db_rm "$2"
        return
        ;;
    create)
        status 'Building image...'
        local dir=$(geo_get DEV_REPO_DIR)
        dir="${dir}/Checkmate/Docker/postgres"
        local dockerfile="Debug.Dockerfile"
        (
            cd "$dir"
            docker build --file "$dockerfile" -t "$IMAGE" . && success 'geo-cli Postgres image created' || warn 'Failed to create geo-cli Postgres image'
        )
        return
        ;;
    ls)
        docker image ls | grep "$IMAGE"
        ;;
    esac

}

###########################################################
COMMANDS+=('db')
geo_db_doc() {
    doc_cmd 'db'
    doc_cmd_desc 'Database commands.'

    doc_cmd_sub_cmds_title

    doc_cmd_sub_cmd 'create [option] <name>'
        doc_cmd_sub_cmd_desc 'Creates a versioned db container and volume.'
        doc_cmd_sub_options_title
            doc_cmd_sub_option '-y'
                doc_cmd_sub_option_desc 'Accept all prompts.'
            doc_cmd_sub_option '-e'
                doc_cmd_sub_option_desc 'Create blank Postgres 12 container.'

    doc_cmd_sub_cmd 'start [option] [name]'
        doc_cmd_sub_cmd_desc 'Starts (creating if necessary) a versioned db container and volume. If no name is provided,
                            the most recent db container name is started.'
    doc_cmd_sub_options_title
        doc_cmd_sub_option '-y'
            doc_cmd_sub_option_desc 'Accept all prompts.'

    doc_cmd_sub_cmd 'cp <source_db> <destination_db>'
        doc_cmd_sub_cmd_desc 'Makes a copy of an existing database container.'

    doc_cmd_sub_cmd 'rm, remove [option] <version> [additional version to remove]'
        doc_cmd_sub_cmd_desc 'Removes the container and volume associated with the provided version (e.g. 2004).'
        doc_cmd_sub_options_title
            doc_cmd_sub_option '-a, --all'
            doc_cmd_sub_option_desc 'Remove all db containers and volumes.'

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
        doc_cmd_sub_cmd_desc "Add, edit, list, or remove scripts that can be run with $(txt_italic geo db psql -q script_name)."
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
    if ! geo_check_docker_permissions; then
        return 1
    fi

    geo_db_check_for_old_image_prefix

    case "$1" in
    init)
        geo_db_init "$2"
        return
        ;;
    ls)
        geo_db_ls_containers

        if [[ $2 =~ ^-*a(ll)? ]]; then
            echo
            geo_db_ls_volumes
            echo
            geo_db_ls_images
        fi
        return
        ;;
    ps)
        docker ps --filter name="$IMAGE*"
        return
        ;;
    stop)
        geo_db_stop "${@:2}"
        return
        ;;
    rm | remove)
        db_version="$2"

        if [[ -z $db_version ]]; then
            Error "No database version provided for removal"
            return
        fi

        geo_db_rm "${@:2}"
        return
        ;;
    create)
        geo_db_create "${@:2}"
        ;;
    start)
        geo_db_start "${@:2}"
        ;;
    cp | copy)
        geo_db_copy "${@:2}"
        ;;
    psql)
        geo_db_psql "${@:2}"
        ;;
    script)
        geo_db_script "${@:2}"
        ;;
    bash | ssh)
        local running_container_id=$(geo_get_running_container_id)
        if [[ -z $running_container_id ]]; then
            Error 'No geo-cli containers are running to connect to.'
            info "Run $(txt_underline 'geo db ls') to view available containers and $(txt_underline 'geo db start <name>') to start one."
            return 1
        fi

        docker exec -it $running_container_id /bin/bash
        ;;
    *)
        Error "Unknown subcommand '$1'"
        ;;
    esac
}

geo_db_check_for_old_image_prefix() {
    old_container_prefix='geo_cli_db_postgres11_'
    containers=$(docker container ls -a --format '{{.Names}}' | grep $old_container_prefix)

    # Return if there aren't any containers with old prefixes.
    [[ -z $containers || -z $IMAGE ]] && return

    debug 'Fixing container names'
    for old_container_name in $containers; do
        cli_name=${old_container_name#$old_container_prefix}
        new_container_name="${IMAGE}_${cli_name}"
        debug "$old_container_name -> $new_container_name"
        docker rename $old_container_name $new_container_name
    done

    # Rename existing image.
    docker image tag geo_cli_db_postgres11 $IMAGE 2> /dev/null
}

geo_db_stop() {
    local silent=false

    if [[ $1 =~ -s ]]; then
        silent=true
        shift
    fi
    local container_name=$(geo_container_name $db_version)

    db_version="$1"

    if [[ -z $db_version ]]; then
        container_id=$(geo_get_running_container_id)
        # container_id=`docker ps --filter name="$IMAGE*" --filter status=running -aq`
    else
        container_id=$(geo_get_running_container_id "${container_name}")
        # container_id=`docker ps --filter name="${container_name}" --filter status=running -aq`
    fi

    if [[ -z $container_id ]]; then
        [[ $silent = false ]] &&
            warn 'No geo-cli db containers running'
        return
    fi

    status_bi 'Stopping container...'

    # Stop all running containers.
    echo $container_id | xargs docker stop >/dev/null && success 'OK'
}

geo_db_create() {
    local silent=false
    local acceptDefaults=
    local no_prompt=
    local empty_db=false
    local OPTIND
    while getopts "sye" opt; do
        case "${opt}" in
            s ) silent=true ;;
            y ) acceptDefaults=true ;;
            n ) no_prompt=true ;;
            e ) empty_db=true && status_bi 'Creating empty Postgres container';;
            \? ) 
                Error "Invalid option: -$OPTARG"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    db_version="$1"
    db_version=$(geo_make_alphanumeric "$db_version")

    if [[ -z $db_version ]]; then
        Error "No database version provided."
        return
    fi

    local container_name=$(geo_container_name "$db_version")

    if geo_container_exists $container_name; then
        Error 'Container already exists'
        return 1
    fi

    if ! geo_check_db_image; then
        Error "Cannot create db without image. Run 'geo image create' to create a db image"
        return 1
    fi

    if [[ -z $acceptDefaults && -z $no_prompt ]]; then
        prompt_continue "Create db container with name $(txt_underline ${db_version})? (Y|n): " || return
    fi
    status_bi "Creating volume:"
    status "  NAME: $container_name"
    docker volume create "$container_name" >/dev/null &&
        success 'OK' || (Error 'Failed to create volume' && return 1)

    status_bi "Creating container:"
    status "  NAME: $container_name"
    # docker run -v $container_name:/var/lib/postgresql/11/main -p 5432:5432 --name=$container_name -d $IMAGE > /dev/null && success OK
    local vol_mount="$container_name:/var/lib/postgresql/12/main"
    local port=5432:5432
    local image_name=$IMAGE
    local sql_user=postgres
    local sql_password='!@)(vircom44'

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

    docker create -v $vol_mount -p $port --name=$container_name $image_name >/dev/null &&
        (echo && success 'OK') || (Error 'Failed to create container' && return 1)

    echo

    if [[ $silent == false ]]; then
        info "Start your new db with $(txt_underline geo db start $db_version)"
        info "Initialize it with $(txt_underline geo db init $db_version)"
        echo
        info_bi "Connect with pgAdmin (after starting with $(txt_underline geo db start $db_version))"
        info 'Create a new server and entering the following information:'
        info "  Name: db (or whatever you want)"
        info "  Host: 127.0.0.1"
        info "  Username: $sql_user"
        info "  Password: $sql_password"
    fi
}

geo_db_start() {
    local acceptDefaults=
    if [[ $1 == '-y' ]]; then
        acceptDefaults=true
        shift
    fi

    local no_prompt=
    if [[ $1 == '-n' ]]; then
        no_prompt=true
        shift
    fi
    # Error "Port error" && return 1
    db_version="$1"
    local prompt_db_name=

    prompt_for_db_version() {
        prompt_db_name=true
        prompt_n "Enter an alphanumeric name for the new database version: "
        read db_version
        # debug $db_version
    }

    if [[ $1 == '-p' ]]; then
        prompt_for_db_version
    fi

    db_version=$(geo_make_alphanumeric "$db_version")
    # debug $db_version
    if [ -z "$db_version" ]; then
        if [[ -n $prompt_db_name ]]; then
            prompt_for_db_name
        else
            db_version=$(geo_get LAST_DB_VERSION)
            if [[ -z $db_version ]]; then
                Error "No database version provided."
                return
            fi
        fi
    fi

    if ! geo_check_db_image; then
        if ! prompt_continue "No database images exist. Would you like to create on (Y|n)?: "; then
            Error "Cannot start db without image. Run 'geo image create' to create a db image"
            return 1
        fi
        geo image create
    fi

    geo_set LAST_DB_VERSION "$db_version"

    # VOL_NAME="geo_cli_db_${db_version}"
    local container_name=$(geo_container_name $db_version)

    # docker run -v 2002:/var/lib/postgresql/11/main -p 5432:5432 postgres11

    # Check to see if the db is already running.
    local running_db=$(docker ps --format "{{.Names}}" -f name=geo_cli_db_)
    [[ $running_db == $container_name ]] && success "DB '$db_version' is already running" && return

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
        Error "Postgres port 5432 is currently bound to the following container: $container_name_using_postgres_port"
        [[ $no_prompt == true ]] && Error "Port error" && return 1
        if prompt_continue "Do you want to stop this container so that a geo db one can be started? (Y|n): "; then
            if docker stop "$container_name_using_postgres_port" > /dev/null; then
                status 'Container stopped'
            else
                Error 'Unable to stop container'
                return 1
            fi
        else
            error 'Cannot continue while port 5432 is already in use.'
            return 1
        fi
    fi

    local container_id=$(geo_get_container_id "$container_name")
    # local container_id=`docker ps -aqf "name=$container_name"`

    local output=''

    try_to_start_db() {
        output=''
        output="$(docker start $1 2>&1 | grep '0.0.0.0:5432: bind: address already in use')"
    }

    if [[ -n $container_id ]]; then

        status_bi "Starting existing container:"
        status "  ID: $container_id"
        status "  NAME: $container_name"

        # if [[ $recreate_container == true ]]; then
        #     docker container rm $container_id
        #     local vol_mount="geo_cli_db_postgres11_${db_version}:/var/lib/postgresql/12/main"
        #     local port=5432:5432
        #     docker create -v $vol_mount -p $port --name=$container_name $IMAGE > /dev/null
        # fi

        try_to_start_db $container_id

        if [[ -n $output ]]; then
            [[ $no_prompt == true ]] && Error "Port error" && return 1
            Error "Port 5432 is already in use."
            info "Fix: Stop postgresql"
            if prompt_continue "Do you want to try to stop the postgresql service? (Y|n): "; then
                sudo service postgresql stop
                sleep 2
                status_bi "Trying to start existing container again"
                try_to_start_db $container_id
                if [[ -n $output ]]; then
                    Error "Port 5432 is still in use. It's not possible to start a db container until this port is available."
                    return 1
                fi
                success OK
            fi
        fi
    else
        # db_version was getting overwritten somehow, so get its value from the config file.
        db_version=$(geo_get LAST_DB_VERSION)
        # db_version="$1"
        # db_version=$(geo_make_alphanumeric "$db_version")

        if [[ -z $acceptDefaults && -z $no_prompt ]]; then
            prompt_continue "Db container $(txt_italic ${db_version}) doesn't exist. Would you like to create it? (Y|n): " || return
        fi
        local opts=-s
        [[ $acceptDefaults == true ]] && opts+=y
        [[ $no_prompt == true ]] && opts+=n

        geo_db_create $opts "$db_version" ||
            (Error 'Failed to create db' && return 1)

        try_to_start_db $container_name
        container_id=$(docker ps -aqf "name=$container_name")

        if [[ -n $output ]]; then
            Error "Port 5432 is already in use."
            info "Fix: Stop postgresql"
            [[ $no_prompt == true ]] && return 1
            if prompt_continue "Do you want to try to stop the postgresql service? (Y|n): "; then
                sudo service postgresql stop && success 'postgresql service stopped'
                sleep 2
                status_bi "Trying to start new container"
                try_to_start_db $container_name
                if [[ -n $output ]]; then
                    Error "Port 5432 is still in use. It's not possible to start a db container until this port is available."
                    return 1
                fi
            else
                Error 'Cannot start db while port 5432 is in use.'
                return 1
            fi

        fi

        status_bi "Starting new container:"
        status "  ID: $container_id"
        status "  NAME: $container_name"

        [[ $no_prompt == true ]] && return
        if [ $acceptDefaults ] || prompt_continue 'Would you like to initialize the db? (Y|n): '; then
            geo_db_init $acceptDefaults
        else
            info "Initialize a running db anytime using $(txt_underline 'geo db init')"
        fi
    fi
    success Done
}

geo_db_copy() {
    local interactive=false
    [[ $1 = -i ]] && interactive=true && shift

    local source_db="$1"
    local destination_db="$2"

    db_name_exists() {
        local name=$(geo_container_name "$1")
        docker container inspect $name > /dev/null 2>&1
        # [[ $? == 0 ]]
    }

    source_db=$(geo_make_alphanumeric "$source_db")
    # Make sure the source database exists.
    ! db_name_exists $source_db && Error "The source database container '$source_db' does not exist" && return 1

    [[ -z $source_db ]] && Error "The source database cannot be empty" && return 1
    if [[ -z $destination_db ]]; then
        if [[ $interactive == true ]]; then
            info -b "Source database: '$source_db'"
            prompt_return=''
            while [[ -z $prompt_return ]] || db_name_exists "$prompt_return"; do
                db_name_exists "$prompt_return" && warn "Database container '$prompt_return' already exists"
                prompt_for_info_n 'Enter a name for the new database container: '
            done
            destination_db="$prompt_return"
        else
            Error "The destination database name cannot be empty" && return 1
        fi
    fi

    [[ -z $destination_db ]] && Error "The destination database name cannot be empty" && return 1
    
    destination_db=$(geo_make_alphanumeric "$destination_db")
    local source_db_name=$(geo_container_name "$source_db")
    local destination_db_name=$(geo_container_name "$destination_db")

    
    # Make sure the destination database doesn't exist
    db_name_exists $destination_db && Error "There is already a container named '$destination_db'" && return 1

    status -b "\nCreating destination database volume '$destination_db'"
    docker volume create --name $destination_db_name > /dev/null

    status -b "\nCopying data from source database volume '$source_db' to '$destination_db'"
    docker run \
        --rm \
        -it \
        -v $source_db_name:/from \
        -v $destination_db_name:/to \
        alpine ash -c "cd /from; cp -av . /to" #> /dev/nullge
    [[ $? -eq 0 ]] && success 'Done' || Error 'Volume creation failed'

    status -b "\nCreating destination database container '$destination_db'"
    local vol_mount="$destination_db_name:/var/lib/postgresql/12/main"
    local port=5432:5432
    if docker create -v $vol_mount -p $port --name=$destination_db_name $IMAGE >/dev/null; then
        success 'Done'
    else
        Error 'Failed to create container'
        return 1
    fi

    prompt_continue "Would you like to start database container '$destination_db'? (Y/n): " && geo_db_start $destination_db
}

geo_db_psql() {
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
    #     debug opt = "$opt", arg = "$OPTARG"
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
    #             Error "Unknown option '$OPTARG'."
    #             return 1
    #             ;;
    #         : )
    #             Error "Invalid argument for '$OPTARG'."
    #             return 1
    #             ;;
    #     esac
    # done
    # debug db_name=$db_name, sql_user=$sql_user, query=$query, psql_options=$psql_options
    # return
    local script_param_count=0
    declare -A cli_param_lookup
    while [[ $1 =~ ^-{1,2}[a-z] ]]; do
        local option=$1
        local arg="$2"
        shift
        # It's an error if the argument to an option is an option.
        [[ ! $arg || $arg =~ ^-[a-z] ]] && Error "Argument missing for option ${option}" && return 1

        # debug "op=$option    arg=$arg"
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

            debug $script_path
            if [[ -f $script_path ]]; then
                query="$(cat $script_path | sed "s/'/\'/g")"
            fi
            ;;
        --*)
            option="${option#--}"
            debug $option $arg
            cli_param_lookup["$option"]="$arg"
            ((script_param_count++))
            ;;
        *)
            Error "Unknown option '$option'."
            return 1
            ;;
        esac
        shift
    done

    # This isn't currently working
    debug $script_param_count
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

        # debug "$query"

        # Remove all comments and empty lines.
        query="$(sed -e 's/--.*//g' -e '/^$/d' <<<"$query")"
        for key in "${!param_lookup[@]}"; do
            value="${param_lookup[$key]}"
            [[ -v cli_param_lookup["$key"] ]] && value="${cli_param_lookup[$key]}"
            debug "value=$value    key=$key"
            query="$(sed "s/{{$key}}/$value/g" <<<"$query")"
        done
        query="$(echo "$query" | tr '\n' ' ')"
        # debug "$query"
    fi

    # Assign default values for sql user/passord.
    [[ -z $db_name ]] && db_name=geotabdemo
    [[ -z $sql_user ]] && sql_user=geotabuser
    [[ -z $sql_password ]] && sql_password=vircom43

    local running_container_id=$(geo_get_running_container_id)
    # debug $sql_user $sql_password $db_name $running_container_id

    if [[ -z $running_container_id ]]; then
        Error 'No geo-cli containers are running to connect to.'
        info "Run $(txt_underline 'geo db ls') to view available containers and $(txt_underline 'geo db start <name>') to start one."
        return 1
    fi

    if [[ -n $query ]]; then
        debug "docker exec $docker_options -e PGPASSWORD=$sql_password $running_container_id /bin/bash -c \"psql -U $sql_user -h localhost -p 5432 -d $db_name '$psql_options $query'\""
        eval "docker exec $docker_options -e PGPASSWORD=$sql_password $running_container_id /bin/bash -c \"psql -U $sql_user -h localhost -p 5432 -d $db_name '$psql_options $query'\""
    else
        docker exec -it -e PGPASSWORD=$sql_password $running_container_id psql -U $sql_user -h localhost -p 5432 -d $db_name
    fi
}

geo_db_script() {
    [[ -z $GEO_CLI_SCRIPT_DIR ]] && Error "GEO_CLI_SCRIPT_DIR doesn't have a value" && return 1
    [[ ! -d $GEO_CLI_SCRIPT_DIR ]] && mkdir -p $GEO_CLI_SCRIPT_DIR
    [[ -z $EDITOR ]] && EDITOR=nano

    local command="$1"
    local script_name=$(geo_make_alphanumeric $2)
    local script_path="$GEO_CLI_SCRIPT_DIR/$script_name".sql

    check_for_script() {
        if [[ -f $script_path ]]; then
            success 'Saved'
        else
            warn "Script '$script_name' wasn't found in script directory, did you save it before closing the text editor?"
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
            debug "$GEO_CLI_SRC_DIR/templates/geo-db-script.sql" "$script_path"
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
            Error "Unknown subcommand '$command'"
            ;;
    esac
}

geo_make_alphanumeric() {
    # Replace any non-alphanumeric characters with '_', then replace 2 or more occurrences with a singe '_'.
    # Ex: some>bad()name -> some_bad__name -> some_bad_name
    echo "$@" | sed 's/[^0-9a-zA-Z_.-]/_/g' | sed -e 's/_\{2,\}/_/g'
}

geo_db_ls_images() {
    info Images
    docker image ls geo_cli* #--format 'table {{.Names}}\t{{.ID}}\t{{.Image}}'
}
geo_db_ls_containers() {
    info 'DB Containers'
    # docker container ls -a -f name=geo_cli
    if [[ $1 = -a ]]; then
        docker container ls -a -f name=geo_cli
        return
    fi

    datediff() {
        d1=$(date -d "$1" +%s)
        d2=$(date -d "$2" +%s)
        days=$(((d1 - d2) / 86400))
        weeks=$(((d1 - d2) / (86400 * 7)))
        months=$(((d1 - d2) / (86400 * 30)))
        years=$(((d1 - d2) / (86400 * 365)))

        msg=$days
        ((days > 1)) && msg="$days days ago"
        ((days == 1)) && msg="yesterday"
        ((days == 0)) && msg="today"
        ((weeks == 1)) && msg="1 week ago"
        ((weeks > 1)) && msg="$weeks weeks ago"
        ((months == 1)) && msg="1 month ago"
        ((months > 1)) && msg="$months months ago"
        ((years == 1)) && msg="1 year ago"
        ((years > 1)) && msg="$years years ago"
        echo $msg
    }
    local now="$(date)"

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
    data_header "$header"

    local created_date=
    local rest_of_line=

    while read -r line; do
        _ifs=$IFS
        # Split the 4 fields in the line into an array (using tab as the delimiter).
        IFS=$'\t' read -r -a line_array <<<"$line"
        IFS=$_ifs

        created_date="${line_array[3]}"
        # Trim off timezone.
        created_date="${created_date:0:19}"

        days_since_created=$(datediff "$now" "$created_date")
        new_line="$(echo -e "${line_array[0]}\t${line_array[1]}\t${line_array[2]}\t$days_since")"
        # Remove the geo db prefix from the container name to get the geo-cli name for the db.
        line_array[0]="${line_array[0]#${GEO_DB_PREFIX}_}"
        printf "$line_format" "${line_array[0]}" "${line_array[1]}" "${line_array[2]}" "$days_since_created"
    done <<< "$output"
}
geo_db_ls_volumes() {
    info Volumes
    docker volume ls -f name=geo_cli
}

geo_container_name() {
    local name=$(geo_make_alphanumeric $1)
    echo "${IMAGE}_${name}"
}

geo_get_container_id() {
    local name=$1
    # [[ -z $name ]] && name="$IMAGE*"
    # echo `docker container ls -a --filter name="$name" -aq`
    local result=$(docker inspect "$name" --format='{{.ID}}' 2>&1)
    local container_does_not_exists=$(echo $result | grep "Error:")
    [[ $container_does_not_exists ]] && return
    echo $result
}

geo_container_exists() {
    local name=$(geo_get_container_id "$1")
    [[ -n $name ]]
}

geo_get_running_container_id() {
    local name=$1
    [[ -z $name ]] && name="$IMAGE*"
    echo $(docker ps --filter name="$name" --filter status=running -aq)
}

geo_get_running_container_name() {
    # local name=$1
    [[ -z $name ]] && name="$IMAGE*"
    
    local container_name=$(docker ps --filter name="$name" --filter status=running -a --format="{{ .Names }}")
    if [[ $1 == -r ]]; then
        container_name=${container_name#geo_cli_db_postgres_}
        container_name=${container_name#geo_cli_db_postgres11_}
    fi
    echo $container_name
}

geo_check_docker_permissions() {
    local ps_error_output=$(docker ps 2>&1 | grep docker.sock)
    if [[ -n $ps_error_output ]]; then
        Error "The current user does not have permission to use the docker command."
        info "Fix: Add the current user to the docker group."
        if prompt_n 'Would you like to fix this now? (Y|n): '; then
            sudo usermod -a -G docker "$USER"
            newgrp docker
            warn 'You must completely log out of you account and then log back in again for the changes to take effect.'
        fi
        return 1
    fi
}

function geo_db_init() {
    local acceptDefaults=$1

    local container_id=$(geo_get_running_container_id)
    if [[ -z $container_id ]]; then
        Error 'No geo-cli containers are running to initialize.'
        info "Run $(txt_underline 'geo db ls') to view available containers and $(txt_underline 'geo db start <name>') to start one."
        return 1
    fi
    db_name='geotabdemo'
    # status 'A db can be initialized with geotabdemo or with a custom db name (just creates an empty database with provided name).'
    # if ! [ $acceptDefaults ] && ! prompt_continue 'Would you like to initialize the db with geotabdemo? (Y|n): '; then
    #     stored_name=`geo_get PREV_DB_NAME`
    #     prompt_txt='Enter the name of the db you would like to create: '
    #     if [[ -n $stored_name ]]; then
    #         data "Stored db name: $stored_name"
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

    # if [[ -z $db_name ]]; then
    #     Error 'Db name cannot be empty'
    #     return 1
    # fi

    status_bi "Initializing db $db_name"
    local user=$(geo_get DB_USER)
    local password=$(geo_get DB_PASSWORD)
    local sql_user=$(geo_get SQL_USER)
    local sql_password=$(geo_get SQL_PASSWORD)
    local answer=''

    # Assign default values for sql user/passord.
    [[ -z $sql_user ]] && sql_user=geotabuser
    [[ -z $sql_password ]] && sql_password=vircom43

    # Make sure there's a running db container to initialize.
    local container_id=$(geo_get_running_container_id)
    if [[ -z $container_id ]]; then
        Error "There isn't a running geo-cli db container to initialize with geotabdemo."
        info 'Start one of the following db containers and try again:'
        geo_db_ls_containers
        return
    fi

    get_user() {
        prompt_n "Enter MyGeotab admin username (your email): "
        read user
        geo_set DB_USER "$user"
    }

    get_password() {
        prompt_n "Enter MyGeotab admin password: "
        read password
        geo_set DB_PASSWORD "$password"
    }

    get_sql_user() {
        prompt_n "Enter db admin username: "
        read sql_user
        geo_set SQL_USER "$sql_user"
    }

    get_sql_password() {
        prompt_n "Enter db admin password: "
        read sql_password
        geo_set SQL_PASSWORD "$sql_password"
    }

    if [ ! $acceptDefaults ]; then
        # Get sql user.
        data "Stored db admin user: $sql_user"
        prompt_continue "Use stored user? (Y|n): " || get_sql_user

        # Get sql password.
        data "Stored db admin password: $sql_password"
        prompt_continue "Use stored password? (Y|n): " || get_sql_password

        # Get db admin user.
        if [[ -z $user ]]; then
            get_user
        else
            data "Stored MyGeotab admin user: $user"
            prompt_continue "Use stored user? (Y|n): " || get_user
        fi

        # Get db admin passord
        if [[ -z $password ]]; then
            get_password
        else
            data "Stored MyGeotab admin password: $password"
            prompt_continue "Use stored password? (Y|n): " || get_password
        fi
    fi

    # path=$HOME/repos/MyGeotab/Checkmate/bin/Debug/netcoreapp3.1

    if ! geo_check_for_dev_repo_dir; then
        Error "Unable to init db: can't find CheckmateServer.dll. Run 'geo db init' to try again on a running db container."
        return 1
    fi

    local path=''
    geo_get_checkmate_dll_path $acceptDefaults
    path=$prompt_return

    [ $acceptDefaults ] && sleep 5

    info 'Waiting for db to start...'

    sleep 5

    if dotnet "${path}" CreateDatabase postgres companyName="$db_name" administratorUser="$user" administratorPassword="$password" sqluser="$sql_user" sqlpassword="$sql_password" useMasterLogin='true'; then
        success "$db_name initialized"
        info_bi 'Connect with pgAdmin (if not already set up)'
        info 'Create a new server and entering the following information:'
        info "  Name: db (or whatever you want)"
        info "  Host: 127.0.0.1"
        info "  Username: $sql_user"
        info "  Password: $sql_password"
        echo
        info_bi "Use geotabdemo"
        info "1. Run MyGeotab.Core in your IDE"
        info "2. Navigate to https://localhost:10001"
        info "3. Log in using:"
        info "  User: $user"
        info "  Password: $password"
    else
        Error 'Failed to initialize db'
        error 'Have you built the assembly for the current branch?'
        return 1
    fi
}

geo_db_rm() {
    if [[ $1 =~ ^-*a(ll)? ]]; then
        prompt_continue "Do you want to remove all db contaners? (Y|n): " || return
        # Get list of contianer names
        names=$(docker container ls -a -f name=geo_cli --format "{{.Names}}")
        # ids=`docker container ls -a -f name=geo_cli --format "{{.ID}}"`
        # echo "$ids" | xargs docker container rm
        local fail_count=0
        for name in $names; do
            # Remove image prefix from container name; leaving just the version/identier (e.g. geo_cli_db_postgres11_2008 => 2008).
            geo_db_rm -n "$name" || ((fail_count++))

            # geo_db_rm "${name#${IMAGE}_}"
            # echo "${name#${IMAGE}_}"
        done
        local num_dbs=$(echo "$names" | wc -l)
        num_dbs=$((num_dbs - fail_count))
        success "Removed $num_dbs dbs"
        [[ fail_count -gt 0 ]] && error "Failed to remove $fail_count dbs"
        return
    fi

    local container_name
    local db_name="$(geo_make_alphanumeric $1)"
    # If the -n option is present, the full container name is passed in as an argument (e.g. geo_cli_db_postgres11_2101). Otherwise, the db name is passed in (e.g., 2101)
    if [[ $1 == -n ]]; then
        container_name="$2"
        db_name="${2#${IMAGE}_}"
        shift
    else
        container_name=$(geo_container_name "$db_name")
    fi

    local container_id=$(geo_get_running_container_id "$container_name")

    if [[ -n "$container_id" ]]; then
        docker stop $container_id >/dev/null && success "Container stopped"
    fi

    # Remove multiple containers if more than one container name was passed in (i.e., geo db rm 8.0 9.0).
    if [[ -n $1 && -n $2 ]]; then
        debug 'Removing multiple containers'
        while [[ -n $1 ]]; do
            geo_db_rm $1
            shift
        done
        return
    fi

    # container_name=bad

    if docker container rm $container_name >/dev/null; then
        success "Container $db_name removed"
    else
        Error "Could not remove container $container_name"
        return 1
    fi

    # Check if the volume has the old container prefix.
    local volume_name=$(docker volume ls -f name=geo_cli --format '{{.Name}}' | grep $container_name'$')
    if [[ -z $volume_name ]]; then
        old_container_prefix='geo_cli_db_postgres11_'
        volume_name=$(docker volume ls -f name=geo_cli --format '{{.Name}}' | grep "${old_container_prefix}${db_name}"'$')
    fi

    if docker volume rm $volume_name >/dev/null; then
        success "Volume $db_name removed"
    else
        Error "Could not remove volume $volume_name"
        return 1
    fi

}

geo_get_checkmate_dll_path() {
    local dev_repo=$(geo_get DEV_REPO_DIR)
    local output_dir="${dev_repo}/Checkmate/bin/Debug"
    local acceptDefaults=$1
    # Get full path of CheckmateServer.dll files, sorted from newest to oldest.
    local files="$(find $output_dir -maxdepth 2 -name "CheckmateServer.dll" -print0 | xargs -r -0 ls -1 -t | tr '\n' ':')"
    local ifs=$IFS
    IFS=:
    read -r -a paths <<<"$files"
    IFS=$ifs
    local number_of_paths=${#paths[@]}
    [[ $number_of_paths = 0 ]] && Error "No output directories could be found in ${output_dir}. These folders should exist and contain CheckmateServer.dll. Build MyGeotab and try again."

    if [[ $number_of_paths -gt 1 ]]; then
        warn "Multiple CheckmateServer.dll output directories exist."
        info_bi "Available executables in directory $(txt_italic "${output_dir}"):"
        local i=0

        data_header "  Id    Directory                                      "
        for d in "${paths[@]}"; do
            local line="  ${i}    ...${d##*Debug}"
            [ $i = 0 ] && line="${line}   $(info_bi -p '(NEWEST)')"
            data "$line"
            ((i++))
        done

        if [ $acceptDefaults ]; then
            info 'Using newest'
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

geo_check_for_dev_repo_dir() {
    local dev_repo=$(geo_get DEV_REPO_DIR)

    is_valid_repo_dir() {
        test -d "${1}/Checkmate"
    }

    get_dev_repo_dir() {
        prompt 'Enter the full path (e.g. ~/repos/Development or /home/username/repos/Development) to the Development repo directory. This directory must contain the Checkmate directory (Type "--" to skip for now):'
        read dev_repo
        # Expand home directory (i.e. ~/repo to /home/user/repo).
        dev_repo=${dev_repo/\~/$HOME}
        if [[ ! -d $dev_repo ]]; then
            warn "The provided path is not a directory"
            return 1
        fi
        if [[ ! -d "$dev_repo/Checkmate" ]]; then
            warn "The provided path does not contain the Checkmate directory"
            return 1
        fi
        echo $dev_repo
    }

    # Ask repeatedly for the dev repo dir until a valid one is provided.
    while ! is_valid_repo_dir "$dev_repo" && [[ "$dev_repo" != -- ]]; do
        get_dev_repo_dir
    done

    [[ "$dev_repo" == -- ]] && return
    
    success "Checkmate directory found"
    geo_set DEV_REPO_DIR "$dev_repo"
}

##########################################################
COMMANDS+=('ar')
geo_ar_doc() {
    doc_cmd 'ar'
    doc_cmd_desc 'Helpers for working with access requests.'
    doc_cmd_sub_cmds_title
        doc_cmd_sub_cmd 'create'
            doc_cmd_sub_cmd_desc 'Opens up the My Access Request page on the MyAdmin website in Chrome.'
        doc_cmd_sub_cmd 'tunnel [gcloud start-iap-tunnel cmd]'
            doc_cmd_sub_cmd_desc "Starts the IAP tunnel (using the gcloud start-iap-tunnel command copied from MyAdmin after opening 
                            an access request) and then connects to the server over SSH. The port is saved and used when you SSH to the server using $(green 'geo ar ssh'). 
                            This command will be saved and re-used next time you call the command without any arguments (i.e. $(green geo ar tunnel))"
            doc_cmd_sub_options_title
            doc_cmd_sub_option '-s'
            doc_cmd_sub_option_desc "Only start the IAP tunnel without SSHing into it."
            doc_cmd_sub_option '-l'
            doc_cmd_sub_option_desc "List and choose from previous IAP tunnel commands."
            # doc_cmd_sub_option_desc "Starts an SSH session to the server immediately after opening up the IAP tunnel."
        doc_cmd_sub_cmd 'ssh'
            doc_cmd_sub_cmd_desc "SSH into a server through the IAP tunnel started with $(green 'geo ar ssh')."
            doc_cmd_sub_options_title
            doc_cmd_sub_option '-p <port>'
            doc_cmd_sub_option_desc "The port to use when connecting to the server. This value is optional since the port that the IAP tunnel was opened on using $(green 'geo ar ssh') is used as the default value"
            doc_cmd_sub_option '-u <user>'
            doc_cmd_sub_option_desc "The user to use when connecting to the server. This value is optional since the username stored in \$USER is used as the default value. The value supplied here will be stored and reused next time you call the command"
    doc_cmd_examples_title
        doc_cmd_example 'geo ar tunnel -s gcloud compute start-iap-tunnel gceseropst4-20220109062647 22 --project=geotab-serverops --zone=projects/709472407379/zones/northamerica-northeast1-b'
        doc_cmd_example 'geo ar ssh'
        doc_cmd_example 'geo ar ssh -p 12345'
        doc_cmd_example 'geo ar ssh -u dawsonmyers'
        doc_cmd_example 'geo ar ssh -u dawsonmyers -p 12345'
}
geo_ar() {
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
                while [[ $1 =~ ^- ]]; do
                    case "$1" in
                        -s ) start_ssh= ;;
                        --prompt ) prompt_for_cmd='true' ;;
                        -l ) list_previous_cmds='true' ;;
                        * ) Error "Unknown option '$1'" && return 1 ;;
                    esac    
                    shift
                done

                local gcloud_cmd="$*"
                local expected_cmd_start='gcloud compute start-iap-tunnel'
                local prompt_txt='Enter the gcloud IAP command that was copied from your MyAdmin access request:'
                if [[ $prompt_for_cmd == true ]]; then
                    prompt_for_info "$prompt_txt"
                    gcloud_cmd="$prompt_return"
                fi

                if [[ $list_previous_cmds == true ]]; then
                    local prev_commands=$(_geo_ar_get_cmd_tags | tr '\n' ' ')
                    # debug "$prev_commands"
                    if [[ -n $prev_commands ]]; then
                        status -bi 'Enter the number for the gcloud IAP command you want to use:'
                        select tag in $prev_commands; do
                            [[ -z $tag ]] && warn "Invalid command number" && continue
                            gcloud_cmd=$(_geo_ar_get_cmd_from_tag $tag)
                            # debug "gcloud_cmd: $gcloud_cmd"
                            # debug "tag: $tag"
                            break
                        done
                    else
                        warn "'-l' option supplied, but there arn't any previous comands stored to choose from."
                    fi
                fi

                # debug $gcloud_cmd
                [[ -z $gcloud_cmd ]] && gcloud_cmd="$(geo_get AR_IAP_CMD)"
                [[ -z $gcloud_cmd ]] && Error 'The gcloud compute start-iap-tunnel command (copied from MyAdmin for your access request) is required.' && return 1
                
                while [[ ! $gcloud_cmd =~ ^$expected_cmd_start ]]; do
                    warn -b "The command must start with 'gcloud compute start-iap-tunnel'"
                    prompt_for_info "$prompt_txt"
                    gcloud_cmd="$prompt_return"
                done

                geo_set AR_IAP_CMD "$gcloud_cmd"
                _geo_ar_push_cmd "$gcloud_cmd"
                
                local open_port=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')
                [[ -z $open_port ]] && Error 'Open port could not be found' && return 1

                local port_arg='--local-host-port=localhost:'$open_port
                
                geo_set AR_PORT "$open_port"
                status -bu 'Opening IAP tunnel'
                info "Using port: '$open_port' to open IAP tunnel"
                info "Note: the port is saved and will be used when you call '$(txt_italic geo ar ssh)'"
                echo
                debug $gcloud_cmd $port_arg
                sleep 1
                echo

                if [[ $start_ssh ]]; then
                    cleanup() {
                        echo
                        # status 'Closing IAP tunnel'
                        kill %1
                        exit
                    }
                    # Catch signals and run cleanup function to make sure the IAP tunnel is closed.
                    trap cleanup INT TERM QUIT EXIT
                    # Start up IAP tunnel in the background.
                    $gcloud_cmd $port_arg &
                    # Wait for the tunnel to start.
                    status 'Waiting for tunnel to open before stating SSH session...'
                    echo
                    sleep 4
                    # Continuously ask the user to re-open the ssh session (until ctrl + C is pressed, killing the tunnel).
                    # This allows users to easily re-connect to the server after the session times out.
                    # The -n option tells geo ar ssh not to store the port; the -p option specifies the ssh port.
                    geo_ar ssh -n -p $open_port
                    
                    fg
                else
                    $gcloud_cmd $port_arg
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

            while [[ ${1:0:1} == - ]]; do
                # debug "option $1"
                # Don't save port/user if -n (no save) option supplied. This option is used in geo ar tunnel so that re-opening
                # an SSH session doesn't overwrite the most recent port (from the newest IAP tunnel, which may be different from this one).
                [[ $1 == '-n' ]] && save= && shift
                # The -r option will cause the ssh tunnel to run ('r' for run) once and then return without looping. 
                [[ $1 == '-r' ]] && loop=false && shift
                [[ $1 == '-p' ]] && port=$2 && shift 2 && ((option_count++))
                [[ $1 == '-u' ]] && user=$2 && shift 2 && ((option_count++))
            done

            [[ -z $port ]] && Error "No port found. Add a port with the -p <port> option." && return 1
            
            echo
            status -bu 'Opening SSH session'
            info "Using user '$user' and port '$port' to open SSH session."

            [[ $option_count == 0 ]] && info "Note: The -u <user> or the -p <port> options can be used to supply different values."
            echo

            if [[ $save == true ]]; then
                geo_set AR_USER "$user"
                geo_set AR_PORT "$port"
            fi

            local cmd="ssh $user@localhost -p $port"
            
            # Run the ssh command once and then return if loop was disabled (with the -r option)
            if [[ $loop == false ]]; then
                debug "$cmd"
                echo
                $cmd
                return
            fi
            
            # Continuously ask the user to re-open the ssh session (until ctrl + C is pressed, killing the tunnel).
            # This allows users to easily re-connect to the server after the session times out.
            while true; do
                debug "$cmd"
                echo
                sleep 1
                # Run ssh command.
                $cmd
                echo
                sleep 1
                status -bu 'SSH closed'
                info 'Options:'
                info '    - Press ENTER to SSH back into the server'
                info '    - Press CTRL + C to close this tunnel (running on port: '$open_port
                info '    - Open a new terminal and run '$(txt_italic geo ar ssh)' to reconnect to this tunnel'
                # status 'SSH closed. Listening to IAP tunnel again. Open a new terminal and run "geo ar ssh" to reconnect to this tunnel.'
                read response
                status -bu 'Reopening SSH session'
                echo
                sleep 1
            done
            ;;
        *)
            Error "Unknown subcommand '$1'"
            ;;
    esac
}

# Save the previous 5 gcloud commands as a single value in the config file, delimited by the '@' character.
_geo_ar_push_cmd() {
    local cmd="$1"
    [[ -z $cmd ]] && return 1
    local prev_commands="$(geo_get AR_IAP_CMDS)"

    if [[ -z $prev_commands ]]; then
        debug "_geo_ar_push_cmd: cmds was empty"
        geo_set AR_IAP_CMDS "$cmd"
        return
    fi
    # Remove duplicates if cmd is already stored.
    prev_commands="${prev_commands//$cmd/}"
    # Remove any delimiters left over from removed commands.
    # The patterns remove lead and trailing @, as well as replaces 2 or more @ with a single one (3 patterns total).
    prev_commands=$(echo $prev_commands | sed -r 's/^@//; s/@$//; s/@{2,}/@/g')

    if [[ -z $prev_commands ]]; then
        Error "_geo_ar_push_cmd[$LINENO]: cmds was empty"
        return
    fi
    # Add the new command to the beginning, delimiting it with the '@' character.
    prev_commands="$cmd@$prev_commands"
    # Get the count of how many commands there are.
    local count=$(echo $prev_commands | awk -F '@' '{ print NF }')
#    debug $count
    if (( count > 5 )); then
        # Remove the oldest command, keeping only 5.
        prev_commands=$(echo $prev_commands | awk -F '@' '{ print $1"@"$2"@"$3"@"$4"@"$5 }')
    fi
#    debug geo_set AR_IAP_CMDS "_geo_ar_push_cmd: setting cmds to: $prev_commands"
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
    [[ -z $cmd_number || $cmd_number -gt 5 || $cmd_number -lt 0 ]] && Error "Invalid command number. Expected a value between 0 and 5." && return 1
    
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
#     #         #     Error "Invalid option: -$OPTARG"
#     #         #     return 1
#     #         #     ;;
#     #         :) # If expected argument omitted:
#     #             echo "Error: -${OPTARG} requires an argument."
#     #             ;;
#     #         *) warn "Unknown argument " ;;
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

###########################################################
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

###########################################################
COMMANDS+=('init')
geo_init_doc() {
    doc_cmd 'init'
    doc_cmd_desc 'Initialize repo directory.'

    doc_cmd_sub_cmds_title
        doc_cmd_sub_cmd 'repo'
            doc_cmd_sub_cmd_desc 'Init Development repo directory using the current directory.'
        doc_cmd_sub_cmd 'npm'
            doc_cmd_sub_cmd_desc "Runs 'npm install' in both the wwwroot and drive CheckmateServer directories. This is quick way to fix the npm dependencies after Switching to a different MYG release branch."

    doc_cmd_examples_title
        doc_cmd_example 'geo init repo'
        doc_cmd_example 'geo init npm'
}
geo_init() {
    if [[ "$1" == '--' ]]; then shift; fi

    case $1 in
    'repo' | '')
        local repo_dir=$(pwd)
        if ! geo_is_valid_repo_dir "$repo_dir"; then
            Error "The current directory does not contain the Development repo since it is missing the Checkmate folder."
            return
        fi
        local current_repo_dir=$(geo_get DEV_REPO_DIR)
        if [[ -n $current_repo_dir ]]; then
            info_bi "The current Development repo directory is:"
            info "    $current_repo_dir"
            if ! prompt_continue "Would you like to replace that with the current directory? (Y|n): "; then
                return
            fi
        fi
        geo_set DEV_REPO_DIR "$repo_dir"
        status "MyGeotab base repo (Development) path set to:"
        detail "    $repo_dir"
        ;;
    # npmi )
    #     (
    #         cd ~/test
    #         npm i || Error "npm install failed" && return 1

    #     )
    #     ;;
    npm )
        local close_delayed=false
        local arg="$2"
        [[ $arg == -c ]] && close_delayed=true
        (
            local fail_count=0

            local current_repo_dir=$(geo_get DEV_REPO_DIR)
            [[ -z $current_repo_dir ]] && Error "MyGeotab repo directory not set." && return 1

            cd $current_repo_dir/Checkmate/CheckmateServer/src/wwwroot
            # echo
            status -b '\nInstalling npm packages for CheckmateServer/src/wwwroot\n'
            npm i || ((fail_count++))
            status -b '\nInstalling npm packages for CheckmateServer/src/wwwroot/drive\n'
            cd drive
            npm i || ((fail_count++))
            # debug "fail $fail_count"
            ((fail_count == 0))
        )
        
        if [[ $? != 0 ]]; then
            Error "npm install failed $"
            if [[ $close_delayed == true ]]; then
                detail 'Press Enter to exit'
                read
                exit 1
            fi
            return 1
        fi

        success 'npm install was successful'
        if [[ $close_delayed == true ]]; then
            detail 'closing in 5 seconds'
            sleep 5
            exit 0
        fi
        ;;
    esac
}

###########################################################
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
#         Error "$1 is not a service"
#     fi
# }

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
#         Error "$1 is not a service"
#     fi
# }

###########################################################
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
#         Error "$1 is not a service"
#     fi
# }

##########################################################
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
        geo_haskey "$2" || (Error "Key '$2' does not exist." && return 1)
        geo_get "$2"
        ;;
    'rm')
        # Show error message if the key doesn't exist.
        geo_haskey "$2" || (Error "Key '$2' does not exist." && return 1)
        geo_rm "$2"
        ;;
    'ls')
        if [[ $2 == keys ]]; then
            awk -F= '{ gsub("GEO_CLI_","",$1); printf "%s ",$1 } ' $GEO_CLI_CONF_FILE | sort
            return
        fi
        local header=$(printf "%-26s %-26s\n" 'Variable' 'Value')
        local env_vars=$(awk -F= '{ gsub("GEO_CLI_","",$1); printf "%-26s %-26s\n",$1,$2 } ' $GEO_CLI_CONF_FILE | sort)
        info_bi "$header"
        data "$env_vars"
        ;;
    *)
        Error "Unknown subcommand '$1'"
        ;;
    esac
}

###########################################################
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
            (( $? != 0 )) && Error "'geo set' failed to lock config file after timeout. Key: $geo_key, value: $value." && return 1
            # Write to the file atomically.
            cfg_write $GEO_CLI_CONF_FILE "$geo_key" "$value"
        # Open up the lock file for writing on file descriptor 200. The lock is release as soon as the subshell exits.
        ) 200> /tmp/.geo.conf.lock
        [[ $? != 0 ]] && return 1
    fi
        

    # local final_line_count=$(wc -l $GEO_CLI_CONF_FILE | awk '{print $1}')

    # debug "$initial_line_count, $final_line_count"
    # debug "$conf_backup"
    # Restore original configuration file and try to write to it again. The conf file can be corrupted
    # if two processes try to write to it at the same time.
    # if (( final_line_count < initial_line_count )); then
    #     echo "$conf_backup" > $GEO_CLI_CONF_FILE
    #     [[ $value_changed == true ]] && cfg_write $GEO_CLI_CONF_FILE "$geo_key" "$value"
    # fi

    if [[ $show_status == true ]]; then
        info_bi "$key"
        info -p '  New value: ' && data "$value"
        if [[ -n $old ]]; then
            info -p '  Old value: ' && data "$old"
        fi
    fi
}

###########################################################
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

###########################################################
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
        (( $? != 0 )) && Error "'geo rm' failed to lock config file after timeout. Key: $key" && return 1
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
    [[ -z $key ]] && Error "_geo_push: Key cannot be empty" && return 1
    [[ -z $value ]] && Error "_geo_push: Value cannot be empty" && return 1
    local stored_items="$(geo_get $key)"

    if [[ -z $stored_items ]]; then
        # debug "_geo_push: stored_items was empty"
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
#    debug $count
    if (( count > 5 )); then
        # Remove the oldest item, keeping only 5.
        stored_items=$(echo $stored_items | awk -F '@' '{ print $1"@"$2"@"$3"@"$4"@"$5 }')
    fi
#    debug geo_set $key "_geo_push: setting cmds to: $stored_items"
    geo_set $key "$stored_items"
}

_geo_push_get_items() {
    [[ -z $1 ]] && return
    geo get $1 | tr '@' '\n'
}

_geo_push_get_item() {
    local key="$1"
    local item_number="$2"
    [[ -z $item_number || $item_number -gt 5 || $item_number -lt 0 ]] && Error "Invalid command number. Expected a value between 0 and 5." && return 1
    
    local items=$(geo_get $key)
    if [[ -z $items ]]; then
        return
    fi
    local awk_cmd='{ print $'$item_number' }'
    echo $(echo $items | awk -F '@' "$awk_cmd")
}

###########################################################
COMMANDS+=('update')
geo_update_doc() {
    doc_cmd 'update'
        doc_cmd_desc 'Update geo to latest version.'
    doc_cmd_options_title
        doc_cmd_option '-f, --force'
            doc_cmd_sub_option_desc 'Force update, even if already at latest version.'
    doc_cmd_examples_title
        doc_cmd_example 'geo update'
        doc_cmd_example 'geo update --force'
}
geo_update() {
    # Don't install if already at latest version unless the force flag is present (-f or --force)
    if ! geo_check_for_updates && [[ $1 != '-f' && $1 != '--force' ]]; then
        Error 'The latest version of geo-cli is already installed'
        return 1
    fi

    local geo_cli_dir="$(geo_get GEO_CLI_DIR)"
    local prev_commit="$(geo_get GIT_PREVIOUS_COMMIT)"
    local new_commit=
    
    (
        cd $geo_cli_dir
        [[ -z $prev_commit ]] && prev_commit=$(git rev-parse HEAD)
        if ! git pull >/dev/null; then
            Error 'Unable to pull changes from remote'
            return 1
        fi
        new_commit=$(git rev-parse HEAD)
        bash $geo_cli_dir/install.sh $prev_commit $new_commit
        geo_set GIT_PREVIOUS_COMMIT "$new_commit"
    )
    # debug "$prev_commit $new_commit"
    
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
                Error "Failed to checkout main"
                return 1
            fi
            if ! git pull; then
                Error "Failed to pull changes from main"
                return 1
            fi
        )
        return $?
    else
        warn "This feature branch is no longer being maintained. You should switch back to the main branch ASAP."
    fi
    return 1
}

###########################################################
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

    success OK
    info 'geo-cli will not be loaded into any new terminals.'
    info "Navigate to the geo-cli repo directory and run 'bash install.sh' to reinstall it."
}

###########################################################
COMMANDS+=('analyze')
geo_analyze_doc() {
    doc_cmd 'analyze [option or analyzerIds]'
    doc_cmd_desc 'Allows you to select and run various pre-build analyzers. You can optionally include the list of analyzers if already known.'

    doc_cmd_options_title
        doc_cmd_option -a
            doc_cmd_option_desc 'Run all analyzers'
        doc_cmd_option -
            doc_cmd_option_desc 'Run previous analyzers'
        doc_cmd_option -b
            doc_cmd_option_desc 'Run analyzers in batches (reduces runtime, but is only supported in 2104+)'
    # doc_cmd_option -i
    # doc_cmd_option_desc 'Run analyzers individually (building each time)'

    doc_cmd_examples_title
        doc_cmd_example 'geo analyze'
        doc_cmd_example 'geo analyze -a'
        doc_cmd_example 'geo analyze 0 3 6'
}
geo_analyze() {
    MYG_CORE_PROJ='Checkmate/MyGeotab.Core.csproj'
    MYG_TEST_PROJ='Checkmate/MyGeotab.Core.Tests/MyGeotab.Core.Tests.csproj'
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
    )
    local len=${#analyzers[@]}
    local max_id=$((len - 1))
    local name=0
    local proj=1
    # Print header for analyzer table. Which has two columns, ID and Name.
    data_header "$(printf '%-4s %-38s %-8s\n' ID Name Project)"
    # Print each analyzer's id and name.
    for ((id = 0; id < len; id++)); do
        # Convert a string containing "name project" into an array [name, project] so that name can be printed with its id.
        read -r -a analyzer <<<"${analyzers[$id]}"
        local project="$(info_bi Core)"
        [[ ${analyzer[$proj]} == $MYG_TEST_PROJ ]] && project=$(info 'Test')

        printf '%-4d %-38s %-8s\n' $id "${analyzer[$name]}" "$project"
    done
    local dev_repo=$(geo_get DEV_REPO_DIR)
    local prev_ids=$(geo_get ANALYZER_IDS)
    
    status "Valid IDs from 0 to ${max_id}"
    local prompt_txt='Enter the analyzer IDs that you would like to run (separated by spaces): '

    local valid_input=false
    local ids=

    # Default to running individually until cmd test batching is supported in more releases currently only 2104.
    local run_individually=true

    local OPTIND
    while getopts "ab" opt; do
        case "${opt}" in
            # Check if the run all analyzers option (-a) was supplied.
            a )
                ids=$(seq -s ' ' 0 $max_id)
                echo
                status_bi 'Running all analyzers'
                ;;
            # Check if the run individually option (-i) was supplied.
            # -i ) run_individually=true ;;
            # Check if the batch run option (-b) was supplied.
            b )
                run_individually=false
                echo
                status_bi 'Running analyzers in batches'
                echo
                ;;
            \? )
                Error "Invalid option: $1"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    # Check if the run previous analyzers option (-) was supplied.
    if [[ $1 =~ ^-$ ]]; then
        ids=$(geo_get ANALYZER_IDS)
        [[ -n $ids ]] && echo && status "Using previous analyzer id(s): $ids"
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
                error "Invalid ID: ${id}. Only IDs from 0 to ${max_id} are valid"
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
        [[ -n $prev_ids ]] && status "Enter '-' to reuse previous ids: '$prev_ids'" && echo
        prompt_for_info "$prompt_txt"
        [[ $prompt_return == - ]] && prompt_return="$prev_ids"
        # Make sure the input consists of only numbers separated by spaces.
        while [[ ! $prompt_return =~ ^( *[0-9]+ *)+$ ]]; do
            error 'Invalid input. Only space-separated integer IDs are accepted'
            prompt_for_info "$prompt_txt"
        done
        # Make sure the numbers are valid ids between 0 and max_id.
        for id in $prompt_return; do
            if ((id < 0 | id > max_id)); then
                error "Invalid ID: ${id}. Only IDs from 0 to ${max_id} are valid"
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
            warn "Press 'ctrl + \' to abort analyzers"

            if [[ $run_individually = false ]]; then
                local core_analyzers=
                local core_analyzers_count=0
                local core_analyzers_result=
                local test_analyzers=
                local test_analyzers_count=0
                local test_analyzers_result=
                for id in $ids; do
                    # echo $id
                    read -r -a analyzer <<<"${analyzers[$id]}"
                    analyzer_name="${analyzer[$name]}"
                    analyzer_proj="${analyzer[$proj]}"
                    if [[ $analyzer_proj == $MYG_CORE_PROJ ]]; then
                        ((core_analyzers_count++))
                        core_analyzers+="$analyzer_name "
                    else
                        ((test_analyzers_count++))
                        test_analyzers+="$analyzer_name "
                    fi
                done

                print_analyzers() {
                    for analyzer in $1; do status_i "  * $analyzer"; done
                }

                local run_core=true
                local run_test=true
                case "$run_project_only" in
                'core' )
                    run_test='false'
                    test_analyzers_result='NOT RUN'
                    echo
                    status_bi 'Running Core project tests only'
                    ;;
                'test' )
                    run_core='false'
                    core_analyzers_result='NOT RUN'
                    echo
                    status_bi 'Running Core.Tests project tests only'
                    ;;
                esac

                if [[ $core_analyzers_count -gt 0 && $run_core == 'true' ]]; then
                    echo
                    status_bi "Running the following $core_analyzers_count analyzer(s) against MyGeotab.Core:"
                    print_analyzers "$core_analyzers"
                    echo

                    if ! dotnet build -p:DebugAnalyzers="${core_analyzers}" -p:TreatWarningsAsErrors=false -p:RunAnalyzersDuringBuild=true ${MYG_CORE_PROJ}; then
                        echo
                        Error "Running MyGeotab.Core analyzer(s) failed"
                        core_analyzers_result=$(red FAIL)
                    else
                        success 'MyGeotab.Core analyzer(s) done'
                        core_analyzers_result=$(green PASS)
                    fi
                fi

                if [[ $test_analyzers_count -gt 0 && $run_test == 'true' ]]; then
                    echo
                    status_bi "Running the following $test_analyzers_count analyzer(s) against MyGeotab.Core.Tests:"
                    print_analyzers "$test_analyzers"
                    echo

                    if ! dotnet build -p:DebugAnalyzers="${test_analyzers}" -p:TreatWarningsAsErrors=false -p:RunAnalyzersDuringBuild=true ${MYG_TEST_PROJ}; then
                        echo
                        Error "Running MyGeotab.Core.Tests analyzer(s) failed"
                        test_analyzers_result=$(red FAIL)
                    else
                        success 'MyGeotab.Core.Tests analyzer(s) done'
                        test_analyzers_result=$(green PASS)
                    fi
                fi

                echo
                info -b 'Results'
                data_header 'Project                     Status'
                data "MyGeotab.Core               $core_analyzers_result"
                data "MyGeotab.Core.Tests         $test_analyzers_result"
                echo
                info_b 'The total time was:'
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
                    warn "$fail_count failed test$([[ $fail_count -gt 1 ]] && echo s) so far"
                fi
                echo
                status_bi "Running ($((run_count++)) of $id_count): $analyzer_name"
                echo

                dotnet build -p:DebugAnalyzers=${analyzer_name} -p:TreatWarningsAsErrors=false -p:RunAnalyzersDuringBuild=true ${analyzer_proj}

                # Check the return code to see if there were any errors.
                if [[ $? != 0 ]]; then
                    echo
                    Error "$analyzer_name failed"
                    ((fail_count++))
                    failed_tests+="  *  $analyzer_name\n"
                else
                    success 'Analyzer done'
                fi
            done

            echo

            if [[ $fail_count -gt 0 ]]; then
                warn "$fail_count out of $id_count analyzers failed. The following analyzers failed:"
                failed_tests=$(echo -e "$failed_tests")
                detail "$failed_tests"
            else
                success 'All analyzers completed successfully'
            fi
            echo
            info_b 'The total time was:'
        }

        time run_analyzers

        echo
    )
}

###########################################################
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
  
    convert_id() {
        arg=${1:-$arg}
        local first_char=${arg:0:1}
        # debug "arg='$arg'"
        # Guid encode.
        if [[ $arg =~ $guid_re || $arg =~ $guid_re_no_dashes ]]; then
            if [[ ${#arg} -ne 36 && ${#arg} -ne 32 ]]; then
                Error "Invalid input format."
                warn "Guid ids must be 36 characters long. The input string length was ${#arg}"
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
                 Error "Invalid input format."
                 warn "Guid encoded ids must be prefixed with 'a' and be 23 characters long."
                 [[ ${#arg} -ne 23 ]] && warn "The input string length was: ${#arg}"
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
            Error "Invalid input format. Length: ${#arg}, input: '$arg'"
            warn "Guid ids must be 36 characters long."
            warn "Encoded guid ids must be prefixed with 'a' and be 23 characters long."
            warn "Encoded long ids must be prefixed with 'b'."
            warn "Use 'geo id help' for usage info."
            return 1
        fi
    }
    
    if [[ $interactive == true || $use_clipboard == true ]]; then
        clipboard=$(xclip -o)
        # debug "Clip $clipboard"
        local valid_id_re='^[a-zA-Z0-9_-]{1,36}$'
        # [[ $clipboard =~ $valid_id_re]]
        # First try to convert the contents of the clipboard as an id.
        if [[ -n $clipboard && ${#clipboard} -le 36 ]]; then
            # [[ $clipboard =~ $valid_id_re ]]
            # geo_id $clipboard
            # debug "Clip $clipboard"
            output=$(convert_id $clipboard)
            # debug $output

            if [[ $output =~ Error ]]; then
                detail 'No valid ID in clipboard'
            else
                detail "Converting the following id from clipboard: $clipboard"
                geo_id $clipboard
                echo
            fi
        fi

        if [[ $use_clipboard == true ]]; then
            detail 'closing in 5 seconds'
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
        return 1
    fi
    [[ $format_output == true ]] && status "$msg: "
    [[ $format_output == true ]] && detail -b $id || echo -n $id
    if ! type xclip > /dev/null; then
        warn 'Install xclip (sudo apt-get instal xclip) in order to have the id copied to your clipboard.'
        return
    fi
    echo -n $id | xclip -selection c
    [[ $format_output == true ]] && info "copied to clipboard"
}

###########################################################
COMMANDS+=('version')
geo_version_doc() {
    doc_cmd 'version, -v, --version'
    doc_cmd_desc 'Gets geo-cli version.'

    doc_cmd_examples_title
    doc_cmd_example 'geo version'
}
geo_version() {
    verbose $(geo_get VERSION)
}

###########################################################
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
                Error "Development repo not set."
                return 1
            fi
            cd "$path"
            ;;
        geo | cli)
            local path=$(geo_get DIR)
            if [[ -z $path ]]; then
                Error "geo-cli directory not set."
                return 1
            fi
            cd "$path"
            ;;
        *)
            Error "Unknown subcommand '$1'"
            ;;
    esac
}

###########################################################
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
    doc_cmd_examples_title
    doc_cmd_example 'geo indicator enable'
    doc_cmd_example 'geo indicator disable'
}
geo_indicator() {
    local running_in_headless_ubuntu=$(dpkg -l ubuntu-desktop | grep 'no packages found')
    if [[ -n $running_in_headless_ubuntu ]]; then
        Error 'Cannot use geo-cli indicator with headless versions of Ubuntu.'
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
            status -b "Enabling app indicator"
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
                Error "App indicator script not found at '$init_script_path'"
                return 1
            fi
            if [[ ! -f $service_file_path ]]; then
                Error "App indicator service file not found at '$service_file_path'"
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
            success 'Indicator disabled'
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
            [[ $indicator_enabled == false ]] && detail "Indicator is disabled. Run $(txt_underline geo indicator enable) to enable it.\n" && return
            geo_indicator enable
            ;;
        *)
            Error "Unknown argument: '$1'"
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
    [[ -z $pkg_name ]] && warn 'No package name supplied' && return 1

    if ! dpkg -l $pkg_name &> /dev/null; then
        status "Installing missing package: $pkg_name"
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

###########################################################
COMMANDS+=('test')
geo_test_doc() {
    doc_cmd 'test <filter>'
        doc_cmd_desc 'Runs tests on the local build of MyGeotab.'

    doc_cmd_options_title
        doc_cmd_option '-d, --docker'
            doc_cmd_option_desc 'Run tests in a docker environment matching the one used in ci/cd pipelines. Requires docker to be logged into gitlab.'

    doc_cmd_examples_title
        doc_cmd_example 'geo test UserTest.AddDriverScopeTest'
        doc_cmd_example 'geo test "FullyQualifiedName=Geotab.Checkmate.ObjectModel.Tests.JSONSerializer.DisplayDiagnosticSerializerTest.DateRangeTest|FullyQualifiedName=Geotab.Checkmate.ObjectModel.Tests.JSONSerializer.DisplayDiagnosticSerializerTest.NotificationUserModifiedValueInfoTest"'
}
geo_test() {
    local dev_repo=$(geo_get DEV_REPO_DIR)
    local myg_tests_dir_path="${dev_repo}/Checkmate/MyGeotab.Core.Tests/"
    local script_path="${dev_repo}/gitlab-ci/scripts/StartDockerForTests.sh"
    local use_docker=false
    local interactive=false

    while [[ $1 =~ ^-+ ]]; do
        case "${1}" in
            -d | --docker ) 
                if [[ ! -f $script_path ]]; then
                    Error "Script to run ci docker environment locally not found in:\n  '${script_path}'."
                    warn "\nThis option is currently only supported for MyGeotab version 9.0 or later (current version is $(geo_dev release)). Running locally instead.\n"
                else
                    use_docker=true
                fi
                ;;
            -i ) interactive=true ;;
            * ) 
                Error "Invalid option: '$1'"
                return 1
                ;;
        esac
        shift
    done

    local test_filter="$1"

    if [[ $interactive == true ]]; then
        status -b "Example tests filters:"
        info "* UserTest.AddDriverScopeTest"
        local long_example="FullyQualifiedName=Geotab.Checkmate.ObjectModel.Tests.JSONSerializer\n .DisplayDiagnosticSerializerTest.DateRangeTest|FullyQualifiedName=Geotab..."
        info "* $long_example"
        echo

        local prev_tests=$(_geo_push_get_items TEST_FILTERS)
        local prev_tests_array=($prev_tests)
        local i=0
        if [[ -n $prev_tests ]]; then
            # select prev_test_filter in $prev_tests; do
            status -b "Previous test filters:"
            for filter in $prev_tests; do
                info "  ${i}) $filter"
                ((i++))
            done
            echo
            info "Reuse one of the above test filters by entering its id."
        fi
        prompt_for_info '\nEnter a test filter: '
        test_filter="$prompt_return"

        # Check if a previous test filter id was entered (a number prefixed with -, e.g., -1).
        if [[ $test_filter =~ ^[0-9] ]]; then
            # Trip the hyphen off the id.
            local i=${test_filter}
            # Get the test filter using the id as the index.
            test_filter=${prev_tests_array[i]}
            [[ -n $test_filter ]] && status "\nUsing test filter: $test_filter"
        fi
        [[ -z $test_filter ]] && Error "Test filter cannot be empty." && return 1


        if prompt_continue -n '\nRun tests in docker container\n(requires GitLab api access token, see Readme for setup instructions)?: (y|N) '; then
            if [[ ! -f $script_path ]]; then
                Error "Script to run ci docker environment locally not found in:\n  '${script_path}'."
                warn "\nThis option is currently only supported for MyGeotab version 9.0 or later (current version is $(geo_dev release)). Running locally instead.\n"
            else
                status '\nRunning in docker\n'
                use_docker=true
            fi
        else
            status '\nRunning locally\n'
        fi
    fi

    _geo_push TEST_FILTERS "$test_filter"

    # if [[ $1 == '-d' || $1 == '--docker' ]]; then
    #     shift
    #     if [[ ! -f $script_path ]]; then
    #         Error "Script to run ci docker environment locally not found in:\n  '${script_path}'."
    #         warn "\nThis option is currently only supported for MyGeotab version 9.0 or later (current version is $(geo_dev release)). Running locally instead.\n"
    #     else
    #         use_docker=true
    #     fi
    # fi
    if [[ $use_docker == true ]]; then
        local test_container_name="ci_test_container"
        $script_path $test_container_name
        docker exec -it $test_container_name /bin/bash -c "pushd MyGeotabRepository/publish; ./CheckmateServer.Tests --filter=\"${1}\""
    else
        (
            cd "$myg_tests_dir_path"
            if dotnet run --filter="${1}" --displayresults; then
                success 'OK'
            else
                Error 'dotnet run failed'
            fi
        )
    fi
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
}
geo_dev() {
    local geo_cli_dir="$(geo_get GEO_CLI_DIR)"
    local myg_dir="$(geo_get DEV_REPO_DIR)"
    local force_update_after_checkout=false
    [[ $1 == -u ]] && force_update_after_checkout=true && shift
    case "$1" in
        update-available )
            GEO_NO_UPDATE_CHECK=false
            if geo_check_for_updates; then
                status true
                return
            fi
            status false
            ;;
        co )
            local branch=
            local checkout_failed=false
            (
                cd $geo_cli_dir
                [[ $2 == - ]] && branch=master || branch="$2"
                git checkout "$branch" || Error 'Failed to checkout branch' && checkout_failed=true
            )
            [[ $checkout_failed == true ]] && return 1
            [[ $force_update_after_checkout == true ]] && geo_update -f
            ;;
        release )
            (
                cd $myg_dir
                local current_myg_release=$(git describe --tags --abbrev=0 --match MYG*)
                # Remove MYG/ prefix (present from 6.0 onwards).
                [[ $current_myg_release =~ ^MYG/ ]] && current_myg_release=${current_myg_release##*/}
                # Remove 5.7. prefix (present from 2104 and earlier).
                [[ $current_myg_release =~ ^5.7. ]] && current_myg_release=${current_myg_release##*.}
                echo -n $current_myg_release
            )
            ;;
        db|dbs|databases )
            echo $(docker container ls --filter name="geo_cli_db_"  -a --format="{{ .Names }}") | sed -e "s/geo_cli_db_postgres_//g"
            ;;
        auto-switch )
            _geo_auto_switch_server_config "$2" "$3"
            ;;
        *)
            Error "Unknown argument: '$1'"
            ;;
    esac
}


_geo_auto_switch_server_config() {
    local cur_myg_release=$1
    local prev_myg_release=$2
    local server_config_path="${HOME}/GEOTAB/Checkmate/server.config"
    local server_config_storage_path="${HOME}/.geo-cli/data/server-config"
    local server_config_backup_path="${HOME}/.geo-cli/data/server-config/backup"
    local prev_server_config_path="$server_config_storage_path/server.config_${prev_myg_release}"
    local next_server_config_name="server.config_${cur_myg_release}"
    local next_server_config_path="$server_config_storage_path/${next_server_config_name}"
    
    [[ -e $cur_myg_release || -e $prev_myg_release ]] && Error "cur_myg_release or prev_myg_release missing" && return 1

    if [[ ! -f $server_config_path ]]; then
        Error "server.config not found at path: '$server_config_path'"
        return 1
    fi

    if [[ ! -d $server_config_storage_path ]]; then
        mkdir -p "$server_config_storage_path"
    fi

    if [[ ! -d $server_config_backup_path ]]; then
        mkdir -p "$server_config_backup_path"
    fi

    # Copy server.config to storage.
    cp $server_config_path $prev_server_config_path

    # If there is a server.config in storage that matches the current myg version, switch it in now.
    if [[ -f $next_server_config_path ]]; then
        cp $next_server_config_path $server_config_path
        status "server.config replaced with '$next_server_config_path'"
    fi
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
    cmd=$(echo "${COMMANDS[@]}" | tr ' ' '\n' | grep -E "$(echo ^$1$)")
    echo $cmd
    [[ -n $cmd ]]
}

# Install Docker and Docker Compose if needed.
check_docker_installation() {
    if ! type docker > /dev/null; then
        warn 'Docker is not installed'
        info_b -p 'Install Docker and Docker Compose? (Y|n): '
        read answer
        if [[ ! $answer =~ [n|N] ]]; then
            info 'Installing Docker and Docker Compose'
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
            
            # Remove old version of docker-compose
            [ -f /usr/local/bin/docker-compose ] && sudo rm /usr/local/bin/docker-compose
            # Get the latest docker-compose version
            COMPOSE_VERSION=`git ls-remote https://github.com/docker/compose | grep refs/tags | grep -oE "[0-9]+\.[0-9][0-9]+\.[0-9]+$" | sort --version-sort | tail -n 1`
            sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION:-1.28.6}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            
            sudo apt-key fingerprint 0EBFCD88
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

            sudo apt-get update
            sudo apt-get install -y docker-ce

            # Add user to the docker group to allow docker to be run without sudo.
            sudo usermod -aG docker $USER
            sudo usermod -a -G docker $USER

            sudo chmod +x /usr/local/bin/docker-compose
            docker-compose --version

            warn 'You must completely log out of your account and log back in again to begin using docker.'
            success 'OK'
        fi
    fi
}

_geo_print_messages_between_commits_after_update() {
    [[ -z $1 || -z $2 ]] && return
    local prev_commit=$1
    local cur_commit=$2

    local geo_cli_dir="$(geo_get GEO_CLI_DIR)"
    
    (
        cd $geo_cli_dir
        local commit_msgs=$(git log --oneline --ancestry-path $prev_commit..$cur_commit)
        # debug "$commit_msgs"
        # Each line will look like this: a62b81f Fix geo id parsing order.
        [[ -z $commit_msgs ]] && return

        local line_count=0
        local max_lines=20

        info -b "What's new:"

        while read msg; do
            (( line_count++ ))
            (( line_count > max_lines )) && continue
            # Trim off commit hash (trim off everything up to the first space).
            msg=${msg#* };
            # Format the text (wrap long lines and indent by 4).
            msg=$(fmt_text_and_indent_after_first_line "* $msg" 3 2)
            detail "$msg"
        done <<<$commit_msgs

        if (( line_count > max_lines )); then
            local msgs_not_shown=$(( line_count - max_lines ))
            msg="   => Plus $msgs_not_shown more changes"
            detail "$msg"
        fi
    )
}

# Docker Compose using the geo config file
# dc_geo() {
#     local dir=$GEO_REPO_DIR/env/full
#     docker-compose -f $dir/docker-compose.yml -f $dir/docker-compose-geo.yml $@
#     # docker-compose -f $GEO_REPO_DIR/env/full/docker-compose-geo.yml $1
# }

# Check for updates. Return true (0 return value) if updates are available.
geo_check_for_updates() {
    [[ $GEO_NO_UPDATE_CHECK == true ]] && return 1
    local geo_cli_dir="$(geo_get GEO_CLI_DIR)"
    local cur_branch=$(cd $geo_cli_dir && git rev-parse --abbrev-ref HEAD)
    local v_remote=

    if [[ $cur_branch != master && -f $geo_cli_dir/feature-version.txt ]]; then
        geo_set FEATURE true
        # debug "cur_branch = $cur_branch"
        v_remote=$(git archive --remote=git@git.geotab.com:dawsonmyers/geo-cli.git $cur_branch feature-version.txt | tar -xO)
        # debug "v_remote = $v_remote"
        if [[ -n $v_remote ]]; then
            local feature_version=$(cat $geo_cli_dir/feature-version.txt)
            geo_set FEATURE_VER_LOCAL "${cur_branch}_V$feature_version"
            geo_set FEATURE_VER_REMOTE "${cur_branch}_V$v_remote"
            # debug "current feature version = $feature_version, remote = $v_remote"
            if [[ $feature_version == MERGED || $v_remote == MERGED || $v_remote -gt $feature_version ]]; then
                # debug setting outdated true
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
        Error 'Unable to pull geo-cli remote version'
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

geo_is_outdated() {
    outdated=$(geo_get OUTDATED)
    [[ $outdated =~ true ]]
}

# Sends an urgent geo-cli notification. This notification must be clicked by the user to dismiss.
_geo_show_update_notification() {
    # debug _geo_show_update_notification
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
geo_show_msg_if_outdated() {
    [[ $GEO_RAW_OUTPUT == true ]] && return
    # outdated=`geo_get OUTDATED`
    if geo_is_outdated; then
        # if [[ $outdated =~ true ]]; then
        warn_bi "New version of geo-cli is available. Run $(txt_underline 'geo update') to get it."
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

# Logging helpers
###########################################################

# Repeat string n number of times.
# 1: a string to repeat
# 2: the number of repeats
repeat_str() {
    echo $(printf "$1%.0s" $(seq 1 $2))
}
# Format long strings of text into lines of a certain width. All lines can also
# be indented.
# 1: the long string to format
# 2: the number of spaces to indent the text with
# 3: the string/char used to indent then text with (a space, by default), or, if the 3rd arg is '--keep-spaces-and-breaks', then don't remove spaces or line breaks
fmt_text() {
    local indent=0
    local indent_len=0
    local indent_str=' '
    local keep_spaces=false
    local txt="$1"

    # Check if args 2 and 3 were provided.
    [[ -n $2 ]] && indent="$2"

    if [[ $3 = '--keep-spaces-and-breaks' ]]; then
        keep_spaces=true
    elif [[ -n $3 ]]; then
        indent_str=$3
    fi

    [[ $indent -eq 0 ]] && indent_str=''

    # echo interprets '-e' as a command line switch, so a space is added to it so that it will actually be printed.
    re='^ *-e$'
    [[ $txt =~ $re ]] && txt+=' '
    
    # Replace 2 or more spaces with a single space and \n with a single space.
    [[ $keep_spaces = false ]] && txt=$(echo "$txt" | tr '\n' ' ' | sed -E 's/ {2,}/ /g')

    # Determin the total length of the repeated indent string.
    indent_len=$((${#indent_str} * indent))

    # Get the width of the console.
    local width=$(tput cols)
    # Get max width of text after the indent widht is subtracted.
    width=$((width - indent_len))

    local sed_pattern="s/^/"
    # Repeat the indent string $indent number of times. seq is used to create
    # a seq from 1 ... $indent (e.g. 1 2 3 4, for $indent=4). So for
    # $indent_str='=+' and $indent=3, this line, when evaluated, would print
    # '=+=+=+'. Note that printf "%.0s" "some-str" will print 0 chars of
    # "some-str". printf "%.3s" "some-str" would print 'som' (3 chars).
    sed_pattern+=$(printf "$indent_str%.0s" $(seq 1 $indent))
    sed_pattern+="/g"
    
    # Text is piped into fmt to format the text to the correct width, then
    # indented using the sed substitution.
    echo "$txt" | fmt -w $width | sed "$sed_pattern"
    # echo $1 | fmt -w $width | sed "s/^/$(printf '$%.0s' `seq 1 $indent`)/g"
}

# Takes a long string and wraps it according to the terminal width (like left justifying text in Word or Goggle Doc),
# but it allows wrapped lines to be indented more than the first line. The all lines created can also have a base indent.
# Parameters:
#   1 (long_text):  The long line of text
#   2 (base_indent): The base indent amount that all of the text will be indented by (the number of spaces to add to prefix each line with)
#   3 (additional_indent): The number of additional spaces to prefix wrapped lines with
# Example: 
#   (Assuming the terminal width is 40)
#   long_text="A very very very very very very very very very very very very very very very very long line"
#   base_indent=4
#   additional_indent=2
#   fmt_text_and_indent_after_first_line "$long_text" $base_indent $additional_indent
#  Returns:
#       A very very very very very very
#         very very very very very very
#         very very very very long line
fmt_text_and_indent_after_first_line() {
    local indent_char=' '
    local long_text="$1"
    # The amount to indent lines that wrap.
    local base_indent=$2
    local additional_indent=$3
    local total_indent=$(( base_indent + additional_indent ))
    local wrapped_line_indent_str=$(printf "$indent_char%.0s" $(seq 1 $additional_indent))
    # debug "'${wrapped_line_indent_str}'"
    local lines=$(fmt_text "$long_text" $base_indent --keep-spaces-and-breaks)
    # debug "$lines"
    local line_number=0
    local output=''

    while read msg; do
        # debug "$msg"
        # Add the additional indent to the start of the line
        msg="${wrapped_line_indent_str}${msg}"
        # debug "$msg"
        local msg_lines=$(fmt_text "$msg" $base_indent --keep-spaces-and-breaks)
        # debug "$msg_lines"
        msg_lines="${msg_lines:additional_indent}"
        # debug -e "$msg_lines"
        output+="$msg_lines\n"
        # while read line; do
        #     (( line_number++ ))
        #     if [[ $line_number = 1 ]]; then
        #         output+="$line\n"
        #         continue
        #     fi
        #     # debug "$line"
        #     # debug "${wrapped_line_indent_str}${line}\n"
        #     output+="${wrapped_line_indent_str}${line}\n"
        # done <<<"$lines"
        # output+="${wrapped_line_indent_str}${line}\n"
    done <<<"$long_text"
    echo -n -e "$output"
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

    eval "
        $name() {
            local msg=\"\$@\"
            local options=
            local format_tokens=
            local opts=e

            # Only parse options if a message to be printed was also supplied (allows messages like '-e' to be printed instead of being treated like an option).
            if [[ \$1 =~ ^-[a-z]+$ && -n \$2 ]]; then
                options=\$1
                msg=\"\${@:2}\"
            fi

            local color_name=$color
            case \$options in
                # Intense
                *t* )
                    color_name="I${color}"
                    ;;&
                # Bold
                *b* )
                    color_name="BI${color}"
                    ;;&
                # Italic
                *i* )
                    msg=\$(txt_italic \$msg)
                    ;;&
                # Underline
                *u* )
                    msg=\$(txt_underline \$msg)
                    ;;&
                # Invert font/background colour
                *v* )
                    msg=\$(txt_invert \$msg)
                    ;;&
                # Prompt (doesn't add a new line after printing)
                *p* | *n* )
                    opts+=n
                    ;;&
            esac

            # echo interprets '-e' as a command line switch, so a space is added to it so that it will actually be printed.
            re='^ *-e$'
            [[ \$msg =~ \$re ]] && msg+=' '
            [[ \$GEO_RAW_OUTPUT == true ]] && echo -n \"\$msg\" && return

            echo \"-\${opts}\" \"\${format_tokens}\${!color_name}\${msg}\${Off}\"
        }
    "
}

# Make logger function using VTE colours.
# Use display_vte_colors command (defined in colors.sh, should always be loaded in your shell if geo-cli is installed) to
# display VTE colours.
make_logger_function_vte() {
    name=$1
    color=$2

    eval "${name}() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_b() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${BOLD_ON}\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_i() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_bi() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${BOLD_ON}\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_u() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${UNDERLINE_ON}\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_bu() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${BOLD_ON}${UNDERLINE_ON}\${${color}}\${args[@]}\${Off}\"; }"

    eval "
        $name() {
            local msg=\"\$@\"
            local options=
            local format_tokens=
            local opts=e

            # Only parse options if a message to be printed was also supplied (allows messages like '-e' to be printed instead of being treated like an option).
            if [[ \$1 =~ ^-[a-z]+$ && -n \$2 ]]; then
                options=\$1
                msg=\"\${@:2}\"
            fi

            case \$options in
                *b* )
                    format_tokens+=\"$BOLD_ON\"
                    ;;&
                *i* )
                    msg=\$(txt_italic \$msg)
                    ;;&
                *u* )
                    msg=\$(txt_underline \$msg)
                    ;;&
                *v* )
                    msg=\$(txt_invert \$msg)
                    ;;&
                *p* )
                    opts+=n
                    ;;&
            esac

            # echo interprets '-e' as a command line switch, so a space is added to it so that it will actually be printed.
            re='^ *-e$'
            [[ \$msg =~ \$re ]] && msg+=' '
            [[ \$GEO_RAW_OUTPUT == true ]] && echo -n \"\${msg}\" && return

            echo \"-\${opts}\" \"\${format_tokens}\${${color}}\${msg}\${Off}\"
        }
    "
}

red() {
    echo -e "${Red}$@${Off}"
}

make_logger_function_vte warn VTE_COLOR_202 # Orange
make_logger_function error Red
make_logger_function info Green
# make_logger_function success Green
make_logger_function detail Yellow
# make_logger_function detail Yellow
make_logger_function_vte data VTE_COLOR_253
# make_logger_function data White
# make_logger_function warn Purple
make_logger_function status Cyan
make_logger_function verbose Purple
make_logger_function debug Purple
make_logger_function purple Purple
make_logger_function red Red
make_logger_function cyan Cyan
make_logger_function yellow Yellow
make_logger_function green Green
make_logger_function white White

_stacktrace() {
    local start=1
    [[ $1 =~ ^- ]] && start=${1:1}
    # debug "start $start"
    local debug_log=$(geo_get DEBUG_LOG)
    if [[ $debug_log == true ]]; then
        # debug "_stacktrace: ${FUNCNAME[@]}"
        local stacktrace="${FUNCNAME[@]:start}"
        local stacktrace_reversed=
        for f in $stacktrace; do 
            [[ -z $stacktrace_reversed ]] && stacktrace_reversed=$f && continue
            stacktrace_reversed="$f -> $stacktrace_reversed"
        done
        debug "Stacktrace: $stacktrace_reversed"
    fi
}

# ✘
Error() {
    echo -e "❌  ${BIRed}Error: $@${Off}"
    _stacktrace
}
error() {
    echo -e "❌  ${BIRed}$@${Off}"
}

data_header() {
    echo -e "${VTE_COLOR_87}${UNDERLINE_ON}${BOLD_ON}$@${Off}"
    # echo -e "${BIGreen}$@${Off}"
}

success() {
    echo -e "${BIGreen}✔️   $@${Off}"
}

prompt() {
    echo -e "${BCyan}$@${Off}"
}

# Echo without new line
prompt_n() {
    echo -en "${BCyan}$@${Off}"
}

# valid_repo() {
#     if [ ${REPOS_DICT[$1]+_} ]; then
#         return 0
#     else
#         return 1
#     fi
# }

# Documentation helpers
###########################################################

# The name of a command
doc_cmd() {
    doc_handle_command "$1"
    local indent=4
    local txt=$(fmt_text "$@" $indent)
    # detail_u "$txt"
    detail_b "$txt"
}

# Command description
doc_cmd_desc() {
    local indent=6
    local txt=$(fmt_text "$@" $indent)
    data_i "$txt"
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
    data "$txt"
}

doc_cmd_options_title() {
    local indent=8
    local txt=$(fmt_text "Options:" $indent)
    info_i "$txt"
    # data_bi "$txt"
}
doc_cmd_option() {
    # doc_handle_subcommand "$1"
    local indent=12
    local txt=$(fmt_text "$@" $indent)
    verbose_bi "$txt"
}
doc_cmd_option_desc() {
    local indent=16
    local txt=$(fmt_text "$@" $indent)
    data "$txt"
}

doc_cmd_sub_cmds_title() {
    local indent=8
    local txt=$(fmt_text "Commands:" $indent)
    info_i "$txt"
    # data_bi "$txt"
}
doc_cmd_sub_cmd() {
    doc_handle_subcommand "$1"
    local indent=12
    local txt=$(fmt_text "$@" $indent)
    verbose_bi "$txt"
}
doc_cmd_sub_cmd_desc() {
    local indent=16
    local txt=$(fmt_text "$@" $indent)
    data "$txt"
}

doc_cmd_sub_sub_cmds_title() {
    local indent=18
    local txt=$(fmt_text "Commands:" $indent)
    info "$txt"
    # data_bi "$txt"
}
doc_cmd_sub_sub_cmd() {
    local indent=20
    local txt=$(fmt_text "$@" $indent)
    verbose "$txt"
}
doc_cmd_sub_sub_cmd_desc() {
    local indent=22
    local txt=$(fmt_text "$@" $indent)
    data "$txt"
}

doc_cmd_sub_options_title() {
    local indent=18
    local txt=$(fmt_text "Options:" $indent)
    info "$txt"
    # data_bi "$txt"
}
doc_cmd_sub_option() {
    local indent=20
    local txt=$(fmt_text "$@" $indent)
    verbose "$txt"
}
doc_cmd_sub_option_desc() {
    local indent=22
    local txt=$(fmt_text "$@" $indent)
    data "$txt"
}

prompt_continue_or_exit() {
    prompt_n "Do you want to continue? (Y|n): "
    read answer
    [[ ! $answer =~ [nN] ]]
}
prompt_continue() {
    # Yes by default, any input other that n/N/no will continue.
    local regex="[^nN]"
    # Default to no if the -n option is present. This means that the user is required to enter y/Y/yes to continue,
    # anything else will decline to continue.
    [[ $1 == -n ]] && regex="[yY]" && shift
    if [[ -z $1 ]]; then
        prompt_n "Do you want to continue? (Y|n): "
    else
        prompt_n "$1"
    fi
    
    read answer

    [[ $answer =~ $regex ]]
}
prompt_for_info() {
    prompt "$1"
    read prompt_return
    # echo $answer
}
prompt_for_info_n() {
    prompt_n "$1"
    read prompt_return
    # echo $answer
}

geo_logo() {
    green_bi '       ___  ____  __         ___  __    __ '
    green_bi '      / __)(  __)/  \  ___  / __)(  )  (  )'
    green_bi '     ( (_ \ ) _)(  O )(___)( (__ / (_/\ )( '
    green_bi '      \___/(____)\__/       \___)\____/(__)'
}

geotab_logo() {
    cyan_bi ''
    cyan_bi '===================================================='
    cyan_bi ''
    cyan_bi ' ██████  ███████  ██████  ████████  █████  ██████ '
    cyan_bi '██       ██      ██    ██    ██    ██   ██ ██   ██'
    cyan_bi '██   ███ █████   ██    ██    ██    ███████ ██████ '
    cyan_bi '██    ██ ██      ██    ██    ██    ██   ██ ██   ██'
    cyan_bi ' ██████  ███████  ██████     ██    ██   ██ ██████ '
    cyan_bi ''
    cyan_bi '===================================================='
}
# geo_logo() {
#     detail ''
#     detail '=============================================================================='
#     node $GEO_CLI_DIR/src/cli/logo/logo.js
#     detail ''
#     detail '=============================================================================='
#     # detail ''
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
        # debug $line
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
    # echo "prev: $prev"  >> bcompletions.txt
    case ${COMP_CWORD} in
        # e.g., geo 
        1)
            local cmds="${COMMANDS[@]}"
            
            COMPREPLY=($(compgen -W "$cmds" -- ${cur}))
            ;;
        # e.g., geo db
        2)
            # echo "$words" >> bcompletions.txt
            if [[ -v SUBCOMMAND_COMPLETIONS[$prev] ]]; then
                # echo "SUBCOMMANDS[$cur]: ${SUBCOMMANDS[$prev]}" >> bcompletions.txt
                COMPREPLY=($(compgen -W "${SUBCOMMAND_COMPLETIONS[$prev]}" -- ${cur}))
                case $prev in
                    get|set|rm ) COMPREPLY=($(compgen -W "$(geo_env ls keys)" -- ${cur^^})) ;;
                esac
            else
                COMPREPLY=()
                
            fi
            
            # case ${prev} in
            #     configure)
            #         COMPREPLY=($(compgen -W "CM DSP NPU" -- ${cur}))
            #         ;;
            #     show)
            #         COMPREPLY=($(compgen -W "some other args" -- ${cur}))
            #         ;;
            # esac
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
            ;;
        *)
            COMPREPLY=()
            ;;
    esac
}

complete -F _geo_complete geo