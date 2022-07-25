#!/bin/bash
dir=$(dirname "${BASH_SOURCE[0]}")
geo_indicator_path="$dir/geo_indicator.py"
echo "geo_indicator_path: $geo_indicator_path"
python3 "$geo_indicator_path"