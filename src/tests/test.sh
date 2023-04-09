#!/bin/bash
geo_dir=$(cat ~/.geo-cli/data/geo/repo-dir) && . "$geo_dir/src/geo-cli.sh"
. "$(cat ~/.geo-cli/data/geo/repo-dir)"
geo-cli::relative_import import.sh
$(geo-cli::relative_import import.sh)
