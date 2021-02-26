#!/bin/bash

# Import colour constants/functions and config file read/write helper functions.
. $GEO_CLI_SRC_DIR/utils/colors.sh
. $GEO_CLI_SRC_DIR/utils/config-file-utils.sh

# The name of the base postgres image that will be used for creating all geo db containers.
export IMAGE=geo_cli_db_postgres11

# A list of all of the top-level geo commands. 
# This is used in geo-cli.sh to confirm that the first param passed to geo (i.e. in 'geo db ls', db is the top-level command) is a valid command.
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

geo_check_db_image() {
    local image=`docker image ls | grep "$IMAGE"`
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
    doc_cmd_options_title
    doc_cmd_option 'create'
    doc_cmd_option_desc 'Creates the base Postgres image configured to be used with geotabdemo.'
    doc_cmd_option 'remove'
    doc_cmd_option_desc 'Removes the base Postgres image.'
    doc_cmd_option 'ls'
    doc_cmd_option_desc 'List existing geo-cli Postgres images.'
    doc_cmd_examples_title
    doc_cmd_example 'geo image create'
}
geo_image() {
    case "$1" in
        rm | remove )
            docker image rm "$IMAGE"
            # if [[ -z $2 ]]; then
            #     Error "No database version provided for removal"
            #     return
            # fi
            # geo_db_rm "$2"
            return
            ;;
        create )
            status 'Building image...'
            local dir=`geo_get DEV_REPO_DIR`
            dir="${dir}/Checkmate/Docker/postgres"
            local dockerfile="Debug.Dockerfile"
            pushd "$dir"
            docker build --file "$dockerfile" -t "$IMAGE" . && success 'geo-cli Postgres image created' || warn 'Failed to create geo-cli Postgres image'
            popd
            return
            ;;
        ls )
            docker image ls | grep "$IMAGE"
            ;;
    esac

}

###########################################################
COMMANDS+=('db')
geo_db_doc() {
    doc_cmd 'db'
    doc_cmd_desc 'Database commands.'

    doc_cmd_options_title

    doc_cmd_option 'create [option] <name>'
    doc_cmd_option_desc 'Creates a versioned db container and volume.'
    doc_cmd_sub_options_title
    doc_cmd_sub_option '-y'
    doc_cmd_sub_option_desc 'Accept all prompts.'

    doc_cmd_option 'start [option] [name]'
    doc_cmd_option_desc 'Starts (creating if necessary) a versioned db container and volume. If no name is provided,
                        the most recent db container name is started.'
    doc_cmd_sub_options_title
    doc_cmd_sub_option '-y'
    doc_cmd_sub_option_desc 'Accept all prompts.'

    doc_cmd_option 'rm, remove <version>'
    doc_cmd_option_desc 'Removes the container and volume associated with the provided version (e.g. 2004).'
    doc_cmd_sub_options_title
    doc_cmd_sub_option '-a, --all'
    doc_cmd_sub_option_desc 'Remove all db containers and volumes.'

    doc_cmd_option 'stop [version]'
    doc_cmd_option_desc 'Stop geo-cli db container.'

    doc_cmd_option 'ls [option]'
    doc_cmd_option_desc 'List geo-cli db containers.'
    doc_cmd_sub_options_title
    doc_cmd_sub_option '-a, --all'
    doc_cmd_sub_option_desc 'Display all geo images, containers, and volumes.'

    doc_cmd_option 'ps'
    doc_cmd_option_desc 'List running geo-cli db containers.'

    doc_cmd_option 'init'
    doc_cmd_option_desc 'Initialize a running db container with geotabdemo or an empty db with a custom name.'
    doc_cmd_sub_options_title
    doc_cmd_sub_option '-y'
    doc_cmd_sub_option_desc 'Accept all prompts.'

    doc_cmd_option 'psql [options] [db name]'
    doc_cmd_option_desc 'Open a psql session to geotabdemo (default db name) in the running geo-cli db container. The username and password used to
                        connect is geotabuser and vircom43, respectively.'
    doc_cmd_sub_options_title
    doc_cmd_sub_option '-u'
    doc_cmd_sub_option_desc 'The admin sql user. The default value used is "geotabuser"'
    doc_cmd_sub_option '-p'
    doc_cmd_sub_option_desc 'The admin sql password. The default value used is "vircom43"'

    doc_cmd_option 'bash'
    doc_cmd_option_desc 'Open a bash session with the running geo-cli db container.'

    doc_cmd_examples_title
    doc_cmd_example 'geo db start 2004'
    doc_cmd_example 'geo db start -y 2004'
    doc_cmd_example 'geo db create 2004'
    doc_cmd_example 'geo db rm 2004'
    doc_cmd_example 'geo db rm --all'
    doc_cmd_example 'geo db ls'
    doc_cmd_example 'geo db psql'
    doc_cmd_example 'geo db psql -u mySqlUser -p mySqlPassword dbName'
}
geo_db() {
    # Check to make sure that the current user is added to the docker group. All subcommands in this command need to use docker.
    if ! geo_check_docker_permissions; then
        return 1
    fi

    case "$1" in
        init )
            geo_db_init "$2"
            return
            ;;
        ls )
            geo_db_ls_containers
            
            if [[ $2 =~ ^-*a(ll)? ]]; then
                echo
                geo_db_ls_volumes
                echo
                geo_db_ls_images
            fi
            return
            ;;
        ps )
            docker ps --filter name="$IMAGE*"
            return
            ;;
        stop )
            local silent=false
            
            if [[ $2 =~ -s ]]; then
                silent=true
                shift
            fi
            local container_name=`geo_container_name $db_version`

            db_version="$2"

            if [[ -z $db_version ]]; then
                container_id=`geo_get_running_container_id`
                # container_id=`docker ps --filter name="$IMAGE*" --filter status=running -aq`
            else
                container_id=`geo_get_running_container_id "${container_name}"`
                # container_id=`docker ps --filter name="${container_name}" --filter status=running -aq`
            fi

            if [[ -z $container_id ]]; then
                [[ $silent = false ]] \
                    && warn 'No geo-cli db containers running'
                return
            fi

            status_bi 'Stopping container...'

            # Stop all running containers.
            echo $container_id | xargs docker stop > /dev/null \
                && success 'OK'
            return
            ;;
        rm | remove )
            db_version="$2"

            if [[ -z $db_version ]]; then
                Error "No database version provided for removal"
                return
            fi

            geo_db_rm "$2" "$3"
            return
            ;;
        create )
            local silent=false
            local acceptDefaults=
            while [[ $2 =~ ^-[a-z] ]]; do
                local option=${2:1}
                local len=${#option}
                if [[ $len -gt 1 ]]; then
                    for ((i=0; i < len; i++)); do
                        local opt=${option:i:1}
                        case $opt in
                            s )
                                silent=true
                                ;;
                            y )
                                acceptDefaults=true
                                ;;
                        esac
                    done
                else
                    case $option in
                        s )
                            silent=true
                            ;;
                        y )
                            acceptDefaults=true
                            ;;
                    esac
                fi
                shift
            done

            db_version="$2"
            db_version=`geo_make_alphanumeric "$db_version"`

            if [ -z "$db_version" ]; then
                Error "No database version provided."
                return
            fi

            local container_name=`geo_container_name "$db_version"`

            if geo_container_exists $container_name; then
                Error 'Container already exists'
                return 1
            fi

            if ! geo_check_db_image; then
                Error "Cannot create db without image. Run 'geo image create' to create a db image"
                return 1
            fi

            if [ ! $acceptDefaults ]; then
                prompt_continue "Create db container with name `txt_underline ${db_version}`? (Y|n): " || return
            fi
            status_bi "Creating volume:"
            status "  NAME: $container_name"
            docker volume create "$container_name" > /dev/null \
                && success 'OK' || (Error 'Failed to create volume' && return 1)
            
            status_bi "Creating container:"
            status "  NAME: $container_name"
            # docker run -v $container_name:/var/lib/postgresql/11/main -p 5432:5432 --name=$container_name -d $IMAGE > /dev/null && success OK
            local vol_mount="$container_name:/var/lib/postgresql/11/main"
            local port=5432:5432
            docker create -v $vol_mount -p $port --name=$container_name $IMAGE > /dev/null \
                && success 'OK' || (Error 'Failed to create volume' && return 1)

            if [[ $silent == false ]]; then
                info "Start your new db with `txt_underline geo db start $db_version`"
                info "Initialize it with `txt_underline geo db init $db_version`"
            fi
            ;;
        start )
            local acceptDefaults=
            if [[ $2 == '-y' ]]; then
                acceptDefaults=true
                shift
            fi
            local db_version="$2"
            db_version=`geo_make_alphanumeric "$db_version"`
            # debug $db_version
            if [ -z "$db_version" ]; then
                db_version=`geo_get LAST_DB_VERSION`
                if [[ -z $db_version ]]; then
                    Error "No database version provided."
                    return
                fi
            fi

            if ! geo_check_db_image; then
                Error "Cannot start db without image. Run 'geo image create' to create a db image"
                return 1
            fi

            geo_set LAST_DB_VERSION "$db_version"

            # VOL_NAME="geo_cli_db_${db_version}"
            local container_name=`geo_container_name $db_version`

            # docker run -v 2002:/var/lib/postgresql/11/main -p 5432:5432 postgres11

            local volume=`docker volume ls | grep " $container_name"`

            geo_db stop -s

            # Check to see if a container is running that is bound to the postgres port (5432).
            # If it is already in use, the user will be prompted to stop it or exit.
            local port_in_use=`docker ps --format '{{.Names}} {{.Ports}}' | grep '5432->'`
            if [[ -n $port_in_use ]]; then
                # Get container name by triming off the port info from docker ps output.
                local container_name_using_postgres_port="${port_in_use%% *}"
                Error "Postgres port 5432 is currently bound to the following container: $container_name_using_postgres_port"
                if prompt_continue "Do you want to stop this container so that a geo db one can be started? (Y|n): "; then
                    if docker stop "$container_name_using_postgres_port" >-; then
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


            local container_id=`geo_get_container_id "$container_name"`
            # local container_id=`docker ps -aqf "name=$container_name"`
            local volume_created=false

            local output=''

            try_to_start_db() {
                output=''
                output="`docker start $1 2>&1 | grep '0.0.0.0:5432: bind: address already in use'`"
            }

            if [[ -n $container_id ]]; then
                
                status_bi "Starting existing container:"
                status "  ID: $container_id"
                status "  NAME: $container_name"

                try_to_start_db $container_id

                if [[ -n $output ]]; then
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
                db_version="$2"
                db_version=`geo_make_alphanumeric "$db_version"`

                if [ ! $acceptDefaults ]; then
                    prompt_continue "Db container `txt_italic ${db_version}` doesn't exist. Would you like to create it? (Y|n): " || return
                fi
                local opts=-s
                [ $acceptDefaults ] && opts+=y

                geo_db create $opts "$db_version" \
                    || (Error 'Failed to create db' && return 1)

                container_id=`docker ps -aqf "name=$container_name"`

                try_to_start_db $container_name

                if [[ -n $output ]]; then
                    Error "Port 5432 is already in use."
                    info "Fix: Stop postgresql"
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

                if [ $acceptDefaults ] || prompt_continue 'Would you like to initialize the db? (Y|n): '; then
                    geo_db_init $acceptDefaults
                else
                    info "Initialize a running db anytime using `txt_underline 'geo db init'`"
                fi
            fi
            success Done
            ;;
        psql )
            local sql_user=`geo_get SQL_USER`
            local sql_password=`geo_get SQL_PASSWORD`
            while [[ $2 =~ ^-[a-z] ]]; do
                local option=$2
                local arg="$3"
                shift
                [[ ! $arg || $arg =~ ^-[a-z] ]] && Error "Argument missing for option ${option}" && return 1

                case $option in
                    -u )
                        sql_user="$arg"
                        ;;
                    -p )
                        sql_password="$arg"
                        ;;
                esac
                shift
            done
            local db_name=$2
            # Assign default values for sql user/passord.
            [[ -z $db_name ]] && db_name=geotabdemo
            [[ -z $sql_user ]] && sql_user=geotabuser
            [[ -z $sql_password ]] && sql_password=vircom43
            debug $sql_user $sql_password $db_name
            return

            local running_container_id=`geo_get_running_container_id`
            [[ ! $running_container_id ]]
            if [[ -z $running_container_id ]]; then
                Error 'No geo-cli containers are running to connect to.'
                info "Run `txt_underline 'geo db ls'` to view available containers and `txt_underline 'geo db start <name>'` to start one."
                return 1
            fi

            
            
            docker exec -it -e PGPASSWORD=$sql_password $running_container_id psql -U $sql_user -h localhost -p 5432 -d $db_name
            ;;
        bash )
            local running_container_id=`geo_get_running_container_id`
            [[ ! $running_container_id ]]
            if [[ -z $running_container_id ]]; then
                Error 'No geo-cli containers are running to connect to.'
                info "Run `txt_underline 'geo db ls'` to view available containers and `txt_underline 'geo db start <name>'` to start one."
                return 1
            fi

            docker exec -it $running_container_id /bin/bash
        ;;
    esac
}

geo_make_alphanumeric() {
    # Replace any non-alphanumeric characters with '_', then replace 2 or more occurrences with a singe '_'.
    # Ex: some>bad()name -> some_bad__name -> some_bad_name
    echo "$@" | sed 's/[^0-9a-zA-Z]/_/g' | sed -e 's/_\{2,\}/_/g'
}

geo_db_ls_images() {
    info Images
    docker image ls geo_cli* #--format 'table {{.Names}}\t{{.ID}}\t{{.Image}}'
}
geo_db_ls_containers() {
    info DB Containers
    # docker container ls -a -f name=geo_cli
    if [[ $1 = -a ]]; then
        docker container ls -a -f name=geo_cli
        return
    fi
    local output=`docker container ls -a -f name=geo_cli --format '{{.Names}}\t{{.ID}}\t{{.Image}}'`
    local header=`printf "%-24s %-16s %-24s\n" "Image" "Container ID" "geo-cli Name"`
    local filtered=`echo $"$output" | awk '{ gsub($3"_","",$1);  printf "%-24s %-16s %-24s\n",$3,$2,$1 } '`
    # filtered=`echo $"$output" | awk 'BEGIN { format="%-24s %-24s %-24s\n"; ; printf format, "Name","Container ID","Image" } { gsub($3"_","",$1);  printf " %-24s %-24s %-24s\n",$1,$2,$3 } '`

    data_header "$header"
    # info_bi "$header"
    data "$filtered"
}
geo_db_ls_volumes() {
    info Volumes
    docker volume ls -f name=geo_cli
}

geo_container_name() {
    echo "${IMAGE}_${1}"
}

geo_get_container_id() {
    local name=$1
    # [[ -z $name ]] && name="$IMAGE*"
    # echo `docker container ls -a --filter name="$name" -aq`
    local result=`docker inspect "$name" --format='{{.ID}}' 2>&1`
    local container_does_not_exists=`echo $result | grep "Error:"`
    [[ $container_does_not_exists ]] && return
    echo $result
}

geo_container_exists() {
    local name=`geo_get_container_id "$1"`
    [[ -n $name ]]
}

geo_get_running_container_id() {
    local name=$1
    [[ -z $name ]] && name="$IMAGE*"
    echo `docker ps --filter name="$name" --filter status=running -aq`
}

geo_check_docker_permissions() {
    local ps_error_output=`docker ps 2>&1 | grep docker.sock`
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

function geo_db_init()
{
    local acceptDefaults=$1
    
    local container_id=`geo_get_running_container_id`
    if [[ -z $container_id ]]; then
        Error 'No geo-cli containers are running to initialize.'
        info "Run `txt_underline 'geo db ls'` to view available containers and `txt_underline 'geo db start <name>'` to start one."
        return 1
    fi
    db_name='geotabdemo'
    status 'A db can be initialized with geotabdemo or with a custom db name (just creates an empty database with provided name).'
    if ! [ $acceptDefaults ] && ! prompt_continue 'Would you like to initialize the db with geotabdemo? (Y|n): '; then
        stored_name=`geo_get PREV_DB_NAME`
        prompt_txt='Enter the name of the db you would like to create: '
        if [[ -n $stored_name ]]; then
            data "Stored db name: $stored_name"
            if ! prompt_continue 'Use stored db name? (Y|n): '; then
                prompt_for_info_n "$prompt_txt"
                while ! prompt_continue "Create db called '$prompt_return'? (Y|n): "; do
                    prompt_for_info_n "$prompt_txt"
                done
                db_name="$prompt_return"
            else
                db_name="$stored_name"
            fi
        else
            prompt_for_info_n "$prompt_txt"
            while ! prompt_continue "Create db called '$prompt_return'? (Y|n): "; do
                prompt_for_info_n "$prompt_txt"
            done
            db_name="$prompt_return"
        fi
        geo_set PREV_DB_NAME "$db_name"
    fi

    if [[ -z $db_name ]]; then
        Error 'Db name cannot be empty'
        return 1
    fi

    status_bi "Initializing db $db_name"
    local user=`geo_get DB_USER`
    local password=`geo_get DB_PASSWORD`
    local sql_user=`geo_get SQL_USER`
    local sql_password=`geo_get SQL_PASSWORD`
    local answer=''
    
    # Assign default values for sql user/passord.
    [[ -z $sql_user ]] && sql_user=geotabuser
    [[ -z $sql_password ]] && sql_password=vircom43

    # Make sure there's a running db container to initialize.
    local container_id=`geo_get_running_container_id`
    if [[ -z $container_id ]]; then
        Error "There isn't a running geo-cli db container to initialize with geotabdemo."
        info 'Start one of the following db containers and try again:'
        geo_db_ls_containers
        return
    fi

    get_user() {
        prompt_n "Enter MyGeotab admin username (your email): "
        read user
        geo_set DB_USER $user
    }

    get_password() {
        prompt_n "Enter MyGeotab admin password: "
        read password
        geo_set DB_PASSWORD $password
    }

    get_sql_user() {
        prompt_n "Enter db admin username: "
        read sql_user
        geo_set SQL_USER $sql_user
    }

    get_sql_password() {
        prompt_n "Enter db admin password: "
        read sql_password
        geo_set SQL_PASSWORD $sql_password
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


    [ $acceptDefaults ] && sleep 3

    if dotnet "${path}" CreateDatabase postgres companyName="$db_name" administratorUser="$user" administratorPassword="$password" sqluser="$sql_user" sqlpassword="$sql_password"; then
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
        names=`docker container ls -a -f name=geo_cli --format "{{.Names}}"`
        # ids=`docker container ls -a -f name=geo_cli --format "{{.ID}}"`
        # echo "$ids" | xargs docker container rm 
        local fail_count=0
        for name in $names; do
            # Remove image prefix from container name; leaving just the version/identier (e.g. geo_cli_db_postgres11_2008 => 2008).
            geo_db_rm -n "$name" || ((fail_count++))
            
            # geo_db_rm "${name#${IMAGE}_}"
            # echo "${name#${IMAGE}_}"
        done
        local num_dbs=`echo "$names" | wc -l`
        num_dbs=$((num_dbs-fail_count))
        success "Removed $num_dbs dbs"
        [[ fail_count > 0 ]] && error "Failed to remove $fail_count dbs"
        return
    fi

    local container_name
    local db_name="$1"
    # If the -n option is present, the full container name is passed in as an argument (e.g. geo_cli_db_postgres11_2101). Otherwise, the db name is passed in (e.g., 2101)
    if [[ $1 == -n ]]; then
        container_name="$2"
        db_name="${2#${IMAGE}_}"
        shift
    else
        container_name=`geo_container_name "$1"`
    fi

    local container_id=`geo_get_running_container_id "$container_name"`

    if [[ -n "$container_id" ]]; then
        docker stop $container_id > /dev/null && success "Container stopped"
    fi

    # container_name=bad

    if docker container rm $container_name > /dev/null; then
        success "Container $db_name removed"
    else
        Error "Could not remove container $container_name"
        return 1
    fi

    if docker volume rm $container_name > /dev/null; then
        success "Volume $db_name removed"
    else
        Error "Could not remove volume $container_name"
        return 1
    fi

}

geo_get_checkmate_dll_path() {
    local dev_repo=`geo_get DEV_REPO_DIR`
    local output_dir="${dev_repo}/Checkmate/bin/Debug"
    local acceptDefaults=$1
    # Get full path of CheckmateServer.dll files, sorted from newest to oldest.
    local files="`find $output_dir -maxdepth 2 -name "CheckmateServer.dll" -print0 | xargs -r -0 ls -1 -t | tr '\n' ':'`"
    local ifs=$IFS
    IFS=:
    read -r -a paths <<< "$files"
    IFS=$ifs
    local number_of_paths=${#paths[@]}
    [[ $number_of_paths = 0 ]] && Error "No output directories could be found in ${output_dir}. These folders should exist and contain CheckmateServer.dll. Build MyGeotab and try again."

    if [[ $number_of_paths -gt 1 ]]; then
        warn "Multiple CheckmateServer.dll output directories exist."
        info_bi "Available executables in directory `txt_italic "${output_dir}"`:"
        local i=0
        
        data_header "  Id    Directory                                      "
        for d in "${paths[@]}"; do
            local line="  ${i}    ...${d##*Debug}"
            [ $i = 0 ] && line="${line}   `info_bi -p  '(NEWEST)'`"
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
    local dev_repo=`geo_get DEV_REPO_DIR`

    is_valid_repo_dir() {
        test -d "${1}/Checkmate"
    }

    get_dev_repo_dir() {
        prompt 'Enter the full path (e.g. ~/repos/Development or /home/username/repos/Development) to the Development repo directory. This directory must contain the Checkmate directory:'
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
    while ! is_valid_repo_dir "$dev_repo"; do
        get_dev_repo_dir
    done

    success "Checkmate directory found"

    geo_set DEV_REPO_DIR "$dev_repo"
}

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
    doc_cmd_desc 'Initiallize repo directory.'

    doc_cmd_options_title
    doc_cmd_option 'repo'
    doc_cmd_option_desc 'Init Development repo directory using the current directory.'
    
    doc_cmd_examples_title
    doc_cmd_example 'geo init repo'
}
geo_init() {
    if [[ "$1" == '--' ]]; then shift; fi

    case $1 in
        'repo' | '' )
            local repo_dir=`pwd`
            if ! geo_is_valid_repo_dir "$repo_dir"; then
                Error "The current directory does not contain the Development repo since it is missing the Checkmate folder."
                return
            fi
            local current_repo_dir=`geo_get DEV_REPO_DIR`
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
    doc_cmd_options_title
    
    doc_cmd_option 'get <env_var>'
    doc_cmd_option_desc 'Gets the value for the env var.'
    
    doc_cmd_option 'set <env_var> <value>'
    doc_cmd_option_desc 'Sets the value for the env var.'
    
    doc_cmd_option 'ls'
    doc_cmd_option_desc 'Lists all env vars.'

    doc_cmd_examples_title
    doc_cmd_example 'geo env get DEV_REPO_DIR'
    doc_cmd_example 'geo env set DEV_REPO_DIR /home/username/repos/Development'
    doc_cmd_example 'geo env ls'
}
geo_env() {
    if [[ -z $1 ]]; then
        geo_env_doc
        return
    fi

    case $1 in
        'set' )
            # Create an array out of the arguments.
            local args=($@)
            # Remove the first arg, which is "set".
            unset "args[0]"
            # Get the key from the second arg, then remove it from the array.
            local key="${args[1]}"
            unset "args[1]"
            # Get the new value by concatenating the rest of the args together.
            local value="${args[@]}"
            geo_set -s "$key" "$value"
            ;;
        'get' )
            shift
            geo_get "$2"
            ;;
        'ls' )
            local header=`printf "%-26s %-26s\n" 'Variable' 'Value'`
            local env_vars=`awk -F= '{ gsub("GEO_CLI_","",$1); printf "%-26s %-26s\n",$1,$2 } ' $GEO_CLI_CONF_FILE`
            info_bi "$header"
            data "$env_vars"
            ;;
    esac 
}

# ##########################################################
# COMMANDS+=('config')
# geo_config_doc() {
#     doc_cmd 'set <ENV_VAR> <value>'
#     doc_cmd_desc 'Set geo environment variable'
#     doc_cmd_examples_title
#     doc_cmd_example 'geo set DEV_REPO_DIR /home/username/repos/Development'
# }
# geo_config() {
#     if [[ -z $1 ]]; then
#         geo_config_doc
#         return
#     fi

#     case $1 in
#         'set' )
#             shift
#             geo_set "$@"
#             ;;
#         'get' )
#             shift
#             geo_get "$@"
#             ;;
#         'ls' )
#             local env_vars=`cat $GEO_CONF_FILE`
#             detail "$env_vars"
#             ;;
#     esac 
# }

###########################################################
COMMANDS+=('set')
geo_set_doc() {
    doc_cmd 'set <env_var> <value>'
    doc_cmd_desc 'Set geo environment variable.'
    doc_cmd_examples_title
    doc_cmd_example 'geo set DEV_REPO_DIR /home/username/repos/Development'
}
geo_set() {
    # Set value of env var
    # $1 - name of env var in conf file
    # $2 - value 
    local show_status=false
    [[ $1 == -s ]] && show_status=true && shift

    local key="$1"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"

    local old=`cfg_read $GEO_CLI_CONF_FILE "$key"`

    cfg_write $GEO_CLI_CONF_FILE "$key" "$2"
    
    if [[ $show_status == true ]]; then
        info_bi "$1"
        info -p '  New value: ' && data "$2"
        if [[ -n $old ]]; then
            info -p '  Old value: ' && data "$old"
        fi
    fi
    export $key="$2"
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
    # Get value of env var
    local key="$1"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"

    value=`cfg_read $GEO_CLI_CONF_FILE $key`
    [[ -z $value ]] && return
    echo "$value"
}

geo_haskey() {
    local key="$1"
    [[ ! $key =~ ^GEO_CLI_ ]] && key="GEO_CLI_${key}"
    cfg_haskey $GEO_CLI_CONF_FILE "$key"
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
    pushd $GEO_CLI_DIR
    if ! git pull > /dev/null; then
        Error 'Unable to pull changes from remote'
        popd
        return 1
    fi
    popd

    bash $GEO_CLI_DIR/install.sh
    # Re-source .bashrc to reload geo in this terminal
    . ~/.bashrc
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
    doc_cmd 'analyze [analyzerId]'
    doc_cmd_desc 'Allows you to select and run various pre-build analyzers. You can optionaly include the list of analyzers if already known.'
    
    doc_cmd_examples_title
    doc_cmd_example 'geo analyze'
}
geo_analyze() {
    MYG_TEST_PROJ='Checkmate/MyGeotab.Core.Tests/MyGeotab.Core.Tests.csproj'
    MYG_CORE_PROJ='Checkmate/MyGeotab.Core.csproj'
    # Analyzer info: an array containing "name project" strings for each analyzer.
    analyzers=(
        "CSharp.CodeStyle $MYG_TEST_PROJ"
        "Threading.Analyzers $MYG_TEST_PROJ"
        "SecurityCodeScan $MYG_CORE_PROJ"
        "CodeAnalysis.FxCopAnalyzer $MYG_TEST_PROJ"
        "StyleCop.Analyzers $MYG_CORE_PROJ"
        "Roslynator.Analyzers $MYG_TEST_PROJ"
        "Meziantou.Analyzer $MYG_TEST_PROJ"
    )
    local len=${#analyzers[@]}
    local max_id=$((len-1))
    local name=0
    local proj=1
    # Print header for analyzer table. Which has two columns, ID and Name.
    data_header "`printf '%-4s %-30s\n' ID Name`"
    # Print each analyzer's id and name.
    for (( id = 0; id < len; id++ )); do
        # Convert a string containing "name project" into an array [name, project] so that name can be printed with its id.
        read -r -a analyzer <<< "${analyzers[$id]}"
        printf '%-4d %-30s\n' $id "${analyzer[$name]}" 
    done
    local dev_repo=`geo_get DEV_REPO_DIR`

    status "Valid IDs from 0 to ${max_id}"
    local prompt_txt='Enter the analyzer IDs that you would like to run (separated by spaces): '
    
    local valid_input=false
    if [[ $1 && $1 =~ ^( *[0-9]+ *)+$ ]]; then
        prompt_return=$1
        # Make sure the numbers are valid ids between 0 and max_id.
        for id in $prompt_return; do
            if (( id < 0 | id > max_id )); then
                error "Invalid ID: ${id}. Only IDs from 0 to ${max_id} are valid"
                # Set valid_input = false and break out of this for loop, causing the outer until loop to run again.
                valid_input=false
                break 
            fi
            valid_input=true
        done
    fi

    # Get the list of ids from the user. Asking repeatedly if invalid input is given.
    until [[ $valid_input == true ]]; do
        prompt_for_info_n "$prompt_txt"
        # Make sure the input consits of only numbers separated by spaces.
        while [[ ! $prompt_return =~ ^( *[0-9]+ *)+$ ]]; do
            error 'Invalid input. Only space-separated integer IDs are accepted'
            prompt_for_info_n "$prompt_txt"
        done 
        # Make sure the numbers are valid ids between 0 and max_id.
        for id in $prompt_return; do
            if (( id < 0 | id > max_id )); then
                error "Invalid ID: ${id}. Only IDs from 0 to ${max_id} are valid"
                # Set valid_input = false and break out of this for loop, causing the outer until loop to run again.
                valid_input=false
                break 
            fi
            valid_input=true
        done
    done

    # The number of ids entered.
    local id_count=`echo "$prompt_return" | wc -w`
    local run_count=1
    # Switch to the development repo directory so that dotnet build can be run.
    pushd "$dev_repo"
    
    # Run each analyzer.
    for id in $prompt_return; do
        # echo $id
        read -r -a analyzer <<< "${analyzers[$id]}"
        ANALYZER_NAME="${analyzer[$name]}"
        ANALYZER_PROJ="${analyzer[$proj]}"
        status_bi "Running ($((run_count++)) of $id_count): $ANALYZER_NAME"
        dotnet build -p:DebugAnalyzers=${ANALYZER_NAME} -p:TreatWarningsAsErrors=false -p:RunAnalyzersDuringBuild=true ${ANALYZER_PROJ} && success 'Analyzer done' || Error 'dotnet build failed'
    done
    # Restore previous directory.
    popd
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
    verbose `geo_get VERSION`
}

###########################################################
COMMANDS+=('cd')
geo_cd_doc() {
    doc_cmd 'cd <dir>'
    doc_cmd_desc 'Change to directory'
    doc_cmd_options_title

    doc_cmd_option 'dev, myg'
    doc_cmd_option_desc 'Change to the Development repo directory.'
    
    doc_cmd_option 'geo, cli'
    doc_cmd_option_desc 'Change to the geo-cli install directory.'

    doc_cmd_examples_title
    doc_cmd_example 'geo cd dev'
    doc_cmd_example 'geo cd cli'
}
geo_cd() {
    case "$1" in
        dev | myg)
            local path=`geo_get DEV_REPO_DIR`
            if [[ -z $path ]]; then
                Error "Development repo not set."
                return 1
            fi
            cd "$path"
            ;;
        geo | cli)
            local path=`geo_get DIR`
            if [[ -z $path ]]; then
                Error "geo-cli directory not set."
                return 1
            fi
            cd "$path"
            ;;
    esac
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
    [[ -n $cmd ]]
}

# Docker Compose using the geo config file
# dc_geo() {
#     local dir=$GEO_REPO_DIR/env/full
#     docker-compose -f $dir/docker-compose.yml -f $dir/docker-compose-geo.yml $@
#     # docker-compose -f $GEO_REPO_DIR/env/full/docker-compose-geo.yml $1
# }

# Check for updates. Return true (0 return value) if updates are available.
geo_check_for_updates() {
    # local auto_update=`geo_get AUTO_UPDATE`
    # [[ -z $auto_update ]] && geo_set AUTO_UPDATE true
    # [[ $auto_update = false ]] && return

    # local tmp=/tmp/geo-cli

    # [[ ! -d $tmp ]] && mkdir $tmp

    # pushd $tmp
    # ! git pull > /dev/null && Error 'Unable to pull changes from remote'
    local v_remote=`git archive --remote=git@git.geotab.com:dawsonmyers/geo-cli.git HEAD version.txt | tar -xO`

    #  Outputs contents of version.txt to stdout
    #  git archive --remote=git@git.geotab.com:dawsonmyers/geo-cli.git HEAD version.txt | tar -xO

    # if ! v_repo=`git archive --remote=git@git.geotab.com:dawsonmyers/geo-cli.git HEAD version.txt | tar -xO`; then
    if [[ -z $v_remote ]]; then
        Error 'Unable to pull geo-cli remote version'
        v_remote='0.0.0'
    else
        geo_set REMOTE_VERSION "$v_remote"
    fi
    # popd

    # The sed cmds filter out any colour codes that might be in the text
    local v_current=`geo_get VERSION` #  | sed -r "s/[[:cntrl:]]\[[0-9]{1,3}m//g"`
    if [[ -z $v_current ]]; then
        v_current=`cat "$GEO_CLI_DIR/version.txt"`
        geo_set VERSION "$v_current"
    fi
    # ver converts semver to int (e.g. 1.2.3 => 001002003) so that it can easliy be compared
    if [ `ver $v_current` -lt `ver $v_remote` ]; then
        geo_set OUTDATED true
        return
    else
        geo_set OUTDATED false
        return 1
    fi
    
}

geo_is_outdated() {
    outdated=`geo_get OUTDATED`
    [[ $outdated =~ true ]]
}

# This was a lot of work to get working right. There were issues with comparing
# strings with number and with literal values. I would read the value 'true'
# or a version number from a file and then try comparing it in an if statement,
# but it wouldn't work because it was a string. Usually 'true' == true will
# work in bash, but when reading from a file if doesn't. This was remedied
# using a regex in the if (i.e., if [[ $outdated =~ true ]]) which was the only
# way it would work.
geo_show_msg_if_outdated() {
    # outdated=`geo_get OUTDATED`
    if geo_is_outdated ; then
    # if [[ $outdated =~ true ]]; then
        warn_bi "New version of geo-cli is available. Run `txt_underline 'geo update'` to get it."
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
    v1=`fix_char $(echo "$1" | awk -F. '{ printf("%s", $1) }')`
    v2=`fix_char $(echo "$1" | awk -F. '{ printf("%s", $2) }')`
    v3=`fix_char $(echo "$1" | awk -F. '{ printf("%s", $3) }')`

    # The parts are reconstructed in a new string (without the \027 char)
    echo "$v1.$v2.$v3" | awk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }'; 
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
    local txt=$(echo "$1" | tr '\n' ' ' | sed -E 's/ {2,}/ /g')
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
    echo "$txt" | fmt -w $width | sed "$sed_pattern"
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
}

# Make logger function using VTE colours.
make_logger_function_vte() {
    name=$1
    color=$2

    eval "${name}() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_b() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${BOLD_ON}\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_i() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_bi() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${BOLD_ON}\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_u() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${UNDERLINE_ON}\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_bu() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${BOLD_ON}${UNDERLINE_ON}\${${color}}\${args[@]}\${Off}\"; }"
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
make_logger_function verbose Cyan
make_logger_function debug Purple
make_logger_function purple Purple
make_logger_function red Red
make_logger_function cyan Cyan
make_logger_function yellow Yellow
make_logger_function green Green
make_logger_function white White

# ✘
Error() {
    echo -e "❌  ${BIRed}Error: $@${Off}"
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
    local indent=12
    local txt=$(fmt_text "$@" $indent)
    verbose_bi "$txt"
}
doc_cmd_option_desc() {
    local indent=16
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
    if [[ -z $1 ]]; then
        prompt_n "Do you want to continue? (Y|n): "
    else
        prompt_n "$1"
    fi
    read answer
    [[ ! $answer =~ [nN] ]]
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
    green_bi '  ___  ____  __         ___  __    __ '
    green_bi ' / __)(  __)/  \  ___  / __)(  )  (  )'
    green_bi '( (_ \ ) _)(  O )(___)( (__ / (_/\ )( '
    green_bi ' \___/(____)\__/       \___)\____/(__)'
}

geotab_logo() 
{
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

# Auto-complete for commands
completions=(
    "${COMMANDS[@]}"
    )

# Doesn't work for some reason
# complete -W "${completions[@]}" geo

# Get list of completions separated by spaces (required as imput to complete command)
comp_string=`echo "${completions[@]}"`
complete -W "$comp_string" geo