#!/bin/bash

WAIT_TIME=${WAIT_TIME:-15}
DIR_PATH=${DIR_PATH:-"$HOME/.purman"}
CONTAINER_NAMES=${CONTAINER_NAMES:-$(docker ps --format '{{.Names}}')}

DB_PATH="$DIR_PATH/data/docker_stats.db"
LOGS_DIR="$DIR_PATH/logs"
STATS_TABLE_NAME="container_stats"
STATUS_LOGS_TABLE_NAME="container_status_logs"
LATEST_PROCESSED_STATUS_ID_FILE="$DIR_PATH/latest_telegram_status_processed_id"
LATEST_PROCESSED_STATS_ID_FILE="$DIR_PATH/latest_telegram_stats_processed_id"

STATUS_MESSAGE_CRITICAL="
*CRITICAL*: \`%s\` has crashed.
*Log File*: \`%s\`
_Logs_:
\`\`\`
%s
\`\`\`
"
STATUS_MESSAGE_NOT_FOUND="_UNKNOWN_: \`%s\` does not exist."
STATUS_MESSAGE_HEALTHY="_INFO_: \`%s\` is running."
STATUS_MESSAGE_UNKNOWN="_UNKNOWN_: \`%s\` has an unknown status: \`%s\`."

STATS_MESSAGE="
*STATS*: \`%s\`
*CPU*: %s%%
*Memory*: %s%%
*Memory Usage*: %s / %s
*Network Input*: %s
*Network Output*: %s
*Block Input*: %s
*Block Output*: %s
"

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

_get_latest_dumped_id() {
  local table_name=$1
  sqlite3 $DB_PATH "SELECT id from $table_name ORDER BY id DESC LIMIT 1"
}

_get_latest_processed_id() {
  local latest_id_file=$1
  if [[ -f "$latest_id_file" ]]; then
    local id=$(cat "$latest_id_file")
    echo "$id"
    return 0
  fi

  if [[ "$latest_id_file" == "$LATEST_PROCESSED_STATUS_ID_FILE" ]]; then
    local latest_id="$(_get_latest_dumped_id $STATUS_LOGS_TABLE_NAME)"
  else
    local latest_id="$(_get_latest_dumped_id $STATS_TABLE_NAME)"
  fi

  echo "$latest_id" >"$latest_id_file"
  echo "$latest_id"
}

_update_latest_processed_id() {
  local latest_id=$1
  local latest_id_file=$2
  echo "$latest_id" >"$latest_id_file"
}

_get_new_status_logs() {
  local latest_id=$(_get_latest_processed_id "$LATEST_PROCESSED_STATUS_ID_FILE")

  sqlite3 $DB_PATH "SELECT id, container_name, log_type, log_fp, timestamp 
    FROM $STATUS_LOGS_TABLE_NAME 
    WHERE id > $latest_id
    ORDER BY id ASC;"
}

_get_new_stats() {
  local latest_id=$(_get_latest_processed_id "$LATEST_PROCESSED_STATS_ID_FILE")

  sqlite3 $DB_PATH "SELECT id, container_name, cpu_perc, mem_perc, mem_usage, mem_capacity, net_input, net_output, block_input, block_output
    FROM $STATS_TABLE_NAME 
    WHERE id > $latest_id
    ORDER BY id ASC;"
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
      message=$(printf "$STATUS_MESSAGE_CRITICAL" "$container_name" "$log_fp" "$log_content")
      message=$(_truncate_message "$message")
    elif [[ "$log_type" == "NOT_FOUND" ]]; then
      message=$(printf "$STATUS_MESSAGE_NOT_FOUND" "$container_name")
    elif [[ "$log_type" == "HEALTHY" ]]; then
      message=$(printf "$STATUS_MESSAGE_HEALTHY" "$container_name")
    else
      message=$(printf "$STATUS_MESSAGE_UNKNOWN" "$container_name" "$log_type")
    fi

    _send_telegram_message "$message"
    _update_latest_processed_id "$id" "$LATEST_PROCESSED_STATUS_ID_FILE"
  done <<<"$new_logs"
}

_process_new_stats() {
  local new_stats=$(_get_new_stats)

  while IFS='|' read -r id container_name cpu_perc mem_perc mem_usage mem_capacity net_input net_output block_input block_output; do
    if [[ -z "$id" ]]; then
      continue
    fi

    latest_processed_id=$(_get_latest_processed_id "$LATEST_PROCESSED_STATS_ID_FILE")

    mem_usage=$(numfmt --to=iec-i --suffix=B "$mem_usage")
    mem_capacity=$(numfmt --to=iec-i --suffix=B "$mem_capacity")

    net_input=$(numfmt --to=iec-i --suffix=B "$net_input")
    net_output=$(numfmt --to=iec-i --suffix=B "$net_output")

    block_input=$(numfmt --to=iec-i --suffix=B "$block_input")
    block_output=$(numfmt --to=iec-i --suffix=B "$block_output")

    message=$(
      printf "$STATS_MESSAGE" "$container_name $latest_processed_id" \
        "$cpu_perc" "$mem_perc" "$mem_usage" "$mem_capacity" \
        "$net_input" "$net_output" "$block_input" "$block_output"
    )
    message=$(_truncate_message "$message")

    _send_telegram_message "$message"
    _update_latest_processed_id "$id" "$LATEST_PROCESSED_STATS_ID_FILE"
  done <<<"$new_stats"
}
function watch_status() {
  while true; do
    _process_new_status_logs
    sleep $WAIT_TIME
  done
}

function watch_stats() {
  while true; do
    _process_new_stats
    sleep $WAIT_TIME
  done
}

HELP_TEXT="
To be run when purman is running or has ran previously.

Usage: $0 <command>

Commands:
  watch_status                Watch the container status of all containers and post to telegram.
  watch_stats                 Watch the stats of all containers and post to telegram.

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
watch_stats)
  watch_stats
  ;;
help)
  echo "$HELP_TEXT"
  ;;
*)
  echo "Invalid command: $1"
  echo "$HELP_TEXT"
  ;;
esac
