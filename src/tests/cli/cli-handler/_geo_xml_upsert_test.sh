# pwd
# #. ./../../../geo-cli.sh
# echo $(cd ./../../../ && pwd)
geo_dir=$(cat ~/.geo-cli/data/geo/repo-dir) && . "$geo_dir/src/geo-cli.sh"
#. "$(cat ~/.geo-cli/data/geo/repo-dir)"

_geo_validate_server_config() {
    ! _geo_terminal_cmd_exists xmlstarlet && return 1
    local server_config="$HOME/GEOTAB/Checkmate/server.config"
    local server_config="$HOME/test/server.config"
    local webPort sslPort
     set -x
    _geo_xml_upsert //WebServerSettings/WebPort 10000 80 $server_config
    _geo_xml_upsert //WebServerSettings/WebSSLPort 10001 443 $server_config
     set +x
#    ! webPort=$(xmlstarlet sel -t -v //WebServerSettings/WebPort "$server_config") \
#        &&  xmlstarlet ed --inplace --insert //WebServerSettings/WebPort -t elem -n WebPort -v 10000 || log::Error "Failed to insert WebPort element into server.config: $server_config"
#
#    sslPort=$(xmlstarlet sel -t -v //WebServerSettings/WebSSLPort "$server_config")
#    if [[ -z $webPort || $webPort == 80 || -z $sslPort || $sslPort == 443 ]]; then
#        xmlstarlet ed --inplace -u "//WebServerSettings/WebPort" -v 10000 -u "//WebServerSettings/WebSSLPort" -v 10001 "$server_config" \
#            && log::status "Setting server.config WebPort & WebSSLPort to correct values. From ($webPort, $sslPort) to (10000, 10001)." \
#            || log::Error "Failed to update server.config with correct WebPort & WebSSLPort. Current values are ($webPort, $sslPort)."
#    fi
    # xmlstarlet ed --inplace -u "//WebSSLPort" -v 10001 "$HOME/GEOTAB/Checkmate/server.config"
}

_geo_xml_upsert() {
    log::debug "args: $*"
    local xpath="$1"
    local xpath_parent="${xpath%/*}"
    local name="${xpath##*/}"
    local default_value="$2"
    local disallowed_value="$3"
    local xml_file="$4"
    log::debug "
    xpath="$1"
    xpath_parent="${xpath%/*}"
    name="${xpath##*/}"
    default_value="$2"
    disallowed_value="$3"
    xml_file="$4"
    "
    local current_value=""
#    ! current_value=$(xmlstarlet sel -t -v "$xpath" "$xml_file") \
#        &&  {
#            xmlstarlet ed --inplace --insert "$xpath_parent" -t elem -n $name -v $default_value \
#            || log::Error "Failed to insert $name element into server.config: $xml_file"  \
#        } && {
#            current_value=$(xmlstarlet sel -t -v "$xpath" "$xml_file") \
#            || log::Error "Attempt to insert element $name failed: $xml_file"
#        }

    log::debug "Checking current value"
    if ! current_value=$(xmlstarlet sel -t -v "$xpath" "$xml_file"); then
        ! xmlstarlet ed --inplace --subnode "$xpath_parent" -t elem -n "$name" -v "$default_value" "$xml_file" \
            && log::Error "Failed to insert $name element into server.config: $xml_file" \
            && return 1
        ! current_value=$(xmlstarlet sel -t -v "$xpath" "$xml_file") \
            && log::Error "Attempt to insert element $name failed: $xml_file" \
            && return 1
    fi

    if [[ $current_value == $disallowed_value ]]; then
        log::status "Updating server.config: $xpath: $current_value => $default_value"
        xmlstarlet ed --inplace -u "$xpath" -v "$default_value" "$xml_file" \
            && log::success "OK." \
            || log::Error "Failed to update server.config with correct $name value."
    elif [[  $current_value != $default_value ]]; then
        log::caution "Warning: server.config: $xpath == $current_value. The default for local development is $default_value"
    fi
}

# @test
 test_function() {
    server_config=$(get_tmpfile xml)
    echo "$test_server_config_xml" > $server_config
    xpath=//WebServerSettings/WebPort
    _geo_xml_upsert $xpath 10000 80 $server_config
    xmlstarlet sel -t -v "$xpath" "$server_config"
    port=$(xmlstarlet sel -t -v "$xpath" "$server_config")
    [[ $port == 10000 ]] && log::success "WebPort = 10000 added"
    xpath=//WebServerSettings/WebSSLPort
    _geo_xml_upsert $xpath 100001 433 $server_config
    xmlstarlet sel -t -v "$xpath" "$server_config"
    port=$(xmlstarlet sel -t -v "$xpath" "$server_config")
    [[ $port == 100001 ]] && log::success "WebPort = 100001 added"
#    TODO: Add tests for when the ports are set to 80/433
}

#input_args="
#a
#b
#c"
#expected_output="$input_args"

#echo "$input_args" | test_function
#func_output="$(echo "$input_args" | test_function)"

# TODO: Create functions for formatting test output and assertions
#log::status '* Expected:'
#log::code "$expected_output"
#log::status '* Actual:'
#log::code "$func_output"
#if [[ $func_output != "$expected_output" ]]; then
#    log::error [FAILED]
##    log::status '* Expected:'
##    log::code "$expected_output"
##    log::status '* Actual:'
##    log::code "$func_output"
#else
#    log::success '[PASS]'
#fi




test_server_config_xml='<?xml version="1.0" encoding="utf-8"?>
<WebServerSettings>
  <SettingsVersion>42</SettingsVersion>
  <IsDebugMode>true</IsDebugMode>
  <IsWebTestDebugMode>false</IsWebTestDebugMode>
  <IsStoreForwardEnabled>false</IsStoreForwardEnabled>
  <IsWebEnabled>true</IsWebEnabled>
  <WebInternalSSLPort>8443</WebInternalSSLPort>
  <RequireSSL>false</RequireSSL>
  <DefaultSqlType>Empty</DefaultSqlType>
  <DefaultSqlServer>127.0.0.1</DefaultSqlServer>
  <DefaultLogin>
    <User>geotabuser</User>
    <Password>vircom43</Password>
  </DefaultLogin>
</WebServerSettings>
'

has() {
  command -v "$1" 1>/dev/null 2>&1
}

# Gets path to a temporary file, even if
get_tmpfile() {
  suffix="$1"
  if has mktemp; then
    printf "%s.%s" "$(mktemp)" "${suffix}"
  else
    # No really good options here--let's pick a default + hope
    printf "/tmp/geo-cli-test.%s" "${suffix}"
  fi
}


test_function
