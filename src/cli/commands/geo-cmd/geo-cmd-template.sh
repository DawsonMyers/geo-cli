#**********************************************************************************************************************
# This is a geo-cli command file. It is automatically executed from cli-handlers.sh when geo-cli is loaded into each 
# new terminal.
# 
# Author: command_author
# Created: command_date
# 
# All of the exported constants and functions available to geo-cli are available here.
#**********************************************************************************************************************

# * NOTE: Most of the logic for geo-cli is in cli-handlers.sh. Make sure to check it out for command examples and coding
#         conventions.

# DO NOT REMOVE THESE CONSTANTS! They are used by other commands.
# The full path to this file.
export new_command_name_command_file_path="${BASH_SOURCE[0]}"
# The full path to the directory that this file is in.
export new_command_name_command_directory_path="$(dirname "${BASH_SOURCE[0]}")"

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
#          for every command in the COMMANDS array when the user runs 'geo help' or 'geo -h'.
#   3. Command function
#       - The actual command that gets executed when the user runs 'geo <your_command>'. All the arguments passed to 
#         geo following the command name will be passed to this function as positional arguments (e.g.. $1, $2, ...).
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
#######################################################################################################################
#### Subcommand and helper functions naming conventions
#######################################################################################################################
#   * Top level command functions (e.g. geo <command>): geo_<command>.
#   * Subcommand functions (e.g. geo <command> <sub-command>) or helper functions: geo_<command>_<subcommand>.
#       * It's best to separate the logic for your subcommand into their own functions to increase readability.
#       * Helper functions (e.g. _geo_my_helper_function) should also be prefixed with _geo_ to help prevent them from
#         being overwritten by function definitions in other scripts that are loaded into the terminal environment.
#   * Functions loaded from other files: command_module::function_name (e.g. db_helpers.sh => db_helpers::<func_name>)
#       * If you are planing on creating a utility module script for your command, geo mycmd,, that will have lots of 
#         helper functions in it, naming the script something like mycmd_helpers.sh and naming your function like this
#         mycmd_helpers::<func_name> can help prevent definition overwrites with other functions in your terminal
#         environment. 
#       * Example function definition in mycmd/mycmd_helpers.sh: mycmd_helpers::parse_json() {...}
#           => NOTE: Alway move your command file into its own directory (named after the command, e.g., mycmd/mycmd.cmd.sh)
#                    if it will include other files.
#######################################################################################################################
#### Load other functions or constants from other shell script files
#######################################################################################################################
# use the '. <path to script file.sh>' to execute another script in-place, making all functions defined in it available
# here.
#**********************************************************************************************************************
#*** DON'T FORGET TO ADD A SECTION TO THE README ABOUT YOUR NEW COMMAND ***
#**********************************************************************************************************************

# The COMMANDS array is defined in cli-handlers.sh. It allows geo to check if a command exits when a user runs
# 'geo <command>'.
COMMANDS+=('new_command_name')
geo_new_command_name_doc() {
    # Replace the following template documentation with relevant info about the command.
  doc_cmd 'new_command_name'
      doc_cmd_desc 'Command description. Explain what the command does and how to use it.'
      
      doc_cmd_sub_cmds_title
      
      doc_cmd_sub_cmd 'test [options] <arg>'
          doc_cmd_sub_cmd_desc 'This subcommand takes options and arguments'
          doc_cmd_sub_options_title
              doc_cmd_sub_option '-a'
                  doc_cmd_sub_option_desc "An option that doesn't take an agrument."
              doc_cmd_sub_option '-b <option_arg>'
                  doc_cmd_sub_option_desc "An option that requires an agrument."

    doc_cmd_sub_cmd 'subcommand1'
          doc_cmd_sub_cmd_desc 'An example subcommand with its own function called _geo_new_command_name_subcommand1'
    doc_cmd_sub_cmd 'subcommand1'
          doc_cmd_sub_cmd_desc 'Another example subcommand with its own function called _geo_new_command_name_subcommand2'
    doc_cmd_sub_cmd 'edit'
          doc_cmd_sub_cmd_desc "Opens up the command file for this command in VS Code."
    
      doc_cmd_examples_title
          doc_cmd_example 'geo new_command_name test -a "some_argument"'
          doc_cmd_example 'geo new_command_name test -b "option armument" "subcommand armument"'
          doc_cmd_example 'geo new_command_name subcommand1'
          doc_cmd_example 'geo new_command_name edit'
}
geo_new_command_name() {
    local option_a_supplied=false
    local option_b_argument=
    
    log::caution "Command is unimplemented"

    # Add the options to the getopts "<options to parse>" string. Append ":" to the option if it takes an argument. 
    # For example 'getopts "b:"' will require the -b option to take an arg: 'geo new_command_name -b 22 ...'.
    # The argument will be available below in the $OPTARG variable.
    # google 'bash getopts' for more info on parsing options.
    local OPTIND
    while getopts "ab:" opt; do
        case "${opt}" in
            a ) 
                option_a_supplied=true
                log::debug "Option 'a' was supplied."
                ;;
            b ) 
                option_b_argument=$OPTARG
                log::debug "Option 'b' was supplied with the following argument: $option_b_argument."
                 ;;
            # Generic error handling
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
        esac
    done
    # Shifts out positional args used for options.
    shift $((OPTIND - 1))

    local cmd="$1"
    shift

    # 
    if [[ -z $cmd ]]; then
         log::caution "No arguments provided."
         geo_new_command_name_doc
         prompt_continue "Edit command now in VS Code? (Y|n): " \
            && code $new_command_name_command_file_path
         return 1
    fi

    # This case statement runs the command's subcommand based on what was passed in by the user (e.g. geo new_command_name test).
    case "$cmd" in
        test )
            log::success "Command 'new_command_name' is now available in geo-cli. Add your logic to the command file at $new_command_name_command_file_path"
            prompt_continue "Edit your command now in VS Code? (Y|n): " && code $new_command_name_command_file_path
            ;;
        subcommand1 | subcmd1 )
            # Passes all remaining arguments to the _geo_new_command_name_subcommand1 subcommand function to keep things easy to read.
            # "$@" passes the remaining arguments just as they were passed in here.
            # "$*" concatenates all remaining arguments as a single argument to the subcommand function.
            _geo_new_command_name_subcommand1 "$@"
            ;;
        subcommand2 | subcmd2 )
            _geo_new_command_name_subcommand2 "$@"
            ;;
        edit )
            _geo_cmd_edit new_command_name
            ;;
        * ) 
            # Standard error handling.
            [[ -z $cmd ]] && log::Error "No arguments provided" && return 1 
            log::Error "The following command is unknown: $cmd" && return 1 
            ;;
    esac
}

# Subcommand functions are named like this: _geo_<command_name>_<sub_command_name>
# <Function description>
# Arguments:
#   1: arg description
#   2: arg description
_geo_new_command_name_subcommand1() {
    # Access positional argurments like this: $1, $2, etc.
    log::debug "_geo_new_command_name_subcommand1 $@"
}

_geo_new_command_name_subcommand2() {
    log::debug "_geo_new_command_name_subcommand2 $@"
}