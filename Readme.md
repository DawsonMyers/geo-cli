# geo-cli
A tool that makes MyGeotab development easier. Specifically, this tool aims to simplify cross-release development by managing various versions of `geotabdemo` Postgres database containers. This allows you to easily switch between release branches without having to worry about database compatibility. In the future, it also aims to simplify other pain points of development by automating them; providing an easy-to-use interface that hides the complexity under the hood.

> `geo-cli` is only supported on Ubuntu.

## Example
Lets say that you're developing a new feature on a `2004` branch of MyGeotab, but have to switch to a `2002` branch for a high priority bug fix that requires the use of `geotabdemo` (or any compatible database, for that matter). Switching to a compatible database is as simple as checking out the branch, **building project** (only required when creating a new db container), and then running the following in a terminal:
```bash
geo db start 2002
```

> `2002` in the above command is just a name that you pick for the container and volume that `geo` creates for you; it can be any alphanumeric name you like. If a db container with that name already exists, it will just start that one instead of creating a new one.


The output of this command is shown below:

![geo db start](res/geo-db-start-1.png)

> Under the hood, `geo` is creating a Postgres container and a data volume for it. The tool then starts the container, mounted with the data volume, and then initializes `geotabdemo` on it using `dotnet CheckmateServer.dll CreateDatabase postgres ...`. This is why you have to build the project for a certain release branch before creating a new db container.

Now you may run `geotabdemo` or any tests that require a 2002 database version.

When you're done with the bug fix and want to resume working on your 2004 feature, switch back to your 2004 branch and run the following in a terminal: 
```
geo db start 2004
```
The output of this command is shown below:

![geo db start](res/geo-db-start-2.png)

## Installation
Navigate to your directory of choice in a terminal and clone this repo
```
git clone git@git.geotab.com:dawsonmyers/geo-cli.git
```
Next, navigate into the repo directory
```
cd geo-cli
```
And finally, execute the install script
```
bash install.sh
```
> Docker is required for `geo` to work. You will be prompted to install it during the install process if it is missing.

You will be asked to enter the location of Development repo during the install. The tool needs to know where this is so that it knows the location of:
- The CheckmateServer dll used for initializing `geotabdemo`
- The Dockerfile used to create the base Postgres image used to build the db containers

The tool will also build the base Postgres image during the install process, so it may take several minutes to complete (even longer if you also have to install Docker).

A simple install (where I already have Docker installed and have created the base db image) is shown below:

![geo db start](res/geo-install.png)

Now you can open a new terminal or run `. ~/.bashrc` in your current one to begin using `geo`.


