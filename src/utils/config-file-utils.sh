cfg_key_lookup_escape() {
    sed -e 's/[]\/$*.^[]/\\&/g'
}

cfg_value_escape() {
    sed ':a;N;$!ba;s/\n/__n__/g'
}

cfg_value_unescape() {
    sed 's/__n__/\n/g'
}

cfg_write() { # path, key, value
    if [[ $2 = 'GEO_REPO_DIR' && $3 = '' ]]; then
        echo "Warning: config-file-utils:cfg_write: preventing '' from being writen to GEO_REPO_DIR"
        return 1
    fi
    local file="$1"
    # Don't escape the key when writing to file. We only want to escape it when looking for it in a file.
    local key="$2"
    local value=$(echo "$3" | cfg_value_escape)
    cfg_delete "$file" "$key"
    echo "$key=$value" >> "$file"
}

cfg_read() { # path, key -> value
    local file="$1"
    local key=$(echo "$2" | cfg_key_lookup_escape)
    test -f "$file" && grep "^$key=" "$file" | sed "s/^$key=//" | tail -1 | cfg_value_unescape
}

cfg_delete() { # path, key
    local file="$1"
    local key=$(echo "$2" | cfg_key_lookup_escape)
    test -f "$file" && sed -i "/^$key="'.*$/d' "$file"
}

cfg_haskey() { # path, key
    local file="$1"
    local key=$(echo "$2" | cfg_key_lookup_escape)
    test -f "$file" && grep "^$key=" "$file" >/dev/null
}
