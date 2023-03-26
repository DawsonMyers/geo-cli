#!/bin/bash

# This file contains various logging functions used throughout geo-cli. All public functions have the prefix 'log::'.

# These should already be defined.
# # Gets the absolute path of the root geo-cli directory.
# export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
# export GEO_CLI_SRC_DIR="${GEO_CLI_DIR}/src"

# # Import colour constants/functions.
# . $GEO_CLI_SRC_DIR/utils/colors.sh

# Import colour constants/functions.
# shellcheck source=./colors.sh
. "$GEO_CLI_SRC_DIR"/utils/colors.sh
# shellcheck source=./util.sh
. "$GEO_CLI_SRC_DIR"/utils/util.sh

# Line numbers for traps:
# https://unix.stackexchange.com/questions/151771/getting-wrong-lineno-for-a-trapped-function

# Gets a green ✔ if the function completed with a zoro ret code, otherwise a red ✘.
log::get_symbol_for_exit_code() {
    exit_code=$?
    if [ "$exit_code" != 0 ]; then
        echo -e "$Red✘$Off"
    else
        echo -e "$Green✔$Off"
    fi
    return "$exit_code"
}

# Debug logs are written to stderr, so redirect it to this function when piping to it.
# Example:
#    _geo_validate_server_config  |&  log::filter_ps4_debug_logs
# Note: '|&' is the new error pipe redirect operator (added in Bash 4) is the same as 2>&1.
# Alternatively, you can set BASH_XTRACEFD=1 to set the debug output file descriptor when using 'set -x' (which is what
# PS4 debug prompts are written to). This simplifies filtering debug output. This way, we can set -x and then filter the output like this:
#   BASH_XTRACEFD=1
#   set -x
#   some_command | grep -Ev "patterns to ignore"
#     * The v in 'grep -Ev' means to inVert the match logic, selecting everything that doesn't match the patterns and
#       the 'E' means that we can use Extended regular expressions, which are just normal REs that we don't have to escape
#       (e.g., '\d+\d' can be used instead of '\\d+\\d').
# The stderr has to be piped in for the de
log::filter_ps4_debug_logs() {
    eval "$(util::eval_to_enable_piped_args)"
#    echo "$*"
    echo "$*" | grep -Ev 'log.sh|debug|config-file|cfg_|geo_get|log::|util::|gitprompt|bashrc-utils'
}

# TODO: Use this where needed. Example: log_function() { echo "$@" >&3; }
# standard output may be used as a return value in the functions
# we need a way to write text on the screen in the functions so that
# it won't interfere with the return value.
# Exposing stream 3 as a pipe to standard output of the script itself
exec 3>&1

export -a log_RETURN_CODE_TO_EMOJI
log_RETURN_CODE_TO_EMOJI[0]="$Green✔$Off"
log_RETURN_CODE_TO_EMOJI[1]="$Red✘$Off"

# Regexes for replacing old log function names.
# (\W)(red|green|error|Error|info|detail|data|status|verbose|debug|purple|cyan|yellow|white|_stacktrace|data_header|success|prompt|prompt_n|warn)
# (\W)(warn)
# \W(red|green|error|Error|info|detail|data|status|verbose|debug|purple|cyan|yellow|white|_stacktrace|data_header|success|prompt|prompt_n)
# log::$1

# A function that dynamically creates multiple colour/format variants of logger functions.
# This works by using the eval function to dynamically create new functions each time
# make_logger_function is called.
# Args:
#   1 name: the base name of the logger function (e.g. verbose)
#   2 base_colour: the name of the base colour (from constants in colors.sh)
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
        _log_$name() {
            set +f
            local msg=\"\$@\"
            local options=
            local format_tokens=
            local opts=e

            # Only parse options if a message to be printed was also supplied (allows messages like '-e' to be printed instead of being treated like an option).
            if [[ \$1 =~ ^-[a-zA-Z]+$ && -n \$2 ]]; then
                options=\$1
                msg=\"\${@:2}\"
            fi

            local color_name=$color
            case \$options in
                # Make file paths relative (replace full path of home dir with a tilde).
                *r* )
                    msg=\"\$(log::make_path_relative_to_user_dir \"\$msg\")\"
                    ;;&
                # Remove new line characters.
                *N* )
                    msg=\"\$(log::replace_line_breaks_with_space \"\$msg\")\"
                    ;;&
                # Remove leading/trailing spaces and replace 2 or more consecutive spaces with a single one.
                *S* )
                    msg=\"\$(log::strip_space \"\$msg\")\"
                    ;;&
                # Print current function name.
                *F* )
                    local func_path=\$(get_func_path 3)
                    [[ -n \$func_path ]] && msg=\"\$func_path: \$msg\"
                    ;;&
                # Format text to the width of the terminal.
                *f* )
                    msg=\"\$(log::fmt_text \"\$msg\")\"
                    ;;&
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
                    msg=\$(log::txt_italic \$msg)
                    ;;&
                # Underline
                *u* )
                    msg=\$(log::txt_underline \$msg)
                    ;;&
                # Invert font/background colour
                *v* )
                    msg=\$(log::txt_invert \$msg)
                    ;;&
                # Print variable name and value
                *V* )
                    local var_name=\$msg
                    msg=\"\$(log::keyvalue -v \"\$var_name\")\"
                    # msg=\"\$(log::keyvalue \"\$var_name\" \"\${!var_name}\")\"
                    ;;&
                # Prompt (doesn't add a new line after printing)
                *p* | *n* )
                    opts+=n
                    ;;&
            esac

            # echo interprets '-e' as a command line switch, so a space is added to it so that it will actually be printed.
            re='^ *-e$'
            [[ \$msg =~ \$re ]] && msg+=' '
            [[ \$GEO_RAW_OUTPUT == true ]] && echo -n \"\$msg\" && set +f && return

            echo \"-\${opts}\" \"\${format_tokens}\${!color_name}\${msg}\${Off}\"
            set +f
        }
    "
}

# Make logger function using VTE colours.
# Use display_vte_colors command (defined in colors.sh, should always be loaded in your shell if geo-cli is installed) to
# display VTE colours.
make_logger_function_vte() {
    name=$1
    color=$2

    # eval "${name}() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_b() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${BOLD_ON}\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_i() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_bi() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${BOLD_ON}\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_u() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${UNDERLINE_ON}\${${color}}\${args[@]}\${Off}\"; }"
    eval "${name}_bu() { args=(\"\$@\"); opt=e; if [[ \${args[0]} =~ ^-p ]]; then opt=en; unset \"args[0]\"; fi; echo \"-\${opt}\" \"${BOLD_ON}${UNDERLINE_ON}\${${color}}\${args[@]}\${Off}\"; }"

    eval "
        _log_$name() {
            set -f
            local msg=\"\$@\"
            local options=
            local format_tokens=
            local opts=e

            # Only parse options if a message to be printed was also supplied (allows messages like '-e' to be printed instead of being treated like an option).
            if [[ \$1 =~ ^--$|^-[a-zA-Z]+$ && -n \$2 ]]; then
                options=\$1
                msg=\"\${@:2}\"
            fi

            case \$options in
                # Don't try to parse options if -- was supplied.
                -- ) break ;;
                # Make file paths relative (replace full path of home dir with a tilde).
                *r* )
                    msg=\"\$(log::make_path_relative_to_user_dir \"\$msg\")\"
                    ;;&
                # Remove new line characters.
                *N* )
                    msg=\"\$(log::replace_line_breaks_with_space \"\$msg\")\"
                    ;;&
                # Remove leading/trailing spaces and replace 2 or more consecutive spaces with a single one.
                *S* )
                    msg=\"\$(log::strip_space \"\$msg\")\"
                    ;;&
                # Print current function name.
                *F* )
                    local func_path=\$(get_func_path 3)
                    [[ -n \$func_path ]] && msg=\"\$func_path: \$msg\"
                    ;;&
                # Format text to the width of the terminal.
                *f* )
                    msg=\"\$(log::fmt_text \"\$msg\")\"
                    ;;&
                *b* )
                    format_tokens+=\"$BOLD_ON\"
                    ;;&
                *i* )
                    msg=\$(log::txt_italic \$msg)
                    ;;&
                *u* )
                    msg=\$(log::txt_underline \$msg)
                    ;;&
                *v* )
                    msg=\$(log::txt_invert \$msg)
                    ;;&
                *V* )
                    local var_name=\$msg
                    msg=\"\$(log::keyvalue -v \"\$var_name\")\"
                    # msg=\"\$(log::keyvalue \"\$var_name\" \"\${!var_name}\")\"
                    ;;&
                *p* | *n* )
                    opts+=n
                    ;;&
            esac

            # echo interprets '-e' as a command line switch, so a space is added to it so that it will actually be printed.
            re='^ *-e$'
            [[ \$msg =~ \$re ]] && msg+=' '
            [[ \$GEO_RAW_OUTPUT == true ]] && echo -n \"\${msg}\" && set +f && return

            echo \"-\${opts}\" \"\${format_tokens}\${${color}}\${msg}\${Off}\"
            set +f
        }
    "
}

# TODO: Clean up these functions
get_func_path() {
    local ignore_count=${1:-1}
    # TODO: Remove
#    e BASH_LINENO
#    e LINENO
#    e BASH_SOURCE
    local line_num=${BASH_LINENO[$ignore_count]}
    local file=${BASH_SOURCE[$ignore_count]##*/}
#    local line_num=${BASH_LINENO[$((${#BASH_LINENO[@]} - $ignore_count))]}
    local func_path=
    local func_names="${FUNCNAME[@]:$ignore_count}"
    func_names="${func_names//source}"
#    set -x
    for func in $func_names; do
        [[ $func =~ ^__geo$ || $func =~ ^log:: ]] && continue
        # Skip first so that there isn't '.' at the end of the path (e.g., geo.geo_db.).
        [[ -z $func_path ]] && func_path="$func" && continue
        func_path="$func.$func_path"
    done
    [[ $func_path =~ \.$ ]] && func_path="${func_path: -1}"

    # Remove @ from path.
    func_path="${func_path//@}"

    [[ -n $func_path ]] && echo -n "${func_path} in $file[$line_num]"
#    [[ -n $func_path ]] && echo -n "at: ${func_path} in $file[$line_num]"
#    set +x
    if [[ $(@geo_get LOG_DEBUG_TRACE) == true ]]; then
        echo
        for ((i=0; i < ${#BASH_LINENO[@]}; i++)); do
            log::debug "at ${BASH_SOURCE[i]}[${BASH_LINENO[i]}]::${FUNCNAME[i]}"
        done
    fi
}

get_line_number_in_call_stack() {
    echo "BASH_LINENO = ${BASH_LINENO[*]}"
    local ignore_count=${1:-1}
    # local func_names="${FUNCNAME[@]:ignore_count}"
    echo "BASH_LINENO = ${BASH_LINENO[*]}"
    # echo "BASH_SOURCE = ${BASH_SOURCE[@]}"
    local line_num=${BASH_LINENO[ignore_count]}
    # local line_num=${BASH_LINENO[$((${#BASH_LINENO[@]} - ignore_count))]}
    echo "line_num=$line_num"
    [[ -n $line_num ]] && echo -n "$line_num"
}

get_filename_in_call_stack() {
    local full_path=false
    [[ $1 == -f ]] && full_path=true && shift
    local ignore_count=${1:-1}
    # local func_names="${FUNCNAME[@]:ignore_count}"
    # echo "BASH_LINENO = ${BASH_LINENO[@]}"
    local path=${BASH_SOURCE[ignore_count]}
    path="$(realpath "$path")"
    echo "local path=${BASH_SOURCE[ignore_count]}"
    echo "get_filename_in_call_stack: path = $path"
    local name=${path##*/}
    echo "get_filename_in_call_stack: name = $name"
    [[ -z $path ]] && return 1
    # local line_num=${BASH_LINENO[$((${#BASH_LINENO[@]} - ignore_count))]}

    $full_path && echo -n "$path" && return

    [[ -n $name ]] && echo -n "$name"
}

make_logger_function error Red
log::red() {
    _log_red "$@"
}
make_logger_function_vte warn VTE_COLOR_202 # Orange
log::warn() {
    _log_warn "$@"
}
make_logger_function error Red
log::error() {
    _log_error "$@"
}
make_logger_function info Green
log::info() {
    _log_info "$@"
}
# make_logger_function success Green
# log::success() {
#     _log_success "$@"
# }
make_logger_function detail Yellow
log::detail() {
    _log_detail "$@"
}
# make_logger_function detail Yellow
# log::detail() {
#     _log_detail "$@"
# }
make_logger_function_vte data VTE_COLOR_253
log::data() {
    _log_data "$@"
}
# make_logger_function data White
# log::data() {
#     _log_data "$@"
# }
# make_logger_function warn Purple
# log::warn() {
#     _log_warn "$@"
# }
make_logger_function status Cyan
log::status() {
    _log_status "$@"
}
make_logger_function verbose Purple
log::verbose() {
    _log_verbose "$@"
}
make_logger_function debug Purple
log::debug() {
    _log_debug "$@" >&2
}
# Prints the function path up to the function where this is called.
# Example: a() { b; }; b() { log::trace "here"}
#   Prints: a.b: here
log::trace() {
    # (( $# == 0 )) &&
    # local filename = get_line_number_in_call_stack
    _log_debug -F "$@"
}
make_logger_function purple Purple
log::purple() {
    _log_purple "$@"
}
make_logger_function red Red
log::red() {
    _log_red "$@"
}
make_logger_function cyan Cyan
log::cyan() {
    _log_cyan "$@"
}
make_logger_function yellow Yellow
log::yellow() {
    _log_yellow "$@"
}
log::caution() {
    _log_yellow "$@"
}
log::link() {
    local relative_path=false
    [[ $1 == -r ]] && relative_path=true && shift

    local msg="$@"
    $relative_path && msg="$(log::make_path_relative_to_user_dir "$msg")"
    _log_yellow -u "$msg"
}
log::file() {
    echo "$(_log_purple -n 'file://')$(_log_yellow -u  "$@")"
}
log::filepath() {
    log::file  "$@"
}
make_logger_function green Green
log::green() {
    _log_green "$@"
}
make_logger_function white White
log::white() {
    _log_white "$@"
}
export LOG_COLOUR_FOR_CODE="$VTE_COLOR_115"
make_logger_function_vte code VTE_COLOR_115 # greenish blue
log::code() {
    _log_code "$@"
}
make_logger_function_vte hint VTE_COLOR_135 # purple
log::hint() {
    _log_hint "$@"
}

log::stacktrace() {
# _stacktrace() {
    local make_path_relative_option=-r
    [[ $1 == --full ]] && make_path_relative_option=
    local start=1
    [[ $1 =~ ^- ]] && start=${1:1}
    # debug "start $start"
    local debug_log=$(@geo_get DEBUG_LOG)
    if [[ $debug_log == true ]]; then
        # debug "_stacktrace: ${FUNCNAME[@]}"
        local stacktrace="${FUNCNAME[@]:start}"
        local stacktrace_reversed=
        for f in $stacktrace; do
            [[ -z $stacktrace_reversed ]] && stacktrace_reversed=$f && continue
            stacktrace_reversed="$f -> $stacktrace_reversed"
        done

        log::debug $make_path_relative_option "Stacktrace: $stacktrace_reversed"
    fi
}

# ✘❌
make_logger_function Error BIRed
alias log::Error='log::Error_ --stub "[${BASH_SOURCE}(${BASH_LINENO})::${FUNCNAME}(${LINENO})]: " '

# log::Error() {
#     log::Error_
# }
log::Error_() {
    local calling_func_name="${FUNCNAME[1]}"
    local stub
    local add_to_stack_depth=0
    [[ $1 == --stub && -n $2 ]] && stub="$2" && shift 2
    [[ $1 == --ignore-stack-depth && $2 =~ ^[0-9] ]] && add_to_stack_depth=$2 && shift 2
    echo -e "${BIRed}✘  Error: $(log::fmt_text_and_indent_after_first_line -d 10 -a 10 "$@")${Off}" >&2
    # log::debug "  ↪ $(get_func_path $((2 + add_to_stack_depth)))"
    log::debug "  ↪ $stub"
    # echo -e "❌  ${BIRed}Error: $@${Off}" >&2

    log::stacktrace
}
log::Error_trace() {
    log::Error "$@"
    log::debug "  In function $(get_func_path 2)"
}
log::error() {
    echo -e "${BIRed}✘  $(log::fmt_text_and_indent_after_first_line -d 4 -a 3 "$@")${Off}" >&2
    # echo -e "❌  ${BIRed}$@${Off}" >&2
}
#
log::getopts_option_expects_argument_error() {
    log::Error --ignore-stack-depth 1 "Option '${OPTARG}' expects an argument."
     return 1
}
#
log::getopts_option_invalid_error() {
    log::Error --ignore-stack-depth 1 "Invalid option: ${OPTARG}"
    return 1
}


log::data_header() {
    local header="$@"
    if [[ $1 == --pad ]]; then
        shift
        header="$@"
        local header_length=${#header}
        local terminal_width=$(tput cols $header_length)
        local padding_length=$(( terminal_width - header_length ))
        header="$header$(log::repeat_str ' ' $padding_length)"
    fi
    echo -e "${VTE_COLOR_87}${UNDERLINE_ON}${BOLD_ON}$header${Off}"
    # echo -e "${BIGreen}$@${Off}"
}

log::success() {
    echo -e "${BIGreen}✔${Off}   ${BIGreen}$(log::fmt_text_and_indent_after_first_line -d 4 -a 4 "$@")${Off}"
    # echo -e "${BIGreen}✔${Off}   ${BIGreen}$@${Off}"
}
make_logger_function prompt BCyan
log::prompt() {
    _log_prompt "$@"
}

# Echo without new line
log::prompt_n() {
    echo -en "${BCyan}$*${Off}"
}

# Logging helpers
###########################################################

# Repeat string n number of times.
# 1: a string to repeat
# 2: the number of repeats
log::repeat_str() {
    local write_to_caller_variable=false
    local str="$(printf "$1%.0s" $(seq 1 "$2"))"
    [[ $1 == -v ]] && local -n caller_var_ref="$2" && caller_var_ref="$str" && return
    echo "$str"
}
# Format long strings of text into lines of a certain width. All lines can also
# be indented.
# 1: the long string to format
# 2: the number of spaces to indent the text with
# 3: the string/char used to indent the text with (a space, by default), or, if the 3rd arg is '--keep-spaces-and-breaks', then don't remove spaces or line breaks
log::fmt_text() {
    set -f
    local keep_spaces=false
    local decrement_width_by=0
    local tight_margins=false
    local remove_color=false
    local indent=0
    local additional_indent=0
    local indent_str=' '

    local OPTIND

    # The --x option prevents command options from being parsed. This is necessary when formatting help text for commands.
    # This type of text often starts with the option, e.g., "-h, --help".
    if [[ $1 =~ --x? ]]; then
        shift
    else
        while getopts "kd:tri:s:" opt; do
            case "${opt}" in
                k ) keep_spaces=true  ;;
                d ) decrement_width_by=$OPTARG ;;
                t ) tight_margins=true ;;
                r ) remove_color=true ;;
                i ) indent=$OPTARG  ;;
                s ) indent_str=$OPTARG  ;;
                : )
                    log::Error "Option '${OPTARG}' expects an argument."
                    return 1
                    ;;
                \? )
                log::debug '----------------------------'
                    log::Error "Invalid option: $OPTARG"
                    return 1
                    ;;
            esac
        done
        shift $((OPTIND - 1))
    fi

    local txt="$1"

    # Remove all color and formatting characters.
    $remove_color && txt="$(log::strip_color_codes <<<"$txt")"

    # The amount to indent lines that wrap.
    # Set if positional parameters were used to set the indents.
    indent=${2:-$indent}
    additional_indent=${3:-$additional_indent}

    # Set default indent string to a space.
    indent_str=${indent_str:- }

    # Set indent string to an empty string if the indent is 0.
    [[ $indent -eq 0 ]] && indent_str=''

    # echo interprets '-e' as a command line switch, so a space is added to it so that it will actually be printed.
    re='^ *-e$'
    [[ $txt =~ $re ]] && txt+=' '

    # Replace 2 or more spaces with a single space and \n with a single space.
    [[ $keep_spaces = false ]] && txt=$(echo "$txt" | tr '\n' ' ' | sed -E 's/ {2,}/ /g')

    # Determin the total length of the repeated indent string.
    local indent_len=$((${#indent_str} * indent))

    local width=80
    # Only run tput if we're running in an interactive terminal.
    # Get the width of the console.
    [[ -n $TERM ]] && width=$(tput cols)

    # Get max width of text after the indent width is subtracted.
    # - 1 in case the the last char is a t the last col position, which means that the new line char will be wrapped
    # to the next line, leaving a blank line.
    ((width = width - indent_len - decrement_width_by - 1))
    ((width = width <= 0 ? 80 : width))

    # Start the sed pattern with s/^/, meaning that we are going to substitute the beginning of the string with our
    # indent string.
    local sed_pattern="s/^/"
    # Repeat the indent string $indent number of times. seq is used to create
    # a seq from 1 ... $indent (e.g. 1 2 3 4, for $indent=4). So for
    # $indent_str='=+' and $indent=3, this line, when evaluated, would print
    # '=+=+=+'. Note that printf "%.0s" "some-str" will print 0 chars of
    # "some-str". printf "%.3s" "some-str" would print 'som' (3 chars).
    sed_pattern+=$(printf "$indent_str%.0s" $(seq 1 $indent))
    sed_pattern+="/g"

    local fmt_command=fmt
    $tight_margins && fmt_command=fold

    # Text is piped into fmt to format the text to the correct width, then
    # indented using the sed substitution to insert our intent string.
    echo "$txt" | $fmt_command -s -w $width | sed "$sed_pattern"
    # echo "$txt" | fmt -w $width | sed "$sed_pattern"
    # echo $1 | fmt -w $width | sed "s/^/$(printf '$%.0s' `seq 1 $indent`)/g"
    set +f
}

# Takes a long string and wraps it according to the terminal width (like left justifying text in Word or Goggle Doc),
# but it allows wrapped lines to be indented more than the first line. All lines created can also have a base indent.
#
# Parameters:
#   1 (long_text):  The long line of text
#   2 (base_indent): The base indent amount that all of the text will be indented by (the number of spaces to add to prefix each line with)
#   3 (additional_indent): The number of additional spaces to prefix wrapped lines with
#
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
log::fmt_text_and_indent_after_first_line() {
    set -f
    local strip_spaces=false
    local tight_margins=false
    local remove_color=false
    local decrement_first_line_width_by=0
    local base_indent=0
    local additional_indent=0
    # local next_line_indent=0
    local OPTIND

    # log::debug "log::fmt_text_and_indent_after_first_line: args: '$*'"

    # The --x option prevents command options from being parsed. This is necessary when formatting help text for commands.
    # This type of text often starts with the option, e.g., "-h, --help".
    if [[ $1 =~ --x? ]]; then
        shift
    else
        while getopts ":b:i:a:sd:tr" opt; do
            case "${opt}" in
                b ) base_indent="$OPTARG"  ;;
                i ) indent_str="$OPTARG"  ;;
                a ) additional_indent=$OPTARG  ;;
                s ) strip_spaces=true  ;;
                d ) decrement_first_line_width_by="$OPTARG" ;;
                t ) tight_margins=true ;;
                r ) remove_color=true ;;
                : )
                    log::Error "Option '${OPTARG}' expects an argument."
                    return 1
                    ;;
                \? )
                    log::debug '----------------------------'
                    log::Error "Invalid option: ${OPTARG}"
                    return 1
                    ;;
            esac
        done
        shift $((OPTIND - 1))
    fi

    local indent_char=' '
    local long_text="$1"
    # Remove all color and formatting characters.
    $remove_color && long_text="$(log::strip_color_codes <<<"$long_text")"
    local total_text_length=${#long_text}

    # The amount to indent lines that wrap.
    # Set if positional parameters were used to set the indents.
    base_indent=${2:-$base_indent}
    additional_indent=${3:-$additional_indent}

    local total_indent=$(( base_indent + additional_indent ))
    local wrapped_line_indent_str=$(printf "$indent_char%.0s" $(seq 1 $additional_indent))
    # log::debug "'${wrapped_line_indent_str}'"
    # local lines=$(log::fmt_text "$long_text" $base_indent)

    local fmt_option=" -k "
    $strip_spaces && fmt_option=
    $tight_margins && fmt_option+=" -t "
    local decrement_option=
    (( decrement_first_line_width_by > 0 )) && decrement_option=" -d $decrement_first_line_width_by "
    local lines=$(log::fmt_text $decrement_option $fmt_option "$long_text" $base_indent )

    local line_number=0
    local output=''

    # Get the first line from the formatted string. We need to know how log it is so that we can format the remaining
    # text again with the additional indent.
    local first_line=$(head -1 <<<"$lines")
    local first_line_length=${#first_line}
    # Remove the base indent form the line to get the actual length of text.
    first_line_length=$((first_line_length - base_indent))
    output="$first_line"
    # log::debug "$first_line"
    # log::debug "first_line_length = $first_line_length"
    # log::debug "total_text_length = $total_text_length"
    # log::debug "$total_text_length != ($first_line_length - $base_indent)"

    if (( total_text_length != first_line_length )); then
        # Add line break for first line.
        output+="\n"

        # Get the remaing text to be indented (everything after the first line).
        local rest_to_be_indented="${long_text:$first_line_length}"
        [[ ${rest_to_be_indented:0:1} == ' ' ]] && rest_to_be_indented="${rest_to_be_indented:1}"
        # Indent the rest with the additional indent.
        local rest_indented="$(log::fmt_text $fmt_option "$rest_to_be_indented" $total_indent)"
        # Add the indented text to the result
        output+="$rest_indented"
        # log::debug "$rest_to_be_indented"
    fi
    echo -n -e "$output"
    set +f
}

# log::indent [iIs] <text to indent>
log::indent() {
    local indent=
    local indent_amount=4
    local indent_str=' '
    local write_to_caller_variable=false

    local OPTIND
    while getopts "I:i:s:v:" opt; do
        case "${opt}" in
            i ) indent_amount="$OPTARG"  ;;
            I ) indent="$OPTARG"  ;;
            s ) indent_str="$OPTARG"  ;;
            v ) local -n caller_var_ref="$OPTARG" && write_to_caller_variable=true  ;;
            : )
                log::Error "Option '${OPTARG}' expects an argument."
                return 1
                ;;
            \? )
                log::debug '----------------------------'
                log::Error "Invalid option: ${OPTARG}"
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    [[ -z $indent ]] && indent="$(log::repeat_str "$indent_str" "$indent_amount")"
    local text="$*"
    # log::debug "indent '$indent'"
    # log::debug "text '$text'"

    local result="$(echo "$text" | sed -e "s/^/$indent/g")"

    $write_to_caller_variable && caller_var_ref="$result" && return
    echo "$result"
}

log::strip_color_codes() {
    local args
    # Allow this command to accept piped in arguments. Example: echo "text" | log::strip_color_codes
    if (( "$#" == 0 )); then
        IFS= read -r -t 0.01 args
        set -- "$args"
    fi
    echo -n "$@" | sed -r "s/(\x1B|\\e)\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g"
    # \e[38;5;${i}m
    # '\033[1;31m'
    # echo -n "$@" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g"
}

# Format functions
BOLD_ON="\e[1m"
BOLD_OFF="\e[21m"
DIM_ON="\e[2m"
DIM_OFF="\e[22m"
ITALIC_ON="\e[3m"
ITALIC_OFF="\e[23m"
UNDERLINE_ON="\e[4m"
UNDERLINE_OFF="\e[24m"
BLINK_ON="\e[5m"
BLINK_OFF="\e[25m"
INVERT_ON="\e[7m"
INVERT_OFF="\e[27m"
HIDE_ON="\e[8m"
HIDE_OFF="\e[28m"

log::txt_bold() {
    echo -en "\e[1m$@\e[21m"
}

# Dim/light text.
log::txt_dim() {
    echo -en "\e[2m$@\e[22m"
}

log::txt_italic() {
    echo -en "\e[3m$@\e[23m"
}

log::txt_underline() {
    echo -en "\e[4m$@\e[24m"
}

# Blinking text.
log::txt_blink() {
    echo -en "\e[5m$@\e[25m"
}

# Inverts foreground/background text color.
log::txt_invert() {
    echo -en "\e[7m$@\e[27m"
}

# Hides the text.
log::txt_hide() {
    echo -en "\e[8m$@\e[28m"
}

# Replaces the value of $HOME in a full file path with ~, making it relative to the user's home directory.
# Example:
#   Input: /home/dawsonmyers/repos/geo-cli/src/geo-cli.sh
#   Output: ~/repos/geo-cli/src/geo-cli.sh
log::make_path_relative_to_user_dir() {
    echo "$@" | sed -e "s%$HOME%~%g"
}
# Replaces the value of $HOME in a full file path with ~, making it relative to the user's home directory.
# Example:
#   Input: /home/dawsonmyers/repos/geo-cli/src/geo-cli.sh
#   Output: ~/repos/geo-cli/src/geo-cli.sh
log::strip_space() {
    local remove_newlines=false
    [[ $1 == -n ]] && remove_newlines=true && shift
    local str="$@"
    $remove_newlines && str="$(log::replace_line_breaks_with_space "$str")"
    echo "$str" | sed -E 's/ {2,}/ /g; s/^ +| +$//g'
}

log::replace_line_breaks_with_space() {
    eval "$(util::eval_to_enable_piped_args)"
    local str="$*"
    echo "$str" | tr '\n' ' '
}

# log::keyvalue() {
#     local key=$1
#     local value=$2
#     # local key_logger=status
#     # local value_logger=data
#     # eval "$(_geo_make_option_parser \
#     #             --opt-arg 'short=k long=key-logger var=key_logger' \
#     #             --opt-arg 'short=v long=value-logger var=value_logger')"
#     # local str="$@"
#     # echo "$str" | tr '\n' ' '
#     # eval "log::$key_logger -n '  $key: ' && log::$value_logger '$value'"
#     log::status -n "  $key: " && log::data "$value"
# }

log::keyvalue() {
    local add_padding=true
    local padding='  '
    local key_ref=
    local is_variable=false
    local is_array=false
    local key=
    local key_name=
    local value=
    local delimiter_default=': '
    local delimiter="$delimiter_default"
    local OPTIND
    # log::debug "args: $@"
    while getopts "Pv:d:" opt; do
        case "${opt}" in
            P ) add_padding=false ;;
            d ) delimiter="${OPTARG:-$delimiter_default}" ;;
            v )
                key_name="$OPTARG"
                [[ -z $key_name ]] && log::Error "log::keyvalue: The variable cannot be empty (-v <variable>)." && return 1
                # [[ ! -v $key ]] && log::Error "log::keyvalue: The variable  cannot be empty (-v <variable>)." && return 1
                is_variable=true
                # log::debug "key_name: $key_name"
                ;;
            # Standard error handling.
            : ) log::Error "Option '${OPTARG}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${OPTARG}"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    if $is_variable; then
        local -n key_ref="$key_name"
        # util::typeofvar key_name
        # util::typeofvar "key_name"
        # util::typeofvar "key_ref"
        # declare -p "$key_name"
        # declare -p "$key_ref"
        # declare -p "key_ref"
        util::typeofvar -t array "key_ref" \
            && is_array=true
        # echo "is_array: $is_array"
        # log::debug "key_name $key_name"
        # log::debug "is_array $is_array"
        if $is_array; then
            local item_count="${#key_ref[@]}"
            # delimiter="[$item_count]"
            # delimiter="[]$delimiter\n"
            # key="$(log::info "$key_name[]")"
            log::info "$key_name[$item_count]"
            # value="$(util::print_array  "$key_name")"
            # util::print_array  "$key_name"
            util::join_array -f "$key_name"
            return
            # value="$(util::join_array -nD "$key_name")"
            # value="$(util::print_array "$key_name")"
        else
            # key="$(log::info -n "$key_name")"
            log::info -n "$key_name$delimiter"
            # log::info -n "$key_name"
            value="$key_ref"
            log::data "$value"
        fi
        return
        # ! $is_array &&  ||
        # value="$(log::data "$value")"
        log::debug "value \n'$value'"
        msg="$key$value"
        log::debug "msg \n'$msg'"
    else
        key_name="$1"
        value="$2"
        [[ $# -lt 2 || -z $key_name ]] \
            && log::Error "log::keyvalue: Both a key and a value are required as arguments, but got '$@' instead." \
            && return 1
        [[ $key_name =~ ': '$ ]] && delimiter=''
        key="$(log::info -n "$key_name$delimiter")"
        # key_length=${#key_name}
        value="$(log::data "$value")"
        # echo "k '$key' kn '$key_name' v '$value'"
        # echo "k '$key' v '$value'"
    fi


    # is_variable &&
    # ! $is_variable &&
    # local print_variable=false
    # if $is_variable; then

    # fi
    # key="$(log::info -n "$1 ")"
    # key_length=${#key}
    # value="$(log::data "$2")"
    msg="$key$value"
    # echo "k '$key'"
    # log::data " $2"
    $add_padding \
        && local padding=(
            # First line indent.
            4
            # Indent for lines after the first line.
            10
        )
    #     echo "k '$key' add_padding '$add_padding'"
    # echo '"${padding[@]}"'" '"${padding[@]}"'"
    log::fmt_text_and_indent_after_first_line "$msg" "${padding[@]}"
    echo
}
