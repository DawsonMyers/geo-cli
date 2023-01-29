
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
# All log functions are prefixed with log:: and are defined in src/utils/log.sh. Try the functions yourself or search
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
export GEO_CLI_LOCAL_COMMAND_DIR="$HOME/.geo-cli/data/commands"

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
                  doc_cmd_sub_option_desc 'Also lists the command files in the geo-cli repo directory. They are located in the src/cli/commands directory.'

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
        * ) 
            [[ -z $cmd ]] && log::Error "No arguments provided" && return 1 
            log::Error "The following cmd is unknown: $cmd" && return 1 
            ;;
    esac
}

_geo_cmd_create() {
    local force_create=false
    local add_cmd_to_repo=false
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

    local command_file_name="geo-${cmd_name}.sh"
    local repo_cmd_file_dir="$GEO_CLI_SRC_DIR/cli/commands"
    local local_cmd_dir="$GEO_CLI_CONFIG_DIR/data/commands"
    mkdir -p "$local_cmd_dir"
    local command_file="$local_cmd_dir/$command_file_name"
    # Add command to to geo-cli config dir so that the user doesn't have to commit anything or create an MR.
    if $add_cmd_to_repo; then
        log::status "Adding new command file to the geo-cli repo"
        log::note "Submit an MR with your new command if you think it would be useful to others."
        command_file="$repo_cmd_file_dir/$command_file_name"
    fi
    local existing_command_file=
    if [[ -f $command_file && existing_command_file="$(cat $command_file)" && -n $existing_command_file ]]; then
        log::warn "Hanlder file already exists at $command_file"
        log::warn "Existing file content:"
        log::code "$existing_command_file"
        prompt_continue "Overwrite existing command file? (Y|n): " || return 1
    fi

    log::link "$command_file\n"
    prompt_continue "Create new command named '$cmd_name' and file for it at path above? (Y|n) : " || return 1

    echo
    log::status "Creating file for new command '$cmd_name'"
    echo
    # Fill in the cmd name into the template file.
    local command_file_text="$(cat "$template_file" | sed -E "s/new_command_name/$cmd_name/g")"
    [[ -z $command_file_text ]] && log::Error "Failed to substitute command name into template file: $command_file_text" && return 1

    echo "$command_file_text"  > "$command_file" \
        || { log::Error "Failed to write command file to $command_file"; return 1; }
    
    echo
    log::success "Command file created"
    log::file "$command_file"

    echo
    log::status "Trying to source command file..."
    . "$command_file" && log::success 'OK' || { log::Error "Failed to source command file"; return 1; }
    
    echo 
    log::info "The new command should be available in this terminal if it is a bash shell."
    log::info "Try it here or open a new terminal and run:"
    log::code "    geo $cmd_name test\n"

    log::info "Next step: Add logic to the command file.\n"

    prompt_continue "Open command file now in VS Code? (Y|n) : " && code "$command_file"
    log::success Done
}

_geo_cmd_remove() {
    local cmd_name="$1"
    local command_file="$GEO_CLI_LOCAL_COMMAND_DIR/geo-${cmd_name}.sh"
    [[ ! -f $command_file ]] && log::warn "Command file not found at: $command_file" && return 1
    prompt_continue "Delete command file at $(txt_underline $command_file)? (Y|n) : " || return 1
    log::status "Deleting command file"
    rm "$command_file" || { log::Error "Failed to delete command file" && return 1; }
    log::success 'Done'
}

_geo_cmd_ls() {
    list_repo_cmd_files=false
    [[ $1 == -r ]] && list_repo_cmd_files=true
#     GEO_CLI_COMMAND_DIR
# GEO_CLI_LOCAL_COMMAND_DIR
    log::status -b "User Command Files"

    if [[ -d $GEO_CLI_LOCAL_COMMAND_DIR && -n $(ls -A $GEO_CLI_LOCAL_COMMAND_DIR) ]]; then
        ls "$GEO_CLI_LOCAL_COMMAND_DIR"
    else
        log::detail "No user command files were found"
    fi

    echo
    log::info "These user commands (created via geo cmd create) are available through geo-cli via 'geo <command>'. They are stored in: "
    log::link "$GEO_CLI_LOCAL_COMMAND_DIR\n"

    ! $list_repo_cmd_files && return

    if [[ -d $GEO_CLI_COMMAND_DIR && $(ls -A $GEO_CLI_COMMAND_DIR | wc -l) -ge 2 ]]; then
        echo
        log::status -b "Repo Command Files"
        ls "$GEO_CLI_COMMAND_DIR" | sed 's/geo-cmd.sh.example//g'
        log::info "These commands (created via geo cmd create -r) are available through geo-cli via 'geo <command>'. They commands are available to all geo-cli users. They are stored in: "
        log::link "$GEO_CLI_COMMAND_DIR\n"
        # ls -lh "$GEO_CLI_COMMAND_DIR"
    else
        log::detail "No command files were found"
    fi
}