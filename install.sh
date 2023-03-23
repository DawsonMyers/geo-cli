#!/bin/bash
if [[ -z $BASH_VERSION ]] ; then
    echo "ERROR: geo-cli must run in a Bash terminal to function correctly. Please run this script with Bash (i.e. 'bash install.sh')"; exit 1;
fi

export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
export GEO_CLI_SRC_DIR="${GEO_CLI_DIR}/src"

# Import config file utils for writing to the geo config file (~/.geo-cli/.geo.conf).
# shellcheck source-path=SCRIPTDIR
. "$GEO_CLI_SRC_DIR/cli/cli-handlers.sh"

# shellcheck source=utils/install-utils.sh
. "$GEO_CLI_SRC_DIR/utils/install-utils.sh"
# . $GEO_CLI_SRC_DIR/utils/log.sh


export GEO_CLI_CONFIG_DIR="$HOME/.geo-cli"
export GEO_CLI_CONF_FILE="$GEO_CLI_CONFIG_DIR/.geo.conf"
# Create config dir if it doesn't exist.
[ ! -d "$GEO_CLI_CONFIG_DIR" ] && mkdir -p $GEO_CLI_CONFIG_DIR
[ ! -d "$GEO_CLI_CONFIG_DIR/data/geo" ] && mkdir -p "$GEO_CLI_CONFIG_DIR/data/geo"
echo -n "$GEO_CLI_DIR" > "$GEO_CLI_CONFIG_DIR/data/geo/repo-dir"

# Create .geo.conf file if it doesn't exist. 
# This file contains environment vars for geo cli.
[ ! -f "$GEO_CLI_CONFIG_DIR/.geo.conf" ] && cp "$GEO_CLI_SRC_DIR/config/.geo.conf" "$GEO_CLI_CONFIG_DIR"
export GEO_CLI_VERSION=$(cat $GEO_CLI_DIR/version.txt)
previously_installed_version=$(@geo_get GEO_CLI_VERSION)
@geo_set GEO_CLI_DIR "$GEO_CLI_DIR"
@geo_set GEO_CLI_SRC_DIR "$GEO_CLI_SRC_DIR"
@geo_set GEO_CLI_CONFIG_DIR "$GEO_CLI_CONFIG_DIR"
@geo_set GEO_CLI_CONF_FILE "$GEO_CLI_CONF_FILE"
@geo_set GEO_CLI_VERSION "$GEO_CLI_VERSION"
@geo_set OUTDATED false

# The prev_commit is the commit hash that was stored last time geo-cli was updated. cur_commit is the commit hash of
# this version of geo-cli. The commit messages between theses two hashes are shown to the user to show what's new in
# this update. The hashes are passed in as params when the 'geo update' command runs this script.
prev_commit=$1
cur_commit=$2

# Check if the current branch is a feature branch.
if [[ $(@geo_get FEATURE) == true ]]; then
    if _geo_check_if_feature_branch_merged; then
        cur_commit=$(git rev-parse HEAD)
        @geo_rm FEATURE
        @geo_rm FEATURE_VER_LOCAL
        @geo_rm FEATURE_VER_REMOTE
        bash "$GEO_CLI_DIR/install.sh" $prev_commit $cur_commit
        exit
    fi
    GEO_CLI_VERSION=$(@geo_get FEATURE_VER_REMOTE)
    previously_installed_version=$(@geo_get FEATURE_VER_LOCAL)
    [[ -z $GEO_CLI_VERSION ]] && GEO_CLI_VERSION=$previously_installed_version
fi

# Remove previous aliases/config from .bashrc/.zshrc for geo command.
# Remove content starting at "#geo-cli-start" and ending at "#geo-cli-end" comments.
sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.bashrc
[[ -f ~/.zshrc ]] && sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.zshrc
# sed -i '/source .*geo-cli-init.*/d' ~/.zshrc

# Append cli alias and env config to ~/.bashrc so that the geo command can be 
# used in any terminal.
# Substitute the env vars into init file text and append to .bashrc. 
envsubst < "$GEO_CLI_DIR"/src/init/bashrc.sh >> ~/.bashrc
# Add geo to the .zshrc file if it exists.
[[ -f $HOME/.zshrc ]] && sed "s+GEO_CLI_SRC_DIR+$GEO_CLI_SRC_DIR+" $GEO_CLI_SRC_DIR/init/zshrc.sh >> ~/.zshrc

_geo_check_docker_installation
_geo_install_apt_package_if_missing 'jq'
_geo_install_apt_package_if_missing 'xmlstarlet'

# Init submodules.
git submodule update --init --recursive

geotab_logo
geo_logo
echo

# 🎉
if [[ $previously_installed_version ]]; then
    log::verbose -b "geo-cli updated $previously_installed_version -> $GEO_CLI_VERSION"
else
    log::verbose -b "geo-cli $GEO_CLI_VERSION installed"
fi

echo

# Display commit messages between the old version and the new version (if any).
# prev_commit=daf4b4adeaff0223b590d978d3fc41a5e2324332
# cur_commit=901e0c31528e27b21216826b7cb338a39bec6185
if [[ -n $prev_commit && -n $cur_commit ]]; then
    _geo_print_messages_between_commits_after_update $prev_commit $cur_commit && echo    
fi

# Enable notification if the SHOW_NOTIFICATIONS setting doesn't exist in the config file.
show_notifications=$(@geo_get SHOW_NOTIFICATIONS)
[[ -z $show_notifications ]] && @geo_set SHOW_NOTIFICATIONS true

# Reset update notification.
@geo_set UPDATE_NOTIFICATION_SENT false

# Generate geo autocompletions.
geo_generate_autocompletions

# Set up app indicator service if not in headless Ubuntu (no UI).
running_in_headless_ubuntu=$(dpkg -l ubuntu-desktop | grep 'no packages found')
if [[ -z $running_in_headless_ubuntu ]]; then
    @geo_indicator init
    echo
fi

install-utils::init-gitlab-pat
# # Ensure GitLab environment variable file has correct permissions.
# PAT_ENV_VAR_FILE_PATH="$GEO_CLI_CONFIG_DIR/env/gitlab-pat.sh"
# [[ -f $PAT_ENV_VAR_FILE_PATH && $(stat -L -c '%a' $PAT_ENV_VAR_FILE_PATH) != 600 ]] && chmod 600 "$PAT_ENV_VAR_FILE_PATH"

# _geo_check_for_dev_repo_dir

# installed_msg=''
# if [[ $previously_installed_version ]]; then
#     . ~/.bashrc
#     installed_msg="The new version of geo-cli is now available in this terminal, as well as all new ones."
# else
#     installed_msg="Open a new terminal or source .bashrc by running '. ~/.bashrc' in this one to start using geo-cli."
# fi
# log::success "$installed_msg"
# log::success "$(log::fmt_text_and_indent_after_first_line -d 4 "$installed_msg" 0 5)"
echo

install-utils::install-nautilus-scripts

# Make the 'geo-cli' command globally available as an executable by adding a symbolic link from geo-cli to
# ~/.local/bin/geo-cli. This allows the geo-cli command to be run by any type of shell (since the script will always
# run in bash because of the shebang (#!/bin/bash) at the top of the file) as long as it is executed (like this
# 'geo-cli <args>' instead of 'source geo-cli.sh').
install-utils::install-geo-cli-executable


# [[ ! -e $HOME/.local/bin/geo-cli ]] && mkdir -p "$HOME"/.local/bin
# if [[ -f $GEO_CLI_SRC_DIR/geo-cli.sh ]]; then
#     myg_branch_version="$(@geo_dev release)"
#     myg_branch_version=${myg_branch_version:-11.0}

#     if ln -fs "$GEO_CLI_SRC_DIR"/geo-cli.sh $HOME/.local/bin/geo-cli; then
#         log::status "Linking $(log::txt_underline 'geo-cli') executable to $(log::txt_underline "~/.local/bin/geo-cli")" # " to make it available in all terminals."
#         echo

#         geo_cli_exec_text="$EMOJI_BULLET The $(log::txt_underline 'geo-cli') command is available to be run in $(log::txt_underline 'any') type of shell (bash, zsh, fish, etc.) as an executable (which will always run in bash, regardless of the shell type that executes it) to $(log::link "~/.local/bin/geo-cli")."
#         geo_exec_text="$EMOJI_BULLET The $(log::txt_underline 'geo') command is available in bash shells only. It is loaded as a function into each bash shell via the .bashrc file."

#         log::info -b 'geo-cli any shell'
#         log::info "$(log::fmt_text_and_indent_after_first_line "$geo_cli_exec_text" 1 3)"
#         echo
#         log::info "$(log::fmt_text_and_indent_after_first_line "$geo_exec_text" 1 3)"
#         echo
#         log::info "$(log::txt_underline Example): Create/start a geo-cli managed database container for MyGeotab"
#         log::code "    geo db start $myg_branch_version     "
#         log::detail " OR"
#         log::code "    geo-cli db start $myg_branch_version"
#         echo
#     else
#         log::error "Failed to make symlink"
#     fi
# fi

log::info -b "Next step: create a database container and start geotabdemo"
step1="1. Build MyGeotab.Core in your IDE (required when creating new dbs)"
step2="2. Run `log::txt_underline 'geo db start <name>'`, where 'name' is any alphanumeric name you want to give this db version (it could be related to the MyGeotab release, e.g., '10.0')."
step3="3. Start MyGeotab.Core in your IDE or via the MyGeotab > Start UI menu item"
log::info "$(log::fmt_text_and_indent_after_first_line "$step1" 3 3)"
log::info "$(log::fmt_text_and_indent_after_first_line "$step2" 3 3)"
log::info "$(log::fmt_text_and_indent_after_first_line "$step3" 3 3)"
echo

echo -n ' ⭐  '
log::hint -nbu " Like geo-cli? " && log::hint -n " Add a star to the repo:\n"
log::code  -n '      * '
log::link ' https://git.geotab.com/dawsonmyers/geo-cli'
# log::hint -fn "Join the geo-cli Chat Space to report bugs, share feature ideas, and stay informed about new features:"
# echo -n ' ✨ '
echo
echo -n ' 💬  '
log::hint -nbu " Join the geo-cli Chat Space " && log::hint " to report bugs, share feature ideas, and stay"
log::hint "     informed about new features:"
log::code  -n '      * '
log::link ' https://chat.google.com/room/AAAAo9gDWgg?cls=7'

# Install setproctitle, which lets us rename the python process for the UI to be 'geo-cli'.
python3 -m pip install setproctitle &> /dev/null

# # Set up update cron job.
# if type crontab > /dev/null; then
#     check_for_updates_with_cron_job=$@geo_get CHECK_FOR_UPDATES_WITH_CRON_JOB)
#     # Add the CHECK_FOR_UPDATES_WITH_CRON_JOB setting if it doesn't exist; enabling it by default.
#     [[ -z $check_for_updates_with_cron_job ]] && @geo_set CHECK_FOR_UPDATES_WITH_CRON_JOB true && check_for_updates_with_cron_job=true
#     cron_function=_geo_check_for_updates
#     # Run the _geo_check_for_updates function every weekday at 9am.
#     cronjob="0 9 * * 1-5 $cron_function"

#     if [[ $check_for_updates_with_cron_job == true ]]; then
#         # Lists all of the current cron jobs, removes existing jobs containing the $cron_function, adds the new cron job
#         # to the existing ones, and then adds all of them to crontab.
#         ( crontab -l | grep -v -F "$cron_function" ; echo "$cronjob" ) | crontab -
#     elif [[ $check_for_updates_with_cron_job == false ]]; then
#         # Remove update cron job (if any).
#         ( crontab -l | grep -v -F "$cron_function" ) | crontab -
#     fi
# fi