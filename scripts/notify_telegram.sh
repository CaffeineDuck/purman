#!/bin/bash

WAIT_TIME=${WAIT_TIME:-15}
DIR_PATH=${DIR_PATH:-"$HOME/.purman"}
CONTAINER_NAMES=${CONTAINER_NAMES:-$(docker ps --format '{{.Names}}')}

DB_PATH="$DIR_PATH/docker_stats.db"
LOGS_DIR="$DIR_PATH/logs"
STATS_TABLE_NAME="container_stats"
STATUS_LOGS_TABLE_NAME="container_status_logs"
LATEST_PROCESSED_ID_FILE="$DIR_PATH/latest_telegram_processed_id"

REQUIRED_ENV_VARS=(
  TELEGRAM_BOT_TOKEN
  TELEGRAM_CHANNEL_ID
)

for env_var in "${REQUIRED_ENV_VARS[@]}"; do
  if [[ -z "${!env_var}" ]]; then
    echo "Environment variable ${env_var} is not set."
    exit 1
  fi
done

_get_latest_processed_id() {
  if [[ -f "$LATEST_PROCESSED_ID_FILE" ]]; then
    cat "$LATEST_PROCESSED_ID_FILE"
  else
    echo "0"
  fi
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

_truncate_message() {
  local message=$1
  local max_length=4096
  if [[ ${#message} -gt $max_length ]]; then
    message="${message:0:$max_length}"
  fi
  echo "$message"
}

_send_telegram_message() {
  local message=$1
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHANNEL_ID" \
    -d text="$message" \
    -d parse_mode="Markdown"
}

_process_new_status_logs() {
  local new_logs=$(_get_new_status_logs)

  while IFS='|' read -r id container_name log_type log_fp timestamp; do
    if [[ -z "$id" ]]; then
      continue
    fi

    if [[ "$log_type" == "CRASHED" ]]; then
      local log_content=$(head -n 30 "$log_fp")
      message="*CRITICAL*: \`$container_name\` has crashed. \`$log_fp\` \`\`\`$log_content\`\`\`"
      message=$(_truncate_message "$message")
    elif [[ "$log_type" == "NOT_FOUND" ]]; then
      message="_UNKNOWN_: \`$container_name\` does not exist."
    elif [[ "$log_type" == "HEALTHY" ]]; then
      message="_INFO_: \`$container_name\` is running."
    else
      message="_UNKNOWN_: \`$container_name\` has an unknown status: \`$log_type\`."
    fi

    _send_telegram_message "$message"
    _update_latest_processed_id "$id"
  done <<<"$new_logs"
}

_check_all_container_status() {
  for container_name in $CONTAINER_NAMES; do
    local status_resp=$(_get_container_status_logs $container_name)

    echo "STATUS_RESP $status_resp"

    _send_telegram_message "$status_resp"
  done
}

function watch_status() {
  while true; do
    _process_new_status_logs
    sleep $WAIT_TIME
  done
}

HELP_TEXT="
To be run when purman is running or has ran previously.

Usage: $0 <command>

Commands:
  watch_status                Watch the status of all containers and post to telegram.

Configuration:
  TELEGRAM_BOT_TOKEN          Telegram bot token.
  TELEGRAM_CHANNEL_ID         Telegram channel ID.
  DIR_PATH                    Directory path where purman is installed. Default: $HOME/.purman
  CONTAINER_NAMES             List of container names to check. Default: All running containers.
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
