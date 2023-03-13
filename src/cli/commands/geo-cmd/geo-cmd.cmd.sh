#!/bin/bash
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

@register_geo_cmd  'cmd'
@geo_cmd_doc() {
  doc_cmd 'cmd'
      doc_cmd_desc "Commands for creating and updating custom geo-cli commands (i.e., 'geo <command_name>'). These commands are stored in files and automatically loaded into geo-cli (by cli-handlers.sh). You can either create a geo command for local use only OR you can have the command file added to the geo-cli repo. Add the command to the repo if you want to submit an MR for it to make it available for all geo-cli users."
      
      doc_cmd_sub_cmd_title
      
      doc_cmd_sub_cmd 'create <command_name>'
          doc_cmd_sub_cmd_desc "Creates a new command file."
        #   "These files are automatically loaded into geo-cli by cli-handlers.sh and are available in all terminals via 'geo <command_name>'). They are stored in the geo-cli repo in the /src/cli/commands directory. If you want to make your command available to all geo-cli users, please create a branch with your command and submit an MR for it. Alternatively, you can also create the command outside of the repo if you are just experimenting with the command and don't want to commit anything to the repo."
        #   doc_cmd_sub_option_title
        #       doc_cmd_sub_option '-r'
        #           doc_cmd_sub_option_desc 'Creates the new command file in the geo-cli repo directory instead of in ~/.geo-cli/data/commands. This makes it easy to create an MR with the new command if you would like to share it with others.'
        #       doc_cmd_sub_option '-d <database name>'
        #           doc_cmd_sub_option_desc 'Sets the name of the db to...'
        doc_cmd_sub_cmd 'rm <command_name>'
          doc_cmd_sub_cmd_desc 'Removes a command file.'
        doc_cmd_sub_cmd 'ls'
          doc_cmd_sub_cmd_desc 'Lists all command files.'
        #   doc_cmd_sub_option '-r'
        #           doc_cmd_sub_option_desc 'Also lists the command files in the geo-cli repo directory. They are located in the /src/cli/commands directory.'
        doc_cmd_sub_cmd 'edit <command_name>'
          doc_cmd_sub_cmd_desc 'Opens the command up for editing in VS Code'

      doc_cmd_examples_title
          doc_cmd_example 'geo cmd create ping'
          doc_cmd_example 'geo cmd rm ping'
          doc_cmd_example 'geo cmd ls'
}
@geo_cmd() {
    # local OPTIND
    # while getopts "v:" opt; do
    #     case "${opt}" in
    #         # v ) [[ $OPTARG =~ ^[[:digit:]]+$ ]] && pg_version=$OPTARG ;;
    #         : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
    #         \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
    #     esac
    # done

    # shift $((OPTIND - 1))
    local cmd="$1"

    shift

    case "$cmd" in
        create )
            @geo_cmd::create "$@"
            ;;
        rm | remove )
            @geo_cmd::remove "$@"
            ;;
        ls | list )
            @geo_cmd::ls "$@"
            ;;
        edit )
            @geo_cmd::edit "$@"
            ;;
        * ) 
            [[ -z $cmd ]] && log::Error "No arguments provided" && return 1 
            log::Error "The following cmd is unknown: $cmd" && return 1 
            ;;
    esac
}

@geo_cmd::create() {
    local force_create=false
    local add_cmd_to_repo=true
    local create_cmd_directory=true

    local OPTIND
    while getopts ":frD" opt; do
        case "${opt}" in
            f ) force_create=true ;;
            r ) add_cmd_to_repo=true ;;
            D ) create_cmd_directory=false ;;
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    
    local template_file="$GEO_CLI_COMMAND_DIR/geo-cmd/geo-cmd-template.sh"
    # local template_file="$GEO_CLI_SRC_DIR/includes/commands/geo-cmd-template.sh"

    local cmd_name="$1"

    if _geo__is_registered_cmd "$cmd_name"; then
        log::warn "Command '$cmd_name' already exists"
        prompt_continue "Continue anyways? (Y|n) : " || return 1
    fi
    
    [[ ! -f $template_file ]] && log::Error "Couldn't find template file at $template_file" && return 1

    local alphanumeric_re='^[^-_0-9]([-[:alnum:]]+)$'
    [[ ! $cmd_name =~ $alphanumeric_re ]] && log::Error "Invalid command name. Command names MUST contain only alphanumeric characters (including -_)." && return 1

    log::status -b "Initializing new geo-cli command '$cmd_name'"
    local command_dir_name=
    # log::detail "You can create your command inside of its own directory, called '@geo_$cmd_name', if its logic requires additional files (i.e. it executes other scripts or parses static data from a text file)."
    # if prompt_continue "Create command in its own directory? (Y|n): "; then
    #     command_dir_name="/geo-$cmd_name"
    # fi
    $create_cmd_directory && command_dir_name="/geo-$cmd_name"
    echo

    # The new command file.
    local command_file_name="geo_${cmd_name}.cmd.sh"
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
            command_file_dir="${local_cmd_dir}${command_dir_name}"
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
    [[ -f $command_file ]] && local existing_command_file="$(cat "$command_file")"
    if [[ -f $command_file && -n $existing_command_file ]]; then
        log::warn "Command file already exists at $command_file"
        log::warn "Existing file content:"
        log::code "$(head -10 <<<"$existing_command_file")"
        log::code "..."
        prompt_continue "Overwrite existing command file? (Y|n): " || return 1
        echo
    fi

    sleep 1
    log::link -r "$command_file\n"
    prompt_continue "Create file for new command named '$cmd_name' at the above path? (Y|n): " || return 1

    echo
    # Fill in the cmd name into the template file.
    local cmd_date=$(date +%Y-%m-%d)
    local cmd_author="$(git config user.email)"
    cmd_author=${cmd_author:-"$USER@geotab.com"}

    # Capitalized command name.
    local CMD_NAME="${cmd_name^^}"
    local command_file_text="$(cat "$template_file" | sed -E "s/\{\{new_command_name\}\}/$cmd_name/g; s/NEW_COMMAND_NAME/$CMD_NAME/g; s/\{\{command_author\}\}/$cmd_author/g; s/\{\{command_date\}\}/$cmd_date/g; ")"
    [[ -z $command_file_text ]] && log::Error "Failed to substitute command name into template file: $command_file_text" && return 1

    # Create the command's directory (if it doesn't already exist).
    mkdir -p "$command_file_dir"

    echo "$command_file_text"  > "$command_file" \
        || { log::Error "Failed to write command file to $command_file"; return 1; }
    
    # _geo_jq_props_to_json -t name $cmd_name repo "$add_cmd_to_repo"

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

@geo_cmd::remove() {
    local cmd_name="$1"
    local has_own_directory=false
    [[ -z $cmd_name ]] && log::Error "No command named supplied" && return 1
    _geo__is_registered_cmd "$cmd_name" || { log::Error "Command '$cmd_name' doesn't exist" && return 1; }
    
    local cmd_file_path=$(_geo_cmd__get_file_path $cmd_name)
    local cmd_directory_path="$(_geo_cmd__get_file_path -d $cmd_name)"
    # local -n cmd_file_path="${cmd_name}_command_file_path"
    # local -n cmd_directory_path="${cmd_name}_command_directory_path"
    # log::debug "[[ -z $cmd_file_path || ! -f $cmd_file_path ]]"

    # log::debug _"$cmd_directory_path"_
    [[ ! -f $cmd_file_path && ! -d $cmd_file_path ]] && log::Error "Command file wasn't found at: '$cmd_file_path'" && return 1
    
    _geo_cmd__has_own_dir $cmd_name && has_own_directory=true
    # local command_file="$GEO_CLI_USER_COMMAND_DIR/geo-${cmd_name}.cmd.sh"
    # [[ ! -f $command_file ]] && log::warn "Command file not found at: $command_file" && return 1

    local delete_path=
    if $has_own_directory; then
        delete_path="$cmd_directory_path"
        local files="$(find "$cmd_directory_path")"
        local file_count="$( echo "$files" | wc -l)"

        log::warn "The following $file_count file(s)/directories will be deleted:"
        log::code -r " * $cmd_directory_path"
        log::code -r "$(echo "$files" | sed -E "s/^/   - /g;" | tail -n +2)"
        # log::code "$(echo "$files" | sed -E "s/^/   - /g; s%$cmd_directory_path/%%g" | tail -n +2)"
    else
        log::warn "The following file will be deleted:"
        delete_path="$cmd_file_path"
        log::code " * $cmd_file_path"
    fi
    echo
    log::warn -b "WARNING: This cannot be undone"
    echo
    prompt_continue -afw "Delete the above file(s)?" || return 1
    log::status "Deleting command files\n"
    rm -Rv "$delete_path" || { log::Error "Failed to delete command file" && return 1; }
    # . ~/.bashrc
    echo
    log::detail "The command will no longer be available in new terminals, but may still be available in open ones."
    echo
    log::success 'Done'
}

_geo_cmd__get_cmd_files() {
    local write_to_caller_variable=false
    local silent=true
    local print_to_stdout=false
    local cmd_files=
    local get_repo_cmd_files=true
    local cmd_dir=("$GEO_CLI_COMMAND_DIR")
    [[ $1 == -v ]] && local -n caller_var_ref=$2
    while [[ -n $1 && $1 =~ ^-{1,2} ]]; do
        opt="$(echo $1 | sed -E 's/^-{1,2}//g')"
        case "${opt}" in
            a | all ) cmd_dir=("$GEO_CLI_USER_COMMAND_DIR" "$GEO_CLI_COMMAND_DIR") ;;
            u | user ) cmd_dir=("$GEO_CLI_USER_COMMAND_DIR") && get_repo_cmd_files=false ;;
            r | repo ) cmd_dir=("$GEO_CLI_COMMAND_DIR") && get_repo_cmd_files=true ;;
            v | var ) 
                local -n caller_var_ref="$2"
                write_to_caller_variable=true
                shift
                ;;
            p | print ) print_to_stdout=true ;;
            # s | silent ) silent=true ;;
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: $1"; return 1 ;;
        esac
        shift
    done
    
    local cmd_files="$(find "${cmd_dir[@]}" -name '*.cmd.sh' 2> /dev/null)"
    # log::debug local cmd_files="\$(find "${cmd_dir[@]}" -name '*.cmd.sh' 2> /dev/null)"
    $write_to_caller_variable && caller_var_ref="$cmd_files"
    ! $print_to_stdout && return
    echo "$cmd_files"
}

_geo_cmd__get_cmd_name_from_file_path() {
    local write_to_caller_var=false
    local print_to_stdout=true
    [[ $1 == -v ]] && local -n caller_var_ref="$2" && write_to_caller_var=true && print_to_stdout=false && shift 2
    [[ $1 == -V ]] && local -n caller_var_ref="$2" && write_to_caller_var=true && shift 2
    local cmd_file_path="$1"
    [[ ! $cmd_file_path =~ '.cmd.sh'$ ]] && log::Error "_geo_get__cmd_name_from_file_path: The file path provided is not for a geo-cli command file (it must end with '.cmd.sh'): '$cmd_file_path'"
    local cmd_file_name="${cmd_file_path##*/geo-}"
    # log::debug "cmd_file_name $cmd_file_name"
    local cmd_name="${cmd_file_name%.cmd.sh}"
    # log::debug "cmd_name $cmd_name"
    $write_to_caller_var && caller_var_ref="$cmd_name"
    $print_to_stdout && echo "$cmd_name"
    return 0
}

@geo_cmd::ls() {
    local list_repo_cmd_files=true
    [[ $1 == -R ]] && list_repo_cmd_files=false
    # [[ $1 == -r ]] && list_repo_cmd_files=true
    log::info "These commands are available through geo-cli via 'geo <command>'"
    log::data_header --pad "User Command Files"

    # local user_cmd_files="$(find "$GEO_CLI_USER_COMMAND_DIR" -name '*.cmd.sh' 2> /dev/null)"
    local user_cmd_files=
    _geo_cmd__get_cmd_files --user -v user_cmd_files
    if [[ -n $user_cmd_files ]]; then
        # ls "$GEO_CLI_USER_COMMAND_DIR"
        # local user_cmd_files=$(find "$GEO_CLI_USER_COMMAND_DIR" -name '*.cmd.sh')
        for cmd_file_path in $user_cmd_files; do
            # local cmd_file_name="$(echo "$cmd_file_path
            # local cmd_file_name=${$cmd_file_path
            local cmd_name=
            _geo_cmd__get_cmd_name_from_file_path -v cmd_name "$cmd_file_path"
            [[ -n "$cmd_name" ]] && cmd_name=" [$cmd_name] "
            log::code -r "  *$cmd_name $cmd_file_path"
        done
    else
        log::detail "No user command files were found"
    fi
    echo
    log::info "These user commands (created via geo cmd create) are available (only to you) through geo-cli via 'geo <command>'. They are stored in: "
    log::file "$GEO_CLI_USER_COMMAND_DIR"
    
    ! $list_repo_cmd_files && return

    echo
    log::data_header --pad "Repo Command Files"
    if [[ -d $GEO_CLI_COMMAND_DIR && $(ls -A "$GEO_CLI_COMMAND_DIR" | wc -l) -ge 2 ]]; then
        # ls "$GEO_CLI_COMMAND_DIR" | sed 's/geo-cmd.cmd.sh.example//g'
          (  
            cd "$GEO_CLI_SRC_DIR"
            local all_cmd_files="$(find "$GEO_CLI_SRC_DIR/cli/commands" -name '*.cmd.sh')"
            # log::data "$all_cmd_files"
            # TODO: log in different colour if cmd file belongs to user.
            # git log --format=%ae gateway.py | tail -1
            # git status --format=%ae gateway.py | tail -1

            # Print out all repo command files
            for cmd_file in $all_cmd_files; do
                local is_untracked=false
                local created_by_user=false
                local user="$(git config user.email)"
                user="${user:-$USER}"
                [[ -n $(git status "$cmd_file" | grep Untracked) ]] && is_untracked=true
                [[ -n $(git log --follow --format=%ae "$cmd_file" | tail -1 | grep "$user") ]] && created_by_user=true

                # Print the file in a different if it belongs to the user.
                if $is_untracked || $created_by_user; then
                    log::code -r "  * $cmd_file"
                else
                    log::data -r "  * $cmd_file"
                fi
            done

            echo
            log::info "These commands are available through geo-cli via 'geo <command>'. They are available to all geo-cli users (once merged into the main geo-cli branch). They are stored in: "
            log::file "$GEO_CLI_COMMAND_DIR"
        )
    else
        log::detail "No repo command files were found"
    fi
}

@geo_cmd::edit() {
    local cmd_name="$1"
    [[ -z $cmd_name ]] \
        && log::Error "No command name supplied" && return 1
    ! _geo__is_registered_cmd "$cmd_name" \
        && log::Error "Command '$cmd_name' doesn't exist" && return 1
    
    local cmd_in_repo=true
    local cmd_file_path="$(_geo_cmd__get_file_path $cmd_name)"
    local cmd_directory_path="${cmd_file_path%/*}"
    # local -n cmd_file_path="${cmd_name}_command_file_path"
    # local -n cmd_directory_path="${cmd_name}_command_directory_path"

    [[ ! -f $cmd_file_path ]] \
        && log::Error "Command file wasn't found at: $cmd_file_path" \
        && return 1
    [[ $cmd_directory_path =~ $GEO_CLI_COMMAND_DIR ]] \
        || cmd_in_repo=false
    
    log::status "Opening command file at:"
    log::link -r "$cmd_file_path"

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

_geo_cmd__has_own_dir() {
    local cmd_name="$1"
    local cmd_path="$(_geo_cmd__get_file_path -d "$cmd_name")"
    local cmd_dir_name="geo-$cmd_name"
    [[ $cmd_path =~ $cmd_dir_name$ ]]
}

# -d option gets just the directory name.
_geo_cmd__get_file_path() {
    local dirname_only=false
    [[ $1 == -d ]] && dirname_only=true && shift
    
    local cmd_name="$1"
    [[ -z $cmd_name ]] && return 1

    local cmd_func_name="geo_$cmd_name"
    _geo__is_registered_cmd "$cmd_name" || return 1

    local cmd_file_name="geo-$cmd_name.cmd.sh"
    local cmd_path="$(echo "${GEO_COMMAND_FILE_PATHS[@]}" | sed 's_/home/_\n/home/_g' | grep "$cmd_file_name")"
    
    # Remove trailing space.
    cmd_path="${cmd_path% }"

    if [[ -z $cmd_path ]]; then
        if type $cmd_func_name | grep "is a function" > /dev/null; then
            log::Error "Failed to find path for command file, but the command function '$cmd_func_name' is loaded in this terminal."
        fi
        return 1
    fi
    $dirname_only && echo "${cmd_path%/*}" || echo "$cmd_path" 
}

# _geo_cmd__valid() {
#     local cmd="$1"
#     if _geo__is_registered_cmd "$cmd_name"; then
#         log::warn "Command '$cmd_name' already exists"
#         prompt_continue "Continue anyways? (Y|n) : " || return 1
#     fi
#     _geo__is_registered_cmd "$cmd_name"
# }

example_options() {
    local raw
    local force
    local option_parser_def=

    # _geo_make_option_parser \
    #     -o option_parser_def \
    #     --opt 'short=r long=raw var=raw' \
    #     --opt-arg 'short=f long=force var=force'

    _geo_make_option_parser --opt 'short=r long=raw var=raw' --opt-arg 'short=f long=force var=force' -o option_parser_def
    eval "$option_parser_def"
    echo "$option_parser_def"
}

        # -o option_parser_def
# _geo_make_option_parser \
#         --arg 'short=r long=raw var=raw' \
#         --arg 'short=f long=force var=force'
# (^| )(-\w)( *$| )

_geo_make_option_parser() {
    # log::debug "start $@"
    local parser_def=
    # local output_var=
    local output_to_caller_variable=false
    local opt_count=0
    local short_opts=()
    local long_opts=()
    local option_variables=()
    local expects_argument=()
    local opt_defs=()

    parse_option_def() {
        local requires_argument=false
        [[ $1 == --arg ]] && requires_argument=true && shift
        local option_def="$1"
        local opt_id=$2
        local short_opt=
        local long_opt=

        local regex="^-{1,2}[[:alnum:]]?"
        if [[ $option_def =~ $regex ]]; then
            for arg in $option_def; do
                if [[ $arg =~ ^-- ]]; then
                    (( ${#arg} > 2 )) && long_opt="${arg#--}"
                    long_opts[$opt_id]="$long_opt"
                elif  [[ $arg =~ ^-[[:alnum:]] ]]; then
                    (( ${#arg} > 1 )) && short_opt="${arg#-}"
                    short_opt[$opt_id]="$short_opt"
                elif  [[ $arg =~ ^@[-_[:alnum:]]{1,} ]]; then
                    local opt_var_name="${arg:1}"
                    local _opt_var_ref="${arg:1}"
                    option_variables[$opt_id]="$opt_var_name"
                    ! $requires_argument && _opt_var_ref="false"
                    # ! $requires_argument && eval "$opt_var=false"
                fi
            done
            # evar long_opts short_opt option_variables
            return
        fi

        if [[ $option_def =~ short=([[:alnum:]]) ]]; then
            short_opt="${BASH_REMATCH[1]}"
            short_opts[$opt_id]="$short_opt"
        fi
        # long_opt=
        # if [[ $option_def =~ short=([[:alnum:]]) ]]; then
        #     short_opt="${BASH_REMATCH[1]}"
        #     short_opts[$opt_id]="$short_opt"
        # fi
        if [[ $option_def =~ long=([-_[:alnum:]]{1,}) ]]; then
        # ere
            long_opt="${BASH_REMATCH[1]}"
            long_opts[$opt_id]="$long_opt"
        fi
        if [[ $option_def =~ var=([[:alnum:]]{1,}) ]]; then
            local opt_var="${BASH_REMATCH[1]}"
            option_variables[$opt_id]="$opt_var"
            ! $requires_argument && { eval "$opt_var=false" || log::Error "eval failed to set output var to false: \"\$opt_var=false\" = '$opt_var=false'"; }
            # if $requires_argument; then
            #     local default_value=
            #     # [[ -z $opt_var ]] && [[ $option_def =~ defa=[[:alnum:]]{1,}=(.{1,}) ]]
            #     # eval "$opt_var=''" 
            # else
            #     eval "$opt_var=false" 
            # fi
        fi
    }

    local OPTIND
    local requires_arg=false
    # log::debug "before while case.1=$1 2=$2"
    while [[ -n $1 && $1 =~ ^-{1,2} ]]; do
        # log::debug "in while case.1=$1 2=$2"
        opt="$(echo $1 | sed -E 's/^-{1,2}//g')"
        case "${opt}" in
            opt | option | opt-arg )
                opt_id=$((opt_count++))
                opt_def="$2"
                opt_defs[$opt_id]="$opt_def"
                requires_arg=false
                [[ $opt == opt-arg ]] \
                    && expects_argument[$opt_id]=true && requires_arg=true \
                    || expects_argument[$opt_id]=false
                
                local reqs_arg_opt=
                $requires_arg && reqs_arg_opt=--arg

                parse_option_def $reqs_arg_opt "$opt_def" $opt_id
                shift
                ;;
            o | output-var ) 
                # log::debug "in output case. 2=$2"
                [[ -n $2 ]] && local -n output_var="$2" && output_to_caller_variable=true && shift
                ;;
            # Stanard error handlers.
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: $1"; return 1 ;;
        esac
        shift
    done

# f() { eval "$(make_option_parser --opt 'short=r long=raw var=raw' --opt-arg 'short=f long=force var=force')"; echo "$raw/$force"; }

    pad='            '

    local takes_arg=
    local opt_variable=
        # [[ -z \$option ]] && local option=\"\$(echo \"\$1\" | sed -E 's/^-{1,2}//g')\"
    local cases="
        case \$option in"

    for ((i = 0; i < $opt_count; i++)); do
        local short_opt="${short_opts[$i]}"
        local long_opt="${long_opts[$i]}"
        local takes_arg="${expects_argument[$i]:-false}"
        local opt_variable="${option_variables[$i]:-_null_var}"
        local opt_params=()
        $takes_arg && opt_params+=(-a)
        [[ -n $short_opt ]] && opt_params+=(-s "$short_opt")
        [[ -n $long_opt ]] && opt_params+=(-l "$long_opt")
        [[ -n $opt_variable ]] && opt_params+=(-v "$opt_variable")
        opt_case="$(make_case_for_option "${opt_params[@]}")"
        # log::debug -V opt_case
        cases+="$opt_case"
    done

    cases+="
            : ) log::Error \"Option '\${option}' expects an argument.\"; return 1 ;;
            \? ) log::Error \"Invalid option: \$1\"; return 1 ;;
        esac"
    
    read -r -d '' parser_def <<-'EOF'
while [[ -n $1 && $1 =~ ^-{1,2} ]]; do
    local multi_option=false
    is_long_opt=false
    local raw_option="$1"
    local option="$(echo "$raw_option" | sed -E 's/^-{1,2}//g')"

    local is_last_option_in_group=true
    [[ $1 =~ ^-- ]] && is_long_opt=true
    option_count="${#option}"
    $is_long_opt && option_count=1
    local option_group=
    ((option_count > 1)) && is_last_option_in_group=false && option_group=$option
    for ((i = 0; i < option_count; i++)); do
        ! $is_long_opt && [[ -n $option_group ]] \
            && option="${option_group:$i:1}"
        (( i == option_count - 1 )) && is_last_option_in_group=true || is_last_option_in_group=false
EOF
    parser_def+="
        $cases
        [[ -n \$option_group ]] && continue
        shift
    done
done"
    # echo "$parser_def"
    $output_to_caller_variable && output_var="$parser_def" || echo "$parser_def"
    return
}

make_case_func_option() {
    local func_def=
    # local func_def='    parse_option() {'
}
make_case_for_option() {
        local requires_arg=false
        [[ $1 == --arg ]] && requires_arg=true && shift
        local condition=
        local long_opt=
        local short_opt=
        local __var_name=
        local OPTIND
        while getopts "al:s:v:c:" opt; do
            case "${opt}" in
                a ) requires_arg=true ;;
                l ) long_opt="$OPTARG" ;;
                s ) short_opt="$OPTARG" ;;
                v ) __var_name="$OPTARG" ;;
                c ) condition="$OPTARG" ;;
                : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
                \? ) log::Error "Invalid option: $1"; return 1 ;;
            esac
        done
        shift $((OPTIND - 1))
        
        if [[ -n $short_opt ]]; then
            [[ -n $long_opt ]] \
                && condition="$short_opt | $long_opt" \
                || condition="$short_opt"
        elif [[ -n $long_opt ]]; then
            condition="$long_opt"
        fi

        local var_assignment="$__var_name=true"
        local arg_check="\$requires_arg && [[ -z \$2 || \$2 =~ ^-{1,2} || ! \$1 =~ \$option\$ ]] \\
                    && log::Error \"Option '\$option' requires an argument, but wasn't supplied with one\" \\
                    && return 1"
        $requires_arg && var_assignment="$__var_name=\"\$2\" && shift"

        local case_txt="
            $condition )
                requires_arg=$requires_arg
                "
        $requires_arg && case_txt+="$arg_check
                "      
        case_txt+="$var_assignment
                ;;"
        echo "$case_txt"
        


    }