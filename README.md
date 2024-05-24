# Purman

Poor man's docker container monitoring system.

## Install

```sh
curl -Ls https://raw.githubusercontent.com/CaffeineDuck/purman/main/install.sh | bash -s -- install
```

<details>
    <summary>
        ## How to uninstall and update?
    </summary>

    ### Uninstall
    ```sh
    curl -Ls https://raw.githubusercontent.com/CaffeineDuck/purman/main/install.sh | bash -s -- uninstall
    ```
    ### Update
    ```sh
    curl -Ls https://raw.githubusercontent.com/CaffeineDuck/purman/main/install.sh | bash -s -- update

    ```

</details>

## CLI Usage

```sh
Usage: ./purman.sh <command>

Options:
    help            Show this help message
    init            Initialize purman
    dump_stats      Continously dump container stats to database
    dump_status     Continously dump container status logs to database

Configuration:
    CONTAINER_NAMES List of container names to monitor. Default: All running containers
    WAIT_TIME       Time in seconds to wait between each dump. Default: 30
    LOG_LEVEL       Log level to use (INFO | DEBUG | WARN | ERROR). Default: INFO
    DIR_PATH        Directory path to store data. Default: $HOME/.purman
    LOG_LINES       Number of lines to store in logs. Default: 200
```
