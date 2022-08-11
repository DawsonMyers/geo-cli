# `geo-cli`
A tool that makes MyGeotab development easier. Specifically, this tool aims to simplify cross-release development by managing various versions of `geotabdemo` Postgres database containers. This allows you to easily switch between release branches without having to worry about database compatibility. In the future, it also aims to simplify other pain points of development by automating them; providing an easy-to-use interface that hides the complexity under the hood.

> `geo-cli` is currently under active development and is updated often. Please contact me on Chat or through email (dawsonmyers@geotab.com) if you have a feature idea or would like to report a bug.

> `geo-cli` is only supported on Ubuntu. However, it can be made to work in WSL on Windows if you set up docker for it.

## Table of Contents
- [`geo-cli`](#geo-cli)
  - [Table of Contents](#table-of-contents)
  - [Example](#example)
  - [Getting Started with `geo-cli`](#getting-started-with-geo-cli)
    - [Install](#install)
    - [Create a Database](#create-a-database)
    - [Copying Databases](#copying-databases)
    - [List Databases](#list-databases)
    - [Removing Databases](#removing-databases)
    - [Creating Empty Databases](#creating-empty-databases)
    - [Querying the Database](#querying-the-database)
    - [Running Analyzers](#running-analyzers)
    - [Options](#options)
    - [Connecting to Servers Using IAP Tunnels](#connecting-to-servers-using-iap-tunnels)
    - [Encode/Decode MyGeotab Long and Guid Ids](#encodedecode-mygeotab-long-and-guid-ids)
      - [Examples](#examples)
    - [Running Tests](#running-tests)
      - [Setting up a GitLab Access Token](#setting-up-a-gitlab-access-token)
      - [Quarantining Tests](#quarantining-tests)
- [`geo-ui` (NEW)](#geo-ui-new)
  - [Databases](#databases)
    - [Running DB](#running-db)
    - [Databases](#databases-1)
    - [Create Database](#create-database)
    - [Auto-Switch](#auto-switch)
      - [Auto-Switch DB](#auto-switch-db)
      - [Auto-Install npm](#auto-install-npm)
      - [Auto-Switch server.config](#auto-switch-serverconfig)
      - [Auto-Clean GeotabDemo Data](#auto-clean-geotabdemo-data)
  - [Dev Utilities](#dev-utilities)
    - [Run Analyzers](#run-analyzers)
    - [npm install](#npm-install)
    - [Convert MyGeotab Long/Guid Ids](#convert-mygeotab-longguid-ids)
    - [Access Requests](#access-requests)
  - [Help](#help)
  - [Updates](#updates)
- [Help](#help-1)
- [Troubleshooting](#troubleshooting)
  - [Update issues](#update-issues)
  - [Problems Creating Databases](#problems-creating-databases)

<!-- Make images > 892 px wide -->

## Example
Lets say that you're developing a new feature on a `2004` branch of MyGeotab, but have to switch to a `2002` branch for a high priority bug fix that requires the use of `geotabdemo` (or any compatible database, for that matter). Switching to a compatible database is as simple as checking out the branch, **building the project** (only required when creating a new db container), and then running the following in a terminal:
```bash
geo db start 2002
```

> `2002` in the above command is just a name that you pick for the container and volume that `geo` creates for you; it can be any alphanumeric name you like. If a db container with that name already exists, it will just start that one instead of creating a new one.


The output of this command is shown below:

![geo db start](res/geo-db-start-1.png)

> Under the hood, `geo` is creating a Postgres container and a data volume for it. The tool then starts the container, mounted with the data volume, and then initializes `geotabdemo` on it using `dotnet CheckmateServer.dll CreateDatabase postgres ...`. This is why you have to build the project for a certain release branch before creating a new db container.

Now you may run `geotabdemo` or any tests that require a 2002 database version.

When you're done with the bug fix and want to resume working on your 2004 feature, switch back to your 2004 branch and run the following in a terminal: 
```bash
geo db start 2004
```
The output of this command is shown below:

![geo db start](res/geo-db-start-2.png)

## Getting Started with `geo-cli`
### Install
Navigate to your directory of choice in a terminal and clone this repo
```bash
git clone git@git.geotab.com:dawsonmyers/geo-cli.git
```
Next, navigate into the repo directory
```bash
cd geo-cli
```
And finally, execute the install script
```bash
bash install.sh
```
> Docker is required for `geo` to work. You will be prompted to install it during the install process if it is missing. You must completely log out and then back in again after a Docker install for the new permissions to take effect.

You will be asked to enter the location of Development repo during the install. The tool needs to know where this is so that it knows the location of:
- The CheckmateServer dll used for initializing `geotabdemo`
- The Dockerfile used to create the base Postgres image used to build the db containers

The tool will also build the base Postgres image during the install process, so it may take several minutes to complete (even longer if you also have to install Docker).

A simple install (where I already have Docker installed and have created the base db image) is shown below:

![geo db start](res/geo-install.png)

Now you can open a new terminal or run `. ~/.bashrc` to re-source .bashrc in your current one to begin using `geo`.

<!-- ### Start Using `geo-cli` -->

Now that `geo-cli` is installed, you can begin using it for creating and running various database versions for your development needs.

### Create a Database
The first thing that you want to do after installing the tool is to create a database. The MyGeotab Postgres database will be created using `CheckmateServer.dll` from the current branch that you have checked out, so you must build MyGeotab before the correct `dll` will be available to `geo-cli`.

Next, we will create, initialize, and start your first database. You will have to give it an alphanumeric name to identify it (the MyGeotab release version is usually the best name to use, e.g., `2004`). So, assuming that you're working on a `2004` branch of MyGeotab, a database could be created by entering the following in a terminal:
```bash
geo db start 2004
```
> You will be prompted to stop Postgres if you have it running locally or in a container. This is so that port 5432 can be made available for a `geo-cli` database.

The output is shown below:

![geo db start 2004](res/geo-db-start-3.png)

### Copying Databases
You can make a copy of a `geo-cli` database using:
```bash
geo db cp <source> <destination>
```
Example:
```bash
$ geo db cp 8.0 8.0-copy

Creating destination database volume '8.0-copy'

Copying data from source database volume '8.0' to '8.0-copy'
✔️   Done

Creating destination database container '8.0-copy'
✔️   Done

```

### List Databases
You can list your `geo-cli` databases using:
```bash
geo db ls
```
![list dbs 1](res/geo-db-ls-1.png)

### Removing Databases
The following command will remove the `2001` database from `geo-cli`:
```bash
geo db rm 2001
```
![rm db](res/geo-db-rm.png)

> You can delete all databases using `geo db rm --all`. You will be prompted before continuing.

You can confirm that the `2001` database has been removed by listing your `geo-cli` databases:

![list dbs 2](res/geo-db-ls-2.png)

### Creating Empty Databases
`geo-cli` can also be used to create empty databases for any use case you may encounter:

![geo db create](res/geo-db-create-1.png)

This creates a postgres db with the sql admin as **geotabuser** and the password as **vircom43**.

If you would like a completely empty Postgres 12 db without any initialization, add the **-e** option to the command, e.g., `geo db create -e <name>`. The default user for Postgres is `postgres` and the password is `password`. This username/password can be used to connect to the db (once started) using pgAdmin.

> The `geo db create` command does not start the container after creating it. Use `geo db start <name>` to start it.

### Querying the Database
`geo db psql` can be used to start an interactive psql session with a running database container. If you just want to run a single query, you can use the `-q` option to specify an sql query:
```bash
geo db psql -q 'SELECT * FROM deviceshare'
```

>Note: The query must be enclosed in single quotes

### Running Analyzers
This is a new feature that is still being developed. It can be accessed using:
```bash
geo analyze
```
This will output the selection menu and prompt you for which analyzers you want to run:

![analyze 1](res/geo-analyze-1.png)

So if you wanted to run `CSharp.CodeStyle` and `StyleCop.Analyzers` you would type `0 4` and press enter:

![analyze 2](res/geo-analyze-2.png)

The output is then displayed as the analyzers are run:

![analyze 3](res/geo-analyze-3.png)

### Options
The following options can be used with `geo analyze`:
- **\-** This option will reuse the last test ids supplied
- **\-a** This option will run all tests
- **\-b** Run analyzers in batches (reduces runtime, but is only supported in 2104+)

### Connecting to Servers Using IAP Tunnels
`geo-cli` can be used to simplify connecting to servers over IAP tunnels. First, make an access request for a server using MyAdmin. Then copy *gcloud compute start-iap-tunnel* command by pressing the copy button:

> `geo ar create` can be used to open up the My Access Request page on the MyAdmin website in Chrome. This page can be used to create a new access request.

![mya access request](res/geo-ar-myadmin.png)

After that, paste the gcloud command in a terminal as an argument to `geo ar tunnel` as shown below:

![geo ar tunnel](res/geo-ar-tunnel.png)

> `geo-cli` will remember the gcloud command so that you can re-open the tunnel by running just `geo ar tunnel` without the gcloud command. It also remembers the port that the tunnel is running on so that you don't have to include it when running `geo ar ssh`

Now you can open another terminal and run the `geo ar ssh` command to ssh into the server:

![geo ar ssh](res/geo-ar-ssh.png)

> By default, the username stored in th $USER environment variable is used when connecting to the server with `geo ar ssh`. You can set the default username by supplying it with the `-u <username>` option. You can also use a different port using the `-p <port>` option.

### Encode/Decode MyGeotab Long and Guid Ids
Use the `geo id <id>` command to both encode and decode long and guid ids to simplify working with the MyGeotab api. The result is copied to your clipboard (if you have xclip installed). Guid encoded ids must be prefixed with 'a' and long encoded ids must be prefixed with 'b'"

#### Examples

Long Encode
```bash
geo id 1234
Encoded long id: 
b4d2
copied to clipboard
```

Long Decode
```bash
geo id b4d2
Decoded long id: 
1234
copied to clipboard
```

Guid Encode
```bash
geo id 00e74ee1-97e7-4f28-9f5e-2ad222451f6d
Encoded guid id: 
aAOdO4ZfnTyifXirSIkUfbQ
copied to clipboard
```

Guid Decode
```bash
geo id aAOdO4ZfnTyifXirSIkUfbQ
Decoded guid id: 
00e74ee1-97e7-4f28-9f5e-2ad222451f6d
copied to clipboard
```

### Running Tests
The `geo test <filter>` command can be used to run tests on your local build. The filter behaves the same as in [dotnet test --filter](https://docs.microsoft.com/en-us/dotnet/core/testing/selective-unit-tests?pivots=xunit). By default, tests matching the given `filter` will be run on your local machine. When run with the `-d` or `--docker` option, the tests will be run in a docker container which matches the one used in CI/CD pipelines instead. This option requires [docker to be logged into gitlab](https://git.geotab.com/dev/Development/container_registry/), and is only supported from 9.0 onwards.

#### Setting up a GitLab Access Token
Go to https://git.geotab.com/-/profile/personal_access_tokens and create a token with api access. Copy the token to your clipboard and then run the following command in a terminal:
```
  docker login git.geotab.com:4567
```
You will then be prompted for your GitLab username and a password. Paste (<kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>V</kbd>) the access token in your clipboard when asked for the password.

#### Quarantining Tests
Use `geo quarantine` to add quarantine annotations to a broken test.

Before running `geo quarantine`:
```bash
    [Fact]
    public void Test()
    {
```

After:
```bash
    [Fact]
    [Trait("TestCategory", "Quarantine")]
    [Trait("QuarantinedTestTicketLink", "")]
    public void Test()
    {
```

```bash
geo quarantine [options] <FullyQualifiedTestName>
      Adds quarantine annotations to a broken test and, optionally, commits the test file.
        Options:
            -b
                Only print out the git blame for the test.
            -c
                Commit the file after adding the annotations to it.
            -m <msg>
                Add a custom commit message. If absent, the default commit
                message will be "Quarantined test $testclass.$testname".
        Example:
            geo quarantine -c
            CheckmateServer.Tests.Web.DriveApp.Login.ForgotPasswordTest.Test
            geo quarantine -c -m 'Quarentine test'
            CheckmateServer.Tests.Web.DriveApp.Login.ForgotPasswordTest.Test
```

# `geo-ui` (NEW)
`geo-ui` is a tray menu UI (app indicator) that further simplifies MyGeotab development. It allows users to quickly access most of `geo-cli`'s features, as well as adding some additional ones, with just a couple mouse clicks.

![geo ui](res/ui/geo-ui-1.png)

## Databases
The first section of the menu contains controls related to working with MyGeotab database containers. 

![database section](res/ui/geo-ui-db-1.png)


### Running DB

This menu item shows the name of the database that is currently running inside of square brackets (e.g. `Running DB [9]` for a db named "9"). If no database is running, the item will be disabled and its label will be "No DB running". It also has a submenu that provides the following functionality:
  * `Stop`: Stops the database container
  * `SSH`:  Opens a terminal and starts an SSH session into the db container
  * `PSQL`:  Opens a terminal, starts an SSH session into the db container, and then starts a psql session for the geotabdemo database
  
> The G tray icon will be green if a database is running or red if there isn't one running.

![geo-ui-db-2](res/ui/geo-ui-2.png) ![geo-ui-db-2](res/ui/geo-ui-db-2.png)

> There seems to be a bug in the framework used to build the menu items that will sometimes remove underscores from labels. So if you have a db named 9_0, it might be rendered as 'Running DB [90]'. 

### Databases
This item allows you start or remove any of your database containers.

![geo-ui-db-3](res/ui/geo-ui-db-3.png) ![geo-ui-db-4](res/ui/geo-ui-db-4.png)

### Create Database
This item opens a terminal and will guide you through creating a new MyGeotab database.
> Note: Make sure you have built MyGeotab.Core on the current branch that you have checked out. The db container will be compatible with the MyGeotab release version of that branch.

> You usually want to name the database container after the MyGeotab release version that it is compatible with (e.g. '9' for version 9.0).

![geo-ui-db-5](res/ui/geo-ui-db-5.png)

### Auto-Switch

![geo-ui-as-1](res/ui/geo-ui-as-1.png)

The Auto-Switch feature performs certain tasks when the checked out MyGeotab release version changes (i.e., from 8.0 to 9.0).
This submenu contains the following items:
  1) `Auto-Install npm`: Enables/disables auto-installing npm in both the `CheckmateServer/src/wwwroot` and `CheckmateServer/src/wwwroot/drive` directories
  2) `Auto-Switch server.config`: Enables/disables auto-switching server.config files
  3) `Auto-Clean GeotabDemo Data`: Enables/disables auto-clean for geotabdemo data
  4) `Auto-Switch DB`: Enables/disables auto-switching database containers
  5) `MYG Release: ...`: Displays the MyGeotab release version of the currently checked out branch
  6) `Configured DB: ...`: Displays the name of the database container that is linked to the current MyGeotab release version
  7) `Set DB for MYG Release/Configured DB Running`: Links the current MyGeotab release version to the running database container


#### Auto-Switch DB
You can link a MyGeotab release version to a database container by doing the following:
  1) Checkout a MyGeotab release branch that you want to link a database container to. The `MYG Release` label shows the MyGeotab release version of the current branch
  2) Start a compatible database container (using the `Databases` submenu)
  3) Click the `Set DB for MYG Release` button under the `Auto-Switch` submenu

The `Configured DB` label will now show the name of the database container and the `Set DB for MYG Release` button will be disabled and labeled `Configured DB Running`. 

Now the configured database container will automatically start whenever you checkout a branch based on its linked MyGeotab release version.

#### Auto-Install npm
When enabled, `npm install` will automatically be run in both the `CheckmateServer/src/wwwroot` and `CheckmateServer/src/wwwroot/drive` directories.

#### Auto-Switch server.config
> This is an experimental feature, it is advised that you make a copy of your server.config file before enabling it.


When enabled, the server.config file will automatically be switched based on the MyGeotab release version of the Development branch that is currently checked out.

This example shows how it works once enabled:
1. Auto-Switch server.config is enabled for the first time
2. The MyGeotab release version of your current branch is `8.0`
3. You edit the server.config file with specific settings for `8.0`
4. You checkout a `9.0` branch
5. The server.config file at `~/GEOTAB/Checkmate/server.config` is copied and renamed to `~/.geo-cli/data/server-config/server.config_8.0`
6. Since this is the first time you have switched release versions with this feature enabled, there isn't a `9.0` server.config version available in `~/.geo-cli/data/server-config/`, so the file at `~/GEOTAB/Checkmate/server.config` remains unchanged
7. You edit the server.config file with specific settings for `9.0`
8. You checkout the `8.0` branch again
9. The server.config file at `~/GEOTAB/Checkmate/server.config` is copied and renamed to `~/.geo-cli/data/server-config/server.config_9.0`
10. The matching file for the release version is copied and renamed from `~/.geo-cli/data/server-config/server.config_8.0` to  `~/GEOTAB/Checkmate/server.config`, replacing the current server.config file with the `8.0` version

You can now continue switching to different release branches and setting up specific settings in the server.config for each one. Your changes will always be saved/restored when switching to/from a certain MyGeotab release branch.

#### Auto-Clean GeotabDemo Data
When enabled, the geotabdemo_data directory in `~GEOTAB/Checkmate/` will be removed when the MyGeotab release version changes. The data generated in this directory may not be compatible between releases and can cause errors when starting up geotabdemo. This file will always be recreated when geotabdemo starts up if it is missing.

## Dev Utilities
These items provide access to utilities that aim to simplify MyGeotab development.

![geo-ui-gu-1](res/ui/geo-ui-gu-1.png)

### Run Analyzers
This submenu provides the following options:
  1) `All`: Runs all analyzers
  2) `Choose`: Lets you choose analyzers from a list that you would like to run
  3) `Previous`: Runs the same analyzers as you ran last time

![geo-ui-gu-2](res/ui/geo-ui-gu-2.png)
![geo-ui-gu-3](res/ui/geo-ui-gu-3.png)

### npm install
This item will run `npm install` in both the `CheckmateServer/src/wwwroot` and `CheckmateServer/src/wwwroot/drive` directories. This is required for MyGeotab.Core to build after switching from one MyGeotab release branch to another (e.g. 9.0 to 8.0).

### Convert MyGeotab Long/Guid Ids
The following two items provide access to MyGeotab long/guid id conversion:
1) `Convert Long/Guid Ids`: Opens a terminal where you may enter a long/guid encoded/decoded id to convert. The result is copied to your clipboard
2) `Convert Id from Clipboard`: Opens a terminal, converts an id from your clipboard, copies the result to your clipboard, and then closes the terminal

> Tip: Middle clicking on the G tray icon will run `Convert Id from Clipboard`. Allowing you to quickly convert ids from your clipboard with just one click.

### Access Requests
This submenu provides access to utilities for working with access requests. It contains the following items:

  1) `Create`: Opens up the Access Request page on MyAdmin where you can create a new access request
  2) `IAP Tunnel`: A submenu menu for working with IAP tunnels. It has the following items:
     1) `Start New`: Opens a terminal were you can paste in the gcloud command that you copied from your MyAdmin access request. An SSH session is automatically started after the IAP tunnel is opened
     2) `Start Previous`: Opens a submenu where you can select from the previous 5 gcloud commands to reopen an IAP tunnel. An SSH session is automatically started after the IAP tunnel is opened
  3) `SSH Over Open IAP`: Opens up a terminal and starts an SSH session using the port from the IAP tunnel that was most recently opened

![geo ui iap 1](res/ui/geo-ui-iap-1.png) ![geo ui iap 2](res/ui/geo-ui-iap-2.png) ![geo ui iap 3](res/ui/geo-ui-iap-3.png)

> If your SSH session is closed (e.g. via timeout), you may press Enter in the terminal to restart it.

## Help
The `Help` submenu contains the following items:

  1) `Show Notifications`: Enables or disables notification from being shown
  2) `View Readme`: Opens up this Readme in Chrome
  3) `Disable`: Disables the ui. It can be re-enabled by opening up a terminal and running `geo indicator enable`


![geo ui help menu](res/ui/geo-ui-help-1.png)

## Updates 
![geo ui update icon](res/ui/geo-icon-green-update.png)

`geo-ui` periodically checks for updates. When a new version is available, the G icon will have a red dot in the lower right corner of it (as shown above). To install the new update, click on the `Update Now` button. 

![geo ui update icon](res/ui/geo-ui-update-1.png)

# Help
Get help for a specific command by entering `geo [command] help`.

Example:
```bash
geo db help
```
Gives you the following:
```html
    db
      Database commands.
        Commands:
            create [option] <name>
                Creates a versioned db container and volume.
                  Options:
                    -y
                      Accept all prompts.
                    -e 
                      Create blank Postgres 12 container.
            start [option] [name]
                Starts (creating if necessary) a versioned db container and volume. If no name is provided, the
                most recent db container name is started.
                  Options:
                    -y
                      Accept all prompts.
            cp <source_db> <destination_db>
                Makes a copy of an existing database container.
            rm, remove [option] <version> [additional version to remove]
                Removes the container and volume associated with the provided version (e.g. 2004).
                  Options:
                    -a, --all
                      Remove all db containers and volumes.
            stop [version]
                Stop geo-cli db container.
            ls [option]
                List geo-cli db containers.
                  Options:
                    -a, --all
                      Display all geo images, containers, and volumes.
            ps
                List running geo-cli db containers.
            init
                Initialize a running db container with geotabdemo or an empty db with a custom name.
                  Options:
                    -y
                      Accept all prompts.
            psql [options]
                Open an interactive psql session to geotabdemo (or a different db, if a db name was provided with
                the -d option) in the running geo-cli db container. You can also use the -q option to execute a
                query on the database instead of starting an interactive session. The default username and password
                used to connect is geotabuser and vircom43, respectively.
                  Options:
                    -d
                      The name of the postgres database you want to connect to. The default value used is "geotabdemo"
                    -p
                      The admin sql password. The default value used is "vircom43"
                    -q
                      A query to run with psql in the running container. This option will cause the result of the
                      query to be returned instead of starting an interactive psql terminal.
                    -u
                      The admin sql user. The default value used is "geotabuser"
            bash
                Open a bash session with the running geo-cli db container.
            script <add|edit|ls|rm> <script_name>
                Add, edit, list, or remove scripts that can be run with geo db psql -q script_name.
                  Options:
                    add
                      Adds a new script and opens it in a text editor.
                    edit
                      Opens an existing script in a text editor.
                    ls
                      Lists existing scripts.
                    rm
                      Removes a script.
        Example:
            geo db start 2004
            geo db start -y 2004
            geo db create 2004
            geo db rm 2004
            geo db rm --all
            geo db rm 7.0 8.0 9.0
            geo db cp 9.0 9.1
            geo db rm --all
            geo db ls
            geo db psql
            geo db psql -u mySqlUser -p mySqlPassword -d dbName
            geo db psql -q "SELECT * FROM deviceshare LIMIT 10"
```

While running the following results in all help being printed:
```bash
geo help
```

<details>
Available commands:
    image
      Commands for working with db images.
        Commands:
            create
                Creates the base Postgres image configured to be used with geotabdemo.
            remove
                Removes the base Postgres image.
            ls
                List existing geo-cli Postgres images.
        Example:
            geo image create
    db
      Database commands.
        Commands:
            create [option] <name>
                Creates a versioned db container and volume.
                  Options:
                    -y
                      Accept all prompts.
                    -e 
                      Create blank Postgres 12 container.
            start [option] [name]
                Starts (creating if necessary) a versioned db container and volume. If no name is provided, the
                most recent db container name is started.
                  Options:
                    -y
                      Accept all prompts.
            cp <source_db> <destination_db>
                Makes a copy of an existing database container.
            rm, remove [option] <version> [additional version to remove]
                Removes the container and volume associated with the provided version (e.g. 2004).
                  Options:
                    -a, --all
                      Remove all db containers and volumes.
            stop [version]
                Stop geo-cli db container.
            ls [option]
                List geo-cli db containers.
                  Options:
                    -a, --all
                      Display all geo images, containers, and volumes.
            ps
                List running geo-cli db containers.
            init
                Initialize a running db container with geotabdemo or an empty db with a custom name.
                  Options:
                    -y
                      Accept all prompts.
            psql [options]
                Open an interactive psql session to geotabdemo (or a different db, if a db name was provided with
                the -d option) in the running geo-cli db container. You can also use the -q option to execute a
                query on the database instead of starting an interactive session. The default username and password
                used to connect is geotabuser and vircom43, respectively.
                  Options:
                    -d
                      The name of the postgres database you want to connect to. The default value used is "geotabdemo"
                    -p
                      The admin sql password. The default value used is "vircom43"
                    -q
                      A query to run with psql in the running container. This option will cause the result of the
                      query to be returned instead of starting an interactive psql terminal.
                    -u
                      The admin sql user. The default value used is "geotabuser"
            bash
                Open a bash session with the running geo-cli db container.
            script <add|edit|ls|rm> <script_name>
                Add, edit, list, or remove scripts that can be run with geo db psql -q script_name.
                  Options:
                    add
                      Adds a new script and opens it in a text editor.
                    edit
                      Opens an existing script in a text editor.
                    ls
                      Lists existing scripts.
                    rm
                      Removes a script.
        Example:
            geo db start 2004
            geo db start -y 2004
            geo db create 2004
            geo db rm 2004
            geo db rm --all
            geo db rm 7.0 8.0 9.0
            geo db cp 9.0 9.1
            geo db rm --all
            geo db ls
            geo db psql
            geo db psql -u mySqlUser -p mySqlPassword -d dbName
            geo db psql -q "SELECT * FROM deviceshare LIMIT 10"
    ar
      Helpers for working with access requests.
        Commands:
            create
                Opens up the My Access Request page on the MyAdmin website in Chrome.
            tunnel [gcloud start-iap-tunnel cmd]
                Starts the IAP tunnel (using the gcloud start-iap-tunnel command copied from MyAdmin after opening
                an access request) and then connects to the server over SSH. The port is saved and used when you
                SSH to the server using geo ar ssh. This command will be saved and re-used next time
                you call the command without any arguments (i.e. geo ar tunnel)
                  Options:
                    -s
                      Only start the IAP tunnel without SSHing into it.
                    -l
                      List and choose from previous IAP tunnel commands.
            ssh
                SSH into a server through the IAP tunnel started with geo ar ssh.
                  Options:
                    -p <port>
                      The port to use when connecting to the server. This value is optional since the port that
                      the IAP tunnel was opened on using geo ar ssh is used as the default value
                    -u <user>
                      The user to use when connecting to the server. This value is optional since the username
                      stored in $USER is used as the default value. The value supplied here will be stored and
                      reused next time you call the command
        Example:
            geo ar tunnel -s gcloud compute start-iap-tunnel gceseropst4-20220109062647 22 --project=geotab-serverops
            --zone=projects/709472407379/zones/northamerica-northeast1-b
            geo ar ssh
            geo ar ssh -p 12345
            geo ar ssh -u dawsonmyers
            geo ar ssh -u dawsonmyers -p 12345
    stop
      Stops all geo-cli containers.
        Example:
            geo stop
    init
      Initialize repo directory.
        Commands:
            repo
                Init Development repo directory using the current directory.
            npm
                Runs 'npm install' in both the wwwroot and drive CheckmateServer directories. This is quick way to
                fix the npm dependencies after Switching to a different MYG release branch.
            pat
                Sets up the GitLab Personal Access Token environment variables.
                  Options:
                    -r
                      Removes the PAT environment variables.
                    -l, --list
                      List/display the current PAT environment variable file.
        Example:
            geo init repo
            geo init npm
    env <cmd> [arg1] [arg2]
      Get, set, or list geo environment variable.
        Commands:
            get <env_var>
                Gets the value for the env var.
            set <env_var> <value>
                Sets the value for the env var.
            rm <env_var>
                Remove geo environment variable.
            ls
                Lists all env vars.
        Example:
            geo env get DEV_REPO_DIR
            geo env set DEV_REPO_DIR /home/username/repos/Development
            geo env ls
    set <env_var> <value>
      Set geo environment variable.
        Options:
            s
                Shows the old and new value of the environment variable.
        Example:
            geo set DEV_REPO_DIR /home/username/repos/Development
    get <env_var>
      Get geo environment variable.
        Example:
            geo get DEV_REPO_DIR
    rm <env_var>
      Remove geo environment variable.
        Example:
            geo rm DEV_REPO_DIR
    update
      Update geo to latest version.
        Options:
            -f, --force
                      Force update, even if already at latest version.
        Example:
            geo update
            geo update --force
    uninstall
      Remove geo-cli installation. This prevents geo-cli from being loaded into new bash terminals, but does not
      remove the geo-cli repo directory. Navigate to the geo-cli repo directory and run 'bash install.sh' to reinstall.
        Example:
            geo uninstall
    analyze [option or analyzerIds]
      Allows you to select and run various pre-build analyzers. You can optionally include the list of analyzers
      if already known.
        Options:
            -a
                Run all analyzers
            -
                Run previous analyzers
            -g
                Run run GW-Linux-Debug pipeline analyzer.
            -i
                Run analyzers individually (building each time)
        Example:
            geo analyze
            geo analyze -a
            geo analyze 0 3 6
    id
      Both encodes and decodes long and guid ids to simplify working with the MyGeotab API. The result is copied
      to your clipboard. Guid encoded ids must be prefixed with 'a' and long encoded ids must be prefixed with 'b'
        Options:
            -o
                Do not format output.
        Example:
            geo id 1234 => b4d2
            geo id b4d2 => 1234
            geo id 00e74ee1-97e7-4f28-9f5e-2ad222451f6d => aAOdO4ZfnTyifXirSIkUfbQ
            geo id aAOdO4ZfnTyifXirSIkUfbQ => 00e74ee1-97e7-4f28-9f5e-2ad222451f6d
    version, -v, --version
      Gets geo-cli version.
        Example:
            geo version
    cd <dir>
      Change to directory
        Commands:
            dev, myg
                Change to the Development repo directory.
            geo, cli
                Change to the geo-cli install directory.
        Example:
            geo cd dev
            geo cd cli
    indicator <command>
      Enables or disables the app indicator.
        Commands:
            enable
                Enable the app indicator.
            disable
                Disable the app indicator.
            start
                Start the app indicator.
            stop
                Stop the app indicator.
            restart
                Restart the app indicator.
            status
                Gets the systemctl service status for the app indicator.
            cat
                Print out the geo-indicator.service file.
            show
                Print out all configuration for the service.
            edit
                Edit the service file.
            no-service
                Runs the indicator directly (using python3).
            log
                # Show service logs.
                  Options:
                    -b[-#]
                      Shows logs since the last boot. Can also use -b-n (n is a number) to get logs from n boots ago.
        Example:
            geo indicator enable
            geo indicator disable
    test <filter>
      Runs tests on the local build of MyGeotab.
        Options:
            -d, --docker
                Run tests in a docker environment matching the one used in ci/cd pipelines. Requires docker to be
                logged into gitlab.
            -n <number of iterations>
                Runs the test(s) n times.
            -r, --random-n <number of iterations>
                Runs the test(s) n times using random seeds.
            --random-seed <seed>
                Runs the test(s) a supplied random seed.
        Example:
            geo test UserTest.AddDriverScopeTest
            geo test -r 3 UserTest.AddDriverScopeTest
            geo test
            "FullyQualifiedName=Geotab.Checkmate.ObjectModel.Tests.JSONSerializer.DisplayDiagnosticSerializerTest.DateRangeTest|FullyQualifiedName=Geotab.Checkmate.ObjectModel.Tests.JSONSerializer.DisplayDiagnosticSerializerTest.NotificationUserModifiedValueInfoTest"
    help, -h, --help
      Prints out help for all commands.
    dev
      Commands used for internal geo-cli development.
        Commands:
            update-available
                Returns "true" if an update is available
            co <branch>
                Checks out a geo-cli branch
            release
                Returns the name of the MyGeotab release version of the currently checked out branch
            databases
                Returns a list of all of the geo-cli database container names
    quarantine [options] <FullyQualifiedTestName>
      Adds quarantine annotations to a broken test and, optionally, commits the test file.
        Options:
            -b
                Only print out the git blame for the test.
            -c
                Commit the file after adding the annotations to it.
            -m <msg>
                Add a custom commit message. If absent, the default commit message will be "Quarantined test
                $testclass.$testname".
        Example:
            geo quarantine -c CheckmateServer.Tests.Web.DriveApp.Login.ForgotPasswordTest.Test
            geo quarantine -c -m 'Quarentine test' CheckmateServer.Tests.Web.DriveApp.Login.ForgotPasswordTest.Test
```

</details>

# Troubleshooting
## Update issues
If you encounter issues while running `geo update`, try navigating to the geo-cli repo directory in a terminal and running `git pull && bash install.sh`.

## Problems Creating Databases
> *Note: you must always build MyGeotab.Core for the branch/release prior to creating a db.*

For issues while running `geo db start <version>`, try the following (to make things):

1. **Checkmate Error:Cause: EXEB84000E: Unable to upgrade 'trunk_template_2...** 
   * Lets say that you're trying to create a db on a 2102 branch using `geo db start 2102` (2102 can be any alphanumeric name) and encounter this error `Checkmate Error:Cause: EXEB84000E: Unable to upgrade 'trunk_template_2102...` try checking out master and then running `geo image create`, followed by `geo db rm 2102`, and then finally `geo db start 2102` again to recreate the db. This problem arose because we upgraded to using Postgres 12, but you may have created the base db image before the changes were made in the Postgres dockerfile; so we need to rebuild your db image for the changes to take effect.
2. **DbUnavailable**
   * If you're trying to create a db using `geo db start <version>` and encounter a DbUnavilable exception, try running `geo db init`.

3. **Unable to find image 'geo_cli_db_postgres:latest' locally**
    * This error can happen when creating a db with `geo db start NAME`. This message indicates that `geo` cannot find the base Postgres image that it uses to create db containers. Fix this by running `geo image create`, followed by the same `geo db start NAME` command again. You may want to run `geo db rm NAME` first to remove anything that was created during the earlier failed attempt.

