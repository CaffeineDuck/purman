#!/bin/bash

WAIT_TIME=${WAIT_TIME:-15}
DIR_PATH=${DIR_PATH:-"$HOME/.purman"}

DB_PATH="$DIR_PATH/data/docker_stats.db"
STATUS_LOGS_TABLE_NAME="container_status_logs"
LATEST_PROCESSED_ID_FILE="$DIR_PATH/latest_monitor_processed_id"

_get_latest_dumped_id() {
  sqlite3 $DB_PATH "SELECT id from $STATUS_LOGS_TABLE_NAME ORDER BY id DESC LIMIT 1"
}

_get_latest_processed_id() {
  local latest_id=0
  if [[ -f "$LATEST_PROCESSED_ID_FILE" ]]; then
    latest_id=$(cat "$LATEST_PROCESSED_ID_FILE")
  fi

  if [[ ! -z "$latest_id" ]]; then
    echo $latest_id
    return 0
  fi

  local latest_id="$(_get_latest_dumped_id)"
  echo "$latest_id" >"$LATEST_PROCESSED_ID_FILE"
  echo "$latest_id"
}

_update_latest_processed_id() {
  local latest_id=$1
  echo "$latest_id" >"$LATEST_PROCESSED_ID_FILE"
}

_get_new_status_logs() {
  local last_processed_id=$(_get_latest_processed_id)
  sqlite3 $DB_PATH \
    "SELECT id, container_name, log_type, log_fp, timestamp 
      FROM $STATUS_LOGS_TABLE_NAME 
      WHERE id > $last_processed_id 
      ORDER BY id ASC;
    "
}

_restart_crashed_containers() {
  local new_logs=$(_get_new_status_logs)

  while IFS='|' read -r id container_name log_type log_fp timestamp; do
    if [[ -z "$id" ]]; then
      continue
    fi

    if [[ "$log_type" == "CRASHED" ]]; then
      echo "$container_name has crashed. Restarting..."
      docker restart "$container_name" >/dev/null
      echo "$container_name has been restarted."
    fi

    _update_latest_processed_id "$id"
  done <<<"$new_logs"
}

function watch_status() {
  while true; do
    _restart_crashed_containers
    sleep $WAIT_TIME
  done
}

HELP_TEXT="
Usage: $0 <command>

Commands:
  watch_status                Watch the status of all containers and restart if crashed.

Configuration:
  DIR_PATH                    Directory path where purman is installed. Default: $HOME/.purman
  WAIT_TIME                   Time in seconds to wait between checks. Default: 15 seconds.
"

case $1 in
watch_status)
  watch_status
  ;;
help)
  echo "$HELP_TEXT"
  ;;
*)
  echo "Invalid command: $1"
  echo "$HELP_TEXT"
  ;;
esac
