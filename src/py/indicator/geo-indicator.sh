export dir=$(dirname "${BASH_SOURCE[0]}")
# export dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)
echo $dir
# sleep 1
# export PYTHONPATH="$dir:$PYTHONPATH"
python3 "$dir/geo_indicator.py"
# (
#     cd "$dir"
#     python3   "$dir/geo_indicator.py"
# #    python3  -m "./indicator/geo_indicator.py"
# )
#python3 "$dir/geo-indicator.py"
# python3 "$dir/indicator/geo_indicator.py"