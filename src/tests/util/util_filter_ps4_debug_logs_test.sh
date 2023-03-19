echo $(pwd)
# The env vars in the run config don't work with Rider macros to get the proj dir
#echo projdir = $projdir
. ./src/geo-cli.sh
log::filter_ps4_debug_logs() {
    eval "$(util::eval_to_enable_piped_args)"
#    echo "$*"
    echo "$*" | grep -Ev 'log.sh|config-file|cfg_|geo_get|log::|util::|gitprompt|bashrc-utils'
}

test_function() {
#    input_args="
#    a
#    b
#    c"
#    expected_output="$input_args"

    echo 'reading...'
    read -r -d '' inputerr  1<&2
    log::debug "inputerr = $inputerr "
    return
    output="$(echo "$input_args" | log::filter_ps4_debug_logs)"

    # TODO: Create functions for formatting test output and assertions
    log::status '* Expected:'
    log::code "$expected_output"
    log::status '* Actual:'
    log::code "$output"
    if [[ $output != "$expected_output" ]]; then
        log::error [FAILED]
    #    log::status '* Expected:'
    #    log::code "$expected_output"
    #    log::status '* Actual:'
    #    log::code "$func_output"
    else
        log::success '[PASS]'
    fi
}




read -r -d '' input_args <<'EOF'
.✔ log.sh[4]:log::stacktrace[11]:  [[ '' =~ ^- ]]
..✘ log.sh[1]:log::stacktrace[11]:  @geo_get DEBUG_LOG
.✔ log.sh[5]:_log_debug[2]:  local format_tokens=
.✔ log.sh[6]:_log_debug[2]:  local opts=e

..✘ cli-handlers.sh[3]:@geo_get[1]:  local key=DEBUG_LOG
..✔ cli-handlers.sh[4]:@geo_get[1]:  [[ ! DEBUG_LOG =~ ^GEO_CLI_ ]]
..✔ cli-handlers.sh[4]:@geo_get[1]:  key=GEO_CLI_DEBUG_LOG
...✔ cli-handlers.sh[1]:@geo_get[1]:  cfg_read /home/dawsonmyers/.geo-cli/.geo.conf GEO_CLI_DEBUG_LOG
...✔ config-file-utils.sh[2]:cfg_read[1]:  local file=/home/dawsonmyers/.geo-cli/.geo.conf
....✔ config-file-utils.sh[1]:cfg_read[1]:  echo GEO_CLI_DEBUG_LOG
....✔ config-file-utils.sh[1]:cfg_read[1]:  cfg_key_lookup_escape
....✔ config-file-utils.sh[2]:cfg_key_lookup_escape[1]:  sed -e 's/[]\/$*.^[]/\\&/g'
...✔ config-file-utils.sh[3]:cfg_read[1]:  local key=GEO_CLI_DEBUG_LOG
...✔ config-file-utils.sh[4]:cfg_read[1]:  test -f /home/dawsonmyers/.geo-cli/.geo.conf
...✔ config-file-utils.sh[4]:cfg_read[1]:  grep --color=auto -a '^GEO_CLI_DEBUG_LOG=' /home/dawsonmyers/.geo-cli/.geo.conf
...✔ config-file-utils.sh[4]:cfg_read[1]:  sed 's/^GEO_CLI_DEBUG_LOG=//'
...✔ config-file-utils.sh[4]:cfg_read[1]:  tail -1
...✔ config-file-utils.sh[4]:cfg_read[1]:  cfg_value_unescape
...✔ config-file-utils.sh[2]:cfg_value_unescape[4]:  sed 's/__n__/\n/g'
..✔ cli-handlers.sh[6]:@geo_get[1]:  value=
..✔ cli-handlers.sh[9]:@geo_get[1]:  [[ GEO_CLI_DEBUG_LOG == GEO_CLI_DIR ]]
..✘ cli-handlers.sh[11]:@geo_get[1]:  [[ -z '' ]]
..✔ cli-handlers.sh[11]:@geo_get[1]:  return
.✔ log.sh[6]:log::stacktrace[11]:  local debug_log=
.✔ log.sh[7]:log::stacktrace[11]:  [[ '' == true ]]
.✔ cli-handlers.sh[34]:_geo_xml_upsert[8]:  return 1
.✘ cli-handlers.sh[9]:_geo_validate_server_config[82]:  set +x
.✔ log.sh[2]:log::debug[2]:  _log_debug 'args: //WebServerSettings/WebPort 10000 80 /home/dawsonmyers/test/server.config'
.✔ log.sh[2]:_log_debug[2]:  set +f
.✔ log.sh[3]:_log_debug[2]:  local 'msg=args: //WebServerSettings/WebPort 10000 80 /home/dawsonmyers/test/server.config'
.✔ log.sh[4]:_log_debug[2]:  local options=

EOF
read -r -d '' expected_output <<'EOF'
.✔ cli-handlers.sh[34]:_geo_xml_upsert[8]:  return 1
.✘ cli-handlers.sh[9]:_geo_validate_server_config[82]:  set +x
EOF

echo testlllllerrrrrr >&2 |& test_function
