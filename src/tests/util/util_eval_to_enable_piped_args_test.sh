. $GEO_CLI_SRC_DIR/geo-cli.sh

test_function() {
#    local _enable_piped_args_code=
#    read -r -d '' eval_code<<'EOF'
#    local __args
#    # Allow this command to accept piped in arguments. Example: echo "text" | log::strip_color_codes
#     if [[ -p /dev/stdin ]]; then
#        IFS= read -r -d '' -t 0.01 __args
#        set -- "$__args"
#    fi
#EOF
#    echo "__args = $__args"
    eval "$(util::eval_to_enable_piped_args)"
#    eval "$eval_code"
#    echo "\$* = $*"
    echo "$*"
#    echo "\$# = $#"
}

input_args="
a
b
c"
expected_output="$input_args"

echo "$input_args" | test_function
func_output="$(echo "$input_args" | test_function)"

# TODO: Create functions for formatting test output and assertions
log::status '* Expected:'
log::code "$expected_output"
log::status '* Actual:'
log::code "$func_output"
if [[ $func_output != "$expected_output" ]]; then
    log::error [FAILED]
#    log::status '* Expected:'
#    log::code "$expected_output"
#    log::status '* Actual:'
#    log::code "$func_output"
else
    log::success '[PASS]'
fi


