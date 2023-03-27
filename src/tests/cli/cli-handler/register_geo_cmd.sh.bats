#!/usr/bin/env bats
#echo $(cd ./../../../ && pwd)
geo_dir=$(cat ~/.geo-cli/data/geo/repo-dir)
. $geo_dir/src/geo-cli.sh

setup() {

    # executed before each test
    echo "setup" >&3
}

teardown() {
    # executed after each test
    echo "teardown" >&3
}

@test "test_name" {
    @register_geo_cmd 'indicator|ui'
}


geo-cli::relative_import
