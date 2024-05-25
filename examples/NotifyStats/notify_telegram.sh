#!/bin/bash
set -e

# Env var required for purman-db
export SCRIPT_DIR="$HOME/.purman/bin"

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

WAIT_TIME=15
CONTAINER_NAMES=$(docker ps --format '{{.Names}}')
LATEST_PROCESSED_IDS=$(mktemp -d)

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

# Map to store processed ids
for container_name in $CONTAINER_NAMES; do
  _insert_to_map "$container_name" 0
done

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

send_stats_message() {
  local id=$1 container_name=$2 cpu_perc=$3 \
    mem_perc=$4 mem_usage=$5 mem_capacity=$6 \
    net_input=$7 net_output=$8 block_input=$9 \
    block_output=${10}

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
}

while true; do
  for container_name in $CONTAINER_NAMES; do
    log_message DEBUG "Checking status_logs of container $container_name"
    latest_stats=$(get_latest_container_stats_by_name "$container_name")
    if [[ -z "$latest_stats" ]]; then
      echo "LATEST_STATUS $latest_stats"
      log_message WARN "No status logs found for container $container_name"
      continue
    fi

    IFS='|' read -r id container_name cpu_perc mem_perc \
      mem_usage mem_capacity net_input net_output \
      block_input block_output timestamp <<<"$latest_stats"
    latest_processed_id=$(_get_from_map "$container_name")
    if [[ $id -le $latest_processed_id ]]; then
      log_message DEBUG "Latest stats for $container_name already processed. Skipping."
      continue
    fi
    _insert_to_map "$container_name" $id

    log_message INFO "Sending stats message for $container_name"
    log_message DEBUG "Id: $id ContainerName: $container_name CPU: $cpu_perc Mem: $mem_perc MemUsage: $mem_usage"

    send_stats_message "$id" "$container_name" "$cpu_perc" "$mem_perc" \
      "$mem_usage" "$mem_capacity" "$net_input" "$net_output" \
      "$block_input" "$block_output"
  done

  sleep $WAIT_TIME
done
