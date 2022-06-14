sed_escape() {
  sed -e 's/[]\/$*.^[]/\\&/g'
}

sed_value_escape() {
  sed ':a;N;$!ba;s/\n/__n__/g'
}

sed_value_unescape() {
  sed 's/__n__/\n/g'
}

cfg_write() { # path, key, value
  if [[ $2 = 'GEO_REPO_DIR' && $3 = '' ]]; then
    echo "Warning: config-file-utils:cfg_write: preventing '' from being writen to GEO_REPO_DIR"
    return 1
  fi
  local key=$(echo "$2" | sed_escape)
  local value=$(echo "$3" | sed_value_escape)
  cfg_delete "$1" "$key"
  echo "$key=$value" >> "$1"
}

cfg_read() { # path, key -> value
  test -f "$1" && grep "^$(echo "$2" | sed_escape)=" "$1" | sed "s/^$(echo "$2" | sed_escape)=//" | tail -1 | sed_value_unescape
}

cfg_delete() { # path, key
  test -f "$1" && sed -i "/^$(echo $2 | sed_escape)=.*$/d" "$1"
}

cfg_haskey() { # path, key
  test -f "$1" && grep "^$(echo "$2" | sed_escape)=" "$1" > /dev/null
}