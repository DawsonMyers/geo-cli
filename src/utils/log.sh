#!/bin/bash

# This file contains various logging functions used throughout geo-cli. All public functions have the prefix 'log::'.

# Gets the absolute path of the root geo-cli directory.
export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
export GEO_CLI_SRC_DIR="${GEO_CLI_DIR}/src"

# Import colour constants/functions.
. $GEO_CLI_SRC_DIR/utils/colors.sh

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
            if [[ \$1 =~ ^-[a-z]+$ && -n \$2 ]]; then
                options=\$1
                msg=\"\${@:2}\"
            fi

            case \$options in
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
                *p* )
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
    _log_debug "$@"
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
log::link() {
    _log_yellow -u "$@"
}
log::filepath() {
    echo "$(_log_purple -n 'file://')$(_log_yellow -u  "$@")"
}
make_logger_function green Green
log::green() {
    _log_green "$@"
}
make_logger_function white White
log::white() {
    _log_white "$@"
}
make_logger_function_vte code VTE_COLOR_115 # greenish blue
log::code() {
    _log_code "$@"
}
make_logger_function_vte hint VTE_COLOR_135 # purple
log::hint() {
    _log_hint "$@"
}

log::keyvalue() {
    key="$(log::info -n "$1 ")"
    key_length=${#key}
    value="$(log::data "$2")"
    msg="$key $value"
    # log::data " $2"
    log::fmt_text_and_indent_after_first_line "$msg" 4 10
}

log::stacktrace() {
# _stacktrace() {
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
log::Error() {
    echo -e "❌  ${BIRed}Error: $@${Off}"
    log::stacktrace
}
log::error() {
    echo -e "❌  ${BIRed}$@${Off}"
}

log::data_header() {
    echo -e "${VTE_COLOR_87}${UNDERLINE_ON}${BOLD_ON}$@${Off}"
    # echo -e "${BIGreen}$@${Off}"
}

log::success() {
    echo -e "${BIGreen}✔${Off}   ${BIGreen}$@${Off}"
}

log::prompt() {
    echo -e "${BCyan}$@${Off}"
}

# Echo without new line
log::prompt_n() {
    echo -en "${BCyan}$@${Off}"
}


# Logging helpers
###########################################################

# Repeat string n number of times.
# 1: a string to repeat
# 2: the number of repeats
log::repeat_str() {
    echo $(printf "$1%.0s" $(seq 1 $2))
}
# Format long strings of text into lines of a certain width. All lines can also
# be indented.
# 1: the long string to format
# 2: the number of spaces to indent the text with
# 3: the string/char used to indent then text with (a space, by default), or, if the 3rd arg is '--keep-spaces-and-breaks', then don't remove spaces or line breaks
log::fmt_text() {
    set -f
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
    set +f
}

# Takes a long string and wraps it according to the terminal width (like left justifying text in Word or Goggle Doc),
# but it allows wrapped lines to be indented more than the first line. The all lines created can also have a base indent.
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
    local indent_char=' '
    local long_text="$1"
    # The amount to indent lines that wrap.
    local base_indent=$2
    local additional_indent=$3
    local total_indent=$(( base_indent + additional_indent ))
    local wrapped_line_indent_str=$(printf "$indent_char%.0s" $(seq 1 $additional_indent))
    # log::debug "'${wrapped_line_indent_str}'"
    local lines=$(log::fmt_text "$long_text" $base_indent --keep-spaces-and-breaks)
    # log::debug "$lines"
    local line_number=0
    local output=''

    while read msg; do
        # log::debug "$msg"
        # Add the additional indent to the start of the line
        msg="${wrapped_line_indent_str}${msg}"
        # log::debug "$msg"
        local msg_lines=$(log::fmt_text "$msg" $base_indent --keep-spaces-and-breaks)
        # log::debug "$msg_lines"
        msg_lines="${msg_lines:additional_indent}"
        # log::debug -e "$msg_lines"
        output+="$msg_lines\n"
        # while read line; do
        #     (( line_number++ ))
        #     if [[ $line_number = 1 ]]; then
        #         output+="$line\n"
        #         continue
        #     fi
        #     # log::debug "$line"
        #     # log::debug "${wrapped_line_indent_str}${line}\n"
        #     output+="${wrapped_line_indent_str}${line}\n"
        # done <<<"$lines"
        # output+="${wrapped_line_indent_str}${line}\n"
    done <<<"$long_text"
    echo -n -e "$output"
    set +f
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