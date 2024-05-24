#!/bin/bash

set -e

SCRIPT_NAME="Purman"
SCRIPT_AUTHOR="CaffeineDuck <hello@samrid.me>"

export SCRIPT_DIR=${SCRIPT_DIR:-"$HOME/.purman/bin"}

# shellcheck source=helpers/defaults.sh
source $SCRIPT_DIR/helpers/defaults.sh

# shellcheck source=helpers/logger.sh
source $SCRIPT_DIR/helpers/logger.sh
log_message DEBUG "Imported helpers/logger.sh, will start logging now."

log_message DEBUG "Importing helpers/utils.sh"
# shellcheck source=helpers/utils.sh
source $SCRIPT_DIR/helpers/utils.sh

log_message DEBUG "Importing helpers/db.sh"
# shellcheck source=helpers/db.sh
source $SCRIPT_DIR/helpers/db.sh

log_message DEBUG "Importing helpers/docker.sh"
# shellcheck source=helpers/docker.sh
source $SCRIPT_DIR/helpers/docker.sh

# Handle exit gracefully with log
if [[ "$DEV_ENV" == "true" ]]; then
    trap handle_exit EXIT
fi

# Requires helpers/docker.sh to be imported
export CONTAINER_NAMES=${CONTAINER_NAMES:-"$(get_all_running_container_names)"}

create_dir_if_not_exists "$DIR_PATH"
create_dir_if_not_exists "$LOGS_DIR"
create_dir_if_not_exists "$DB_DIR"

create_tables_if_not_exists

if [[ -z "$CONTAINER_NAMES" ]]; then
    log_message ERROR "Container name not provided and no running containers found. Exiting."
    exit 1
fi

function _validate_and_insert_container_status_log() {
    local required_args=(
        "CONTAINER_NAME"
        "LOG_TYPE"
    )
    check_required_args "${FUNCNAME[0]}" "${required_args[@]}"

    log_message DEBUG "Checking latest log for container $CONTAINER_NAME ($LOG_TYPE)"

    local existing_log=$(get_latest_log_type_for_container "$CONTAINER_NAME")
    if [[ "$existing_log" == "$LOG_TYPE" ]]; then
        log_message INFO "Latest log type for container $CONTAINER_NAME is already $LOG_TYPE, no new entry added."
        return 0
    fi

    if [[ "$LOG_TYPE" == "CRASHED" ]]; then
        local random_string=$(generate_random_string 12)
        log_fp="$LOGS_DIR/$CONTAINER_NAME-$random_string.log"

        LOG_LINES="$LOG_LINES" dump_container_logs "$CONTAINER_NAME" "$log_fp"
        log_message ALARM "Container $CONTAINER_NAME has crashed. Log file: $log_fp"
    fi

    log_message INFO "Inserting status log for container $CONTAINER_NAME ($LOG_TYPE)"
    CONTAINER_NAME="$CONTAINER_NAME" LOG_TYPE="$LOG_TYPE" LOG_FP="${log_fp-''}" insert_container_status_log
}

function _validate_and_insert_container_stats() {
    local required_args=(
        "CPU_PERC"
        "NAME"
        "MEM_USAGE"
        "MEM_PERC"
        "NET_IO"
        "BLOCK_IO"
    )
    check_required_args "${FUNCNAME[0]}" "${required_args[@]}"

    log_message INFO "Inserting stats for container $NAME."

    local name=$(echo $NAME | tr -d '" ')
    local cpu_perc=$(echo $CPU_PERC | tr -d '"% ')
    local mem_perc=$(echo $MEM_PERC | tr -d '"% ')

    local mem_usage_str=$(echo $MEM_USAGE | awk -F' / ' '{print $1}' | tr -d '" ')
    local mem_capacity_str=$(echo $MEM_USAGE | awk -F' / ' '{print $2}' | tr -d '" ')
    local mem_usage_bytes=$(convert_to_bytes $mem_usage_str)
    local mem_capacity_bytes=$(convert_to_bytes $mem_capacity_str)

    local net_input=$(echo $NET_IO | awk -F' / ' '{print $1}' | tr -d '" ')
    local net_output=$(echo $NET_IO | awk -F' / ' '{print $2}' | tr -d '" ')
    local net_input_bytes=$(convert_to_bytes $net_input)
    local net_output_bytes=$(convert_to_bytes $net_output)

    local block_input=$(echo $BLOCK_IO | awk -F' / ' '{print $1}' | tr -d '" ')
    local block_output=$(echo $BLOCK_IO | awk -F' / ' '{print $2}' | tr -d '" ')
    local block_input_bytes=$(convert_to_bytes $block_input)
    local block_output_bytes=$(convert_to_bytes $block_output)

    CONTAINER_NAME="$name" \
        CPU_PERC="$cpu_perc" \
        MEM_USAGE="$mem_usage_bytes" \
        MEM_PERC="$mem_perc" \
        MEM_CAPACITY="$mem_capacity_bytes" \
        NET_INPUT="$net_input_bytes" \
        NET_OUTPUT="$net_output_bytes" \
        BLOCK_INPUT="$block_input_bytes" \
        BLOCK_OUTPUT="$block_output_bytes" \
        insert_container_stats

}

function _dump_stats_to_db() {
    docker_stats=$(get_container_stats "${CONTAINER_NAMES[@]}")
    echo "$docker_stats" |
        jq -r '. | [.Name, .CPUPerc, .MemUsage, .MemPerc, .NetIO, .BlockIO] | @csv' |
        while IFS=, read -r NAME CPU_PERC MEM_USAGE MEM_PERC NET_IO BLOCK_IO; do
            _validate_and_insert_container_stats
        done
}

function _dump_status_logs_to_db() {
    for CONTAINER_NAME in $CONTAINER_NAMES; do
        local status_str=$(get_container_status $CONTAINER_NAME | tr -d -c 0-9)
        local status=$(($status_str))

        log_message DEBUG "Container $CONTAINER_NAME status: $status"

        if [ $status -eq 200 ]; then
            LOG_TYPE=HEALTHY _validate_and_insert_container_status_log
        elif [ $status -eq 404 ]; then
            LOG_TYPE=NOT_FOUND _validate_and_insert_container_status_log
        elif [ $status -eq 500 ]; then
            LOG_TYPE=CRASHED _validate_and_insert_container_status_log
        fi
    done
}

function continously_dump_stats() {
    log_message "INFO" "Starting continous dump of container stats."
    while true; do
        log_message "DEBUG" "Dumping container stats to database."
        _dump_stats_to_db
        log_message "DEBUG" "Dumping stats to database. Sleeping for $WAIT_TIME seconds."
        sleep $WAIT_TIME
    done
}

function continously_dump_status_logs() {
    log_message "INFO" "Starting continous dump of container status logs."
    while true; do
        log_message "DEBUG" "Dumping container status logs to database."
        _dump_status_logs_to_db
        log_message "DEBUG" "Dumped status logs to database. Sleeping for $WAIT_TIME seconds."
        sleep $WAIT_TIME
    done
}

HELP_TEXT="
$SCRIPT_NAME - Docker container monitoring tool

Usage: $0 <command>

Options:
    help            Show this help message
    dump_stats      Continously dump container stats to database
    dump_status     Continously dump container status logs to database

Configuration:
    CONTAINER_NAMES List of container names to monitor. Default: All running containers
    WAIT_TIME       Time in seconds to wait between each dump. Default: 30
    LOG_LEVEL       Log level to use (INFO | DEBUG | WARN | ERROR). Default: INFO
    DIR_PATH        Directory path to store data. Default: $HOME/.purman
    LOG_LINES       Number of lines to store in logs. Default: 200
"

case $1 in
dump_stats)
    continously_dump_stats
    ;;
dump_status)
    continously_dump_status_logs
    ;;
help)
    echo "$HELP_TEXT"
    ;;
*)
    if [[ -z "$1" ]]; then
        echo "No command provided."
        echo "$HELP_TEXT"
        exit 1
    fi

    echo "Invalid command: $1"
    echo "$HELP_TEXT"
    ;;
esac
