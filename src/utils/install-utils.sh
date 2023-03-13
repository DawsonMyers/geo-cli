#!/bin/bash
#
# Gets the absolute path of the root geo-cli directory.

[[ -z $GEO_CLI_DIR ]] && export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
[[ -z $GEO_CLI_SRC_DIR ]] && export GEO_CLI_SRC_DIR="$GEO_CLI_DIR/src"

# . "$GEO_CLI_SRC_DIR/cli/cli-handlers.sh"
# . "$GEO_CLI_SRC_DIR/cli/cli-handlers.sh"
export GEO_UTILS_DIR="$(dirname "${BASH_SOURCE[0]}")"
. "$GEO_UTILS_DIR/log.sh"

install-utils::install-nautilus-scripts() {
    # Set up the nautilus context menu scripts.
    local script_dir="$GEO_CLI_SRC_DIR/includes/nautilus-scripts"

    if [[ -d $script_dir ]]; then
        log::status "Adding file explorer (Nautilus) context menu scripts"
        local nautilus_script_dir=~/.local/share/nautilus/scripts
        [[ ! -d $nautilus_script_dir ]] && mkdir $nautilus_script_dir
        # cp $GEO_CLI_SRC_DIR/includes/nautilus-scripts/* $nautilus_script_dir/
        local script_added=false

        # Remove old scripts.
        rm -f $nautilus_script_dir/\[geo-cl\]*

        for script in "$script_dir"/*; do
            local script_name="${script##*/}"
            log::code "  => $script_name"

            [[ -f $script && $(stat -L -c '%a' "$script") != 700 ]] && chmod 700 "$script"
            local target_script_path="$nautilus_script_dir/$script_name"
            [[ -f $target_script_path ]] && rm "$target_script_path"
            # [[ ! -f $target_script_path ]] && cp "$script" "$nautilus_script_dir/$script_name"
            ln -sf "$script" "$target_script_path" || log::Error "Failed to link script to $(log::file $target_script_path/)"
            # log::detail "  $script  $script_name -> .local/share/nautilus/scripts/"
            log::success
            script_added=true
        done

        $script_added && log::info "\nYou can access the above scripts by right clicking on a file/folder in the Nautilus file explorer (Ubuntu default) to open the context menu and then expanding the Scripts submenu"
        echo
    fi
}

# Make the 'geo-cli' command globally available as an executable by adding a symbolic link from geo-cli to
# ~/.local/bin/geo-cli. This allows the geo-cli command to be run by any type of shell (since the script will always
# run in bash because of the shebang (#!/bin/bash) at the top of the file) as long as it is executed (like this
# 'geo-cli <args>' instead of 'source geo-cli.sh').
install-utils::install-geo-cli-executable() {
    [[ ! -e $HOME/.local/bin/geo-cli ]] \
        && mkdir -p "$HOME"/.local/bin

    if [[ -f $GEO_CLI_SRC_DIR/geo-cli.sh ]]; then
        local myg_branch_version="$(@geo_dev release)"
        local myg_branch_version=${myg_branch_version:-11.0}

        if ln -fs "$GEO_CLI_SRC_DIR"/geo-cli.sh $HOME/.local/bin/geo-cli; then
            log::status "Linking $(log::txt_underline 'geo-cli') executable to $(log::txt_underline "~/.local/bin/geo-cli")" # " to make it available in all terminals."
            log::success
            echo

            geo_cli_exec_text="$EMOJI_BULLET The $(log::txt_underline 'geo-cli') command is available to be run in $(log::txt_underline 'any') type of shell (bash, zsh, fish, etc.) as an executable (which will always run in bash, regardless of the shell type that executes it) to $(log::link "~/.local/bin/geo-cli")."
            geo_exec_text="$EMOJI_BULLET The $(log::txt_underline 'geo') command is available in bash shells only. It is loaded as a function into each bash shell via the .bashrc file."

            log::info -b "Run $(log::txt_underline geo-cli) any shell"
            log::info "$(log::fmt_text_and_indent_after_first_line "$geo_cli_exec_text" 1 3)"
            echo
            log::info "$(log::fmt_text_and_indent_after_first_line "$geo_exec_text" 1 3)"
            echo
            log::info "$(log::txt_underline Example): Create/start a geo-cli managed database container for MyGeotab"
            log::code "    geo db start $myg_branch_version     "
            log::detail " OR"
            log::code "    geo-cli db start $myg_branch_version"
            echo
        else
            log::error "Failed to make symlink"
        fi
    fi
}

install-utils::init-gitlab-pat() {
    # Ensure GitLab environment variable file has correct permissions.
    PAT_ENV_VAR_FILE_PATH="$GEO_CLI_CONFIG_DIR/env/gitlab-pat.sh"
    [[ -f $PAT_ENV_VAR_FILE_PATH && $(stat -L -c '%a' $PAT_ENV_VAR_FILE_PATH) != 600 ]] && chmod 600 "$PAT_ENV_VAR_FILE_PATH"

    _geo_check_for_dev_repo_dir

    installed_msg=''
    if [[ $previously_installed_version ]]; then
        . ~/.bashrc
        installed_msg="The new version of geo-cli is now available in this terminal, as well as all new ones."
    else
        installed_msg="Open a new terminal or source .bashrc by running '. ~/.bashrc' in this one to start using geo-cli."
    fi
    log::success "$installed_msg"
}