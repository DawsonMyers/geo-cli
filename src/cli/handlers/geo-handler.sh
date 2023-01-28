
read -r -d '' handler_header <<'EOF'
#**********************************************************************************************************************
# This is a geo-cli handler file. It is automatically executed from cli-handlers.sh when geo-cli is loaded into each 
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
  
#######################################################################################################################
#### Create a new command (e.g. 'geo <some_new_command>')
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
#   geo_command_doc() {...}
#   geo_command() {...}
# Example for the definition of 'geo db' command:
#   COMMAND+=('db')
#   geo_db_doc() {...}
#   geo_db() {...}
#
## Start off a new command definition by making a copy of the template above and fill in your own logic. 
# Some example documentation functions are also included in the template. They take care of formatting/colouring the
# text when printing it out for the user. Replace the example documentation with your own.
#------------------------------------------------------------
# Template:
#######################################################################################################################
# COMMANDS+=('command')
# geo_command_doc() {
#   doc_cmd 'command'
#       doc_cmd_desc 'Commands description.'
#       
#       doc_cmd_sub_cmds_title
#       
#       doc_cmd_sub_cmd 'start [options] <name>'
#           doc_cmd_sub_cmd_desc 'Creates a versioned db container and...'
#           doc_cmd_sub_options_title
#               doc_cmd_sub_option '-y'
#                   doc_cmd_sub_option_desc 'Accept all prompts.'
#               doc_cmd_sub_option '-d <database name>'
#                   doc_cmd_sub_option_desc 'Sets the name of the db to...'
# 
#       doc_cmd_examples_title
#           doc_cmd_example 'geo db start 11.0'
#           doc_cmd_example 'geo db start -y 11.0'
# }
# geo_command() {
#
# }
#######################################################################################################################
# 
# Also, add a section to the README with instructions on how to use your command.
EOF

export GEO_CLI_HANDLERS_DIR="$GEO_CLI_SRC_DIR/cli/handlers"

COMMANDS+=('handler')
geo_command_doc() {
  doc_cmd 'handler'
      doc_cmd_desc 'Commands for dealing with handler files (command handlers that are external to cli-handlers.sh).'
      
      doc_cmd_sub_cmds_title
      
      doc_cmd_sub_cmd 'create <command_name>'
          doc_cmd_sub_cmd_desc 'Creates a new command handler file.'
        #   doc_cmd_sub_options_title
        #       doc_cmd_sub_option '-y'
        #           doc_cmd_sub_option_desc 'Accept all prompts.'
        #       doc_cmd_sub_option '-d <database name>'
        #           doc_cmd_sub_option_desc 'Sets the name of the db to...'

      doc_cmd_examples_title
          doc_cmd_example 'geo db start 11.0'
          doc_cmd_example 'geo db start -y 11.0'
}
geo_handler() {    
    local OPTIND
    while getopts "v:" opt; do
        case "${opt}" in
            v ) [[ $OPTARG =~ ^[[:digit:]]+$ ]] && pg_version=$OPTARG ;;
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
        esac
    done

    shift $((OPTIND - 1))
    local cmd="$1"

    shift

    case "$cmd" in
        create )
            _geo_handler_create "$@"
            ;;
        rm | remove )
            _geo_handler_remove "$@"
            ;;
        ls | list )
            _geo_handler_ls "$@"
            ;;
        * ) 
            [[ -z $cmd ]] && log::Error "No arguments provided" && return 1 
            log::Error "The following command is unknown: $cmd" && return 1 
            ;;
    esac
}

_geo_handler_create() {
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
    local template_file="$GEO_CLI_SRC_DIR/includes/handlers/geo-handler-template.sh"

    local cmd_name="$1"

    if _geo_cmd_exists "$cmd_name"; then
        log::warn "Command '$cmd_name' already exists"
        prompt_continue "Continue anyways? (Y|n) : " || return 1
    fi
    [[ ! -f $template_file ]] && log::Error "Couldn't find template file at $template_file" && return 1
    local alphanumeric_re='^([[:alnum:]]|[-_])+$'
    [[ ! $cmd_name =~ $alphanumeric_re ]] && log::Error "Invalid command name. Only alphanumeric characters (including -_) are allowed." && return 1

    local handler_file="$GEO_CLI_SRC_DIR/cli/handlers/geo-${cmd_name}.sh"
    local existing_handler_file=
    if [[ -f $handler_file && existing_handler_file="$(cat $handler_file)" && -n $existing_handler_file ]]; then
        log::warn "Hanlder file already exists at $handler_file"
        log::warn "Existing file content:"
        log::code "$existing_handler_file"
        prompt_continue "Overwrite existing handler file? (Y|n): " || return 1
    fi



    prompt_continue "Create new command named '$cmd_name' and handler file for it at '$handler_file'? (Y|n) : " || return 1

    log::status "Creating handler file for new command '$cmd_name'"
    # Fill in the cmd name into the template file.
    local handler_file_text="$(cat "$template_file" | sed -E "s/new_command_name/$cmd_name/g")"
    [[ -z $handler_file_text ]] && log::Error "Failed to substitute command name into template file: $handler_file_text" && return 1

    echo "$handler_file_text"  > "$handler_file" \
        || { log::Error "Failed to write handler file to $handler_file"; return 1; }
    
    log::success "Handler file created"
    log::file "$handler_file"

    log::info "Add the logic to your command to the handler file. You're command should now be accessible in new terminals via:"
    log::code "    geo $cmd_name\n"

    log::status "Trying to source handler file..."
    . "$handler_file" && log::success 'OK' || { log::Error "Failed to source handler file"; return 1; }
    
    log::info "The new command should be available in this terminal if it is a bash shell."
    log::info "Try it here or open a new terminal and run:"
    log::code "    geo $cmd_name test\n"

    prompt_continue "Open handler file now in VS Code? (Y|n) : " && code "$handler_file"
    log::success Done
}

_geo_handler_remove() {
    local cmd_name="$1"
    local handler_file="$GEO_CLI_SRC_DIR/cli/handlers/geo-${cmd_name}.sh"
    [[ ! -f $handler_file ]] && log::warn "Handler file not found at: $handler_file"
    prompt_continue "Delete handler file at $handler_file? (Y|n) : " || return 1
    log::status "Deleting handler file"
    rm "$handler_file" || log::Error "Failed to delete handler file" && return 1
    log::success 'Done'
}

_geo_handler_ls() {
    ls -lh "$GEO_CLI_SRC_DIR/cli/handlers/"
}