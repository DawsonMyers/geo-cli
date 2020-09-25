#!/bin/bash
# Import config file utils for writing to the geo config file (~/.geo-cli/.geo.conf).
export GEO_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 
export GEO_SRC_DIR="${GEO_CLI_DIR}/src"

. $GEO_SRC_DIR/utils/cli-handlers.sh

export GEO_CONFIG_DIR=$HOME/.geo-cli
export GEO_CONF_FILE=$GEO_CONFIG_DIR/.geo.conf

# Create config dir if it doesn't exist.
[ ! -d "$GEO_CONFIG_DIR" ] && mkdir -p $GEO_CONFIG_DIR

# Create .geo.conf file if it doesn't exist. 
# This file contains environment vars for geo cli.
[ ! -f "$GEO_CONFIG_DIR/.geo.conf" ] && (cp ./src/config/.geo.conf $GEO_CONFIG_DIR)
geo_set GEO_CLI_DIR $GEO_CLI_DIR
geo_set GEO_SRC_DIR $GEO_SRC_DIR

export GEO_CLI_VERSION=`cat $GEO_CLI_DIR/version.txt`
geo_set GEO_CLI_VERSION $GEO_CLI_VERSION

# Remove previous aliases/config from ~/.profile for geo command.
# Remove content starting at "#geo-cli-start" and ending
# at "#geo-cli-end" comments.
sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.bashrc
sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.profile
# sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.zshrc
# sed -i '/source .*geo-cli-init.*/d' ~/.zshrc

# Append cli alias and env config to ~/.profile so that the geo command can be 
# used in any terminal.
# Substitute the env vars into init file text and append to .bashrc. 
envsubst < $GEO_CLI_DIR/src/init/bashrc.sh >> ~/.bashrc
# cat $GEO_CLI_DIR/src/init/bashrc.sh >> ~/.profile
# cat $GEO_CLI_DIR/src/init/zshrc.sh >> ~/.zshrc

# Install Docker and Docker Compose if needed
if ! type docker > /dev/null; then
    warn 'Docker not installed'
    info_b -p 'Install Docker and Docker Compose (Y|n)?: '
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
        sudo curl -L "https://github.com/docker/compose/releases/download/1.27.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo apt-key fingerprint 0EBFCD88
        sudo add-apt-repository \
        "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) \
        stable"

        sudo apt-get update
        sudo apt-get install -y docker-ce

        sudo chmod +x /usr/local/bin/docker-compose
        docker-compose --version
        success 'OK'
    fi
fi

geo_logo
echo
verbose_bi "geo-cli $GEO_CLI_VERSION installed"
echo

geo_check_for_dev_repo_dir

success "Open an new terminal or run '. ~/.bashrc' in this one to start using geo-cli"


