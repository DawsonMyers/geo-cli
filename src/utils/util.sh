export GEO_CLI_UTILS_DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
# echo "GEO_CLI_UTILS_DIR $GEO_CLI_UTILS_DIR"
# . "$GEO_CLI_UTILS_DIR/log.sh" ==> circular ref

util::template_doc() {
    read -r -d '' help_text <<-'EOF'
Templates
    o | opt | option | options
        default (*) - Plain while getopts case loop
        long | l    - While case loop for parsing long options
        long-groups - While case loop for parsing long options and groups of single
                      options (e.g. -abc)
EOF
    log::green "$help_text"
}
util::template() {
    [[ $1 =~ (^-h)|(^--help) ]] && util::template_doc && return
    
    read -r -d '' option_template <<-'EOF'
local OPTIND
while getopts "v:p" opt; do
    case "${opt}" in
        v ) caller_variable=$OPTARG ;;
        p ) print_result=true ;;
        # Standard error handling.
        : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
        \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
    esac
done
shift $((OPTIND - 1))
EOF

    read -r -d '' option_long_template <<-'EOF'
while [[ -n $1 && $1 =~ ^-{1,2} ]]; do
    opt="$(echo $1 | sed -E 's/^-{1,2}//g')"
    case "${opt}" in
        v | var ) 
            local -n caller_var_ref="$2"
            write_to_caller_variable=true
            shift
            ;;
        p | print ) print_to_stdout=true ;;
        s | silent ) silent=true ;;
        : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
        \? ) log::Error "Invalid option: $1"; return 1 ;;
    esac
    shift
done
EOF

    read -r -d '' option_long_args_and_groups_template <<-'EOF'
parse_option() {
    local opt="$1"
    case "${opt}" in
        r | raw ) raw=true && echo raw;;
        t ) add_timestamp=true ;;
        # Standard error handling.
        : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
        \? ) log::Error "Invalid option: $1"; return 1 ;;
    esac
}

while [[ -n $1 && $1 =~ ^-{1,2} ]]; do
    local option="$1"
    # opt="$(echo $1 | sed -E 's/^-{1,2}//g')"
    if [[ $1 =~ ^-[[:alpha:]]{1,} ]]; then
        local option_count=${#option}
        # (( option_count ))
        local single_option=
        for ((i = 1; i < option_count; i++)); do
            single_option="${option:$i:1}"
            parse_option "$single_option"
        done
        shift
        continue
    fi
    long_option="$(echo $option | sed -E 's/^-{1,2}//g')"
    parse_option "$long_option"
    shift
done
EOF

    local template_type=$1

    case template_type in
        o | opt | option | options )
            case $2 in
                long | l ) echo "$option_long_template" ;;
                long-group | long-groups | lg ) echo "$option_long_args_and_groups_template" ;;
                * ) echo "$option_template" ;;
            esac   
            ;;
        * ) echo "$option_template" ;;
    esac
}

util::replace_home_path_with_tilde() {
    echo "$@" | sed -e "s%$HOME%~%g"
}

util::print_array() {
    local print_BASH_REMATCH=false
    local formatted=false
    local same_line=false
    [[ $1 = -r ]] && local -n array=BASH_REMATCH || local -n array="$1"
    local OPTIND
    while getopts "rfs" opt; do
        case "${opt}" in
            r ) print_BASH_REMATCH=true ;;
            f ) formatted=true ;;
            s ) same_line=true ;;
            # f ) formatted=$OPTARG ;;
            # Standard error handlers.
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    local text=
    
    for item in "${array[@]}"; do
        echo "$item"
    done
}



# a=(1 2 3)
# Plain:
# util::join_array a
# 1, 2, 3
# Print formatted:
# util::join_array -f a
# [
#   1,
#   2,
#   3
# ]
# Add -D to remove delimiter:
# util::join_array -fD a
# [
#   1
#   2
#   3
# ]
util::join_array() {
    local brackets=false
    local newlines=false
    local formatted=false
    local nl=$'\n'
    local raw=false
    local indent=false
    local indent_amount=2
    local delim=", "
    local print_BASH_REMATCH=false

    # [[ $1 = --re ]] && local -n array=BASH_REMATCH || local -n array="$1"
    local OPTIND
    while getopts "nbird:R:fD" opt; do
        case "${opt}" in
            R ) print_BASH_REMATCH=true ;;
            f ) formatted=true ;;
            r ) raw=true ;;
            n ) newlines=true ;;
            b ) brackets=true ;;
            d ) delim="$OPTARG" ;;
            D ) delim='' ;;
            i ) indent=true ;;
            I ) indent=true && indent_amount="$OPTARG" ;;
            # f ) formatted=$OPTARG ;;
            # Standard error handlers.
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    
    $formatted && newlines=true && brackets=true && indent=true

    # log::debug "args: $@"
    $print_BASH_REMATCH \
        && local -n array=BASH_REMATCH \
        || local -n array="$1"
    # local -n array=$1
    [[ -n $2 ]] && delim="${2:-$delim}"
    # local delim="${2:-, }"
    local text=

    $raw && echo "${array[@]}" && return

    # for item in "${array[@]}"; do
    #     echo "$item"
    # done

    local line_break=
    $newlines && line_break="$nl"
    
    local count=${#array[@]}
    for ((i=0; i<count; i++)); do
        local end="$delim"
        end+="$line_break"
        ((i == count-1)) && end=
        # log::debug "text+=${array[$i]}$end"
        text+="${array[$i]}$end"
    done

    $indent && ((indent_amount > 0)) && text="$(log::indent -i $indent_amount "$text")"

    $brackets && echo "[$line_break$text$line_break]" || echo "$text"
    
    # $brackets && echo ""

}

# _geo_extract_re() {
#     local -n array=$1
#     for item in "${array[@]}"; do
#         echo "$item"
#     done
# }

util::typeofvar () {
    local is_type=false
    local silent=false
    local is_ref=false
    
    local OPTIND
    while getopts "aAmhst:T:r" opt; do
        case "${opt}" in
            t ) is_type="$OPTARG" && silent=true ;;
            T ) is_type="$OPTARG" ;;
            a ) is_type=array ;;
            m ) is_type=map ;;
            s ) is_type=string ;;
            S ) silent=true ;;
            r ) is_ref=true ;;
            # Standard error handling.
            : ) log::Error "Option '${opt}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${opt}"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    # [[ $1 == --array ]] && is_type=array && shift
    # [[ $1 == --array ]] && is_type=array
    # echo "1 = $1"
    local name=$1
    local -n var_ref=$name 
    # local type_signature=$(declare -p "var_ref" 2>/dev/null)
    # echo "type_signature = $type_signature"
    local type_signature=$(declare -p "$name" 2>/dev/null)
    # echo "type_signature = $type_signature"
    re="declare -n [-_a-zA-Z0-9]{1,}=[\"']?([-_a-zA-Z0-9]{1,})['\"]?"
    while [[ $type_signature =~ $re ]]; do
    # while [[ $type_signature =~ declare -n ]]; do
        local ref_name="${BASH_REMATCH[1]}"
        type_signature="$(declare -p "$ref_name" 2>/dev/null)"
        # echo "while type_signature = $type_signature"
    done
    # util::get_ref_var_name -v ref_name $name

    $is_ref && local -n var_ref=$1 && type_signature=$(declare -p "var_ref" 2>/dev/null)

    local var_type=
    if [[ "$type_signature" =~ "declare --" ]]; then
        var_type="string"
    elif [[ "$type_signature" =~ "declare -a" ]]; then
        var_type="array"
    elif [[ "$type_signature" =~ "declare -A" ]]; then
        var_type="map"
    else
        var_type="none"
    fi

    # echo "var_type = $var_type"
    ! $silent && echo -n "$var_type"

    if [[ -n $is_type ]]; then
        # log::debug "[[ ! $var_type =~ $is_type ]] && return 1"
        [[ $var_type =~ $is_type ]] && return
        return 1
    fi
    return 0
    # echo -n "$var_type"
}


# Add eval "$(util::eval_enable_piped_args)" to a function to enable reading from stdin
util::eval_enable_piped_args() {
    local _enable_piped_args_code=
    read -r -d '' _enable_piped_args_code <<-'EOF'
    local args
    # Allow this command to accept piped in arguments. Example: echo "text" | log::strip_color_codes
    if (( "$#" == 0 )); then
        IFS= read -r args
        set -- "$args"
    fi
EOF
 [[ $1 == -v ]] && local -n var="$2" && var="$_enable_piped_args_code" && return
 echo "$_enable_piped_args_code"
}

util::get_ref_var_name() {
    local write_to_var=false
    [[ $1 == -v ]] && local -n out_var=$2 && shift 2 && write_to_var=true
    local name="$1"
    local re="declare -n [-_a-zA-Z0-9]{1,}=[\"']?([-_a-zA-Z0-9]{1,})['\"]?"
    local type_signature="$(declare -p "$name" 2>/dev/null)"
    while [[ $type_signature =~ $re ]]; do
    # while [[ $type_signature =~ declare -n ]]; do
        name="${BASH_REMATCH[1]}"
        type_signature="$(declare -p "$name" 2>/dev/null)"
        # echo "while type_signature = $type_signature"
    done
    $write_to_var && out_var="$name" || echo $name
}
