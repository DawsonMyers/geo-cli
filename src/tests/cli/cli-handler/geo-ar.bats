#!/usr/bin/env bats
. ./../src/geo-cli.sh
setup() {
    # executed before each test
    echo "setup" >&3
}

teardown() {
    # executed after each test
    echo "teardown" >&3
}

#@test test_name {
#    _geo_ar__copy_pgAdmin_server_config
#    true
#}

alias ":["="cat <<__GEO_BLOCK
eval echo "\$\(\( $* \)\)"
"

alias "]:"="
__GEO_BLOCK
"
#alias "]:"="$(echo -e "\n__GEO_BLOCK\n")"

