# Container Status

In this quick intro, we are going to install purman with
default configuration. And we are going to create a simple
tool over purman to automatically restart containers when
it crashes.

We'll also cover viewing and running through the web dashboard
in the next section.

## Install

This will install **purman** to `~/.purman/bin` and create a _symlink_
to `/usr/local/bin/purman`.

You maybe prompted to enter your user's password as we'll be using `sudo`
for creating the symlink.

```sh
curl -Ls https://raw.githubusercontent.com/CaffeineDuck/purman/main/install.sh | bash -s -- install
```

## Watch container status

We will now need to watch containers and log it's status. If it is healthy
or has crashed.

```bash
purman dump_status
```

The above command starts watching all the running containers, and logs to
database whenever a crash is detected.

## Auto restart containers

We're going to create a new shell file for this. You can name it anything
you like.

Let's start with the shebang `#!`.

```bash
#!/bin/bash
```

We are going to use the `purman-db` library that is installed
by default when you install `purman`. It contains helper methods
for reading the data from database, so we won't have to write
raw SQL queries and parse through it.

For that we need to set a env-var called `SCRIPT_DIR` which should
point to where `purman` is installed. By default it's installed in
`$HOME/.purman/bin` so let's set it as that

You need to **export** it as it's used by `purman-db`.

```bash
export SCRIPT_DIR="$HOME/.purman/bin"
```

Now let's **source** (import) the `purman-db`.

```bash
# shellcheck $HOME/.purman/bin/helpers/db.sh
source $(which purman-db)
```

The _shellcheck_ comment is for **bashls** to provide you with
function references and auto-completions.

We need a list of containers that need to be restarted when crashed.
So let's set that to all the running containers.

```bash
CONTAINER_NAMES=$(docker ps --format '{{.Names}}')
```

You can also manually pass the container names that you want to
restart when it crashes as so;

```bash
CONTAINER_NAMES=(container-name-1 container-name-2)
```

Now we have container names, but we need a way to fetch the status
details of the container from the database that `purman` has dumped
into.

Fortunately, `purman-db` provides us with the helper functions to
fetch such data.

```bash
latest_status=$(get_latest_container_status_logs_by_name $container_name)
```

Now we are able get the `latest_status` from the database, but we need to parse
it too. The output is in format of `col1|col2|col3|col4|col5`. For seperating
them, we can set the `IFS` (Internal Field Seperator) and use `read` command.

```bash
IFS='|' read -r id container_name log_type log_fp timestamp <<<"$latest_status"
```

Let's check the `log_type` to figure out if it has crashed. And if it has crashed,
let's restart the container.

```bash
if [[ $log_type == "CRASHED" ]]; then
  docker restart $container_name
fi
```

Now put all of these inside a **while-true-loop** which sleeps for specified
`WAIT_TIME` and checks all the container's status inside a **for-loop** over
`CONTAINER_NAMES`. And restarts if a crash is detected.

There you have it, simplest way to restart your container once it crashes.

For a complete example where all the edge-cases have been covered you can
you look at the examples. [Auto Restart Example](docs/examples/auto-restart)
