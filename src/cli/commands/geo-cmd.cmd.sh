
#**********************************************************************************************************************
# This is a geo-cli command file. It is automatically executed from cli-handlers.sh when geo-cli is loaded into each 
# new terminal.
# 
# All of the exported constants and functions available to geo-cli are available here.
#**********************************************************************************************************************

#######################################################################################################################
# Global Constants and Functions
#######################################################################################################################
# [Path Constants]  
# GEO_CLI_DIR         The full path to the geo-cli repo.
# GEO_CLI_SRC_DIR     The full path to the geo-cli src dir, located in the root of the repo (geo-cli/src).
# GEO_CLI_CONFIG_DIR  The full path to the geo-cli config dir, located at $HOME/.geo-cli.
#   => This directory is used any time geo-cli or its commands need to persist some kind of information. If a command
#        needs to store data in this directory, create a new directory the same name as the command located at
#          $GEO_CLI_CONFIG_DIR/data/<command_name>.
# GEO_CLI_CONF_FILE   The full path to the geo-cli config file, located at $HOME/.geo-cli/.geo.conf.
#   => This file effectively acts as the db for geo, it stores all configurations and user preferences. It is written
#        to automically using lock a lock file.
# [Log Functions]
# All log functions are prefixed with log:: and are defined in /src/utils/log.sh. Try the functions yourself or search
# for usages for use cases.
#   log::caution                log::hint
#   log::filepath               log::fmt_text_and_indent_after_first_line
#   log::keyvalue               log::prompt_n
#   log::txt_italic             log::txt_blink
#   log::code                   log::yellow
#   log::fmt_text               log::detail
#   log::link                   log::purple
#   log::stacktrace             log::txt_bold
#   log::txt_underline          log::Error
#   log::cyan                   log::red
#   log::status                 log::txt_dim
#   log::verbose                log::error
#   log::data                   log::repeat_str
#   log::strip_color_codes      log::txt_hide
#   log::warn                   log::file
#   log::data_header            log::info
#   log::green                  log::txt_invert
#   log::white                  log::prompt                 
#   log::debug                  log::success                    
  

export GEO_CLI_COMMAND_DIR="$GEO_CLI_SRC_DIR/cli/commands"
export GEO_CLI_USER_COMMAND_DIR="$HOME/.geo-cli/data/commands"

COMMANDS+=('cmd')
geo_cmd_doc() {
  doc_cmd 'cmd'
      doc_cmd_desc "Commands for creating and updating custom geo-cli commands (i.e., 'geo <custom_command>'). These commands are stored in files and automatically loaded into geo-cli (in cli-handlers.sh). You can either create a geo command for local use only OR you can have the command file added to the geo-cli repo (by adding the -r option to the create command, e.g., 'geo cmd create -r <command_name>'). Add the command to the repo if you want to submit an MR for it to make it available for all geo-cli users."
      
      doc_cmd_sub_cmds_title
      
      doc_cmd_sub_cmd 'create [options] <command_name>'
          doc_cmd_sub_cmd_desc 'Creates a new command file. These files are automatically loaded into geo-cli (in cli-handlers.sh) and are stored in ~/.geo-cli/data/commands. If you want to make your command available to all geo-cli users, add the -r option to have the command file added to the geo-cli repo (in the src/cli/commands directory). Create and push a branch to GitLab for the command file and submit an MR for it.'
          doc_cmd_sub_options_title
              doc_cmd_sub_option '-r'
                  doc_cmd_sub_option_desc 'Creates the new command file in the geo-cli repo directory instead of in ~/.geo-cli/data/commands. This makes it easy to create an MR with the new command if you would like to share it with others.'
        #       doc_cmd_sub_option '-d <database name>'
        #           doc_cmd_sub_option_desc 'Sets the name of the db to...'
        doc_cmd_sub_cmd 'rm <command_name>'
          doc_cmd_sub_cmd_desc 'Removes a command file.'
        doc_cmd_sub_cmd 'ls'
          doc_cmd_sub_cmd_desc 'Lists all command files.'
          doc_cmd_sub_option '-r'
                  doc_cmd_sub_option_desc 'Also lists the command files in the geo-cli repo directory. They are located in the /src/cli/commands directory.'

      doc_cmd_examples_title
          doc_cmd_example 'geo cmd create ping'
          doc_cmd_example 'geo cmd rm ping'
          doc_cmd_example 'geo cmd ls'
}
geo_cmd() {    
    local OPTIND
    while getopts "v:" opt; do
        case "${opt}" in
            # v ) [[ $OPTARG =~ ^[[:digit:]]+$ ]] && pg_version=$OPTARG ;;
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
        esac
    done

    shift $((OPTIND - 1))
    local cmd="$1"

    shift

    case "$cmd" in
        create )
            _geo_cmd_create "$@"
            ;;
        rm | remove )
            _geo_cmd_remove "$@"
            ;;
        ls | list )
            _geo_cmd_ls "$@"
            ;;
        edit )
            _geo_cmd_edit "$@"
            ;;
        * ) 
            [[ -z $cmd ]] && log::Error "No arguments provided" && return 1 
            log::Error "The following cmd is unknown: $cmd" && return 1 
            ;;
    esac
}

_geo_cmd_create() {
    local force_create=false
    local add_cmd_to_repo=true

    local OPTIND
    while getopts "fr" opt; do
        case "${opt}" in
            f ) force_create=true ;;
            r ) add_cmd_to_repo=true ;;
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    
    local template_file="$GEO_CLI_SRC_DIR/includes/commands/geo-cmd-template.sh"

    local cmd_name="$1"

    if _geo_cmd_exists "$cmd_name"; then
        log::warn "Command '$cmd_name' already exists"
        prompt_continue "Continue anyways? (Y|n) : " || return 1
    fi
    
    [[ ! -f $template_file ]] && log::Error "Couldn't find template file at $template_file" && return 1

    local alphanumeric_re='^([[:alnum:]]|[-_])+$'
    [[ ! $cmd_name =~ $alphanumeric_re ]] && log::Error "Invalid command name. Only alphanumeric characters (including -_) are allowed." && return 1

    local command_dir_name=
    log::detail "You can create your command inside of its own directory, called 'geo-$cmd_name', if its logic requires additional files (i.e. it executes other scripts or parses static data from a text file)."
    if prompt_continue "Create command in its own directory? (Y|n): "; then
        command_dir_name="/geo-$cmd_name"
    fi
    echo

    # The new command file.
    local command_file_name="geo-${cmd_name}.cmd.sh"
    local repo_cmd_file_dir="$GEO_CLI_SRC_DIR/cli/commands"
    local local_cmd_dir="$GEO_CLI_CONFIG_DIR/data/commands"
    local command_file_dir="$repo_cmd_file_dir$command_dir_name"
    ! $add_cmd_to_repo && command_file_dir="$local_cmd_dir$command_dir_name"
    
    if $add_cmd_to_repo; then
        log::info "Your command will be added to the $(txt_underline /src/cli/commands) directory in your local geo-cli repo, by default, which makes it easy to add it to a branch and submit an MR for it.\n"
        log::info "Alternatively, if you are just experimenting and don't plan to commit it to the repo yet, the command file can instead be added outside of the repo, in the $(txt_underline 'user commands') directory ($(txt_underline '~/.geo-cli/data/commands')).\n"
        log::info "This way you can still remain on the main geo-cli repo branch, making it easier to keep geo-cli up-to-date (since you wouldn't have to deal with any conflicts from your own local changes).\n"
        log::detail "Answering 'no' to the following prompt will result in your command being added to the $(txt_underline 'user commands') directory"
        if ! prompt_continue "Add command to repo (default)? (Y|n): "; then
            echo
            log::status "Adding command to the $(txt_underline 'user commands') directory"
            sleep 1
            log::info "If you would like to have your command added to the main geo-cli repo branch, making it available to all geo-cli users, move your command file/directory to the repo commands directory. Then add it to a branch and submit an MR for it."
            sleep 1
            add_cmd_to_repo=false
            command_file_dir="$local_cmd_dir$command_dir_name"
        fi
        
    fi
    echo
    
    local command_file="$command_file_dir/$command_file_name"

    # Add command to the geo-cli config dir so that the user doesn't have to commit anything or create an MR.
    if $add_cmd_to_repo; then
        log::status "Adding new command file to the geo-cli repo"
        sleep 1
        echo
    fi
    local existing_command_file=
    if [[ -f $command_file && existing_command_file="$(cat $command_file)" && -n $existing_command_file ]]; then
        log::warn "Command file already exists at $command_file"
        log::warn "Existing file content:"
        log::code "$existing_command_file"
        prompt_continue "Overwrite existing command file? (Y|n): " || return 1
        echo
    fi

    log::link "$command_file\n"
    prompt_continue "Create file for new command named '$cmd_name' at the above path? (Y|n): " || return 1

    # Create the command's directory (if it doesn't already exist).
    mkdir -p "$command_file_dir"

    echo
    # Fill in the cmd name into the template file.
    local cmd_date=$(date +%Y-%m-%d)
    local cmd_author="$(git config user.email)"
    cmd_author=${cmd_author:-"$USER@geotab.com"}

    local command_file_text="$(cat "$template_file" | sed -E "s/new_command_name/$cmd_name/g; s/command_author/$cmd_author/g; s/command_date/$cmd_date/g")"
    [[ -z $command_file_text ]] && log::Error "Failed to substitute command name into template file: $command_file_text" && return 1

    echo "$command_file_text"  > "$command_file" \
        || { log::Error "Failed to write command file to $command_file"; return 1; }
    
    sleep .3
    log::success "Command file created"
    log::file "$command_file"
    sleep .5
    echo
    log::status "Trying to source command file..."
    . "$command_file" && log::success 'OK' || { log::Error "Failed to source command file"; return 1; }
    sleep .3
    echo 
    log::info "The new command should be available in this terminal if it is a bash shell."
    log::info "Try it here or open a new terminal and run:"
    log::code "  geo $cmd_name test\n"

    sleep .2
    
    if $add_cmd_to_repo && prompt_continue "Would you like to create a branch for this command now? (Y|n): "; then
        local branch_name="add-geo-$cmd_name-command"
        if ! prompt_continue "Name new branch '$branch_name'? (Y|n)"; then
            branch_name=
            local first_iteration=true
            until _geo_is_valid_git_new_branch_name "$branch_name"; do
                ! $first_iteration && log::warn "Branch '$branch_name' already exists or is invalid." && first_iteration=false
                prompt_for_info -v branch_name "Enter branch name: "
            done

            log::status "Creating branch"
            if git checkout -b $branch_name; then
                git add $command_file
            else
                echo
                log::Error "Failed to create branch"
            fi
        fi
    fi

    sleep .7

    log::info "Next step: Add logic to the command file.\n"
    log::hint "* Please submit an MR with your new command if you think it would be useful to others.\n"

    sleep 1

    if prompt_continue "Open command file now in VS Code? (Y|n) : "; then
        if $add_cmd_to_repo; then
            # Open the geo-cli repo folder in a new vs code session.
            code -n "$GEO_CLI_DIR"
        else
            # Otherwise, open the user command folder in a new vs code session.
            code -n "$local_cmd_dir"
        fi
        # Open command file in vs code.
        code -r "$command_file"
    fi
    log::success Done
}

_geo_cmd_remove() {
    local cmd_name="$1"
    local has_own_directory=false
    [[ -z $cmd_name ]] && log::Error "No command namd supplied" && return 1
    _geo_cmd_exists "$cmd_name" || { log::Error "Command '$cmd_name' doesn't exist" && return 1; }
    
    local cmd_file_path=$(_geo_cmd_get_file_path $cmd_name)
    local cmd_directory_path="$(_geo_cmd_get_file_path -d $cmd_name)"
    # local -n cmd_file_path="${cmd_name}_command_file_path"
    # local -n cmd_directory_path="${cmd_name}_command_directory_path"
    # log::debug "[[ -z $cmd_file_path || ! -f $cmd_file_path ]]"

    # log::debug _"$cmd_directory_path"_
    [[ ! -f $cmd_file_path && ! -d $cmd_file_path ]] && log::Error "Command file wasn't found at: '$cmd_file_path'" && return 1
    
    _geo_cmd_has_own_dir $cmd_name && has_own_directory=true
    # local command_file="$GEO_CLI_USER_COMMAND_DIR/geo-${cmd_name}.cmd.sh"
    # [[ ! -f $command_file ]] && log::warn "Command file not found at: $command_file" && return 1

    local delete_path=
    if $has_own_directory; then
        log::warn "The following file(s) will be deleted:"
        delete_path="$cmd_directory_path"
        log::code " * $cmd_directory_path"
        log::code "$(find "$cmd_directory_path" | sed -E 's/^/   * /g' | tail -n +2)"
    else
        log::warn "The following file will be deleted:"
        delete_path="$cmd_file_path"
        log::code " * $cmd_file_path"
    fi
    echo
    log::warn -b "WARNING: This cannot be undone"
    echo
    prompt_continue -afw "Delete the above file(s)?" || return 1
    log::status "Deleting command file"
    rm -Rv "$delete_path" || { log::Error "Failed to delete command file" && return 1; }
    # . ~/.bashrc
    echo
    log::detail "The command will no longer be available in new terminals, but may still be available in open ones."
    echo
    log::success 'Done'
}

_geo_cmd_ls() {
    list_repo_cmd_files=true
    [[ $1 == -r ]] && list_repo_cmd_files=true
#     GEO_CLI_COMMAND_DIR
# GEO_CLI_USER_COMMAND_DIR

    log::data_header --pad "User Command Files"

    local user_cmd_files="$(find "$GEO_CLI_USER_COMMAND_DIR" -name '*.cmd.sh' 2> /dev/null)"
    if [[ -n $user_cmd_files ]]; then
        # ls "$GEO_CLI_USER_COMMAND_DIR"
        # local user_cmd_files=$(find "$GEO_CLI_USER_COMMAND_DIR" -name '*.cmd.sh')
        for cmd_file in $user_cmd_files; do
            log::code "  * $cmd_file"
        done
    else
        log::detail "No user command files were found"
    fi

    log::info "These user commands (created via geo cmd create) are available (only to you) through geo-cli via 'geo <command>'. They are stored in: "
    log::file "$GEO_CLI_USER_COMMAND_DIR"
    
    ! $list_repo_cmd_files && return

    echo
    log::data_header --pad "Repo Command Files"
    if [[ -d $GEO_CLI_COMMAND_DIR && $(ls -A $GEO_CLI_COMMAND_DIR | wc -l) -ge 2 ]]; then
        # ls "$GEO_CLI_COMMAND_DIR" | sed 's/geo-cmd.cmd.sh.example//g'
          (  
            cd "$GEO_CLI_SRC_DIR"
            local all_cmd_files="$(find "$GEO_CLI_SRC_DIR/cli/commands" -name '*.cmd.sh')"
            # log::data "$all_cmd_files"
            # TODO: log in different colour if cmd file belongs to user.
            # git log --format=%ae gateway.py | tail -1
            # git status --format=%ae gateway.py | tail -1

            for cmd_file in $all_cmd_files; do
                local isUntracked=false
                local createdByUser=false
                local user="$(git config user.email)"
                user="${user:-$USER}"
                [[ -n $(git status "$cmd_file" | grep Untracked) ]] && isUntracked=true
                [[ -n $(git log --follow --format=%ae "$cmd_file" | tail -1 | grep "$user") ]] && createdByUser=true

                # Print the file in a different if it belongs to the user.
                $isUntracked || $createdByUser \
                    && log::code "  * $cmd_file" \
                    || log::data "  * $cmd_file"
            done

            log::info "These commands are available through geo-cli via 'geo <command>'. They are available to all geo-cli users (once merged into the main geo-cli branch). They are stored in: "
            log::file "$GEO_CLI_COMMAND_DIR"
        )
        # ls -lh "$GEO_CLI_COMMAND_DIR"
    else
        log::detail "No repo command files were found"
    fi
}

_geo_cmd_edit() {
    local cmd_name="$1"
    [[ -z $cmd_name ]] && log::Error "No command namd supplied" && return 1
    _geo_cmd_exists "$cmd_name" || { log::Error "Command '$cmd_name' doesn't exist" && return 1; }
    
    local cmd_in_repo=true
    local -n cmd_file_path="${cmd_name}_command_file_path"
    local -n cmd_directory_path="${cmd_name}_command_directory_path"
    [[ -z $cmd_file_path || ! -f $cmd_file_path ]] && log::Error "Command file wasn't found at: $cmd_file_path" && return 1
    [[ $cmd_directory_path =~ $GEO_CLI_COMMAND_DIR ]] || cmd_in_repo=false
    
    log::status "Opening command file"
    log::link "$cmd_file_path"
    if $cmd_in_repo; then
        # Open the geo-cli repo folder in a new vs code session.
        code -n "$GEO_CLI_DIR"
    else
        # Otherwise, open the user command folder in a new vs code session.
        code -n "$GEO_CLI_USER_COMMAND_DIR"
    fi
    # Open command file in vs code.
    code -r "$cmd_file_path"
}

_geo_cmd_has_own_dir() {
    local cmd_name="$1"
    local cmd_path="$(_geo_cmd_get_file_path -d "$cmd_name")"
    local cmd_dir_name="geo-$cmd_name"
    [[ $cmd_path =~ $cmd_dir_name$ ]]
}

# -d option gets just the directory name.
_geo_cmd_get_file_path() {
    local dirname_only=false
    [[ $1 == -d ]] && dirname_only=true && shift
    local cmd_name="$1"
    [[ -z $cmd_name ]] && return 1
    _geo_cmd_exists "$cmd_name" || return 1
    cmd_name="geo-$cmd_name"
    local cmd_path="$(echo "${GEO_COMMAND_FILE_PATHS[@]}" | sed 's_/home/_\n/home/_g' | grep "$cmd_name")"
    cmd_path="${cmd_path% }"
    [[ -z $cmd_path ]] && return 1
    $dirname_only && echo "${cmd_path%/*}" || echo "$cmd_path" 
}

# _geo_cmd_valid() {
#     local cmd="$1"
#     if _geo_cmd_exists "$cmd_name"; then
#         log::warn "Command '$cmd_name' already exists"
#         prompt_continue "Continue anyways? (Y|n) : " || return 1
#     fi
#     _geo_cmd_exists "$cmd_name"
# }