#!/bin/bash

set -e

REQUIRED_ENV_VARS=(
  DB_PATH
  SCRIPT_DIR
)

for env_var in "${REQUIRED_ENV_VARS[@]}"; do
  if [[ -z "${!env_var}" ]]; then
    echo "Environment variable ${env_var} is not set."
    exit 1
  fi
done

# ./sql.sh requires these variables
export STATS_TABLE_NAME="container_stats"
export STATUS_LOGS_TABLE_NAME="container_status_logs"

# shellcheck source=helpers/sql.sh
source $SCRIPT_DIR/helpers/sql.sh
# shellcheck source=helpers/utils.sh
source $SCRIPT_DIR/helpers/utils.sh

# Create the database if it doesn't exist
function create_tables_if_not_exists() {
  log_message DEBUG "Creating table $STATS_TABLE_NAME if not exists."
  sqlite3 $DB_PATH "$CREATE_CONTAINER_STATS_TABLE_SQL"

  log_message DEBUG "Creating table $STATUS_LOGS_TABLE_NAME if not exists."
  sqlite3 $DB_PATH "$CREATE_CONTAINER_STATUS_LOGS_TABLE_SQL"
}

function _fetch_latest_dumped_id() {
  local table_name=$1
  sqlite3 $DB_PATH "$(printf "$SELECT_LATEST_DUMP_ID_SQL" $table_name)"
}

function _fetch_next_dump_id() {
  local table_name=$1
  local last_id=$2
  sqlite3 $DB_PATH "$(printf "$SELECT_NEXT_DUMP_ID_SQL" $table_name $last_id)"
}

function get_latest_dumped_stats_id() {
  _fetch_latest_dumped_id $STATS_TABLE_NAME
}

function get_next_dumped_stats_id() {
  local last_id=$1
  _fetch_next_dump_id $STATS_TABLE_NAME $last_id
}

function get_latest_dumped_status_logs_id() {
  _fetch_latest_dumped_id $STATUS_LOGS_TABLE_NAME
}

function get_next_dumped_status_logs_id() {
  local last_id=$1
  _fetch_next_dump_id $STATUS_LOGS_TABLE_NAME $last_id
}

function get_latest_container_stats() {
  local latest_processed_id=$(get_latest_dumped_stats_id)
  sqlite3 $DB_PATH "$(printf "$SELECT_CONTAINER_STATS_BY_ID_SQL" $latest_processed_id)"
}

function get_next_container_stats() {
  local last_processed_id=$1
  local next_id=$(get_next_dumped_stats_id $last_processed_id)
  sqlite3 $DB_PATH "$(printf "$SELECT_CONTAINER_STATS_BY_ID_SQL" $next_id)"
}

function get_latest_container_status_logs() {
  local latest_processed_id=$(get_latest_dumped_status_logs_id)
  sqlite3 $DB_PATH "$(printf "$SELECT_CONTAINER_STATS_BY_ID_SQL" $last_processed_id)"
}

function get_next_container_status_logs() {
  local last_processed_id=$1
  local next_id=$(get_next_dumped_status_logs_id $last_processed_id)
  sqlite3 $DB_PATH "$(printf "$SELECT_CONTAINER_STATUS_LOGS_BY_ID_SQL" $next_id)"
}

function get_latest_log_type_for_container() {
  local container_name=$1
  sqlite3 $DB_PATH "$(printf "$SELECT_LATEST_LOG_TYPE_FOR_CONTAINER_SQL" $container_name)"
}

function insert_container_status_log() {
  local required_args=(
    "CONTAINER_NAME"
    "LOG_TYPE"
    "LOG_FP"
  )
  check_required_args "${FUNCNAME[0]}" "${required_args[@]}"

  sqlite3 $DB_PATH \
    "$(printf "$INSERT_CONTAINER_STATUS_LOG_SQL" $CONTAINER_NAME $LOG_TYPE $LOG_FP)"
}

function insert_container_stats() {
  local required_args=(
    "CONTAINER_NAME"
    "CPU_PERC"
    "MEM_USAGE"
    "MEM_PERC"
    "MEM_CAPACITY"
    "NET_INPUT"
    "NET_OUTPUT"
    "BLOCK_INPUT"
    "BLOCK_OUTPUT"
  )
  check_required_args "${FUNCNAME[0]}" "${required_args[@]}"

  sqlite3 $DB_PATH \
    "$(
      printf "$INSERT_CONTAINER_STATS_SQL" $CONTAINER_NAME $CPU_PERC \
        $MEM_USAGE $MEM_PERC $MEM_CAPACITY $NET_INPUT $NET_OUTPUT \
        $BLOCK_INPUT $BLOCK_OUTPUT
    )"

}
