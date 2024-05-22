#!/bin/bash

set -e

LOG_LEVEL=${LOG_LEVEL:-INFO}
WAIT_TIME=${WAIT_TIME:-15}
DIR_PATH=${DIR_PATH:-"$HOME/.purman"}
LOG_LINES=${LOG_LINES:-200}

DB_PATH="$DIR_PATH/docker_stats.db"
LOGS_DIR="$DIR_PATH/logs"
STATS_TABLE_NAME="container_stats"
STATUS_LOGS_TABLE_NAME="container_status_logs"

STATS_TABLE_SQL="
    CREATE TABLE IF NOT EXISTS $STATS_TABLE_NAME (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        container_name TEXT,
        cpu_perc REAL,
        mem_perc REAL,
        mem_usage REAL,
        mem_capacity REAL,
        net_input REAL,
        net_output REAL,
        block_input REAL,
        block_output REAL,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    );
"
CONTAINER_STATUS_LOGS_SQL="
    CREATE TABLE IF NOT EXISTS $STATUS_LOGS_TABLE_NAME (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        container_name TEXT,
        log_type TEXT, -- CRASHED | NOT_FOUND | HEALTHY
        log_fp TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    );
"

_handle_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        _log_message "ERROR" "Script exited with code $exit_code at line ${BASH_LINENO[0]} due to command: ${BASH_COMMAND}"
    fi
}
trap _handle_exit EXIT

_log_message() {
    local level=$1
    shift
    local message=$@
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Disable exit on error for conditional checks
    set +e

    case $level in
    DEBUG)
        [[ "$LOG_LEVEL" == "DEBUG" ]] && echo "$timestamp [DEBUG] $message"
        ;;
    INFO)
        [[ "$LOG_LEVEL" == "INFO" || "$LOG_LEVEL" == "DEBUG" ]] &&
            echo "$timestamp [INFO] $message"
        ;;
    WARN)
        [[ "$LOG_LEVEL" == "WARN" || "$LOG_LEVEL" == "INFO" ||
            "$LOG_LEVEL" == "DEBUG" ]] && echo "$timestamp [WARN] $message"
        ;;
    ALARM)
        [[ $LOG_LEVEL == "ALARM" || $LOG_LEVEL == "WARN" ||
            $LOG_LEVEL == "INFO" || $LOG_LEVEL == "DEBUG" ]] &&
            echo "$timestamp [ALARM] $message"
        ;;
    ERROR)
        echo "$timestamp [ERROR] $message"
        ;;
    esac

    # Re-enable exit on error for conditional checks
    set -e
}

function _convert_to_bytes() {
    local value=$1
    echo $value | awk '
        /KiB/ {printf "%.0f", $1 * 1024; exit}
        /MiB/ {printf "%.0f", $1 * 1024 * 1024; exit}
        /GiB/ {printf "%.0f", $1 * 1024 * 1024 * 1024; exit}
        /TiB/ {printf "%.0f", $1 * 1024 * 1024 * 1024 * 1024; exit}
        /kB/ {printf "%.0f", $1 * 1000; exit}
        /MB/ {printf "%.0f", $1 * 1000 * 1000; exit}
        /GB/ {printf "%.0f", $1 * 1000 * 1000 * 1000; exit}
        /TB/ {printf "%.0f", $1 * 1000 * 1000 * 1000 * 1000; exit}
        /B/ {printf "%.0f", $1; exit}
        {print "Error: Unrecognized format"; exit 1}
    '
}

_validate_or_create_data_dir() {
    if [[ ! -d "$DIR_PATH" ]]; then
        _log_message "DEBUG" "Directory $DIR_PATH does not exist. Creating it..."
        mkdir -p "$DIR_PATH"
        _log_message "DEBUG" "Directory $DIR_PATH created successfully."
    else
        _log_message "DEBUG" "Directory $DIR_PATH already exists."
    fi

    if [[ ! -d "$LOGS_DIR" ]]; then
        _log_message "DEBUG" "Directory $LOGS_DIR does not exist. Creating it..."
        mkdir -p "$LOGS_DIR"
        _log_message "DEBUG" "Directory $LOGS_DIR created successfully."
    else
        _log_message "DEBUG" "Directory $LOGS_DIR already exists."
    fi
}

_validate_or_create_db_table() {
    if [[ ! -d "$DB_PATH" ]]; then
        _log_message "DEBUG" "Database $DB_PATH does not exist. Creating it..."
        sqlite3 "$DB_PATH" "$STATS_TABLE_SQL"
        sqlite3 "$DB_PATH" "$CONTAINER_STATUS_LOGS_SQL"
    else
        _log_message "DEBUG" "Database $DB_PATH already exists."
    fi
}

_validate_or_fetch_container_names() {
    if [[ -z "$CONTAINER_NAMES" ]]; then
        _log_message "WARN" "No container names provided. Fetching all container names..."
        CONTAINER_NAMES=$(docker ps --format "{{.Names}}")
    else
        _log_message "DEBUG" "Container names provided: $CONTAINER_NAMES"
    fi
}

_insert_container_status_log() {
    local container_name=$1
    local log_type=$2
    local log_error_message=$3
    local log_fp=""

    _log_message "DEBUG" "Checking latest log for container $container_name ($log_type)"
    existing_log=$(sqlite3 $DB_PATH "
        SELECT log_type FROM $STATUS_LOGS_TABLE_NAME
            WHERE container_name='$container_name'
            ORDER BY timestamp DESC LIMIT 1
    " | tr -d '[:space:]')

    if [[ -z "$existing_log" ]]; then
        _log_message "DEBUG" "Existing log type for container $container_name: '$existing_log'"
    fi

    if [[ "$existing_log" == "$log_type" ]]; then
        _log_message "INFO" "Latest log type for container $container_name is already $log_type, no new entry added."
        return 0
    fi

    if [[ "$log_type" == "CRASHED" ]]; then
        local random_string=$(openssl rand -hex 12)
        log_fp="$LOGS_DIR/$container_name-$random_string.log"

        docker logs --tail $LOG_LINES $container_name &>$log_fp
        _log_message "ALARM" "Container $container_name has crashed. Log file: $log_fp"
    fi

    _log_message "INFO" "Inserting status log for container $container_name ($log_type)"

    sqlite3 $DB_PATH "
    INSERT INTO $STATUS_LOGS_TABLE_NAME 
        (container_name, log_type, log_fp) 
    VALUES 
        ('$container_name', '$log_type', '$log_fp');
    "
}

_insert_container_stats() {
    local container_name=$1
    local cpu_perc=$2
    local mem_usage=$3
    local mem_perc=$4
    local mem_capacity=$5
    local net_input=$6
    local net_output=$7
    local block_input=$8
    local block_output=$9

    _log_message "INFO" "Inserting stats for container $container_name."

    sqlite3 $DB_PATH <<-EOD
        INSERT INTO $STATS_TABLE_NAME (
            container_name,
            cpu_perc,
            mem_usage,
            mem_perc,
            mem_capacity,
            net_input,
            net_output,
            block_input,
            block_output
        ) 
        VALUES(
            '$container_name',
            $cpu_perc,
            $mem_usage, 
            $mem_perc,
            $mem_capacity,
            $net_input,
            $net_output,
            $block_input,
            $block_output
        );
EOD
}

_check_container() {
    local running=$(docker inspect --format="{{ .State.Running }}" "$1" 2>/dev/null)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo 404 # Container not found
    elif [ "$running" == "false" ]; then
        echo 500 # Container has crashed
    else
        echo 200 # Container is running
    fi
}

_check_all_containers_are_healthy() {
    for container_name in $CONTAINER_NAMES; do
        local status_str=$(_check_container "$container_name" | tr -d -c 0-9)
        local status=$(($status_str))

        if [[ $status -eq 404 ]]; then
            _log_message "ERROR" "Container $container_name not found."
        elif [[ $status -eq 500 ]]; then
            _log_message "ERROR" "Container $container_name has stopped."
        elif [[ $status -eq 200 ]]; then
            _log_message "INFO" "Container $container_name is running."
        fi
    done
}

function _dump_stats_to_db() {
    _check_all_containers_are_healthy

    docker_stats=$(docker stats --no-stream --format "{{ json . }}" $CONTAINER_NAMES)
    echo "$docker_stats" |
        jq -r '. | [.Name, .CPUPerc, .MemUsage, .MemPerc, .NetIO, .BlockIO] | @csv' |
        while IFS=, read -r name cpu_perc mem_usage mem_perc net_io block_io; do
            local name=$(echo $name | tr -d '" ')
            local cpu_perc=$(echo $cpu_perc | tr -d '"% ')
            local mem_perc=$(echo $mem_perc | tr -d '"% ')

            local mem_usage_str=$(echo $mem_usage | awk -F' / ' '{print $1}' | tr -d '" ')
            local mem_capacity_str=$(echo $mem_usage | awk -F' / ' '{print $2}' | tr -d '" ')
            local mem_usage_bytes=$(_convert_to_bytes $mem_usage_str)
            local mem_capacity_bytes=$(_convert_to_bytes $mem_capacity_str)

            local net_input=$(echo $net_io | awk -F' / ' '{print $1}' | tr -d '" ')
            local net_output=$(echo $net_io | awk -F' / ' '{print $2}' | tr -d '" ')
            local net_input_bytes=$(_convert_to_bytes $net_input)
            local net_output_bytes=$(_convert_to_bytes $net_output)

            local block_input=$(echo $block_io | awk -F' / ' '{print $1}' | tr -d '" ')
            local block_output=$(echo $block_io | awk -F' / ' '{print $2}' | tr -d '" ')
            local block_input_bytes=$(_convert_to_bytes $block_input)
            local block_output_bytes=$(_convert_to_bytes $block_output)

            _insert_container_stats \
                "$name" \
                "$cpu_perc" \
                "$mem_usage_bytes" \
                "$mem_perc" \
                "$mem_capacity_bytes" \
                "$net_input_bytes" \
                "$net_output_bytes" \
                "$block_input_bytes" \
                "$block_output_bytes"
        done
}

function _dump_status_logs_to_db() {
    for container_name in $CONTAINER_NAMES; do
        local status_str=$(_check_container $container_name | tr -d -c 0-9)
        local status=$(($status_str))

        _log_message "DEBUG" "Container $container_name status: $status"

        if [ $status -eq 200 ]; then
            _insert_container_status_log $container_name "HEALTHY"
        elif [ $status -eq 404 ]; then
            _insert_container_status_log $container_name "NOT_FOUND"
        elif [ $status -eq 500 ]; then
            _insert_container_status_log $container_name "CRASHED"
        fi
    done
}

function _handle_pre_checks() {
    _validate_or_fetch_container_names

    if [[ -z "$CONTAINER_NAMES" ]]; then
        _log_message "ERROR" "No container names provided. Exiting."
        exit 1
    fi
}

function initialize() {
    _log_message "INFO" "Initializing purman..."
    _validate_or_create_data_dir

    _log_message "INFO" "Initializing database..."
    _validate_or_create_db_table

    _log_message "INFO" "Validating container names..."
    _validate_or_fetch_container_names

    _log_message "INFO" "Checking container status..."
    _check_all_containers_are_healthy

    _log_message "INFO" "Initialization complete."
}

function continously_dump_stats() {
    _handle_pre_checks

    _log_message "INFO" "Starting continous dump of container stats."
    while true; do
        _log_message "DEBUG" "Dumping container stats to database."
        _dump_stats_to_db
        _log_message "DEBUG" "Dumping stats to database. Sleeping for $WAIT_TIME seconds."
        sleep $WAIT_TIME
    done
}

function continously_dump_status_logs() {
    _handle_pre_checks

    _log_message "INFO" "Starting continous dump of container status logs."

    while true; do
        _log_message "DEBUG" "Dumping container status logs to database."
        _dump_status_logs_to_db
        _log_message "DEBUG" "Dumped status logs to database. Sleeping for $WAIT_TIME seconds."
        sleep $WAIT_TIME
    done
}

function read_container_status_logs() {
    sqlite3 "$DB_PATH" "
        SELECT * FROM $STATUS_LOGS_TABLE_NAME;
    "
}

function read_container_stats() {
    sqlite3 "$DB_PATH" "
        SELECT * FROM $STATS_TABLE_NAME;
    "
}

HELP_TEXT="
Purman - Docker container monitoring tool

Usage: $0 <command>

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
"

case $1 in
init)
    initialize
    ;;
dump_stats)
    continously_dump_stats
    ;;
dump_status)
    continously_dump_status_logs
    ;;
read_logs)
    read_container_status_logs
    ;;
read_stats)
    read_container_stats
    ;;
help)
    echo "$HELP_TEXT"
    ;;
*)
    echo "Invalid command: $1"
    echo "$HELP_TEXT"
    exit 1
    ;;
esac
