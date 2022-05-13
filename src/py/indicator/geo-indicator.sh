export dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)
echo $dir
sleep 1
#python3 "$dir/geo-indicator.py"
(
    cd "$dir"
    python3   "$dir/geo-indicator.py"
#    python3  -m "./indicator/geo-indicator.py"
)
#python3 "$dir/geo-indicator.py"
# python3 "$dir/indicator/geo-indicator.py"