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
        : ) log::Error "Option '${OPTARG}'  expects an argument."; return 1 ;;
        \? ) log::Error "Invalid option: ${OPTARG}"; return 1 ;;
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
        : ) log::Error "Option '${OPTARG}'  expects an argument."; return 1 ;;
        \? ) log::Error "Invalid option: $OPTARG"; return 1 ;;
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
        : ) log::Error "Option '${OPTARG}'  expects an argument."; return 1 ;;
        \? ) log::Error "Invalid option: $OPTARG"; return 1 ;;
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

    case "$template_type" in
        o | opt | option | options )
            case "$2" in
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
            : ) log::Error "Option '${OPTARG}'  expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${OPTARG}"; return 1 ;;
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
            : ) log::Error "Option '${OPTARG}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${OPTARG}"; return 1 ;;
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

util::get_var_type () {
    local write_to_caller_var=false
    [[ $1 == -v ]] && local -n var_ref=$2 && write_to_caller_var=true && shift 2
    local __var_name=$1
    local type_signature=
    util::get_var_sig -v type_signature $__var_name

    local __var_type=
    if [[ "$type_signature" =~ "declare --" ]]; then
        __var_type="string"
    elif [[ "$type_signature" =~ "declare -a" ]]; then
        __var_type="array"
    elif [[ "$type_signature" =~ "declare -A" ]]; then
        __var_type="map"
    elif [[ "$type_signature" =~ "declare -n" ]]; then
        __var_type="ref"
    else
        __var_type="none"
    fi

    if $write_to_caller_var; then
        var_ref="$__var_type"
        return
    fi
    echo "$__var_type"
}

util::typeofvar () { util::typeof "$@"; }
util::typeof () {
    local is_type=false
    local silent=false
    local is_ref=false

    local OPTIND
    while getopts "aAmhst:T:r" opt; do
        case "${opt}" in
            # Type to test for
            t ) is_type="$OPTARG" && silent=true ;;
            # Type to test for and print the variable type out.
            T ) is_type="$OPTARG" ;;
            a ) is_type=array ;;
            m ) is_type=map ;;
            s ) is_type=string ;;
            S ) silent=true ;;
            r ) is_ref=true ;;
            # Standard error handling.
            : ) log::Error "Option '${OPTARG}' expects an argument."; return 1 ;;
            \? ) log::Error "Invalid option: ${OPTARG}"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    # [[ $1 == --array ]] && is_type=array && shift
    # [[ $1 == --array ]] && is_type=array
    # echo "1 = $1"
    local root_name=$1
    # local type_signature=$(declare -p "var_ref" 2>/dev/null)
    # echo "type_signature = $type_signature"

    local _name=
    util::get_ref_var_name -v _name $1
    # log::debug util::get_ref_var_name -v _name $1

    local -n var_ref=$_name
    # log::debug "local -n var_ref=$_name "

    # local type_signature=
    # util::get_var_sig -v type_signature $name
    # log::debug "util::get_var_sig -v type_signature $name"

    # echo "type_signature = $type_signature"
    # local type_signature=$(declare -p "$name" 2>/dev/null)
    # re="declare -n [-_a-zA-Z0-9]{1,}=[\"']?([-_a-zA-Z0-9]{1,})['\"]?"
    # while [[ $type_signature =~ $re ]]; do
    # # while [[ $type_signature =~ declare -n ]]; do
    #     local ref_name="${BASH_REMATCH[1]}"
    #     type_signature="$(declare -p "$ref_name" 2>/dev/null)"
    #     # echo "while type_signature = $type_signature"
    # done

    # $is_ref && local -n var_ref=$1 && type_signature=$(declare -p "var_ref" 2>/dev/null)

    local var_type=
    util::get_var_type -v var_type $_name
    # log::debug util::get_var_type -v var_type $_name
    # evar var_type
    # if [[ "$type_signature" =~ "declare --" ]]; then
    #     var_type="string"
    # elif [[ "$type_signature" =~ "declare -a" ]]; then
    #     var_type="array"
    # elif [[ "$type_signature" =~ "declare -A" ]]; then
    #     var_type="map"
    # else
    #     var_type="none"
    # fi

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

# Check to see if the variable name is a reference that points to another variable.
util::is_ref_var() {
    local var_type
    util::get_var_type -v var_type $1
    [[ $var_type == ref ]]
}

# Check to see if the variable name is a reference that points to another variable.
util::is_var() {
    local var_type
    util::get_var_type -v var_type $1
    [[ $var_type == ref ]]
}

util::get_var_sig() {
    local has_var=false
    [[ $1 == -v ]] && local -n __ref=$2 && has_var=true && shift 2
    local sig="$(declare -p "$1" 2>/dev/null)"
    [[ $has_var == true ]] && __ref="$sig" || echo "$sig"
}


# Add eval "$(util::eval_to_enable_piped_args)" to a function to enable reading from stdin
util::eval_to_enable_piped_args() {
    local _eval_code
    read -r -d '' _eval_code<<-'EOF'
    local __args
    # Allow this command to accept piped in arguments. Example: echo "text" | log::strip_color_codes
     if [[ -p /dev/stdin ]]; then
        IFS= read -r -d '' -t 0.01 __args
        set -- "$__args"
    fi
EOF
 [[ $1 == -v ]] && local -n var="$2" && var="$_eval_code" && return
 echo "$_eval_code"
}
# TODO: Update
util::eval_trap_error_and_log() {
     local err_trap="$BCyan\${BASH_SOURCE[0]##\${HOME}*/}${Purple}[\$LINENO]:${Yellow}\${FUNCNAME:-FuncNameNull}: $Off"
    err_trap="${GEO_ERR_TRAP:-$err_trap}"
    export PS4='.${err_trap}'
    trap "$err_trap" ERR
#    export PS4='.${BASH_SOURCE[0]##*/}[$LINENO]: '
}

util::get_ref_var_name() {
    local write_to_var=false
    [[ $1 == -v ]] && local -n out_var=$2 && write_to_var=true && shift 2
    local __name="$1"
    local re="declare -n [-_a-zA-Z0-9]{1,}=[\"']?([-_a-zA-Z0-9]{1,})['\"]?"
    local type_signature="$(declare -p "$__name" 2> /dev/null)"
    while [[ $type_signature =~ $re ]]; do
    # while [[ $type_signature =~ declare -n ]]; do
        __name="${BASH_REMATCH[1]}"
        type_signature="$(declare -p "$__name" 2> /dev/null)"
        # echo "while type_signature = $type_signature"
    done
    $write_to_var && out_var="$__name" || echo $__name
}

# util::arg_spread() {
#     local args=()
#     local cmd=$1
#     shift
#     # Allow this command to accept piped in arguments. Example: echo "text" | log::strip_color_codes
#     if (( "$#" == 0 )); then
#         IFS= read -r -t 0.5 -a args
#         set -- "$args"
#         log::debug -V "$args"
#         log::debug -V "count: ${#args}"


#         (( "$#" == 0 )) && log::Error "No arguments supplied." && return 1
#     fi

#     $cmd "$@"
# }

# declare -A map
# keyvalues_to_map map 'short=a long=alt var=x'
# map now equals: { short: a, long: alt, var: x}
util::keyvalues_to_map() {
    local -n map_ref="$1"
    local def="$2"
    for arg in $def; do
        local key="${arg%=*}"
        local value="${arg#*=}"
        map[$key]="$value"
    done
}

# The map must be explicitly defined like this:
#     declare -A map
# Otherwise ${!_map_ref[@]} won't get the key names, just indexes (0, 1, ..).
util::map_to_json() {
    local -n _map_ref="$1"
    local def="$2"
    local jq_args=()
    for key in "${!_map_ref[@]}"; do
        # local key="${arg%=*}"
        local value="${_map_ref[$key]}"
        map[$key]="$value"
        jq_args+=(--arg "$key" "$value")
    done

     jq "${jq_args[@]}" \
        '$ARGS.named' <<<'{}'
}

# Sets key-value pairs in a map
# Args:
#     1: the name of the map
#     2: key name
#     3: value
#     4: key name
#     5: value
#     ...
# Example:
#   declare -A map
#   util::set_map map a 1 b 2 c 3
util::set_map() {
    local -n _map_ref="$1"
    echo "var name = $1"
    shift

    local count="$#"
    # for (())
    # for key in "$@"; do
    while [[ -n $1 && -n $2 ]]; do
        local key="$1"
        local value="$2"
        _map_ref[$key]="$value"
        echo '_map_ref[$key]="$value" = ' "_map_ref[$key]=$value"
        echo "_map_ref[$key]= ${_map_ref[$key]}"
        shift 2
    done
}

util::array_sort() {
    local inplace=false
    local reverse=false
    local sort_opts=
    if [[ $1 =~ ^-[ir] ]]; then
        [[ $1 =~ i ]] && inplace=true
        [[ $1 =~ r ]] && reverse=true && sort_opts='-r'
        shift
    fi

    local -n _array_ref="$1"
    local ar=()
    ar=($(echo "${_array_ref[@]}" | tr " " "\n" | sort $sort_opts | tr "\n" " "))

    if $inplace; then
        local i=0
        for item in "${ar[@]}"; do
            eval "$1[i]=\"$item\""
            ((i++))
        done
    else
        echo "${ar[@]}"
    fi
}
util::array_length() {
    local -n _array_ref="$1"
    echo ${#_array_ref[@]}
}
util::array_empty() {
    local -n _array_ref="$1"
    [[ ${#_array_ref[@]} -gt 0 ]]
}
util::array_to_path() {
    local -n _array_ref="$1"
    echo "${_array_ref[*]}" | tr ' ' '.'
}
util::array_concat() {
    # local join_str=' '
    local default_join_str=' '
    local join_str="$default_join_str"
    [[ $1 == -z ]] && join_str='' && shift
    [[ $2 == -z ]] && join_str='' && set -- "$1"
    local -n _array_ref="$1"
    [[ -n $2 ]] && local join_str="${*:2}"
    [[ $join_str == "$default_join_str" ]] && echo "${_array_ref[*]}" && return

    local str=''
    for item in "${_array_ref[@]}"; do
        [[ -z $str ]] && str="$item" && continue
        str+="${join_str}${item}"
    done
    echo "$str"
}
alias util::array_join=util::array_concat
alias util::join=util::array_concat
alias array-join=util::array_concat

util::array_pop() {
    local -n __array_ref="$1"
    [[ ${#__array_ref[@]} -lt 1 ]] || return 0
    echo "${__array_ref[-1]}"
    unset __array_ref[-1]
}
alias array-pop=util::array_pop

util::array_pop_front() {
    local -n __array_ref="$1"
    [[ ${#__array_ref[@]} -lt 1 ]] || return 0
    echo "${__array_ref[0]}"
    unset __array_ref[0]
}
alias array-pop-front=util::array_pop_front

util::array_push() {
    local -n __array_ref="$1"
    local value="$2"
    __array_ref+=("$value")
}
alias array-push=util::array_push

util::array_push_front() {
    local -n __array_ref="$1"
    local value="$2"
    echo "${__array_ref[@]}"
    [[ ${#__array_ref[@]} -lt 1 ]] || return
    local ar=("$value" "${__array_ref[@]}")
    # evar ar
    local i=0
    for item in "${ar[@]}"; do
        __array_ref[$((i++))]="$item"
    done
}
alias array-push-front=util::array_push_front
alias array-shift=util::array_push_front

# TODO: Finish dev
util::remove_region_from_file() {
    local file="$1"
    local replacement_text="$2"
    local start_tag="${3:-#geo-cli-start}"
    local end_tag="${4:-#geo-cli-end}"
    local regex_separator='^'
    local new_region="$start_tag
$replacement_text
$end_tag
"

    local file_text="$(cat "$file")"
    local replacement_regex="s/\n?${start_tag}.*${end_tag}\n?//g"
    # local new_region_parts="/\n?${start_tag}.*${end_tag}/d"
    # local new_region_parts="${regex_separator}\n?${start_tag}.*${end_tag}${regex_separator}d"
    # local replacement_regex="$(array-join new_region_parts "$regex_separator")"
    # local new_region_parts=('s' "\n?$start_tag.*$end_tag" "$new_region")
    # local replacement_regex="$(array-join new_region_parts "$regex_separator")"
    e new_region_parts
    e replacement_regex
    sed -i -E "${replacement_regex}" "$file"
    # [[ -n $file_text ]] && echo "$file_text" | sed -i -E "${replacement_regex}"
        # || echo "new file: $new_region"
    # echo "$new_region" >> "$file"
    # [[ -n $file_text ]] && echo "$file_text" | sed "$replacement_regex" \
    #     || echo "new file: $new_region"
    # sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.bashrc
}

# "#geo-cli-start
# my:info:here
# #geo-cli-end"

util::is_alphanumeric() {
    local allow_periods=false
    [[ $1 == -p ]] && allow_periods=true && shift
    local alphanumeric_re='^[^-_0-9]([-[:alnum:]]+)$'
    [[ $* =~ $alphanumeric_re ]]
}
