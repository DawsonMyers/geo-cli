#!/bin/bash
if [ -z "$BASH" ] ; then echo "Please run this script $0 with bash"; exit 1; fi
export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
export GEO_CLI_SRC_DIR="${GEO_CLI_DIR}/src"

# Import config file utils for writing to the geo config file (~/.geo-cli/.geo.conf).
. $GEO_CLI_SRC_DIR/utils/cli-handlers.sh

export GEO_CLI_CONFIG_DIR="$HOME/.geo-cli"
export GEO_CLI_CONF_FILE="$GEO_CLI_CONFIG_DIR/.geo.conf"
# Create config dir if it doesn't exist.
[ ! -d "$GEO_CLI_CONFIG_DIR" ] && mkdir -p $GEO_CLI_CONFIG_DIR

# Create .geo.conf file if it doesn't exist. 
# This file contains environment vars for geo cli.
[ ! -f "$GEO_CLI_CONFIG_DIR/.geo.conf" ] && (cp $GEO_CLI_SRC_DIR/config/.geo.conf $GEO_CLI_CONFIG_DIR)
export GEO_CLI_VERSION=`cat $GEO_CLI_DIR/version.txt`
previously_installed_version=`geo_get GEO_CLI_VERSION`
geo_set GEO_CLI_DIR $GEO_CLI_DIR
geo_set GEO_CLI_SRC_DIR $GEO_CLI_SRC_DIR
geo_set GEO_CLI_CONFIG_DIR $GEO_CLI_CONFIG_DIR
geo_set GEO_CLI_CONF_FILE $GEO_CLI_CONF_FILE
geo_set GEO_CLI_VERSION "$GEO_CLI_VERSION"
geo_set OUTDATED false

if [[ $(geo_get FEATURE) == true ]]; then
    GEO_CLI_VERSION=$(geo_get FEATURE_VER_REMOTE)
    previously_installed_version=$(geo_get FEATURE_VER_LOCAL)
fi

# Remove previous aliases/config from .bashrc/.zshrc for geo command.
# Remove content starting at "#geo-cli-start" and ending at "#geo-cli-end" comments.
sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.bashrc
[[ -f ~/.zshrc ]] && sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.zshrc
# sed -i '/source .*geo-cli-init.*/d' ~/.zshrc

# Append cli alias and env config to ~/.bashrc so that the geo command can be 
# used in any terminal.
# Substitute the env vars into init file text and append to .bashrc. 
envsubst < $GEO_CLI_DIR/src/init/bashrc.sh >> ~/.bashrc
# Add geo to the .zshrc file if it exists.
[[ -f $HOME/.zshrc ]] && sed "s+GEO_CLI_SRC_DIR+$GEO_CLI_SRC_DIR+" $GEO_CLI_SRC_DIR/init/zshrc.sh >> ~/.zshrc

check_docker_installation

geotab_logo
geo_logo
echo

if [[ $previously_installed_version ]]; then
    verbose_bi "geo-cli updated $previously_installed_version -> $GEO_CLI_VERSION"
else
    verbose_bi "geo-cli $GEO_CLI_VERSION installed"
fi

echo

# Display commit messages between the old version and the new version (if any).
prev_commit=$1
cur_commit=$2
# prev_commit=daf4b4adeaff0223b590d978d3fc41a5e2324332
# cur_commit=901e0c31528e27b21216826b7cb338a39bec6185
if [[ -n $prev_commit && -n $cur_commit ]]; then
    _geo_print_messages_between_commits_after_update $prev_commit $cur_commit
    echo
fi

# Enable notification if the SHOW_NOTIFICATIONS setting doesn't exist in the config file.
show_notifications=$(geo_get SHOW_NOTIFICATIONS)
[[ -z $show_notifications ]] && geo_set SHOW_NOTIFICATIONS true

# Reset update notification.
geo_set UPDATE_NOTIFICATION_SENT false

# Generate geo autocompletions.
geo_generate_autocompletions

# Set up app indicator service if not in headless Ubuntu (no UI).
running_in_headless_ubuntu=$(dpkg -l ubuntu-desktop | grep 'no packages found')
if [[ -z $running_in_headless_ubuntu ]]; then
    geo_indicator init
fi


geo_check_for_dev_repo_dir

installed_msg=''
if [[ $previously_installed_version ]]; then
    . ~/.bashrc
    installed_msg="The new version of geo-cli is now available in this terminal, as well as all new ones."
else
    installed_msg="Open a new terminal or source .bashrc by running '. ~/.bashrc' in this one to start using geo-cli."
fi
success "$(fmt_text_and_indent_after_first_line "$installed_msg" 0 5)"
echo

info_bi "Next step: create a database container and start geotabdemo"
step1="1. Build MyGeotab.Core in your IDE (required when creating new dbs)"
step2="2. Run `txt_underline 'geo db start <name>'`, where 'name' is any alphanumeric name you want to give this db version (it could be related to the MyGeotab release, e.g., '2004')."
step3="3. Start MyGeotab.Core in your IDE"
info "$(fmt_text_and_indent_after_first_line "$step1" 3 3)"
info "$(fmt_text_and_indent_after_first_line "$step2" 3 3)"
info "$(fmt_text_and_indent_after_first_line "$step3" 3 3)"
echo

# # Set up update cron job.
# if type crontab > /dev/null; then
#     check_for_updates_with_cron_job=$(geo_get CHECK_FOR_UPDATES_WITH_CRON_JOB)
#     # Add the CHECK_FOR_UPDATES_WITH_CRON_JOB setting if it doesn't exist; enabling it by default.
#     [[ -z $check_for_updates_with_cron_job ]] && geo_set CHECK_FOR_UPDATES_WITH_CRON_JOB true && check_for_updates_with_cron_job=true
#     cron_function=geo_check_for_updates
#     # Run the geo_check_for_updates function every weekday at 9am.
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