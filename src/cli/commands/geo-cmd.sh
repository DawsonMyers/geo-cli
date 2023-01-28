
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

COMMANDS+=('cmd')
geo_cmd_doc() {
  doc_cmd 'cmd'
      doc_cmd_desc "Commands for creating and updating custom geo-cli commands ('db' is the command in 'geo db'). These custom command are stored in files that are external to main cli-handlers.sh file."
      
      doc_cmd_sub_cmds_title
      
      doc_cmd_sub_cmd 'create <command_name>'
          doc_cmd_sub_cmd_desc 'Creates a new command file.'
        #   doc_cmd_sub_options_title
        #       doc_cmd_sub_option '-y'
        #           doc_cmd_sub_option_desc 'Accept all prompts.'
        #       doc_cmd_sub_option '-d <database name>'
        #           doc_cmd_sub_option_desc 'Sets the name of the db to...'
        doc_cmd_sub_cmd 'rm <command_name>'
          doc_cmd_sub_cmd_desc 'Removes a command file.'
        doc_cmd_sub_cmd 'ls'
          doc_cmd_sub_cmd_desc 'Lists all command files.'

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
    local OPTIND
    while getopts "f" opt; do
        case "${opt}" in
            f ) force_create=true ;;
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

    local command_file="$GEO_CLI_SRC_DIR/cli/commands/geo-${cmd_name}.sh"
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
    local command_file="$GEO_CLI_SRC_DIR/cli/commands/geo-${cmd_name}.sh"
    [[ ! -f $command_file ]] && log::warn "Handler file not found at: $command_file"
    prompt_continue "Delete command file at $command_file? (Y|n) : " || return 1
    log::status "Deleting command file"
    rm "$command_file" || log::Error "Failed to delete command file" && return 1
    log::success 'Done'
}

_geo_cmd_ls() {
    ls -lh "$GEO_CLI_SRC_DIR/cli/commands/"
}