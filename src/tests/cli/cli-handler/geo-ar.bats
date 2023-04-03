#!/usr/bin/env bats

setup() {
    # $BATS_SETUP_COMMENT$
    echo "setup" >&3
}

teardown() {
    # $BATS_TEARDOWN_COMMENT$
    echo "teardown" >&3
}

@test "$test_name$" {
    true$END$
}
