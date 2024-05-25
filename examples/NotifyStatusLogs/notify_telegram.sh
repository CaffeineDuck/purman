#!/bin/bash

set -e

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

# Env var required for purman-db
export SCRIPT_DIR="$HOME/.purman/bin"

# Wait time in seconds between each poll
WAIT_TIME=15
# The containers to watch and restart if they crash
CONTAINER_NAMES=$(docker ps --format '{{.Names}}')
# map to store latest processed ids for each container
# for compatibility with bash 3 (default on macOS)
LATEST_PROCESSED_IDS=$(mktemp -d)

# Message formats

STATUS_MESSAGE_NOT_FOUND="_UNKNOWN_: \`%s\` does not exist."
STATUS_MESSAGE_HEALTHY="_INFO_: \`%s\` is running."
STATUS_MESSAGE_UNKNOWN="_UNKNOWN_: \`%s\` has an unknown status: \`%s\`."
STATUS_MESSAGE_CRITICAL="
*CRITICAL*: \`%s\` has crashed.
*Log File*: \`%s\`
_Logs_:
\`\`\`
%s
\`\`\`
"
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

# shellcheck source=helpers/db.sh
source $(which purman-db)

function _insert_to_map() {
  local key=$1
  local value=$2
  echo "$value" >"$LATEST_PROCESSED_IDS/$key"
}

function _get_from_map() {
  local key=$1
  cat "$LATEST_PROCESSED_IDS/$key"
}

_truncate_message() {
  local message=$1
  local max_length=4096
  if [[ ${#message} -gt $max_length ]]; then
    message="${message:0:$max_length}"
  fi
  echo "$message"
}

function _send_telegram_message() {
  local message=$1
  local telegram_bot_token=$TELEGRAM_BOT_TOKEN
  local telegram_channel_id=$TELEGRAM_CHANNEL_ID

  log_message DEBUG "Sending message to Telegram channel $telegram_channel_id"
  log_message DEBUG "Message: $message"

  curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" \
    -d "chat_id=$telegram_channel_id" \
    -d "text=$message" \
    -d "parse_mode=Markdown" >/dev/null
}

function send_status_message() {
  local container_name=$1 log_type=$2 log_fp=$3 log_content=$4

  if [[ "$log_type" == CRASHED ]]; then
    local log_content=$(head -n 30 "$log_fp")
    message=$(printf "$STATUS_MESSAGE_CRITICAL" "$container_name" "$log_fp" "$log_content")
  elif [[ "$log_type" == NOT_FOUND ]]; then
    message=$(printf "$STATUS_MESSAGE_NOT_FOUND" "$container_name")
  elif [[ "$log_type" == HEALTHY ]]; then
    message=$(printf "$STATUS_MESSAGE_HEALTHY" "$container_name")
  else
    message=$(printf "$STATUS_MESSAGE_UNKNOWN" "$container_name" "$log_type")
  fi

  message=$(_truncate_message "$message")
  _send_telegram_message "$message"
}

for container_name in $CONTAINER_NAMES; do
  _insert_to_map "$container_name" 0
done

while true; do
  for container_name in $CONTAINER_NAMES; do
    log_message DEBUG "Checking status_logs of container $container_name"
    latest_status=$(get_latest_container_status_logs_by_name "$container_name")
    if [[ -z "$latest_status" ]]; then
      echo "LATEST_STATUS $latest_status"
      log_message WARN "No status logs found for container $container_name"
      continue
    fi

    IFS='|' read -r id container_name log_type log_fp timestamp <<<"$latest_status"
    latest_processed_id=$(_get_from_map "$container_name")
    if [[ $id -le $latest_processed_id ]]; then
      log_message DEBUG "Latest log for $container_name already processed. Skipping."
      continue
    fi
    _insert_to_map "$container_name" $id

    log_message INFO "Sending message for container $container_name with status: $log_type"
    send_status_message "$container_name" "$log_type" "$log_fp" "$log_content"
  done

  sleep $WAIT_TIME
done
