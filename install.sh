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

geo_check_for_dev_repo_dir

if [[ $previously_installed_version ]]; then
    . ~/.bashrc
    success "The new version of geo-cli is now available in this terminal, as well as all new ones."
else
    success "Open a new terminal or source .bashrc by running '. ~/.bashrc' in this one to start using geo-cli."
fi

echo

info_bi "Next step: create a database container and start geotabdemo"
info "1. Build MyGeotab.Core in your IDE (required when creating new dbs)"
info "2. Run `txt_underline 'geo db start <name>'`, where 'name' is any alphanumeric name you want to give this db version (it could be related to the MyGeotab release, e.g., '2004')."
info "3. Start MyGeotab.Core in your IDE"

# Install Docker and Docker Compose if needed.
check_docker_installation() {
    if ! type docker > /dev/null; then
        warn 'Docker is not installed'
        info_b -p 'Install Docker and Docker Compose? (Y|n): '
        read answer
        if [[ ! $answer =~ [n|N] ]]; then
            info 'Installing Docker and Docker Compose'
            # sudo apt-get remove docker docker-engine docker.io
            sudo apt update
            sudo apt upgrade
            sudo apt-get install \
                apt-transport-https \
                ca-certificates \
                curl \
                software-properties-common
            sudo apt-get install -y build-essential make gcc g++ python
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            
            # Remove old version of docker-compose
            [ -f /usr/local/bin/docker-compose ] && sudo rm /usr/local/bin/docker-compose
            # Get the latest docker-compose version
            COMPOSE_VERSION=`git ls-remote https://github.com/docker/compose | grep refs/tags | grep -oE "[0-9]+\.[0-9][0-9]+\.[0-9]+$" | sort --version-sort | tail -n 1`
            sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION:-1.28.6}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            
            sudo apt-key fingerprint 0EBFCD88
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

            sudo apt-get update
            sudo apt-get install -y docker-ce

            # Add user to the docker group to allow docker to be run without sudo.
            sudo usermod -aG docker $USER
            sudo usermod -a -G docker $USER

            sudo chmod +x /usr/local/bin/docker-compose
            docker-compose --version

            warn 'You must completely log out of your account and log back in again to begin using docker.'
            success 'OK'
        fi
    fi
}

