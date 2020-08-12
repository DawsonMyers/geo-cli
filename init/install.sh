# Import config file utils for writing to the geo config file (~/.geo-cli/.geo.conf).
. ./src/utils/config-file-utils.sh
. ./src/utils/cli-handlers.sh

GEO_CLI_DIR="$HOME/.geo-cli/cli"
# GEO_CLI_DIR="$HOME/.geo-cli/cli"
GEO_CONFIG_DIR=~/.geo-cli
GEO_CONF_FILE=$GEO_CONFIG_DIR/.geo.conf

# Remove previous version of geo.
rm -rf $GEO_CLI_DIR

# Create cli directory.
mkdir -p $GEO_CLI_DIR
cp -r ./* $GEO_CLI_DIR
# cp -r ./src/cli/* $GEO_CLI_DIR

# Create .geo.conf file if it doesn't exist. 
# This file contains environment vars for geo cli.
[ ! -f "$GEO_CONFIG_DIR/.geo.conf" ] && (cp ./src/config/.geo.conf $GEO_CONFIG_DIR)
# [ ! -f "$GEO_CONFIG_DIR/.geo.conf" ] && (cp $GEO_CLI_DIR/src/config/.geo.conf $GEO_CONFIG_DIR)
 
# Remove previous aliases/config from ~/.profile for geo command.
# Remove content starting at "#geo-cli-start" and ending
# at "#geo-cli-end" comments.
sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.bashrc
sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.profile
sed -i '/#geo-cli-start/,/#geo-cli-end/d' ~/.zshrc
# sed -i '/source .*geo-cli-init.*/d' ~/.zshrc

# Append cli alias and env config to ~/.profile so that the geo command can be 
# used in any terminal.
cat $GEO_CLI_DIR/src/init/bashrc.sh >> ~/.bashrc
cat $GEO_CLI_DIR/src/init/bashrc.sh >> ~/.profile
cat $GEO_CLI_DIR/src/init/zshrc.sh >> ~/.zshrc