check_for_dev_repo_dir() {
    local dev_repo=`geo_get DEV_REPO_DIR`

    is_valid_repo_dir() {
        test -d "${1}/Checkmate"
    }

    get_dev_repo_dir() {
        prompt 'Enter the full path (e.g. ~/repos/Development or /home/username/repos/Development) to the Development repo directory. This directory must contain the Checkmate directory:'
        read dev_repo
        # Expand home directory (i.e. ~/repo to /home/user/repo).
        dev_repo=${dev_repo/\~/$HOME}
        if [[ ! -d $dev_repo ]]; then
            warn "The provided path is not a directory"
            return 1
        fi
        if [[ ! -d "$dev_repo/Checkmate" ]]; then
            warn "The provided path does not contain the Checkmate directory"
            return 1
        fi
        echo $dev_repo
    }

    while ! is_valid_repo_dir "$dev_repo"; do
        get_dev_repo_dir
    done

    success "Checkmate directory found"

    # geo_get DEV_REPO_DIR "$dev_repo"

}
check_for_dev_repo_dir