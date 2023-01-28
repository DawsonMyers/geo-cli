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

#*** DON'T FORGET TO ADD A SECTION TO THE README ABOUT YOUR NEW COMMAND ***

# The full path to this file.
export new_command_name_handler_file_path="${BASH_SOURCE[0]}"

COMMANDS+=('new_command_name')
geo_new_command_name_doc() {
    # Replace the following template documentation with relevant info about the command.
  doc_cmd 'new_command_name'
      doc_cmd_desc 'Commands description.'
      
      doc_cmd_sub_cmds_title
      
      doc_cmd_sub_cmd 'create [options] <arg>'
          doc_cmd_sub_cmd_desc 'This command takes options and arguments'
          doc_cmd_sub_options_title
              doc_cmd_sub_option '-y'
                  doc_cmd_sub_option_desc 'Accept all prompts.'
              doc_cmd_sub_option '-p <port_number>'
                  doc_cmd_sub_option_desc 'Sets the port for connecting to...'
    
    doc_cmd_sub_cmd 'rm'
          doc_cmd_sub_cmd_desc '...'

      doc_cmd_examples_title
          doc_cmd_example 'geo new_command_name create -p 22 my_db'
          doc_cmd_example 'geo new_command_name create -y my_other_db'
}
geo_new_command_name() {
    local accept_all=false
    local port=21
    
    local OPTIND
    # Add the options to the getopts "" string. Add a : to the option if it takes an argument. 
    # For example 'getopts "p:"' will allow for the -p option to take an arg: 'geo new_command_name -p 22 ...'.
    # The argument will be available below in the $OPTARG variable.
    # google 'bash getopts' for more info on parsing options.
    while getopts "yp:" opt; do
        case "${opt}" in
            y ) 
                accept_all=true
                ;;
            p ) 
                port=$OPTARG ;;
            # Generic error handling
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
        esac
    done
    # Shifts out positional args used for options.
    shift $((OPTIND - 1))

    local cmd="$1"
    shift

    case "$cmd" in
        test )
            # Passes all remaining arguments to the geo_handler_create sub-handler to keep things easy to read.
            log::success "Command 'new_command_name' is now using geo-cli. Add your logic to the handler file at $new_command_name_handler_file_path"
            prompt_continue "Edit your command now in VS Code? (Y|n): " && code $new_command_name_handler_file_path
            ;;
        create )
            # Passes all remaining arguments to the geo_handler_create sub-handler to keep things easy to read.
            _geo_new_command_name_create "$@"
            ;;
        rm | remove )
            _geo_new_command_name_remove "$@"
            ;;
        * ) 
            [[ -z $cmd ]] && log::Error "No arguments provided" && return 1 
            log::Error "The following command is unknown: $cmd" && return 1 
            ;;
    esac
}

# Sub-handler functions are named like this: _geo_<command_name>_<sub_command_name>
_geo_new_command_name_create() {
    log::debug "_geo_new_command_name_create $@"
}

_geo_new_command_name_remove() {
    log::debug "_geo_new_command_name_remove $@"
}