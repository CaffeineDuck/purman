# Purman

Poor man's docker container monitoring system.

```sh
Usage: ./purman.sh <command>

Options:
    help            Show this help message
    init            Initialize purman
    dump_stats      Continously dump container stats to database
    dump_status     Continously dump container status logs to database
    read_logs       Read container status logs from database
    read_stats      Read container stats from database

Configuration:
    CONTAINER_NAMES List of container names to monitor. Default: All running containers
    WAIT_TIME       Time in seconds to wait between each dump. Default: 15
    LOG_LEVEL       Log level to use (INFO | DEBUG | WARN | ERROR). Default: INFO
    DIR_PATH        Directory path to store data. Default: $HOME/.purman/data
    LOG_LINES       Number of lines to store in logs. Default: 200
```
